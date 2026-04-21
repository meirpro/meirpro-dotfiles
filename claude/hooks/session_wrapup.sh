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

# Single Python block:
#   1. Read session file, normalize, compute segment metrics.
#   2. Append entry to ~/.claude/time-log.jsonl.
#   3. Update session file (keep alive, reset segment counter).
#   4. Build CC payload from in-memory data + telemetry.
#   5. POST to cc.meir.pro with 3 retries (0.5s/1.5s/4s backoff). On
#      total failure, append payload to ~/.claude/wrapup-queue.jsonl.
#   6. Print one JSON report including cc_delivered + queued_depth so
#      callers can tell delivered-to-CC from queued-locally.
SESSION_FILE_PATH="$SESSION_FILE" \
TIME_LOG_PATH="$TIME_LOG" \
SESSIONS_DIR_PATH="$SESSIONS_DIR" \
NOW_ISO="$NOW" \
BRANCH_NAME="$BRANCH" \
WRAPUP_QUEUE="$HOME/.claude/wrapup-queue.jsonl" \
SUMMARY_ARG="$SUMMARY" \
python3 <<'PYEOF'
import json, os, sys, subprocess, glob
from datetime import datetime, timezone

# cc_client.py owns the X-Track-Key (Keychain or legacy file fallback),
# the User-Agent (CF won't 1010 us), and the retry/backoff schedule.
sys.path.insert(0, os.path.expanduser('~/.claude/hooks'))
import cc_client

session_file = os.environ['SESSION_FILE_PATH']
time_log = os.environ['TIME_LOG_PATH']
sessions_dir = os.environ['SESSIONS_DIR_PATH']
NOW = os.environ['NOW_ISO']
BRANCH = os.environ['BRANCH_NAME']
queue_file = os.environ['WRAPUP_QUEUE']
summary = os.environ['SUMMARY_ARG']

def p(s):
    return datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)

def ts_to_iso(ms):
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

now = p(NOW)

with open(session_file) as f:
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

# Heal the upstream "session file clobbered to ?" bug at the wrapup
# layer: when the session record's project_path is the "?" sentinel
# (or empty), fall back to the actual cwd so CC's resolveProject can
# attribute this segment instead of writing project_id=null.
# Documented in claude/hooks/KNOWN_ISSUES.md (last section).
if project_path in ('?', '', None):
    project_path = os.getcwd()
    project = os.path.basename(project_path) or project

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
for path in glob.glob(os.path.join(sessions_dir, '*.json')):
    if os.path.abspath(path) == os.path.abspath(session_file):
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
    'date': NOW[:10],
    'project': project,
    'project_path': project_path,
    'branch': BRANCH,
    'session_id': sid,
    'segment': wc,
    'start': segment_start,
    'end': NOW,
    'duration_min': active_min,
    'wall_clock_min': wm,
    'summary': summary,
    'files_changed': fc,
    'commits': commits,
}
if pi:
    e['parallel_with'] = pi

with open(time_log, 'a') as f:
    f.write(json.dumps(e) + '\n')

# --- Update session file (keep alive, reset segment) ---
data['last_wrapup'] = NOW
data['wrapup_count'] = wc
data['active_minutes'] = 0  # reset for next segment
data['last_seen'] = NOW
# Ensure enriched fields exist for future heartbeats
if 'start' not in data and 'startedAt' in data:
    data['start'] = start_iso
    data['session_id'] = sid
    data['project'] = project
    data['project_path'] = project_path

with open(session_file, 'w') as f:
    json.dump(data, f, indent=2)

# --- Push wrapup segment to CC API with retry ---
telemetry = data.get('telemetry', {}) or {}
live = telemetry.get('live', {}) or {}
totals = telemetry.get('totals', {}) or {}

