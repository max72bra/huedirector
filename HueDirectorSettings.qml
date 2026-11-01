import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "."

PluginSettings {
    id: root
    pluginId: "hueDirector"

    property var roomOptions: []

    function loadRooms() {
        if (!hueBridge.configured)
            return;
        hueBridge.fetchAll((result, err) => {
            if (!err)
                roomOptions = result.rooms.map(r => ({ label: r.Name, value: r.Id })).sort((a, b) => a.label.localeCompare(b.label));
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
}
