import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "."
import "Accent.js" as Accent
import "WallpaperSync.js" as WallpaperSync

PluginComponent {
    id: root

    // State, commands and the event stream live in the daemon (HueEvents.qml), one for all bars
    readonly property var hue: PluginService.pluginDaemonInstances["hueDirector"] ?? null
    readonly property var rooms: hue?.rooms ?? []
    readonly property var zones: hue?.zones ?? []
    // Rooms first, then zones: home cards, room page and favorite room look them up here
    readonly property var groups: rooms.concat(zones)
    // Entertainment areas: cards for the wallpaper sync, after rooms and zones
    readonly property var areas: hue?.areas ?? []
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

    // Colors along a light that is on, as [{pos 0..1, rgb}], or [] when off. Gradient lights: their points,
    // evenly spread; mirrored styles start at the center and repeat towards both ends. Others: one color
    function lightStops(light) {
        const solid = lightRgb(light);
        if (!solid)
            return [];
        const g = light.HueData.gradient;
        const pts = (g?.points ?? []).map(p => xyToRgb(p.color.xy.x, p.color.xy.y)).filter(c => c);
        if (pts.length < 2)
            return [{ pos: 0, rgb: solid }, { pos: 1, rgb: solid }];
        const step = 1 / (pts.length - 1);
        if ((g.mode ?? "").endsWith("_mirrored"))
            return pts.map((c, i) => ({ pos: 0.5 - i * step / 2, rgb: c })).reverse().concat(pts.slice(1).map((c, i) => ({ pos: 0.5 + (i + 1) * step / 2, rgb: c })));
        return pts.map((c, i) => ({ pos: i * step, rgb: c }));
    }

    // Color at t (0..1) between sorted stops
    function stopsAt(stops, t) {
        const next = stops.findIndex(s => s.pos >= t);
        if (next <= 0)
            return stops[next < 0 ? stops.length - 1 : 0].rgb;
        const a = stops[next - 1], b = stops[next];
        const f = b.pos > a.pos ? (t - a.pos) / (b.pos - a.pos) : 0;
        return [0, 1, 2].map(i => a.rgb[i] + (b.rgb[i] - a.rgb[i]) * f);
    }

    // Room or zone card background: one equal band per light that is on, gradient lights drawn along
    // their band. [] (flat average tint) unless a gradient light is on
    function groupStops(lightList) {
        const on = lightList.map(lightStops).filter(s => s.length);
        if (!on.some(s => s.length > 2 || s[0].rgb !== s[1].rgb))
            return [];
        return [].concat(...on.map((s, i) => s.map(st => ({ pos: (i + 0.05 + st.pos * 0.9) / on.length, rgb: st.rgb }))));
    }

    // Entertainment area card background: each channel's color at its x position in the area (left to
    // right); a gradient strip's segment takes the color at its place along the strip
    function areaStops(area) {
        const ch = area?.Channels ?? [];
        const maxX = Math.max(0, ...ch.map(c => Math.abs(c.X)));
        const segments = {};
        ch.forEach(c => c.Members.forEach(m => segments[m.LightId] = (segments[m.LightId] ?? 0) + 1));
        const byPos = {};
        for (const c of ch) {
            for (const m of c.Members) {
                const s = lightStops(lights.find(l => l.Id === m.LightId));
                if (!s.length)
                    continue;
                const n = segments[m.LightId];
                const pos = Math.round((maxX ? (c.X / maxX + 1) / 2 : 0.5) * 100) / 100;
                (byPos[pos] = byPos[pos] ?? []).push(stopsAt(s, n > 1 ? m.Index / (n - 1) : 0.5));
            }
        }
        // Channels on the same vertical (left top and bottom) share one averaged stop
        return Object.keys(byPos).map(Number).sort((a, b) => a - b).map(p => ({ pos: p, rgb: [0, 1, 2].map(i => byPos[p].reduce((sum, c) => sum + c[i], 0) / byPos[p].length) }));
    }

    function rgbColor(rgb) {
        return rgb ? Qt.rgba(rgb[0], rgb[1], rgb[2], 1) : Theme.primary;
    }

    // Wallpaper sampler for the daemon's sync (HueEvents.syncSamplers): a Canvas paints only inside a
    // window, which the bar widgets have and the daemon doesn't. Never shown
    Canvas {
        id: wallpaperSampler

        property string source: ""
        // Pending sample(path, cb) callback: cb({w, h, px}) or cb(null) on error or timeout
        property var callback: null

        width: WallpaperSync.sampleWidth
        height: WallpaperSync.sampleHeight
        opacity: 0
        renderStrategy: Canvas.Immediate

        function sample(path, cb) {
            // A newer request replaces a pending one, dropped unanswered: not an unreadable wallpaper
            if (callback) {
                sampleTimeout.stop();
                unloadImage(source);
            }
            callback = cb;
            // encodeURI leaves "#" alone, which would start a URL fragment
            source = "file://" + encodeURI(path).replace(/#/g, "%23");
            sampleTimeout.restart();
            if (isImageLoaded(source))
                requestPaint();
            else
                loadImage(source);
        }

        function finish(img) {
            sampleTimeout.stop();
            const cb = callback;
            callback = null;
            unloadImage(source);
            cb?.(img);
        }

        onImageLoaded: if (callback && isImageLoaded(source)) requestPaint()
        onPaint: {
            if (!callback || !isImageLoaded(source))
                return;
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(source, 0, 0, width, height);
            finish(WallpaperSync.fromRgba(ctx.getImageData(0, 0, width, height).data, width, height));
        }

        // Unreadable files (videos, missing) never report imageLoaded
        Timer {
            id: sampleTimeout
            interval: 5000
            onTriggered: wallpaperSampler.finish(null)
        }
    }

    onHueChanged: hue?.addSyncSampler(wallpaperSampler)
    Component.onCompleted: hue?.addSyncSampler(wallpaperSampler)
    Component.onDestruction: hue?.removeSyncSampler(wallpaperSampler)

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

    // Effect labels for LightRow and the room page. Literal strings, so the translation tooling can extract them
    function effectLabel(v) {
        switch (v) {
        case "no_effect":
            return I18n.trFor("hueDirector", "No effect");
        case "candle":
            return I18n.trFor("hueDirector", "Candle");
        case "fire":
            return I18n.trFor("hueDirector", "Fireplace");
        case "prism":
            return I18n.trFor("hueDirector", "Prism");
        case "sparkle":
            return I18n.trFor("hueDirector", "Sparkle");
        case "opal":
            return I18n.trFor("hueDirector", "Opal");
        case "glisten":
            return I18n.trFor("hueDirector", "Glisten");
        case "underwater":
            return I18n.trFor("hueDirector", "Underwater");
        case "cosmos":
            return I18n.trFor("hueDirector", "Cosmos");
        case "sunbeam":
            return I18n.trFor("hueDirector", "Sunbeam");
        case "enchant":
            return I18n.trFor("hueDirector", "Enchant");
        case "sunrise":
            return I18n.trFor("hueDirector", "Sunrise");
        case "sunset":
            return I18n.trFor("hueDirector", "Sunset");
        default:
            return v;
        }
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

    // Touchpads send fractions of a notch (120)
    property real wheelAccum: 0

    // 10% per notch on the favorite. Without one the event stays unaccepted: the bar switches workspace
    function pillWheel(wheel) {
        if (!wheel.angleDelta.y || !hue?.pluginData?.favoriteLight) {
            wheel.accepted = false;
            return;
        }
        wheelAccum += wheel.angleDelta.y;
        const notches = Math.trunc(wheelAccum / 120);
        if (!notches)
            return;
        wheelAccum -= notches * 120;
        hue.wheelFavorite(notches * 10);
    }

    // shortcut: the wheel area covers the icon and the count, not the pill padding (PluginComponent doesn't
    // forward BarPill.wheel); there the bar still switches workspace, until the shell exposes that signal
    horizontalBarPill: Component {
        MouseArea {
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            acceptedButtons: Qt.NoButton
            onWheel: wheel => root.pillWheel(wheel)

            Row {
                id: pillRow
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
    }

    verticalBarPill: Component {
        MouseArea {
            implicitWidth: pillColumn.implicitWidth
            implicitHeight: pillColumn.implicitHeight
            acceptedButtons: Qt.NoButton
            onWheel: wheel => root.pillWheel(wheel)

            Column {
                id: pillColumn
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
                                    stops: root.groupStops(roomLights)
                                    subtitle: (isOn ? I18n.trFor("hueDirector", "%1 of %2 on · %3%").arg(onCount).arg(roomLights.length).arg(brightness) : I18n.trFor("hueDirector", "Off")) + unreachableText
                                    onToggleRequested: on => root.hue.setRoom(room, { on: { on: on } })
                                    onBrightnessRequested: value => root.hue.setRoom(room, { on: { on: true }, dimming: { brightness: value } })
                                    onClicked: root.openRoomId = room.Id
                                }
                            }
                        }

                        StyledText {
                            visible: root.areas.length > 0
                            topPadding: Theme.spacingS
                            text: I18n.trFor("hueDirector", "Entertainment areas")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        // Entertainment area: the toggle starts the wallpaper sync (one area at a time),
                        // the slider sets the brightness of all its lights. No page
                        Repeater {
                            model: root.areas.length

                            RoomCard {
                                required property int index
                                readonly property var area: root.areas[index]
                                readonly property bool syncing: root.hue?.syncAreaId === area?.Id

                                width: parent.width
                                clickable: false
                                // Another app is streaming to it: hands off until it stops
                                enabled: !area?.Active
                                name: area?.Name ?? ""
                                icon: "tv"
                                isOn: syncing
                                sliderEnabled: syncing
                                brightness: syncing ? (root.hue?.syncBrightness ?? 0) : 0
                                accentColor: root.rgbColor(root.averageRgb(root.lights.filter(l => (area?.LightIds ?? []).includes(l.Id))))
                                stops: root.areaStops(area)
                                subtitle: area?.Active ? I18n.trFor("hueDirector", "In use by another app") : syncing && root.hue.syncError ? root.hue.syncError : syncing ? I18n.trFor("hueDirector", "Wallpaper sync on · %1%").arg(brightness) : I18n.trFor("hueDirector", "Wallpaper sync off")
                                onToggleRequested: on => root.hue.setSync(on ? area.Id : "")
                                onBrightnessRequested: value => root.hue.setSyncBrightness(value)
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
                        // Effects any light of the room supports, not only the shared ones (mixed models
                        // often share none); then the timed ones (sunrise/sunset), "no_effect" first.
                        // grouped_light ignores effects: they are sent light by light
                        readonly property var effectValues: {
                            const regular = [], timed = [];
                            for (const l of roomLights) {
                                for (const e of l.HueData?.effects?.effect_values ?? [])
                                    if (e !== "no_effect" && !regular.includes(e))
                                        regular.push(e);
                                for (const e of l.HueData?.timed_effects?.effect_values ?? [])
                                    if (e !== "no_effect" && !timed.includes(e))
                                        timed.push(e);
                            }
                            return regular.length || timed.length ? ["no_effect"].concat(regular, timed) : [];
                        }
                        // The effect every light with effects is running; different ones show "no_effect"
                        readonly property string currentEffect: {
                            const running = roomLights.filter(l => l.HueData?.effects || l.HueData?.timed_effects).map(l => {
                                const timed = l.HueData?.timed_effects?.status ?? "no_effect";
                                return timed !== "no_effect" ? timed : (l.HueData?.effects?.status ?? "no_effect");
                            });
                            return running.length && running.every(e => e === running[0]) ? running[0] : "no_effect";
                        }

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

                        // Room-wide effect: sent to each light that supports it, skipping the ones another app streams to.
                        // "no_effect" goes to every light with effects. Picking the shown value sends it again, which
                        // also clears a mix of different effects (shown as "no_effect")
                        DDropdown {
                            width: parent.width
                            visible: roomPage.effectValues.length > 0
                            text: I18n.trFor("hueDirector", "Effect")
                            options: roomPage.effectValues.map(v => root.effectLabel(v))
                            optionValues: roomPage.effectValues
                            currentValue: roomPage.currentEffect
                            onValueChanged: value => {
                                for (const l of roomPage.roomLights) {
                                    const hd = l.HueData;
                                    const supported = (hd?.effects?.effect_values ?? []).concat(hd?.timed_effects?.effect_values ?? []);
                                    if (!l.Streaming && supported.includes(value))
                                        root.hue.setEffect(l, value);
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
                                    effectLabel: root.effectLabel
                                    currentRgb: root.lightRgb(light)
                                    expanded: roomPage.expandedLightId === light?.Id
                                    // The color picker may answer after the popout is gone: the daemon outlives it
                                    applyColor: {
                                        const lightId = light?.Id;
                                        const hue = root.hue;
                                        return c => hue?.setColor(lightId, c);
                                    }
                                    gradientColors: (light?.HueData?.gradient?.points ?? []).map(p => root.rgbColor(root.xyToRgb(p.color.xy.x, p.color.xy.y)))
                                    applyGradient: {
                                        const lightId = light?.Id;
                                        const hue = root.hue;
                                        return (colors, mode) => hue?.setGradient(lightId, colors, mode);
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
