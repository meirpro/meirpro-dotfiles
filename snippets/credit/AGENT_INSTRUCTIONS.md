# Agent Instructions — install meir.pro credit in a project

Paste this entire document into the Claude session working on the target project. Fill in the two `<FILL_IN>` placeholders at the top before pasting.

---

## Context for the agent

You are installing a two-part footer credit into this project:

1. **Visible React component** — a small "Made with ♥ by Meir.pro" line in the footer with a red lucide-react `<Heart>` icon. Uses Tailwind classes (`select-all`, `sr-only`, `text-muted-foreground`, etc.) — assume the project has Tailwind configured.
2. **Console ASCII-art credit** — an independent inline `<script>` that prints a cowboy-hat silhouette to the browser console on page load. Lives in HTML, not React, so it survives removal of the visible component.

Both pieces link back to `https://meir.pro/?s=<PROJECT_NAME>` for referral tracking. Pick **one** short identifier and use it in both places. It should match the `referrerLink` value in meir.pro's `src/pages/ExperienceList.js` if this project is listed there.

### Values to fill in

- **PROJECT_NAME**: `<FILL_IN — e.g. SapphireLoans, RuthKnappV2, KnappCartoons>`
- **Project type**: `<FILL_IN — e.g. Next.js App Router, Next.js Pages Router, CRA, Vite>`

---

## Step 1 — Verify prerequisites

Before writing anything, check:

```bash
# Is lucide-react installed?
cat package.json | grep -i "lucide-react"

# Is Tailwind configured?
ls tailwind.config.* 2>/dev/null
```

If `lucide-react` is not installed, ask the user whether to:
(a) `npm install lucide-react` (adds ~2 KB gzipped — standard icon library), or
(b) replace the `<Heart>` import with an inline SVG (zero dependencies)

If Tailwind is not configured, stop and tell the user — this component depends on Tailwind utility classes (`select-all`, `sr-only`, `text-muted-foreground`, etc.). A raw-CSS rewrite is possible but not automatic.

## Step 2 — Copy the visible component

Copy the component to the project's components directory. Prefer the existing convention — look at where other components live (`components/`, `src/components/`, `app/components/`, `app/_components/`).

```bash
cp ~/git/meirpro-dotfiles/snippets/credit/MeirProCredit.jsx \
   <target_components_dir>/MeirProCredit.jsx
```

For TypeScript projects, you can optionally rename to `.tsx` — the component has no explicit types but works as-is. If the project is strict-mode TS, add a minimal prop type:

```tsx
interface MeirProCreditProps {
  project: string
  className?: string
  hiddenHref?: string
}
```

### IMPORTANT — React Server Components compatibility (Next.js App Router)

The source file is marked `"use client"` at the top. **Do not remove this line.** The component has an `onClick` handler (for the optional `hiddenHref` shift-click feature), and function props cannot be serialized across the RSC boundary. Without `"use client"`, importing the component from a Server Component footer (the default in App Router) throws at runtime:

> Event handlers cannot be passed to Client Component props.
> `<a ... onClick={function handleClick} ...>`

The component is a tiny leaf island — ~200 bytes gzipped — so making it a client component has negligible cost. If you ever decide you don't want the hidden-link feature and want a zero-JS server component, delete the `"use client"` line AND the `hiddenHref` prop AND the `handleClick` handler together. Don't delete just one — they're a set.

### Dark-footer color overrides

The source component uses `text-muted-foreground` and `text-primary hover:text-accent` — these are shadcn/ui-style design-token classes that assume a **light background**. If the target project's footer is dark (e.g. `bg-sapphire text-white`, `bg-slate-900 text-white`), those classes will render the credit invisible or low-contrast. In that case, override them on the wrapper `className` and the link className so they inherit the parent's text color, e.g.:

```tsx
<MeirProCredit project="PROJECT_NAME" className="text-white/60" />
```

…and edit the link className inside the component from `text-primary hover:text-accent hover:underline font-medium` to something like `underline hover:text-white transition-colors`. Always check the footer's background color before installing and adjust accordingly.

### Tailwind v4 note

Tailwind v4 removed several legacy utility classes. If the project uses Tailwind v4 without a shadcn/ui-style theme layer, classes like `text-muted-foreground`, `text-primary`, and `text-accent` may not exist. Verify by grepping the project for `text-muted-foreground` — if it returns nothing, the project doesn't define those tokens and you must replace them with concrete colors (`text-white/60`, `text-slate-500`, etc.).

## Step 3 — Add it to the footer

Find the footer component (usually `Footer.tsx`, `footer.tsx`, or inline in `layout.tsx`). Import and render the component. Place it where the existing copyright or "All rights reserved" line lives — typically bottom-right or centered.

```tsx
import MeirProCredit from '@/components/MeirProCredit'

// inside the footer JSX
<MeirProCredit project="PROJECT_NAME" />
```

Match the project's existing footer layout (flex, grid, alignment). Do NOT wrap it in extra divs unless necessary for layout.

## Step 4 — Add the console snippet

### For Next.js App Router

Open `app/layout.tsx` (or `src/app/layout.tsx`). At the top, add:

```tsx
import Script from 'next/script'
```

