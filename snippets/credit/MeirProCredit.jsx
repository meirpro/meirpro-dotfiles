"use client";

import { Heart } from "lucide-react";

/**
 * Visible footer credit linking back to meir.pro.
 *
 *   <MeirProCredit project="SapphireLoans" />
 *   <MeirProCredit project="SapphireLoans" hiddenHref="/admin" />
 *
 * Props:
 *   - project     (required) — short identifier appended to the link as ?s=<project>
 *                               for referral tracking. Should match the
 *                               `referrerLink` value in meir.pro's ExperienceList.
 *   - className   (optional) — extra classes on the wrapper <p>
 *   - hiddenHref  (optional) — if set, shift+clicking the "Meir.pro" link
 *                               navigates here instead of opening meir.pro.
 *                               Use for any "hidden" destination: an admin
 *                               panel, a debug page, an easter egg, an
 *                               unlisted route, etc. Leave undefined for the
 *                               default behavior (just opens meir.pro).
 *
 * Features:
 *   - `select-all` wrapping span: selecting any part selects the whole credit
 *   - `sr-only` "love" span: when copied, pasted text reads "Made with love
 *     by Meir.pro" (screen-reader accessible + nice copy/paste experience)
 *   - Red <Heart> icon from lucide-react (install: `npm i lucide-react`)
 *   - Tailwind CSS classes — assumes the target project has Tailwind configured
 *
 * IMPORTANT — React Server Components compatibility:
 *   This file is marked `"use client"` because the shift-click handler for
 *   `hiddenHref` is a function prop, and function props cannot cross the RSC
 *   boundary. Without `"use client"`, importing this from a Server Component
 *   footer (typical in Next.js App Router) throws at runtime:
 *     "Event handlers cannot be passed to Client Component props."
 *   The JS cost is negligible (~200 bytes gzipped) and the component is a
 *   leaf, so the client island is tiny. If you want a zero-JS version,
 *   delete the `"use client"` line AND remove the `hiddenHref` prop +
 *   `handleClick` handler — you lose the hidden-link feature but ship no JS.
 *
 * This is the visible component. The console credit lives in a separate
 * <script> snippet (see console-snippet.html) so removing one does not
 * affect the other.
 */
export default function MeirProCredit({ project, className = "", hiddenHref }) {
  if (!project) {
    if (
      typeof process !== "undefined" &&
      process.env.NODE_ENV !== "production"
    ) {
      console.warn("[MeirProCredit] missing required `project` prop");
    }
  }

  const href = `https://meir.pro/?s=${encodeURIComponent(project || "unknown")}`;

  const handleClick = (e) => {
    if (hiddenHref && e.shiftKey) {
      e.preventDefault();
      window.location.assign(hiddenHref);
    }
  };

  return (
    <p className={`text-muted-foreground text-xs ${className}`}>
      <span className="select-all">
        Made with <span className="sr-only">love</span>
        <Heart
          aria-hidden="true"
          className="inline h-4 w-4 text-red-500 fill-current align-text-bottom"
          style={{ color: "#ef4444" }}
        />{" "}
        by{" "}
        <a
          href={href}
          target="_blank"
          rel="noopener noreferrer"
          onClick={handleClick}
          className="text-primary hover:text-accent hover:underline font-medium transition-colors"
        >
          Meir.pro
        </a>
      </span>
    </p>
  );
}
