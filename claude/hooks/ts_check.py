#!/usr/bin/env python3

import json
import sys
import subprocess
from pathlib import Path


def main():
    try:
        # Read input data from stdin
        input_data = json.load(sys.stdin)

        tool_input = input_data.get("tool_input", {})
        print(tool_input)

        # Get file path from tool input
        file_path = tool_input.get("file_path")
        if not file_path:
            sys.exit(0)

        # Only check TypeScript/JavaScript files
        if not file_path.endswith((".ts", ".tsx", ".js", ".jsx")):
            sys.exit(0)

        # Check if file exists
        if not Path(file_path).exists():
            sys.exit(0)

        # Run TypeScript to check for type errors
        try:
            # Get project root (assuming we're checking files in a project)
            project_root = Path(file_path)
            while project_root.parent != project_root:
                if (project_root / "package.json").exists():
                    break
                project_root = project_root.parent
            else:
                # If no package.json found, use current directory
                project_root = Path(".")

            result = subprocess.run(
                ["npx", "tsc", "--noEmit", "--skipLibCheck"],
                cwd=project_root,
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode != 0 and (result.stdout or result.stderr):
                # Log the error for debugging
                log_file = Path(__file__).parent.parent / "typescript_errors.json"
                error_output = result.stdout or result.stderr

                # Filter out JSX config errors as mentioned in CLAUDE.md
                filtered_errors = []
                for line in error_output.split('\n'):
                    if line.strip() and 'JSX element implicitly has type' not in line:
                        filtered_errors.append(line)

                # Only proceed if there are actual errors after filtering
                if filtered_errors:
                    error_entry = {
                        "file_path": file_path,
                        "errors": '\n'.join(filtered_errors),
                        "session_id": input_data.get("session_id"),
                    }

                    # Load existing errors or create new list
                    if log_file.exists():
                        with open(log_file, "r") as f:
                            errors = json.load(f)
                    else:
                        errors = []

                    errors.append(error_entry)

                    # Save errors
                    with open(log_file, "w") as f:
                        json.dump(errors, f, indent=2)

                    # Send error message to stderr for LLM to see
                    print(f"TypeScript errors found in project (triggered by {file_path}):", file=sys.stderr)
                    print('\n'.join(filtered_errors), file=sys.stderr)

                    # Exit with code 2 to signal LLM to correct
                    sys.exit(2)

        except subprocess.TimeoutExpired:
            print("TypeScript check timed out", file=sys.stderr)
            sys.exit(0)
        except FileNotFoundError:
            # TypeScript not available, skip check
            sys.exit(0)

    except json.JSONDecodeError as e:
        print(f"Error parsing JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error in TypeScript hook: {e}", file=sys.stderr)
        sys.exit(1)


main()