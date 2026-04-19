#!/bin/bash
# git-pre-push.sh — runs before every git push via global core.hooksPath
# Flushes ~/.claude/git-commits-queue.jsonl to cc.meir.pro/api/commits/batch.
# Best-effort — never blocks the push.

QUEUE_FILE="$HOME/.claude/git-commits-queue.jsonl"

# Best-effort: silence errors, never block the push
{
    [ -f "$QUEUE_FILE" ] || exit 0

    COMMITS=$(jq -s '.' "$QUEUE_FILE" 2>/dev/null)
    [ -z "$COMMITS" ] && exit 0
    [ "$COMMITS" = "[]" ] && exit 0

    # 5s + 1 retry budget so a slow CC never holds up `git push`.
    # Queue stays put on any non-2xx (no-key included).
    if echo "{\"commits\": $COMMITS}" \
        | "$HOME/.claude/bin/cc-call" --timeout 5 --retries 1 POST /api/commits/batch \
            >/dev/null 2>&1; then
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
