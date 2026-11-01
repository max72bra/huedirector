import QtQuick
import qs.DCommon.Widgets

// DSlider that follows the bridge-reported value, but holds the requested one
// until the bridge reports it, so stale or mid-transition refreshes don't move it
DSlider {
    id: slider

    property int reported: 0
    // Max distance between requested and reported value that counts as confirmed
    property int tolerance: 1
    property int pending: -1

    signal requested(int value)

    onReportedChanged: if (Math.abs(reported - pending) <= tolerance) pending = -1
    onSliderValueChanged: newValue => {
        pending = newValue;
        pendingTimeout.restart();
        requested(newValue);
    }

    Timer {
        id: pendingTimeout
        interval: 3000
        onTriggered: slider.pending = -1
    }

    // DSlider assigns value on drag, which would break a plain binding
    Binding on value {
        when: !slider.isDragging && slider.pending < 0
        value: slider.reported
    }
}
