#!/bin/bash
# Session wrapup — logs a time segment, keeps session alive
# Usage: bash session_wrapup.sh --session-id <UUID> "summary"
#    or: bash session_wrapup.sh --pid <PID> "summary"       (finds session by PID)
#    or: bash session_wrapup.sh "summary"                    (falls back to project-path match)

SESSIONS_DIR="$HOME/.claude/sessions"
TIME_LOG="$HOME/.claude/time-log.jsonl"
SESSION_ID=""
PID=""
SUMMARY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --pid)        PID="$2"; shift 2 ;;
    *)            SUMMARY="$1"; shift ;;
  esac
done

SUMMARY="${SUMMARY:-no summary provided}"
SESSION_FILE=""

# Strategy 1: Direct session ID lookup (best — exact, parallel-safe)
if [ -n "$SESSION_ID" ] && [ -f "$SESSIONS_DIR/$SESSION_ID.json" ]; then
  SESSION_FILE="$SESSIONS_DIR/$SESSION_ID.json"
fi

# Strategy 1b: Use session_lib resolver to handle PID-format orphans
if [ -z "$SESSION_FILE" ] && [ -n "$SESSION_ID" ]; then
  RESOLVED=$(python3 "$HOME/.claude/hooks/session_lib.py" resolve "$SESSION_ID" 2>/dev/null)
  if [ -n "$RESOLVED" ] && [ -f "$RESOLVED" ]; then
    SESSION_FILE="$RESOLVED"
  fi
fi

# Strategy 2: Find session file by PID field
if [ -z "$SESSION_FILE" ] && [ -n "$PID" ] && [ -d "$SESSIONS_DIR" ]; then
  SESSION_FILE=$(python3 -c "
import json,os,glob
for f in glob.glob(os.path.join('$SESSIONS_DIR','*.json')):
  try:
    with open(f) as h:
      d=json.load(h)
      if d.get('pid')==int('$PID') or os.path.basename(f)=='$PID.json':
        print(f); break
  except: pass
" 2>/dev/null)
fi

# Strategy 3: Fallback — most recent file matching project path
if [ -z "$SESSION_FILE" ] && [ -d "$SESSIONS_DIR" ]; then
  PROJECT_PATH="$(pwd)"
  SESSION_FILE=$(python3 -c "
import json,os,glob
p='$PROJECT_PATH'; best=None; bm=0
for f in glob.glob(os.path.join('$SESSIONS_DIR','*.json')):
  try:
    with open(f) as h: d=json.load(h)
    pp=d.get('project_path',d.get('cwd',''))
    if pp.lower()==p.lower():
      m=os.path.getmtime(f)
      if m>bm: best=f; bm=m
  except: pass
if best: print(best)
" 2>/dev/null)
fi

if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  echo '{"error":"No active session found. Pass --session-id <UUID> or --pid \$PPID."}'; exit 1
fi

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git branch --show-current 2>/dev/null || echo n/a)"

python3 -c "
import json,sys,subprocess,os,glob
from datetime import datetime,timezone

def p(s):
    return datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)

