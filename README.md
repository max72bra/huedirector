# Hue Director

Control your Philips Hue lights from the Dux Shell bar, powered by [openhue-cli](https://www.openhue.io/cli).

Works with Dux Shell >= 2.0.0 (formerly DankMaterialShell).

## Features

> Work in progress: the widget is under development and these features are planned.

- List rooms and lights, toggle them on and off
- Set brightness
- Set color by RGB, by name or in CIE space (x, y)
- Set color temperature (mirek)
- Activate scenes
- Live state updates from the bridge (`openhue get events`)

All bridge communication goes through the `openhue` command; the plugin talks only to your local Hue Bridge.

## Requirements

- `openhue-cli`
- A Hue Bridge paired with openhue: run `openhue setup` once (the configuration is saved in `~/.openhue/config.yaml`)

## Installation

1. Open DMS Settings → Plugins
2. Click "Scan for Plugins"
3. Browse for `Hue Director` 3rd party plugin
4. Install and enable it

Manual install: clone this repository into `~/.config/dms/plugins/hueDirector`, then scan for plugins and enable it.

## Settings

No settings yet.

## License

MIT
