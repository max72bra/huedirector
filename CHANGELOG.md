# Changelog

## 1.2.0

- Identify: a button on each light pulses its brightness twice in 2.5 s, then restores it, to find it.
- Light effects (candle, fireplace, prism, sparkle, opal, glisten, underwater, cosmos, sunbeam, enchant) and timed sunrise/sunset, in the light's color controls.
- Smart scenes (a different scene for each time of day) appear among the room's scenes with a clock badge; click to start or stop them.
- Dynamic scene speed setting (scene default, slow, medium, fast).

## 1.1.0

- Unreachable lights (unplugged or out of zigbee range) are marked in the light rows and counted on the room cards.
- Dynamic scenes: scenes with a color palette get a play/pause button to cycle their colors.
- Fade time setting for turning lights on/off and changing scene (instant to 4 s, or the bridge default).
- Command line and keybindings: `dms ipc call hueDirector toggle | on <target> | off <target> | scene <name>`.

## 1.0.0

First release.

- Bar widget: lights-on count (optional) and state icon for the whole home or a favorite room; right-click toggles a favorite light, room or all lights.
- Popout: tinted room cards with brightness, a room page with scene tiles painted with the scene colors, and per-light controls (brightness, color temperature, hue slider, shell color picker). "All off" button and a shortcut to the plugin settings.
- The current scene is recognized from the lights' state, also after the bridge marks it inactive.
- Live updates through the bridge event stream, with polling as a fallback.
- System event automations: login, logout, screen lock/unlock, monitors off/on, suspend/resume, reboot, power off.
- Direct Hue API v2 client over curl: in-shell pairing with bridge discovery (mDNS or discovery.meethue.com), bridge public key pinning, key stored in a private file and never passed on a command line. "Forget bridge" removes everything from this computer.
- Translations: English, French, German, Italian, Japanese, Korean, Simplified Chinese, Spanish.
