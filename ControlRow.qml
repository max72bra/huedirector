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
        onRequested: value => row.brightnessRequested(value)
    }
}
