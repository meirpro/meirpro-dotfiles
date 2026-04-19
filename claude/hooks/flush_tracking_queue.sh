#!/bin/bash
# flush_tracking_queue.sh — Send queued events that failed to POST (offline periods)
# Usage: bash ~/.claude/hooks/flush_tracking_queue.sh
#
# Reads ~/.claude/tracking-queue.jsonl, POSTs as /api/event/batch via
# cc-call, removes the file on success.

QUEUE_FILE="$HOME/.claude/tracking-queue.jsonl"

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

echo "Flushing $LINE_COUNT queued events..."

# jq builds the batch payload from JSONL — handles escaped chars +
# malformed lines gracefully.
PAYLOAD=$(jq -s '{events: .}' "$QUEUE_FILE" 2>/dev/null)
if [ $? -ne 0 ]; then
  # Fallback: fix common issue (escaped braces) and retry
  PAYLOAD=$(sed 's/\\{/{/g; s/\\}/}/g' "$QUEUE_FILE" | jq -s '{events: .}' 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: queue file contains unparseable JSON. Fix manually." >&2
    exit 1
  fi
fi

# 30s timeout to match the original; default 3-retry schedule from
# cc-call rides through CF cold starts and DNS hiccups.
RESPONSE=$(echo "$PAYLOAD" | "$HOME/.claude/bin/cc-call" --timeout 30 POST /api/event/batch 2>&1)
EXIT=$?

case "$EXIT" in
  0)
    echo "Success: $RESPONSE"
    rm -f "$QUEUE_FILE"
    ;;
  3)
    echo "Error: no track key (Keychain + legacy file both empty)" >&2
    echo "Queue file preserved at $QUEUE_FILE" >&2
    exit 1
    ;;
  *)
    echo "Failed: $RESPONSE" >&2
    echo "Queue file preserved at $QUEUE_FILE" >&2
    exit 1
    ;;
esac
