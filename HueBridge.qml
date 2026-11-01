import QtQuick
import Quickshell.Io
import qs.Common

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
    // Per instance (widget, settings): Proc.runCommand debounces by id, so shared ids would drop the other instance's requests
    readonly property string procPrefix: "hueDirector." + Math.random().toString(36).slice(2) + "."
    property string ip: ""

    signal configChanged

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

    function curlArgs(path) {
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

    // cb(result, error): result is {rooms, lights} in the shape the UI uses, error a message or ""
    function fetchAll(cb) {
        Proc.runCommand(procPrefix + "fetch", curlArgs("resource").concat(["-m", "10", "-w", "\n%{http_code}"]), (stdout, exitCode) => {
            const response = parseResponse(stdout, exitCode);
            if (response.error) {
                cb(null, response.error);
                return;
            }
            cb(normalize(response.body?.data ?? []), "");
        }, 200);
    }

    // kind: "light" | "grouped_light" | "scene". Debounced per resource, so slider drags send one request
    function put(kind, id, body, cb) {
        Proc.runCommand(procPrefix + "put." + id, curlArgs(kind + "/" + id).concat(["-m", "10", "-X", "PUT", "-H", "Content-Type: application/json", "--data", JSON.stringify(body), "-w", "\n%{http_code}"]), (stdout, exitCode) => {
            cb(parseResponse(stdout, exitCode).error);
        }, 300);
    }

    // stdout is the body plus a last line with the HTTP status (-w)
    function parseResponse(stdout, exitCode) {
        if (exitCode === 26)
            return { error: "unpaired" };
        if (exitCode === 90)
            return { error: I18n.trFor("hueDirector", "The bridge certificate changed: pair again") };
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
        return { body: body, error: "" };
    }

    // Joins flat v2 resources into the shape the UI was built on:
    // room {Id, Name, GroupedLight.HueData, Scenes[] {Id, Name, HueData}}, light {Id, Name, HueData, Parent.Parent.Id = room}
    function normalize(data) {
        const deviceRoom = {};
        const groupedByRoom = {};
        const scenesByRoom = {};
        for (const r of data) {
            if (r.type === "room")
                for (const c of r.children ?? [])
                    if (c.rtype === "device")
                        deviceRoom[c.rid] = r.id;
            if (r.type === "grouped_light" && r.owner?.rtype === "room")
                groupedByRoom[r.owner.rid] = r;
            if (r.type === "scene" && r.group?.rtype === "room")
                (scenesByRoom[r.group.rid] = scenesByRoom[r.group.rid] ?? []).push({ Id: r.id, Name: r.metadata?.name ?? "", HueData: r });
        }
        const rooms = data.filter(r => r.type === "room").map(r => ({
            Id: r.id,
            Name: r.metadata?.name ?? "",
            GroupedLight: groupedByRoom[r.id] ? { HueData: groupedByRoom[r.id] } : null,
            Scenes: scenesByRoom[r.id] ?? []
        }));
        const lights = data.filter(r => r.type === "light").map(l => ({
            Id: l.id,
            Name: l.metadata?.name ?? "",
            HueData: l,
            Parent: { Id: l.owner?.rid, Parent: { Id: deviceRoom[l.owner?.rid] } }
        }));
        return { rooms: rooms, lights: lights };
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
