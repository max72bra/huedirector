# Hue Director

Control your Philips Hue lights from the Dux Shell bar, powered by [openhue-cli](https://www.openhue.io/cli).

Works with Dux Shell >= 2.0.0 (formerly DankMaterialShell).

## Features

- **Bar pill**: lightbulb icon and number of lights on, for the whole home or a favorite room. Turns red when `openhue` fails.
- **Rooms**: turn each room on or off and set its brightness.
- **Lights**: expand a room to control each light: on/off and brightness.
- **Color**: for lights that support it, set the color temperature (in Kelvin) or pick one of 8 preset colors.
- **Scenes**: expand a room to activate one of its scenes; the active scene is highlighted.
- **Live updates**: changes made from the Hue app or switches show up right away, through the bridge event stream (`openhue get events`). If the stream fails, the plugin falls back to polling every 30 seconds.

All bridge communication goes through the `openhue` command; the plugin talks only to your local Hue Bridge.

### Known limitations

- Colors are limited to the presets; there is no free color picker yet.
- The current color of a light is not highlighted among the presets.
- The bridge event stream is an alpha feature of openhue-cli.

## Requirements

- `openhue-cli`
- A Philips Hue Bridge on the same local network

The plugin checks that `openhue` is installed when it is enabled. If it is missing, the plugin is not activated and the shell shows what to do.

## Installation

1. Open DMS Settings → Plugins
2. Click "Scan for Plugins"
3. Browse for `Hue Director` 3rd party plugin
4. Install and enable it

Manual install: clone this repository into `~/.config/dms/plugins/hueDirector`, then scan for plugins and enable it.

## Pairing with the Hue Bridge

The plugin needs to be paired with your Hue Bridge once. Keep the bridge within reach: you will have 90 seconds to press its button.

### First time

1. Add the Hue Director widget to the bar. While it is not paired, it shows a broken-link icon.
2. Click the widget to open it, then click **Pair**.
3. When the widget asks you to, press the round button on top of the Hue Bridge.
4. The widget shows "Paired with the Hue Bridge" and loads your rooms.

### Pairing again

Pair again if you reset or replaced the bridge, or if its IP address changed:

1. Open DMS Settings → Plugins → Hue Director.
2. Under **Hue Bridge**, click **Pair again** and press the bridge button.

The current pairing is replaced only if the new one succeeds. If you cancel, or the button is not pressed in time, nothing changes.

### If the bridge is not found

The plugin looks for the bridge on your network automatically. If it can't find it, enter the bridge IP address in the **Bridge IP address** field before clicking Pair. The Hue app shows it under Settings → Bridges.

### From a terminal

Run `openhue setup`, or `openhue setup -b <bridge IP>`, then press the bridge button. The configuration is saved in `$XDG_CONFIG_HOME/openhue/config.yaml`, or in `~/.openhue/config.yaml` when `XDG_CONFIG_HOME` is not set.

## Settings

- **Hue Bridge**: shows the paired bridge and lets you pair again.
- **Favorite room**: room shown in the bar pill (icon and number of lights on). Default: all rooms.

## License

MIT
