import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "."

// Daemon (one instance, unlike the bar widgets): applies the "System events" rules from the settings.
// Rule per event: pluginData.event_<e>_target ("" | "grouped_light:<id>" | "light:<id>") and
// pluginData.event_<e>_action ("on" | "off", default in defaultActions)
PluginComponent {
    id: root

    readonly property var defaultActions: ({
            login: "on", lock: "off", unlock: "on", logout: "off", sleep: "off", resume: "on", shutdown: "off", reboot: "off"
        })

    // shutdown marker: power off/reboot also end the graphical session, the logout hook must then stay quiet
    readonly property string shutdownMarker: "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hue-director-shutdown"

    function rule(e) {
        const target = pluginData?.["event_" + e + "_target"] ?? "";
        const sep = target.indexOf(":");
        if (sep < 0)
            return null;
        const kind = target.slice(0, sep);
        const id = target.slice(sep + 1);
        // ids come from the bridge; anything else is ignored (they also end up in the logout hook file)
        if ((kind !== "light" && kind !== "grouped_light") || !/^[0-9a-f-]+$/.test(id))
            return null;
        return { kind: kind, id: id, on: (pluginData?.["event_" + e + "_action"] ?? defaultActions[e]) === "on" };
    }

    // done() is always called, also when there is no rule, so sleep/shutdown can release the inhibitor
    function run(e, done) {
        const r = hueBridge.configured ? rule(e) : null;
        if (!r) {
            done?.();
            return;
        }
        hueBridge.put(r.kind, r.id, { on: { on: r.on } }, err => {
            if (err)
                console.warn("Hue Director: event", e, "failed:", err);
            done?.();
        });
    }

    HueBridge {
        id: hueBridge
        onConfigChanged: root.syncLogoutHook()
    }

    Component.onCompleted: {
        subscribeShutdown();
        checkLogin();
    }

    // --- Login: the daemon also starts on shell restarts, so only a session younger than 2 minutes counts
    function checkLogin() {
        Proc.runCommand("hueDirector.events.login", ["sh", "-c", "s=$(loginctl show-session \"$XDG_SESSION_ID\" -p TimestampMonotonic --value) || exit 1; u=$(cut -d' ' -f1 /proc/uptime); awk -v s=\"$s\" -v u=\"$u\" 'BEGIN{exit !(u - s/1e6 < 120)}'"], (stdout, exitCode) => {
            if (exitCode === 0)
                loginTimer.start();
        }, 0);
    }

    // The bridge config loads asynchronously right after startup
    Timer {
        id: loginTimer
        interval: 3000
        onTriggered: root.run("login")
    }

    // --- Lock / unlock
    Connections {
        target: SessionService
        function onSessionLocked() {
            root.run("lock");
        }
        function onSessionUnlocked() {
            root.run("unlock");
        }
        function onPreparingForSleepChanged() {
            if (SessionService.preparingForSleep) {
                root.run("sleep", () => inhibitor.released = true);
            } else {
                inhibitor.released = false;
                root.run("resume");
            }
        }
    }

    // --- Power off / reboot: logind PrepareForShutdownWithMetadata(true, {type}) tells them apart
    // (systemd >= 256). Older systemd only has PrepareForShutdown(bool): then every shutdown counts as power off.
    // (false) means the shutdown was cancelled
    property string shutdownSubscriptionId: ""
    property bool shutdownHasMetadata: false

    function subscribeShutdown() {
        if (shutdownSubscriptionId || !DMSService.capabilities.includes("dbus"))
            return;
        const subscribe = (member, onFail) => DMSService.dbusSubscribe("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", member, response => {
            const id = response.result?.subscriptionId ?? "";
            if (id) {
                shutdownSubscriptionId = id;
                shutdownHasMetadata = member === "PrepareForShutdownWithMetadata";
            } else {
                onFail(response.error);
            }
        });
        subscribe("PrepareForShutdownWithMetadata", () => subscribe("PrepareForShutdown", error => console.warn("Hue Director: cannot watch power off/reboot:", error)));
    }

    // "reboot" for reboot, kexec and soft-reboot; "shutdown" for poweroff, halt and when the type is unknown
    function shutdownEvent(body) {
        if (!shutdownHasMetadata)
            return "shutdown";
        // a{sv}: the variant may arrive unwrapped or as an object holding the value
        const t = body?.[1]?.type;
        const type = (t !== null && typeof t === "object") ? (t.value ?? t.Value ?? t.data ?? "") : (t ?? "");
        return ["reboot", "kexec", "soft-reboot"].includes(String(type)) ? "reboot" : "shutdown";
    }

    Connections {
        target: DMSService
        function onCapabilitiesChanged() {
            root.subscribeShutdown();
        }
        function onDbusSignalReceived(subscriptionId, data) {
            if (!subscriptionId || subscriptionId !== root.shutdownSubscriptionId)
                return;
            if (data?.body?.[0] === true) {
                Proc.runCommand("hueDirector.events.marker", ["sh", "-c", ": > \"" + root.shutdownMarker + "\""], () => {}, 0);
                root.run(root.shutdownEvent(data.body), () => inhibitor.released = true);
            } else {
                Proc.runCommand("hueDirector.events.marker", ["sh", "-c", "rm -f \"" + root.shutdownMarker + "\""], () => {}, 0);
                inhibitor.released = false;
            }
        }
    }

    Component.onDestruction: inhibitor.running = false

    // --- Delay inhibitor: logind waits for it (up to InhibitDelayMaxSec, 5 s by default) before sleep or
    // power off, so the PUT can reach the bridge. Released as soon as the rule has run
    Process {
        id: inhibitor

        property bool released: false
        readonly property string what: [root.rule("sleep") ? "sleep" : "", root.rule("shutdown") || root.rule("reboot") ? "shutdown" : ""].filter(w => w).join(":")

        running: what !== "" && hueBridge.configured && !released
        command: ["systemd-inhibit", "--what=" + what, "--mode=delay", "--who=Hue Director", "--why=Set the lights before sleep or power off", "sleep", "infinity"]
    }

    // --- Logout: the shell dies with the session, so a transient user unit bound to graphical-session.target
    // sends the PUT from its ExecStop. The hook reads logout.action, so rule changes never restart the unit
    readonly property string hookScript: "#!/bin/sh\n"
        + "# Hue Director logout action, run by hue-director-session.service (ExecStop) when the graphical session ends\n"
        + "d=$(dirname \"$0\")\n"
        + "[ -e \"" + shutdownMarker + "\" ] && exit 0\n"
        + "[ -f \"$d/logout.action\" ] || exit 0\n"
        + "{ read -r p; read -r b; } < \"$d/logout.action\"\n"
        + "exec curl -K \"$d/bridge.conf\" -m 4 -X PUT -H 'Content-Type: application/json' --expand-url \"https://{{ip}}/clip/v2/$p\" --data \"$b\"\n"

    // $1 state dir, $2 hook script, $3 action path ("" removes the action), $4 action body
    readonly property string syncScript: "umask 077; mkdir -p \"$1\" || exit 1\n"
        + "if [ -z \"$3\" ]; then rm -f \"$1/logout.action\"; exit 0; fi\n"
        + "printf '%s' \"$2\" > \"$1/logout-hook.sh\" && printf '%s\\n%s\\n' \"$3\" \"$4\" > \"$1/logout.action\" || exit 1\n"
        + "systemctl --user is-active --quiet graphical-session.target || exit 3\n"
        + "systemctl --user is-active --quiet hue-director-session && exit 0\n"
        + "exec systemd-run --user --quiet --unit=hue-director-session --description='Hue Director logout action' -p PartOf=graphical-session.target -p After=graphical-session.target -p Type=oneshot -p RemainAfterExit=yes -p \"ExecStop=/bin/sh '$1/logout-hook.sh'\" /bin/true\n"

    function syncLogoutHook() {
        const r = hueBridge.configured ? rule("logout") : null;
        Proc.runCommand("hueDirector.events.logout", ["sh", "-c", syncScript, "sh", hueBridge.stateDir, hookScript, r ? "resource/" + r.kind + "/" + r.id : "", r ? JSON.stringify({ on: { on: r.on } }) : ""], (stdout, exitCode) => {
            if (exitCode === 3)
                console.warn("Hue Director: no systemd graphical session, the logout rule can't run");
            else if (exitCode !== 0)
                console.warn("Hue Director: logout hook setup failed (exit", exitCode + ")");
        }, 500);
    }

    onPluginDataChanged: syncLogoutHook()
}
