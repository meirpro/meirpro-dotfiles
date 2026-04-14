#!/bin/bash
# git-pre-push.sh — runs before every git push via global core.hooksPath
# Flushes ~/.claude/git-commits-queue.jsonl to cc.meir.pro/api/commits/batch.
# Best-effort — never blocks the push.

QUEUE_FILE="$HOME/.claude/git-commits-queue.jsonl"
TRACK_KEY_FILE="$HOME/.claude/track-key"
API_URL="https://cc.meir.pro/api/commits/batch"

# Best-effort: silence errors, never block the push
{
    [ -f "$QUEUE_FILE" ] || exit 0
    [ -f "$TRACK_KEY_FILE" ] || exit 0

    TRACK_KEY=$(cat "$TRACK_KEY_FILE")

    COMMITS=$(jq -s '.' "$QUEUE_FILE" 2>/dev/null)
    [ -z "$COMMITS" ] && exit 0
    [ "$COMMITS" = "[]" ] && exit 0

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "X-Track-Key: $TRACK_KEY" \
        --max-time 15 \
        -d "{\"commits\": $COMMITS}")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        rm -f "$QUEUE_FILE"
    fi
} 2>/dev/null

# Fall-through to repo-local pre-push hook if one exists
REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$REPO_PATH" ]; then
    REPO_HOOK="$REPO_PATH/.git/hooks/pre-push"
    if [ -x "$REPO_HOOK" ] && [ "$(readlink -f "$REPO_HOOK" 2>/dev/null || echo "$REPO_HOOK")" != "$(readlink -f "$0" 2>/dev/null || echo "$0")" ]; then
        exec "$REPO_HOOK" "$@"
    fi
fi

exit 0
