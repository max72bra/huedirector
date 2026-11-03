# Release test checklist

Manual checks before a release. Watch the shell log for `hueDirector` errors: `/run/user/$UID/quickshell/by-id/*/log.log`. After adding or changing a `.js` file or a component used by the widget (e.g. `RoomCard.qml`), run `dms restart`: `plugins reload` keeps Qt's cached copy.

## Setup
- [ ] Fresh install: the plugin loads disabled; enabling it shows the broken-link icon and the pairing panel in the popout.
- [ ] Pairing with auto-discovery, and with a typed IP. A wrong IP shows "No Hue Bridge at this address" or "not reachable".
- [ ] Pairing timeout (button not pressed) and Cancel keep the previous pairing.
- [ ] `~/.local/state/dms/plugins/hueDirector/bridge.conf` is mode 600; `pgrep -af curl` never shows the key.
- [ ] Missing curl or openssl blocks activation with a clear message.

## Bar and popout
- [ ] Horizontal and vertical bar; two monitors (one widget per bar, actions run once).
- [ ] Light and dark theme: card tints and slider fills stay readable.
- [ ] Room toggle, brightness, "All off", room page, scene tiles (check mark follows the lights), light toggle, brightness, temperature, hue, color picker.
- [ ] Changes made from the Hue app show up within a second.
- [ ] Bridge powered off at shell start, then powered on: red icon, then normal state without restarting the shell.
- [ ] Locale switch (Settings → Locale) retranslates the plugin.
- [ ] Gradient light on: its room/zone card shows its colors along the card (mirrored style: first point in the middle), in pastel tones; no gradient light on: flat tint as before.

## Wallpaper sync (an entertainment area with a gradient strip and a plain lamp)
- [ ] Area card toggle: lights take the wallpaper edge colors at their positions, all at the slider brightness; the card shows them left to right.
- [ ] Change the wallpaper (image and solid color): lights that are on follow within ~1 s; lights that are off stay off.
- [ ] Brightness slider while syncing changes all the area's lights.
- [ ] Toggle off: every light goes back to its previous state (gradient points and style, color temperature, color, brightness, on/off). Switching to another area restores the first one.
- [ ] `syncSnapshot` missing from `~/.local/state/dms/plugins/hueDirector_state.json`: stopping applies the area's menu (off, leave, warm white, scene); the menu lists only scenes using the area's lights.
- [ ] Restore at startup on: `dms restart` resumes the sync without overwriting the saved previous state. Off: lights untouched at startup.
- [ ] Area started by the Hue Sync app: the card says it is in use and its lights are not touched.
- [ ] Remove the widget from every bar while syncing: after ~3 s the sync stops and restores the lights; `dms ipc call hueDirector sync <area>` answers that the widget is needed.
- [ ] Unreadable wallpaper (video): the card says it can't read the wallpaper after ~5 s.
- [ ] `dms ipc call hueDirector sync <area>` / `syncOff`.

## Automations (one rule per event, e.g. a test lamp)
- [ ] Login (log out and back in), Logout.
- [ ] Screen locked / unlocked.
- [ ] Monitors off / on (shell idle settings).
- [ ] Suspend / resume, hibernate.
- [ ] Reboot and power off: each runs its own rule only.
- [ ] `pgrep -af systemd-inhibit` shows the inhibitor only while a sleep, reboot or power off rule is set.

## Uninstall
- [ ] "Forget bridge" (two clicks) removes the state folder and the `hue-director-session` unit, and does not switch any light.
- [ ] With a logout rule set, disabling the plugin removes `logout.action` and stops `hue-director-session` without switching any light; `bridge.conf` stays, and re-enabling works without pairing. `dms restart` with the plugin enabled keeps `logout.action`.
- [ ] Scene tiles, room cards and light rows in a dark and a light theme: hover/press state layer, readable slider text on white and dark lights.
