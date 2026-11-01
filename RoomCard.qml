import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import "Accent.js" as Accent

// Home page card for a room: icon, name, status, toggle and brightness.
// A click on the card body (clicked signal of DCard) opens the room page
DCard {
    id: card

    property string name: ""
    property string icon: "meeting_room"
    property string subtitle: ""
    property bool isOn: false
    property int brightness: 0
    property bool dimmable: true
    // Average color of the room's lights that are on; Theme.primary when off
    property color accentColor: Theme.primary
    readonly property color visibleAccent: Accent.visible(accentColor, Theme.surfaceContainer)

    signal toggleRequested(bool on)
    signal brightnessRequested(int value)

    clickable: true
    implicitHeight: content.implicitHeight + pad * 2
    // Room color washed over the card surface while the room is on
    color: isOn ? Qt.tint(surfaceColor, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.18)) : surfaceColor

    Behavior on color {
        ColorAnimation {
            duration: 250
        }
    }

    Column {
        id: content
        width: parent.width
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingM

            Rectangle {
                id: iconBubble
                width: 40
                height: 40
                radius: 20
                anchors.verticalCenter: parent.verticalCenter
                color: card.isOn ? Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.3) : Theme.surfaceContainerHigh

                DIcon {
                    anchors.centerIn: parent
                    name: card.icon
                    size: Theme.iconSize
                    color: card.isOn ? card.visibleAccent : Theme.surfaceVariantText
                }
            }

            Column {
                width: parent.width - iconBubble.width - toggle.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    width: parent.width
                    text: card.name
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    text: card.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }

            DToggle {
                id: toggle
                anchors.verticalCenter: parent.verticalCenter
                checked: card.isOn
                onToggled: checked => card.toggleRequested(checked)
            }
        }

        HeldSlider {
            width: parent.width
            visible: card.dimmable
            minimum: 1
            maximum: 100
            unit: "%"
            startIcon: "brightness_low"
            endIcon: "brightness_high"
            reported: card.brightness
            fillColor: card.visibleAccent
            fillTextColor: Accent.textOn(card.visibleAccent)
            onRequested: value => card.brightnessRequested(value)
        }
    }
}
