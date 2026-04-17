# Session Tracker — Known Issues

## Session file resets to placeholder record mid-session

### Symptom

A live UUID-named session file at `~/.claude/sessions/<session_id>.json`
has its `project_path`/`project` fields clobbered to the literal string
`"?"`, `start` and `last_seen` get reset to a recent timestamp, and all
rich fields are lost — `last_wrapup`, `active_minutes`, `migrated_from_pid`,
`migration_note`, `telemetry`, `recent_commits`, `uncommitted_changes`.

Post-reset file contents match exactly the fresh-record template created
by `session_lib.py::resolve_session_file` when `create_if_missing=True`:

```python
# session_lib.py:114-126
fresh = {
    "session_id": session_id,
    "start": now_iso(),
    "last_seen": now_iso(),
    "active_minutes": 0,
    "project": "?",
    "project_path": "?",
    "branch": "n/a",
    "recent_commits": [],
    "uncommitted_changes": 0,
}
with open(uuid_path, "w") as f:
    json.dump(fresh, f, indent=2)
```

### Observed case (2026-04-17)

- Session `3841d13d-09ab-45e8-b74b-a15bc1b7b54b` in project
  `careers-sweetrobo-next`.
- First `/wrapup` earlier in the session succeeded, logged time, wrote
  `last_wrapup` into the file — confirmed by the output:

  ```json
  { "segment": 1, "active_time": "37m", "wall_time": "48m",
    "summary": "Migrated both AI endpoints ...",
    "parallel_count": 6 }
  ```

- Several hours of work continued (six additional commits landed on
  `main`). Session file was being updated by the heartbeat throughout.
- Second `/wrapup` attempt: the Step-1 resolver found the file by name
  but matched on `project_path == "?"`, not the current `$PWD`, so it
  correctly refused to proceed. The file's `start` had been reset to
  `2026-04-17T18:14:34Z`, erasing the segment-1 state. Time segment for
  that window could not be logged via `/wrapup`.

### Impact

- Time segments after the reset cannot be logged until either:
  - `project_path` is manually restored, or
  - The wrapup caller overrides `--session-id` and accepts the mangled
    `project_path` (the script may or may not tolerate this — untested).
- Active-minutes / wall-time / commit history data for that window is
  effectively orphaned. The commits themselves are safe (they live in
  git); only the time-tracking record is lost.
- The guard clause in the wrapup skill's Step 1
  (*"project_path MUST equal $PWD"*) is doing its job — without it, we'd
  be logging the segment under the wrong project.

### Hypothesis — mechanism

`session_heartbeat.sh` runs:

```bash
SESSION_FILE=$(python3 "$SESSION_LIB" resolve "$SESSION_ID" 2>/dev/null)
if [ -z "$SESSION_FILE" ]; then
  SESSION_FILE=$(python3 "$SESSION_LIB" resolve-or-create "$SESSION_ID" 2>/dev/null)
fi
```

`resolve` returns the UUID file path if `os.path.isfile(uuid_path)` is
true (the fast path at session_lib.py:87-89). The only way to reach the
`resolve-or-create` branch is for `resolve` to output nothing.

Suspected triggers (not yet confirmed):

1. **Concurrent write truncates the file.** The heartbeat's Python block
   does `with open(SESSION_FILE, 'w') as f: json.dump(data, f, indent=2)`
   without locking. If a second hook fires during the write window and
   `os.path.isfile()` briefly returns false (unlikely on macOS but
   possible if `w` mode was interrupted mid-create), the second caller
   falls through to `resolve-or-create` and wins the overwrite race with
   the template record.
2. **Stdout contamination suppresses the `resolve` output.** If the
   Python `resolve` branch prints anything extra to stdout before the
   path (it shouldn't — but a non-silenced warning or deprecation
   message in some environment would do it), `SESSION_FILE` would
   contain garbage, the file-exists check in the shell becomes false,
   and the fallback runs. Worth checking whether any Python warnings
   can leak to stdout in this codepath.
3. **`migrate_all_orphans` running from a sibling tool.** It deletes
   UUID-named orphans it considers duplicates (line 158-163). Our
   basename check at line 146 `if "-" in basename.replace(".json", "")
   and len(basename) > 30: continue` skips UUID-named files, so this
   is unlikely — but worth ruling out.

### Mitigations — ideas, not yet implemented

- **Preserve existing state in `resolve-or-create`.** Before writing the
  fresh template, re-check `os.path.isfile(uuid_path)` and re-load its
  contents if present. Only overwrite fields missing from the existing
  record. This makes the recovery path idempotent instead of destructive.
