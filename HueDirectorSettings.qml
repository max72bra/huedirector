import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "hueDirector"

    property var roomOptions: []

    Component.onCompleted: Proc.runCommand("hueDirector.settings.rooms", ["openhue", "get", "room", "--json"], (stdout, exitCode) => {
        if (exitCode !== 0)
            return;
        try {
            roomOptions = (JSON.parse(stdout) ?? []).map(r => ({ label: r.Name, value: r.Id })).sort((a, b) => a.label.localeCompare(b.label));
        } catch (e) {}
    })

    SelectionSetting {
        settingKey: "favoriteRoom"
        label: I18n.trFor("hueDirector", "Favorite room")
        description: I18n.trFor("hueDirector", "Room shown in the bar pill (icon and lights on count)")
        // Room Id is stored, so renaming the room keeps the setting
        options: [{ label: I18n.trFor("hueDirector", "All rooms"), value: "all" }].concat(root.roomOptions)
        defaultValue: "all"
    }
}
