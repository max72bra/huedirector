// Checks for WallpaperSync.js (pure functions). Run: node tests/wallpaper-sync.test.js
const assert = require("assert");
const fs = require("fs");
const path = require("path");

// QML-only first line out, then the library's functions as a module
const src = fs.readFileSync(path.join(__dirname, "..", "WallpaperSync.js"), "utf8").replace(".pragma library", "");
const ws = new Function(src + "\nreturn { fromRgba, dominant, lightColors, spread };")();

// w x h image filled per pixel by f(x, y) -> [r, g, b]
const image = (w, h, f) => {
    const px = [];
    for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++)
            px.push(...f(x, y));
    return { w: w, h: h, px: px };
};
const close = (a, b) => a.every((v, i) => Math.abs(v - b[i]) < 0.02);

// Left half red, right half blue: the outermost lights take the color of their edge
const img = image(32, 18, x => x < 16 ? [1, 0, 0] : [0, 0, 1]);
const area = { Channels: [
    { X: -1, Z: 0, Members: [{ LightId: "strip", Index: 0 }] },
    { X: 1, Z: 0, Members: [{ LightId: "strip", Index: 1 }] },
    { X: 1, Z: 0, Members: [{ LightId: "lamp", Index: 0 }] }
] };
const colors = ws.lightColors(area, img);
assert.ok(close(colors.strip[0], [1, 0, 0]), "strip left end red");
assert.ok(close(colors.strip[1], [0, 0, 1]), "strip right end blue");
assert.ok(close(colors.lamp[0], [0, 0, 1]), "lamp on the right blue");

// A few vivid pixels (3 of the 36 in the sampled box) beat a large dull area; a gray region gives its mean color
const mostlyGray = image(10, 10, (x, y) => x === 5 && y >= 3 && y < 6 ? [0, 1, 0] : [0.5, 0.5, 0.5]);
assert.ok(close(ws.dominant(mostlyGray, 0.5, 0.5), [0, 1, 0]), "vivid green wins");
assert.ok(close(ws.dominant(image(4, 4, () => [0.3, 0.3, 0.3]), 0.5, 0.5), [0.3, 0.3, 0.3]), "gray mean");

// spread keeps both ends and never adds colors
assert.deepStrictEqual(ws.spread([1, 2, 3, 4, 5, 6, 7], 5), [1, 3, 4, 6, 7]);
assert.deepStrictEqual(ws.spread([1, 2], 5), [1, 2]);

// fromRgba drops alpha and rejects short data
assert.deepStrictEqual(ws.fromRgba([255, 0, 0, 255], 1, 1).px, [1, 0, 0]);
assert.strictEqual(ws.fromRgba([255, 0, 0], 1, 1), null);

console.log("wallpaper-sync: ok");
