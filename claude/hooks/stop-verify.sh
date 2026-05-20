#!/usr/bin/env bash
# Stop hook: run `npm run verify` before Claude declares done.
#
# What it catches: regressions Claude introduces — type errors, lint
# violations, broken tests, broken bundle. Same checks CI runs on PRs,
# so a green Stop hook means a green CI (for the local-checkable parts).
#
# What it doesn't catch: changes pushed by humans or other agents without
# going through Claude. Those rely on CI. By design.
#
# Skips when:
#   - The project ships its own .claude/hooks/stop-verify.sh — the project
#     copy wins (same deferral pattern format_code.sh uses here).
#   - The project has no `verify` npm script.
#   - Nothing under tracked code paths has changed AND no unpushed commits.
#   - Pure-docs sessions (matches CI's paths-ignore).
#
# Blocks the stop (exit 2) when verify fails. Claude sees stderr and is
# forced to fix the failure before claiming done.

set -u

# Defer to the project's hook if it ships one — keeps each project's
# tuned verify command authoritative. Same pattern as format_code.sh.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] \
   && [ -x "$CLAUDE_PROJECT_DIR/.claude/hooks/$(basename "$0")" ] \
   && [ "$(realpath "$CLAUDE_PROJECT_DIR/.claude/hooks/$(basename "$0")" 2>/dev/null)" != "$(realpath "$0" 2>/dev/null)" ]; then
  exit 0
fi

# Only meaningful for Node projects that define a `verify` npm script.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/package.json" ]; then
  if ! grep -q '"verify"[[:space:]]*:' "$CLAUDE_PROJECT_DIR/package.json" 2>/dev/null; then
    exit 0
  fi
fi

# Resolve the repo to validate. Fallbacks in priority order:
#
#   1. The `cwd` field from stdin JSON — this is the SESSION'S current
#      working directory at hook fire time, per Claude Code's hook spec.
#      When the agent is operating in a git worktree (e.g. after
#      EnterWorktree), this reflects the worktree, even though
#      CLAUDE_PROJECT_DIR stays pinned to the original launch directory.
#      Critical: without this fix, sessions that move into a worktree
#      mid-conversation still get verified against whatever WIP is
#      sitting in the main checkout, blocking on errors that aren't
#      theirs. Same pattern format_code.sh uses to read tool_input.
#
#   2. CLAUDE_PROJECT_DIR — Claude sets this for every hook invocation,
#      pinned to the launch directory. Used when (1) is unavailable
#      (older Claude versions or malformed input).
#
#   3. `git -C "$PWD" rev-parse --show-toplevel` — if neither (1) nor (2)
#      gave us a worktree-aware path.
#
#   4. Walk up from the script's own path. Last resort.
HOOK_INPUT=$(cat 2>/dev/null || true)
SESSION_CWD=""
if [ -n "$HOOK_INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    SESSION_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  else
    # jq fallback: extract "cwd": "value" via grep+sed.
    SESSION_CWD=$(echo "$HOOK_INPUT" \
      | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  fi
fi

REPO=""
# Only honor the session cwd if it actually points at a git worktree on disk.
if [ -n "$SESSION_CWD" ] && [ -d "$SESSION_CWD" ]; then
  CANDIDATE=$(git -C "$SESSION_CWD" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$CANDIDATE" ]; then REPO="$CANDIDATE"; fi
fi
if [ -z "$REPO" ]; then REPO="${CLAUDE_PROJECT_DIR:-}"; fi
if [ -z "$REPO" ]; then
  REPO=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
fi
if [ -z "$REPO" ]; then
  REPO=$(cd "$(dirname "$0")/../.." && pwd)
fi
cd "$REPO" || exit 0  # never block on a missing project dir

# --- Should we skip? ----------------------------------------------------------

# Anything modified, staged, or untracked that isn't ignored?
DIRTY=$(git status --porcelain 2>/dev/null)
# Any local commits not yet pushed to the tracked upstream? (Empty when on
# main with everything pushed, or on a brand-new branch with no upstream —
# in which case we still want to verify if working tree is dirty.)
UNPUSHED=""
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  UNPUSHED=$(git log @{u}..HEAD --oneline 2>/dev/null)
fi

if [ -z "$DIRTY" ] && [ -z "$UNPUSHED" ]; then
  exit 0  # nothing to verify
fi

# Docs-only? Mirror .github/workflows/ci-deploy.yml `paths-ignore`.
CHANGED_FILES=$(
  {
    git status --porcelain 2>/dev/null | awk '{print $NF}'
    [ -n "$UNPUSHED" ] && git diff --name-only @{u}..HEAD 2>/dev/null
  } | sort -u
)
NON_DOC=$(echo "$CHANGED_FILES" | grep -vE '(\.md$|^LICENSE$|^\.gitignore$|^\.github/ISSUE_TEMPLATE/|^\.vscode/|^\.idea/|^$)' || true)
if [ -z "$NON_DOC" ]; then
  exit 0  # docs-only session — same skip CI uses
fi

# --- Run verify ---------------------------------------------------------------

echo "[stop-hook] running npm run verify (format:check + lint + type-check + test + build)…" >&2

# Capture combined output instead of streaming it. ESLint emits warn-level
# noise (no-console etc.) that doesn't fail the gate but buries the real
# errors. We summarize: one green line on pass, errors-only on fail.
# npm_config_loglevel=silent drops the `> sweetcrm@1.0.0 …` lifecycle
# echoes from every nested `npm run` in the verify chain.
VERIFY_OUT=$(npm_config_loglevel=silent npm run verify 2>&1)
VERIFY_STATUS=$?

if [ "$VERIFY_STATUS" -eq 0 ]; then
  # Pull the allowed-warning count from ESLint's summary line, e.g.
  # "✖ 316 problems (0 errors, 316 warnings)". Absent ⇒ zero warnings.
  WARN_COUNT=$(echo "$VERIFY_OUT" \
    | grep -oE '[0-9]+ warnings?\)' | grep -oE '[0-9]+' | tail -1)
  echo "[stop-hook] verify passed ✓ — ${WARN_COUNT:-0} lint warnings (allowed); format, type-check, tests, build all green" >&2
  exit 0
fi

# Verify failed — surface ONLY the signal: drop ESLint warning lines, the
# "potentially fixable" hint, and orphan file-path headers left behind once
# their warnings are stripped. tsc/test/build errors never match these, so
# they pass through untouched. Tail keeps the failing step's tail concise.
echo "$VERIFY_OUT" \
  | grep -vE '^[[:space:]]+[0-9]+:[0-9]+[[:space:]]+warning[[:space:]]' \
  | grep -vE '[0-9]+ (errors?|warnings?) potentially fixable with the' \
  | grep -vE '^/.*\.(ts|tsx|js|jsx|json|css)$' \
  | grep -vE '^[[:space:]]*$' \
  | tail -40 >&2

# Exit 2 surfaces stderr to Claude and prevents the turn from ending.
cat >&2 <<'EOF'

[stop-hook] verify failed — fix the errors above before declaring done.
This blocks Claude from claiming the task is complete, NOT a real push.
Bypass for a real emergency by editing .claude/settings.json (don't).
EOF
exit 2
