#!/bin/bash
SESSIONS_DIR="$HOME/.claude/sessions"
TIME_LOG="$HOME/.claude/time-log.jsonl"
LEGACY_FILE="$HOME/.claude/session-active.json"
mkdir -p "$SESSIONS_DIR"
python3 -c "
import json,os,glob
from datetime import datetime,timezone,timedelta
cutoff=datetime.now(timezone.utc)-timedelta(hours=8)
for p in glob.glob(os.path.join('$SESSIONS_DIR','*.json')):
 try:
  with open(p) as f: d=json.load(f)
  ls=datetime.strptime(d.get('last_seen',d['start']),'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
  if ls<cutoff:
   e={'date':d.get('last_seen',d['start'])[:10],'project':d.get('project','?'),'project_path':d.get('project_path','?'),'branch':d.get('branch','n/a'),'session_id':d.get('session_id','?'),'start':d['start'],'end':d.get('last_seen',d['start']),'duration_min':d.get('active_minutes',0),'summary':'auto-closed: orphan >8h','files_changed':d.get('uncommitted_changes',0),'commits':d.get('recent_commits',[])}
   with open('$TIME_LOG','a') as f: f.write(json.dumps(e)+'\n')
   os.remove(p)
 except: pass
" 2>/dev/null
if [ -f "$LEGACY_FILE" ]; then
  python3 -c "
import json
try:
 with open('$LEGACY_FILE') as f: d=json.load(f)
 e={'date':d.get('last_seen',d['start'])[:10],'project':d.get('project','?'),'project_path':d.get('project_path','?'),'branch':d.get('branch','n/a'),'session_id':d.get('session_id','?'),'start':d['start'],'end':d.get('last_seen',d['start']),'duration_min':d.get('active_minutes',0),'summary':'auto-closed: legacy migration','files_changed':d.get('uncommitted_changes',0),'commits':d.get('recent_commits',[])}
 with open('$TIME_LOG','a') as f: f.write(json.dumps(e)+'\n')
except: pass
" 2>/dev/null
  rm -f "$LEGACY_FILE"
fi
SESSION_ID=$(cat 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown-$(date +%s)"
PROJECT_PATH="$(pwd)"; PROJECT_NAME="$(basename "$PROJECT_PATH")"
BRANCH="$(git branch --show-current 2>/dev/null || echo n/a)"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SESSION_LIB="$HOME/.claude/hooks/session_lib.py"

# Try to migrate any existing PID-format orphan for this session_id
EXISTING=$(python3 "$SESSION_LIB" resolve "$SESSION_ID" 2>/dev/null)

if [ -n "$EXISTING" ] && [ -f "$EXISTING" ]; then
  # File already exists (UUID or just-migrated PID) — update fields, don't overwrite
  python3 -c "
import json
try:
 with open('$EXISTING') as f: d=json.load(f)
 d.setdefault('session_id','$SESSION_ID')
 d.setdefault('start','$NOW')
 d.setdefault('last_seen','$NOW')
 d.setdefault('active_minutes',0)
 if not d.get('project') or d.get('project')=='?':
  d['project']='$PROJECT_NAME'
 if not d.get('project_path') or d.get('project_path')=='?':
  d['project_path']='$PROJECT_PATH'
 d['branch']='$BRANCH'
 with open('$EXISTING','w') as f: json.dump(d,f,indent=2)
except: pass
" 2>/dev/null
else
  # Fresh session — create a new UUID file
  python3 -c "
import json
with open('$SESSIONS_DIR/${SESSION_ID}.json','w') as f:
 json.dump({'session_id':'$SESSION_ID','start':'$NOW','last_seen':'$NOW','active_minutes':0,'project':'$PROJECT_NAME','project_path':'$PROJECT_PATH','branch':'$BRANCH','recent_commits':[],'uncommitted_changes':0},f,indent=2)
"
fi

exit 0