def ts_to_iso(ms):
    return datetime.fromtimestamp(ms/1000,tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

summary = sys.argv[1]
now = p('$NOW')

with open('$SESSION_FILE') as f:
    data = json.load(f)

# --- Normalize across session file formats ---
if 'start' in data:
    start_iso = data['start']
    sid = data.get('session_id', '?')
    project_path = data.get('project_path', '?')
    project = data.get('project', os.path.basename(project_path))
    last_seen_iso = data.get('last_seen', start_iso)
    active_min = data.get('active_minutes', 0)
    last_wrapup = data.get('last_wrapup', start_iso)
    wrapup_count = data.get('wrapup_count', 0)
elif 'startedAt' in data:
    start_iso = ts_to_iso(data['startedAt'])
    sid = data.get('sessionId', '?')
    project_path = data.get('cwd', '?')
    project = os.path.basename(project_path)
    last_seen_iso = start_iso
    active_min = 0
    last_wrapup = start_iso
    wrapup_count = 0
else:
    print(json.dumps({'error': 'Unrecognized session file format'}))
    sys.exit(1)

# Segment wall time (since last wrapup or session start)
segment_start = last_wrapup

# --- Try wrapper truth first ---
# When spawned by claude-timed (cld), CLAUDE_TIMING_LOG points at this
# session's exact JSONL log. Sum agent_work_ms + typing_ms for events
# whose ts falls within [segment_start, now]. Falls back to heartbeat
# active_min only if the env var is missing or parsing fails.
wrapper_active_min = None
timing_log = os.environ.get('CLAUDE_TIMING_LOG')
if timing_log and os.path.isfile(timing_log):
    try:
        seg_start_dt = p(segment_start)
        total_ms = 0
        with open(timing_log) as tf:
            for line in tf:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except:
                    continue
                ev_ts_str = ev.get('ts')
                if not ev_ts_str:
                    continue
                try:
                    ev_dt = datetime.fromisoformat(ev_ts_str.replace('Z', '+00:00'))
                except:
                    continue
                if ev_dt < seg_start_dt:
                    continue
                if ev_dt > now:
                    continue
                total_ms += int(ev.get('agent_work_ms', 0) or 0)
                total_ms += int(ev.get('typing_ms', 0) or 0)
        wrapper_active_min = total_ms // 60000
    except Exception:
        wrapper_active_min = None

if wrapper_active_min is not None:
    active_min = wrapper_active_min
else:
    # Fallback: heartbeat-based estimation. Add gap since last_seen if recent (< 30 min)
    try:
        ls = p(last_seen_iso)
        gap = (now - ls).total_seconds()
        if 0 < gap < 1800:
            active_min += int(gap / 60)
    except:
        pass

wm = int((now - p(segment_start)).total_seconds() / 60)

# Commits in this segment
try:
    r = subprocess.run(
        ['git', 'log', '--oneline', '--since=' + segment_start, '--no-merges'],
        capture_output=True, text=True, timeout=10
    )
    commits = [c for c in r.stdout.strip().split('\n') if c]
except:
    commits = []

# Files changed
try:
    n = len(commits)
    if n > 0:
        r = subprocess.run(
            ['git', 'diff', '--name-only', f'HEAD~{n}..HEAD'],
            capture_output=True, text=True, timeout=5
        )
        fc = len([l for l in r.stdout.strip().split('\n') if l])
    else:
        fc = 0
except:
    fc = 0

wc = wrapup_count + 1

# Detect parallel agents
pi = []
start_dt = p(start_iso)
for path in glob.glob(os.path.join('$SESSIONS_DIR', '*.json')):
    if os.path.abspath(path) == os.path.abspath('$SESSION_FILE'):
        continue
    try:
        with open(path) as f:
            o = json.load(f)
        if 'start' in o:
            o_start = p(o['start'])
            o_last = p(o.get('last_seen', o['start']))
            o_sid = o.get('session_id', '?')
        elif 'startedAt' in o:
            o_start = p(ts_to_iso(o['startedAt']))
            o_last = o_start
            o_sid = o.get('sessionId', '?')
        else:
            continue
        if o_start <= now and o_last >= start_dt:
            pi.append(o_sid)
    except:
        pass

# --- Write time log entry ---
e = {
    'date': '$NOW'[:10],
    'project': project,
    'project_path': project_path,
    'branch': '$BRANCH',
    'session_id': sid,
    'segment': wc,
    'start': segment_start,
    'end': '$NOW',
    'duration_min': active_min,
    'wall_clock_min': wm,
    'summary': summary,
    'files_changed': fc,
    'commits': commits,
}
if pi:
    e['parallel_with'] = pi

with open('$TIME_LOG', 'a') as f:
    f.write(json.dumps(e) + '\n')

# --- Update session file (keep alive, reset segment) ---
data['last_wrapup'] = '$NOW'
data['wrapup_count'] = wc
data['active_minutes'] = 0  # reset for next segment
data['last_seen'] = '$NOW'
# Ensure enriched fields exist for future heartbeats
if 'start' not in data and 'startedAt' in data:
    data['start'] = start_iso
    data['session_id'] = sid
    data['project'] = project
    data['project_path'] = project_path

with open('$SESSION_FILE', 'w') as f:
    json.dump(data, f, indent=2)

# --- Output report ---
h, m = divmod(active_min, 60)
dd = f'{h}h {m}m' if h else f'{m}m'
wh, wr = divmod(wm, 60)
wd = f'{wh}h {wr}m' if wh else f'{wr}m'

r = {
    'project': project,
    'branch': '$BRANCH',
    'session_id': sid,
    'segment': wc,
    'active_time': dd,
    'wall_time': wd,
    'active_min': active_min,
    'wall_min': wm,
    'start': segment_start,
    'end': '$NOW',
    'commits': len(commits),
    'files_changed': fc,
    'summary': summary,
    'logged_to': '$TIME_LOG',
}
if pi:
    r['parallel_with'] = pi
    r['parallel_count'] = len(pi)

print(json.dumps(r, indent=2))
" "$SUMMARY"

# === Push wrapup segment to CC API (best-effort) ===
TRACK_KEY_FILE="$HOME/.claude/track-key"
WRAPUP_QUEUE="$HOME/.claude/wrapup-queue.jsonl"
TIME_LOG_FILE="$HOME/.claude/time-log.jsonl"

if [ -f "$TRACK_KEY_FILE" ] && [ -f "$SESSION_FILE" ]; then
    SESSION_FILE_PATH="$SESSION_FILE" \
    TIME_LOG_PATH="$TIME_LOG_FILE" \
    WRAPUP_QUEUE_PATH="$WRAPUP_QUEUE" \
    TRACK_KEY_VAL=$(cat "$TRACK_KEY_FILE") \
    python3 - <<'PYEOF' 2>/dev/null || true
import json, os, sys
import urllib.request, urllib.error

session_file = os.environ.get("SESSION_FILE_PATH")
time_log = os.environ.get("TIME_LOG_PATH")
queue_file = os.environ.get("WRAPUP_QUEUE_PATH")
track_key = os.environ.get("TRACK_KEY_VAL", "")

if not (session_file and time_log and track_key):
    sys.exit(0)

# Load session JSON for telemetry block
try:
    with open(session_file) as f:
        session = json.load(f)
except Exception:
    sys.exit(0)

telemetry = session.get("telemetry", {}) or {}
live = telemetry.get("live", {}) or {}
totals = telemetry.get("totals", {}) or {}

# Read the LAST row from time-log.jsonl (just appended by the wrapup logic above)
last_row = None
try:
    with open(time_log) as f:
        for line in f:
            line = line.strip()
            if line:
                last_row = line
    if not last_row:
        sys.exit(0)
    last_data = json.loads(last_row)
except Exception:
    sys.exit(0)

# Build the API payload from the time-log row + telemetry
payload = {
    "session_id": last_data.get("session_id"),
    "segment_num": last_data.get("segment", 1),
    "start": last_data.get("start"),
    "end": last_data.get("end"),
    "duration_ms": (last_data.get("duration_min") or 0) * 60 * 1000,
    "wall_ms": (last_data.get("wall_clock_min") or 0) * 60 * 1000,
    "summary": last_data.get("summary"),
    "files_changed": last_data.get("files_changed", 0),
    "commits": last_data.get("commits", []),
    "parallel_with": last_data.get("parallel_with", []),
    "cwd": last_data.get("project_path"),
    "branch": last_data.get("branch"),
    # Live telemetry from statusline
    "cost_usd": live.get("cost_usd"),
    "api_duration_ms": live.get("api_duration_ms"),
    "wall_duration_ms": live.get("wall_duration_ms"),
    "lines_added": live.get("lines_added"),
    "lines_removed": live.get("lines_removed"),
    "tokens_in": live.get("tokens_in"),
    "tokens_out": live.get("tokens_out"),
    "model_id": live.get("model_id"),
    "model_display": live.get("model_display"),
    "claude_code_version": live.get("claude_code_version"),
    "context_window_size": live.get("context_window_size"),
    "context_used_percentage": live.get("context_used_percentage"),
    "rate_limit_5h_pct": live.get("rate_limit_5h_pct"),
    "rate_limit_7d_pct": live.get("rate_limit_7d_pct"),
    # Sub-agent telemetry
    "sub_agent_count": totals.get("sub_agent_count", 0),
    "sub_agent_total_ms": totals.get("sub_agent_total_ms", 0),
    "parallelism_factor": totals.get("parallelism_factor"),
}

# Drop if missing required fields
if not payload.get("session_id") or not payload.get("start") or not payload.get("end"):
    sys.exit(0)

# POST
try:
    req = urllib.request.Request(
        "https://cc.meir.pro/api/wrapup_segments",
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "X-Track-Key": track_key,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        if resp.status not in (200, 201):
            raise Exception(f"HTTP {resp.status}")
except Exception:
    # Queue for later flush
    try:
        with open(queue_file, "a") as qf:
            qf.write(json.dumps(payload) + "\n")
    except Exception:
        pass

sys.exit(0)
PYEOF
fi

exit 0
