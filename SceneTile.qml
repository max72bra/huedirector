import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

// Scene button: horizontal gradient of the scene's colors, name at the bottom, check when active
Rectangle {
    id: tile

    property string name: ""
    // Up to 3 colors (HueDirector.sceneColors); empty gives a neutral tile
    property var colors: []
    property bool active: false

    signal activated

    function stopColor(i) {
        return colors.length ? colors[Math.min(i, colors.length - 1)] : Theme.surfaceContainerHigh;
    }

    height: 60
    radius: Theme.cornerRadius
    border.width: active ? 2 : 0
    border.color: Theme.primary
    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.checked: active

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
            position: 0
            color: tile.stopColor(0)
        }
        GradientStop {
            position: 0.5
            color: tile.stopColor(1)
        }
        GradientStop {
            position: 1
            color: tile.stopColor(2)
        }
    }

    // Darkens the bottom so the white name stays readable on light palettes (bright white scenes)
    Rectangle {
        anchors.fill: parent
        anchors.margins: tile.border.width
        radius: tile.radius
        gradient: Gradient {
            GradientStop {
                position: 0.3
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: Qt.rgba(0, 0, 0, 0.55)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: tile.radius
        color: "white"
        opacity: mouse.pressed ? 0.25 : (mouse.containsMouse ? 0.12 : 0)
    }

    StyledText {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingS
        text: tile.name
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: "white"
    }

    DIcon {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingXS
        visible: tile.active
        name: "check_circle"
        size: Theme.iconSizeSmall
        color: "white"
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.activated()
    }
}
