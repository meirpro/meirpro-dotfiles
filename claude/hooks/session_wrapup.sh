#!/bin/bash
# Session wrapup — reads active_minutes since last wrapup, appends to time-log.
# Can be called multiple times per session — resets active_minutes each time.
# Session file is NOT deleted; it persists until the next SessionStart.
# Usage: session_wrapup.sh "summary text here"

SESSION_FILE="$HOME/.claude/session-active.json"
TIME_LOG="$HOME/.claude/time-log.jsonl"
SUMMARY="${1:-no summary provided}"

if [ ! -f "$SESSION_FILE" ]; then
  echo '{"error": "No active session found. Session may have already been wrapped up."}'
  exit 1
fi

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git branch --show-current 2>/dev/null || echo "n/a")"

# Get commits since last wrapup (or session start)
LAST_WRAPUP="$(python3 -c "
import json
with open('$SESSION_FILE') as f:
    data = json.load(f)
print(data.get('last_wrapup', data['start']))
" 2>/dev/null)"

RECENT_COMMITS="$(git log --oneline --since="$LAST_WRAPUP" --no-merges 2>/dev/null)"

python3 -c "
import json, sys, subprocess
from datetime import datetime, timezone

def parse_iso(s):
    return datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)

summary = sys.argv[1]

with open('$SESSION_FILE', 'r') as f:
    data = json.load(f)

now = parse_iso('$NOW')
last_seen = parse_iso(data.get('last_seen', data['start']))

# Add final active segment (time since last heartbeat, if recent)
delta_sec = (now - last_seen).total_seconds()
active_min = data.get('active_minutes', 0)
if 0 < delta_sec < 1800:
    active_min += int(delta_sec / 60)

# Wall clock: from last wrapup (or session start) to now
segment_start = data.get('last_wrapup', data['start'])
wall_start = parse_iso(segment_start)
wall_min = int((now - wall_start).total_seconds() / 60)

# Commits since last wrapup
commits_raw = '''$RECENT_COMMITS'''.strip().split('\n') if '''$RECENT_COMMITS'''.strip() else []
commits = [c for c in commits_raw if c]

# Files changed
try:
    n = len(commits)
    if n > 0:
        result = subprocess.run(
            ['git', 'diff', '--stat', '--name-only', f'HEAD~{n}..HEAD'],
            capture_output=True, text=True, timeout=5
        )
        files_changed = len([l for l in result.stdout.strip().split('\n') if l])
    else:
        files_changed = 0
except Exception:
    files_changed = 0

# Wrapup count for this session
wrapup_count = data.get('wrapup_count', 0) + 1

# Build JSONL entry
entry = {
    'date': '$NOW'[:10],
    'project': data.get('project', 'unknown'),
    'project_path': data.get('project_path', 'unknown'),
    'branch': '$BRANCH',
    'session_id': data.get('session_id', 'unknown'),
    'segment': wrapup_count,
    'start': segment_start,
    'end': '$NOW',
    'duration_min': active_min,
    'wall_clock_min': wall_min,
    'summary': summary,
    'files_changed': files_changed,
    'commits': commits
}

with open('$TIME_LOG', 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')

# Reset active_minutes and mark wrapup time — keep session alive
data['active_minutes'] = 0
data['last_wrapup'] = '$NOW'
data['last_seen'] = '$NOW'
data['wrapup_count'] = wrapup_count
data['branch'] = '$BRANCH'

with open('$SESSION_FILE', 'w') as f:
    json.dump(data, f, indent=2)

# Format for display
hours = active_min // 60
mins = active_min % 60
duration_display = f'{hours}h {mins}m' if hours > 0 else f'{mins}m'

wall_hours = wall_min // 60
wall_mins_r = wall_min % 60
wall_display = f'{wall_hours}h {wall_mins_r}m' if wall_hours > 0 else f'{wall_mins_r}m'

report = {
    'project': data.get('project', 'unknown'),
    'branch': '$BRANCH',
    'segment': wrapup_count,
    'active_time': duration_display,
    'wall_time': wall_display,
    'active_min': active_min,
    'wall_min': wall_min,
    'start': segment_start,
    'end': '$NOW',
    'commits': len(commits),
    'files_changed': files_changed,
    'summary': summary,
    'logged_to': '$TIME_LOG'
}
print(json.dumps(report, indent=2))
" "$SUMMARY"

exit 0
