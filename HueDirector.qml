import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Raw openhue JSON arrays
    property var rooms: []
    property var lights: []
    property string error: ""
    property bool loaded: false

    readonly property int lightsOn: lights.filter(l => l.HueData?.on?.on).length
    readonly property string pillIcon: error ? "error" : (lightsOn > 0 ? "lightbulb" : "light_off")
    readonly property color pillColor: error ? Theme.error : (lightsOn > 0 ? Theme.primary : Theme.surfaceText)

    function fetch(kind, apply) {
        Proc.runCommand("huedirector.get." + kind, ["openhue", "get", kind, "--json"], (stdout, exitCode) => {
            if (exitCode !== 0) {
                error = I18n.trFor("huedirector", "openhue failed (exit %1)").arg(exitCode);
                return;
            }
            try {
                apply(JSON.parse(stdout) ?? []);
                error = "";
                loaded = true;
            } catch (e) {
                error = I18n.trFor("huedirector", "Invalid openhue output");
            }
        }, 200);
    }

    function refresh() {
        fetch("room", data => rooms = data);
        fetch("light", data => lights = data);
    }

    // Proc debounce (300ms per room) collapses slider drags into one call
    function setRoom(roomId, args) {
        Proc.runCommand("huedirector.set.room." + roomId, ["openhue", "set", "room", roomId].concat(args), (stdout, exitCode) => {
            if (exitCode !== 0) {
                error = I18n.trFor("huedirector", "openhue failed (exit %1)").arg(exitCode);
                return;
            }
            refresh();
        }, 300);
    }

    Component.onCompleted: refresh()
    onInteractionActiveChanged: if (interactionActive) refresh()

    Timer {
        interval: 30000
        running: root.surfaceLive
        repeat: true
        onTriggered: root.refresh()
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.pillIcon
                size: Theme.iconSize - 7
                color: root.pillColor
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.lightsOn > 0
                text: root.lightsOn
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.pillIcon
                size: Theme.iconSize - 7
                color: root.pillColor
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.lightsOn > 0
                text: root.lightsOn
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "Hue Director"
            detailsText: root.error || (root.loaded ? I18n.trFor("huedirector", "%1 of %2 lights on").arg(root.lightsOn).arg(root.lights.length) : I18n.trFor("huedirector", "Loading…"))

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Repeater {
                    // Count, not the array: delegates survive refreshes, so a slider drag is not interrupted
                    model: root.rooms.length

                    Column {
                        id: roomRow
                        required property int index
                        readonly property var room: root.rooms[index]
                        readonly property bool isOn: room?.GroupedLight?.HueData?.on?.on ?? false
                        readonly property int brightness: Math.round(room?.GroupedLight?.HueData?.dimming?.brightness ?? 0)
                        // Requested value held until the bridge reports it, so stale or mid-transition refreshes don't move the slider
                        property int pendingBrightness: -1

                        onBrightnessChanged: if (Math.abs(brightness - pendingBrightness) <= 1) pendingBrightness = -1

                        width: parent.width
                        spacing: Theme.spacingXS

                        Timer {
                            id: pendingTimeout
                            interval: 3000
                            onTriggered: roomRow.pendingBrightness = -1
                        }

                        DToggle {
                            width: parent.width
                            text: roomRow.room?.Name ?? ""
                            checked: roomRow.isOn
                            onToggled: checked => root.setRoom(roomRow.room.Id, [checked ? "--on" : "--off"])
                        }

                        DSlider {
                            id: slider
                            width: parent.width
                            minimum: 1
                            maximum: 100
                            unit: "%"
                            startIcon: "brightness_low"
                            endIcon: "brightness_high"
                            onSliderValueChanged: newValue => {
                                roomRow.pendingBrightness = newValue;
                                pendingTimeout.restart();
                                root.setRoom(roomRow.room.Id, ["--on", "--brightness", String(newValue)]);
                            }

                            // DSlider assigns value on drag, which would break a plain binding
                            Binding on value {
                                when: !slider.isDragging && roomRow.pendingBrightness < 0
                                value: roomRow.brightness
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 360
    popoutHeight: 400
}
