#!/bin/bash
# track_event.sh — Non-blocking POST to cc.meir.pro tracking API
# Usage: track_event.sh <event_type> [metadata_json]
#
# Requires:
#   ~/.claude/track-key — contains the TRACK_KEY secret
#   CLAUDE_SESSION_ID   — set by Claude Code (session UUID)
#
# On failure: appends event to ~/.claude/tracking-queue.jsonl for later flush

EVENT_TYPE="$1"
METADATA="${2:-{}}"
SESSION_ID="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CWD="${PWD}"
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")

TRACK_URL="https://cc.meir.pro"
TRACK_KEY_FILE="$HOME/.claude/track-key"

if [ ! -f "$TRACK_KEY_FILE" ]; then
  echo "track_event.sh: missing $TRACK_KEY_FILE" >&2
  exit 0  # don't block Claude
fi

TRACK_KEY=$(cat "$TRACK_KEY_FILE")

PAYLOAD="{\"session_id\":\"$SESSION_ID\",\"event_type\":\"$EVENT_TYPE\",\"timestamp\":\"$TIMESTAMP\",\"cwd\":\"$CWD\",\"branch\":\"$BRANCH\",\"metadata\":$METADATA}"

# Fire and forget — background curl with 2s timeout
(
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TRACK_URL/api/event" \
    -H "Content-Type: application/json" \
    -H "X-Track-Key: $TRACK_KEY" \
    -d "$PAYLOAD" \
    --max-time 2 2>/dev/null)

  # Queue on failure (network error, 5xx, etc.)
  if [ "$HTTP_CODE" != "200" ]; then
    echo "$PAYLOAD" >> "$HOME/.claude/tracking-queue.jsonl"
  fi
) &

exit 0
