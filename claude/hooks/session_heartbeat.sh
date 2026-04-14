#!/bin/bash
# Updates active_minutes and last_seen on every Stop hook.
# Uses session_lib.py to find or migrate the session file.

SESSIONS_DIR="$HOME/.claude/sessions"
SESSION_LIB="$HOME/.claude/hooks/session_lib.py"
mkdir -p "$SESSIONS_DIR"

INPUT=$(cat 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

# Resolve via the shared library — auto-migrates PID-format orphans
SESSION_FILE=$(python3 "$SESSION_LIB" resolve "$SESSION_ID" 2>/dev/null)

# If still not found, create a fresh file (recovery path)
if [ -z "$SESSION_FILE" ]; then
  SESSION_FILE=$(python3 "$SESSION_LIB" resolve-or-create "$SESSION_ID" 2>/dev/null)
fi

[ -f "$SESSION_FILE" ] || exit 0

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git branch --show-current 2>/dev/null || echo n/a)"
RECENT_COMMITS="$(git log --oneline -5 --no-merges 2>/dev/null)"
CHANGED_FILES="$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')"

python3 -c "
import json
from datetime import datetime,timezone
def p(s): return datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
try:
 with open('$SESSION_FILE') as f: data=json.load(f)
 now=p('$NOW')
 ls_str = data.get('last_seen', data.get('start'))
 if ls_str:
  ls=p(ls_str)
  d=(now-ls).total_seconds()
  if 0<d<1800:
   data['active_minutes']=data.get('active_minutes',0)+int(d/60)
 data['last_seen']='$NOW'
 data['branch']='$BRANCH'
 c='''$RECENT_COMMITS'''.strip().split('\n') if '''$RECENT_COMMITS'''.strip() else []
 data['recent_commits']=[x for x in c if x]
 data['uncommitted_changes']=int('$CHANGED_FILES') if '$CHANGED_FILES'.isdigit() else 0
 with open('$SESSION_FILE','w') as f: json.dump(data,f,indent=2)
except Exception as e:
 pass
" 2>/dev/null

exit 0
