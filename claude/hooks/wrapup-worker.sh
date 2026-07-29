#!/bin/bash
# wrapup-worker.sh — launchd-driven processor for the wrapup scheduling queue.
#
# Fired by:
#   - WatchPaths on ~/.claude/wrapups/queue/ (instant on enqueue)
#   - StartInterval 600 (10-min backstop polling)
#
# For each queue file with scheduled_at ≤ now: invoke the existing
# wrapup.sh against the session_id, drop the queue file on success.
# Leave it in place on failure — next tick (or next watch trigger)
# will retry.
#
# Concurrency: a single flock prevents overlapping worker ticks. Per-session
# queue files overwrite atomically (mv), so concurrent enqueues don't
# corrupt anything.
#
# See: ~/Documents/GitHub/command-center/docs/superpowers/plans/2026-05-25-wrapup-stop-sessionend.md

set -uo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
QUEUE_DIR="$HOME/.claude/wrapups/queue"
LOG_FILE="$HOME/.claude/wrapups/worker.log"
LOCK_FILE="$HOME/.claude/wrapups/worker.lock"

mkdir -p "$QUEUE_DIR"
touch "$LOG_FILE"

log() {
  echo "[$(date -u +%FT%TZ)] worker: $*" >> "$LOG_FILE"
}

# --- Prereqs ---
for bin in jq python3; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    log "missing prereq: $bin"
    exit 3
  fi
done

if [ ! -x "$HOOKS_DIR/wrapup.sh" ]; then
  log "missing $HOOKS_DIR/wrapup.sh — cannot process queue"
  exit 3
fi

# --- Single-instance guard ---
# macOS lacks `flock`. Use noclobber to atomically claim the lock; trap
# cleanup on exit. If another worker holds it, exit quietly.
if ! (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
  HOLDER="$(cat "$LOCK_FILE" 2>/dev/null || echo unknown)"
  # If holder PID is dead, steal the lock (crashed prior worker).
  if [ -n "$HOLDER" ] && ! kill -0 "$HOLDER" 2>/dev/null; then
    log "stealing stale lock from pid $HOLDER"
    echo "$$" > "$LOCK_FILE"
  else
    # Another worker is running — silent exit; it'll handle the queue.
    exit 0
  fi
fi
trap 'rm -f "$LOCK_FILE"' EXIT INT TERM

# --- Process due entries ---
NOW_EPOCH="$(date -u +%s)"
shopt -s nullglob
PROCESSED=0
SKIPPED=0
FAILED=0

for queue_file in "$QUEUE_DIR"/*.json; do
  SID="$(jq -r '.session_id // empty' "$queue_file" 2>/dev/null)"
  SCHEDULED_AT="$(jq -r '.scheduled_at // empty' "$queue_file" 2>/dev/null)"

  if [ -z "$SID" ] || [ -z "$SCHEDULED_AT" ]; then
    log "skipping malformed queue file: $(basename "$queue_file")"
    rm -f "$queue_file"
    continue
  fi

  # ISO-8601 → epoch via python (date -d unavailable on macOS).
  SCHED_EPOCH="$(python3 -c "
import datetime, sys
try:
    print(int(datetime.datetime.strptime('$SCHEDULED_AT', '%Y-%m-%dT%H:%M:%SZ')
              .replace(tzinfo=datetime.timezone.utc).timestamp()))
except Exception:
    print(-1)
")"

  if [ "$SCHED_EPOCH" = "-1" ]; then
    log "skipping queue file with bad scheduled_at: $(basename "$queue_file")"
    rm -f "$queue_file"
    continue
  fi

  if [ "$NOW_EPOCH" -lt "$SCHED_EPOCH" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue  # not yet due
  fi

  log "processing $SID (scheduled_at=$SCHEDULED_AT)"

  # Run wrapup.sh. Capture status; output goes to log on failure only.
  WRAPUP_OUT="$(bash "$HOOKS_DIR/wrapup.sh" "$SID" 2>&1)"
  STATUS=$?

  if [ "$STATUS" -eq 0 ]; then
    rm -f "$queue_file"
    PROCESSED=$((PROCESSED + 1))
    log "completed $SID"
  else
    FAILED=$((FAILED + 1))
    log "FAILED $SID (exit $STATUS): $(echo "$WRAPUP_OUT" | tail -5 | tr '\n' ' | ')"
    # Leave queue file in place; next tick retries.
    # If wrapup.sh hard-fails (exit 2 = unresolvable session, exit 3 =
    # prereq missing), the failure will repeat every tick — that's fine,
    # the log makes it visible. Future enhancement: max-retry counter.
  fi
done

if [ "$PROCESSED" -gt 0 ] || [ "$FAILED" -gt 0 ]; then
  log "tick done: processed=$PROCESSED skipped=$SKIPPED failed=$FAILED"
fi

exit 0
