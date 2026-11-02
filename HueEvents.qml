import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "."

// Daemon (one instance, unlike the bar widgets, one per bar). It owns the bridge state, the event stream,
// the polling and every command, shared with the widgets and the settings through
// PluginService.pluginDaemonInstances["hueDirector"]; it also runs the "System events" rules and the IPC.
// Rule per event: pluginData.event_<e>_target ("" | "grouped_light:<id>" | "light:<id>") and
// pluginData.event_<e>_action ("on" | "off", default in defaultActions)
PluginComponent {
    id: root

    // --- Bridge state, in the shape built by HueBridge.normalize()
    readonly property var bridge: hueBridge
    readonly property var pairing: pairingItem
    property var rooms: []
    property var lights: []
    // grouped_light of the whole home, for "all off"
    property string homeGroupedId: ""
    property string error: ""
    property bool loaded: false
    // False when there is no pairing or the bridge rejects the key
    property bool paired: true
    // The bridge answered with a different public key than at pairing (replaced bridge or another device)
    property bool certChanged: false
    readonly property bool needsPairing: !paired || certChanged
    // Unreachable lights keep their last reported state on the bridge: they never count as on
    readonly property int lightsOn: lights.filter(l => l.Reachable && l.HueData?.on?.on).length
    // Last error written to the log, so a bridge that stays offline doesn't log on every poll
    property string loggedError: ""

    // Shared by fetch and put. Returns true when err was handled as an error
    function handleError(err) {
        if (!err)
            return false;
        if (err !== loggedError)
            console.warn("Hue Director:", err);
        loggedError = err;
        if (err === "unpaired") {
            paired = false;
            error = "";
        } else if (err === "unreachable") {
            error = I18n.trFor("hueDirector", "Hue Bridge not reachable");
        } else if (err === "certchanged") {
            certChanged = true;
            error = I18n.trFor("hueDirector", "The bridge identity changed: pair again");
        } else {
            error = err;
        }
        return true;
    }

    function refresh() {
        if (!hueBridge.configured) {
            // Forgotten or never paired: drop the old bridge's rooms and lights (settings targets, IPC)
            paired = false;
            rooms = [];
            lights = [];
            homeGroupedId = "";
            loaded = false;
            return;
        }
        hueBridge.fetchAll((result, err) => {
            if (handleError(err))
                return;
            // Bridge order is not stable (scenes move after activation): sort everything by name
            const byName = (a, b) => (a.Name ?? "").localeCompare(b.Name ?? "");
            result.rooms.forEach(r => r.Scenes.sort(byName));
            rooms = result.rooms.sort(byName);
            lights = result.lights.sort(byName);
            homeGroupedId = result.homeGroupedId;
            error = "";
            loggedError = "";
            loaded = true;
            paired = true;
            certChanged = false;
            startEvents();
        });
    }

    // kind: "light" | "grouped_light" | "scene" | "smart_scene", body: Hue API v2 PUT body.
    // With the event stream up, the bridge's own event refreshes the state; otherwise refresh here
    function setResource(kind, id, body) {
        hueBridge.put(kind, id, body, err => {
            if (!handleError(err) && !eventsActive)
                refresh();
        });
    }

    // Rooms are controlled through their grouped_light service
    function setRoom(room, body) {
        const groupedId = room?.GroupedLight?.HueData?.id;
        if (groupedId)
            setResource("grouped_light", groupedId, body);
    }

    function setColor(lightId, c) {
        const xy = hueBridge.rgbToXy(c);
        if (xy)
            setResource("light", lightId, { on: { on: true }, color: { xy: xy } });
    }

    // Favorite light, room or whole home (Settings → Favorite light): bar right click and IPC toggle
    function toggleFavorite() {
        const t = hueBridge.parseTarget(pluginData?.favoriteLight);
        if (!t)
            return "no favorite light set";
        setResource(t.kind, t.id, { on: { on: !hueBridge.targetIsOn(t, root) } });
        return "ok";
    }

    // Timed effects (sunrise/sunset) need a duration: 30 minutes, like the Hue app default.
    // "no_effect" clears both kinds, since only one of them can be running
    function setEffect(light, value) {
        const timed = light?.HueData?.timed_effects?.effect_values ?? [];
        let body;
        if (value === "no_effect")
            body = { effects: { effect: "no_effect" } };
        else if (timed.includes(value))
            body = { on: { on: true }, timed_effects: { effect: value, duration: 1800000 } };
        else
            body = { on: { on: true }, effects: { effect: value } };
        if (value === "no_effect" && (light?.HueData?.timed_effects?.status ?? "no_effect") !== "no_effect")
            body.timed_effects = { effect: "no_effect" };
        setResource("light", light.Id, body);
    }

    // Soft blink: two brightness pulses in 2.5 s (4 steps of 625 ms, each a 600 ms fade), then back to the
    // light's previous state. Hue "breathe" can't be stopped and runs far longer on some lights.
    // Steps go straight to the bridge: the event stream updates the UI, no refresh per step
    readonly property int identifyStepMs: 625
    // light id -> remaining PUT bodies
    property var identifyQueue: ({})

    function identify(light) {
        const hd = light?.HueData;
        if (!hd || identifyQueue[light.Id])
            return;
        const fade = { duration: identifyStepMs - 25 };
        // Reported also while off: restored so the next switch-on keeps the user's brightness
        const bri = hd.dimming?.brightness ?? 100;
        let steps;
        if (hd.on?.on) {
            // Dim a bright light, brighten a dim one: the pulse must be visible either way
            const pulse = bri > 40 ? Math.max(1, Math.round(bri * 0.15)) : 100;
            steps = [pulse, bri, pulse, bri].map(b => ({ dimming: { brightness: b }, dynamics: fade }));
        } else {
            steps = [{ on: { on: true }, dimming: { brightness: 100 }, dynamics: fade }, { dimming: { brightness: 5 }, dynamics: fade }, { dimming: { brightness: bri }, dynamics: fade }, { on: { on: false }, dynamics: fade }];
        }
        identifyQueue = Object.assign({}, identifyQueue, { [light.Id]: steps });
        identifyStep();
        identifyTimer.start();
    }

    function identifyStep() {
        const next = {};
        for (const id in identifyQueue) {
            const steps = identifyQueue[id];
            hueBridge.put("light", id, steps[0], err => handleError(err));
            if (steps.length > 1)
                next[id] = steps.slice(1);
        }
        identifyQueue = next;
        if (Object.keys(next).length === 0)
            identifyTimer.stop();
    }

    Timer {
        id: identifyTimer
        interval: root.identifyStepMs
        repeat: true
        onTriggered: root.identifyStep()
    }

    // --- Live updates from the bridge event stream (SSE); polling is the safety net
    // Consecutive event stream failures; reset whenever a line arrives
    property int eventsRestarts: 0
    readonly property int maxEventsRestarts: 5
    readonly property bool eventsActive: eventsProcess.running && eventsRestarts <= maxEventsRestarts
    // Set while the stream is stopped on purpose (new pairing), so the exit isn't counted as a failure
    property bool eventsStopping: false

    // Called after every successful fetch: the bridge is reachable, so a stream that gave up
    // (eventsRestarts > max, e.g. laptop away from home) gets a fresh start
    function startEvents() {
        if (eventsProcess.running || eventsRestartTimer.running)
            return;
        if (eventsRestarts > maxEventsRestarts)
            eventsRestarts = 0;
        eventsProcess.running = true;
    }

    // Resource types shown by the UI; other events (sensors, ...) don't refresh
    readonly property var watchedTypes: ["light", "grouped_light", "scene", "smart_scene", "room", "zigbee_connectivity"]

    Process {
        id: eventsProcess
        command: ["curl", "-K", hueBridge.confPath, "-N", "-H", "Accept: text/event-stream", "--expand-url", "https://{{ip}}/eventstream/clip/v2"]
        onExited: (exitCode, exitStatus) => {
            // Stopped on purpose, or unpaired: refresh()/a new pairing starts it again
            if (root.eventsStopping || !root.paired) {
                root.eventsStopping = false;
                return;
            }
            if (++root.eventsRestarts > root.maxEventsRestarts) {
                console.warn("Hue Director: event stream keeps failing - falling back to polling");
                return;
            }
            eventsRestartTimer.restart();
        }
        stdout: SplitParser {
            // SSE frames: "id: ...", "data: [...]", and ": hi" keepalives.
            // Any line proves the stream works, keepalives included (quiet homes send no data for long);
            // the Proc debounce in HueBridge.fetchAll() collapses bursts into one request
            onRead: line => {
                if (!line.trim())
                    return;
                root.eventsRestarts = 0;
                if (!line.startsWith("data:"))
                    return;
                let relevant = true;
                try {
                    relevant = JSON.parse(line.slice(5)).some(ev => (ev.data ?? []).some(r => root.watchedTypes.includes(r.type)));
                } catch (e) {}
                if (relevant)
                    root.refresh();
            }
        }
    }

    Timer {
        id: eventsRestartTimer
        interval: 5000
        onTriggered: eventsProcess.running = true
    }

    Timer {
        interval: root.eventsActive ? 300000 : 30000
        running: hueBridge.configured
        repeat: true
        onTriggered: root.refresh()
    }

    readonly property var defaultActions: ({
            login: "on", lock: "off", unlock: "on", monitorOff: "off", monitorOn: "on", logout: "off", sleep: "off", resume: "on", shutdown: "off", reboot: "off"
        })

    // shutdown marker: power off/reboot also end the graphical session, the logout hook must then stay quiet
    readonly property string shutdownMarker: "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hue-director-shutdown"

    function rule(e) {
        const t = hueBridge.parseTarget(pluginData?.["event_" + e + "_target"]);
        if (!t)
            return null;
        return { kind: t.kind, id: t.id, on: (pluginData?.["event_" + e + "_action"] ?? defaultActions[e]) === "on" };
    }

    // done() is always called, also when there is no rule, so sleep/shutdown can release the inhibitor.
    // Those pass done and run without the debounce: logind waits only a few seconds.
    // retries: attempts left when the bridge is unreachable, 2 s apart (resume: the network comes back later)
    function run(e, done, retries) {
        const r = hueBridge.configured ? rule(e) : null;
        if (!r) {
            done?.();
            return;
        }
        console.info("Hue Director: event", e, "->", r.kind, r.id, r.on ? "on" : "off");
        hueBridge.put(r.kind, r.id, { on: { on: r.on } }, err => {
            if (err === "unreachable" && retries > 0) {
                retryLater(() => run(e, done, retries - 1));
                return;
            }
            if (err)
                console.warn("Hue Director: event", e, "failed:", err);
            else
                console.info("Hue Director: event", e, "done");
            done?.();
        }, !!done);
    }

    // One pending retry at a time is enough: events of the same kind replace each other
    property var retryFn: null

    function retryLater(fn) {
        retryFn = fn;
        retryTimer.restart();
    }

    Timer {
        id: retryTimer
        interval: 2000
        onTriggered: {
            const fn = root.retryFn;
            root.retryFn = null;
            fn?.();
        }
    }

    Pairing {
        id: pairingItem
        bridge: hueBridge
    }

    HueBridge {
        id: hueBridge
        transitionMs: parseInt(root.pluginData?.transitionMs ?? "-1")
        // Startup or new pairing: reconnect the event stream with the new key/bridge (refresh() restarts it)
        onConfigChanged: {
            root.eventsRestarts = 0;
            if (eventsProcess.running) {
                root.eventsStopping = true;
                eventsProcess.running = false;
            }
            root.refresh();
            root.syncLogoutHook();
        }
    }

    // --- Command line / keybindings: dms ipc call hueDirector <function> [arg]. Uses the live state,
    // so calls answer with the outcome ("ok" or what is wrong)

    // "all", a room name or a light name (case-insensitive); rooms win over lights with the same name
    function findTarget(name) {
        const n = (name ?? "").trim().toLowerCase();
        if (n === "all")
            return homeGroupedId ? { kind: "grouped_light", id: homeGroupedId } : null;
        const room = rooms.find(r => r.Name.toLowerCase() === n && r.GroupedLight);
        if (room)
            return { kind: "grouped_light", id: room.GroupedLight.HueData.id };
        const light = lights.find(l => l.Name.toLowerCase() === n);
        return light ? { kind: "light", id: light.Id } : null;
    }

    function ipcReady() {
        return !hueBridge.configured ? "not paired" : !loaded ? "not connected to the bridge yet" : "";
    }

    function setTarget(name, on) {
        const t = findTarget(name);
        if (!t)
            return "no room or light named " + name;
        setResource(t.kind, t.id, { on: { on: on } });
        return "ok";
    }

    IpcHandler {
        target: "hueDirector"

        // Toggles the favorite light, room or all lights (Settings → Favorite light)
        function toggle(): string {
            return root.ipcReady() || root.toggleFavorite();
        }

        function on(target: string): string {
            return root.ipcReady() || root.setTarget(target, true);
        }

        function off(target: string): string {
            return root.ipcReady() || root.setTarget(target, false);
        }

        // "Scene" or "Room/Scene" when the name exists in several rooms (case-insensitive)
        function scene(name: string): string {
            const notReady = root.ipcReady();
            if (notReady)
                return notReady;
            const parts = name.split("/");
            const sceneName = parts.pop().trim().toLowerCase();
            const roomName = parts.join("/").trim().toLowerCase();
            const room = roomName ? root.rooms.find(r => r.Name.toLowerCase() === roomName) : null;
            if (roomName && !room)
                return "no room named " + roomName;
            // no Array.flatMap in the shell's JS engine
            const scenes = [].concat(...(room ? [room] : root.rooms).map(r => r.Scenes));
            const sc = scenes.find(s => s.Name.toLowerCase() === sceneName);
            if (!sc)
                return "no scene named " + name;
            root.setResource("scene", sc.Id, { recall: { action: "active" } });
            return "ok";
        }
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

    // --- Monitors off / on: DPMS driven by the shell idle settings (IdleService.requestMonitorOff/On)
    Connections {
        target: IdleService
        function onMonitorsOffChanged() {
            root.run(IdleService.monitorsOff ? "monitorOff" : "monitorOn");
        }
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
        function onSleepRequestedChanged() {
            if (!SessionService.sleepRequested || root.earlySleep)
                return;
            root.earlySleep = true;
            root.earlySleepDone = false;
            earlySleepTimeout.restart();
            root.run("sleep", () => root.sleepRuleDone());
        }
    }

    // --- Suspend / resume. NetworkManager takes the network down as soon as logind announces the sleep
    // (PrepareForSleep), so the rule runs earlier when the shell starts the suspend (power menu, idle):
    // SessionService.sleepRequested turns true before logind is called. PrepareForSleep then only waits
    // for that request and releases the inhibitor. Suspends the shell doesn't start (lid, terminal) still
    // run on PrepareForSleep, racing the network
    property bool earlySleep: false
    property bool earlySleepDone: false
    property bool sleepPending: false

    function sleepRuleDone() {
        earlySleepDone = true;
        if (sleepPending)
            inhibitor.released = true;
    }

    function onPrepareForSleep(sleeping) {
        if (sleeping) {
            if (earlySleep && earlySleepDone) {
                inhibitor.released = true;
            } else if (earlySleep) {
                sleepPending = true;
            } else {
                root.run("sleep", () => inhibitor.released = true);
            }
        } else {
            earlySleep = false;
            sleepPending = false;
            earlySleepTimeout.stop();
            inhibitor.released = false;
            // 15 attempts, 2 s apart: the network may need a while to come back after resume
            root.run("resume", null, 15);
        }
    }

    // A sleep request that never reaches logind (refused, cancelled) must not swallow the next one
    Timer {
        id: earlySleepTimeout
        interval: 30000
        onTriggered: root.earlySleep = false
    }

    // --- Power off / reboot: logind PrepareForShutdownWithMetadata(true, {type}) tells them apart
    // (systemd >= 256). Older systemd only has PrepareForShutdown(bool): then every shutdown counts as power off.
    // (false) means the shutdown was cancelled
    property string shutdownSubscriptionId: ""
    property bool shutdownHasMetadata: false
    property string sleepSubscriptionId: ""

    function subscribeShutdown() {
        if (!DMSService.capabilities.includes("dbus"))
            return;
        if (!sleepSubscriptionId)
            DMSService.dbusSubscribe("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep", response => {
                sleepSubscriptionId = response.result?.subscriptionId ?? "";
                if (!sleepSubscriptionId)
                    console.warn("Hue Director: cannot watch suspend:", response.error);
            });
        if (shutdownSubscriptionId)
            return;
        const subscribe = (member, onFail) => DMSService.dbusSubscribe("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", member, response => {
            const id = response.result?.subscriptionId ?? "";
            if (id) {
                shutdownSubscriptionId = id;
                shutdownHasMetadata = member === "PrepareForShutdownWithMetadata";
                console.info("Hue Director: watching power off/reboot through", member);
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
            if (subscriptionId && subscriptionId === root.sleepSubscriptionId) {
                root.onPrepareForSleep(data?.body?.[0] === true);
                return;
            }
            if (!subscriptionId || subscriptionId !== root.shutdownSubscriptionId)
                return;
            console.info("Hue Director: logind shutdown signal", JSON.stringify(data?.body ?? []));
            if (data?.body?.[0] === true) {
                Proc.runCommand("hueDirector.events.marker", ["sh", "-c", ": > \"" + root.shutdownMarker + "\""], () => {}, 0);
                root.run(root.shutdownEvent(data.body), () => inhibitor.released = true);
            } else {
                Proc.runCommand("hueDirector.events.marker", ["sh", "-c", "rm -f \"" + root.shutdownMarker + "\""], () => {}, 0);
                inhibitor.released = false;
            }
        }
    }

    // Also runs on shell exit and logout, when the logout hook must stay. Only a disabled or uninstalled
    // plugin (enabled turned false before the unload, or plugin.json gone) removes it; bridge.conf is kept
    Component.onDestruction: {
        inhibitor.running = false;
        Proc.runCommand("hueDirector.events.unload", ["sh", "-c", "[ \"$3\" = true ] && [ -f \"$2\" ] && exit 0\n"
            + "rm -f \"$1/logout.action\"\nsystemctl --user stop hue-director-session 2>/dev/null\nexit 0\n",
            "sh", Paths.strip(Paths.state) + "/plugins/hueDirector", Paths.strip(Qt.resolvedUrl("plugin.json")), String(SettingsData.getPluginSetting("hueDirector", "enabled", false))], () => {}, 0);
    }

    // --- Delay inhibitor: logind waits for it (up to InhibitDelayMaxSec, 5 s by default) before sleep or
    // power off, so the PUT can reach the bridge. Released as soon as the rule has run
    Process {
        id: inhibitor

        property bool released: false
        readonly property string what: [root.rule("sleep") ? "sleep" : "", root.rule("shutdown") || root.rule("reboot") ? "shutdown" : ""].filter(w => w).join(":")
        readonly property bool wanted: what !== "" && hueBridge.configured && !released

        running: wanted
        command: ["systemd-inhibit", "--what=" + what, "--mode=delay", "--who=Hue Director", "--why=Set the lights before sleep or power off", "sleep", "infinity"]
        // Logout scripts that kill the user's processes before calling systemctl poweroff/reboot take
        // "sleep" down too, which drops the lock. Started again at once: a new process usually escapes
        // such scripts, which collect the processes to kill up front
        onExited: if (wanted) inhibitorRestart.restart()
    }

    Timer {
        id: inhibitorRestart
        interval: 1000
        onTriggered: if (inhibitor.wanted && !inhibitor.running) inhibitor.running = true
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
