#!/bin/bash
# wrapup-enqueue.sh — Stop + SessionEnd hook handler.
#
# Reads the hook stdin JSON, writes (or overwrites) a queue file at
# ~/.claude/wrapups/queue/{session_id}.json telling the worker to wrap
# this session at some future time. Multiple Stop fires on the same
# session simply overwrite the file with a new scheduled_at — that's
# the debounce mechanism.
#
# Scheduled offsets:
#   Stop        → now + 10 min  (still-active session)
#   SessionEnd  → now + 30 sec  (closed session, wrap soon)
#
# A SessionEnd file always wins over a prior Stop file for the same
# session (smaller scheduled_at). A Stop after a SessionEnd also wins,
# pushing the wrap back out — correct, because the user resumed.
#
# Never blocks the hook event. Returns 0 unconditionally; the worker
# is the authoritative path and any error here is logged + ignored.
#
# See: ~/Documents/GitHub/command-center/docs/superpowers/plans/2026-05-25-wrapup-stop-sessionend.md

set -uo pipefail

QUEUE_DIR="$HOME/.claude/wrapups/queue"
LOG_FILE="$HOME/.claude/wrapups/worker.log"
mkdir -p "$QUEUE_DIR"

# --- Read hook stdin ---
HOOK_INPUT="$(cat 2>/dev/null || true)"
if [ -z "$HOOK_INPUT" ]; then
  echo "[$(date -u +%FT%TZ)] enqueue: empty stdin, ignoring" >> "$LOG_FILE"
  exit 0
fi

# Parse session_id, cwd, hook_event_name. jq preferred; grep+sed fallback
# matches the same pattern stop-verify.sh uses.
if command -v jq >/dev/null 2>&1; then
  SID="$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
  CWD="$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  EVENT="$(echo "$HOOK_INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
else
  SID=$(echo "$HOOK_INPUT" \
    | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  CWD=$(echo "$HOOK_INPUT" \
    | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  EVENT=$(echo "$HOOK_INPUT" \
    | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

if [ -z "$SID" ]; then
  echo "[$(date -u +%FT%TZ)] enqueue: no session_id in stdin, ignoring" >> "$LOG_FILE"
  exit 0
fi

# --- Compute scheduled_at ---
case "$EVENT" in
  SessionEnd)
    DELAY_SEC=30
    ;;
  Stop|*)
    DELAY_SEC=600  # 10 min default; also covers unknown events
    ;;
esac

# date -d isn't available on macOS; use python for ISO-8601 offset arithmetic.
SCHEDULED_AT="$(python3 -c "
import datetime, sys
print((datetime.datetime.utcnow() + datetime.timedelta(seconds=$DELAY_SEC))
      .strftime('%Y-%m-%dT%H:%M:%SZ'))
")"

# --- Write queue file atomically ---
QUEUE_FILE="$QUEUE_DIR/$SID.json"
TMP_FILE="$QUEUE_FILE.tmp.$$"

cat > "$TMP_FILE" <<EOF
{
  "session_id": "$SID",
  "scheduled_at": "$SCHEDULED_AT",
  "cwd": "$CWD",
  "enqueued_by": "$EVENT",
  "enqueued_at": "$(date -u +%FT%TZ)"
}
EOF

mv -f "$TMP_FILE" "$QUEUE_FILE"

echo "[$(date -u +%FT%TZ)] enqueue: $SID via $EVENT → $SCHEDULED_AT" >> "$LOG_FILE"
exit 0
