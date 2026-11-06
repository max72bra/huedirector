# Hue Director

Control your Philips Hue lights from the Dux Shell bar. Hue Director talks directly to your Hue Bridge on the local network (Hue API v2).

Works with Dux Shell >= 2.0.0 (formerly DankMaterialShell).

![Hue Director popout: room cards tinted with the lights' color, brightness sliders, settings and all-off buttons](screenshot.png)

## Features

### In the bar
- **Status icon** for the whole home or a favorite room or zone: a lit bulb and the number of lights on (the number can be hidden), an off bulb when everything is off, a broken link when not paired, red when the bridge can't be reached.
- **Right-click** turns your favorite light, room, zone or all lights on or off.

### In the popout
- **Room cards**: icon from the room type set in the Hue app, how many lights are on, brightness, an on/off switch and a brightness slider. Each card is tinted with the current color of its lights; with a gradient light on, the card shows its colors side by side, in soft pastel tones. The header shows how many lights are on, in a chip tinted with their color: click it to turn off every light in the home. Another button opens the plugin settings.
- **Zone cards**: zones from the Hue app (groups of lights across rooms) get the same cards, in their own section below the rooms, and the same page.
- **Entertainment area cards**: a switch that makes the area's lights continue the wallpaper beyond the screen, and one brightness slider for all of them. The card shows each light's color at its place in the area. See [Wallpaper sync](#wallpaper-sync).
- **Room page** (click a card):
  - **Scenes** as tiles painted with each scene's own colors. The current scene is marked, also when the bridge no longer reports it active (it is recognized from the lights' state).
  - **Dynamic scenes**: scenes with a color palette have a play button that keeps their colors slowly cycling.
  - **Smart scenes** (a different scene for each time of day, from the Hue app) are marked with a clock; click to start or stop them.
  - **Effect** for the whole room: one menu with every effect its lights support (candle, fireplace, ..., sunrise, sunset), applied to each light that has it.
  - **Lights**: switch, brightness, and a mark on unreachable lights (unplugged or out of range).
- **Light controls** (palette button on a light): color temperature in Kelvin, a rainbow hue slider, the shell color picker for any exact color (hex, color area, eyedropper, recent colors), and a menu of light effects (candle, fireplace, prism, sparkle, ...) with a 30-minute sunrise or sunset.
- **Gradient lights** (lightstrips, Play gradient, ...): one color for each point the light supports (5 on current models), each set with the color picker, and the gradient style (blend, mirrored blend, scattered, segments) when the light offers more than one.
- **Identify**: makes a light pulse its brightness twice in 2.5 seconds, then restores it, so you can tell which lamp it is.

### Session events
- Turn a light, a room, a zone or all lights on or off when you **log in or out**, **lock or unlock** the screen, when the **monitors turn off or on**, on **suspend and resume**, on **reboot** and on **power off**. See [Automations](#automations).

### Everywhere
- **Live updates**: changes made from the Hue app or from switches show up within a second, through the bridge event stream; if the stream fails, the plugin polls every 30 seconds.
- **Fade time** for switching lights and scenes, and **dynamic scene speed**, in the settings.
- **Command line and keybindings**: `dms ipc call hueDirector toggle | on | off | brightness | effect | scene | sync | syncOff`. See [Command line and keybindings](#command-line-and-keybindings).
- **One connection to the bridge** for the whole shell, also with a bar on every monitor.
- **No external Hue tools**: the plugin talks to the bridge directly (Hue API v2), with in-shell pairing and certificate pinning.
- **Translations**: English, French, German, Italian, Japanese, Korean, Russian, Simplified Chinese, Spanish.

The plugin talks only to your Hue Bridge. The only internet request is bridge discovery through `discovery.meethue.com`, and only when the bridge isn't found on the local network.

### Known limitations

- The hue slider sets fully saturated colors; use the color picker for pastel tones.
- Colors shown on screen are an approximation: Hue lamps can produce colors a monitor can't display.
- Hue Bridge v1 (the round first-generation bridge) is not supported: it has no API v2.
- Wallpaper sync reads the whole image: with a wallpaper cropped to fill the screen, the edge colors can come from a part you don't see. Video wallpapers can't be read.

## Requirements

- `curl` and `openssl`
- A Philips Hue Bridge (second generation or Bridge Pro) on the same local network
- For the wallpaper sync: an entertainment area set up in the Hue app, and the Hue Director widget on a bar
- Optional: `avahi` (`avahi-browse`), to find the bridge on the local network without going through `discovery.meethue.com`

Automations also use `systemd-inhibit`, `systemd-run` and `busctl` (part of systemd) and `gdbus` (part of glib2, already installed with Dux Shell). See [What runs in the background](#what-runs-in-the-background).

The plugin checks for `curl` and `openssl` when it is enabled. If one is missing, the plugin is not activated and the shell shows what to do.

## Installation

1. Open Settings → Plugins and click **Browse**.
2. Find **Hue Director**, then install and enable it.
3. Add the Hue Director widget to the bar.

Or from a terminal: `dms plugins install hueDirector`.

## Pairing with the Hue Bridge

The plugin needs to be paired with your Hue Bridge once. Keep the bridge within reach: you will have 90 seconds to press its button.

### First time

1. Enable the plugin and add the Hue Director widget to the bar. While it is not paired, it shows a broken-link icon.
2. Click the widget to open it, then click **Pair**.
3. When the widget asks you to, press the round button on top of the Hue Bridge. Pairing keeps going if the popout closes while you walk to the bridge.
4. Once paired, the popout shows your rooms.

### Pairing again

Pair again if you reset or replaced the bridge, or if its IP address changed. If the bridge answering on the saved address isn't the one you paired with, the popout shows the pairing panel by itself.

1. Open DMS Settings → Plugins → Hue Director.
2. Under **Hue Bridge**, click **Pair again** and press the bridge button.

The current pairing is replaced only if the new one succeeds. If you cancel, or the button is not pressed in time, nothing changes.

### If the bridge is not found

The plugin looks for the bridge on your network automatically. If it can't find it, enter the bridge IP address in the **Bridge IP address** field before clicking Pair. The Hue app shows it in the bridge's settings; your router's list of connected devices shows it too.

### Security and privacy

- The pairing key is stored in the Dux Shell state folder (`~/.local/state/dms/plugins/hueDirector/bridge.conf`, readable only by you). It is never passed on a command line.
- The bridge certificate is checked on every request: at pairing, the plugin remembers the bridge's public key and rejects any other device that answers on its address. If you replace the bridge, pair again.

## Automations

In Settings → Plugins → Hue Director → **System events**, pick for each event what to switch (nothing, all lights, a room or a light) and whether to turn it on or off.

| Event | How it is detected |
|---|---|
| Login | The shell starts within 2 minutes of the session start (restarting the shell later doesn't count) |
| Screen locked / unlocked | Dux Shell lock screen |
| Monitors off / on | Dux Shell power saving turning the monitors off (DPMS) and back on. Monitors turned off by other tools (e.g. hypridle) are not detected |
| Suspend or hibernate / Resume | Suspend started from Dux Shell (power menu, idle): when the shell requests it, while the network is still up. The system suspends as soon as the rule has been sent. Other suspends (lid, terminal): logind sleep signal, which may be too late, since NetworkManager takes the network down at the same moment; the system waits up to 5 seconds for the rule (logind `InhibitDelayMaxSec`). On resume the rule retries for up to 30 seconds until the network is back |
| Power off / Reboot | logind shutdown signal: the system waits until the rule has run, at most 5 seconds. Power off and reboot are told apart on systemd 256 or newer; on older systems the Power off rule runs for both |
| Logout | A small user service bound to `graphical-session.target` runs the action when the session ends. It needs a systemd-managed session (e.g. uwsm); otherwise logout rules don't run. Power off and reboot end the session too, but run only their own rules |

### What runs in the background

All of them run as you. The first three run inside the Dux Shell service and stop with it:

| Process | When | What for |
|---|---|---|
| `curl ... /eventstream/clip/v2` | While paired | Bridge event stream (live updates). The key is read from `bridge.conf`, never from the command line |
| `gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1` | Always | Reads the logind sleep and shutdown signals (`PrepareForSleep`, `PrepareForShutdown`). It only listens and needs no privileges; at start, `gdbus introspect` checks once whether logind can tell reboot from power off. Started again after 5 seconds if it exits |
| `systemd-inhibit --what=sleep:shutdown --mode=delay ... sleep infinity` | While a suspend, reboot, power off or logout rule is set | Asks logind to wait (at most 5 seconds) before suspending or powering off, so the rule reaches the bridge (with a logout rule: so the logout action knows it must stay quiet). Released as soon as the rule has run. Listed by `systemd-inhibit --list` as "Hue Director" |
| `hue-director-session` (user service) | While a logout rule is set | A separate user service: runs the logout action when the session ends, after the shell has already stopped |

The login rule reads the session start time once from logind, with `busctl`.

## Wallpaper sync

The lights of a Hue entertainment area continue the wallpaper beyond the screen: a lamp on the left takes the color of the wallpaper's left edge, a lightstrip behind the monitor follows the edges all around it.

1. In the Hue app, create an entertainment area and place its lights around the screen (Settings → Entertainment areas).
2. In the popout, turn on the area's card under **Entertainment areas**. The slider sets the brightness of all its lights.

How it works:
- The positions come from the entertainment area: left to right and bottom to top. Each light takes the dominant color of the wallpaper region at its position (vivid colors win over large dull areas). Gradient lightstrips have one position per segment, so they get several colors along the strip.
- Only the color comes from the wallpaper: every light uses the slider's brightness, so dark wallpaper regions don't dim the lights.
- When the wallpaper changes, the lights that are on follow it after about a second.
- Only one area syncs at a time. An area that another app is using (Hue Sync, a TV box) is left alone.
- The commands go over the normal Hue API: the entertainment area is only used as a map of positions, it is never started and nothing is streamed.
- When the sync stops, or moves to another area, each light goes back to how it was before: on or off, brightness, and its gradient, color temperature or color. A running effect or dynamic scene is not started again. If the previous state is not known, the area's menu in the settings decides (see [Settings](#settings)).
- The wallpaper is read by the Hue Director widget on the bar: the image is scaled down by Qt in the widget, so no external tool is needed. Without the widget on any bar the sync can't run: it does not start, and it stops a few seconds after the last widget is removed.

## Settings

- **Hue Bridge**: shows the paired bridge and lets you pair again.
- **Favorite room**: room or zone shown in the bar pill (icon and number of lights on). Default: all rooms.
- **Fade time**: how long lights take to turn on or off and to change scene: the bridge default (0.4 s), instant, 1, 2 or 4 seconds. Brightness and color sliders are not faded.
- **Dynamic scene speed**: how fast colors cycle when you play a dynamic scene. The speed is saved in the scene on the bridge, so the Hue app uses it too.
- **Show lights on count**: number next to the bar icon. Turn it off to keep only the icon, which still changes with the lights' state. Default: on.
- **Favorite light**: a light, a room, a zone or all lights. Right-click the bar icon to turn it on or off.
- **Wallpaper sync**:
  - **Restore wallpaper sync at startup**: when the shell starts, the sync starts again on the entertainment area where it was on. Default: off.
  - **Wallpaper sync monitor**: shown only with a different wallpaper per monitor; the monitor whose wallpaper the lights follow.
  - One menu per entertainment area: what to do when the sync stops and the lights' state before it is not known: turn the area's lights off (default), leave them as they are, warm white (2700 K at the area's sync brightness), or activate one of the scenes that use the area's lights.
- **System events**: the automations described above.

## Command line and keybindings

The plugin answers `dms ipc` calls, so you can bind lights to keys:

| Command | Effect |
|---|---|
| `dms ipc call hueDirector toggle` | Toggles the favorite light (Settings → Favorite light) |
| `dms ipc call hueDirector on <target>` | Turns on `all`, a room, a zone or a light, by name (rooms win over zones with the same name) |
| `dms ipc call hueDirector off <target>` | Turns it off |
| `dms ipc call hueDirector brightness <target> <value>` | Sets the brightness: `50` (turns the target on), `+10` or `-- -10` (relative; a step up turns on a target that is off, a step down leaves it off) |
| `dms ipc call hueDirector effect <target> <name>` | Starts an effect on each light of the target that supports it: `candle`, `fire`, `prism`, `sparkle`, `opal`, `glisten`, `underwater`, `cosmos`, `sunbeam`, `enchant`, `sunrise`, `sunset`; `off` stops it. `all` means every room |
| `dms ipc call hueDirector scene <name>` | Activates a scene; use `Room/Scene` (or `Zone/Scene`) when several rooms or zones have a scene with that name |
| `dms ipc call hueDirector sync <area>` | Starts the [wallpaper sync](#wallpaper-sync) on an entertainment area, by name |
| `dms ipc call hueDirector syncOff` | Stops the wallpaper sync |

Names are case-insensitive; quote names with spaces. A negative step needs `--` before it, or `dms` reads it as an option. Example for Hyprland:

```
bind = SUPER, L, exec, dms ipc call hueDirector toggle
bind = SUPER SHIFT, L, exec, dms ipc call hueDirector scene "Studio/Relax"
bind = SUPER, Prior, exec, dms ipc call hueDirector brightness Studio +10
bind = SUPER, Next, exec, dms ipc call hueDirector brightness Studio -- -10
```

Each call answers `ok`, or says what is wrong (e.g. `no scene named Relax`, `not paired`).

The mouse wheel on the bar widget's icon changes the brightness of the favorite light by 10% per notch. With no favorite set, the wheel keeps its usual bar behavior.

## Uninstall

1. Open Settings → Plugins → Hue Director and click **Forget bridge** twice. This removes the pairing key, the logout action and the `hue-director-session` user service from this computer.
2. Disable and uninstall the plugin in Settings → Plugins.

Disabling the plugin alone also removes the logout action and the user service, but keeps the pairing key, so the plugin works again as soon as it is enabled.

If the plugin is already gone, remove the leftovers by hand:

```sh
rm -f ~/.local/state/dms/plugins/hueDirector/logout.action
systemctl --user stop hue-director-session
rm -rf ~/.local/state/dms/plugins/hueDirector
```

Remove `logout.action` before stopping the service: stopping it runs the logout action.

The bridge may still list Hue Director among its connected apps.

## Translations

The interface is in English and follows the Dux Shell language (Settings → Locale). Available translations: French, German, Italian, Japanese, Korean, Russian, Simplified Chinese and Spanish (`translations/`). They were machine-assisted: corrections from native speakers are welcome.

To add a language, copy `translations/it.json` to `translations/<locale>.json` (e.g. `de.json`, `pt_BR.json`) and translate the values. Each key is the English text; placeholders like `%1` must stay in the translation. Missing terms fall back to English. Reload with `dms ipc call plugins reload hueDirector`.

Room, zone, light and scene names come from your Hue Bridge and are shown as they are.

## Credits

Hue Director is written by Massimo Branchini (maxb) together with Claude (Anthropic), used through Claude Code as an AI co-author: much of the code and documentation was generated with it, then reviewed and tested on real hardware by the author.

## License

MIT
