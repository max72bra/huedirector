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
    // Scenes with a color palette can run as dynamic scenes (colors cycling slowly)
    property bool dynamicCapable: false
    property bool dynamicActive: false
    // Smart scene (changes with the time of day): marked with a clock badge
    property bool smart: false

    // Text and icons sit on the scrim, over any scene color: always the light on-color
    readonly property color onScrim: Theme.contrastLight
    readonly property color badgeColor: Theme.withAlpha(Theme.scrimColor, 0.35)

    signal activated
    signal dynamicToggled

    function stopColor(i) {
        return colors.length ? colors[Math.min(i, colors.length - 1)] : Theme.surfaceContainerHigh;
    }

    height: Theme.listItemHeight + Theme.spacingXS
    radius: Theme.cornerRadius
    border.width: active ? Theme.outlineWidthFocused : 0
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

    // Darkens the bottom so the name stays readable on light palettes (bright white scenes)
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
                color: Theme.withAlpha(Theme.scrimColor, Theme.scrimAlpha)
            }
        }
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
        color: tile.onScrim
    }

    DIcon {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingXS
        visible: tile.active
        name: "check_circle"
        size: Theme.iconSizeSmall
        color: tile.onScrim
    }

    StateLayer {
        stateColor: tile.onScrim
        onClicked: tile.activated()
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacingXS
        width: Theme.iconSize
        height: width
        radius: width / 2
        visible: tile.smart
        color: tile.badgeColor

        DIcon {
            anchors.centerIn: parent
            name: "schedule"
            size: Theme.iconSizeSmall
            color: tile.onScrim
        }
    }

    // Play/pause the dynamic palette; above the tile StateLayer so it gets its own clicks
    Rectangle {
        id: dynamicButton
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacingXS
        width: Theme.iconSize
        height: width
        radius: width / 2
        visible: tile.dynamicCapable
        color: tile.badgeColor
        Accessible.role: Accessible.Button
        Accessible.name: tile.dynamicActive ? I18n.trFor("hueDirector", "Stop dynamic scene") : I18n.trFor("hueDirector", "Play dynamic scene")

        DIcon {
            anchors.centerIn: parent
            name: tile.dynamicActive ? "pause" : "play_arrow"
            size: Theme.iconSizeSmall
            color: tile.onScrim
        }

        StateLayer {
            stateColor: tile.onScrim
            onClicked: tile.dynamicToggled()
        }
    }
}
