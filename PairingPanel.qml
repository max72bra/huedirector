import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

// View of the daemon's pairing (Pairing.qml), in the popout (first time) and in settings (again):
// both show the same pairing, which keeps running when the popout closes
Column {
    id: panel

    // The daemon (HueEvents.qml): hue.pairing and hue.bridge
    required property var hue
    readonly property var pairing: hue?.pairing ?? null

    readonly property bool validIp: ipField.text === "" || /^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$/.test(ipField.text)
    readonly property string bridgeIp: hue?.bridge?.configured ? hue.bridge.ip : ""
    readonly property bool waiting: pairing?.waiting ?? false

    width: parent.width
    spacing: Theme.spacingS

    function startPairing() {
        if (validIp && !waiting)
            pairing?.start(ipField.text);
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
            onClicked: panel.pairing?.cancel()
        }

        // Two clicks: forgetting means pairing again with the bridge button
        DButton {
            id: forgetButton
            property bool armed: false

            visible: panel.bridgeIp !== "" && !panel.waiting
            text: armed ? I18n.trFor("hueDirector", "Click again to confirm") : I18n.trFor("hueDirector", "Forget bridge")
            iconName: "link_off"
            backgroundColor: armed ? Theme.error : Theme.secondaryContainer
            textColor: armed ? Theme.surface : Theme.surfaceText
            onClicked: {
                if (!armed) {
                    armed = true;
                    disarmTimer.restart();
                    return;
                }
                armed = false;
                panel.pairing?.forget();
            }

            Timer {
                id: disarmTimer
                interval: 5000
                onTriggered: forgetButton.armed = false
            }
        }
    }

    StyledText {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeMedium
        color: panel.pairing?.result === "failed" ? Theme.error : (panel.pairing?.result === "success" ? Theme.primary : Theme.surfaceText)
        text: panel.pairing?.counting ? I18n.trFor("hueDirector", "Press the button on your Hue Bridge now (%1 s left)").arg(panel.pairing.secondsLeft) : (panel.pairing?.message ?? "")
    }
}