- **Write via tempfile + atomic rename.** `json.dump` to
  `uuid_path + ".tmp"`, `os.replace(tmp, uuid_path)`. Eliminates the
  "partial file readable" window during concurrent writes.
- **Add a `last_reset_cause` field** when the fresh-record path fires,
  so future occurrences leave a forensic trail (PID, caller script,
  timestamp).
- **Soft-recover in the wrapup resolver.** If no session file matches
  `$PWD` but a file with the current `$CLAUDE_SESSION_ID` exists with
  `project_path == "?"`, log a warning and heal it in place rather
  than refusing to wrap up. Trade-off: silently overriding the sanity
  check defeats its purpose. Better to heal in the heartbeat, not in
  wrapup.

### Related files

- `session_heartbeat.sh` — the Stop-hook that writes heartbeats
- `session_lib.py::resolve_session_file` — source of the fresh-template
- `session_wrapup.sh` — the caller that reads these records
- `session_tracker.sh` — creates the initial record on SessionStart

---

## Skill content is cached at SessionStart; long-running sessions run stale
## instructions forever — observed via wrapup skill's pre-fix `ls -t` picker

### Symptom

An agent in a long-running session receives the **pre-update version** of a
slash-command skill (e.g. `/wrapup`), even when the on-disk skill file
(`~/.claude/commands/wrapup.md`) has since been updated with bug fixes.
Tool calls succeed, no error is produced; the agent just follows stale
instructions. Any bug the update was meant to fix continues to manifest
for the duration of the session.

This is distinct from — but interacts with — the "pick-by-mtime session
resolver bug" that was already fixed in commit `42abdc5`. The resolver
fix is correct and live on disk, but sessions that started **before** the
fix landed never receive the updated skill content. The bug the fix
addresses keeps triggering in those sessions.

### Observed case (2026-04-14 → surfaced 2026-04-17)

- User was in session `70bcdbe5-a87c-4e50-b2f3-5fcfacfe02b4` (project
  `sweetrobo-backend`), started `2026-04-14T16:20:36Z` = 12:20 EDT.
- At `2026-04-14T17:11 EDT`, `~/.claude/commands/wrapup.md` was updated
  on disk (author: meirpro). The change replaced the `ls -t` discovery
  instruction with a deterministic Python resolver that matches session
  files by `project_path == $PWD`. The commit landed at
  `2026-04-14T22:33 EDT` as `42abdc5 wrapup skill: resolve session by
  project_path, never by mtime`. The skill file mtime pre-dates the
  commit because the author tested locally before committing.
- On `2026-04-17T14:?? EDT` (≈3 days into the session), the agent
  invoked `/wrapup`. The skill content delivered into the conversation
  was the **pre-fix** version — the old Step 1 that says "Your session
  ID is in the conversation context. Extract these fields…" The
  resolver Python block from commit `42abdc5` was absent from the
  delivered skill text.
- The agent, following pre-fix instructions with no actual session_id
  available in the conversation context, fell back to
  `ls -t ~/.claude/sessions/*.json | head -3`. It picked
  `d6a4996d-6fda-4f33-807c-0518c52f3f2e.json` (an older
  `careers-sweetrobo-next` session that had been recently
  heartbeat-touched), not the actual current session. Local and remote
  wrapup records were written under the wrong session.
- Discovery: user spot-checked and noticed the mislabel
  ("why careers-sweetrobo-next? we are on the sweetrobo-backend").
- The fix (commit `42abdc5`) WOULD have prevented this — it explicitly
  forbids `ls -t` and refuses to proceed on `project_path` mismatch.
  But the agent never saw the fixed instructions.

### Verification the fix exists on disk

```bash
$ grep -c "Resolve the current session deterministically" ~/.claude/commands/wrapup.md
1
$ head -3 ~/.claude/commands/wrapup.md
---
description: "Log a time segment with summary for the current work topic"
...
```

The file has the new Step 1. An agent starting a fresh session **today**
would receive the correct instructions. Only long-lived sessions that
pre-date the update are affected.

### Impact

- **Users of long-running sessions never benefit from skill fixes** until
  they close and reopen the session. "Long-running" here means anything
  from hours to days — Claude Code supports session resumption across
  CLI restarts, and many users treat a session as semi-permanent for a
  project.
- **Every skill update has a rollout window** during which fixed
  behavior is unavailable to existing users. Users who reason "I already
  updated the dotfiles, the bug is gone" are wrong for their own
  still-open sessions.
- **Latent bugs stay exploitable indefinitely.** If the skill file is
  updated to patch a data-integrity or security issue, existing sessions
  continue executing the vulnerable instructions until natural churn
  ends them.

### Root cause — mechanism (hypothesis)

