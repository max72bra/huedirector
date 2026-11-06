import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "."

PluginSettings {
    id: root
    pluginId: "hueDirector"

    // State lives in the daemon (HueEvents.qml): no requests of our own, the options follow live changes
    readonly property var hue: PluginService.pluginDaemonInstances["hueDirector"] ?? null
    property var roomOptions: []
    // Targets for the system event rules and the favorite light, values as read by HueBridge.parseTarget()
    property var targetOptions: []
    // Wallpaper sync end per entertainment area: {areaId: [{label, value "off" | "none" | "warm" | "scene:<id>"}]}
    property var syncEndOptions: ({})
    // Areas as of the last rebuild, so the rows below aren't recreated (and closed) on every refresh
    property var syncAreas: []
    // Ids and names only: the options are rebuilt when these change, not on every brightness event,
    // which would reset a dropdown while it is open
    readonly property string optionsKey: JSON.stringify([hue?.homeGroupedId ?? "", (hue?.rooms ?? []).concat(hue?.zones ?? []).map(r => [r.Id, r.Name, r.GroupedLight?.HueData?.id ?? "", r.Scenes.map(sc => [sc.Id, sc.Name])]), (hue?.lights ?? []).map(l => [l.Id, l.Name]), (hue?.areas ?? []).map(a => [a.Id, a.Name, a.LightIds])])

    onOptionsKeyChanged: rebuildOptions()
    Component.onCompleted: rebuildOptions()

    // Dropdowns work with labels: same-named entries (the bridge allows them) get " (2)", " (3)", ...
    // or only the first could be picked
    function uniqueLabels(options) {
        const seen = {};
        return options.map(o => {
            const n = seen[o.label] = (seen[o.label] ?? 0) + 1;
            return n > 1 ? Object.assign({}, o, { label: o.label + " (" + n + ")" }) : o;
        });
    }

    function rebuildOptions() {
        const byLabel = (a, b) => a.label.localeCompare(b.label);
        const zoneLabel = name => I18n.trFor("hueDirector", "Zone · %1").arg(name);
        roomOptions = uniqueLabels((hue?.rooms ?? []).map(r => ({ label: r.Name, value: r.Id })).sort(byLabel)
            .concat((hue?.zones ?? []).map(z => ({ label: zoneLabel(z.Name), value: z.Id })).sort(byLabel)));
        const rooms = (hue?.rooms ?? []).filter(r => r.GroupedLight).map(r => ({ label: I18n.trFor("hueDirector", "Room · %1").arg(r.Name), value: "grouped_light:" + r.GroupedLight.HueData.id })).sort(byLabel);
        const zones = (hue?.zones ?? []).filter(z => z.GroupedLight).map(z => ({ label: zoneLabel(z.Name), value: "grouped_light:" + z.GroupedLight.HueData.id })).sort(byLabel);
        const lights = (hue?.lights ?? []).map(l => ({ label: I18n.trFor("hueDirector", "Light · %1").arg(l.Name), value: "light:" + l.Id })).sort(byLabel);
        const home = hue?.homeGroupedId ? [{ label: I18n.trFor("hueDirector", "All lights"), value: "grouped_light:" + hue.homeGroupedId }] : [];
        targetOptions = uniqueLabels(home.concat(rooms, zones, lights));
        // Only scenes that set at least one light of the area. Labels are matched back to values, so
        // a scene name found in several rooms gets the room name
        const groups = (hue?.rooms ?? []).concat(hue?.zones ?? []);
        const endOptions = {};
        for (const area of hue?.areas ?? []) {
            const scenes = [].concat(...groups.map(r => r.Scenes.filter(sc => (sc.HueData.actions ?? []).some(a => area.LightIds.includes(a.target?.rid))).map(sc => ({ name: sc.Name, group: r.Name, value: "scene:" + sc.Id }))));
            const label = sc => scenes.filter(o => o.name === sc.name).length > 1 ? "%1 (%2)".arg(sc.name).arg(sc.group) : sc.name;
            endOptions[area.Id] = uniqueLabels([{ label: I18n.trFor("hueDirector", "Turn off"), value: "off" }, { label: I18n.trFor("hueDirector", "Leave as is"), value: "none" }, { label: I18n.trFor("hueDirector", "Warm white"), value: "warm" }].concat(scenes.map(sc => ({ label: label(sc), value: sc.value })).sort(byLabel)));
        }
        syncEndOptions = endOptions;
        syncAreas = (hue?.areas ?? []).map(a => ({ Id: a.Id, Name: a.Name }));
    }

    // Narrower than the stock small button (56): four fit next to the dropdown on the idle row
    readonly property int actionButtonWidth: 40
    // Width of the action buttons column: the same on every row (idle has four), so the dropdowns line up
    readonly property real actionColumnWidth: actionButtonWidth * 4 + Theme.spacingL

    // Default actions come from the daemon (HueEvents.defaultActions)
    readonly property var events: [
        { key: "login", label: I18n.trFor("hueDirector", "Login") },
        { key: "logout", label: I18n.trFor("hueDirector", "Logout") },
        { key: "lock", label: I18n.trFor("hueDirector", "Screen locked") },
        { key: "unlock", label: I18n.trFor("hueDirector", "Screen unlocked") },
        { key: "monitorOff", label: I18n.trFor("hueDirector", "Monitors off") },
        { key: "monitorOn", label: I18n.trFor("hueDirector", "Monitors on") },
        { key: "sleep", label: I18n.trFor("hueDirector", "Suspend or hibernate") },
        { key: "resume", label: I18n.trFor("hueDirector", "Resume from sleep") },
        // Told apart from power off only on systemd >= 256 (PrepareForShutdownWithMetadata); older systems run "Power off" for both
        { key: "reboot", label: I18n.trFor("hueDirector", "Reboot") },
        { key: "shutdown", label: I18n.trFor("hueDirector", "Power off") },
        { key: "nightOn", label: I18n.trFor("hueDirector", "Night mode on") },
        { key: "nightOff", label: I18n.trFor("hueDirector", "Night mode off") },
        { key: "idle", label: I18n.trFor("hueDirector", "User idle") }
    ]

    StyledText {
        text: I18n.trFor("hueDirector", "Hue Bridge")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    PairingPanel {
        hue: root.hue
    }

    SelectionSetting {
        settingKey: "favoriteRoom"
        label: I18n.trFor("hueDirector", "Favorite room")
        description: I18n.trFor("hueDirector", "Room or zone shown in the bar pill (icon and lights on count)")
        // Room or zone Id is stored, so renaming it keeps the setting
        options: [{ label: I18n.trFor("hueDirector", "All rooms"), value: "all" }].concat(root.roomOptions)
        defaultValue: "all"
    }

    // Values are HueBridge.transitionMs; "-1" leaves the bridge default
    SelectionSetting {
        settingKey: "transitionMs"
        label: I18n.trFor("hueDirector", "Fade time")
        description: I18n.trFor("hueDirector", "How long lights take to turn on or off and to change scene")
        options: [
            { label: I18n.trFor("hueDirector", "Bridge default (0.4 s)"), value: "-1" },
            { label: I18n.trFor("hueDirector", "Instant"), value: "0" },
            { label: I18n.trFor("hueDirector", "%1 s").arg(1), value: "1000" },
            { label: I18n.trFor("hueDirector", "%1 s").arg(2), value: "2000" },
            { label: I18n.trFor("hueDirector", "%1 s").arg(4), value: "4000" }
        ]
        defaultValue: "-1"
    }

    // Saved into the scene when a dynamic scene starts (Hue speed 0..1); "-1" keeps the scene's own speed
    SelectionSetting {
        settingKey: "dynamicSpeed"
        label: I18n.trFor("hueDirector", "Dynamic scene speed")
        description: I18n.trFor("hueDirector", "How fast colors cycle when you play a scene. The speed is saved in the scene, also for the Hue app")
        options: [
            { label: I18n.trFor("hueDirector", "Scene default"), value: "-1" },
            { label: I18n.trFor("hueDirector", "Slow"), value: "0.2" },
            { label: I18n.trFor("hueDirector", "Medium"), value: "0.5" },
            { label: I18n.trFor("hueDirector", "Fast"), value: "0.85" }
        ]
        defaultValue: "-1"
    }

    ToggleSetting {
        settingKey: "showLightCount"
        label: I18n.trFor("hueDirector", "Show lights on count")
        description: I18n.trFor("hueDirector", "Number next to the bar icon; when off, only the icon shows the state")
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "favoriteLight"
        label: I18n.trFor("hueDirector", "Favorite light")
        description: I18n.trFor("hueDirector", "Right-click the bar icon to turn it on or off")
        // Same values as the system event targets ("grouped_light:<id>" or "light:<id>")
        options: [{ label: I18n.trFor("hueDirector", "Nothing"), value: "none" }].concat(root.targetOptions)
        defaultValue: "none"
    }

    StyledText {
        topPadding: Theme.spacingL
        text: I18n.trFor("hueDirector", "Wallpaper sync")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "syncRestore"
        label: I18n.trFor("hueDirector", "Restore wallpaper sync at startup")
        description: I18n.trFor("hueDirector", "Start the wallpaper sync again when the shell starts, on the entertainment area where it was on")
        defaultValue: false
    }

    // Only with a different wallpaper per monitor; otherwise every monitor shows the same one
    SelectionSetting {
        visible: SessionData.perMonitorWallpaper
        settingKey: "syncMonitor"
        label: I18n.trFor("hueDirector", "Wallpaper sync monitor")
        description: I18n.trFor("hueDirector", "Monitor whose wallpaper the entertainment area follows")
        options: Quickshell.screens.map(s => ({ label: s.name, value: s.name }))
        defaultValue: Quickshell.screens[0]?.name ?? ""
    }

    StyledText {
        width: parent.width
        visible: root.syncAreas.length > 0
        wrapMode: Text.WordWrap
        text: I18n.trFor("hueDirector", "When the sync stops, the lights go back to how they were. If that is not known, each entertainment area does this instead:")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    // One per entertainment area, saved as syncEnd_<areaId>. DDropdown + loadValue/saveValue like the
    // event rows below, for the same reason (settings nested in a Repeater can't save)
    Repeater {
        model: root.syncAreas

        DDropdown {
            id: endSetting
            required property var modelData
            readonly property string endKey: "syncEnd_" + modelData.Id
            readonly property var endValues: (root.syncEndOptions[modelData.Id] ?? []).map(o => o.value)
            readonly property var endLabels: (root.syncEndOptions[modelData.Id] ?? []).map(o => o.label)

            width: parent.width
            text: modelData.Name
            options: endLabels
            currentValue: endLabels[Math.max(0, endValues.indexOf(root.loadValue(endKey, "off")))] ?? ""
            onValueChanged: newValue => {
                const i = endLabels.indexOf(newValue);
                if (i >= 0)
                    root.saveValue(endKey, endValues[i]);
            }
        }
    }

    StyledText {
        topPadding: Theme.spacingL
        text: I18n.trFor("hueDirector", "System events")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: I18n.trFor("hueDirector", "Turn a light, a room, a zone or all lights on or off when something happens in your session. Logout rules need a systemd-managed session (e.g. uwsm). The lights are set before suspend and power off: the system waits for them at most a few seconds.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    // Column headers: the action buttons have no room for a label of their own
    Item {
        width: parent.width
        height: actionHeader.implicitHeight

        StyledText {
            text: I18n.trFor("hueDirector", "Event and target")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceVariantText
        }

        StyledText {
            id: actionHeader
            anchors.right: parent.right
            width: root.actionColumnWidth
            horizontalAlignment: Text.AlignHCenter
            text: I18n.trFor("hueDirector", "Action")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceVariantText
        }
    }

    Repeater {
        model: root.events

        Item {
            id: eventRow
            required property var modelData
            readonly property string actionKey: "event_" + modelData.key + "_action"

            width: parent.width
            height: Math.max(targetSetting.height, actionGroup.height)

            // Not a SelectionSetting: PluginSettings reloads only its direct children when pluginService
            // arrives, and settings nested in a Repeater can't find the page to save on (findSettings walks
            // the parents). Bound to the page's loadValue/saveValue instead, like the on/off buttons
            DDropdown {
                id: targetSetting
                readonly property string targetKey: "event_" + eventRow.modelData.key + "_target"
                // "none" instead of "": the stored value of "Nothing"
                readonly property var targetValues: ["none"].concat(root.targetOptions.map(o => o.value))
                readonly property var targetLabels: [I18n.trFor("hueDirector", "Nothing")].concat(root.targetOptions.map(o => o.label))

                width: parent.width - root.actionColumnWidth - Theme.spacingM
                text: eventRow.modelData.label
                options: targetLabels
                // loadValue reads SettingsData.pluginSettings, so this follows saves and the late pluginService
                currentValue: targetLabels[Math.max(0, targetValues.indexOf(root.loadValue(targetKey, "none")))] ?? ""
                onValueChanged: newValue => {
                    const i = targetLabels.indexOf(newValue);
                    if (i >= 0)
                        root.saveValue(targetKey, targetValues[i]);
                }
            }

            // Saved like SelectionSetting does (PluginSettings.saveValue)
            DButtonGroup {
                id: actionGroup
                readonly property var actionValues: eventRow.modelData.key === "idle" ? ["on", "off", "warm", "dim"] : ["on", "off", "warm"]
                anchors.right: parent.right
                anchors.verticalCenter: targetSetting.verticalCenter
                iconOnly: true
                checkEnabled: false
                arrowKeysSelect: false
                size: "small"
                minButtonWidth: root.actionButtonWidth
                buttonPadding: Theme.spacingS
                model: [
                    { text: I18n.trFor("hueDirector", "Turn on"), icon: "lightbulb" },
                    { text: I18n.trFor("hueDirector", "Turn off"), icon: "light_off" },
                    { text: I18n.trFor("hueDirector", "Warm white"), icon: "wb_incandescent" },
                    { text: I18n.trFor("hueDirector", "Dim"), icon: "brightness_low" }
                ].slice(0, actionValues.length)
                currentIndex: Math.max(0, actionValues.indexOf(root.loadValue(eventRow.actionKey, root.hue?.defaultActions?.[eventRow.modelData.key] ?? "off")))
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        root.saveValue(eventRow.actionKey, actionValues[index]);
                }
            }
        }
    }

    SliderSetting {
        settingKey: "idleMinutes"
        label: I18n.trFor("hueDirector", "Idle after")
        description: I18n.trFor("hueDirector", "Minutes without input before the User idle rule runs")
        defaultValue: 5
        minimum: 1
        maximum: 60
        unit: "min"
    }

    SliderSetting {
        settingKey: "dimPercent"
        label: I18n.trFor("hueDirector", "Dim to")
        description: I18n.trFor("hueDirector", "Share of each light's current brightness. It comes back when you do, unless the light was changed meanwhile")
        defaultValue: 30
        minimum: 5
        maximum: 90
        unit: "%"
    }
}
