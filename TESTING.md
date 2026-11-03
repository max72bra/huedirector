# Release test checklist

Manual checks before a release. Watch the shell log for `hueDirector` errors: `/run/user/$UID/quickshell/by-id/*/log.log`. After adding or changing a `.js` file or a component used by the widget (e.g. `RoomCard.qml`), run `dms restart`: `plugins reload` keeps Qt's cached copy.

Automated checks for the wallpaper sampling: `node tests/wallpaper-sync.test.js`.

## Setup
- [x] Fresh install: the plugin loads disabled; enabling it shows the broken-link icon and the pairing panel in the popout.
- [x] Pairing with auto-discovery, and with a typed IP. A wrong IP shows "No Hue Bridge at this address" or "not reachable".
- [x] Pairing timeout (button not pressed) and Cancel keep the previous pairing.
- [x] `~/.local/state/dms/plugins/hueDirector/bridge.conf` is mode 600; `pgrep -af curl` never shows the key.
- [x] Missing curl or openssl blocks activation with a clear message.

## Bar and popout
- [x] Horizontal and vertical bar; two monitors (one widget per bar, actions run once).
- [x] Light and dark theme: card tints and slider fills stay readable.
- [x] Room toggle, brightness, "All off", room page, scene tiles (check mark follows the lights), light toggle, brightness, temperature, hue, color picker.
- [x] Changes made from the Hue app show up within a second.
- [x] Bridge powered off at shell start, then powered on: red icon, then normal state without restarting the shell.
- [x] Locale switch (Settings → Locale) retranslates the plugin.
- [x] Gradient light on: its room/zone card shows its colors along the card (mirrored style: first point in the middle), in pastel tones; no gradient light on: flat tint as before.

## Wallpaper sync (an entertainment area with a gradient strip and a plain lamp)
- [x] Area card toggle: lights take the wallpaper edge colors at their positions, all at the slider brightness; the card shows them left to right.
- [x] Change the wallpaper (image and solid color): lights that are on follow within ~1 s; lights that are off stay off.
- [x] Brightness slider while syncing changes all the area's lights.
- [x] Toggle off: every light goes back to its previous state (gradient points and style, color temperature, color, brightness, on/off). Switching to another area restores the first one.
- [x] `syncSnapshot` missing from `~/.local/state/dms/plugins/hueDirector_state.json`: stopping applies the area's menu (off, leave, warm white, scene); the menu lists only scenes using the area's lights.
- [x] Restore at startup on: `dms restart` resumes the sync without overwriting the saved previous state. Off: lights untouched at startup.
- [x] Area started by the Hue Sync app: the card says it is in use and its lights are not touched.
- [x] While another app streams to an area: its card (switch, slider) and the rows of its lights are disabled and say "In use by another app"; room cards and the other lights still work. `dms ipc call hueDirector on <streamed light>` and `sync <area>` answer "in use by another app"; an event rule on that light is skipped (log). Stopping the stream re-enables everything within ~1 s.
- [x] Remove the widget from every bar while syncing: after ~3 s the sync stops and restores the lights; `dms ipc call hueDirector sync <area>` answers that the widget is needed.
- [x] Unreadable wallpaper (video): the card says it can't read the wallpaper after ~5 s.
- [x] `dms ipc call hueDirector sync <area>` / `syncOff`.

## Automations (one rule per event, e.g. a test lamp)
- [x] Login (log out and back in), Logout.
- [x] Screen locked / unlocked.
- [x] Monitors off / on (shell idle settings).
- [x] Suspend / resume, hibernate.
- [x] Reboot and power off: each runs its own rule only.
- [x] `pgrep -af systemd-inhibit` shows the inhibitor only while a sleep, reboot or power off rule is set.

## Uninstall
- [x] "Forget bridge" (two clicks) removes the state folder and the `hue-director-session` unit, and does not switch any light.
- [x] With a logout rule set, disabling the plugin removes `logout.action` and stops `hue-director-session` without switching any light; `bridge.conf` stays, and re-enabling works without pairing. `dms restart` with the plugin enabled keeps `logout.action`.
- [x] Scene tiles, room cards and light rows in a dark and a light theme: hover/press state layer, readable slider text on white and dark lights.
