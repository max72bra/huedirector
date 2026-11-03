import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "."
import "Accent.js" as Accent

PluginComponent {
    id: root

    // State, commands and the event stream live in the daemon (HueEvents.qml), one for all bars
    readonly property var hue: PluginService.pluginDaemonInstances["hueDirector"] ?? null
    readonly property var rooms: hue?.rooms ?? []
    readonly property var zones: hue?.zones ?? []
    // Rooms first, then zones: home cards, room page and favorite room look them up here
    readonly property var groups: rooms.concat(zones)
    readonly property var lights: hue?.lights ?? []
    readonly property string homeGroupedId: hue?.homeGroupedId ?? ""
    readonly property string error: hue?.error ?? ""
    readonly property bool loaded: hue?.loaded ?? false
    readonly property bool paired: hue?.paired ?? true
    readonly property bool needsPairing: hue?.needsPairing ?? false
    readonly property int lightsOn: hue?.lightsOn ?? 0
    // Room or zone whose page is open in the popout; "" shows the cards
    property string openRoomId: ""

    // Pill shows the favorite room or zone only; "all" or a removed one falls back to the whole home
    readonly property string favoriteRoomId: pluginData?.favoriteRoom ?? ""
    readonly property bool hasFavorite: groups.some(r => r.Id === favoriteRoomId)
    readonly property int pillLightsOn: hasFavorite ? roomLightsOf(favoriteRoomId).filter(l => l.Reachable && l.HueData?.on?.on).length : lightsOn
    // Settings: number next to the pill icon (default on); off leaves only the icon and its color
    readonly property bool showLightCount: pluginData?.showLightCount ?? true
    readonly property string pillIcon: !paired ? "link_off" : error ? "error" : (pillLightsOn > 0 ? "lightbulb" : "light_off")
    readonly property color pillColor: paired && error ? Theme.error : (paired && pillLightsOn > 0 ? Theme.primary : Theme.surfaceText)

    function roomLightsOf(roomId) {
        const ids = groups.find(r => r.Id === roomId)?.LightIds ?? [];
        return lights.filter(l => ids.includes(l.Id));
    }

    // Current color of a light as [r, g, b] in 0..1 at full brightness, or null when off, unreachable
    // or unknown. mirek_valid tells whether the light is in color temperature mode or xy color mode
    function lightRgb(light) {
        const hd = light?.HueData;
        if (!hd?.on?.on || !light.Reachable)
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

    // Right click on the pill toggles the favorite light, room or whole home (settings: favoriteLight)
    pillRightClickAction: () => hue?.toggleFavorite()

    // Reopening the popout starts from the room cards
    onInteractionActiveChanged: {
        if (interactionActive)
            hue?.refresh();
        else
            openRoomId = "";
    }
    // Back to the cards if the open room or zone was removed from the bridge
    onGroupsChanged: if (openRoomId && !groups.some(r => r.Id === openRoomId)) openRoomId = ""

    // Material Symbols for Hue room archetypes; unknown ones fall back to meeting_room
    readonly property var roomIcons: ({
            living_room: "weekend", lounge: "weekend", kitchen: "kitchen", dining: "dining", bedroom: "bed", guest_room: "bed",
            kids_bedroom: "child_care", nursery: "crib", bathroom: "bathtub", toilet: "wc", office: "desk", computer: "computer",
            studio: "mic", music: "music_note", tv: "tv", reading: "menu_book", recreation: "sports_esports", gym: "fitness_center",
            hallway: "door_front", front_door: "door_front", staircase: "stairs", upstairs: "stairs", downstairs: "stairs",
            top_floor: "roofing", attic: "roofing", garage: "garage", carport: "garage", driveway: "directions_car",
            terrace: "deck", porch: "deck", balcony: "balcony", garden: "yard", barbecue: "outdoor_grill", pool: "pool",
            closet: "checkroom", storage: "inventory_2", laundry_room: "local_laundry_service", man_cave: "sports_bar", home: "home"
        })

    function roomIcon(archetype) {
        return roomIcons[archetype] ?? "meeting_room";
    }

    // Hue light archetypes by family (hue_lightstrip_pc, pendant_round, ...); fallback lightbulb
    function lightIcon(archetype) {
        const a = archetype ?? "";
        if (a.indexOf("lightstrip") !== -1)
            return "linear_scale";
        if (a.startsWith("hue_play"))
            return "tv";
        if (a.startsWith("pendant") || a.startsWith("ceiling"))
            return "light";
        if (a.startsWith("floor"))
            return "floor_lamp";
        if (a.startsWith("table") || a.startsWith("desk"))
            return "table_lamp";
        if (a.startsWith("wall"))
            return "wall_lamp";
        if (a.indexOf("spot") !== -1 || a.indexOf("flood") !== -1)
            return "highlight";
        return "lightbulb";
    }

    // The bridge marks a scene inactive as soon as one of its lights changes (even off and back on) and never
    // re-activates it, so the scene shown as current is: the one the bridge reports active, else the scene whose
    // actions match the lights' current state (latest last_recall wins when several match), else none
    function currentSceneId(scenes) {
        const active = scenes.find(s => (s.HueData?.status?.active ?? "inactive") !== "inactive");
        if (active)
            return active.Id;
        const matching = scenes.filter(sceneMatchesLights);
        matching.sort((a, b) => (b.HueData?.status?.last_recall ?? "").localeCompare(a.HueData?.status?.last_recall ?? ""));
        return matching[0]?.Id ?? "";
    }

    // Tolerances absorb the bridge's rounding: brightness ±2, mirek ±5, xy ±0.015 (gamut mapping)
    function sceneMatchesLights(scene) {
        const actions = scene?.HueData?.actions ?? [];
        if (!actions.length)
            return false;
        return actions.every(a => {
            const light = lights.find(l => l.Id === a.target?.rid)?.HueData;
            const want = a.action ?? {};
            if (!light)
                return false;
            const isOn = light.on?.on ?? false;
            if ((want.on?.on ?? true) !== isOn)
                return false;
            if (!isOn)
                return true;
            if (want.dimming && Math.abs(want.dimming.brightness - (light.dimming?.brightness ?? -100)) > 2)
                return false;
            if (want.color_temperature?.mirek) {
                const ct = light.color_temperature;
                if (!ct?.mirek_valid || Math.abs(want.color_temperature.mirek - ct.mirek) > 5)
                    return false;
            }
            if (want.color?.xy) {
                const xy = light.color?.xy;
                if (!xy || light.color_temperature?.mirek_valid || Math.abs(want.color.xy.x - xy.x) > 0.015 || Math.abs(want.color.xy.y - xy.y) > 0.015)
                    return false;
            }
            return true;
        });
    }

    // Up to 3 colors for a scene tile: palette colors, else palette temperatures, else the per-light actions
    function sceneColors(scene) {
        const hd = scene?.HueData;
        const out = [];
        const add = rgb => {
            if (rgb && out.length < 3)
                out.push(rgbColor(rgb));
        };
        for (const p of hd?.palette?.color ?? [])
            add(xyToRgb(p.color.xy.x, p.color.xy.y));
        if (!out.length)
            for (const p of hd?.palette?.color_temperature ?? [])
                add(mirekToRgb(p.color_temperature.mirek));
        if (!out.length)
            for (const a of hd?.actions ?? []) {
                const act = a.action ?? {};
                if (act.color?.xy)
                    add(xyToRgb(act.color.xy.x, act.color.xy.y));
                else if (act.color_temperature?.mirek)
                    add(mirekToRgb(act.color_temperature.mirek));
            }
        return out;
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.pillIcon
                size: root.iconSize
                color: root.pillColor
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.showLightCount && root.pillLightsOn > 0
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
                size: root.iconSize
                color: root.pillColor
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.showLightCount && root.pillLightsOn > 0
                text: root.pillLightsOn
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            // Own header instead of headerText/headerActions: the stock one indents the title by spacingS,
            // out of line with the cards below. Same height and title font as the stock header
            Item {
                id: header
                width: parent.width
                height: 40

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Hue Director"
                    font.pixelSize: Theme.fontSizeLarge + 4
                    color: Theme.surfaceText
                }

                // The lights-on summary and the buttons sit next to the title
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.needsPairing
                    spacing: Theme.spacingXS

                    DIconButton {
                        iconName: "settings"
                        tooltipText: I18n.trFor("hueDirector", "Settings and automations")
                        onClicked: {
                            PopoutService.openSettingsWithTab("plugin:hueDirector");
                            popout.closePopout?.();
                        }
                    }
                    // Master chip: lights on over total, tinted with their average color; click turns everything off
                    Rectangle {
                        id: masterChip

                        readonly property bool anyOn: root.lightsOn > 0
                        readonly property bool canTurnOff: anyOn && root.homeGroupedId !== ""
                        readonly property color accent: Accent.visible(root.rgbColor(root.averageRgb(root.lights)), Theme.surfaceContainer)

                        anchors.verticalCenter: parent.verticalCenter
                        width: chipRow.implicitWidth + Theme.spacingM * 2
                        height: Theme.iconButtonSize
                        radius: height / 2
                        color: anyOn ? Qt.tint(Theme.surfaceContainerHigh, Qt.rgba(accent.r, accent.g, accent.b, 0.3)) : Theme.surfaceContainerHigh
                        Accessible.role: Accessible.Button
                        Accessible.name: (root.loaded ? I18n.trFor("hueDirector", "%1 of %2 lights on").arg(root.lightsOn).arg(root.lights.length) : I18n.trFor("hueDirector", "Loading…")) + (canTurnOff ? ". " + I18n.trFor("hueDirector", "Turn off all lights") : "")

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.longDuration
                            }
                        }

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: masterChip.anyOn ? "lightbulb" : "light_off"
                                size: Theme.iconSizeSmall
                                color: masterChip.anyOn ? masterChip.accent : Theme.surfaceVariantText
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: !root.loaded ? I18n.trFor("hueDirector", "Loading…") : masterChip.anyOn ? root.lightsOn + "/" + root.lights.length : I18n.trFor("hueDirector", "All off")
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: masterChip.anyOn ? Theme.surfaceText : Theme.surfaceVariantText
                            }

                            DIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: masterChip.canTurnOff
                                name: "power_settings_new"
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                            }
                        }

                        StateLayer {
                            disabled: !masterChip.canTurnOff
                            stateColor: Theme.surfaceText
                            tooltipText: masterChip.canTurnOff ? I18n.trFor("hueDirector", "Turn off all lights") : null
                            onClicked: if (masterChip.canTurnOff) root.hue.setResource("grouped_light", root.homeGroupedId, { on: { on: false } })
                        }
                    }
                }
            }

            // Errors only: PairingPanel already says "Not paired"; certChanged shows its error here
            StyledText {
                id: errorText
                width: parent.width
                bottomPadding: Theme.spacingS
                text: root.paired ? root.error : ""
                visible: text.length > 0
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }

            PairingPanel {
                hue: root.hue
                visible: root.needsPairing
            }

            // Gap between header and page; the line shows only while the page is scrolled under the header
            Item {
                id: headerDivider
                visible: !root.needsPairing
                width: parent.width
                height: Theme.spacingL

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.outlineVariant
                    opacity: (root.openRoomId === "" ? homeFlick : roomFlick).contentY > 0 ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.shortDuration
                        }
                    }
                }
            }

            // PluginPopout sizes the popout from this component's implicitHeight, so the popout grows
            // with the open page (all controls visible without scrolling) up to 75% of the screen
            Item {
                visible: !root.needsPairing
                width: parent.width
                height: Math.min((root.parentScreen?.height ?? 1000) * 0.75 - header.height - (errorText.visible ? errorText.implicitHeight : 0) - headerDivider.height, root.openRoomId === "" ? homeColumn.implicitHeight : roomPage.implicitHeight)

                // Home: one card per room, then one per zone
                DFlickable {
                    id: homeFlick
                    anchors.fill: parent
                    visible: root.openRoomId === ""
                    contentWidth: width
                    contentHeight: homeColumn.implicitHeight
                    clip: true

                    Column {
                        id: homeColumn
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            // Count, not the array: delegates survive refreshes, so a slider drag is not interrupted
                            model: root.groups.length

                            Column {
                                required property int index
                                readonly property var room: root.groups[index]

                                width: parent.width
                                spacing: Theme.spacingS

                                // Section titles above the first room and the first zone
                                StyledText {
                                    visible: index === 0 || index === root.rooms.length
                                    topPadding: index > 0 ? Theme.spacingS : 0
                                    text: index < root.rooms.length ? I18n.trFor("hueDirector", "Rooms") : I18n.trFor("hueDirector", "Zones")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceVariantText
                                }

                                RoomCard {
                                    readonly property var room: parent.room
                                    readonly property var roomLights: root.roomLightsOf(room?.Id)
                                    readonly property int onCount: roomLights.filter(l => l.Reachable && l.HueData?.on?.on).length
                                    readonly property int unreachableCount: roomLights.filter(l => !l.Reachable).length
                                    readonly property string unreachableText: unreachableCount ? " · " + I18n.trFor("hueDirector", "%1 unreachable").arg(unreachableCount) : ""

                                    width: parent.width
                                    name: room?.Name ?? ""
                                    icon: root.roomIcon(room?.Archetype)
                                    isOn: room?.GroupedLight?.HueData?.on?.on ?? false
                                    brightness: Math.round(room?.GroupedLight?.HueData?.dimming?.brightness ?? 0)
                                    dimmable: !!room?.GroupedLight?.HueData?.dimming
                                    accentColor: root.rgbColor(root.averageRgb(roomLights))
                                    subtitle: (isOn ? I18n.trFor("hueDirector", "%1 of %2 on · %3%").arg(onCount).arg(roomLights.length).arg(brightness) : I18n.trFor("hueDirector", "Off")) + unreachableText
                                    onToggleRequested: on => root.hue.setRoom(room, { on: { on: on } })
                                    onBrightnessRequested: value => root.hue.setRoom(room, { on: { on: true }, dimming: { brightness: value } })
                                    onClicked: root.openRoomId = room.Id
                                }
                            }
                        }
                    }
                }

                // Room or zone page: scenes and lights of root.openRoomId
                DFlickable {
                    id: roomFlick
                    anchors.fill: parent
                    visible: root.openRoomId !== ""
                    contentWidth: width
                    contentHeight: roomPage.implicitHeight
                    clip: true

                    Column {
                        id: roomPage

                        readonly property var room: root.groups.find(r => r.Id === root.openRoomId) ?? null
                        readonly property var roomLights: root.roomLightsOf(room?.Id)
                        readonly property var scenes: room?.Scenes ?? []
                        readonly property var smartScenes: room?.SmartScenes ?? []
                        // A running smart scene drives the lights: no regular scene is marked meanwhile
                        readonly property bool smartActive: smartScenes.some(s => s.HueData?.state === "active")
                        readonly property string activeSceneId: smartActive ? "" : root.currentSceneId(scenes)
                        // Clicked scene held until the bridge reports it active, like HeldSlider.pending
                        property string pendingSceneId: ""
                        // One light at a time shows its color controls
                        property string expandedLightId: ""

                        onActiveSceneIdChanged: if (activeSceneId === pendingSceneId) pendingSceneId = ""

                        width: parent.width
                        spacing: Theme.spacingM

                        Connections {
                            target: root
                            function onOpenRoomIdChanged() {
                                roomPage.pendingSceneId = "";
                                roomPage.expandedLightId = "";
                            }
                        }

                        Timer {
                            id: pendingSceneTimeout
                            interval: 3000
                            onTriggered: roomPage.pendingSceneId = ""
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DIconButton {
                                id: backButton
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "arrow_back"
                                tooltipText: I18n.trFor("hueDirector", "All rooms")
                                onClicked: root.openRoomId = ""
                            }

                            DIcon {
                                id: pageIcon
                                anchors.verticalCenter: parent.verticalCenter
                                name: root.roomIcon(roomPage.room?.Archetype)
                                size: Theme.iconSize
                                color: Theme.surfaceText
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - backButton.width - pageIcon.width - pageToggle.width - parent.spacing * 3
                                text: roomPage.room?.Name ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            DToggle {
                                id: pageToggle
                                anchors.verticalCenter: parent.verticalCenter
                                checked: roomPage.room?.GroupedLight?.HueData?.on?.on ?? false
                                onToggled: checked => root.hue.setRoom(roomPage.room, { on: { on: checked } })
                            }
                        }

                        StyledText {
                            visible: roomPage.scenes.length + roomPage.smartScenes.length > 0
                            text: I18n.trFor("hueDirector", "Scenes")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        Grid {
                            id: sceneGrid
                            width: parent.width
                            columns: 3
                            spacing: Theme.spacingS

                            Repeater {
                                model: roomPage.scenes.length

                                SceneTile {
                                    required property int index
                                    readonly property var scene: roomPage.scenes[index]

                                    width: (sceneGrid.width - sceneGrid.spacing * (sceneGrid.columns - 1)) / sceneGrid.columns
                                    name: scene?.Name ?? ""
                                    colors: root.sceneColors(scene)
                                    active: scene?.Id === (roomPage.pendingSceneId || roomPage.activeSceneId)
                                    // Palette scenes can cycle their colors (Hue "dynamic" scenes)
                                    dynamicCapable: (scene?.HueData?.palette?.color?.length ?? 0) > 1
                                    dynamicActive: scene?.HueData?.status?.active === "dynamic_palette"
                                    onActivated: {
                                        roomPage.pendingSceneId = scene.Id;
                                        pendingSceneTimeout.restart();
                                        root.hue.setResource("scene", scene.Id, { recall: { action: "active" } });
                                    }
                                    onDynamicToggled: {
                                        roomPage.pendingSceneId = scene.Id;
                                        pendingSceneTimeout.restart();
                                        const body = { recall: { action: dynamicActive ? "static" : "dynamic_palette" } };
                                        // Settings → Dynamic scene speed; "-1" keeps the speed saved in the scene
                                        const speed = parseFloat(root.pluginData?.dynamicSpeed ?? "-1");
                                        if (!dynamicActive && speed >= 0)
                                            body.speed = speed;
                                        root.hue.setResource("scene", scene.Id, body);
                                    }
                                }
                            }

                            // Smart scenes: a different scene for each time of day; click starts or stops them
                            Repeater {
                                model: roomPage.smartScenes.length

                                SceneTile {
                                    required property int index
                                    readonly property var smartScene: roomPage.smartScenes[index]

                                    width: (sceneGrid.width - sceneGrid.spacing * (sceneGrid.columns - 1)) / sceneGrid.columns
                                    name: smartScene?.Name ?? ""
                                    colors: root.sceneColors(smartScene?.Current)
                                    smart: true
                                    active: smartScene?.HueData?.state === "active"
                                    onActivated: root.hue.setResource("smart_scene", smartScene.Id, { recall: { action: active ? "deactivate" : "activate" } })
                                }
                            }
                        }

                        StyledText {
                            visible: roomPage.roomLights.length > 0
                            text: I18n.trFor("hueDirector", "Lights")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingS

                            Repeater {
                                // Count, not the array: delegates survive refreshes, so a slider drag is not interrupted
                                model: roomPage.roomLights.length

                                LightRow {
                                    required property int index

                                    width: parent.width
                                    light: roomPage.roomLights[index]
                                    icon: root.lightIcon(light?.Archetype)
                                    currentRgb: root.lightRgb(light)
                                    expanded: roomPage.expandedLightId === light?.Id
                                    // The color picker may answer after the popout is gone: the daemon outlives it
                                    applyColor: {
                                        const lightId = light?.Id;
                                        const hue = root.hue;
                                        return c => hue?.setColor(lightId, c);
                                    }
                                    onExpandToggled: roomPage.expandedLightId = expanded ? "" : light.Id
                                    onToggleRequested: on => root.hue.setResource("light", light.Id, { on: { on: on } })
                                    onBrightnessRequested: value => root.hue.setResource("light", light.Id, { on: { on: true }, dimming: { brightness: value } })
                                    onIdentifyRequested: root.hue.identify(light)
                                    onEffectRequested: value => root.hue.setEffect(light, value)
                                    onTemperatureRequested: mirek => root.hue.setResource("light", light.Id, { on: { on: true }, color_temperature: { mirek: mirek } })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: Theme.listItemHeight * 7.5
    // Initial size only: PluginPopout then follows the content height (see the pages Item)
    popoutHeight: Theme.listItemHeight * 9
}
