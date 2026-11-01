# Changelog

## 1.0.0

First release.

- Bar widget: lights-on count (optional) and state icon for the whole home or a favorite room; right-click toggles a favorite light, room or all lights.
- Popout: tinted room cards with brightness, a room page with scene tiles painted with the scene colors, and per-light controls (brightness, color temperature, hue slider, shell color picker). "All off" button and a shortcut to the plugin settings.
- The current scene is recognized from the lights' state, also after the bridge marks it inactive.
- Live updates through the bridge event stream, with polling as a fallback.
- System event automations: login, logout, screen lock/unlock, monitors off/on, suspend/resume, reboot, power off.
- Direct Hue API v2 client over curl: in-shell pairing with bridge discovery (mDNS or discovery.meethue.com), bridge public key pinning, key stored in a private file and never passed on a command line. "Forget bridge" removes everything from this computer.
- Translations: English, French, German, Italian, Japanese, Korean, Simplified Chinese, Spanish.
