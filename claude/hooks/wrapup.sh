#!/bin/bash
# wrapup.sh — self-driving /wrapup orchestrator.
#
# One-shot replacement for the 10-step `/wrapup` skill procedure. Does all
# the mechanical work (session resolve, telemetry, git, JSONL slice,
# Haiku summary, POST) and prints a single structured report.
#
# Usage:  bash ~/.claude/hooks/wrapup.sh <session_id>
#         (or:  bash ~/.claude/hooks/wrapup.sh   — falls back to env $CLAUDE_SESSION_ID)
#
# Exit codes:
#   0  wrapup completed (POST may have queued — that's not a hard failure)
#   2  unresolvable session id (literal ${CLAUDE_SESSION_ID}, no file, no transcript)
#   3  prerequisite missing (claude CLI, jq, python3, session_wrapup.sh)
#
# See: ~/Documents/GitHub/command-center/docs/superpowers/plans/2026-05-25-wrapup-self-driving.md

set -uo pipefail

SID="${1:-${CLAUDE_SESSION_ID:-}}"
HOOKS_DIR="$HOME/.claude/hooks"
SESSIONS_DIR="$HOME/.claude/sessions"
WRAPUPS_DIR="$HOME/.claude/wrapups"
TIME_LOG="$HOME/.claude/time-log.jsonl"
TIMINGS_DIR="$HOME/.claude/timings"

# --- Prereqs ---
for bin in jq python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "wrapup.sh: missing prereq: $bin" >&2; exit 3; }
done
[ -f "$HOOKS_DIR/session_wrapup.sh" ] \
  || { echo "wrapup.sh: missing $HOOKS_DIR/session_wrapup.sh" >&2; exit 3; }

# --- Validate SID ---
if [ -z "$SID" ] || [[ "$SID" == *'${CLAUDE_SESSION_ID}'* ]]; then
  echo "wrapup.sh: no session_id (Claude Code did not substitute \${CLAUDE_SESSION_ID})." >&2
  echo "  Pass it as the first arg, or set CLAUDE_SESSION_ID in the environment." >&2
  exit 2
fi

mkdir -p "$WRAPUPS_DIR"
SIDECAR="$WRAPUPS_DIR/$SID.jsonl"

# --- Resolve session file (retry 3× with 1s sleeps for lazy heartbeat race) ---
SESSION_FILE=""
for _try in 1 2 3; do
  if [ -f "$SESSIONS_DIR/$SID.json" ]; then
    SESSION_FILE="$SESSIONS_DIR/$SID.json"; break
  fi
  RESOLVED="$(python3 "$HOOKS_DIR/session_lib.py" resolve "$SID" 2>/dev/null || true)"
  if [ -n "$RESOLVED" ] && [ -f "$RESOLVED" ]; then
    SESSION_FILE="$RESOLVED"; break
  fi
  sleep 1
done

# Fallback: synthesize from transcript JSONL
if [ -z "$SESSION_FILE" ]; then
  python3 "$HOOKS_DIR/transcript_to_session.py" synthesize "$SID" >/dev/null 2>&1 || true
  if [ -f "$SESSIONS_DIR/$SID.json" ]; then
    SESSION_FILE="$SESSIONS_DIR/$SID.json"
  fi
fi

if [ -z "$SESSION_FILE" ]; then
  echo "wrapup.sh: cannot resolve session file for $SID (no file, no transcript)" >&2
  exit 2
fi

# --- Read session file: project, branch, telemetry.live, last_wrapup ---
PROJECT_PATH="$(jq -r '.project_path // .cwd // "?"' "$SESSION_FILE")"
SESSION_START="$(jq -r '.start // ""' "$SESSION_FILE")"
LAST_WRAPUP="$(jq -r '.last_wrapup // .start // ""' "$SESSION_FILE")"
WRAPUP_COUNT_PREV="$(jq -r '.wrapup_count // 0' "$SESSION_FILE")"
TELEMETRY_LAST_UPDATED="$(jq -r '.telemetry.live.last_updated // ""' "$SESSION_FILE")"
CUM_COST="$(jq -r '.telemetry.live.cost_usd // 0' "$SESSION_FILE")"
CUM_WALL_MS="$(jq -r '.telemetry.live.wall_duration_ms // 0' "$SESSION_FILE")"
CUM_API_MS="$(jq -r '.telemetry.live.api_duration_ms // 0' "$SESSION_FILE")"

