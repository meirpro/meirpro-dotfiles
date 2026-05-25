# Optimizing Lottie JSON for the web

A fresh `.tgs` → JSON conversion is 50–500 KB per icon. That's tolerable for one above-the-fold hero icon but rough for a grid of twelve. Three optimization passes, in increasing aggressiveness.

## Pass 1: Round float precision (do this first, always safe)

Keyframe paths and transforms often have 10+ decimal digits. Rounding to 3 typically cuts size 20–40% with no human-visible difference.

**Tool: `lottie-minify` (Node CLI)**

```bash
npm install -g lottie-minify
lottie-minify in.json -o out.json --precision 3
```

Or programmatically:

```js
import { minify } from "lottie-minify";
const minified = minify(jsonObject, { precision: 3 });
```

**What it can break**: very subtle motion blur or sub-pixel positioning. Inspect the output visually for any icon involving fine drift or rotation. Drop precision to 4 if visible artifacts appear.

**Alternative — manual one-liner with `jq`**:

```bash
jq -c 'walk(if type == "number" then (. * 1000 | round) / 1000 else . end)' \
   in.json > out.json
```

Requires `jq` 1.6+ (for `walk`). Same effect, no Node dependency.

## Pass 2: Strip metadata

Lottie JSON carries `nm` (name) fields on every layer, marker comments, and often hidden/test layers from the original After Effects export. These cost 5–15% with zero render impact.

**With `lottie-minify`**:

```bash
lottie-minify in.json -o out.json --precision 3 --no-names --no-hidden
```

**Manually** — drop these top-level fields if present: `meta` (author info), `markers` (named time markers). Inside each layer, drop `nm` and any layer where `hd: true`.

**What it can break**: if downstream code references layers by name (`anim.goToAndStop("fire-start")`), stripping `nm` breaks that. Rare in practice but worth a grep before applying.

## Pass 3: Convert to dotLottie format

dotLottie (`.lottie` file) is a zip container holding the JSON plus any assets. Two wins:

1. **~50% smaller on the wire** vs. served gzipped JSON (the zip is more aggressive and includes Brotli-friendly structure).
2. **Smaller player runtime** — `@lottiefiles/dotlottie-web` is ~30 KB vs. `lottie-web`'s ~250 KB.

**Tool: `dotlottie-js`**

```bash
npm install -g @lottiefiles/dotlottie-js
dotlottie pack -i fire.json -o fire.lottie
```

Or in a build script:

```js
import { DotLottie } from "@lottiefiles/dotlottie-js";

const dotLottie = new DotLottie();
await dotLottie.addAnimation({ id: "fire", data: jsonObject });
const buffer = await dotLottie.build();
await fs.writeFile("fire.lottie", buffer);
```

**Trade-off**: requires switching the player package from `lottie-web` / `lottie-react` to `@lottiefiles/dotlottie-web` / `dotlottie-react`. The API is slightly different (uses `<DotLottieReact src="fire.lottie" />` instead of `<Lottie animationData={...} />`). If the project already uses `lottie-react`, the migration is a one-component swap; if it relies on `lottie-react`-specific features (imperative refs to `goToAndStop`), check dotLottie's equivalent first.

**Bundling many animations**: a single `.lottie` file can hold multiple animations and share assets between them. For a 20-icon library, one `library.lottie` is often smaller than 20 separate `.json` files.

## Pass 4 (rare): Manual layer pruning

For very heavy files (1+ MB), open the JSON in a Lottie editor (LottieFiles editor, or the original After Effects file if available) and:

- Delete hidden / guide / reference layers the author left in
- Merge stacked shape layers that always animate identically
- Replace embedded raster assets (`assets[]` with `"p": "image_0.png"` entries) with vector equivalents if possible — raster assets are the single biggest contributor to file size

This is hand work and easy to break the animation. Only worth it for hero-page or video-export use cases.

## What NOT to do

- **Don't gzip the `.json` and serve it as `.json`** — browsers won't decode it. Either let your server's HTTP gzip handle it (always on by default for `application/json`), or convert to `.lottie` (which is a proper container format).
- **Don't `JSON.stringify(JSON.parse(file))` and call it "minified"** — that strips whitespace, but `.tgs`-derived JSON is already minified (no whitespace).
- **Don't run optimization in production at request time.** Always pre-optimize during build/asset-pipeline. Optimization is CPU-expensive (especially Pass 3).

## Quick reference: typical sizes after each pass

For a representative 200 KB unprocessed icon:

| Pass | Resulting size | % of original |
|---|---|---|
| Original (.tgs → gunzipped JSON) | 200 KB | 100% |
| + Pass 1 (precision 3) | 130 KB | 65% |
| + Pass 2 (strip metadata) | 115 KB | 58% |
| + Pass 3 (dotLottie) | 55 KB | 28% |
| + gzip on the wire (no extra work — HTTP layer) | 18 KB | 9% |

The HTTP-gzip column is what users actually download. Run the math on that, not the on-disk size.
