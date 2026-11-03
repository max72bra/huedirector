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
    // Gradient lights (lightstrips, Play gradient, ...): 2..points_capable colors spread along the light
    readonly property var gradient: hd?.gradient ?? null
    // Always as many points as the light declares: a solid color (temperature or hue slider) reports none
    readonly property int maxPoints: Math.max(2, gradient?.points_capable ?? 5)
    // Current points as colors, set by the host (HueDirector.xyToRgb)
    property var gradientColors: []
    // Reported points repeated to maxPoints; none reported (solid color): the light's current color
    readonly property var baseColors: {
        const out = [];
        for (let i = 0; i < maxPoints; i++)
            out.push(gradientColors.length ? gradientColors[i % gradientColors.length] : accentColor);
        return out;
    }
    // Same points as baseColors, as the bridge's own xy: sent back untouched (style change, the other points
    // when one is picked), since an xy -> RGB -> xy round trip clips and shifts the colors.
    // Solid color: the light's color.xy, also reported in temperature mode; else the swatch color
    readonly property var basePoints: {
        const xy = (gradient?.points ?? []).map(p => p.color?.xy).filter(p => p);
        const solid = hd?.color?.xy;
        const out = [];
        for (let i = 0; i < maxPoints; i++)
            out.push(xy.length ? xy[i % xy.length] : solid ?? baseColors[i]);
        return out;
    }
    readonly property var modeValues: gradient?.mode_values ?? []
    readonly property bool hasColorControls: hasColor || !!colorTemp || effectValues.length > 0
    readonly property color accentColor: currentRgb ? Qt.rgba(currentRgb[0], currentRgb[1], currentRgb[2], 1) : Theme.primary
    readonly property color visibleAccent: Accent.visible(accentColor, Theme.surfaceContainer)
    // Icon bubble: the light's color at 0.3 over the row; the icon is checked against it, not the theme surface
    readonly property color bubbleColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3)
    readonly property color iconColor: Accent.visible(accentColor, Qt.tint(color, bubbleColor))

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
    // function (points, mode) set by the host, same reason: points are bridge xy {x, y} or colors;
    // mode "" keeps the current one
    property var applyGradient: null

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
                width: Theme.iconSizeLarge
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: row.isOn ? row.bubbleColor : Theme.surfaceContainerHigh

                DIcon {
                    anchors.centerIn: parent
                    name: row.reachable ? row.icon : "link_off"
                    size: Theme.iconSizeMedium
                    color: row.isOn ? row.iconColor : Theme.surfaceVariantText
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
            fillTextColor: Accent.textOn(row.visibleAccent, Theme.surfaceText, Theme.surface)
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
                fillTextColor: Accent.textOn(row.visibleAccent, Theme.surfaceText, Theme.surface)
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
                    const apply = row.applyColor;
                    row.openPicker(row.accentColor, c => apply?.(c));
                }
            }
        }

        // Gradient points: click a swatch to pick its color
        // Icon in the slot of the sliders' start icon, like the thermometer row
        Item {
            width: parent.width
            height: Theme.iconButtonSize
            visible: row.expanded && !!row.gradient

            DIcon {
                id: gradientIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: "gradient"
                size: Theme.iconSize
                color: Theme.surfaceText
            }

            // Spread over the slider track above (between the start and end icon slots): equal gaps between
            // the swatches and at both ends
            Row {
                id: swatchRow
                readonly property real swatchSize: Theme.iconSize + Theme.spacingS
                readonly property real gap: (width - swatchSize * row.baseColors.length) / (row.baseColors.length + 1)

                anchors.left: gradientIcon.right
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (Theme.iconSize + Theme.spacingM) * 2
                leftPadding: gap
                spacing: gap

                Repeater {
                    model: row.baseColors.length

                    DColorButton {
                        required property int index

                        anchors.verticalCenter: parent.verticalCenter
                        width: swatchRow.swatchSize
                        height: width
                        swatchColor: row.baseColors[index] ?? "transparent"
                        tooltipText: I18n.trFor("hueDirector", "Gradient color %1").arg(index + 1)
                        onClicked: {
                            // Captured now: the callback must not depend on this row
                            const points = row.basePoints.slice();
                            const i = index;
                            const apply = row.applyGradient;
                            row.openPicker(row.baseColors[i], c => {
                                points[i] = c;
                                apply?.(points, "");
                            });
                        }
                    }
                }
            }
        }

        // How the points spread along the light. DDropdown works with labels
        DDropdown {
            readonly property var modeLabels: row.modeValues.map(v => row.modeLabel(v))

            width: parent.width
            visible: row.expanded && row.modeValues.length > 1
            text: I18n.trFor("hueDirector", "Gradient style")
            options: modeLabels
            currentValue: row.modeLabel(row.gradient?.mode ?? "")
            onValueChanged: newValue => {
                const i = modeLabels.indexOf(newValue);
                if (i >= 0 && row.modeValues[i] !== row.gradient?.mode)
                    row.applyGradient?.(row.basePoints, row.modeValues[i]);
            }
        }

        // Light effects (candle, fire, ...) and timed ones (sunrise, sunset). DDropdown works with labels
        DDropdown {
            readonly property var effectLabels: row.effectValues.map(v => row.effectLabel(v))

            width: parent.width
            visible: row.expanded && row.effectValues.length > 0
            text: I18n.trFor("hueDirector", "Effect")
            options: effectLabels
            currentValue: row.effectLabel(row.currentEffect)
            onValueChanged: newValue => {
                const i = effectLabels.indexOf(newValue);
                if (i >= 0 && row.effectValues[i] !== row.currentEffect)
                    row.effectRequested(row.effectValues[i]);
            }
        }
    }

    // Shell color picker (hex, color area, eyedropper, recent colors). Opening a modal closes every popout
    // unless the modal has keepPopoutsOpen: the picker is shared, so the flag is set for this use only
    // and restored when it closes
    function openPicker(initial, onPicked) {
        const picker = PopoutService.colorPickerModal;
        if (!picker)
            return;
        const keepBefore = picker.keepPopoutsOpen;
        const restore = () => {
            picker.dialogClosed.disconnect(restore);
            picker.keepPopoutsOpen = keepBefore;
        };
        picker.dialogClosed.connect(restore);
        picker.keepPopoutsOpen = true;
        picker.selectedColor = initial;
        picker.pickerTitle = light?.Name ?? "";
        picker.onColorSelectedCallback = onPicked;
        picker.show();
    }

    // Literal strings, so the translation tooling can extract them
    function modeLabel(v) {
        switch (v) {
        case "interpolated_palette":
            return I18n.trFor("hueDirector", "Blend");
        case "interpolated_palette_mirrored":
            return I18n.trFor("hueDirector", "Mirrored blend");
        case "random_pixelated":
            return I18n.trFor("hueDirector", "Scattered");
        case "segmented_palette":
            return I18n.trFor("hueDirector", "Segments");
        default:
            return v;
        }
    }

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
