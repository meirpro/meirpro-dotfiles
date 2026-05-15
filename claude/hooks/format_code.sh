#!/bin/bash

# Defer to the project's hook if it ships one — avoids double-running
# the same formatter logic on every edit. The project hook lives in its
# repo (committed) so teammates without these global hooks still get
# format-on-edit; the global one stays as the default for projects that
# don't ship their own.
if [ -n "$CLAUDE_PROJECT_DIR" ] && [ -x "$CLAUDE_PROJECT_DIR/.claude/hooks/$(basename "$0")" ]; then
    exit 0
fi

# Read JSON input from stdin
input=$(cat)

# Extract file_path using jq (more reliable than grep)
if command -v jq >/dev/null 2>&1; then
    file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
else
    # Fallback to basic text processing if jq not available
    file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# Exit if no file path
if [ -z "$file_path" ] || [ "$file_path" = "null" ]; then
    exit 0
fi

# Check if file exists
if [ ! -f "$file_path" ]; then
    exit 0
fi

# Format based on file extension
case "$file_path" in
    *.ts|*.tsx|*.js|*.jsx)
        # Format TypeScript/JavaScript files with Prettier
        if command -v prettier >/dev/null 2>&1; then
            echo "Formatting TypeScript/JavaScript file: $file_path" >&2
            prettier --write "$file_path" 2>/dev/null || true
        elif command -v npx >/dev/null 2>&1; then
            echo "Formatting TypeScript/JavaScript file: $file_path" >&2
            npx prettier --write "$file_path" 2>/dev/null || true
        fi
        ;;
    *.go)
        # Format Go files with gofmt
        if command -v gofmt >/dev/null 2>&1; then
            echo "Formatting Go file: $file_path" >&2
            gofmt -w "$file_path" 2>/dev/null || true
        fi
        ;;
    *.py)
        # Format Python files with black (if available)
        if command -v black >/dev/null 2>&1; then
            echo "Formatting Python file: $file_path" >&2
            black "$file_path" 2>/dev/null || true
        fi
        ;;
    *.rs)
        # Format Rust files with rustfmt (if available)
        if command -v rustfmt >/dev/null 2>&1; then
            echo "Formatting Rust file: $file_path" >&2
            rustfmt "$file_path" 2>/dev/null || true
        fi
        ;;
esac

exit 0