# Heal "?" sentinel project_path with current pwd (matches session_wrapup.sh logic)
if [ "$PROJECT_PATH" = "?" ] || [ -z "$PROJECT_PATH" ]; then
  PROJECT_PATH="$(pwd)"
fi

BRANCH="$(git -C "$PROJECT_PATH" branch --show-current 2>/dev/null || echo n/a)"

# --- Reconcile telemetry vs claude-timed timings ---
# Telemetry wins; only emit warning when they disagree >10% on wall.
RECONCILE_WARNING=""
CUMULATIVE_SOURCE="telemetry"
TIMINGS_FILE="$TIMINGS_DIR/$SID.jsonl"
if [ -z "$TELEMETRY_LAST_UPDATED" ] || [ "$CUM_WALL_MS" = "0" ]; then
  if [ -f "$TIMINGS_FILE" ]; then
    TIMINGS_WALL_MS="$(jq -s 'map((.typing_ms // 0) + (.agent_work_ms // 0) + (.idle_ms // 0)) | add // 0' "$TIMINGS_FILE" 2>/dev/null || echo 0)"
    if [ "$TIMINGS_WALL_MS" != "0" ] && [ "$TIMINGS_WALL_MS" != "null" ]; then
      CUM_WALL_MS="$TIMINGS_WALL_MS"
      CUMULATIVE_SOURCE="timings_only"
    else
      CUMULATIVE_SOURCE="stub"
    fi
  else
    CUMULATIVE_SOURCE="stub"
  fi
elif [ -f "$TIMINGS_FILE" ]; then
  TIMINGS_WALL_MS="$(jq -s 'map((.typing_ms // 0) + (.agent_work_ms // 0) + (.idle_ms // 0)) | add // 0' "$TIMINGS_FILE" 2>/dev/null || echo 0)"
  if [ "$TIMINGS_WALL_MS" != "0" ] && [ "$TIMINGS_WALL_MS" != "null" ] && [ "$CUM_WALL_MS" != "0" ]; then
    DIFF_PCT="$(python3 -c "
t=$CUM_WALL_MS; x=$TIMINGS_WALL_MS
print(round(abs(t-x)/max(t,1)*100,1))
" 2>/dev/null || echo 0)"
    if python3 -c "import sys; sys.exit(0 if $DIFF_PCT > 10 else 1)" 2>/dev/null; then
      RECONCILE_WARNING="telemetry wall=${CUM_WALL_MS}ms vs timings wall=${TIMINGS_WALL_MS}ms (${DIFF_PCT}% diff)"
    fi
  fi
fi

# --- Read sidecar for prev cumulative ---
PREV_CUM_COST=0
PREV_CUM_WALL_MS=0
PREV_CUM_API_MS=0
PREV_TS=""
PREV_WRAPUP_N=0
if [ -f "$SIDECAR" ]; then
  PREV_LINE="$(tail -1 "$SIDECAR" 2>/dev/null)"
  if [ -n "$PREV_LINE" ]; then
    PREV_CUM_COST="$(echo "$PREV_LINE" | jq -r '.cum_cost // 0')"
    PREV_CUM_WALL_MS="$(echo "$PREV_LINE" | jq -r '.cum_wall_ms // 0')"
    PREV_CUM_API_MS="$(echo "$PREV_LINE" | jq -r '.cum_api_ms // 0')"
    PREV_TS="$(echo "$PREV_LINE" | jq -r '.ts // ""')"
    PREV_WRAPUP_N="$(echo "$PREV_LINE" | jq -r '.wrapup_n // 0')"
  fi
fi

if [ -z "$PREV_TS" ]; then
  PREV_TS="${LAST_WRAPUP:-$SESSION_START}"
fi

NEXT_WRAPUP_N=$(( WRAPUP_COUNT_PREV > PREV_WRAPUP_N ? WRAPUP_COUNT_PREV + 1 : PREV_WRAPUP_N + 1 ))

