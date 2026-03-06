#!/bin/bash

LOG_FILE="$HOME/.claude/bash-command-log.txt"
MAX_SIZE_BYTES=$((25 * 1024 * 1024))  # 25MB

# Read JSON input from stdin
input=$(cat)

# Extract command and description using jq (more reliable) or fallback
if command -v jq >/dev/null 2>&1; then
    command_text=$(echo "$input" | jq -r '.tool_input.command // empty')
    description=$(echo "$input" | jq -r '.tool_input.description // "No description"')
    cwd=$(echo "$input" | jq -r '.cwd // empty')
else
    command_text=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    description=$(echo "$input" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    cwd=$(echo "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

    if [ -z "$description" ]; then
        description="No description"
    fi
fi

# Exit if no command
if [ -z "$command_text" ] || [ "$command_text" = "null" ]; then
    exit 0
fi

# Get project name from cwd (last directory component)
if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
    project=$(basename "$cwd")
else
    project="unknown"
fi

mkdir -p ~/.claude

# Log with project context
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$timestamp] [$project] $command_text - $description" >> "$LOG_FILE"

# Rotate if file exceeds max size — archive with date range, start fresh
if [ -f "$LOG_FILE" ]; then
    file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$file_size" -gt "$MAX_SIZE_BYTES" ]; then
        first_date=$(head -1 "$LOG_FILE" | grep -o '^\[[0-9-]*' | tr -d '[')
        last_date=$(tail -1 "$LOG_FILE" | grep -o '^\[[0-9-]*' | tr -d '[')
        first_date="${first_date:-unknown}"
        last_date="${last_date:-unknown}"
        mv "$LOG_FILE" "$HOME/.claude/bash-command-log_${first_date}_to_${last_date}.txt"
    fi
fi

exit 0