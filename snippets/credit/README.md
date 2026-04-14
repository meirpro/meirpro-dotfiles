# meir.pro credit snippets

Two independent snippets to attribute work back to meir.pro across client projects. Use both, or just one — they don't depend on each other.

## 1. Visible footer credit (`MeirProCredit.jsx`)

A small React component that renders a "Made with ♥ by Meir.pro" line. Drop into a footer.

**Install:**

```bash
cp meirpro-dotfiles/snippets/credit/MeirProCredit.jsx <project>/src/components/
```

**Use:**

```jsx
import MeirProCredit from './components/MeirProCredit'

<footer>
  <MeirProCredit project="SapphireLoans" />
</footer>
```

**Props:**

| Prop | Required | Default | Description |
|---|---|---|---|
| `project` | yes | — | Short identifier used in the referral link as `?s=<project>` |
| `className` | no | `''` | Extra classes on the wrapper `<p>` |
| `heart` | no | `'♥'` | Heart character (override per project for variety) |
| `adminHref` | no | — | If set, shift+clicking the credit navigates here instead of opening meir.pro |

The `adminHref` shift-click pattern is a quiet way to add an admin entry point without cluttering the public UI with a visible "Admin" button.

## 2. Console credit (`console-snippet.html`)

A `<script>` tag that prints an ASCII-art credit to the browser console on every page load. Lives in HTML, not React, so it survives component removal, CSS hiding, and most non-developer attempts at deletion.

**Install:**

Copy the entire `<script>...</script>` block from `console-snippet.html` and paste it into the project's HTML entry point:

| Project type | File |
|---|---|
| Create React App | `public/index.html` (in `<head>`) |
| Next.js (App Router) | `app/layout.tsx` — wrap in `<Script>` from `next/script` with `strategy="afterInteractive"` |
| Next.js (Pages Router) | `pages/_document.tsx` |
| Vite | `index.html` (in `<head>`) |
| Astro | `src/layouts/Layout.astro` |
| Plain HTML | anywhere in `<head>` or `<body>` |

**Configure:**

Set `data-meirpro-project="..."` on the `<script>` tag to the project identifier (used as `?s=<name>` in the referral link). Match this to whatever you pass to the React component above for consistency.

```html
<script data-meirpro-project="SapphireLoans">
  ...
</script>
```

## Why two pieces?

Decoupling them gives the credit a fallback layer. If a non-technical project owner removes the visible footer credit (it has happened), the console credit still runs. Conversely, if a strict CSP or some script-stripping build step kills the console snippet, the visible credit still attributes.

## Updates

Both files live in `meirpro-dotfiles/snippets/credit/`. When the components evolve, copy the latest versions into client projects manually. There is intentionally no npm package or auto-update mechanism — see [the design discussion](https://github.com/meirpro/meir.pro/blob/main/docs/superpowers/specs/2026-04-10-portfolio-refresh-design.md) for why.
