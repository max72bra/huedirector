import QtQuick
import qs.Common
import qs.DCommon.Widgets

// On/off toggle + brightness slider for a room or a light
Column {
    id: row

    property string name: ""
    property bool isOn: false
    property int brightness: 0
    property bool dimmable: true
    property bool expandable: false
    property bool expanded: false
    // Slider fill: the light's current color (Theme.primary when off or unknown)
    property color accentColor: Theme.primary
    // accentColor darkened (light theme) or lightened (dark theme) until it stands out from the popout background,
    // e.g. a 6500K near-white fill on a light theme. Colors that already stand out are left untouched
    readonly property color visibleAccent: {
        const bg = luminance(Theme.surfaceContainer);
        let c = accentColor;
        for (let i = 0; i < 4 && Math.abs(luminance(c) - bg) < 0.2; i++)
            c = bg > 0.5 ? Qt.darker(c, 1.3) : Qt.lighter(c, 1.3);
        return c;
    }
    // Dark text on light fills, light text on dark ones
    readonly property color accentTextColor: luminance(visibleAccent) > 0.5 ? "#000000" : "#FFFFFF"

    // Approximate relative luminance on gamma-encoded channels, good enough for contrast decisions
    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    signal toggleRequested(bool on)
    signal brightnessRequested(int value)

    spacing: Theme.spacingXS

    Row {
        width: parent.width
        spacing: Theme.spacingXS

        DIconButton {
            id: expandButton
            anchors.verticalCenter: parent.verticalCenter
            visible: row.expandable
            iconName: row.expanded ? "expand_less" : "expand_more"
            onClicked: row.expanded = !row.expanded
        }

        DToggle {
            width: parent.width - (expandButton.visible ? expandButton.width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: row.name
            checked: row.isOn
            onToggled: checked => row.toggleRequested(checked)
        }
    }

    HeldSlider {
        width: parent.width
        visible: row.dimmable
        minimum: 1
        maximum: 100
        unit: "%"
        startIcon: "brightness_low"
        endIcon: "brightness_high"
        reported: row.brightness
        fillColor: row.visibleAccent
        fillTextColor: row.accentTextColor
        onRequested: value => row.brightnessRequested(value)
    }
}
