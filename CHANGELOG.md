# Changelog

## 1.6.3

- The cursor on the bar widget's icon and count is a pointing hand again (it had become an arrow in 1.6.0).

## 1.6.2

- New event rules: night mode on, night mode off and user idle. Fullscreen and excluded apps pausing night mode don't run them.
- New rule action: warm white (2700 K), on every event.
- User idle can dim: each light that is on goes to a share of its own brightness (Settings → Dim to, default 30%) and returns when you are back, unless it was changed meanwhile. Settings → Idle after sets the wait, default 5 minutes.

## 1.6.1

- Effects from keybindings: `dms ipc call hueDirector effect <target> <name>` starts an effect on a light, room, zone or `all` (every room), `off` stops it. Lights without that effect or in use by another app are skipped.

## 1.6.0

- Brightness from keybindings and the bar: `dms ipc call hueDirector brightness <target> <value>` takes `50`, `+10` or `-- -10`, and the mouse wheel on the widget's icon changes the favorite light by 10% per notch. Fast notches are sent as one request. A step up turns on a target that is off; lights in use by another app are skipped.

## 1.5.6

- Room and zone pages have an Effect menu: it lists every effect the room's lights support and applies the chosen one to each light that has it (the bridge ignores effects sent to a whole room). Lights in use by another app are skipped. It shows the running effect when all the lights share it, otherwise "No effect"; choosing "No effect" stops them all.

## 1.5.5

- The login rule also runs when the computer was suspended before logging in (the time spent suspended was counted as time since login).
- A logout rule no longer runs, now and then, on power off or reboot.
- Two requests on the same light no longer answer each other: a power off rule could let the system go before its command had reached the bridge. An older bridge state no longer replaces a newer one for a moment.
- Changes from the bridge (Hue app, switches, sliders) are applied without reading the whole bridge again, which only happens when lights, rooms or scenes are added or removed.
- Settings: lights, rooms, zones or scenes with the same name get a number, so each can be picked; the logout service is set up again only when the logout rule changes.

## 1.5.4

- Suspend, resume, reboot and power off rules run reliably again: the logind signals are now read by the plugin itself with `gdbus monitor` (glib2, already installed with the shell), because the Dux Shell server didn't always pass them on. When that happened, the system waited 5 seconds before suspending or powering off, and the resume rule didn't run.
- Suspend started from the shell no longer waits 5 seconds: the system suspends as soon as the rule has been sent.

## 1.5.3

- While another app (Hue Sync, a TV box) streams to an entertainment area, its card and the rows of its lights are disabled and say "In use by another app"; event rules, IPC calls and the bar right click aimed at those lights are skipped, and the wallpaper sync leaves them alone. Everything comes back when the stream stops. Rooms, zones and scenes keep working for the other lights.

## 1.5.2

- Tooltips on the icons of scene tiles (active, smart scene, dynamic/pause) and of the light color controls (warm, cool, gradient).

## 1.5.1

- Adding a reboot or power off rule while a suspend rule exists (or the other way round) now takes effect at once, without restarting the shell.
- Wallpaper sync: moving between two entertainment areas that share a light restores that light to how it was before the first sync, not to the wallpaper colors; a wallpaper change is no longer skipped when a bridge update arrives while it is read; no false "Can't read the wallpaper" when a new read replaces a pending one.
- Picking black in the color picker sets the darkest color instead of doing nothing.
- Smart scenes are sorted by name, so their tiles no longer move around.
- Automated checks for the wallpaper sampling (`node tests/wallpaper-sync.test.js`).

## 1.5.0

