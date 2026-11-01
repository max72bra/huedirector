.pragma library

// Contrast helpers for fills tinted with a light's color (RoomCard, LightRow)

// Approximate relative luminance on gamma-encoded channels, good enough for contrast decisions
function luminance(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

// c darkened (light background) or lightened (dark background) until it stands out from bg,
// e.g. a 6500K near-white fill on a light theme. Colors that already stand out are left untouched
function visible(c, bg) {
    const bgLum = luminance(bg);
    for (let i = 0; i < 4 && Math.abs(luminance(c) - bgLum) < 0.2; i++)
        c = bgLum > 0.5 ? Qt.darker(c, 1.3) : Qt.lighter(c, 1.3);
    return c;
}

// Dark text on light fills, light text on dark ones
function textOn(c) {
    return luminance(c) > 0.5 ? "#000000" : "#FFFFFF";
}
