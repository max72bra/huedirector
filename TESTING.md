# Release test checklist

Manual checks before a release. Watch the shell log for `hueDirector` errors: `/run/user/$UID/quickshell/by-id/*/log.log`.

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
