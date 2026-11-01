import QtQuick
import qs.Common

// Blocks activation only when openhue is missing.
// Pairing is not checked: the settings page exists only while the plugin is loaded,
// so an unpaired plugin must load to offer pairing (popout and settings, PairingPanel.qml).
QtObject {
    function check(done) {
        Proc.runCommand("hueDirector.startupCheck", ["sh", "-c", "command -v openhue"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": I18n.trFor("hueDirector", "openhue-cli is required"),
                "details": I18n.trFor("hueDirector", "The 'openhue' command is not installed or not on your PATH.\n\nInstall openhue-cli from https://www.openhue.io/cli, then re-enable this plugin.")
            });
        });
    }
}
