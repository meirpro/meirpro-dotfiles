#!/bin/bash

# Lightweight tool usage logger — PreToolUse hook (all tools)
# Logs tool name + timestamp to a compact TSV for analytics.
# Rotate at 10MB.

LOG_FILE="$HOME/.claude/tool-usage-log.tsv"
MAX_SIZE_BYTES=$((10 * 1024 * 1024))

input=$(cat)

# Extract tool name and cwd
if command -v jq >/dev/null 2>&1; then
    tool_name=$(echo "$input" | jq -r '.tool_name // empty')
    cwd=$(echo "$input" | jq -r '.cwd // empty')
else
    tool_name=$(echo "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    cwd=$(echo "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
fi

if [ -z "$tool_name" ] || [ "$tool_name" = "null" ]; then
    exit 0
fi

# Project name from cwd
if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
    project=$(basename "$cwd")
else
    project="unknown"
fi

# Compact TSV format: timestamp \t project \t tool_name
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
printf '%s\t%s\t%s\n' "$timestamp" "$project" "$tool_name" >> "$LOG_FILE"

# Rotate
if [ -f "$LOG_FILE" ]; then
    file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$file_size" -gt "$MAX_SIZE_BYTES" ]; then
        first_date=$(head -1 "$LOG_FILE" | cut -f1 | cut -d' ' -f1)
        last_date=$(tail -1 "$LOG_FILE" | cut -f1 | cut -d' ' -f1)
        mv "$LOG_FILE" "$HOME/.claude/tool-usage-log_${first_date:-unknown}_to_${last_date:-unknown}.tsv"
    fi
fi

exit 0
