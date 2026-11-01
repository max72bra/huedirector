import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

// Pairs openhue with a Hue Bridge through `openhue setup`, in the popout (first time) and in settings (again)
Column {
    id: panel

    readonly property int timeoutSeconds: 90
    // Same rule as openhue: $XDG_CONFIG_HOME/openhue if set, else ~/.openhue. Only the bridge line is read, never the key
    readonly property string readBridgeScript: "d=\"${XDG_CONFIG_HOME:+$XDG_CONFIG_HOME/openhue}\"; sed -n 's/^bridge: *//p' \"${d:-$HOME/.openhue}/config.yaml\" 2>/dev/null"
    readonly property bool validIp: ipField.text === "" || /^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$/.test(ipField.text)

    property string bridgeIp: ""
    property bool waiting: false
    property bool cancelled: false
    property int secondsLeft: 0
    property string lastError: ""
    // "", "success" or "failed"
    property string result: ""
    property string message: ""

    signal paired

    width: parent.width
    spacing: Theme.spacingS

    function readBridge() {
        Proc.runCommand("hueDirector.pairing.bridge", ["sh", "-c", readBridgeScript], (stdout, exitCode) => bridgeIp = stdout.trim(), 0);
    }

    function startPairing() {
        if (!validIp || waiting)
            return;
        lastError = "";
        cancelled = false;
        result = "";
        message = I18n.trFor("hueDirector", "Looking for the Hue Bridge…");
        secondsLeft = timeoutSeconds;
        // timeout: openhue setup polls for the button forever
        setup.command = ["timeout", String(timeoutSeconds), "openhue", "setup"].concat(ipField.text ? ["-b", ipField.text] : []);
        setup.running = true;
        waiting = true;
    }

    Component.onCompleted: readBridge()

    Process {
        id: setup

        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("[KO]") !== -1)
                    panel.lastError = line.replace(/^.*\[KO\]\s*/, "");
                else if (line.indexOf("push the button") !== -1)
                    countdown.start();
            }
        }

        onExited: (exitCode, exitStatus) => {
            countdown.stop();
            panel.waiting = false;
            if (exitCode === 0 && !panel.lastError && !panel.cancelled) {
                panel.result = "success";
                panel.message = I18n.trFor("hueDirector", "Paired with the Hue Bridge");
                panel.readBridge();
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
                panel.message = I18n.trFor("hueDirector", "Hue Bridge not found: enter its IP address");
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
