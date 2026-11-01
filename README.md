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
- A Hue Bridge paired with openhue: run `openhue setup` once (the configuration is saved in `~/.openhue/config.yaml`)

The plugin checks both when it is enabled. If one is missing, it is not activated and the shell shows what to do.

## Installation

1. Open DMS Settings → Plugins
2. Click "Scan for Plugins"
3. Browse for `Hue Director` 3rd party plugin
4. Install and enable it

Manual install: clone this repository into `~/.config/dms/plugins/hueDirector`, then scan for plugins and enable it.

## Settings

- **Favorite room**: room shown in the bar pill (icon and number of lights on). Default: all rooms.

## License

MIT
