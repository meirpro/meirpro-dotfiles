---
name: lottie-animations
description: Find, extract, optimize, and embed Lottie animations on websites and in video work. Covers extracting free animated icons from Telegram sticker packs (.tgs is gzipped Lottie JSON, 1000s of high-quality emojis available free), optimizing Lottie JSON for web delivery, embedding in React/Vue/Next.js/vanilla HTML, and the loop-length math needed when using Lottie in Remotion or other video tools. Activate when someone asks about Lottie files, animated icons for web, .tgs files, Telegram sticker extraction, animated emoji, lottie-web, lottie-react, dotLottie, @remotion/lottie, or "where do I get free animated icons." NOT for raster/GIF animation (use CSS or video), motion graphics in After Effects (Lottie is the export target — use AE skills for authoring), or general SVG animation (use GSAP/Motion).
---

# Lottie Animations on the Web

## Overview

Lottie is a vector animation format (JSON) that renders crisp at any size, weighs a fraction of an equivalent GIF/video, and animates on the GPU. The biggest practical obstacle is **sourcing** good Lottie files; the second is **embedding** them without bloating the bundle or breaking SSR. This skill solves both: it shows how to harvest hundreds of free, high-quality animated icons from public Telegram sticker packs, how to optimize them, and how to render them in any modern web stack.

## Quick start: a free animated icon in 3 minutes

The fastest path to one good Lottie icon on a webpage:

1. **Pick a Telegram sticker pack** with animated emoji. The canonical one is `t.me/addstickers/AnimatedEmojies` (~599 official Telegram-authored animations) but any pack tagged "animated" works. See `references/sticker-pack-sources.md` for a curated list.
2. **Extract the `.tgs` files** via `@Stickerdownloadbot` on Telegram (DM it the pack URL, it returns a zip), or via the Bot API (`scripts/fetch_sticker_pack.py`).
3. **Convert** to Lottie JSON: `scripts/tgs_to_lottie.sh path/to/0.tgs > public/icons/fire.json`. The `.tgs` format is literally gzipped Lottie JSON with a `"tgs": 1` marker — `gunzip` is the entire conversion.
4. **Render it** with whatever Lottie player matches the stack. For React: `npm i lottie-react` then `<Lottie animationData={fireJson} loop />`. For vanilla HTML: drop in `lottie-web` and call `lottie.loadAnimation()`. Full snippets per framework in `references/web-embedding.md`.

That's the 80% case. The rest of this skill is for the 20% — picking the right player, optimizing file size, aligning loops in video, and avoiding the common pitfalls.

## Workflows

### Extracting animations from a Telegram sticker pack

Telegram is the single best free source of high-quality animated icons because professional animators publish whole curated packs to it. Two extraction paths:

**Path A — third-party bot (zero setup, manual)**
- DM `@Stickerdownloadbot` (or any equivalent — `@StickerDownloadBot`, `@stickerdownloader_bot`, etc.) with the pack URL like `https://t.me/addstickers/AnimatedEmojies`.
- It replies with a zip of every sticker as `N.tgs` files (`0.tgs`, `1.tgs`, ...).
- Unzip locally. Browse the files via any Lottie previewer (LottieFiles desktop app, or `npx @lottiefiles/lottie-viewer`, or just `scripts/inspect_lottie.py` for metadata).
- Convert chosen files with `scripts/tgs_to_lottie.sh`.

**Path B — Telegram Bot API (scriptable, reproducible)**
- Create a bot via `@BotFather`, save the token.
- Run `python scripts/fetch_sticker_pack.py --token <BOT_TOKEN> --pack AnimatedEmojies --output ./stickers/`
- The script calls `getStickerSet` → `getFile` → downloads each `.tgs` and (optionally) converts on the fly.
- This is the right path when re-pulling needs to be reproducible (CI, build step, or multiple projects pulling the same pack).

**Naming convention.** Files arrive numerically (`0.tgs` ... `598.tgs`). Rename to semantic kebab-case (`fire.json`, `crystal-ball.json`) before checking in — the numeric names are meaningless. The original sticker's `nm` field inside the JSON often preserves the author's intent (`"!!!!fire"`, `"Crystal Ball"`) and is worth a peek when picking names.

**License note.** Telegram's official `AnimatedEmojies` pack is free for use as part of Telegram's emoji set. Third-party packs vary — many are CC-0 or unmarked, some have author tags inside the `nm` field (`"Thought Balloon (@syrreel)"`). For commercial redistribution (e.g., bundling into a sold product), check the individual pack page for an explicit license or contact the author. For typical app/website use (decoration in your own product), it's safe by convention.

### Converting `.tgs` to Lottie JSON

A `.tgs` file is a gzipped Lottie JSON with one Telegram-specific marker (`"tgs": 1` at the root, indicating Telegram-spec compliance: 512×512 canvas, 60fps cap, ≤64KB compressed, ≤3-second loop). After gunzip the JSON is renderable by any Lottie player.

```bash
# Single file
scripts/tgs_to_lottie.sh fire.tgs > public/icons/fire.json

# Whole directory in one shot
scripts/tgs_to_lottie.sh --batch stickers/ public/icons/
```

The `"tgs": 1` marker is harmless in non-Telegram contexts — leave it. Some optimizers strip it; that's fine too.

### Inspecting Lottie metadata before committing

Before picking which extracted file to use, look at its metadata. `scripts/inspect_lottie.py` reports name, fps, in/out frame, natural duration, layer count, asset count, and file size:

```bash
$ python scripts/inspect_lottie.py public/icons/fire.json
fire.json
  nm:         !!!!fire
  fr:         60 fps
  ip → op:    0 → 180  (3.00s loop)
  layers:     12 (0 images, 12 shapes)
  size:       435 KB minified
```

