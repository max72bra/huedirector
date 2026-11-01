import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "Accent.js" as Accent

// Room page row for a light: icon, name, toggle and brightness.
// The palette button asks to expand the color controls. The card itself is not clickable:
// a whole-card hover/press highlight looked like a stuck background color
DCard {
    id: row

    // Light in the shape built by HueBridge.normalize()
    property var light: null
    property string icon: "lightbulb"
    // Current color as [r, g, b] (HueDirector.lightRgb), null when off or unknown
    property var currentRgb: null
    property bool expanded: false

    readonly property var hd: light?.HueData ?? null
    readonly property bool isOn: hd?.on?.on ?? false
    // Unplugged or out of zigbee range: the bridge still reports the last known state
    readonly property bool reachable: light?.Reachable ?? true
    readonly property var colorTemp: hd?.color_temperature ?? null
    readonly property bool hasColor: !!hd?.color
    // Effects the light supports, then the timed ones (sunrise/sunset), "no_effect" first
    readonly property var timedEffects: (hd?.timed_effects?.effect_values ?? []).filter(e => e !== "no_effect")
    readonly property var effectValues: {
        const regular = (hd?.effects?.effect_values ?? []).filter(e => e !== "no_effect");
        return regular.length || timedEffects.length ? ["no_effect"].concat(regular, timedEffects) : [];
    }
    readonly property string currentEffect: {
        const timed = hd?.timed_effects?.status ?? "no_effect";
        return timed !== "no_effect" ? timed : (hd?.effects?.status ?? "no_effect");
    }
    readonly property bool hasColorControls: hasColor || !!colorTemp || effectValues.length > 0
    readonly property color accentColor: currentRgb ? Qt.rgba(currentRgb[0], currentRgb[1], currentRgb[2], 1) : Theme.primary
    readonly property color visibleAccent: Accent.visible(accentColor, Theme.surfaceContainer)

    signal toggleRequested(bool on)
    signal brightnessRequested(int value)
    signal temperatureRequested(int mirek)
    signal expandToggled
    signal identifyRequested
    // value: an entry of effectValues ("no_effect" stops both regular and timed effects)
    signal effectRequested(string value)
    // function (color) set by the host. A function, not a signal: the color picker calls it after
    // the popout (and this row) may already be gone
    property var applyColor: null

    implicitHeight: content.implicitHeight + pad * 2

    Column {
        id: content
        width: parent.width
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingM

            Rectangle {
                id: iconBubble
                width: 32
                height: 32
                radius: 16
                anchors.verticalCenter: parent.verticalCenter
                color: row.isOn ? Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b, 0.3) : Theme.surfaceContainerHigh

                DIcon {
                    anchors.centerIn: parent
                    name: row.reachable ? row.icon : "link_off"
                    size: Theme.iconSize - 4
                    color: row.isOn ? row.visibleAccent : Theme.surfaceVariantText
                }
            }

            Column {
                width: parent.width - iconBubble.width - (expandIcon.visible ? expandIcon.width + parent.spacing : 0) - (identifyButton.visible ? identifyButton.width + parent.spacing : 0) - toggle.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    width: parent.width
                    text: row.light?.Name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    text: !row.reachable ? I18n.trFor("hueDirector", "Unreachable") : row.isOn ? Math.round(row.hd?.dimming?.brightness ?? 100) + "%" : I18n.trFor("hueDirector", "Off")
                    font.pixelSize: Theme.fontSizeSmall
                    color: row.reachable ? Theme.surfaceVariantText : Theme.error
                }
            }

            // Blinks the light to find it
            DIconButton {
                id: identifyButton
                anchors.verticalCenter: parent.verticalCenter
                visible: row.reachable && !!row.hd?.dimming
                iconName: "flare"
                tooltipText: I18n.trFor("hueDirector", "Identify")
                onClicked: row.identifyRequested()
            }

            DIconButton {
                id: expandIcon
                anchors.verticalCenter: parent.verticalCenter
                visible: row.hasColorControls
                iconName: row.expanded ? "expand_less" : "palette"
                tooltipText: row.expanded ? I18n.trFor("hueDirector", "Hide color controls") : I18n.trFor("hueDirector", "Color and temperature")
                onClicked: row.expandToggled()
            }

            DToggle {
                id: toggle
                anchors.verticalCenter: parent.verticalCenter
                checked: row.isOn
                onToggled: checked => row.toggleRequested(checked)
            }
        }

        HeldSlider {
            width: parent.width
            visible: !!row.hd?.dimming
            minimum: 1
            maximum: 100
            unit: "%"
            startIcon: "brightness_low"
            endIcon: "brightness_high"
            reported: Math.round(row.hd?.dimming?.brightness ?? 0)
            fillColor: row.visibleAccent
            fillTextColor: Accent.textOn(row.visibleAccent)
            onRequested: value => row.brightnessRequested(value)
        }

        // Color temperature in Kelvin (bridge uses mirek = 1e6 / K): empty thermometer at the low end,
        // full one at the high end. DSlider side icons can't be filled, so the icons sit outside the
        // slider in the same slots (iconSize wide, spacingM gap) to stay aligned with the sliders above
        Row {
            width: parent.width
            visible: row.expanded && !!row.colorTemp
            spacing: Theme.spacingM

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "thermometer"
                size: Theme.iconSize
                color: Theme.surfaceText
            }

            HeldSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (Theme.iconSize + parent.spacing) * 2
                minimum: Math.round(1e6 / (row.colorTemp?.mirek_schema?.mirek_maximum ?? 500))
                maximum: Math.round(1e6 / (row.colorTemp?.mirek_schema?.mirek_minimum ?? 153))
                step: 50
                unit: "K"
                // In color mode (mirek_valid false) keep the last known temperature;
                // before any, the middle of the light's range
                readonly property int currentMirek: row.colorTemp?.mirek_valid ? (row.colorTemp.mirek ?? 0) : 0
                property int knownMirek: 0

                onCurrentMirekChanged: if (currentMirek > 0) knownMirek = currentMirek
                Component.onCompleted: if (currentMirek > 0) knownMirek = currentMirek

                reported: knownMirek > 0 ? Math.round(1e6 / knownMirek) : Math.round((minimum + maximum) / 2)
                // Kelvin -> mirek -> Kelvin rounding drifts up to ~50K at the cold end
                tolerance: 100
                fillColor: row.visibleAccent
                fillTextColor: Accent.textOn(row.visibleAccent)
                onRequested: value => row.temperatureRequested(Math.round(1e6 / value))
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "thermometer"
                filled: true
                size: Theme.iconSize
                color: Theme.surfaceText
            }
        }

        // Swatch takes the slot of the end icon of the sliders above (DSlider SideIcon: iconSize wide, spacingM gap)
        Row {
            width: parent.width
            visible: row.expanded && row.hasColor
            spacing: Theme.spacingM

            // Fully saturated hue; the picker covers pastel tones and exact colors
            HeldSlider {
                readonly property real currentHue: row.currentRgb ? row.accentColor.hsvHue : -1
                // Achromatic or off (currentHue < 0): keep the last known hue
                property int knownHue: 0

                onCurrentHueChanged: if (currentHue >= 0) knownHue = Math.round(currentHue * 360)
                Component.onCompleted: if (currentHue >= 0) knownHue = Math.round(currentHue * 360)

                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - pickerButton.width - parent.spacing
                minimum: 0
                maximum: 359
                showValue: false
                startIcon: "palette"
                reported: knownHue
                // xy <-> RGB round trips drift a few degrees
                tolerance: 5
                onRequested: value => row.applyColor?.(Qt.hsva(value / 360, 1, 1, 1))

                // Same rainbow track as the shell color picker (Modules/ColorPicker/ColorPickerContent.qml)
                trackGradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.hsva(0, 1, 1, 1) }
                    GradientStop { position: 1 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) }
                    GradientStop { position: 2 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
                    GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) }
                    GradientStop { position: 4 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) }
                    GradientStop { position: 5 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) }
                    GradientStop { position: 1; color: Qt.hsva(1, 1, 1, 1) }
                }
            }

            // Opens the shell color picker (hex, color area, eyedropper, recent colors)
            DColorButton {
                id: pickerButton
                width: Theme.iconSize
                height: Theme.iconSize
                anchors.verticalCenter: parent.verticalCenter
                swatchColor: row.accentColor
                tooltipText: I18n.trFor("hueDirector", "More colors…")
                onClicked: {
                    const picker = PopoutService.colorPickerModal;
                    if (!picker)
                        return;
                    picker.selectedColor = row.accentColor;
                    picker.pickerTitle = row.light?.Name ?? "";
                    const apply = row.applyColor;
                    picker.onColorSelectedCallback = c => apply?.(c);
                    picker.show();
                }
            }
        }

        // Light effects (candle, fire, ...) and timed ones (sunrise, sunset)
        DFilterChips {
            width: parent.width
            visible: row.expanded && row.effectValues.length > 0
            showCounts: false
            model: row.effectValues.map(v => ({ label: row.effectLabel(v), value: v }))
            onSelectionChanged: index => row.effectRequested(row.effectValues[index])

            // Chips assign currentIndex on click, which would break a plain binding
            Binding on currentIndex {
                value: Math.max(0, row.effectValues.indexOf(row.currentEffect))
            }
        }
    }

    // Literal strings, so the translation tooling can extract them
    function effectLabel(v) {
        switch (v) {
        case "no_effect":
            return I18n.trFor("hueDirector", "No effect");
        case "candle":
            return I18n.trFor("hueDirector", "Candle");
        case "fire":
            return I18n.trFor("hueDirector", "Fireplace");
        case "prism":
            return I18n.trFor("hueDirector", "Prism");
        case "sparkle":
            return I18n.trFor("hueDirector", "Sparkle");
        case "opal":
            return I18n.trFor("hueDirector", "Opal");
        case "glisten":
            return I18n.trFor("hueDirector", "Glisten");
        case "underwater":
            return I18n.trFor("hueDirector", "Underwater");
        case "cosmos":
            return I18n.trFor("hueDirector", "Cosmos");
        case "sunbeam":
            return I18n.trFor("hueDirector", "Sunbeam");
        case "enchant":
            return I18n.trFor("hueDirector", "Enchant");
        case "sunrise":
            return I18n.trFor("hueDirector", "Sunrise");
        case "sunset":
            return I18n.trFor("hueDirector", "Sunset");
        default:
            return v;
        }
    }
}
