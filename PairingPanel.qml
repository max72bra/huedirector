import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

// Pairs with a Hue Bridge (HueBridge.pairScript), in the popout (first time) and in settings (again)
Column {
    id: panel

    // HueBridge instance of the host component
    required property var bridge

    readonly property int timeoutSeconds: 90
    readonly property bool validIp: ipField.text === "" || /^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$/.test(ipField.text)

    readonly property string bridgeIp: bridge?.configured ? bridge.ip : ""
    property bool waiting: false
    property bool succeeded: false
    property bool cancelled: false
    property int secondsLeft: 0
    property string lastError: ""
    // "", "success" or "failed"
    property string result: ""
    property string message: ""

    signal paired

    width: parent.width
    spacing: Theme.spacingS

    function startPairing() {
        if (!validIp || waiting)
            return;
        lastError = "";
        cancelled = false;
        succeeded = false;
        result = "";
        message = I18n.trFor("hueDirector", "Looking for the Hue Bridge…");
        secondsLeft = timeoutSeconds;
        // timeout: the script polls for the button until it is pressed
        setup.command = ["timeout", String(timeoutSeconds), "sh", "-c", bridge.pairScript, "sh", bridge.stateDir, ipField.text];
        setup.running = true;
        waiting = true;
    }

    Process {
        id: setup

        stdout: SplitParser {
            // Status lines from HueBridge.pairScript
            onRead: line => {
                if (line.startsWith("IP "))
                    panel.message = I18n.trFor("hueDirector", "Connecting to the bridge at %1…").arg(line.slice(3));
                else if (line === "WAIT")
                    countdown.start();
                else if (line === "OK")
                    panel.succeeded = true;
                else if (line === "ERR notfound")
                    panel.lastError = I18n.trFor("hueDirector", "Hue Bridge not found: enter its IP address");
                else if (line === "ERR unreachable")
                    panel.lastError = I18n.trFor("hueDirector", "Hue Bridge not reachable at this address");
                else if (line === "ERR notbridge")
                    panel.lastError = I18n.trFor("hueDirector", "No Hue Bridge at this address");
                else if (line.startsWith("ERR"))
                    panel.lastError = line.slice(4) || I18n.trFor("hueDirector", "Pairing failed");
            }
        }

        onExited: (exitCode, exitStatus) => {
            countdown.stop();
            panel.waiting = false;
            if (panel.succeeded && !panel.cancelled) {
                panel.result = "success";
                panel.message = I18n.trFor("hueDirector", "Paired with the Hue Bridge");
                panel.bridge.loadConfig();
                PluginService.setGlobalVar("hueDirector", "pairingRevision", PluginService.getGlobalVar("hueDirector", "pairingRevision", 0) + 1);
                panel.paired();
                return;
            }
            panel.result = "failed";
            if (panel.cancelled)
                panel.message = I18n.trFor("hueDirector", "Pairing cancelled");
            else if (exitCode === 124)
                panel.message = I18n.trFor("hueDirector", "The bridge button was not pressed within %1 seconds").arg(panel.timeoutSeconds);
            else if (panel.lastError)
                panel.message = panel.lastError;
            else
                panel.message = I18n.trFor("hueDirector", "Pairing failed (exit %1)").arg(exitCode);
        }
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: panel.secondsLeft = Math.max(0, panel.secondsLeft - 1)
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeMedium
        text: panel.bridgeIp ? I18n.trFor("hueDirector", "Paired with the bridge at %1").arg(panel.bridgeIp) : I18n.trFor("hueDirector", "Not paired with a Hue Bridge")
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        text: panel.bridgeIp ? I18n.trFor("hueDirector", "Pair again after resetting or replacing the bridge, or if its IP address changed. The saved key is replaced only if pairing succeeds.") : I18n.trFor("hueDirector", "Click Pair, then press the round button on top of your Hue Bridge.")
    }

    DTextField {
        id: ipField
        width: parent.width
        enabled: !panel.waiting
        labelText: I18n.trFor("hueDirector", "Bridge IP address (optional)")
        placeholderText: I18n.trFor("hueDirector", "Auto-discover")
        isError: !panel.validIp
        supportingText: panel.validIp ? I18n.trFor("hueDirector", "Leave empty to find the bridge automatically. The IP is shown in the Hue app under Settings → Bridges.") : I18n.trFor("hueDirector", "Enter an IPv4 address, e.g. 192.168.1.20")
        onAccepted: panel.startPairing()
    }

    Row {
        spacing: Theme.spacingS

        DButton {
            text: panel.bridgeIp ? I18n.trFor("hueDirector", "Pair again") : I18n.trFor("hueDirector", "Pair")
            iconName: "link"
            busy: panel.waiting
            enabled: panel.validIp && !panel.waiting
            onClicked: panel.startPairing()
        }

        DButton {
            visible: panel.waiting
            text: I18n.trFor("hueDirector", "Cancel")
            backgroundColor: Theme.secondaryContainer
            onClicked: {
                panel.cancelled = true;
                setup.running = false;
            }
        }
    }

    StyledText {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeMedium
        color: panel.result === "failed" ? Theme.error : (panel.result === "success" ? Theme.primary : Theme.surfaceText)
        text: panel.waiting && countdown.running ? I18n.trFor("hueDirector", "Press the button on your Hue Bridge now (%1 s left)").arg(panel.secondsLeft) : panel.message
    }
}
