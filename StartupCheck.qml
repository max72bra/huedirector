import QtQuick
import qs.Common

// Blocks activation only when curl or openssl is missing (HueBridge.qml needs both).
// Pairing is not checked: the settings page exists only while the plugin is loaded,
// so an unpaired plugin must load to offer pairing (popout and settings, PairingPanel.qml).
QtObject {
    function check(done) {
        Proc.runCommand("hueDirector.startupCheck", ["sh", "-c", "for c in curl openssl; do command -v $c >/dev/null || echo $c; done"], (stdout, exitCode) => {
            const missing = stdout.trim().split("\n").filter(s => s);
            if (missing.length === 0) {
                done(null);
                return;
            }
            done({
                "title": I18n.trFor("hueDirector", "Missing: %1").arg(missing.join(", ")),
                "details": I18n.trFor("hueDirector", "Hue Director talks to the Hue Bridge with curl and checks its certificate with openssl.\n\nInstall the missing packages with your package manager, then re-enable this plugin.")
            });
        });
    }
}
