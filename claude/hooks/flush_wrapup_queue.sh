#!/bin/bash
# flush_wrapup_queue.sh — retry queued wrapup segment pushes to cc.meir.pro
# Usage: bash ~/.claude/hooks/flush_wrapup_queue.sh
#
# Reads ~/.claude/wrapup-queue.jsonl, POSTs each line as a wrapup_segments
# payload, removes the file on full success. On partial failure, kept failed
# lines remain in the queue file for next attempt.

QUEUE_FILE="$HOME/.claude/wrapup-queue.jsonl"
TRACK_KEY_FILE="$HOME/.claude/track-key"
API_URL="https://cc.meir.pro/api/wrapup_segments"

if [ ! -f "$QUEUE_FILE" ]; then
    echo "no queue file"
    exit 0
fi

if [ ! -f "$TRACK_KEY_FILE" ]; then
    echo "missing track key" >&2
    exit 1
fi

TRACK_KEY=$(cat "$TRACK_KEY_FILE")
TMP_FAIL="${QUEUE_FILE}.failed.tmp"
> "$TMP_FAIL"

LINE_COUNT=0
SUCCESS=0
FAIL=0

while IFS= read -r line; do
    [ -z "$line" ] && continue
    LINE_COUNT=$((LINE_COUNT + 1))
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "X-Track-Key: $TRACK_KEY" \
        -d "$line" \
        --max-time 10)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "$line" >> "$TMP_FAIL"
    fi
done < "$QUEUE_FILE"

echo "processed: $LINE_COUNT, success: $SUCCESS, failed: $FAIL"

if [ -s "$TMP_FAIL" ]; then
    mv "$TMP_FAIL" "$QUEUE_FILE"
    echo "some events failed — kept in queue"
    exit 1
else
    rm -f "$QUEUE_FILE" "$TMP_FAIL"
    echo "queue flushed"
    exit 0
fi
