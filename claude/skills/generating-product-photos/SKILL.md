---
name: generating-product-photos
description: Use when a store, catalog, landing page or category card needs product or packaging photos — especially branded consumables (boxes, packs, bottles) that must match a brand's real logo and artwork, need a transparent background, or need a "machine with its products around it" collage made from images that already exist.
---

# Generating product photos (GPT Image + brand refs + transparent background)

## Overview

Send the brand's **real files** (logo, printed artwork) as reference images to the
GPT Image **edits** endpoint, ask for one product per call, and get transparency from
the **API parameter** — never from prompt text. Then verify the alpha and judge every
candidate on white before anything is published. A collage of existing transparent
images needs no AI at all.

## Quick reference

Scripts sit beside this file: `S=~/.claude/skills/generating-product-photos/scripts`
(run each with `node`; `check`/`collage` load `sharp` from the current project).

| Decision | Use |
|---|---|
| Endpoint | `POST /v1/images/edits` with `image[]` refs (generations only when there is no brand art) |
| Model | `gpt-image-2.5-sunburst` (editing precision — brand fidelity); `gpt-image-2.5-flare` for fast drafts. **Re-check the current names** in `developers.openai.com/api/docs/guides/image-generation.md` (curl with a browser UA, append `.md`) — model names move |
| Transparency | `background: "transparent"` + `output_format: "png"` (or webp). Not in the prompt |
| Other params | `size: "1024x1024"`, `quality: "high"`, `n: 2`. No `input_fidelity` (gpt-image-2 family is always high fidelity) |
| Key | `node --env-file=<project secrets file> $S/gen.mjs …` — the script reads `process.env`, length-checks ≥ 40, never prints it. Don't open the secrets file yourself |
| Collage | `$S/collage.mjs` (sharp: trim → fit → place → webp + `-750w`) |

## Prompt recipe

`<base> + <the product> + <what each ref is> + <physical orientation> + <exact counts> + <label text>`

- **Base** (shared): "Studio product photograph for an online store, photorealistic, three-quarter view from slightly above, soft even studio lighting, crisp clean edges, a soft contact shadow directly under the product, nothing else in the frame."
- **Refs by number**: "The top card is exactly the card in image 1 … the robot mark from image 2 and the wordmark from image 3 in dark ink." Pass the files in that order.
- **Orientation physically**, not as a word: "the box is deeper than it is wide, so the cards are seen in PORTRAIT (taller than wide, long side running away from the viewer)". "Portrait cards" alone came back landscape.
- **Counts**: "EXACTLY TEN … in a single row (count them: 10, not 9, not 11, not 12). No loose items outside the box." A loose extra item is where miscounts hide.
- **Label text**: short, quoted, upper-case ("A5 DRAWING PAPER", "2,000 SHEETS").
- **Third-party products** (the pens a machine uses): describe them generically — "plain matte black barrels with no brand names" — so no other company's brand appears.

## Workflow

1. Find the brand's source files (logo master, wordmark on transparent, print artwork). Use the artwork the customer will actually receive.
2. Write a `jobs.json` (see `examples/jobs.json`) and run `node --env-file=… $S/gen.mjs jobs.json out/`.
3. `node $S/check.mjs out/sheet.png out/*.png` (from a project with `sharp`) — every line must say `OK` (alpha, corner transparent), then **look at the on-white sheet**.
4. Zoom-crop to count items and read the label text. Reject and regenerate rather than publish a wrong count or orientation.
5. Publish through the app's own upload path (it builds the WebP ladder), then re-download the served file and confirm it still has alpha.

## Common mistakes

| Mistake | Fix |
|---|---|
| "transparent background" in the prompt | It's `background: "transparent"`; text can make a checkerboard or white box |
| Judging the image in a viewer that draws alpha over dark grey | The soft shadow reads as a grey halo; judge on the white contact sheet |
| `n: 1` and shipping whatever came back | `n: 2`, pick; counts and orientation fail often |
| Asking AI for a collage of images you already have | `$S/collage.mjs` — exact, free, repeatable |
| Skipping the served-file check | Re-download from the CDN; confirm `hasAlpha` and corner alpha 0 |
