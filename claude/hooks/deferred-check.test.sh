#!/bin/bash
# Tests for deferred-check. Run: bash claude/hooks/deferred-check.test.sh
# Everything runs in a throwaway state dir and HOME; nothing touches ~/.claude.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/deferred-check"
SETTINGS="$HERE/../bin/claude-settings"
T=$(mktemp -d)
export DEFERRED_CHECK_DIR="$T/state"
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "  ok    $1"; }
no() { fail=$((fail + 1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && echo "        got: $2"; }

# fire SESSION EVENT NAME [opts] -- CMD...  → prints the hook's stdout
fire() {
  local sid=$1 ev=$2
  shift 2
  printf '{"session_id":"%s","hook_event_name":"%s","cwd":"/x"}' "$sid" "$ev" | "$HOOK" "$@"
}
# settle NAME: wait for the background run to finish
settle() {
  local i
  for i in $(seq 100); do
    [ -d "$DEFERRED_CHECK_DIR/$1/lock" ] || return 0
    sleep 0.05
  done
  return 1
}
state() { cat "$DEFERRED_CHECK_DIR/$1/$2" 2>/dev/null; }

echo "A standing problem:"
out=$(fire s1 UserPromptSubmit c1 --every 0 -- sh -c 'echo boom; exit 1')
code=$?
settle c1
[ "$code" = 0 ] && [ -z "$out" ] && [ "$(state c1 last.exit)" = 1 ] &&
  ok "the first firing says nothing, exits 0, and the run is recorded" ||
  no "first firing" "exit=$code out=$out last.exit=$(state c1 last.exit)"

started=$(state c1 started)
out=$(fire s1 UserPromptSubmit c1 --every 3600 -- sh -c 'exit 0')
echo "$out" | jq -e '(.systemMessage | contains("c1: boom"))
  and .hookSpecificOutput.hookEventName == "UserPromptSubmit"
  and (.hookSpecificOutput.additionalContext | contains("boom"))' >/dev/null &&
  ok "the next firing says the previous result: systemMessage + additionalContext" ||
  no "next firing" "$out"

out=$(fire s1 UserPromptSubmit c1 --every 3600 -- true)
[ -z "$out" ] && ok "the same session is not told twice" || no "told twice" "$out"

out=$(fire s2 SessionStart c1 --every 3600 -- true)
echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null &&
  ok "another session is told, with its own event name" || no "other session" "$out"

out=$(fire s3 Stop c1 --every 3600 -- true)
echo "$out" | jq -e '.systemMessage and (has("hookSpecificOutput") | not)' >/dev/null &&
  ok "Stop gets systemMessage only (it takes no additionalContext)" || no "Stop" "$out"

[ "$(state c1 started)" = "$started" ] &&
  ok "no new run inside --every" || no "throttle" "started moved"

fire s4 UserPromptSubmit c1 --every 0 -- true >/dev/null
settle c1
out=$(fire s4 UserPromptSubmit c1 --every 3600 -- true)
[ -z "$out" ] && [ "$(state c1 last.exit)" = 0 ] &&
  ok "a clean run silences the problem for a session not yet told" || no "clean run" "$out"

echo
echo "An event (exit 3):"
fire s1 UserPromptSubmit c2 --every 0 -- sh -c 'echo reverted it; exit 3' >/dev/null
settle c2
out=$(fire s1 UserPromptSubmit c2 --every 0 -- true)
settle c2
echo "$out" | jq -e '.systemMessage | contains("reverted it")' >/dev/null &&
  ok "it is told on the next firing" || no "event told" "$out"
out=$(fire s1 UserPromptSubmit c2 --every 3600 -- true)
[ -z "$out" ] && ok "and only once in that session" || no "event twice" "$out"
out=$(fire s5 UserPromptSubmit c2 --every 3600 -- true)
[ "$(state c2 last.exit)" = 0 ] && echo "$out" | jq -e '.systemMessage | contains("reverted it")' >/dev/null &&
  ok "a later session is still told after a clean run" || no "event kept" "$out"

echo
echo "Housekeeping:"
mkdir -p "$DEFERRED_CHECK_DIR/c3/lock"
echo 999999 >"$DEFERRED_CHECK_DIR/c3/lock/pid"
echo $(($(date +%s) - 100)) >"$DEFERRED_CHECK_DIR/c3/started"
fire s1 UserPromptSubmit c3 --every 0 -- true >/dev/null
settle c3
[ "$(state c3 last.exit)" = 0 ] && ok "a dead run's lock is cleared and the check runs" || no "dead lock"

fire s1 UserPromptSubmit c4 --every 0 -- sleep 3 >/dev/null
echo $(($(date +%s) - 700)) >"$DEFERRED_CHECK_DIR/c4/started"
out=$(fire s1 UserPromptSubmit c4 --every 3600 -- true)
echo "$out" | jq -e '.systemMessage | contains("still running")' >/dev/null &&
  ok "a run past --stale is reported as still running" || no "stale" "$out"
settle c4

t0=$(python3 -c 'import time;print(time.time())')
for i in $(seq 20); do fire s9 UserPromptSubmit c1 --every 3600 -- true >/dev/null; done
ms=$(python3 -c "import time;print(round((time.time()-$t0)/20*1000,1))")
python3 -c "import sys;sys.exit(0 if $ms < 100 else 1)" &&
  ok "a firing that starts nothing takes ${ms} ms" || no "speed: ${ms} ms per firing"

echo
echo "End to end: Vibe Island's ungated hook planted in a throwaway HOME:"
H="$T/home"
mkdir -p "$H/.claude"
cat >"$T/public.json" <<'JSON'
{"model": "x", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/a.sh"}]}]}}
JSON
cat >"$T/private.json" <<'JSON'
{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/bin/sh -c '[ -S \"$HOME/.vibe-island/run/vibe-island.sock\" ] || exit 0; \"$HOME/.vibe-island/bin/vibe-island-bridge\"'"}]}]}}
JSON
export CLAUDE_SETTINGS_PUBLIC="$T/public.json" CLAUDE_SETTINGS_PRIVATE="$T/private.json"
HOME="$H" python3 "$SETTINGS" build >/dev/null
python3 - "$H/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hooks"].setdefault("UserPromptSubmit", []).append(
    {"hooks": [{"type": "command", "command":
        "/bin/sh -c '[ -x \"$HOME/.vibe-island/bin/vibe-island-bridge\" ] && "
        "\"$HOME/.vibe-island/bin/vibe-island-bridge\" --source claude; exit 0'"}]})
json.dump(d, open(p, "w"))
PY
HOME="$H" fire s1 SessionStart guard --every 0 -- python3 "$SETTINGS" revert-hooks 'vibe-island[-]bridge' >/dev/null
settle guard
out=$(HOME="$H" fire s1 UserPromptSubmit guard --every 3600 -- true)
cmp -s "$H/.claude/settings.json" "$H/.claude/.settings.built.json" &&
  echo "$out" | jq -e '.systemMessage | contains("Restored the last build")' >/dev/null &&
  ok "the guard restores the build and the next prompt says so" ||
  no "end to end" "$out"

rm -rf "$T"
echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
