#!/bin/bash
# Session time tracker — runs on SessionStart.
# If an orphaned session exists (crash/forgot wrapup), auto-close it first.

SESSION_FILE="$HOME/.claude/session-active.json"
TIME_LOG="$HOME/.claude/time-log.jsonl"

# --- Auto-close orphaned session ---
if [ -f "$SESSION_FILE" ]; then
  python3 -c "
import json, sys
try:
    with open('$SESSION_FILE', 'r') as f:
        data = json.load(f)
    entry = {
        'date': data.get('last_seen', data['start'])[:10],
        'project': data.get('project', 'unknown'),
        'project_path': data.get('project_path', 'unknown'),
        'branch': data.get('branch', 'n/a'),
        'session_id': data.get('session_id', 'unknown'),
        'start': data['start'],
        'end': data.get('last_seen', data['start']),
        'duration_min': data.get('active_minutes', 0),
        'summary': 'auto-closed: session ended without /wrapup',
        'files_changed': data.get('uncommitted_changes', 0),
        'commits': data.get('recent_commits', [])
    }
    with open('$TIME_LOG', 'a') as f:
        f.write(json.dumps(entry, ensure_ascii=False) + '\n')
except Exception:
    pass
" 2>/dev/null
  rm -f "$SESSION_FILE"
fi

# --- Create new session ---
SESSION_ID=$(cat 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="unknown-$(date +%s)"
fi

PROJECT_PATH="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_PATH")"
BRANCH="$(git branch --show-current 2>/dev/null || echo "n/a")"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 -c "
import json
data = {
    'session_id': '$SESSION_ID',
    'start': '$NOW',
    'last_seen': '$NOW',
    'active_minutes': 0,
    'project': '$PROJECT_NAME',
    'project_path': '$PROJECT_PATH',
    'branch': '$BRANCH',
    'recent_commits': [],
    'uncommitted_changes': 0
}
with open('$SESSION_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"

exit 0
