---
description: "Log a time segment with summary for the current work topic"
allowed-tools:
  [
    "Bash(bash ~/.claude/hooks/session_wrapup.sh:*)",
    "Bash(cat ~/.claude/sessions:*)",
    "Bash(cat ~/.claude/timings:*)",
    "Bash(echo $PPID:*)",
    "Bash(python3 -c *)",
    "Bash(git -C * log --oneline --since=* --no-merges -20:*)",
    "Bash(git -C * branch --show-current:*)",
    "Bash(git -C * diff --stat HEAD~*:*)",
  ]
---

# Session Wrapup

Log a time segment for the current work topic, then continue the session.

## How sessions work

- Each Claude Code process gets a session file at `~/.claude/sessions/<session_id>.json`
- The heartbeat hook updates `last_seen` and `active_minutes` on every prompt
- `/wrapup` logs a time segment WITHOUT destroying the session — it resets the segment start
- Multiple wrapups per session are normal (one per topic/feature/task)
- On session exit, `claude-timed` auto-wrapups with a mechanical summary as a fallback

## Process — follow these steps EXACTLY

### Step 1 — Resolve the current session

**Your session ID is: `${CLAUDE_SESSION_ID}`**

Claude Code substitutes this literal token with the actual UUID of the current session when it renders this skill. Use it directly — no guessing, no scanning, no mtime races.

Assign it to a variable and read the session file:

```bash
SID='${CLAUDE_SESSION_ID}'
SESSION_FILE=~/.claude/sessions/"$SID".json
cat "$SESSION_FILE"
```

Extract these fields:
- `session_id` — for the wrapup script call (should equal `$SID`)
- `last_wrapup` (or `start` if first wrapup) — for the git log --since filter
- `project_path` — for git commands
- `branch` — for the report

**Sanity check — MUST pass before proceeding past this step:**

1. `$SID` must be a valid UUID, NOT the literal string `${CLAUDE_SESSION_ID}`. If Claude Code didn't substitute (older versions may not), the token will still be there verbatim — in that case, fall back to the resolver below.
2. The session file MUST exist at `~/.claude/sessions/$SID.json`. If missing, tell the user "No session file for $SID" and stop.
3. The file's `project_path` MUST equal `$PWD` (case-insensitive). If it doesn't, STOP and report the mismatch — something is inconsistent and wrapping up would mislabel the work.

#### Fallback resolver (only if the substitution above didn't expand)

If `$SID` literally contains `${CLAUDE_SESSION_ID}` (unexpanded), use this deterministic resolver. **Never use `ls -t` to pick the most-recent file** — parallel sessions and stale heartbeats make that unreliable.

```bash
python3 -c '
import json, os, glob
pwd = os.getcwd().lower()
best, best_ts = None, ""
for f in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
    try:
        d = json.load(open(f))
        pp = (d.get("project_path") or d.get("cwd") or "").lower()
        if pp == pwd:
            ls = d.get("last_seen") or d.get("start") or ""
            if ls > best_ts:
                best_ts = ls; best = f
    except Exception: pass
print(best or "")
'
```

Rules for the fallback:
- **Zero matches** → tell the user "No session being tracked for $PWD" and stop.
- **Exactly one match** → use it.
- **Multiple matches** → the resolver picks the one with highest `last_seen`.

Then `cat` the resolved file and apply the same sanity check (`project_path == $PWD`).

### Step 2 — Read wrapper timing (if available)

```bash
cat ~/.claude/timings/.current-session
```

If that file exists, it contains the path to the current timing JSONL. Read the last 20 lines to find timing events. Sum up `typing_ms`, `agent_work_ms`, and `idle_ms` from events that occurred since `last_wrapup`. If the file doesn't exist, skip this step — timing data is optional.

### Step 3 — Get recent commits

Run exactly this command, substituting the timestamp from step 1:

```bash
git -C <project_path> log --oneline --since="<last_wrapup>" --no-merges -20
```

Count the number of commits returned.

### Step 4 — Get changed files count

If there were commits in step 3, run:

```bash
git -C <project_path> diff --stat HEAD~<commit_count>
```

Where `<commit_count>` is the count from step 3. If 0 commits, skip this step.

### Step 5 — Write summary and call wrapup

Write a 1-3 sentence summary of the work done in this segment. Be specific: feature names, bug fixes, files touched. If wrapper timing is available, append: "Agent: Xm, Typing: Ym, Idle: Zm".

Then call the wrapup script:

```bash
bash ~/.claude/hooks/session_wrapup.sh --session-id <session_id> "<your summary here>"
```

### Step 6 — Display the report

Parse the JSON output and format as:

```
--- Session Wrapup ---
Project:     <project>
Branch:      <branch>
Segment:     <N>
Active time: <Xh Ym>
Wall time:   <Xh Ym>
Commits:     <N>
Summary:     <text>
Logged to:   ~/.claude/time-log.jsonl
---
```

## Rules

- **Always pass `--session-id`** — never rely on project-path guessing
- **NEVER pick the session by `ls -t` / most-recently-modified.** Stale heartbeats and parallel agents make that unreliable. Use the Step 1 resolver.
- **Never proceed past Step 1 if `project_path != $PWD`.** A mismatch means you have the wrong session file.
- **Run exactly the commands listed above** — no variations, no extra git commands
- Each wrapup logs ONE segment. The session stays alive for the next topic.
- Do NOT use inline `$()` or date arithmetic — the script handles all calculation
- If wall time > 8 hours, warn the user the session may be stale
- If no commits, still log: include "no commits — exploratory/review session"
- The time-log.jsonl is append-only — never modify existing entries
