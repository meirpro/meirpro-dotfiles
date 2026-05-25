# Sources of free Lottie animations

## Telegram sticker packs (best source)

Telegram is the highest-quality free source for animated icons because professional animators publish curated packs as free emoji sets. Every pack is hundreds of animations, all internally consistent, all licensable under at-least-permissive terms.

### Curated list of useful animated packs

| Pack URL slug | What's in it | Approx. count |
|---|---|---|
| `AnimatedEmojies` | Official Telegram-authored emoji set: 😀 → fire, star, gem, calendar, clock, hand-writing, etc. Universally usable. | ~599 |
| `MicrosoftAnimatedEmojies` | Fluent UI emoji set, animated. Cleaner geometric style than Apple/Google emoji. | ~1500 |
| `LargeEmoji` | Bigger expressive animated faces, useful for reactions / hero moments. | ~80 |
| `UtyaDuck` / `UtyaDuckFull` | Cute duck mascot reaction stickers. Great for casual / playful brands. | ~100 each |
| `XmasEmoji` / `HalloweenEmoji` | Seasonal sets. | ~50 each |
| `FluentEmoji` | Fluent-style alternative to AnimatedEmojies. | ~1000 |

Search `tg-stickers.com`, `combot.org/sticker`, or just `https://t.me/addstickers/<query>` to discover more. Most packs tagged "animated" are `.tgs` (Lottie). Packs tagged "video" are `.webm`, which is a different format entirely (not Lottie — closer to an alpha-channel video clip; needs a `<video>` element, not a Lottie player).

### How to spot an animated (Lottie) pack vs static/video

- **Animated (Lottie)**: pack listing in Telegram client shows stickers moving on hover, and the Bot API's `getStickerSet` returns `"is_animated": true`.
- **Static**: `.webp` files, no animation. Bot API returns `"is_animated": false, "is_video": false`. Not Lottie.
- **Video**: `.webm` files, longer animations with transparent backgrounds. Bot API returns `"is_video": true`. Also not Lottie, render with `<video>`.

The `fetch_sticker_pack.py` script in this skill prints which kind it found right after fetching the pack metadata.

### License conventions

- **Official Telegram packs** (`AnimatedEmojies`, etc.) — free for use as part of the platform's emoji set. Treating them as a free emoji library for app/website decoration is the norm; explicit commercial-redistribution licenses are not provided.
- **Third-party packs** — vary widely. Many are CC-0 or unmarked. Some have author tags inside the Lottie `nm` field (e.g., `"Thought Balloon (@syrreel)"`) — treat as informal attribution.
- **Commercial redistribution** (bundling animations into a sold/SaaS product where the animations are themselves a feature) — verify the pack page on Telegram or contact the pack author. For typical "use as decoration in our own product" the convention is permissive.

## Non-Telegram free sources

Used when Telegram doesn't have the specific animation needed, or when a higher level of licensing certainty is required.

| Source | Notes |
|---|---|
| **LottieFiles community** (lottiefiles.com/featured-free-animations) | Largest free Lottie library. Many under MIT / CC-BY. Filter by license. Inconsistent quality — pick by individual file. |
| **IconScout free tier** (iconscout.com/free-lotties) | Curated, smaller selection. Free tier requires attribution; paid tier removes it. |
| **Useanimations.com** | 100 free animated icons, MIT-licensed. Smaller / simpler than typical Telegram emoji but very clean. |
| **Pixsellz** | Small free Lottie pack, designed for marketing pages. |

For a project that needs ~10 specific animated icons, the typical workflow is: scan LottieFiles first for the exact concept; if anything is missing or inconsistent stylistically, fall back to a Telegram pack and accept the convention-based license.

## Anti-patterns

- **Don't scrape paid Lottie marketplaces** (LottieFiles premium, etc.) by inspecting their preview URLs. Their previews are intentionally watermarked or low-precision; the full file is licensed.
- **Don't grab animations from random websites** by saving their fetched `.json`. You don't know the license, the file may be customized for that site, and the author can't be credited.
- **Don't use animated stickers from a *single author's* personal pack** for a commercial product without asking. Telegram personal packs are author works; even if technically extractable, redistribution is rude.
