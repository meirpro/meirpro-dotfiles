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

  # Shell: `something FILE > SAME-FILE`. The redirect truncates before the
  # command's first read. Requires the token to look like a path and to appear
  # BEFORE the redirect, so `cmd > fresh.log` is untouched.
  #
  # THE SCAN MUST RESPECT QUOTING. A `>` inside a quoted argument is text, and
  # the shell will not redirect on it — but a plain text match cannot tell the
  # difference, so any command carrying a quoted `>` next to a path-shaped word
  # was refused. Real false positive (2026-09-06): a task-tracker call whose
  # message read "...hayom-1.11.1-BUILD-CHANNEL.apk..." with angle brackets
  # around the placeholders. The scan took the `>` of a placeholder as a
  # redirect, `.apk` as the target, found `.apk` earlier in the same sentence,
  # and blocked a command that writes no file at all.
  #
  # Stripping quoted spans first would fix that and break the guard: the
  # dangerous form is very often `cmd "in.txt" > "in.txt"`, where the TARGET
  # itself is quoted, so removing quoted spans removes the evidence. Instead
  # this walks the string tracking quote state, finds a `>` at depth zero, and
  # unquotes only the target token.
  redirect_at=""
  {
    _s="$cmd"
    _n=${#_s}
    _sq=0
    _dq=0
    _i=0
    while [ "$_i" -lt "$_n" ]; do
      _c="${_s:_i:1}"
      # A backslash inside "..." escapes the next character, including a quote.
      if [ "$_dq" -eq 1 ] && [ "$_c" = "\\" ]; then
        _i=$((_i + 2))
        continue
      fi
      if [ "$_c" = "'" ] && [ "$_dq" -eq 0 ]; then
        _sq=$((1 - _sq))
      elif [ "$_c" = '"' ] && [ "$_sq" -eq 0 ]; then
        _dq=$((1 - _dq))
      elif [ "$_c" = ">" ] && [ "$_sq" -eq 0 ] && [ "$_dq" -eq 0 ]; then
        _prev=""
        [ "$_i" -gt 0 ] && _prev="${_s:_i-1:1}"
        _next="${_s:_i+1:1}"
        # `2>` is a stream number, `>>` appends — neither truncates on open.
        case "$_prev" in
          [0-9] | ">") _i=$((_i + 1)); continue ;;
        esac
        if [ "$_next" = ">" ]; then
          _i=$((_i + 2))
          continue
        fi
        redirect_at="$_i"
        break
      fi
      _i=$((_i + 1))
    done
  }

  target=""
  before=""
  if [ -n "$redirect_at" ]; then
    before="${cmd:0:redirect_at}"
    _rest="${cmd:redirect_at+1}"
    # Leading whitespace, then the token up to the next separator.
    #
    # FIRST LINE ONLY. `sed` is line-oriented, so without the `1` a multi-line
    # command yielded a multi-line "target" — one match per line — which then
    # matched nothing sensible and produced an unreadable refusal naming a
    # dozen words at once. A redirect target is one token on one line.
    _rest="${_rest#"${_rest%%[![:space:]]*}"}"
    target="$(printf '%s' "$_rest" | sed -n '1s/^\([^[:space:];|&<>]*\).*/\1/p')"
    # The target may itself be quoted — `> "out with spaces.txt"` — so compare
    # on the bare path, which is also what `before` would contain either way.
    target="${target%\"}"
    target="${target#\"}"
    target="${target%\'}"
    target="${target#\'}"
  fi

  if [ -n "$target" ] && printf '%s' "$target" | grep -Eq '[./]' && ! printf '%s' "$target" | grep -q '^-'; then
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
