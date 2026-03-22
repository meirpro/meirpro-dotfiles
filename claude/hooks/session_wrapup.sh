#!/bin/bash
SESSIONS_DIR="$HOME/.claude/sessions"
LEGACY_FILE="$HOME/.claude/session-active.json"
TIME_LOG="$HOME/.claude/time-log.jsonl"
SUMMARY="${1:-no summary provided}"
SESSION_FILE=""
if [ -d "$SESSIONS_DIR" ]; then
  PROJECT_PATH="$(pwd)"
  SESSION_FILE=$(python3 -c "
import json,os,glob
p='$PROJECT_PATH'; best=None; bm=0
for f in glob.glob(os.path.join('$SESSIONS_DIR','*.json')):
 try:
  with open(f) as h: d=json.load(h)
  if d.get('project_path','').lower()==p.lower():
   m=os.path.getmtime(f)
   if m>bm: best=f; bm=m
 except: pass
if best: print(best)
" 2>/dev/null)
fi
[ -z "$SESSION_FILE" ] && [ -f "$LEGACY_FILE" ] && SESSION_FILE="$LEGACY_FILE"
if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  echo '{"error":"No active session found."}'; exit 1
fi
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git branch --show-current 2>/dev/null || echo n/a)"
LAST_WRAPUP="$(python3 -c "
import json
with open('$SESSION_FILE') as f: d=json.load(f)
print(d.get('last_wrapup',d['start']))
" 2>/dev/null)"
RECENT_COMMITS="$(git log --oneline --since="$LAST_WRAPUP" --no-merges 2>/dev/null)"
python3 -c "
import json,sys,subprocess,os,glob
from datetime import datetime,timezone
def p(s): return datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
summary=sys.argv[1]
with open('$SESSION_FILE') as f: data=json.load(f)
now=p('$NOW'); ls=p(data.get('last_seen',data['start']))
d=(now-ls).total_seconds(); am=data.get('active_minutes',0)
if 0<d<1800: am+=int(d/60)
ss=data.get('last_wrapup',data['start']); wm=int((now-p(ss)).total_seconds()/60)
cr='''$RECENT_COMMITS'''.strip().split('\n') if '''$RECENT_COMMITS'''.strip() else []
commits=[c for c in cr if c]
try:
 n=len(commits)
 if n>0:
  r=subprocess.run(['git','diff','--stat','--name-only',f'HEAD~{n}..HEAD'],capture_output=True,text=True,timeout=5)
  fc=len([l for l in r.stdout.strip().split('\n') if l])
 else: fc=0
except: fc=0
wc=data.get('wrapup_count',0)+1
pi=[]
st=p(data['start'])
for path in glob.glob(os.path.join('$SESSIONS_DIR','*.json')):
 if os.path.abspath(path)==os.path.abspath('$SESSION_FILE'): continue
 try:
  with open(path) as f: o=json.load(f)
  if p(o['start'])<=now and p(o.get('last_seen',o['start']))>=st: pi.append(o.get('session_id','?'))
 except: pass
e={'date':'$NOW'[:10],'project':data.get('project','?'),'project_path':data.get('project_path','?'),'branch':'$BRANCH','session_id':data.get('session_id','?'),'segment':wc,'start':ss,'end':'$NOW','duration_min':am,'wall_clock_min':wm,'summary':summary,'files_changed':fc,'commits':commits}
if pi: e['parallel_with']=pi
with open('$TIME_LOG','a') as f: f.write(json.dumps(e)+'\n')
os.remove('$SESSION_FILE')
h,m=divmod(am,60); dd=f'{h}h {m}m' if h else f'{m}m'
wh,wr=divmod(wm,60); wd=f'{wh}h {wr}m' if wh else f'{wr}m'
r={'project':data.get('project','?'),'branch':'$BRANCH','session_id':data.get('session_id','?'),'segment':wc,'active_time':dd,'wall_time':wd,'active_min':am,'wall_min':wm,'start':ss,'end':'$NOW','commits':len(commits),'files_changed':fc,'summary':summary,'logged_to':'$TIME_LOG'}
if pi: r['parallel_with']=pi; r['parallel_count']=len(pi)
print(json.dumps(r,indent=2))
" "$SUMMARY"
exit 0
