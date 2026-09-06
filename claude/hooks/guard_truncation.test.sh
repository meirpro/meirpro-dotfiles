#!/usr/bin/env bash
#
# Cases for guard_truncation.sh's `pre` half.
#
# Written after the guard refused a command that writes no file at all
# (2026-09-06): a task-tracker call whose message contained
# `hayom-1.11.1-<build>-<channel>.apk`. The scan read the placeholder's `>` as
# a redirect, `.apk` as the target, found `.apk` earlier in the same sentence,
# and blocked. A guard that fires on prose is a guard people route around.
#
# The two halves have to hold together, which is why both directions are here:
# a scan loose enough to catch `cmd f > f` and tight enough to ignore a `>`
# inside quotes. Deleting either column re-opens the failure the other prevents.
#
#   bash guard_truncation.test.sh

set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/guard_truncation.sh"
pass=0
fail=0

run() {
  local cmd="$1"
  printf '{"tool_input":{"command":%s}}' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd")" |
    bash "$HOOK" pre >/dev/null 2>&1
  printf '%s' "$?"
}

check() {
  local want="$1" cmd="$2" got
  got="$(run "$cmd")"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    printf '  ok    %s\n' "$cmd"
  else
    fail=$((fail + 1))
    printf '  FAIL  (want %s, got %s)  %s\n' "$want" "$got" "$cmd"
  fi
}

echo "BLOCKS a real truncate-before-read:"
check 2 'sort in.txt > in.txt'
# The dangerous form very often quotes its paths, which is exactly why the
# quote-aware scan unquotes the TARGET rather than stripping quoted spans.
check 2 'sort "in.txt" > "in.txt"'
check 2 'jq . data/x.json > data/x.json'
check 2 'python3 -c "import x" build/out.js > build/out.js'

echo
echo "ALLOWS commands that write nothing, or write elsewhere:"
# The reported false positive.
check 0 'cc done HAY-49 --why "shows hayom-1.11.1-<build>-<channel>.apk at the start"'
check 0 'echo "a -> b" > fresh.log'
check 0 'sort in.txt > out.txt'
check 0 'python x.py 2> err.log'
# `>>` appends; it does not truncate on open.
check 0 'cat a.txt >> a.txt'
check 0 'echo "<div class=x>report.apk</div>"'
# A `>` inside single quotes is text too.
check 0 "grep -o 'a>b' notes.txt"
# No redirect at all.
check 0 'git log --oneline -1'

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
