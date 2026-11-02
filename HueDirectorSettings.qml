import QtQuick
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
    // Ids and names only: the options are rebuilt when these change, not on every brightness event,
    // which would reset a dropdown while it is open
    readonly property string optionsKey: JSON.stringify([hue?.homeGroupedId ?? "", (hue?.rooms ?? []).map(r => [r.Id, r.Name, r.GroupedLight?.HueData?.id ?? ""]), (hue?.lights ?? []).map(l => [l.Id, l.Name])])

    onOptionsKeyChanged: rebuildOptions()
    Component.onCompleted: rebuildOptions()

    function rebuildOptions() {
        const byLabel = (a, b) => a.label.localeCompare(b.label);
        roomOptions = (hue?.rooms ?? []).map(r => ({ label: r.Name, value: r.Id })).sort(byLabel);
        const rooms = (hue?.rooms ?? []).filter(r => r.GroupedLight).map(r => ({ label: I18n.trFor("hueDirector", "Room · %1").arg(r.Name), value: "grouped_light:" + r.GroupedLight.HueData.id })).sort(byLabel);
        const lights = (hue?.lights ?? []).map(l => ({ label: I18n.trFor("hueDirector", "Light · %1").arg(l.Name), value: "light:" + l.Id })).sort(byLabel);
        const home = hue?.homeGroupedId ? [{ label: I18n.trFor("hueDirector", "All lights"), value: "grouped_light:" + hue.homeGroupedId }] : [];
        targetOptions = home.concat(rooms, lights);
    }

    // Width of the on/off buttons column (two small icon buttons)
    readonly property real actionColumnWidth: Theme.minimumTouchTargetSize * 2 + Theme.spacingL

    readonly property var events: [
        { key: "login", label: I18n.trFor("hueDirector", "Login"), def: "on" },
        { key: "logout", label: I18n.trFor("hueDirector", "Logout"), def: "off" },
        { key: "lock", label: I18n.trFor("hueDirector", "Screen locked"), def: "off" },
        { key: "unlock", label: I18n.trFor("hueDirector", "Screen unlocked"), def: "on" },
        { key: "monitorOff", label: I18n.trFor("hueDirector", "Monitors off"), def: "off" },
        { key: "monitorOn", label: I18n.trFor("hueDirector", "Monitors on"), def: "on" },
        { key: "sleep", label: I18n.trFor("hueDirector", "Suspend or hibernate"), def: "off" },
        { key: "resume", label: I18n.trFor("hueDirector", "Resume from sleep"), def: "on" },
        // Told apart from power off only on systemd >= 256 (PrepareForShutdownWithMetadata); older systems run "Power off" for both
        { key: "reboot", label: I18n.trFor("hueDirector", "Reboot"), def: "off" },
        { key: "shutdown", label: I18n.trFor("hueDirector", "Power off"), def: "off" }
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
        description: I18n.trFor("hueDirector", "Room shown in the bar pill (icon and lights on count)")
        // Room Id is stored, so renaming the room keeps the setting
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
        text: I18n.trFor("hueDirector", "System events")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: I18n.trFor("hueDirector", "Turn a light, a room or all lights on or off when something happens in your session. Logout rules need a systemd-managed session (e.g. uwsm). Before suspend and power off the system waits a few seconds for the lights to be set.")
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
                currentValue: targetLabels[Math.max(0, targetValues.indexOf(root.loadValue(targetKey, "none")))]
                onValueChanged: newValue => {
                    const i = targetLabels.indexOf(newValue);
                    if (i >= 0)
                        root.saveValue(targetKey, targetValues[i]);
                }
            }

            // Index 0 = turn on, 1 = turn off; saved like SelectionSetting does (PluginSettings.saveValue)
            DButtonGroup {
                id: actionGroup
                anchors.right: parent.right
                anchors.verticalCenter: targetSetting.verticalCenter
                iconOnly: true
                checkEnabled: false
                arrowKeysSelect: false
                size: "small"
                model: [
                    { text: I18n.trFor("hueDirector", "Turn on"), icon: "lightbulb" },
                    { text: I18n.trFor("hueDirector", "Turn off"), icon: "light_off" }
                ]
                currentIndex: root.loadValue(eventRow.actionKey, eventRow.modelData.def) === "on" ? 0 : 1
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        root.saveValue(eventRow.actionKey, index === 0 ? "on" : "off");
                }
            }
        }
    }
}
