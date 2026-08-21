#!/usr/bin/env bash
#
# Guard against scripted in-place file truncation.
#
# WHY THIS EXISTS (2026-08-21): an agent ran, in a Bash heredoc,
#
#     open(path, "w", encoding="utf-8").write(add(open(path).read(), loc))
#
# Python evaluates `open(path, "w")` FIRST — that is the object whose `.write`
# is being looked up — so the file is already truncated to zero bytes by the
# time the argument `open(path).read()` runs. It read back an empty file, wrote
# an empty result, and destroyed another agent's uncommitted edits to a shared
# i18n file. Nothing errored. The only reason the work was recoverable is that
# a `git diff` of it happened to be in the transcript minutes earlier.
#
# Two halves, because neither alone is enough:
#
#   pre  — refuse the KNOWN IDIOMS before they run. Cheap, precise, and the
#          only half that actually prevents data loss.
#   post — detect the OUTCOME, whatever produced it: a tracked file that is now
#          zero bytes and was not zero bytes in HEAD. This catches truncation
#          from mechanisms the pre-check has never heard of (a `sed -i` gone
#          wrong, a botched `tee`, a Node script, a future language), which is
#          the whole point of guarding the result rather than the syntax.
#
# The post half is deliberately narrow — EMPTY, not "shrank a lot". A partial
# overwrite is a judgement call; a tracked file at zero bytes is never
# something anyone meant to do, so it has no false positives and can be loud.
#
# Usage: guard_truncation.sh pre|post   (hook JSON on stdin)

set -uo pipefail

mode="${1:-}"
payload="$(cat)"

# ── pre: refuse the idioms ────────────────────────────────────────────────
if [ "$mode" = "pre" ]; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)"
  [ -z "$cmd" ] && exit 0

  # Python (and any language with the same evaluation order): a write-mode
  # open whose .write() argument opens something. The read is evaluated after
  # the truncation, so it always reads an empty file.
  if printf '%s' "$cmd" | grep -Eq 'open\([^)]*["'"'"']w["'"'"'][^)]*\)[[:space:]]*\.write\(.*open\('; then
    cat >&2 <<'MSG'
BLOCKED — truncate-before-read.

  open(p, "w").write( ... open(p).read() ... )

Python evaluates open(p, "w") before the argument, so the file is already
empty when the read runs. You will write an empty file and lose whatever was
there — including any uncommitted work by a parallel agent.

Read first, into a variable, then write:

  current = open(path, encoding="utf-8").read()
  updated = transform(current)
  open(path, "w", encoding="utf-8").write(updated)
MSG
    exit 2
  fi

  # Shell: `something <file> > <same file>`. The redirect truncates before the
  # command's first read. Requires the token to look like a path and to appear
  # BEFORE the redirect, so `cmd > fresh.log` is untouched.
  target="$(printf '%s' "$cmd" | sed -n 's/.*[^0-9>]>[[:space:]]*\([^[:space:];|&<>]*\).*/\1/p' | head -1)"
  if [ -n "$target" ] && printf '%s' "$target" | grep -Eq '[./]' && ! printf '%s' "$target" | grep -q '^-'; then
    before="${cmd%%>*}"
    if printf '%s' "$before" | grep -Fq -- "$target"; then
      cat >&2 <<MSG
BLOCKED — truncate-before-read: "$target" is both an input and the > target.

The shell opens the redirect (truncating it) before the command runs, so the
command reads an empty file. Write to a temporary file and move it into place:

  cmd "$target" > "$target.tmp" && mv "$target.tmp" "$target"
MSG
      exit 2
    fi
  fi
  exit 0
fi

# ── post: detect the outcome ──────────────────────────────────────────────
if [ "$mode" = "post" ]; then
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

  # Only files git already knows changed — keeps this O(diff), not O(repo).
  emptied=""
  while IFS=$'\t' read -r added removed file; do
    [ "$added" = "0" ] || continue          # nothing written
    [ "$removed" = "0" ] && continue        # was already empty
    [ -e "$file" ] || continue              # deleted is a different thing
    [ -s "$file" ] && continue              # still has content
    emptied="${emptied}${file}"$'\n'
  done < <(git diff --numstat HEAD 2>/dev/null)

  [ -z "$emptied" ] && exit 0

  {
    echo "TRUNCATION DETECTED — tracked file(s) are now ZERO BYTES:"
    printf '%s' "$emptied" | sed 's/^/  /'
    echo
    echo "This is almost never intentional. Before doing anything else:"
    echo
    printf '%s' "$emptied" | while read -r f; do
      [ -n "$f" ] && echo "  git checkout HEAD -- $f"
    done
    echo
    echo "That restores the committed content. Any UNCOMMITTED edits that were"
    echo "in the file are gone from disk — check this transcript for a recent"
    echo "'git diff' of it, and reapply by hand. Say so plainly; a parallel"
    echo "agent may have been the author."
  } >&2
  exit 2
fi

exit 0
