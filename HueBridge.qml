import QtQuick
import qs.Common
import qs.Services

// Hue API v2 client. QML XMLHttpRequest can't trust the bridge certificate (private Signify CA),
// so requests run through curl with the bridge public key pinned at pairing: no CA file needed,
// and a different device answering on the bridge IP is rejected (curl exit 90).
//
// The bridge connection lives in a curl config file (0600): ip variable, key header, pinned key.
// The key never appears in a command line: shell scripts keep it in variables and write it with
// the printf builtin, curl reads it from the config file.
Item {
    id: bridge

    visible: false

    readonly property string stateDir: Paths.strip(Paths.state) + "/plugins/hueDirector"
    readonly property string confPath: stateDir + "/bridge.conf"

    property bool configured: false
    // Single instance, in the daemon (HueEvents.qml); Proc.runCommand debounces by these ids
    readonly property string procPrefix: "hueDirector.bridge."
    property string ip: ""

    // Bodies waiting for the Proc debounce, per resource id (see put())
    property var pendingBodies: ({})
    // Callbacks waiting for the next fetch / for a resource's PUT: the Proc debounce runs only the last
    // call, so earlier callers (e.g. screen lock then suspend on the same light) are kept here and all answered
    property var fetchWaiters: []
    property var putWaiters: ({})
    // Fade time for on/off and scene recalls in ms (Hue "dynamics"); -1 leaves the bridge default (about 0.4 s).
    // Sliders are not faded: a long fade would lag behind the drag
    property int transitionMs: -1

    signal configChanged

    // Bumped by PairingPanel (popout or settings) after a successful pairing or a forget
    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === "hueDirector" && varName === "pairingRevision")
                bridge.loadConfig();
        }
    }

    // Shared shell functions. pin_of IP: sha256 of the bridge public key, base64 (44 chars)
    // (an unreachable bridge gives no key: fail instead of hashing empty input)
    readonly property string shellLib: "pin_of() { k=$(echo | timeout 5 openssl s_client -connect \"$1:443\" 2>/dev/null | openssl x509 -pubkey -noout 2>/dev/null); [ -n \"$k\" ] || return 1; printf '%s\\n' \"$k\" | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 -binary | base64; }\n"
        // write_conf DIR IP KEY PIN: atomic, so a failed write keeps the previous pairing.
        // Explicit chmod before the key is written: a default ACL on the folder overrides umask
        + "write_conf() { umask 077; mkdir -p \"$1\" && chmod 700 \"$1\" && : > \"$1/bridge.conf.$$\" && chmod 600 \"$1/bridge.conf.$$\" && printf '# Hue Director bridge connection, written at pairing\\nvariable = \"ip=%s\"\\nheader = \"hue-application-key: %s\"\\n# insecure skips the CA check only: the pinned bridge public key below must still match\\ninsecure\\npinnedpubkey = \"sha256//%s\"\\nsilent\\n' \"$2\" \"$3\" \"$4\" > \"$1/bridge.conf.$$\" && mv -f \"$1/bridge.conf.$$\" \"$1/bridge.conf\"; }\n"

    // $1 = state dir, $2 = bridge IP or empty for discovery. Prints status lines:
    // "IP <ip>", "WAIT" (press the button), "OK", "ERR <reason>" (notfound, unreachable, notbridge or the bridge's description)
    readonly property string pairScript: shellLib
        + "ip=$2\n"
        + "if [ -z \"$ip\" ]; then\n"
        + "  command -v avahi-browse >/dev/null && ip=$(timeout 5 avahi-browse -rtpk _hue._tcp 2>/dev/null | awk -F';' '$1==\"=\" && $3==\"IPv4\" {print $8; exit}')\n"
        + "  [ -n \"$ip\" ] || ip=$(curl -s -m 5 https://discovery.meethue.com | sed -n 's/.*\"internalipaddress\":\"\\([0-9.]*\\)\".*/\\1/p' | head -n 1)\n"
        + "  [ -n \"$ip\" ] || { echo 'ERR notfound'; exit 3; }\n"
        + "fi\n"
        + "echo \"IP $ip\"\n"
        + "pin=$(pin_of \"$ip\"); [ ${#pin} -eq 44 ] || { echo 'ERR unreachable'; exit 3; }\n"
        + "curl -sk -m 5 --pinnedpubkey \"sha256//$pin\" \"https://$ip/api/config\" | grep -q '\"bridgeid\"' || { echo 'ERR notbridge'; exit 3; }\n"
        + "echo WAIT\n"
        + "while :; do\n"
        + "  r=$(curl -sk -m 5 --pinnedpubkey \"sha256//$pin\" -X POST --data '{\"devicetype\":\"hue_director#dux_shell\",\"generateclientkey\":true}' \"https://$ip/api\") || { echo 'ERR unreachable'; exit 3; }\n"
        + "  key=$(printf '%s' \"$r\" | sed -n 's/.*\"username\":\"\\([A-Za-z0-9-]*\\)\".*/\\1/p')\n"
        + "  [ -n \"$key\" ] && break\n"
        // 101 = link button not pressed yet
        + "  printf '%s' \"$r\" | grep -q '\"type\":101' || { echo \"ERR $(printf '%s' \"$r\" | sed -n 's/.*\"description\":\"\\([^\"]*\\)\".*/\\1/p')\"; exit 4; }\n"
        + "  sleep 1\n"
        + "done\n"
        + "write_conf \"$1\" \"$ip\" \"$key\" \"$pin\" && echo OK\n"

    // $1 = state dir. Removes everything the plugin leaves on this machine. logout.action goes first:
    // stopping the unit runs its ExecStop, which then finds no action and does nothing
    readonly property string forgetScript: "rm -f \"$1/logout.action\"\n"
        + "systemctl --user stop hue-director-session 2>/dev/null\n"
        + "rm -f \"$1/bridge.conf\" \"$1/logout-hook.sh\"\n"
        + "rmdir \"$1\" 2>/dev/null\n"
        + "exit 0\n"

    // Reloads through pairingRevision, like after a pairing
    function forget(done) {
        Proc.runCommand(procPrefix + "forget", ["sh", "-c", forgetScript, "sh", stateDir], () => {
            PluginService.setGlobalVar("hueDirector", "pairingRevision", PluginService.getGlobalVar("hueDirector", "pairingRevision", 0) + 1);
            done?.();
        }, 0);
    }

    function curlArgs(path) {
        // path is relative to /clip/v2/, e.g. "resource" or "resource/light/<id>"
        return ["curl", "-K", confPath, "--expand-url", "https://{{ip}}/clip/v2/" + path];
    }

    // Reads the ip from the config; no config means not paired
    function loadConfig() {
        Proc.runCommand(procPrefix + "config", ["sh", "-c", "sed -n 's/^variable = \"ip=\\(.*\\)\"$/\\1/p' \"$1\"", "sh", confPath], (stdout, exitCode) => {
            ip = exitCode === 0 ? stdout.trim() : "";
            configured = ip !== "";
            configChanged();
        }, 0);
    }

    // cb(result, error): result is {rooms, lights} in the shape the UI uses,
    // error "" or "unpaired" or "certchanged" or a message
    function fetchAll(cb) {
        fetchWaiters.push(cb);
        Proc.runCommand(procPrefix + "fetch", curlArgs("resource").concat(["-m", "10", "-w", "\n%{http_code}"]), (stdout, exitCode) => {
            const waiters = fetchWaiters;
            fetchWaiters = [];
            const response = parseResponse(stdout, exitCode);
            const result = response.error ? null : normalize(response.body?.data ?? []);
            // One failing caller must not keep the others waiting
            for (const w of waiters) {
                try {
                    w(result, response.error);
                } catch (e) {
                    console.warn("Hue Director: fetch callback failed:", e);
                }
            }
        }, 200);
    }

    // kind: "light" | "grouped_light" | "scene". Debounced per resource, so slider drags send one request.
    // The debounce keeps only the last call, so bodies are merged: a toggle followed by a slider move
    // within 300 ms sends both. color and color_temperature exclude each other, the latest wins
    function put(kind, id, body, cb) {
        const merged = Object.assign({}, pendingBodies[id] ?? {}, body);
        if (body.color)
            delete merged.color_temperature;
        if (body.color_temperature)
            delete merged.color;
        pendingBodies[id] = merged;
        (putWaiters[id] = putWaiters[id] ?? []).push(cb);
        const sent = Object.assign({}, merged);
        if (transitionMs >= 0) {
            // Smart scenes take only an action in recall
            if (sent.recall && kind === "scene")
                sent.recall = Object.assign({}, sent.recall, { duration: transitionMs });
            else if (sent.on && !sent.dimming && !sent.color && !sent.color_temperature && !sent.dynamics)
                sent.dynamics = { duration: transitionMs };
        }
        Proc.runCommand(procPrefix + "put." + id, curlArgs("resource/" + kind + "/" + id).concat(["-m", "10", "-X", "PUT", "-H", "Content-Type: application/json", "--data", JSON.stringify(sent), "-w", "\n%{http_code}"]), (stdout, exitCode) => {
            delete pendingBodies[id];
            const waiters = putWaiters[id] ?? [];
            delete putWaiters[id];
            const error = parseResponse(stdout, exitCode).error;
            for (const w of waiters) {
                try {
                    w?.(error);
                } catch (e) {
                    console.warn("Hue Director: put callback failed:", e);
                }
            }
        }, 300);
    }

    // stdout is the body plus a last line with the HTTP status (-w)
    function parseResponse(stdout, exitCode) {
        if (exitCode === 26)
            return { error: "unpaired" };
        // Pinned public key mismatch: replaced bridge, or another device on its address
        if (exitCode === 90)
            return { error: "certchanged" };
        if (exitCode === 6 || exitCode === 7 || exitCode === 28)
            return { error: I18n.trFor("hueDirector", "Hue Bridge not reachable") };
        if (exitCode !== 0)
            return { error: I18n.trFor("hueDirector", "Request failed (curl exit %1)").arg(exitCode) };
        const cut = stdout.lastIndexOf("\n");
        const status = parseInt(stdout.slice(cut + 1));
        let body = null;
        try {
            body = JSON.parse(stdout.slice(0, cut));
        } catch (e) {}
        if (status === 403)
            return { error: "unpaired" };
        if (status < 200 || status >= 300)
            return { error: body?.errors?.[0]?.description || I18n.trFor("hueDirector", "Bridge error (HTTP %1)").arg(status) };
        // 207 and some 200 answers carry per-field errors (e.g. an effect the light doesn't support)
        if (body?.errors?.length)
            return { error: body.errors[0].description || I18n.trFor("hueDirector", "Bridge error (HTTP %1)").arg(status) };
        return { body: body, error: "" };
    }

    // Joins flat v2 resources into the shape the UI was built on:
    // room {Id, Name, Archetype, GroupedLight.HueData, Scenes[] {Id, Name, HueData},
    //       SmartScenes[] {Id, Name, HueData, Current = scene of the active time slot or null}},
    // light {Id, Name, Archetype, HueData, Reachable, Parent.Parent.Id = room}, homeGroupedId (all lights of the bridge)
    function normalize(data) {
        const deviceRoom = {};
        const groupedByRoom = {};
        let homeGroupedId = "";
        const scenesByRoom = {};
        // zigbee_connectivity status per device: "connected", "disconnected", "connectivity_issue", ...
        const deviceZigbee = {};
        for (const r of data) {
            if (r.type === "room")
                for (const c of r.children ?? [])
                    if (c.rtype === "device")
                        deviceRoom[c.rid] = r.id;
            if (r.type === "grouped_light" && r.owner?.rtype === "room")
                groupedByRoom[r.owner.rid] = r;
            if (r.type === "zigbee_connectivity" && r.owner?.rtype === "device")
                deviceZigbee[r.owner.rid] = r.status;
            if (r.type === "grouped_light" && r.owner?.rtype === "bridge_home")
                homeGroupedId = r.id;
            if (r.type === "scene" && r.group?.rtype === "room")
                (scenesByRoom[r.group.rid] = scenesByRoom[r.group.rid] ?? []).push({ Id: r.id, Name: r.metadata?.name ?? "", HueData: r });
        }
        // Smart scenes switch between scenes by time of day; Current gives the tile its colors
        const sceneById = {};
        for (const list of Object.values(scenesByRoom))
            for (const sc of list)
                sceneById[sc.Id] = sc;
        const smartByRoom = {};
        for (const r of data) {
            if (r.type !== "smart_scene" || r.group?.rtype !== "room")
                continue;
            const slot = r.active_timeslot;
            const day = (r.week_timeslots ?? []).find(w => (w.recurrence ?? []).includes(slot?.weekday));
            const current = sceneById[day?.timeslots?.[slot?.timeslot_id]?.target?.rid] ?? null;
            (smartByRoom[r.group.rid] = smartByRoom[r.group.rid] ?? []).push({ Id: r.id, Name: r.metadata?.name ?? "", HueData: r, Current: current });
        }
        const rooms = data.filter(r => r.type === "room").map(r => ({
            Id: r.id,
            Name: r.metadata?.name ?? "",
            Archetype: r.metadata?.archetype ?? "",
            GroupedLight: groupedByRoom[r.id] ? { HueData: groupedByRoom[r.id] } : null,
            Scenes: scenesByRoom[r.id] ?? [],
            SmartScenes: smartByRoom[r.id] ?? []
        }));
        const lights = data.filter(r => r.type === "light").map(l => ({
            Id: l.id,
            Name: l.metadata?.name ?? "",
            Archetype: l.metadata?.archetype ?? "",
            HueData: l,
            // Lights without a zigbee_connectivity service (e.g. Matter/Wi-Fi) count as reachable
            Reachable: (deviceZigbee[l.owner?.rid] ?? "connected") === "connected",
            Parent: { Id: l.owner?.rid, Parent: { Id: deviceRoom[l.owner?.rid] } }
        }));
        return { rooms: rooms, lights: lights, homeGroupedId: homeGroupedId };
    }

    // Saved targets ("grouped_light:<id>" or "light:<id>", settings and IPC) -> {kind, id}, or null.
    // ids come from the bridge; anything else is rejected (they also end up in the logout hook file)
    function parseTarget(target) {
        const sep = (target ?? "").indexOf(":");
        if (sep < 0)
            return null;
        const kind = target.slice(0, sep);
        const id = target.slice(sep + 1);
        if ((kind !== "light" && kind !== "grouped_light") || !/^[0-9a-f-]+$/.test(id))
            return null;
        return { kind: kind, id: id };
    }

    // Whether a target is on in a normalize() result (or anything with rooms, lights, homeGroupedId).
    // The home group counts as on when any reachable light is on: unreachable ones keep a stale state
    function targetIsOn(t, state) {
        if (t.kind === "light")
            return state.lights.find(l => l.Id === t.id)?.HueData?.on?.on ?? false;
        const room = state.rooms.find(r => r.GroupedLight?.HueData?.id === t.id);
        if (room)
            return room.GroupedLight.HueData.on?.on ?? false;
        return t.id === state.homeGroupedId && state.lights.some(l => l.Reachable && l.HueData?.on?.on);
    }

    // sRGB 0..1 -> CIE xy (Wide RGB D65 matrix from the Hue developer docs).
    // shortcut: no gamut clamping, the bridge maps out-of-gamut xy to the nearest color it can show
    function rgbToXy(c) {
        const lin = [c.r, c.g, c.b].map(v => v > 0.04045 ? Math.pow((v + 0.055) / 1.055, 2.4) : v / 12.92);
        const X = lin[0] * 0.664511 + lin[1] * 0.154324 + lin[2] * 0.162028;
        const Y = lin[0] * 0.283881 + lin[1] * 0.668433 + lin[2] * 0.047685;
        const Z = lin[0] * 0.000088 + lin[1] * 0.072310 + lin[2] * 0.986039;
        const sum = X + Y + Z;
        if (sum <= 0)
            return null;
        return { x: Math.round(X / sum * 10000) / 10000, y: Math.round(Y / sum * 10000) / 10000 };
    }

    Component.onCompleted: loadConfig()
}
