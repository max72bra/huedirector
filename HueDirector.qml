import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "."

PluginComponent {
    id: root

    // Bridge data, in the shape built by HueBridge.normalize()
    property var rooms: []
    property var lights: []
    property string error: ""
    property bool loaded: false
    // False when there is no pairing or the bridge rejects the key; PairingPanel replaces the room list
    property bool paired: true

    readonly property int lightsOn: lights.filter(l => l.HueData?.on?.on).length

    // Pill shows the favorite room only; "all" or a removed room falls back to the whole home
    readonly property string favoriteRoomId: pluginData?.favoriteRoom ?? ""
    readonly property bool hasFavorite: rooms.some(r => r.Id === favoriteRoomId)
    readonly property int pillLightsOn: hasFavorite ? lights.filter(l => l.Parent?.Parent?.Id === favoriteRoomId && l.HueData?.on?.on).length : lightsOn
    readonly property string pillIcon: !paired ? "link_off" : error ? "error" : (pillLightsOn > 0 ? "lightbulb" : "light_off")
    readonly property color pillColor: paired && error ? Theme.error : (paired && pillLightsOn > 0 ? Theme.primary : Theme.surfaceText)

    // Current color of a light as [r, g, b] in 0..1 at full brightness, or null when off/unknown.
    // mirek_valid tells whether the light is in color temperature mode or xy color mode
    function lightRgb(light) {
        const hd = light?.HueData;
        if (!hd?.on?.on)
            return null;
        if (hd.color_temperature?.mirek_valid && hd.color_temperature.mirek)
            return mirekToRgb(hd.color_temperature.mirek);
        if (hd.color?.xy)
            return xyToRgb(hd.color.xy.x, hd.color.xy.y);
        return null;
    }

    // CIE xy -> sRGB with the Wide RGB D65 matrix from the Hue developer docs, normalized so the max channel is 1
    function xyToRgb(x, y) {
        if (y <= 0)
            return null;
        const X = x / y, Z = (1 - x - y) / y;
        const lin = [X * 1.656492 - 0.354851 - Z * 0.255038, -X * 0.707196 + 1.655397 + Z * 0.036152, X * 0.051713 - 0.121364 + Z * 1.011530].map(v => Math.max(0, v));
        const m = Math.max(...lin) || 1;
        return lin.map(v => v / m).map(v => v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055);
    }

    // Color temperature -> RGB, Tanner Helland's blackbody approximation
    function mirekToRgb(mirek) {
        const t = 1e6 / mirek / 100;
        const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
        const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
        const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
        return [r, g, b].map(v => Math.min(255, Math.max(0, v)) / 255);
    }

    // Average color of the lights that are on, or null
    function averageRgb(lightList) {
        const colors = lightList.map(lightRgb).filter(c => c);
        if (!colors.length)
            return null;
        return [0, 1, 2].map(i => colors.reduce((sum, c) => sum + c[i], 0) / colors.length);
    }

    function rgbColor(rgb) {
        return rgb ? Qt.rgba(rgb[0], rgb[1], rgb[2], 1) : Theme.primary;
    }

    HueBridge {
        id: hueBridge
        onConfigChanged: root.refresh()
    }

    function refresh() {
        if (!hueBridge.configured) {
            paired = false;
            return;
        }
        hueBridge.fetchAll((result, err) => {
            if (err === "unpaired") {
                paired = false;
                error = "";
                return;
            }
            if (err) {
                error = err;
                return;
            }
            // Bridge order is not stable (scenes move after activation): sort everything by name
            const byName = (a, b) => (a.Name ?? "").localeCompare(b.Name ?? "");
            result.rooms.forEach(r => r.Scenes.sort(byName));
            rooms = result.rooms.sort(byName);
            lights = result.lights.sort(byName);
            error = "";
            loaded = true;
            paired = true;
            startEvents();
        });
    }

    // kind: "light" | "grouped_light" | "scene", body: Hue API v2 PUT body
    function setResource(kind, id, body) {
        hueBridge.put(kind, id, body, err => {
            if (err === "unpaired")
                paired = false;
            else if (err)
                error = err;
            else
                refresh();
        });
    }

    // Rooms are controlled through their grouped_light service
    function setRoom(room, body) {
        const groupedId = room?.GroupedLight?.HueData?.id;
        if (groupedId)
            setResource("grouped_light", groupedId, body);
    }

    function setColor(lightId, c) {
        const xy = hueBridge.rgbToXy(c);
        if (xy)
            setResource("light", lightId, { on: { on: true }, color: { xy: xy } });
    }

    onInteractionActiveChanged: if (interactionActive) refresh()

    // Consecutive event stream failures; reset whenever an event arrives
    property int eventsRestarts: 0
    readonly property int maxEventsRestarts: 5
    readonly property bool eventsActive: eventsProcess.running && eventsRestarts <= maxEventsRestarts

    function startEvents() {
        if (!eventsProcess.running && !eventsRestartTimer.running && eventsRestarts <= maxEventsRestarts)
            eventsProcess.running = true;
    }

    // Live updates from the bridge event stream (SSE): any event triggers a refresh,
    // the Proc debounce in HueBridge.fetchAll() collapses bursts into one request
    Process {
        id: eventsProcess
        command: ["curl", "-K", hueBridge.confPath, "-N", "-H", "Accept: text/event-stream", "--expand-url", "https://{{ip}}/eventstream/clip/v2"]
        onExited: (exitCode, exitStatus) => {
            // Unpaired: wait for pairingRevision instead of retrying
            if (!root.paired)
                return;
            if (++root.eventsRestarts > root.maxEventsRestarts) {
                console.warn("Hue Director: event stream keeps failing - falling back to polling");
                return;
            }
            eventsRestartTimer.restart();
        }
        stdout: SplitParser {
            // SSE frames: "id: ...", "data: [...]", and ": hi" keepalives
            onRead: line => {
                if (!line.startsWith("data:"))
                    return;
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

    // Bumped by PairingPanel (popout or settings) after a successful pairing
    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId !== "hueDirector" || varName !== "pairingRevision")
                return;
            root.eventsRestarts = 0;
            // Reconnect with the new key/bridge; loadConfig() triggers refresh(), which restarts events
            eventsProcess.running = false;
            hueBridge.loadConfig();
        }
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
            detailsText: !root.paired ? "" : root.error || (root.loaded ? I18n.trFor("hueDirector", "%1 of %2 lights on").arg(root.lightsOn).arg(root.lights.length) : I18n.trFor("hueDirector", "Loading…"))

            // PairingPanel already says "Not paired", so detailsText stays empty
            PairingPanel {
                bridge: hueBridge
                visible: !root.paired
            }

            DFlickable {
                visible: root.paired
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
                                accentColor: root.rgbColor(root.averageRgb(roomItem.roomLights))
                                name: roomItem.room?.Name ?? ""
                                isOn: roomItem.room?.GroupedLight?.HueData?.on?.on ?? false
                                brightness: Math.round(roomItem.room?.GroupedLight?.HueData?.dimming?.brightness ?? 0)
                                dimmable: !!roomItem.room?.GroupedLight?.HueData?.dimming
                                expandable: roomItem.roomLights.length > 0 || roomItem.scenes.length > 0
                                onToggleRequested: on => root.setRoom(roomItem.room, { on: { on: on } })
                                onBrightnessRequested: value => root.setRoom(roomItem.room, { on: { on: true }, dimming: { brightness: value } })
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
                                    root.setResource("scene", roomItem.pendingSceneId, { recall: { action: "active" } });
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
                                    readonly property color accentColor: root.rgbColor(root.lightRgb(light))

                                    x: Theme.spacingL
                                    width: roomItem.width - x
                                    spacing: Theme.spacingXS

                                    ControlRow {
                                        id: lightControl
                                        width: parent.width
                                        accentColor: lightItem.accentColor
                                        name: lightItem.light?.Name ?? ""
                                        isOn: lightItem.light?.HueData?.on?.on ?? false
                                        brightness: Math.round(lightItem.light?.HueData?.dimming?.brightness ?? 0)
                                        dimmable: !!lightItem.light?.HueData?.dimming
                                        expandable: lightItem.hasColor || !!lightItem.colorTemp
                                        onToggleRequested: on => root.setResource("light", lightItem.light.Id, { on: { on: on } })
                                        onBrightnessRequested: value => root.setResource("light", lightItem.light.Id, { on: { on: true }, dimming: { brightness: value } })
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
                                        fillColor: lightControl.visibleAccent
                                        fillTextColor: lightControl.accentTextColor
                                        onRequested: value => root.setResource("light", lightItem.light.Id, { on: { on: true }, color_temperature: { mirek: Math.round(1e6 / value) } })
                                    }

                                    // Swatch takes the slot of the end icon of the sliders above (DSlider SideIcon: iconSize wide, spacingM gap)
                                    Row {
                                        width: parent.width
                                        visible: lightControl.expanded && lightItem.hasColor
                                        spacing: Theme.spacingM

                                        // Fully saturated hue; the picker covers pastel tones and exact colors
                                        HeldSlider {
                                            id: hueSlider
                                            readonly property real currentHue: root.lightRgb(lightItem.light) ? root.rgbColor(root.lightRgb(lightItem.light)).hsvHue : -1
                                            // Achromatic or off (currentHue < 0): keep the last known hue
                                            property int knownHue: 0

                                            onCurrentHueChanged: if (currentHue >= 0) knownHue = Math.round(currentHue * 360)
                                            Component.onCompleted: if (currentHue >= 0) knownHue = Math.round(currentHue * 360)

                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - pickerButton.width - parent.spacing
                                            minimum: 0
                                            maximum: 359
                                            showValue: false
                                            startIcon: "palette"
                                            reported: knownHue
                                            // xy <-> RGB round trips drift a few degrees
                                            tolerance: 5
                                            onRequested: value => root.setColor(lightItem.light.Id, Qt.hsva(value / 360, 1, 1, 1))

                                            // Same rainbow track as the shell color picker (Modules/ColorPicker/ColorPickerContent.qml)
                                            trackGradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0; color: Qt.hsva(0, 1, 1, 1) }
                                                GradientStop { position: 1 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) }
                                                GradientStop { position: 2 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
                                                GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) }
                                                GradientStop { position: 4 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) }
                                                GradientStop { position: 5 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) }
                                                GradientStop { position: 1; color: Qt.hsva(1, 1, 1, 1) }
                                            }
                                        }

                                        // Opens the shell color picker (hex, color area, eyedropper, recent colors)
                                        DColorButton {
                                            id: pickerButton
                                            width: Theme.iconSize
                                            height: Theme.iconSize
                                            anchors.verticalCenter: parent.verticalCenter
                                            swatchColor: lightItem.accentColor
                                            tooltipText: I18n.trFor("hueDirector", "More colors…")
                                            onClicked: {
                                                const picker = PopoutService.colorPickerModal;
                                                if (!picker)
                                                    return;
                                                const lightId = lightItem.light.Id;
                                                picker.selectedColor = lightItem.accentColor;
                                                picker.pickerTitle = lightItem.light.Name;
                                                picker.onColorSelectedCallback = c => root.setColor(lightId, c);
                                                picker.show();
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

    popoutWidth: 420
    popoutHeight: 480
}
