// Verify generated images really are transparent, and build an ON-WHITE contact
// sheet to judge them the way a shopper sees them (image viewers often show
// alpha over dark grey, which makes the soft shadow look like a grey halo).
//
//   node check.mjs <out.png> <img1.png> [img2.png ...]
// Run from a project that has `sharp` installed (it is loaded from the cwd).
import { createRequire } from "node:module";
const require = createRequire(`${process.cwd()}/`);
let sharp;
try {
  sharp = require("sharp");
} catch {
  console.error("sharp not found from this directory — cd into a project with sharp, or `npm i -D sharp`.");
  process.exit(2);
}
const [sheet, ...imgs] = process.argv.slice(2);
const T = 420;
const tiles = [];
for (const f of imgs) {
  const m = await sharp(f).metadata();
  const { data } = await sharp(f).ensureAlpha().extractChannel(3).raw().toBuffer({ resolveWithObject: true });
  let clear = 0;
  for (const v of data) if (v === 0) clear++;
  const pct = (100 * clear) / data.length;
  const ok = m.hasAlpha && data[0] === 0 && pct > 5;
  console.log(`${ok ? "OK  " : "FAIL"} ${f.split("/").pop()} ${m.width}x${m.height} alpha=${m.hasAlpha} corner=${data[0]} clear=${pct.toFixed(0)}%`);
  tiles.push(await sharp(f).resize(T, T, { fit: "contain", background: { r: 255, g: 255, b: 255, alpha: 0 } }).png().toBuffer());
}
const cols = Math.min(3, tiles.length);
const rows = Math.ceil(tiles.length / cols);
await sharp({ create: { width: cols * T, height: rows * T, channels: 3, background: "#ffffff" } })
  .composite(tiles.map((t, i) => ({ input: t, left: (i % cols) * T, top: Math.floor(i / cols) * T })))
  .png()
  .toFile(sheet);
console.log(`contact sheet on white -> ${sheet}`);
