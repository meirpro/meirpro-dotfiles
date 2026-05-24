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

1. `$SID` must be a valid UUID, NOT the literal string `${CLAUDE_SESSION_ID}`. If Claude Code didn't substitute (older versions may not), the token will still be there verbatim — in that case, **ask the user for the first 8 chars of their session ID** (visible in their Claude Code status bar). Do not silently pick a different session.
2. The session file MUST exist at `~/.claude/sessions/$SID.json`. If missing, **retry 3× with 1 s sleeps** — the heartbeat hook creates it lazily on the first Stop hook, so the file may not exist yet at the moment `/wrapup` starts. After retries, if still missing, see "Lazy file race" below.
3. The file's `project_path` MUST equal `$PWD` (case-insensitive). If it's `"?"`, the heartbeat hook hadn't populated it yet — **rewrite the file's `project_path` to `$PWD` and proceed** (the substituted SID is ground truth; an unpopulated `project_path` doesn't override that). If it's a different real path (not `?`), STOP and report the mismatch.

#### Lazy file race — the heartbeat sometimes creates the session file AFTER `/wrapup` starts

Empirically observed: on a fresh process, the first turn of `/wrapup` can fire before the heartbeat hook has written `~/.claude/sessions/$SID.json`. The skill USED to silently fall back to a PWD-based resolver and pick an adjacent session (wrong cost, wrong start time, wrong everything). **Never do that.** Instead:

1. Retry `cat` 3× with 1 s sleeps to let a slow heartbeat finish writing.
2. If still missing, **create a minimal stub yourself** so the wrapup script has something to anchor to:
   ```bash
   python3 - <<EOF
   import json, os
   from datetime import datetime, timezone
   path = os.path.expanduser(f"~/.claude/sessions/$SID.json")
   if not os.path.exists(path):
       now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
       json.dump({
           "session_id": "$SID",
           "start": now,
           "last_seen": now,
           "active_minutes": 0,
           "project_path": "$PWD",
           "project": os.path.basename("$PWD".rstrip("/")) or "?",
           "branch": "$BRANCH",
           "recent_commits": [],
           "uncommitted_changes": 0,
       }, open(path, "w"), indent=2)
   EOF
   ```
3. Mark `wall_unreliable: true` in your eventual report — the wrapup script's `wall_min` will be ~0 because the stub `start` is "now". Reconcile against the status line per Step 5.5.

#### Fallback resolver (only if the substitution above truly didn't expand)

If `$SID` literally contains `${CLAUDE_SESSION_ID}` (unexpanded), **don't guess** — the status bar in Claude Code shows the first 8 chars of the session ID. Ask the user:

> Couldn't read the session ID. Your Claude Code status bar shows the first 8 chars of the session — could you paste them? (e.g. `e4a7e8bc`)

Then match exactly one file under `~/.claude/sessions/`:

```bash
ls ~/.claude/sessions/<first-8-chars>*.json
```

Zero matches → "No session file matching `<prefix>`" and stop. Multiple matches → ask the user for more characters. Exactly one match → use it.

**Never use `ls -t`** and **never fall back to PWD-resolution silently** — parallel sessions and a lazy heartbeat make adjacent-session selection a foot-gun. Mislabeled wrapups carry wrong cost/time numbers and pollute `time-log.jsonl`.

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

### Step 5.5 — Reconcile against the status line (MANDATORY when worktree / no session file)

The script's `wall_min`/`active_min`/`commits` are derived from the session
FILE. That file is **missing for git-worktree sessions** (the heartbeat keys
session files by the main-repo path), so the script falls back to "now" and
returns a bogus `wall_min`≈1, `active_min`=0, `commits`=0 for what may be a
multi-hour session. `api_min`/`cost_usd` come from telemetry and ARE correct.

The **authoritative** numbers are on the user's Claude Code STATUS LINE
(e.g. `41h57m (API: 4h7m) 💰 $219`), produced by `claude-timed` from
`~/.claude/timings/*.jsonl`, independent of the session file.

So:

1. Look at the script's JSON output. If it contains `"wall_unreliable": true`
   (or `wall_min` ≤ 2 while you know the session ran longer, or you resolved
   the session via the worktree fallback / no session file existed):
   - **Ask the user for their status-line figures** if you don't already have
     them ("what does your status line show for time / API / cost?"), OR use
     the figures the user already volunteered this turn.
   - **Embed those authoritative numbers verbatim into the summary text**
     passed to `session_wrapup.sh` (so the append-only time-log entry carries
     the truth even though the structured fields are understated), e.g.
     append: `Wall <status-line wall>, API <status-line api>, $<cost> (from
     status line; session-file gap — worktree).`
2. Always run the script with `--session-id` of the real session even if no
   file exists for it — the telemetry/cost still resolve, and the summary
   text carries the corrected wall/API/cost.

### Step 6 — Display the report

Parse the JSON output and format as below. When Step 5.5 applied, show the
status-line numbers as the headline figures and annotate the structured ones:

```
--- Session Wrapup ---
Project:     <project>
Branch:      <branch>
Segment:     <N>
Active time: <status-line wall>   (script saw <wall_min>m — session-file gap)
Wall time:   <status-line wall>   (worktree: no session file; see note)
API time:    <api_time>           ✓ (telemetry — trustworthy)
Cost:        $<cost_usd>           ✓ (telemetry — trustworthy)
Commits:     <N or "git log count">
Summary:     <text incl. embedded authoritative numbers>
Logged to:   ~/.claude/time-log.jsonl
---
```

When the session file WAS present and valid, omit the parentheticals and use
the structured fields directly.

## Rules

- **Always pass `--session-id`** — never rely on project-path guessing
- **NEVER pick the session by `ls -t` / most-recently-modified.** Stale heartbeats and parallel agents make that unreliable. Use the Step 1 resolver.
- **Never proceed past Step 1 if `project_path != $PWD`** — UNLESS the only mismatch is that `$PWD` is a git worktree of the session's project (e.g. session `project_path` is `/repo`, `$PWD` is `/repo/.claude/worktrees/foo`). That is the same project; it is NOT cross-project contamination. In that case proceed, but apply Step 5.5 (status-line reconciliation) because the worktree session likely has no session file of its own.
- **Run exactly the commands listed above** — no variations, no extra git commands
- Each wrapup logs ONE segment. The session stays alive for the next topic.
- Do NOT use inline `$()` or date arithmetic — the script handles all calculation
- If wall time > 8 hours, warn the user the session may be stale
- If no commits, still log: include "no commits — exploratory/review session"
- The time-log.jsonl is append-only — never modify existing entries
