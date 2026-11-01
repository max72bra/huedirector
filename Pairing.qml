import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

// Pairing with a Hue Bridge (HueBridge.pairScript). Lives in the daemon, so a pairing survives the popout
// closing while the user walks to the bridge, and the popout and the settings page show the same one
Item {
    id: pairing

    visible: false

    required property var bridge

    readonly property int timeoutSeconds: 90
    property bool waiting: false
    // True once the bridge waits for its button: the countdown is shown from then on
    property bool counting: false
    property int secondsLeft: 0
    // "", "success" or "failed"
    property string result: ""
    property string message: ""

    property bool succeeded: false
    property bool cancelled: false
    property string lastError: ""
    // The timeout also covers discovery and the certificate check, so the countdown counts from the start
    property double startedAt: 0

    // ip: "" for discovery, else an IPv4 address validated by the caller
    function start(ip) {
        if (waiting)
            return;
        lastError = "";
        cancelled = false;
        succeeded = false;
        counting = false;
        result = "";
        message = I18n.trFor("hueDirector", "Looking for the Hue Bridge…");
        startedAt = Date.now();
        secondsLeft = timeoutSeconds;
        // timeout: the script polls for the button until it is pressed
        setup.command = ["timeout", String(timeoutSeconds), "sh", "-c", bridge.pairScript, "sh", bridge.stateDir, ip];
        setup.running = true;
        waiting = true;
    }

    function cancel() {
        cancelled = true;
        setup.running = false;
    }

    function forget() {
        bridge.forget(() => {
            result = "";
            message = I18n.trFor("hueDirector", "Bridge forgotten on this computer. The bridge itself may still list Hue Director among its connected apps.");
        });
    }

    Process {
        id: setup

        stdout: SplitParser {
            // Status lines from HueBridge.pairScript
            onRead: line => {
                if (line.startsWith("IP "))
                    pairing.message = I18n.trFor("hueDirector", "Connecting to the bridge at %1…").arg(line.slice(3));
                else if (line === "WAIT") {
                    pairing.counting = true;
                    countdown.triggered();
                    countdown.start();
                } else if (line === "OK")
                    pairing.succeeded = true;
                else if (line === "ERR notfound")
                    pairing.lastError = I18n.trFor("hueDirector", "Hue Bridge not found: enter its IP address");
                else if (line === "ERR unreachable")
                    pairing.lastError = I18n.trFor("hueDirector", "Hue Bridge not reachable at this address");
                else if (line === "ERR notbridge")
                    pairing.lastError = I18n.trFor("hueDirector", "No Hue Bridge at this address");
                else if (line.startsWith("ERR"))
                    pairing.lastError = line.slice(4) || I18n.trFor("hueDirector", "Pairing failed");
            }
        }

        onExited: (exitCode, exitStatus) => {
            countdown.stop();
            pairing.waiting = false;
            pairing.counting = false;
            if (pairing.succeeded && !pairing.cancelled) {
                pairing.result = "success";
                pairing.message = I18n.trFor("hueDirector", "Paired with the Hue Bridge");
                // HueBridge reloads its config on this
                PluginService.setGlobalVar("hueDirector", "pairingRevision", PluginService.getGlobalVar("hueDirector", "pairingRevision", 0) + 1);
                return;
            }
            pairing.result = "failed";
            if (pairing.cancelled)
                pairing.message = I18n.trFor("hueDirector", "Pairing cancelled");
            else if (exitCode === 124)
                pairing.message = I18n.trFor("hueDirector", "The bridge button was not pressed within %1 seconds").arg(pairing.timeoutSeconds);
            else if (pairing.lastError)
                pairing.message = pairing.lastError;
            else
                pairing.message = I18n.trFor("hueDirector", "Pairing failed (exit %1)").arg(exitCode);
        }
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: pairing.secondsLeft = Math.max(0, pairing.timeoutSeconds - Math.round((Date.now() - pairing.startedAt) / 1000))
    }
}
