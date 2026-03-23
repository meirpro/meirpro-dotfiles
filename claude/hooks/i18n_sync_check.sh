#!/bin/bash

# i18n key sync checker — PostToolUse hook
# Fires on Write|Edit|MultiEdit, checks if edited file is en.json or he.json,
# and reports missing keys between the pair.

input=$(cat)

# Extract file path (same pattern as ts_lint.sh)
if command -v jq >/dev/null 2>&1; then
    file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
else
    file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
fi

# Exit silently if no file path
if [ -z "$file_path" ] || [ "$file_path" = "null" ]; then
    exit 0
fi

# Only check en.json or he.json in an i18n/messages directory
case "$file_path" in
    */i18n/messages/en.json)
        sibling_path="${file_path%en.json}he.json"
        edited="en.json"
        sibling="he.json"
        ;;
    */i18n/messages/he.json)
        sibling_path="${file_path%he.json}en.json"
        edited="he.json"
        sibling="en.json"
        ;;
    *)
        exit 0
        ;;
esac

# Check sibling exists
if [ ! -f "$sibling_path" ]; then
    exit 0
fi

# Need jq for key comparison
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Extract top-level keys from both files
edited_keys=$(jq -r 'keys[]' "$file_path" 2>/dev/null | sort)
sibling_keys=$(jq -r 'keys[]' "$sibling_path" 2>/dev/null | sort)

if [ -z "$edited_keys" ] || [ -z "$sibling_keys" ]; then
    exit 0
fi

# Find keys in edited file but missing from sibling
missing_in_sibling=$(comm -23 <(echo "$edited_keys") <(echo "$sibling_keys"))
# Find keys in sibling but missing from edited file
missing_in_edited=$(comm -13 <(echo "$edited_keys") <(echo "$sibling_keys"))

if [ -n "$missing_in_sibling" ] || [ -n "$missing_in_edited" ]; then
    echo "i18n key sync issue detected:" >&2
    if [ -n "$missing_in_sibling" ]; then
        echo "" >&2
        echo "Keys in $edited but MISSING from $sibling:" >&2
        echo "$missing_in_sibling" | sed 's/^/  - /' >&2
    fi
    if [ -n "$missing_in_edited" ]; then
        echo "" >&2
        echo "Keys in $sibling but MISSING from $edited:" >&2
        echo "$missing_in_edited" | sed 's/^/  - /' >&2
    fi
    # Exit 2 = signal to LLM to fix the issue
    exit 2
fi

exit 0
