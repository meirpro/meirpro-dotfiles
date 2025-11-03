#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract command and description using jq (more reliable) or fallback
if command -v jq >/dev/null 2>&1; then
    command_text=$(echo "$input" | jq -r '.tool_input.command // empty')
    description=$(echo "$input" | jq -r '.tool_input.description // "No description"')
else
    # Fallback to basic text processing if jq not available
    command_text=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    description=$(echo "$input" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

    # Set default if description is empty
    if [ -z "$description" ]; then
        description="No description"
    fi
fi

# Exit if no command
if [ -z "$command_text" ] || [ "$command_text" = "null" ]; then
    exit 0
fi

# Create log directory if it doesn't exist
mkdir -p ~/.claude

# Log the command with timestamp
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$timestamp] $command_text - $description" >> ~/.claude/bash-command-log.txt

exit 0