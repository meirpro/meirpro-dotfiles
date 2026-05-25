# Embedding Lottie animations in web stacks

Per-framework code snippets for rendering Lottie JSON in production. Each section includes the package to install, an SSR/perf caveat if relevant, and a bundle-cost estimate so the right player gets picked for the stack.

## Player package comparison

| Package | Stack | Bundle (gzipped) | Format | Notes |
|---|---|---|---|---|
| `lottie-web` | Any | ~250 KB | `.json` | The reference player. Heaviest. Use when no framework wrapper fits. |
| `lottie-react` | React | ~50 KB | `.json` | Wraps `lottie-web` with hooks. Simplest React API. |
| `vue3-lottie` | Vue 3 | ~55 KB | `.json` | Vue 3 wrapper around `lottie-web`. |
| `@lottiefiles/dotlottie-web` | Any | ~30 KB | `.lottie` | LottieFiles' newer player. Renders `.lottie` (zipped) files. Smallest. |
| `@lottiefiles/dotlottie-react` | React | ~35 KB | `.lottie` | React binding for dotLottie. |
| `@lottiefiles/lottie-player` | Web Component | ~250 KB | `.json` / `.lottie` | `<lottie-player>` custom element. Framework-agnostic. |
| `@remotion/lottie` | Remotion only | bundled | `.json` | Remotion-aware: frame-accurate playback driven by `useCurrentFrame()`. |

**Decision rule of thumb**: pick `lottie-react` (or `vue3-lottie`) for a React/Vue app, `dotlottie-web` for vanilla / size-critical, `@remotion/lottie` for Remotion. Only reach for raw `lottie-web` when the framework doesn't have a wrapper.

## React (client-side)

```bash
npm install lottie-react
```

```tsx
import Lottie from "lottie-react";
import fireAnimation from "@/assets/lottie/fire.json";

export function FireIcon() {
  return (
    <Lottie
      animationData={fireAnimation}
      loop
      autoplay
      style={{ width: 64, height: 64 }}
    />
  );
}
```

Key props: `loop` (bool or number of loops), `autoplay`, `onComplete`, `onSegmentStart`, `lottieRef` (imperative `.play()`, `.pause()`, `.goToAndStop(frame)`).

## Next.js (App Router or Pages Router)

`lottie-web` (and therefore `lottie-react`) reads `document` at module load. SSR will crash. Two options:

**Option A — Dynamic import with SSR disabled:**

```tsx
"use client";
import dynamic from "next/dynamic";

const Lottie = dynamic(() => import("lottie-react"), { ssr: false });

export function FireIcon() {
  // animationData can still be imported normally — only the player needs the dynamic guard
  return <Lottie animationData={require("@/assets/lottie/fire.json")} loop />;
}
```

**Option B — Use `@lottiefiles/dotlottie-react` instead.** It has an explicit SSR-safe build and skips the dynamic-import dance entirely. Recommended for new Next.js work.

## Vue 3

```bash
npm install vue3-lottie
```

```vue
<script setup>
import { Vue3Lottie } from "vue3-lottie";
import fireAnimation from "@/assets/lottie/fire.json";
</script>

<template>
  <Vue3Lottie :animation-data="fireAnimation" :height="64" :width="64" :loop="true" />
</template>
```

For Nuxt 3 SSR, wrap in `<ClientOnly>` or use the dotLottie equivalent.

## Vanilla HTML

```html
<div id="fire" style="width: 64px; height: 64px;"></div>
<script src="https://cdn.jsdelivr.net/npm/lottie-web@5/build/player/lottie.min.js"></script>
<script>
  lottie.loadAnimation({
    container: document.getElementById("fire"),
    renderer: "svg",     // also: "canvas" (faster on many DOM nodes), "html"
    loop: true,
    autoplay: true,
    path: "/icons/fire.json",
  });
</script>
```

Switch `renderer` from `svg` to `canvas` if there are many simultaneous Lotties on one page — DOM weight from a hundred SVG nodes each can exceed canvas frame cost.

## Web Component (`<lottie-player>`)

Framework-free, drop-in:

```html
<script src="https://unpkg.com/@lottiefiles/lottie-player@latest/dist/lottie-player.js"></script>
<lottie-player
  src="/icons/fire.json"
  background="transparent"
  speed="1"
  style="width: 64px; height: 64px;"
  loop
  autoplay
></lottie-player>
```

Heavier than `dotlottie-web` but gives a clean HTML-level API. Useful in CMSes where editors can drop the tag without touching JS.

## Remotion (video work)

```bash
npm install @remotion/lottie
```

```tsx
import { staticFile } from "remotion";
import { Lottie, LottieAnimationData } from "@remotion/lottie";
import { useEffect, useState } from "react";

function FireIcon() {
  const [data, setData] = useState<LottieAnimationData | null>(null);
  useEffect(() => {
    fetch(staticFile("lottie/fire.json"))
      .then((r) => r.json())
      .then(setData);
  }, []);
  if (!data) return null;
  return <Lottie animationData={data} loop style={{ width: 64, height: 64 }} />;
}
```

**Critical**: Remotion's Lottie playback is driven by `useCurrentFrame()`, not wall-clock time. This means the loop is **deterministic and frame-aligned** — but it also means a Lottie whose natural loop length doesn't divide the composition's total frames will visibly freeze on the last frame. See SKILL.md "Loop math for video work" and `inspect_lottie.py --lcm`.

## Lazy-loading and performance

Three principles, regardless of stack:

1. **Defer player JS below the fold.** `lottie-react` is small but `lottie-web` is 250 KB. Don't load it for routes that don't use it. Code-split the player.
2. **Fetch JSON, don't import it.** `import fire from "fire.json"` inlines the entire animation into the JS bundle — terrible for tree-shaking and caching. Use `fetch("/icons/fire.json")` instead so the icon caches independently and downloads in parallel.
3. **Pause when off-screen.** Use `IntersectionObserver` to call `.pause()` when the Lottie scrolls out of view. CPU-cheap; significant battery wins on long pages with multiple Lotties.

```ts
const observer = new IntersectionObserver(([entry]) => {
  if (entry.isIntersecting) lottieRef.current?.play();
  else lottieRef.current?.pause();
});
observer.observe(containerRef.current!);
```

## Common bugs and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Blank rectangle, no errors | Player loaded before container had layout | Set explicit `width`/`height` on the container, or wait for `onLoad`. |
| `ReferenceError: document is not defined` | SSR rendering the player | Dynamic-import with `ssr: false`, or use a dotLottie SSR-safe player. |
| Animation plays once and stops | `loop` prop not set / set to `false` | Set `loop` (React) or `loop: true` (vanilla `loadAnimation`). |
| One Lottie among many freezes mid-loop in Remotion | Composition duration not a multiple of that file's video-frame loop | Recompute duration via `inspect_lottie.py --lcm`. |
| Animation visibly aliased / blurry | `renderer: "canvas"` upscaled past its rasterized size | Switch to `renderer: "svg"`, or render at a higher pixel density. |
| Huge file size (~5 MB) | Animation has embedded raster `assets[]` (PNG sequences) | These are heavy by design — consider re-authoring as pure vector, or compress the PNGs externally. |
