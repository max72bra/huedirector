.pragma library

// Contrast helpers for fills and icons tinted with a light's color (RoomCard, LightRow, header chip)

// WCAG relative luminance (sRGB channels linearized)
function luminance(c) {
    const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

// WCAG contrast ratio, 1 (same) to 21 (black on white)
function contrast(a, b) {
    const la = luminance(a), lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

// c moved towards black (light background) or white (dark background) until it reaches ratio
// (default 3:1, the WCAG minimum for icons and graphical parts) against bg, e.g. a 2700K beige
// on a light theme or a deep blue on a dark one. Colors that already stand out are left untouched.
// Mixing, not Qt.lighter: a near-black color can't be lightened by multiplying its value
function visible(c, bg, ratio) {
    const target = ratio ?? 3;
    const towards = luminance(bg) > 0.18 ? 0 : 1;
    for (let i = 0; i < 10 && contrast(c, bg) < target; i++)
        c = Qt.rgba(c.r * 0.8 + towards * 0.2, c.g * 0.8 + towards * 0.2, c.b * 0.8 + towards * 0.2, c.a);
    return c;
}

// Whichever of the theme colors a and b (e.g. Theme.surfaceText, Theme.surface) stands out more on c
function textOn(c, a, b) {
    return contrast(a, c) >= contrast(b, c) ? a : b;
}