- Wallpaper sync: "Entertainment areas" cards in the popout. The switch makes the area's lights continue the wallpaper beyond the screen, each light with the dominant color of the wallpaper where it stands (gradient strips get one color per segment); the slider sets one brightness for all of them. Stopping the sync puts the lights back as they were (if that is unknown, a per-area setting turns them off, leaves them, sets warm white or activates one of the scenes using them). Follows wallpaper changes, skips areas used by another app, can restart with the shell (Settings), and has `sync` / `syncOff` IPC calls. The wallpaper is read by the bar widget with no external tools, so the sync needs the widget on a bar.
- Cards with a gradient light on show its colors along the card in soft pastel tones, in place of the flat tint; entertainment area cards place each light's color at its position in the area.
- Better contrast in light and dark themes: icons, slider fills and the header chip tinted with a light's color reach at least 3:1 (WCAG) against what they are drawn on, room and light icons included on their colored bubble.

## 1.4.0

- Gradient lights: edit each of the colors along the light (as many as the light supports) and pick the gradient style.
- The color picker no longer closes the popout.

## 1.3.0

- Zones: zone cards and pages in the popout, below the rooms; zones as favorite room, favorite light, event rule targets and IPC names.
- The popout header has the title, the settings button and a chip with the lights on (tinted with their color) that turns all lights off, in one row aligned with the cards; "Rooms" and "Zones" section titles; a line under the header shows only while the page scrolls.

## 1.2.7

- Russian translation.

## 1.2.6

- The bar icon follows the bar's icon size and scale, the initial popout height comes from the theme's size tokens, and the room card color fade follows the shell's animation speed.
- The description says that pairing uses avahi-browse when installed.

## 1.2.5

- Disabling or uninstalling the plugin removes the logout action and stops the `hue-director-session` unit, so the logout rule no longer fires at the end of that session. The pairing is kept for when the plugin is enabled again.
- Scene tiles use the shell's state layer for hover and press (with ripple), and the theme's scrim and on-colors instead of fixed black and white.
- Slider text on colored fills picks the more readable of the theme's text and surface colors.
- Sizes of tiles, icon bubbles, settings columns and the popout come from the theme's size tokens.
- The description says that pairing may look the bridge up through `discovery.meethue.com`.

## 1.2.4

- Power off and reboot rules survive logout scripts that kill the user's processes before calling `systemctl poweroff`/`reboot`: the lock that makes the system wait for the lights is started again if its process is killed.
- The shell log shows when power off/reboot are being watched and when logind's signal arrives.

## 1.2.3

- System event targets in the settings are saved again and show the stored value: as dropdowns nested in a list they were neither reloaded nor able to reach the page to save on.
- Suspend rule works: NetworkManager takes the network down as soon as logind announces the sleep, so the rule now runs when the shell starts the suspend (power menu, idle), while the network is still up. Suspends started elsewhere (lid, terminal) still run on logind's signal.
- Suspend/resume are watched directly on logind (PrepareForSleep) instead of through the shell's lock settings.
- Resume rule retries for up to 30 seconds until the network and the bridge are back.
- Sleep and power off rules skip the 300 ms command delay; every system event is written to the shell log with its outcome.

## 1.2.2

- Pairing runs in the daemon: it keeps going if the popout closes while you walk to the bridge, and the popout and the settings page show the same pairing instead of being able to start two.
- "Forget bridge" also clears the old rooms and lights from the settings and the IPC commands.
- Settings dropdowns are rebuilt only when rooms or lights are added, removed or renamed, not on every light change.

## 1.2.1

- One connection to the bridge for the whole shell: state, event stream, polling and commands moved to the daemon, shared by every bar (multi-monitor) and by the settings page.
- Unreachable lights no longer count as on (bar count, "lights on" summary, all-off button, room color, favorite toggle).
- Quick commands on the same light (e.g. screen lock then suspend) no longer lose their confirmation, which could delay suspend by up to 5 seconds.
- Partial bridge errors (HTTP 207) are reported instead of ignored.
- Identify on a light that is off keeps its brightness for the next switch-on, and no longer refetches the whole state at every step.
- IPC calls answer with the outcome (`ok`, `no scene named …`, `not paired`).
- An offline bridge is logged once, not at every poll; the event stream restarts at once after a new pairing.

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