Inside the `<body>` of the root layout, just before `{children}` closes (or just before `</body>`), add:

```tsx
<Script id="meirpro-credit" strategy="afterInteractive">{`
;(function(){
  var art = [
    '                                ░▒███▓▒░░░░▒▓██▓▒░                               ',
    '                               ░██████████████████▒                              ',
    '                               ▓██████████████████▓░                             ',
    '                              ▒████████████████████▒                             ',
    '                             ░▓████████████████████▓░                            ',
    '                             ▒██████████████████████░                            ',
    '                            ▓███████████████████████▓▒                           ',
    '                           ▒██████████████████████████▓                          ',
    '                          ░████████████████████████████░░░░                      ',
    '                         ░█████████████████████████████████████▓░                ',
    '         ▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█████████████████████████████████████████▓░             ',
    '         ▒█████████████████████████████████████████▓▒░▓█████████████▓░           ',
    '          ░██████████████████████████████████▓▒░     ░████████████████░          ',
    '            ░▓██████████████████████████▓▒░░░░░░░░░  ░█████████████████░         ',
    '              ░▒▓███████████████████▒▒░        ░░░▒▒▒░▓████████████████▒         ',
    '                 ░░▒▒█████████▓▒░░                 ░▒█▓██░░░░░░░░░░░░░░          ',
    '                       ░█▓░                           ▓▓█░                       ',
    '                        ▒▓░                           ▒█▓░                       ',
    '                         ▓█░                         ░█▒                         ',
    '                         ░█▒                         ▒░                          ',
    '                          ░                                                      ',
    '                                                                                 ',
    '                            ░                      ░░                            ',
    '                            ▒▒░               ░▒░ ▒█▒                            ',
    '                            ▓█▒░         ░░▒████░░██▓░                           ',
    '                           ░███▒ ░██████▒▓██▒░ ▒▒████░                           ',
    '                           █████░█▒            ▒█████▒                           ',
    '                         ░███████▒             ▓██████                           ',
    '                        ░▓███████▓░   ░▓▓▒   ░▓███████▒                          ',
    '                         ▒████████▓░ ▒███▒  ▒██████████                          ',
    '                          ▒████████████████████████████░                         ',
    '                           ░████████████████████████▓░                           ',
    '                            ░▓████████████████████▒░                             ',
    '                              ░▓███████████████▓░                                ',
    '                                ░▓███████████▒░                                  ',
    '                                  ░▒██████▓░                                     ',
    '                                     ░▒▓▒░                                       '
  ].join('\\n');
  var msg = '\\n' + art + '\\n\\n  Built by Meir Knapp\\n  https://meir.pro/?s=PROJECT_NAME\\n';
  if (typeof console !== 'undefined' && console.log) {
    console.log('%c' + msg, 'font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 11px; line-height: 1; color: #fff;');
  }
})();
`}</Script>
```

Replace `PROJECT_NAME` in the script string with the same value you used in Step 3.

### For Next.js Pages Router

Add the same logic to `pages/_document.tsx` via a `<Script>` in `<Head>` with `strategy="afterInteractive"`, OR paste the raw `<script>...</script>` tag inside `<Head>` using `__html`. The App Router pattern above is strongly preferred if both are available.

### For CRA / Vite / plain HTML

Paste the raw `<script>...</script>` tag (from `console-snippet.html`) into `public/index.html` or `index.html` inside `<head>`. No `next/script` wrapper needed. Replace `YOUR_PROJECT_NAME` in the `data-meirpro-project` attribute with the correct identifier.

## Step 5 — Verification

After installing, run:

```bash
npm run dev  # or whatever the project uses
```

Then:

1. Open the site in a browser
2. Scroll to the footer — you should see "Made with ♥ by Meir.pro" in small gray text with a red heart
3. Try selecting part of the credit text with your mouse — the entire credit should highlight as one unit (`select-all` behavior)
4. Copy the credit and paste it somewhere — pasted text should read "Made with love by Meir.pro" (the `sr-only` "love" word replaces the heart icon in clipboard)
5. Click "Meir.pro" — should open meir.pro in a new tab with `?s=PROJECT_NAME` in the URL
6. Open DevTools Console — you should see the cowboy-hat ASCII art followed by "Built by Meir Knapp" and the same link

If any of these fail, report back with specifics before committing.

## Step 6 — Commit

Create one commit for the change. Keep it focused:

```bash
git add <paths of all modified files>
git commit -m "feat: add meir.pro footer credit and console signature"
```

Do NOT stage unrelated files. Do NOT use `git add -A` or `git add .`.

---

## Notes on the select-all / sr-only trick

This is a polish detail that's easy to miss. The wrapping `<span className="select-all">` tells the browser "if the user starts selecting any text inside me, extend the selection to cover all of me." The nested `<span className="sr-only">love</span>` is visually hidden (via Tailwind's `sr-only` utility that uses `clip-path`) but is present in the DOM. When the user copies the selection, they get the full text "Made with love by Meir.pro" because the heart icon (an SVG) is not copyable as text, but the hidden "love" word is.

Net effect: the credit looks clean with a red heart, but when pasted elsewhere it reads naturally. Don't remove either wrapper — they're load-bearing for the UX.
