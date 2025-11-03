#!/bin/bash

# Claude Code macOS Notification Hook
# This hook displays native macOS notifications with sound when triggered
# The input JSON is passed via stdin

# Read the JSON input from stdin
json_input=$(cat)

# Extract title and message from the JSON
title=$(echo "$json_input" | jq -r '.title // "Claude Code Notification"')
message=$(echo "$json_input" | jq -r '.message // "Task completed"')

# Use terminal-notifier if installed (recommended for reliable notifications)
if command -v terminal-notifier &> /dev/null; then
    terminal-notifier -title "$title" -message "$message" -sound Glass
else
    # Fallback: Play sound and display notification separately
    afplay /System/Library/Sounds/Glass.aiff &
    osascript <<EOD
tell application "System Events"
    display notification "$message" with title "$title" subtitle "Claude Code"
end tell
EOD
fi

# Optional: Log the notification for debugging
echo "[$(date)] Notification sent - Title: $title, Message: $message" >> /Users/lightwing/.claude/hooks/notification.log

# Exit successfully
exit 0