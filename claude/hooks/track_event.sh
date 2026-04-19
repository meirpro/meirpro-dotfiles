#!/bin/bash
# track_event.sh — Non-blocking POST to cc.meir.pro tracking API
# Usage: track_event.sh <event_type> [metadata_json]
#
# Requires:
#   CLAUDE_SESSION_ID — set by Claude Code (session UUID)
#   X-Track-Key in macOS Keychain (service "claude-track-key") or
#   the legacy ~/.claude/track-key file (resolved by cc_client.py).
#
# On failure: appends event to ~/.claude/tracking-queue.jsonl for later
# flush. On no-key: silently exits 0 — preserves the historical
# behavior of "don't block Claude when CC tracking isn't set up."

EVENT_TYPE="$1"
METADATA="${2:-{}}"
SESSION_ID="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CWD="${PWD}"
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")

PAYLOAD="{\"session_id\":\"$SESSION_ID\",\"event_type\":\"$EVENT_TYPE\",\"timestamp\":\"$TIMESTAMP\",\"cwd\":\"$CWD\",\"branch\":\"$BRANCH\",\"metadata\":$METADATA}"

# Fire-and-forget: 2s timeout, single attempt — the queue catches anything
# slow/down. cc-call exit codes:
#   0 = delivered, 3 = no key (skip silently), other = queue for flush.
(
    echo "$PAYLOAD" | "$HOME/.claude/bin/cc-call" --timeout 2 --retries 1 POST /api/event >/dev/null 2>&1
    EXIT=$?
    case "$EXIT" in
        0|3) : ;;
        *)   echo "$PAYLOAD" >> "$HOME/.claude/tracking-queue.jsonl" ;;
    esac
) &

exit 0