Use this to:
- Pick the cleanest version when multiple candidates exist (fewer layers = lighter render).
- Compute loop math for video (see below).
- Catch broken extractions (a file with 0 layers, or with `op == ip`, is corrupt or static).

### Optimizing Lottie JSON for web

Out of the box, a `.tgs` → JSON conversion produces files in the 50–500 KB range — bigger than ideal for hot pages. Three optimization passes in increasing aggressiveness, all documented with tool names and concrete commands in `references/optimization.md`:

1. **Round float precision** — keyframe paths and transforms often have 10+ decimal digits. Rounding to 3 typically cuts size 20–40% with no visible difference.
2. **Strip metadata** — `nm` fields on every layer, marker comments, hidden layers. Cuts another ~10%.
3. **Convert to dotLottie** (`.lottie` file = zip of JSON + assets). Drops bundle weight ~50% over served JSON because it's gzip-equivalent compressed *and* the runtime player ships smaller. Trade-off: needs `@lottiefiles/dotlottie-web` or `@lottiefiles/dotlottie-react` instead of `lottie-web`.

Recommended starting tool: `lottie-minify` (Node CLI) for passes 1+2, or `dotlottie-js` for the full conversion. See the reference doc for current package names and flags — the LottieFiles ecosystem renames things every ~year.

### Embedding in a website

Full per-framework snippets are in `references/web-embedding.md`. Quick reference:

| Stack | Package | Bundle cost | Notes |
|---|---|---|---|
| React (CSR) | `lottie-react` | ~50 KB gz | Simplest API; `<Lottie animationData={...} loop />`. |
| React (SSR/Next.js) | `lottie-react` with `dynamic(..., { ssr: false })` | ~50 KB gz | Lottie reads `document` — SSR-disable the import. |
| Vue 3 | `vue3-lottie` | ~55 KB gz | Same animationData prop pattern. |
| Vanilla HTML | `lottie-web` | ~250 KB gz | Heaviest, but framework-free. CDN-friendly. |
| dotLottie everywhere | `@lottiefiles/dotlottie-web` / `dotlottie-react` | ~30 KB gz | Smallest runtime; needs `.lottie` files (see optimization). |
| Remotion (video) | `@remotion/lottie` | bundled with Remotion | See "Loop math for video" below — special concern. |

**Always lazy-load** the player and the animation data on routes where the icon is below the fold. `loadAnimation()` + a fetched JSON URL beats inline imports for anything bigger than ~20 KB.

### Loop math for video work (Remotion, etc.)

When a Lottie loops inside a fixed-duration video composition, the composition's total frame count **must be a whole multiple of the animation's video-frame loop length** or the icon visibly freezes/cuts mid-cycle on the final frame.

The math, step by step:

1. **Read the Lottie's natural loop length.** From `inspect_lottie.py` or the JSON itself: `loopFrames_native = op - ip`, at the file's native `fr` (frames per second). Example: `op=180, ip=0, fr=60` → 3-second loop.
2. **Convert to video frames.** `loopFrames_video = loopFrames_native × (video_fps / native_fr)`. Example: 3 seconds at video 30 fps = 90 frames.
3. **Pick a composition duration that's a whole multiple.** Example: 1350 video frames = exactly 15 × 90-frame loops = 45 seconds at 30 fps. The animation ends cleanly on the last frame.
4. **If swapping in a new icon**, recompute. A new emoji with a 2.5-second native loop = 75 video frames at 30 fps, and 1350 / 75 = 18 — still clean. But 1350 / 80 = 16.875 — not clean, animation would freeze 0.875 of a loop in.

**Pitfall: mixed loop lengths.** If a video shows multiple Lottie icons simultaneously and they have different natural durations, the composition needs to be a common multiple of all of them. Use the LCM (`scripts/inspect_lottie.py --lcm file1.json file2.json file3.json` reports it).

## Scripts

- **`scripts/tgs_to_lottie.sh`** — Bash. Converts `.tgs` files to Lottie JSON via `gunzip`. Single-file mode (`tgs_to_lottie.sh in.tgs > out.json`) or batch mode (`tgs_to_lottie.sh --batch in_dir/ out_dir/`). No dependencies beyond standard Unix tools.
- **`scripts/inspect_lottie.py`** — Python 3. Reports Lottie metadata (name, fps, loop length, layer count, file size). With `--lcm file1 file2 ...`, reports the least common multiple of loop lengths in video frames for a given `--video-fps` (default 30) — use this for Remotion duration planning.
- **`scripts/fetch_sticker_pack.py`** — Python 3. Calls the Telegram Bot API to download every sticker in a named pack as `.tgs` files. Requires a bot token from `@BotFather`. Optional `--convert` flag also runs `tgs_to_lottie.sh` on each file.

## References

- **`references/sticker-pack-sources.md`** — Curated list of free animated Telegram sticker packs (`AnimatedEmojies`, others), plus non-Telegram free sources (LottieFiles community, IconScout free tier).
- **`references/web-embedding.md`** — Per-framework code snippets (React, Next.js, Vue, vanilla, Remotion). Includes SSR pitfalls, lazy-loading patterns, and player-package comparison with bundle sizes.
- **`references/optimization.md`** — Concrete optimization commands for `lottie-minify`, `dotlottie-js`, and manual JSON pruning. Documents what each pass cuts and what it can break.
- **`references/lottie-file-format.md`** — Lottie JSON anatomy (`v`, `fr`, `ip`, `op`, `w`, `h`, `layers`, `assets`). Just enough to debug a broken file or write a custom optimizer.
