import { Heart } from "lucide-react";

/**
 * Visible footer credit linking back to meir.pro.
 *
 *   <MeirProCredit project="SapphireLoans" />
 *
 * Props:
 *   - project    (required) — short identifier appended to the link as ?s=<project>
 *                              for referral tracking. Should match the
 *                              `referrerLink` value in meir.pro's ExperienceList.
 *   - className  (optional) — extra classes on the wrapper <p>
 *   - adminHref  (optional) — if set, shift+clicking the link navigates here
 *                              instead of opening meir.pro (hidden admin entry)
 *
 * Features:
 *   - `select-all` wrapping span: selecting any part selects the whole credit
 *   - `sr-only` "love" span: when copied, pasted text reads "Made with love
 *     by Meir.pro" (screen-reader accessible + nice copy/paste experience)
 *   - Red <Heart> icon from lucide-react (install: `npm i lucide-react`)
 *   - Tailwind CSS classes — assumes the target project has Tailwind configured
 *
 * This is the visible component. The console credit lives in a separate
 * <script> snippet (see console-snippet.html) so removing one does not
 * affect the other.
 */
export default function MeirProCredit({ project, className = "", adminHref }) {
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
    if (adminHref && e.shiftKey) {
      e.preventDefault();
      window.location.assign(adminHref);
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
