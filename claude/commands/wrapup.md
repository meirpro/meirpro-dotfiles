---
description: "End-of-session: summarize work, log time, suggest CLAUDE.md improvements"
allowed-tools:
  [
    "Bash(bash ~/.claude/hooks/session_wrapup.sh:*)",
    "Bash(cat ~/.claude/session-active.json:*)",
    "Bash(cat ~/.claude/time-log.jsonl:*)",
    "Bash(git diff:*)",
    "Bash(git log:*)",
    "Bash(git status:*)",
    "Read",
  ]
---

# Session Wrapup

End-of-session routine: summarize what was accomplished, log time spent, and suggest CLAUDE.md improvements.

## Process

### Step 1 — Check session exists

Read `~/.claude/session-active.json` to confirm an active session. If missing, tell the user no session is being tracked and skip to CLAUDE.md suggestions only.

### Step 2 — Gather context for summary

Run in parallel:
- `git log --oneline --since="<start_time>" --no-merges` — commits this session
- `git diff --stat` — current changes

### Step 3 — Write a summary

Write a 1-3 sentence summary of what was accomplished, based on commits and diff. Be specific — mention feature names, bug fixes, files touched. Write it for a human reading a weekly report.

### Step 4 — Call the wrapup script

Run the wrapup script with the summary as argument:

```
bash ~/.claude/hooks/session_wrapup.sh "your summary here"
```

The script handles ALL mechanics:
- Reads session-active.json for start time and session_id
- Calculates duration
- Appends a JSONL entry to `~/.claude/time-log.jsonl`
- Deletes the session marker
- Outputs a JSON report

### Step 5 — Display the report

Parse the script's JSON output and display:

```
--- Session Wrapup ---
Project:     hayom
Branch:      main
Active time: 47m (actual working time)
Wall time:   2h 15m (start to finish)
Commits:     3
Files:       7 changed

Summary: Added session time tracking with SessionStart hook,
created /verify and /wrapup slash commands.

Logged to: ~/.claude/time-log.jsonl
---
```

Active time only counts periods where Claude was actively working (gaps < 30 min between turns). Wall time is the full start-to-end span. For weekly reports, active time is the useful metric.

### Step 6 — Suggest CLAUDE.md improvements

Review the work done this session. If you learned something about the codebase that would help future sessions (patterns, gotchas, conventions), suggest specific additions to the project's CLAUDE.md. Present as a bulleted list the user can approve or reject. Do NOT auto-edit CLAUDE.md.

## Important

- Do NOT use inline `$()` or date arithmetic in Bash — the wrapup script handles all calculation
- If duration >8 hours, warn the user the session file may be stale
- If no commits were made, still log the session with summary "no commits — exploratory/review session"
- The time-log.jsonl file is append-only — never read/modify existing entries
