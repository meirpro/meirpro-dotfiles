import { useEffect } from "react";

/**
 * Visible footer credit linking back to meir.pro.
 *
 *   <MeirProCredit project="SapphireLoans" />
 *
 * Props:
 *   - project    (required) — short identifier appended to the link as ?s=<project>
 *                              for referral tracking
 *   - className  (optional) — extra classes on the wrapper <p>
 *   - heart      (optional) — character to render as the heart (default: '♥')
 *   - adminHref  (optional) — if set, shift+clicking the link navigates here
 *                              instead of opening meir.pro
 *
 * This is the visible component. The console credit lives in a separate
 * <script> snippet (see console-snippet.html) so removing one does not
 * affect the other.
 */
export default function MeirProCredit({
  project,
  className = "",
  heart = "♥",
  adminHref,
}) {
  if (!project) {
    // Fail loud in dev so we don't ship an untracked credit
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
      // Navigate within the same tab; consumer can change to router.push if needed
      window.location.assign(adminHref);
    }
  };

  return (
    <p
      className={className}
      style={{
        fontSize: "0.875rem",
        color: "#6b7280",
        margin: 0,
      }}
    >
      Made with{" "}
      <span aria-hidden="true" style={{ color: "#ef4444" }}>
        {heart}
      </span>
      <span style={{ position: "absolute", left: "-9999px" }}>love</span> by{" "}
      <a
        href={href}
        target="_blank"
        rel="noopener noreferrer"
        onClick={handleClick}
        style={{
          color: "inherit",
          textDecoration: "underline",
          textUnderlineOffset: "2px",
        }}
      >
        Meir.pro
      </a>
    </p>
  );
}
