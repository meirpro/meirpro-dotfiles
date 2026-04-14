# Snippets

Reusable code snippets that get copied into client/personal projects. These are intentionally **not** an npm package — they ship as source files you own in the target project. See `credit/README.md` for the design rationale.

## Available snippets

| Snippet | What it is | Where to put it |
|---|---|---|
| `credit/` | meir.pro footer credit (React component) + console ASCII-art credit (HTML script) | See below |

---

## Install instructions for Claude (and humans)

When asked to install a snippet into a target project, follow these exact steps.

### 1. `credit/MeirProCredit.jsx` — visible React footer credit

```bash
cp ~/Documents/GitHub/meirpro-dotfiles/snippets/credit/MeirProCredit.jsx \
   <target_project>/src/components/MeirProCredit.jsx
```

For Next.js App Router projects, use `app/_components/` or `components/` — match the project's existing convention.

Then edit the project's footer component to import and render it:

```jsx
import MeirProCredit from './components/MeirProCredit'

<footer>
  <MeirProCredit project="<ShortProjectName>" />
</footer>
```

Choose `<ShortProjectName>` to match what you pass to the console snippet below (for consistent referral tracking).

### 2. `credit/console-snippet.html` — independent console credit

Copy the entire `<script data-meirpro-project="...">...</script>` block from `snippets/credit/console-snippet.html` and paste it into the project's HTML entry point. **Do not** include the surrounding HTML comment — just the `<script>` tag and its contents.

**Target file by framework:**

| Framework | File | Where inside the file |
|---|---|---|
| **Create React App** | `public/index.html` | Inside `<head>` |
| **Vite (React/Vue/Svelte)** | `index.html` | Inside `<head>` |
| **Next.js App Router** | `app/layout.tsx` | Use `next/script` `<Script strategy="afterInteractive">` — see Next.js notes below |
| **Next.js Pages Router** | `pages/_document.tsx` | Inside `<Head>` of the `Html` component |
| **Astro** | `src/layouts/Layout.astro` or equivalent | Inside `<head>` |
| **SvelteKit** | `src/app.html` | Inside `<head>` |
| **Nuxt** | `nuxt.config.ts` | Use `app.head.script` array |
| **Plain HTML** | `index.html` or equivalent | Inside `<head>` |

Always update `data-meirpro-project="YOUR_PROJECT_NAME"` to the same `<ShortProjectName>` used above.

### Next.js App Router specifics

The raw `<script>` tag won't work directly in `app/layout.tsx` — wrap it in `next/script`:

```tsx
import Script from 'next/script'

<Script
  id="meirpro-credit"
  strategy="afterInteractive"
  data-meirpro-project="SapphireLoans"
>{`
  ;(function () {
    // ... paste the IIFE body from console-snippet.html here
  })()
`}</Script>
```

`strategy="afterInteractive"` is correct — the script is non-critical and just logs to console, so it shouldn't block render.

### CSP notes

If the target project has a strict `Content-Security-Policy`, the inline script may be blocked unless `script-src` allows `'unsafe-inline'` or a nonce. In that case either:
- Add the nonce via the framework's CSP mechanism, or
- Move the console snippet to a separate `.js` file served from the same origin and reference it via `<script src="/meirpro-credit.js">`.

---

## Referral tracking

Both snippets construct a link to `https://meir.pro/?s=<project>`. The `?s=` param matches `referrerLink` entries in `meir.pro`'s `src/pages/ExperienceList.js` — when someone clicks through, meir.pro highlights the matching project card on load. Keep the name consistent between both snippets and the portfolio entry.

## Updates

When a snippet evolves in `meirpro-dotfiles`, client projects don't auto-update. Re-run the copy step manually, or diff the current file against the dotfiles version and merge. This is an intentional design choice (see `credit/README.md`).
