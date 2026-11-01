import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "."

PluginSettings {
    id: root
    pluginId: "hueDirector"

    property var roomOptions: []
    // Targets for the system event rules, values as read by HueEvents.rule()
    property var targetOptions: []
    // Width of the on/off buttons column (two small icon buttons)
    readonly property int actionColumnWidth: 112

    readonly property var events: [
        { key: "login", label: I18n.trFor("hueDirector", "Login"), def: "on" },
        { key: "logout", label: I18n.trFor("hueDirector", "Logout"), def: "off" },
        { key: "lock", label: I18n.trFor("hueDirector", "Screen locked"), def: "off" },
        { key: "unlock", label: I18n.trFor("hueDirector", "Screen unlocked"), def: "on" },
        { key: "sleep", label: I18n.trFor("hueDirector", "Suspend or hibernate"), def: "off" },
        { key: "resume", label: I18n.trFor("hueDirector", "Resume from sleep"), def: "on" },
        // Told apart from power off only on systemd >= 256 (PrepareForShutdownWithMetadata); older systems run "Power off" for both
        { key: "reboot", label: I18n.trFor("hueDirector", "Reboot"), def: "off" },
        { key: "shutdown", label: I18n.trFor("hueDirector", "Power off"), def: "off" }
    ]

    function loadRooms() {
        if (!hueBridge.configured)
            return;
        hueBridge.fetchAll((result, err) => {
            if (err)
                return;
            const byLabel = (a, b) => a.label.localeCompare(b.label);
            roomOptions = result.rooms.map(r => ({ label: r.Name, value: r.Id })).sort(byLabel);
            const rooms = result.rooms.filter(r => r.GroupedLight).map(r => ({ label: I18n.trFor("hueDirector", "Room · %1").arg(r.Name), value: "grouped_light:" + r.GroupedLight.HueData.id })).sort(byLabel);
            const lights = result.lights.map(l => ({ label: I18n.trFor("hueDirector", "Light · %1").arg(l.Name), value: "light:" + l.Id })).sort(byLabel);
            const home = result.homeGroupedId ? [{ label: I18n.trFor("hueDirector", "All lights"), value: "grouped_light:" + result.homeGroupedId }] : [];
            targetOptions = home.concat(rooms, lights);
        });
    }

    HueBridge {
        id: hueBridge
        onConfigChanged: root.loadRooms()
    }

    StyledText {
        text: I18n.trFor("hueDirector", "Hue Bridge")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    // Pairing reloads the bridge config, which reloads the rooms through onConfigChanged
    PairingPanel {
        bridge: hueBridge
    }

    SelectionSetting {
        settingKey: "favoriteRoom"
        label: I18n.trFor("hueDirector", "Favorite room")
        description: I18n.trFor("hueDirector", "Room shown in the bar pill (icon and lights on count)")
        // Room Id is stored, so renaming the room keeps the setting
        options: [{ label: I18n.trFor("hueDirector", "All rooms"), value: "all" }].concat(root.roomOptions)
        defaultValue: "all"
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

            SelectionSetting {
                id: targetSetting
                width: parent.width - root.actionColumnWidth - Theme.spacingM
                settingKey: "event_" + eventRow.modelData.key + "_target"
                label: eventRow.modelData.label
                // "none" instead of "": SelectionSetting saves the label when the value is empty
                options: [{ label: I18n.trFor("hueDirector", "Nothing"), value: "none" }].concat(root.targetOptions)
                defaultValue: "none"
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
