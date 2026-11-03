import QtQuick
import qs.DCommon.Widgets

// Tooltip for an icon that is not a button. A HoverHandler, not a MouseArea: it takes no clicks
// and doesn't steal the hover from the card or tile around the icon
Item {
    id: tip

    property string text: ""

    anchors.fill: parent

    HoverHandler {
        onHoveredChanged: hovered ? host.schedule() : host.dismiss()
    }

    DTooltipHost {
        id: host
        text: tip.text
        target: tip
    }
}
