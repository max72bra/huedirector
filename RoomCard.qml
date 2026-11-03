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
    // False shows the slider but ignores it (entertainment area while not syncing)
    property bool sliderEnabled: true
    // Average color of the room's lights that are on; Theme.primary when off
    property color accentColor: Theme.primary
    readonly property color visibleAccent: Accent.visible(accentColor, Theme.surfaceContainer)
    // Icon bubble: the light's color at 0.3 over the card; the icon is checked against it, not the theme surface
    readonly property color bubbleColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3)
    readonly property color iconColor: Accent.visible(accentColor, Qt.tint(color, bubbleColor))
    // Colors along the card, [{pos 0..1, rgb [r, g, b]}] (HueDirector.groupStops/areaStops): drawn as
    // a horizontal tint instead of the flat accentColor one; [] keeps the flat tint
    property var stops: []

    signal toggleRequested(bool on)
    signal brightnessRequested(int value)

    clickable: true
    implicitHeight: content.implicitHeight + pad * 2
    // Room color washed over the card surface while the room is on
    color: isOn && !stops.length ? Qt.tint(surfaceColor, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.18)) : surfaceColor

    Behavior on color {
        ColorAnimation {
            duration: Theme.longDuration
        }
    }

    // GradientStop objects can't be bound
    // from a list: they are recreated when the stops change
    onStopsChanged: {
        // Copied: the list property would already show the new stops
        const old = [];
        for (let i = 0; i < tintGradient.stops.length; i++)
            old.push(tintGradient.stops[i]);
        // A bit stronger than the flat tint (0.25 vs 0.18), 30% less saturated (towards the gray of the same luminance) so
        // vivid gradients stay soft. Lightening towards white instead washed pale colors into a uniform gray
        const soft = c => {
            const gray = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
            return Qt.rgba(...c.map(v => v * 0.7 + gray * 0.3), 0.25);
        };
        tintGradient.stops = stops.map(s => stopComponent.createObject(tintGradient, { position: s.pos, color: soft(s.rgb) }));
        for (let i = 0; i < old.length; i++)
            old[i].destroy();
    }

    Component {
        id: stopComponent
        GradientStop {}
    }

    // Inside the padded content: stretched back over the whole card, behind the controls
    Rectangle {
        z: -1
        anchors.fill: parent
        anchors.margins: -card.pad
        radius: card.radius
        visible: card.isOn && card.stops.length > 0
        gradient: Gradient {
            id: tintGradient
            orientation: Gradient.Horizontal
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
                width: Theme.iconButtonSize
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: card.isOn ? card.bubbleColor : Theme.surfaceContainerHigh

                DIcon {
                    anchors.centerIn: parent
                    name: card.icon
                    size: Theme.iconSize
                    color: card.isOn ? card.iconColor : Theme.surfaceVariantText
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
            enabled: card.sliderEnabled
            minimum: 1
            maximum: 100
            unit: "%"
            startIcon: "brightness_low"
            endIcon: "brightness_high"
            reported: card.brightness
            fillColor: card.visibleAccent
            fillTextColor: Accent.textOn(card.visibleAccent, Theme.surfaceText, Theme.surface)
            onRequested: value => card.brightnessRequested(value)
        }
    }
}