payload = {
    'session_id': sid,
    'segment_num': wc,
    'start': segment_start,
    'end': NOW,
    'duration_ms': (active_min or 0) * 60 * 1000,
    'wall_ms': (wm or 0) * 60 * 1000,
    'summary': summary,
    'files_changed': fc,
    'commits': commits,
    'parallel_with': pi,
    'cwd': project_path,
    'branch': BRANCH,
    'cost_usd': live.get('cost_usd'),
    'api_duration_ms': live.get('api_duration_ms'),
    'wall_duration_ms': live.get('wall_duration_ms'),
    'lines_added': live.get('lines_added'),
    'lines_removed': live.get('lines_removed'),
    'tokens_in': live.get('tokens_in'),
    'tokens_out': live.get('tokens_out'),
    'model_id': live.get('model_id'),
    'model_display': live.get('model_display'),
    'claude_code_version': live.get('claude_code_version'),
    'context_window_size': live.get('context_window_size'),
    'context_used_percentage': live.get('context_used_percentage'),
    'rate_limit_5h_pct': live.get('rate_limit_5h_pct'),
    'rate_limit_7d_pct': live.get('rate_limit_7d_pct'),
    'sub_agent_count': totals.get('sub_agent_count', 0),
    'sub_agent_total_ms': totals.get('sub_agent_total_ms', 0),
    'parallelism_factor': totals.get('parallelism_factor'),
}

cc_delivered = False
cc_attempts = 0
cc_last_error = None

# Strengthened cwd guard: if the project_path sentinel heal (above) failed
# to produce a real path, refuse to POST a row that would land in CC with
# project_id=null. Known Issue: see claude/hooks/KNOWN_ISSUES.md section
# "Wrapup POSTs succeed with project_id: null when cwd = '?'".
# Queue locally with _skipped_reason so an operator can inspect + repair.
cwd_unresolved = project_path in ('?', '', None, '/')

# Only attempt POST when we have everything required AND cwd resolved.
if payload['session_id'] and payload['start'] and payload['end'] and not cwd_unresolved:
    result = cc_client.request(
        'POST', '/api/wrapup_segments',
        body=payload, timeout=15, retries=3,
    )
    cc_delivered = result['delivered']
    cc_attempts = result['attempts']
    cc_last_error = result['error']

    if not cc_delivered and cc_last_error != 'no_track_key':
        # Network / 5xx / non-retryable 4xx after the retry budget —
        # park the payload for flush_wrapup_queue.sh.
        try:
            with open(queue_file, 'a') as qf:
                qf.write(json.dumps(payload) + '\n')
        except Exception as ex:
            cc_last_error = f'queue-write-failed: {ex}'
elif cwd_unresolved:
    cc_last_error = f"cwd-unresolved: project_path={project_path!r} after heal; refusing POST to avoid null project_id"
    # Queue with a visible marker so this is distinguishable from normal
    # transient-failure queued payloads when flush_wrapup_queue.sh drains.
    skipped = {**payload, '_skipped_reason': 'cwd-unresolved'}
    try:
        with open(queue_file, 'a') as qf:
            qf.write(json.dumps(skipped) + '\n')
    except Exception as ex:
        cc_last_error = f'queue-write-failed: {ex}'

queued_depth = 0
try:
    if os.path.isfile(queue_file):
        with open(queue_file) as qf:
            queued_depth = sum(1 for ln in qf if ln.strip())
except Exception:
    pass

# --- Output report ---
h, m = divmod(active_min, 60)
dd = f'{h}h {m}m' if h else f'{m}m'
wh, wr = divmod(wm, 60)
wd = f'{wh}h {wr}m' if wh else f'{wr}m'

report = {
    'project': project,
    'branch': BRANCH,
    'session_id': sid,
    'segment': wc,
    'active_time': dd,
    'wall_time': wd,
    'active_min': active_min,
    'wall_min': wm,
    'start': segment_start,
    'end': NOW,
    'commits': len(commits),
    'files_changed': fc,
    'summary': summary,
    'logged_to': time_log,
    'cc_delivered': cc_delivered,
    'queued_depth': queued_depth,
}
if cc_attempts:
    report['cc_attempts'] = cc_attempts
if not cc_delivered and cc_last_error:
    report['cc_error'] = cc_last_error
if pi:
    report['parallel_with'] = pi
    report['parallel_count'] = len(pi)

print(json.dumps(report, indent=2))
PYEOF

exit 0
