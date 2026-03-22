---
description: "Run the project's full verification suite (typecheck + lint + tests) in one shot"
allowed-tools:
  [
    "Bash(npx tsc:*)",
    "Bash(npm run lint:*)",
    "Bash(npm test:*)",
    "Bash(npm run test:*)",
    "Bash(npx vitest:*)",
    "Bash(npx eslint:*)",
    "Bash(cat package.json:*)",
    "Read",
  ]
---

# Self-Verification Loop

Run the project's full verification suite and report results. This is the "self-verifying loop" — use after making changes to catch issues before committing.

## Process

1. Read `package.json` to detect available scripts (test, lint, typecheck, build)
2. Run each check **sequentially**, stopping to report on first failure:
   - **TypeScript**: `npx tsc --noEmit`
   - **Lint**: `npm run lint` (or project equivalent)
   - **Tests**: `npm test` (or `npx vitest run`)
3. Report a clear pass/fail summary

## Output Format

```
--- Verify ---
[PASS] TypeScript — no type errors
[PASS] Lint — clean
[FAIL] Tests — 2 failing in src/lib/dates.test.ts
---
```

If a step fails, show the relevant error output and suggest a fix. Do NOT auto-fix — just report.

## Rules

- If `package.json` doesn't have a test script, skip tests and note it
- If tsc is not available, skip typecheck and note it
- Never modify code — this is read-only verification
- Keep output concise — only show errors, not full passing output
