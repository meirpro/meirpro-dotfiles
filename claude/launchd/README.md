# launchd agents

macOS LaunchAgents that drive periodic hook scripts on a timer instead of
piggybacking on session events. Plists live here as templates; installation
copies or symlinks them into `~/Library/LaunchAgents/` and loads them with
`launchctl bootstrap`.

## Agents

### `pro.meir.cc.flush-wrapup-queue.plist`

Drains `~/.claude/wrapup-queue.jsonl` by replaying queued wrapup-segment
POSTs to `cc.meir.pro/api/wrapup_segments`. The queue collects payloads
that `session_wrapup.sh`'s 3-retry loop failed to deliver (CC outage,
Cloudflare hiccup, laptop offline at the time of `/wrapup` or session
exit).

- **Script:** `~/.claude/hooks/flush_wrapup_queue.sh`
- **Cadence:** every 30 minutes (`StartInterval: 1800`) + once at load (`RunAtLoad: true`)
- **Empty-queue cost:** <50ms early-exit, no HTTP calls
- **Dedupe:** the script GETs `/api/wrapup_segments?session_id=…&segment_num=…` before POSTing (CC has no idempotency keys, so dedupe is client-side)
- **Residual handling:** undelivered entries stay queued via tempfile+rename; nothing is lost on interruption

**Why launchd instead of SessionStart?** Earlier, this was wired into
`SessionStart` hooks (commit `f0455b5`) so every new session drained the
queue. That worked, but tied the drain cadence to "how often I start new
sessions" — for a backed-up queue during a long live session the drain is
deferred indefinitely. Moving to a 30-minute timer makes the drain cadence
predictable and keeps session startup a pure no-op for this concern.

## Install

```bash
# 1. Symlink the plist into LaunchAgents (so edits in the repo propagate)
ln -sf "$PWD/claude/launchd/pro.meir.cc.flush-wrapup-queue.plist" \
       "$HOME/Library/LaunchAgents/pro.meir.cc.flush-wrapup-queue.plist"

# 2. Ensure the log directory exists (launchd does not create it)
mkdir -p "$HOME/Library/Logs"

# 3. Load the agent into the current user's GUI session
launchctl bootstrap "gui/$UID" \
  "$HOME/Library/LaunchAgents/pro.meir.cc.flush-wrapup-queue.plist"
```

`bootstrap` also runs the job once (`RunAtLoad: true`), so you should see
a line appear in the stdout log within a second.

**Path caveat:** plists cannot shell-expand `~` or `$HOME` in log path
fields. If your home is not `/Users/lightwing`, edit
`StandardOutPath` and `StandardErrorPath` before installing. The
`ProgramArguments` *does* resolve `$HOME` because it runs through
`/bin/bash -c`.

## Verify

```bash
# Status (running? last exit code? next run?)
launchctl print "gui/$UID/pro.meir.cc.flush-wrapup-queue"

# Trigger a run on demand (don't wait for the 30-min interval)
launchctl kickstart -k "gui/$UID/pro.meir.cc.flush-wrapup-queue"

# Tail logs
tail -f "$HOME/Library/Logs/pro.meir.cc.flush-wrapup-queue.out.log"
tail -f "$HOME/Library/Logs/pro.meir.cc.flush-wrapup-queue.err.log"
```

Output on an empty queue is one line: `no queue file` or `queue file empty`.
Output on a live drain is a JSON summary with `processed`, `posted`,
`already_on_cc`, `failed`, `malformed`, `remaining_in_queue`.

## Uninstall

```bash
launchctl bootout "gui/$UID" \
  "$HOME/Library/LaunchAgents/pro.meir.cc.flush-wrapup-queue.plist"
rm "$HOME/Library/LaunchAgents/pro.meir.cc.flush-wrapup-queue.plist"
```

Logs in `~/Library/Logs/` are left behind; delete manually if desired.

## Editing the plist

After editing the plist in this repo, reload the agent so launchd picks up
the change:

```bash
launchctl bootout "gui/$UID" "$HOME/Library/LaunchAgents/pro.meir.cc.flush-wrapup-queue.plist"
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/pro.meir.cc.flush-wrapup-queue.plist"
```

Because the LaunchAgents entry is a symlink back to this repo, the edit is
live as soon as you save; the bootout/bootstrap cycle just forces launchd
to re-read the file.

## Troubleshooting

- **"Could not find specified service"** — the agent isn't loaded. Run the
  `bootstrap` command from Install.
- **No log file after 1 minute** — either `~/Library/Logs/` doesn't exist,
  or the path in the plist doesn't match your home directory. `mkdir -p`
  the log dir, check the plist paths.
- **Script runs but queue never shrinks** — check the `.err.log`. Common
  causes: missing track key (`cc_client.has_key()` returned false),
  Cloudflare blocking (check User-Agent is set — see
  `cc_client.py`), CC endpoint down (GET probe failing).
- **I want to run the drain right now** — `launchctl kickstart -k` forces
  an immediate run without waiting for the next interval.
