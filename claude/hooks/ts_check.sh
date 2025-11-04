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

# Find project root (look for package.json)
project_root="$PWD"
current_dir=$(dirname "$file_path")
while [ "$current_dir" != "/" ] && [ "$current_dir" != "." ]; do
    if [ -f "$current_dir/package.json" ]; then
        project_root="$current_dir"
        break
    fi
    current_dir=$(dirname "$current_dir")
done

# Run TypeScript check on specific file
cd "$project_root" || exit 0

# Convert to absolute path
abs_file_path=$(realpath "$file_path")

# Run tsc on specific file using project configuration
tsc_output=$(npx tsc --noEmit --project . --skipLibCheck "$abs_file_path" 2>&1)
tsc_exit_code=$?

# If there are errors, filter out JSX config errors and report
if [ $tsc_exit_code -ne 0 ] && [ -n "$tsc_output" ]; then
    # Filter out JSX config errors and focus on the specific file
    filtered_output=$(echo "$tsc_output" | grep -v "JSX element implicitly has type" | grep "$abs_file_path\|$(basename "$file_path")")

    if [ -n "$filtered_output" ]; then
        echo "TypeScript errors found in $file_path:" >&2
        # Format output more compactly (similar to ESLint compact format)
        echo "$filtered_output" | sed 's/^/  /' >&2
        exit 2
    fi
fi

exit 0