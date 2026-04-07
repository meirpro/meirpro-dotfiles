#!/bin/bash
# flush_tracking_queue.sh — Send queued events that failed to POST (offline periods)
# Usage: bash ~/.claude/hooks/flush_tracking_queue.sh
#
# Reads ~/.claude/tracking-queue.jsonl, POSTs each as /api/event/batch,
# removes the file on success.

QUEUE_FILE="$HOME/.claude/tracking-queue.jsonl"
TRACK_URL="https://cc.meir.pro"
TRACK_KEY_FILE="$HOME/.claude/track-key"

if [ ! -f "$QUEUE_FILE" ]; then
  echo "No queued events."
  exit 0
fi

LINE_COUNT=$(wc -l < "$QUEUE_FILE" | tr -d ' ')
if [ "$LINE_COUNT" -eq 0 ]; then
  echo "Queue file is empty."
  rm -f "$QUEUE_FILE"
  exit 0
fi

if [ ! -f "$TRACK_KEY_FILE" ]; then
  echo "Error: missing $TRACK_KEY_FILE" >&2
  exit 1
fi

TRACK_KEY=$(cat "$TRACK_KEY_FILE")

echo "Flushing $LINE_COUNT queued events..."

# Build JSON array from JSONL
EVENTS="["
FIRST=true
while IFS= read -r line; do
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    EVENTS="$EVENTS,"
  fi
  EVENTS="$EVENTS$line"
done < "$QUEUE_FILE"
EVENTS="$EVENTS]"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "$TRACK_URL/api/event/batch" \
  -H "Content-Type: application/json" \
  -H "X-Track-Key: $TRACK_KEY" \
  -d "{\"events\":$EVENTS}" \
  --max-time 30)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "Success: $BODY"
  rm -f "$QUEUE_FILE"
else
  echo "Failed (HTTP $HTTP_CODE): $BODY" >&2
  echo "Queue file preserved at $QUEUE_FILE" >&2
  exit 1
fi
