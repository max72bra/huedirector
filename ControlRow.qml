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

    // Requested value held until the bridge reports it, so stale or mid-transition refreshes don't move the slider
    property int pendingBrightness: -1

    onBrightnessChanged: if (Math.abs(brightness - pendingBrightness) <= 1) pendingBrightness = -1

    spacing: Theme.spacingXS

    Timer {
        id: pendingTimeout
        interval: 3000
        onTriggered: row.pendingBrightness = -1
    }

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

    DSlider {
        id: slider
        width: parent.width
        visible: row.dimmable
        minimum: 1
        maximum: 100
        unit: "%"
        startIcon: "brightness_low"
        endIcon: "brightness_high"
        onSliderValueChanged: newValue => {
            row.pendingBrightness = newValue;
            pendingTimeout.restart();
            row.brightnessRequested(newValue);
        }

        // DSlider assigns value on drag, which would break a plain binding
        Binding on value {
            when: !slider.isDragging && row.pendingBrightness < 0
            value: row.brightness
        }
    }
}