# --- Compute segment deltas ---
SEG_COST="$(python3 -c "print(round(max(0.0, $CUM_COST - $PREV_CUM_COST), 6))")"
SEG_WALL_MS="$(python3 -c "print(max(0, $CUM_WALL_MS - $PREV_CUM_WALL_MS))")"
SEG_API_MS="$(python3 -c "print(max(0, $CUM_API_MS - $PREV_CUM_API_MS))")"

# --- Find transcript JSONL ---
TRANSCRIPT_PATH="$(python3 "$HOOKS_DIR/transcript_to_session.py" find-transcript "$SID" 2>/dev/null || true)"

# --- Slice transcript for Haiku + scan for own commits ---
TMP_DIR="$(mktemp -d -t wrapup-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
TRANSCRIPT_SLICE="$TMP_DIR/transcript_slice.jsonl"
OWN_COMMITS_FILE="$TMP_DIR/own_commits.json"
SUMMARY_JSON_FILE="$TMP_DIR/summary.json"

OWN_COMMIT_COUNT=0
WINDOW_COMMIT_COUNT=0
PARALLEL_COMMIT_COUNT=0

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Slice: entries with timestamp >= prev_ts. Records without timestamps
  # are kept (e.g. tool_result blocks) so we don't lose context.
  jq -c --arg cutoff "$PREV_TS" '
    select((.timestamp // "") >= $cutoff)
  ' "$TRANSCRIPT_PATH" > "$TRANSCRIPT_SLICE" 2>/dev/null || true

  # Extract our own commits: Bash tool calls whose input.command contains
  # `git commit` (not just --amend), then grab the SHA from the tool result.
  python3 - "$TRANSCRIPT_SLICE" "$PROJECT_PATH" "$OWN_COMMITS_FILE" <<'PYEOF'
import json, re, subprocess, sys
slice_path, project_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

commit_re = re.compile(r"(?<![\w-])git\s+commit\b(?!\s+--amend\b)")
sha_re = re.compile(r"\[[^\]]+\s+([0-9a-f]{7,40})\]")

pending_ids = set()
own_shas = []

try:
    with open(slice_path) as f:
        for line in f:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = rec.get("message") or rec
            content = msg.get("content") if isinstance(msg, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                btype = block.get("type")
                if btype == "tool_use" and block.get("name") == "Bash":
                    cmd = (block.get("input") or {}).get("command", "")
                    if commit_re.search(cmd):
                        pending_ids.add(block.get("id"))
                elif btype == "tool_result":
                    tid = block.get("tool_use_id")
                    if tid not in pending_ids:
                        continue
                    raw = block.get("content")
                    text = ""
                    if isinstance(raw, str):
                        text = raw
                    elif isinstance(raw, list):
                        text = "\n".join(
                            (b.get("text", "") if isinstance(b, dict) else "")
                            for b in raw
                        )
                    m = sha_re.search(text)
                    if m:
                        own_shas.append(m.group(1))
                    pending_ids.discard(tid)
except OSError:
    pass

enriched = []
for sha in own_shas:
    try:
        out = subprocess.run(
            ["git", "-C", project_path, "log", "-1", "--format=%H%x09%s", sha],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0 and out.stdout:
            full_sha, _, subject = out.stdout.strip().partition("\t")
            enriched.append({"sha": full_sha, "msg": subject})
    except (OSError, subprocess.TimeoutExpired):
        pass

seen = set()
deduped = []
for c in enriched:
    if c["sha"] not in seen:
        seen.add(c["sha"])
        deduped.append(c)

with open(out_path, "w") as f:
    json.dump(deduped, f)
PYEOF
fi

OWN_COMMIT_COUNT="$(jq 'length' "$OWN_COMMITS_FILE" 2>/dev/null || echo 0)"

if [ -n "$PREV_TS" ]; then
  WINDOW_COMMIT_COUNT="$(git -C "$PROJECT_PATH" log --since="$PREV_TS" --no-merges --format='%H' 2>/dev/null | wc -l | tr -d ' ')"
fi
PARALLEL_COMMIT_COUNT=$(( WINDOW_COMMIT_COUNT - OWN_COMMIT_COUNT ))
[ "$PARALLEL_COMMIT_COUNT" -lt 0 ] && PARALLEL_COMMIT_COUNT=0

# --- Generate summary (Haiku via wrapup_summarize.py) ---
[ ! -s "$TRANSCRIPT_SLICE" ] && echo "(empty transcript slice)" > "$TRANSCRIPT_SLICE"
[ ! -s "$OWN_COMMITS_FILE" ] && echo "[]" > "$OWN_COMMITS_FILE"

# Budget: $0.40 is enough for the non-bare boot path (~$0.10 of boot
# tokens cached after first call + ~$0.10 for the actual prompt). With
# ANTHROPIC_API_KEY set the script switches to --bare and the real cost
# is ~$0.005, so the budget cap is a safety net, not a per-call charge.
# Bumped from $0.15 during 2026-05-25 e2e verify (kept hitting
# error_max_budget_usd during boot before the prompt ran).
python3 "$HOOKS_DIR/wrapup_summarize.py" \
  --transcript-slice "$TRANSCRIPT_SLICE" \
  --commits-file "$OWN_COMMITS_FILE" \
  --out "$SUMMARY_JSON_FILE" \
  --timeout-seconds 120 \
  --budget-usd 0.40 \
  2> "$TMP_DIR/summarize.stderr" || true

if [ ! -s "$SUMMARY_JSON_FILE" ]; then
  # wrapup_summarize.py always writes the file (even on failure), but be defensive
  echo '{"headline":"wrapup","details":[],"topics":[],"blockers":[],"_fallback":true,"_fallback_reason":"summarize_script_failed"}' > "$SUMMARY_JSON_FILE"
fi

HEADLINE="$(jq -r '.headline // "wrapup"' "$SUMMARY_JSON_FILE")"
DETAILS_JSON="$(jq -c '.details // []' "$SUMMARY_JSON_FILE")"
TOPICS_JSON="$(jq -c '.topics // []' "$SUMMARY_JSON_FILE")"
BLOCKERS_JSON="$(jq -c '.blockers // []' "$SUMMARY_JSON_FILE")"
IS_FALLBACK="$(jq -r '._fallback // false' "$SUMMARY_JSON_FILE")"
FALLBACK_REASON="$(jq -r '._fallback_reason // ""' "$SUMMARY_JSON_FILE")"

# --- Call session_wrapup.sh with all the new flags ---
WRAPUP_RESULT="$(bash "$HOOKS_DIR/session_wrapup.sh" \
  --session-id "$SID" \
  --summary-json "$SUMMARY_JSON_FILE" \
  --own-commits "$OWN_COMMITS_FILE" \
  --cumulative-source "$CUMULATIVE_SOURCE" \
  --reconcile-warning "$RECONCILE_WARNING" \
  --parallel-commits "$PARALLEL_COMMIT_COUNT" \
  "$HEADLINE" 2>&1)"

# session_wrapup.sh prints a JSON object — extract the fields we need.
CC_DELIVERED="$(echo "$WRAPUP_RESULT" | grep -E '^\s*"cc_delivered"' | head -1 | sed -E 's/.*: *([^,]*).*/\1/' | tr -d ' ')"
QUEUED_DEPTH="$(echo "$WRAPUP_RESULT" | grep -E '^\s*"queued_depth"' | head -1 | sed -E 's/.*: *([0-9]+).*/\1/')"
ACTIVE_TIME_REPORTED="$(echo "$WRAPUP_RESULT" | grep -E '^\s*"active_time"' | head -1 | sed -E 's/.*: *"([^"]*)".*/\1/')"
[ -z "$CC_DELIVERED" ] && CC_DELIVERED="?"
[ -z "$QUEUED_DEPTH" ] && QUEUED_DEPTH=0

# --- Append to sidecar ---
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$SIDECAR" "$NEXT_WRAPUP_N" "$NOW_ISO" "$CUM_COST" "$CUM_WALL_MS" "$CUM_API_MS" "$HEADLINE" <<'PYEOF'
import json, sys
path, n, ts, cost, wall_ms, api_ms, headline = sys.argv[1:]
with open(path, "a") as f:
    f.write(json.dumps({
        "wrapup_n": int(n),
        "ts": ts,
        "cum_cost": float(cost),
        "cum_wall_ms": int(wall_ms),
        "cum_api_ms": int(api_ms),
        "summary_headline": headline,
    }) + "\n")
PYEOF

# --- Print report ---
fmt_ms() {
  python3 -c "
ms=int(float('$1'))
s=ms//1000; m=s//60; h=m//60
if h>0: print(f'{h}h{m%60:02d}m')
elif m>0: print(f'{m}m{s%60:02d}s')
else: print(f'{s}s')
"
}

fmt_cost() {
  python3 -c "print(f'\${float(\"$1\"):.4f}')"
}

SHORT_SID="${SID:0:8}"
PROJECT_NAME="$(basename "$PROJECT_PATH")"

echo "─── Wrapup #${NEXT_WRAPUP_N} ─────────────────────────────────"
echo "Session:  ${SHORT_SID}   Project: ${PROJECT_NAME}   Branch: ${BRANCH}"
echo "Segment:  ${PREV_TS} → ${NOW_ISO}"
echo ""
echo "This segment:  wall $(fmt_ms "$SEG_WALL_MS")  api $(fmt_ms "$SEG_API_MS")  $(fmt_cost "$SEG_COST")  own-commits ${OWN_COMMIT_COUNT}"
echo "Session total: wall $(fmt_ms "$CUM_WALL_MS")  api $(fmt_ms "$CUM_API_MS")  $(fmt_cost "$CUM_COST")"
if [ -n "$ACTIVE_TIME_REPORTED" ] && [ "$ACTIVE_TIME_REPORTED" != "null" ]; then
  echo "Active time:   ${ACTIVE_TIME_REPORTED}"
fi
echo ""

if [ "$OWN_COMMIT_COUNT" -gt 0 ]; then
  echo "Own commits this segment:"
  jq -r '.[] | "  \(.sha[0:8])  \(.msg)"' "$OWN_COMMITS_FILE"
  if [ "$PARALLEL_COMMIT_COUNT" -gt 0 ]; then
    echo "(${PARALLEL_COMMIT_COUNT} other commits in window from parallel agents)"
  fi
elif [ "$PARALLEL_COMMIT_COUNT" -gt 0 ]; then
  echo "Own commits: none  (${PARALLEL_COMMIT_COUNT} commits in window are from parallel agents)"
else
  echo "Own commits: none (exploratory/review segment)"
fi
echo ""

echo "Headline: ${HEADLINE}"
DETAIL_COUNT="$(echo "$DETAILS_JSON" | jq 'length')"
if [ "$DETAIL_COUNT" -gt 0 ]; then
  echo "Details:"
  echo "$DETAILS_JSON" | jq -r '.[] | "  • \(.)"'
fi
TOPIC_LIST="$(echo "$TOPICS_JSON" | jq -r 'join(", ")')"
[ -n "$TOPIC_LIST" ] && echo "Topics:   ${TOPIC_LIST}"
BLOCKER_COUNT="$(echo "$BLOCKERS_JSON" | jq 'length')"
if [ "$BLOCKER_COUNT" -gt 0 ]; then
  echo "Blockers:"
  echo "$BLOCKERS_JSON" | jq -r '.[] | "  ⚠ \(.)"'
fi

if [ "$IS_FALLBACK" = "true" ]; then
  echo ""
  echo "⚠ Summary is FALLBACK (Haiku failed: ${FALLBACK_REASON}). Commit-derived only."
fi
if [ -n "$RECONCILE_WARNING" ]; then
  echo "⚠ ${RECONCILE_WARNING}"
fi
if [ "$CUMULATIVE_SOURCE" != "telemetry" ]; then
  echo "⚠ Cumulative source: ${CUMULATIVE_SOURCE} (telemetry.live unavailable/stale)"
fi

echo ""
echo "POST: ${CC_DELIVERED}   queued: ${QUEUED_DEPTH}"
echo "Logged: $TIME_LOG  +  $SIDECAR"
echo "wrapup-marker:${SID}:${NEXT_WRAPUP_N}:${CUM_COST}:${CUM_WALL_MS}:${NOW_ISO}"
echo "────────────────────────────────────────────────────────────"

exit 0
