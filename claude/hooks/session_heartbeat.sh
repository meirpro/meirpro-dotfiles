#!/bin/bash
# Session heartbeat — runs on every Stop event (async).
# Tracks ACTIVE working time: only counts gaps < 30 min as active.
# Gaps >= 30 min are treated as idle (user was away / session resumed later).

SESSION_FILE="$HOME/.claude/session-active.json"
IDLE_THRESHOLD_SEC=1800  # 30 minutes

[ -f "$SESSION_FILE" ] || exit 0

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git branch --show-current 2>/dev/null || echo "n/a")"
RECENT_COMMITS="$(git log --oneline -5 --no-merges 2>/dev/null)"
CHANGED_FILES="$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')"

python3 -c "
import json, sys
from datetime import datetime, timezone

def parse_iso(s):
    return datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)

try:
    with open('$SESSION_FILE', 'r') as f:
        data = json.load(f)

    now = parse_iso('$NOW')
    last_seen = parse_iso(data.get('last_seen', data['start']))
    delta_sec = (now - last_seen).total_seconds()

    # Only count as active if gap < threshold
    if 0 < delta_sec < $IDLE_THRESHOLD_SEC:
        data['active_minutes'] = data.get('active_minutes', 0) + int(delta_sec / 60)

    data['last_seen'] = '$NOW'
    data['branch'] = '$BRANCH'
    commits = '''$RECENT_COMMITS'''.strip().split('\n') if '''$RECENT_COMMITS'''.strip() else []
    data['recent_commits'] = [c for c in commits if c]
    data['uncommitted_changes'] = int('$CHANGED_FILES') if '$CHANGED_FILES'.isdigit() else 0

    with open('$SESSION_FILE', 'w') as f:
        json.dump(data, f, indent=2)
except Exception:
    pass
" 2>/dev/null

exit 0
