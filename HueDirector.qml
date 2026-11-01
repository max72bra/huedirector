import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "."

PluginComponent {
    id: root

    // Raw openhue JSON arrays
    property var rooms: []
    property var lights: []
    property string error: ""
    property bool loaded: false

    // Red, orange, yellow, green, cyan, blue, purple, pink
    readonly property var colorPresets: ["#FF0000", "#FF8000", "#FFD000", "#00FF00", "#00FFFF", "#0000FF", "#8000FF", "#FF00A0"]

    readonly property int lightsOn: lights.filter(l => l.HueData?.on?.on).length

    // Pill shows the favorite room only; "all" or a removed room falls back to the whole home
    readonly property string favoriteRoomId: pluginData?.favoriteRoom ?? ""
    readonly property bool hasFavorite: rooms.some(r => r.Id === favoriteRoomId)
    readonly property int pillLightsOn: hasFavorite ? lights.filter(l => l.Parent?.Parent?.Id === favoriteRoomId && l.HueData?.on?.on).length : lightsOn
    readonly property string pillIcon: error ? "error" : (pillLightsOn > 0 ? "lightbulb" : "light_off")
    readonly property color pillColor: error ? Theme.error : (pillLightsOn > 0 ? Theme.primary : Theme.surfaceText)

    function fetch(kind, apply) {
        Proc.runCommand("hueDirector.get." + kind, ["openhue", "get", kind, "--json"], (stdout, exitCode) => {
            if (exitCode !== 0) {
                error = I18n.trFor("hueDirector", "openhue failed (exit %1)").arg(exitCode);
                return;
            }
            try {
                apply(JSON.parse(stdout) ?? []);
                error = "";
                loaded = true;
            } catch (e) {
                error = I18n.trFor("hueDirector", "Invalid openhue output");
            }
        }, 200);
    }

    function refresh() {
        // Bridge order is not stable (scenes move after activation): sort everything by name
        const byName = (a, b) => (a.Name ?? "").localeCompare(b.Name ?? "");
        fetch("room", data => {
            data.forEach(r => (r.Scenes ?? []).sort(byName));
            rooms = data.sort(byName);
        });
        fetch("light", data => lights = data.sort(byName));
    }

    // kind: "room" | "light". Proc debounce (300ms per resource) collapses slider drags into one call
    function setResource(kind, id, args) {
        Proc.runCommand("hueDirector.set." + kind + "." + id, ["openhue", "set", kind, id].concat(args), (stdout, exitCode) => {
            if (exitCode !== 0) {
                error = I18n.trFor("hueDirector", "openhue failed (exit %1)").arg(exitCode);
                return;
            }
            refresh();
        }, 300);
    }

    Component.onCompleted: refresh()
    onInteractionActiveChanged: if (interactionActive) refresh()

    // Consecutive event stream failures; reset whenever an event arrives
    property int eventsRestarts: 0
    readonly property int maxEventsRestarts: 5
    readonly property bool eventsActive: eventsProcess.running && eventsRestarts <= maxEventsRestarts

    // Live updates (openhue events are alpha): any event triggers a refresh,
    // Proc debounce in fetch() collapses bursts into one call
    Process {
        id: eventsProcess
        running: true
        command: ["openhue", "get", "events"]
        onExited: (exitCode, exitStatus) => {
            if (++root.eventsRestarts > root.maxEventsRestarts) {
                console.warn("Hue Director: event stream keeps failing - falling back to polling");
                return;
            }
            eventsRestartTimer.restart();
        }
        stdout: SplitParser {
            onRead: line => {
                root.eventsRestarts = 0;
                root.refresh();
            }
        }
    }

    Timer {
        id: eventsRestartTimer
        interval: 5000
        onTriggered: eventsProcess.running = true
    }

    // Safety net while events are active, main source when they are not
    Timer {
        interval: root.eventsActive ? 300000 : 30000
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
                visible: root.pillLightsOn > 0
                text: root.pillLightsOn
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
                visible: root.pillLightsOn > 0
                text: root.pillLightsOn
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Hue Director"
            detailsText: root.error || (root.loaded ? I18n.trFor("hueDirector", "%1 of %2 lights on").arg(root.lightsOn).arg(root.lights.length) : I18n.trFor("hueDirector", "Loading…"))

            DFlickable {
                width: parent.width
                height: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingL * 2
                contentWidth: width
                contentHeight: roomList.implicitHeight
                clip: true

                Column {
                    id: roomList
                    width: parent.width
                    spacing: Theme.spacingM

                    Repeater {
                        // Count, not the array: delegates survive refreshes, so a slider drag is not interrupted
                        model: root.rooms.length

                        Column {
                            id: roomItem
                            required property int index
                            readonly property var room: root.rooms[index]
                            readonly property var roomLights: root.lights.filter(l => l.Parent?.Parent?.Id === room?.Id)
                            readonly property var scenes: room?.Scenes ?? []
                            // status.active is "inactive", "static" or "dynamic_palette"
                            readonly property string activeSceneId: scenes.find(s => (s.HueData?.status?.active ?? "inactive") !== "inactive")?.Id ?? ""
                            // Clicked scene held until the bridge reports it active, like ControlRow.pendingBrightness
                            property string pendingSceneId: ""

                            onActiveSceneIdChanged: if (activeSceneId === pendingSceneId) pendingSceneId = ""

                            Timer {
                                id: pendingSceneTimeout
                                interval: 3000
                                onTriggered: roomItem.pendingSceneId = ""
                            }

                            width: parent.width
                            spacing: Theme.spacingXS

                            ControlRow {
                                id: roomControl
                                width: parent.width
                                name: roomItem.room?.Name ?? ""
                                isOn: roomItem.room?.GroupedLight?.HueData?.on?.on ?? false
                                brightness: Math.round(roomItem.room?.GroupedLight?.HueData?.dimming?.brightness ?? 0)
                                dimmable: !!roomItem.room?.GroupedLight?.HueData?.dimming
                                expandable: roomItem.roomLights.length > 0 || roomItem.scenes.length > 0
                                onToggleRequested: on => root.setResource("room", roomItem.room.Id, [on ? "--on" : "--off"])
                                onBrightnessRequested: value => root.setResource("room", roomItem.room.Id, ["--on", "--brightness", String(value)])
                            }

                            DFilterChips {
                                x: Theme.spacingL
                                width: roomItem.width - x
                                visible: roomControl.expanded && roomItem.scenes.length > 0
                                showCounts: false
                                model: roomItem.scenes.map(s => ({ label: s.Name }))
                                onSelectionChanged: index => {
                                    roomItem.pendingSceneId = roomItem.scenes[index].Id;
                                    pendingSceneTimeout.restart();
                                    root.setResource("scene", roomItem.pendingSceneId, []);
                                }

                                // Chips assign currentIndex on click, which would break a plain binding
                                Binding on currentIndex {
                                    value: roomItem.scenes.findIndex(s => s.Id === (roomItem.pendingSceneId || roomItem.activeSceneId))
                                }
                            }

                            Repeater {
                                model: roomControl.expanded ? roomItem.roomLights.length : 0

                                Column {
                                    id: lightItem
                                    required property int index
                                    readonly property var light: roomItem.roomLights[index]
                                    readonly property var colorTemp: light?.HueData?.color_temperature ?? null
                                    readonly property bool hasColor: !!light?.HueData?.color

                                    x: Theme.spacingL
                                    width: roomItem.width - x
                                    spacing: Theme.spacingXS

                                    ControlRow {
                                        id: lightControl
                                        width: parent.width
                                        name: lightItem.light?.Name ?? ""
                                        isOn: lightItem.light?.HueData?.on?.on ?? false
                                        brightness: Math.round(lightItem.light?.HueData?.dimming?.brightness ?? 0)
                                        dimmable: !!lightItem.light?.HueData?.dimming
                                        expandable: lightItem.hasColor || !!lightItem.colorTemp
                                        onToggleRequested: on => root.setResource("light", lightItem.light.Id, [on ? "--on" : "--off"])
                                        onBrightnessRequested: value => root.setResource("light", lightItem.light.Id, ["--on", "--brightness", String(value)])
                                    }

                                    // Color temperature in Kelvin (bridge uses mirek = 1e6 / K)
                                    HeldSlider {
                                        width: parent.width
                                        visible: lightControl.expanded && !!lightItem.colorTemp
                                        minimum: Math.round(1e6 / (lightItem.colorTemp?.mirek_schema?.mirek_maximum ?? 500))
                                        maximum: Math.round(1e6 / (lightItem.colorTemp?.mirek_schema?.mirek_minimum ?? 153))
                                        step: 50
                                        unit: "K"
                                        startIcon: "wb_incandescent"
                                        endIcon: "wb_sunny"
                                        reported: Math.round(1e6 / (lightItem.colorTemp?.mirek || 370))
                                        // Kelvin -> mirek -> Kelvin rounding drifts up to ~50K at the cold end
                                        tolerance: 100
                                        onRequested: value => root.setResource("light", lightItem.light.Id, ["--on", "--temperature", String(Math.round(1e6 / value))])
                                    }

                                    Flow {
                                        width: parent.width
                                        visible: lightControl.expanded && lightItem.hasColor
                                        spacing: Theme.spacingXS

                                        Repeater {
                                            model: root.colorPresets

                                            DColorButton {
                                                required property string modelData
                                                swatchColor: modelData
                                                onClicked: root.setResource("light", lightItem.light.Id, ["--on", "--rgb", modelData])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 380
    popoutHeight: 480
}
