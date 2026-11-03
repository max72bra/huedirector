.pragma library

// Wallpaper sync: colors of the wallpaper regions where the lights of an entertainment area stand.
// Pure functions (no Qt): the bar widget's Canvas scales the wallpaper down, the daemon (HueEvents.qml) samples it

// Size the wallpaper is scaled to before sampling: enough for edge colors, small to parse
var sampleWidth = 32;
var sampleHeight = 18;

// Canvas getImageData() result (RGBA bytes) -> {w, h, px: [r, g, b, ...] in 0..1}, or null
function fromRgba(data, w, h) {
    if (!data || data.length < w * h * 4)
        return null;
    var px = [];
    for (var i = 0; i < w * h; i++)
        px.push(data[i * 4] / 255, data[i * 4 + 1] / 255, data[i * 4 + 2] / 255);
    return { w: w, h: h, px: px };
}

// Dominant color of the box around (u, v) (0..1, v = 0 at the top), as [r, g, b] in 0..1.
// Hue histogram weighted by saturation x value, so a few vivid pixels beat a large dull area;
// the winning bin is averaged. A gray region (no weight) gives its mean color instead
function dominant(img, u, v) {
    var bins = 12, half = 0.25;
    var x0 = Math.max(0, Math.floor((u - half) * img.w)), x1 = Math.min(img.w, Math.ceil((u + half) * img.w));
    var y0 = Math.max(0, Math.floor((v - half) * img.h)), y1 = Math.min(img.h, Math.ceil((v + half) * img.h));
    var weight = [], sum = [], mean = [0, 0, 0], n = 0;
    for (var b = 0; b < bins; b++) {
        weight.push(0);
        sum.push([0, 0, 0]);
    }
    for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
            var i = (y * img.w + x) * 3;
            var r = img.px[i], g = img.px[i + 1], bl = img.px[i + 2];
            mean[0] += r;
            mean[1] += g;
            mean[2] += bl;
            n++;
            var mx = Math.max(r, g, bl), mn = Math.min(r, g, bl), d = mx - mn;
            if (d < 0.08)
                continue;
            var hue = mx === r ? ((g - bl) / d + 6) % 6 : mx === g ? (bl - r) / d + 2 : (r - g) / d + 4;
            var k = Math.floor(hue / 6 * bins) % bins;
            var wgt = (d / mx) * mx;
            weight[k] += wgt;
            sum[k][0] += r * wgt;
            sum[k][1] += g * wgt;
            sum[k][2] += bl * wgt;
        }
    }
    if (!n)
        return null;
    var best = 0;
    for (b = 1; b < bins; b++)
        if (weight[b] > weight[best])
            best = b;
    // Vivid pixels under ~5% of the box: the region reads as gray/white/black
    if (weight[best] < n * 0.05)
        return mean.map(function (c) { return c / n; });
    return sum[best].map(function (c) { return c / weight[best]; });
}

// area: HueBridge.normalize() area {Channels: [{X, Z, Members: [{LightId, Index}]}]}.
// Returns {lightId: [[r, g, b], ...]} with one color per channel of the light, in Index order.
// Positions are scaled by the area's widest x and z, so the outermost lights sample the image edges
function lightColors(area, img) {
    var ch = area.Channels || [];
    var maxX = 0, maxZ = 0;
    ch.forEach(function (c) {
        maxX = Math.max(maxX, Math.abs(c.X));
        maxZ = Math.max(maxZ, Math.abs(c.Z));
    });
    var byLight = {};
    ch.forEach(function (c) {
        var u = maxX ? (c.X / maxX + 1) / 2 : 0.5;
        // z goes up, image rows go down
        var v = maxZ ? (1 - c.Z / maxZ) / 2 : 0.5;
        var color = dominant(img, u, v);
        if (!color)
            return;
        c.Members.forEach(function (m) {
            (byLight[m.LightId] = byLight[m.LightId] || []).push({ index: m.Index, color: color });
        });
    });
    var out = {};
    for (var id in byLight)
        out[id] = byLight[id].sort(function (a, b) { return a.index - b.index; }).map(function (e) { return e.color; });
    return out;
}

// n colors picked evenly from a longer list (7 strip segments -> 5 gradient points), ends kept
function spread(colors, n) {
    if (colors.length <= n)
        return colors;
    var out = [];
    for (var i = 0; i < n; i++)
        out.push(colors[Math.round(i * (colors.length - 1) / (n - 1))]);
    return out;
}
