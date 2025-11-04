#!/usr/bin/env python3
import sys
import json
from datetime import datetime

# Log to a file
log_file = "/Users/lightwing/.claude/hooks/hook_debug.log"

with open(log_file, "a") as f:
    f.write(f"\n{'='*60}\n")
    f.write(f"Timestamp: {datetime.now().isoformat()}\n")
    f.write(f"Hook triggered!\n")
    
    # Try to read stdin
    try:
        input_data = json.load(sys.stdin)
        f.write(f"Input data:\n{json.dumps(input_data, indent=2)}\n")
    except Exception as e:
        f.write(f"Error reading stdin: {e}\n")
        f.write(f"stdin readable: {not sys.stdin.isatty()}\n")
    
    # Check command line args
    f.write(f"Command line args: {sys.argv}\n")
