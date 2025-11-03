#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract file_path using basic text processing
file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

# Exit if no file path
if [ -z "$file_path" ]; then
    exit 0
fi

# Only check TypeScript/JavaScript files
case "$file_path" in
    *.ts|*.tsx|*.js|*.jsx)
        ;;
    *)
        exit 0
        ;;
esac

# Check if file exists
if [ ! -f "$file_path" ]; then
    exit 0
fi

# Run ESLint on the specific file
eslint_output=$(timeout 30 npx eslint "$file_path" --format compact 2>&1)
eslint_exit_code=$?

# If ESLint found errors
if [ $eslint_exit_code -ne 0 ] && [ -n "$eslint_output" ]; then
    # Extract session_id from input if available
    session_id=$(echo "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    # Log the error for debugging (optional)
    log_file="$HOME/.claude/eslint_errors.json"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create a simple log entry (simplified compared to Python version)
    if [ -f "$log_file" ]; then
        # Append to existing log (simplified - just append as new line)
        echo "[$timestamp] File: $file_path, Session: $session_id, Errors: $eslint_output" >> "$log_file"
    else
        # Create new log file
        echo "[$timestamp] File: $file_path, Session: $session_id, Errors: $eslint_output" > "$log_file"
    fi

    # Send error message to stderr for LLM to see
    echo "ESLint errors found in $file_path:" >&2
    echo "$eslint_output" >&2

    # Exit with code 2 to signal LLM to correct
    exit 2
fi

# Check if timeout occurred (exit code 124 from timeout command)
if [ $eslint_exit_code -eq 124 ]; then
    echo "ESLint check timed out" >&2
    exit 0
fi

# If ESLint command not found or other issues, just exit silently
exit 0