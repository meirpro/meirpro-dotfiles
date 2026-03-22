#!/bin/bash
DAYS="${1:-7}"; TIME_LOG="$HOME/.claude/time-log.jsonl"; SESSIONS_DIR="$HOME/.claude/sessions"
[ ! -f "$TIME_LOG" ] && echo "No time log found" && exit 1
python3 -c "
import json,os,glob
from datetime import datetime,timezone,timedelta
from collections import defaultdict
days=int('$DAYS'); cutoff=(datetime.now(timezone.utc)-timedelta(days=days)).strftime('%Y-%m-%d')
entries=[]
with open('$TIME_LOG') as f:
 for line in f:
  line=line.strip()
  if not line: continue
  try:
   e=json.loads(line)
   if e.get('date','')>=cutoff: entries.append(e)
  except: pass
if not entries: print(f'No sessions in the last {days} days.'); raise SystemExit(0)
groups=defaultdict(list)
for e in entries: groups[(e.get('project','?'),e.get('branch','n/a'))].append(e)
sd=min(e.get('date','') for e in entries); ed=max(e.get('date','') for e in entries)
print(f'Session Report: {sd} to {ed}'); print('='*50)
ta=tw=ts=0
for (proj,br),group in sorted(groups.items()):
 a=sum(e.get('duration_min',0) for e in group); w=sum(e.get('wall_clock_min',0) for e in group)
 ss=len(set(e.get('session_id','') for e in group)); cc=sum(len(e.get('commits',[])) for e in group)
 mp=max((len(e.get('parallel_with',[])) for e in group),default=0)+1
 ta+=a; tw+=w; ts+=ss
 ah,am=divmod(a,60); astr=f'{ah}h {am}m' if ah else f'{am}m'
 wh,wm=divmod(w,60); wstr=f'{wh}h {wm}m' if wh else f'{wm}m'
 ratio=f'{a/w:.1f}x' if w>0 else '-'
 print(f''); print(f'{proj} ({br})'); print(f'  Agent-hours:   {astr}'); print(f'  Wall time:     {wstr} ({ratio} parallelism)')
 print(f'  Sessions:      {ss}'); print(f'  Commits:       {cc}')
 if mp>1: print(f'  Peak parallel: {mp} agents')
 for e in group:
  s=e.get('summary','')
  if s and 'auto-closed' not in s:
   sid=e.get('session_id','?')[:8]; d=e.get('duration_min',0)
   print(f'    [{sid}] {d}m - {s[:80]}')
print(''); print('='*50)
th,tm=divmod(ta,60); print(f'Total agent-hours: {th}h {tm}m across {ts} sessions')
if os.path.isdir('$SESSIONS_DIR'):
 act=[]
 for p in glob.glob(os.path.join('$SESSIONS_DIR','*.json')):
  try:
   with open(p) as f: act.append(json.load(f))
  except: pass
 if act:
  print(''); print('Active sessions:')
  for s in act:
   sid=s.get('session_id','?')[:8]; proj=s.get('project','?'); br=s.get('branch','?'); m=s.get('active_minutes',0)
   print(f'  [{sid}] {proj} ({br}) - {m}m active')
"
exit 0