Claude Code appears to load the slash-command skill file content at
**SessionStart** and include it in the session's system prompt or
available-skills manifest. That content is snapshot-copied into the
persistent conversation state; subsequent changes to the file on disk
don't retroactively update the already-loaded content.

This is consistent with how Anthropic describes skill loading in the
docs (skills are injected into the system prompt at load time), and
with the observed behavior in this session: `grep` of the live skill
file shows the new text, but what the agent receives when invoking
`/wrapup` is the old text.

Unverified but plausible details:
- Skill content may be re-serialized at session-resume time from the
  session's stored state rather than re-read from disk.
- There may be a cache-invalidation path (e.g., `claude --reset-skills`
  or closing and reopening the session entirely) that would force a
  reload, but no such mechanism is documented.
- This may only affect slash-command skills (the `/foo` kind); invoked
  Skill-tool skills may behave differently. Not tested here.

### Related issue in this file

The previous section of this document — "Session file resets to
placeholder record mid-session" — describes a data loss during an
earlier session on the same day (2026-04-17, session
`3841d13d-09ab-...`). That session's second wrapup attempt failed
because the session file had been clobbered. It's conceivable that
THAT agent was also running pre-fix skill instructions for the same
reason described here, but the symptom is different and the mechanisms
likely independent. Worth cross-checking whether the agent that wrote
that section also received old skill text — if so, both observations
point to the same underlying "skill content is snapshot-frozen" bug
as the amplifier.

### Mitigations — ideas, not yet implemented

Ordered by where the fix would live:

1. **In Claude Code itself**: add a skill-cache-reload mechanism.
   Either:
   - Re-read skill files from disk on every `/command` invocation (simple
     but higher latency), or
   - Watch the skills directory and invalidate the in-memory cache when
     files change (mtime or inotify/FSEvents), or
   - Expose a `/reload-skills` meta-command so users can opt in to fresh
     content without restarting the session.

   This is the only robust fix — it eliminates the staleness window
   entirely. Needs coordination with Anthropic or filing a feature
   request against the Claude Code team.

2. **In the skill file itself**: include a self-freshness check as the
   first step. E.g., skill instructs the agent to `stat -f "%m"
   ~/.claude/commands/wrapup.md` and compare against a known-good
   timestamp embedded in the instructions. If the on-disk file is newer
   than the instructions the agent has, tell the user "this skill has
   been updated on disk since your session started; please restart
   Claude Code to pick up the fix" and refuse to proceed. Defensive but
   viable.

3. **Out of band**: notify users. When a skill is updated with a
   correctness fix, surface a banner at SessionStart (via
   `session_tracker.sh`) in any session whose start time pre-dates the
   skill file's mtime. "Heads up: your wrapup skill has been updated
   since this session started; restart to pick up the fix."

4. **For the wrapup skill specifically**: move the resolver logic out
   of the skill instructions entirely and into `session_wrapup.sh`.
   The skill instructs the agent to call
   `session_wrapup.sh --summary "..."` with NO session_id arg; the
   script itself does the project_path-match resolution. Then the bug
   fix lives in a shell script (which is invoked fresh on every run,
   no caching), not in a skill file (which is snapshot-loaded). This
   converts a cached-skill problem into a live-script problem, which
   we already know how to solve. Probably the most pragmatic fix for
   this specific skill, and would be a general anti-pattern lesson:
   **put logic in scripts, not in skill prose**, because scripts
   reload live.

### Related files

- `~/.claude/commands/wrapup.md` — on-disk skill file, has the fix
- `meirpro-dotfiles/claude/commands/wrapup.md` (hardlinked copy in git)
- `~/.claude/hooks/session_wrapup.sh` — already accepts
  `--session-id`; could be extended to do resolution itself
- Commit `42abdc5` — the existing fix that never reached pre-commit sessions
- `cc.meir.pro/api/wrapup_segments` POST accepts `correction_of_id` for
  after-the-fact fixes (the escape hatch used to correct segment id=8 →
  id=9 in this session)

### Why this is worth prioritizing

Skill staleness is a **systemic latent-bug amplifier**: every future
skill fix will also fail to reach long-running sessions unless this
loading/caching behavior is addressed. Today the cost is one mislabeled
time-tracking segment. Next time it could be a security fix to a skill
that handles secrets, a correctness fix to a data-manipulation skill,
or an instruction update that protects against a newly-discovered
prompt injection pattern. The longer sessions live, the larger the
window during which they're running outdated behavior.

Moving skill logic into scripts (mitigation #4 above) is a cheap
workaround for individual skills as they're fixed, but doesn't solve
the general problem. The general solution needs to live in Claude Code's
skill-loading layer.
