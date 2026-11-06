// Compose a transparent collage (e.g. a "products by machine" card: the machine in
// the middle, its products around it) from existing transparent images. No AI.
//
//   node collage.mjs <layout.json>
// layout.json:
// { "size": 1300, "out": "/abs/cat-x",            // writes cat-x.png, cat-x.webp, cat-x-750w.webp
//   "widths": [750],                              // extra -<w>w.webp variants
//   "items": [ { "file": "/abs/machine.png", "maxW": 760, "maxH": 930, "left": "center", "top": 20 },
//              { "file": "/abs/box.png", "maxW": 400, "maxH": 400, "left": 40, "bottom": 40 } ] }
// Items are trimmed to their visible pixels, fitted inside maxW x maxH, and placed in
// order (later items sit in front). left: number | "center"; top or bottom: number.
// Run from a project that has `sharp` installed.
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
const require = createRequire(`${process.cwd()}/`);
const sharp = require("sharp");

const L = JSON.parse(await readFile(process.argv[2], "utf8"));
const S = L.size ?? 1300;
const layers = [];
for (const it of L.items) {
  const trimmed = await sharp(it.file).trim({ threshold: 1 }).png().toBuffer();
  const { data, info } = await sharp(trimmed)
    .resize(it.maxW, it.maxH, { fit: "inside" })
    .png()
    .toBuffer({ resolveWithObject: true });
  const left = it.left === "center" ? Math.round((S - info.width) / 2) : it.left;
  const top = it.bottom != null ? S - info.height - it.bottom : it.top;
  layers.push({ input: data, left, top });
  console.log(`${it.file.split("/").pop()} ${info.width}x${info.height} @ ${left},${top}`);
}
await sharp({ create: { width: S, height: S, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
  .composite(layers)
  .png()
  .toFile(`${L.out}.png`);
await sharp(`${L.out}.png`).webp({ quality: 82, alphaQuality: 90, effort: 6 }).toFile(`${L.out}.webp`);
for (const w of L.widths ?? [])
  await sharp(`${L.out}.png`).resize(w, w).webp({ quality: 82, alphaQuality: 90, effort: 6 }).toFile(`${L.out}-${w}w.webp`);
console.log(`wrote ${L.out}.png/.webp${(L.widths ?? []).map((w) => ` + -${w}w.webp`).join("")}`);
