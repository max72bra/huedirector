import QtQuick
import qs.Common

// Blocks activation when openhue is missing or not paired with a bridge.
// Bridge reachability is not checked: an offline bridge must not disable the plugin.
QtObject {
    function check(done) {
        Proc.runCommand("hueDirector.startupCheck", ["sh", "-c", "command -v openhue >/dev/null || exit 10; test -f \"$HOME/.openhue/config.yaml\" || exit 11"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            if (exitCode === 10) {
                done({
                    "title": I18n.trFor("hueDirector", "openhue-cli is required"),
                    "details": I18n.trFor("hueDirector", "The 'openhue' command is not installed or not on your PATH.\n\nInstall openhue-cli from https://www.openhue.io/cli, then re-enable this plugin.")
                });
                return;
            }
            done({
                "title": I18n.trFor("hueDirector", "openhue is not paired with a Hue Bridge"),
                "details": I18n.trFor("hueDirector", "Run 'openhue setup' in a terminal and press the button on your Hue Bridge when asked, then re-enable this plugin.")
            });
        });
    }
}
