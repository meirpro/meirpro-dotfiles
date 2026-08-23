# crontab

The user crontab on this machine, kept in version control. `crontab -l` is the
live copy; [`crontab`](crontab) in this directory is the source of truth.

Almost everything scheduled here should be a LaunchAgent instead — see
[`macos/launchd/`](../launchd/README.md). Cron is used for `saytime` only
because the job is a trivial one-liner on a fixed wall-clock interval, which is
the one shape where a plist is more ceremony than it's worth.

## Jobs

### `saytime` — a 15-minute passage-of-time reminder

```cron
SAYTIME_VOLUME=0.35
*/15 * * * * /Users/meirpro/git/meirpro-dotfiles/macos/bin/saytime
```

Speaks "It's 2:15". The purpose is noticing that another 15 minutes went by,
not looking up the time — so it deliberately omits AM/PM.

macOS has an equivalent built-in (Menu bar → Clock Options → **Announce the
time**) on the same quarter-hour schedule. **It is disabled on this machine**,
or both would fire. Re-enable it and remove this job if the script ever
becomes more trouble than it's worth:

```bash
/usr/libexec/PlistBuddy -c "Set :TimeAnnouncementPrefs:TimeAnnouncementsEnabled true" \
  ~/Library/Preferences/com.apple.speech.synthesis.general.prefs.plist && killall cfprefsd
```

#### Settings

Environment variables, set in the crontab above:

| Variable | Default | Notes |
|---|---|---|
| `SAYTIME_VOLUME` | `0.35` | 0.0–1.0. Attenuates *relative* to system volume — cannot exceed it. |
| `SAYTIME_VOICE` | system voice | Any name from `say -v ?`. Enhanced voices sound far better than the default. |
| `SAYTIME_RATE` | voice default | Words per minute. |

**`say` has no volume flag.** Volume comes from an inline speech command,
`[[volm 0.35]]`, prepended to the string — the synthesiser consumes it instead
of reading it aloud. This is the only way to attenuate `say` without changing
system output volume for everything else.

#### cron replays jobs missed during short sleeps — and that broke this

**If the machine sleeps through a quarter mark and wakes within 10 minutes,
cron runs the missed job on wake.** `date` inside the script then returns the
*wake* time, so the 5:00 announcement fires at 5:03 and says "It's 5:03" —
late, and wrong about the thing it exists to tell you.

This is not the documented behavior you'll find by skimming `cron.c`. The
`±600` second branch there is the **resync** path taken on *large* jumps, and
its comment ("we have the chance of missing a minute's jobs completely") reads
like cron never replays. For gaps **under** 600 seconds it does: it advances
its internal clock a minute at a time and runs each missed minute's jobs.

Measured on this machine over 132 logged invocations:

| | |
|---|---|
| Fired within 5s of a quarter mark | 73 |
| Fired late | **59 (45%)** |
| Maximum lag observed | **571s** — just under cron's 600s cutoff |

The 571s ceiling is what identified the mechanism; nothing else would stop
neatly below 600.

**Why it hits this machine so hard:** `pmset` shows `sleep 1` on battery — idle
system sleep after one minute, with Power Nap on. Nearly 2,900 sleep/wake
cycles since boot. Short naps across quarter marks are constant here, where on
a Mac idling at the default 10+ minutes this would be rare.

**The fix is a staleness check, not a scheduler change.** `saytime` computes how
far past the quarter mark it is and exits silently beyond `SAYTIME_MAX_LAG`
(default 90s), logging what it would have said. A replayed announcement is
dropped rather than spoken wrong.

```bash
SAYTIME_MAX_LAG=0 saytime          # always skips — proves the guard
saytime --force                    # speak regardless of lag
```

Moving to a LaunchAgent would *also* avoid the replay, but launchd's
`StartCalendarInterval` has the same underlying problem in a different shape:
it coalesces missed runs into one firing at wake time, which is still not the
boundary. The staleness check is needed either way, so the scheduler doesn't
have to change.

#### Log

Every invocation is recorded to `~/Library/Logs/saytime.log`:

```
2026-08-23 00:16:18 pid=80979  SPEAK lag=78s "It's 12:16"
2026-08-23 00:16:20 pid=80979  DONE  rc=0 after 2s
2026-08-23 00:16:22 pid=81287  SKIP  another instance still speaking
2026-08-23 00:16:18 pid=80973  SKIP  stale by 78s (max 0s)
```

`DONE … after Ns` is deliberate instrumentation for an **unresolved** problem:
several announcements were heard overlapping on wake, while the log showed
their invocations minutes apart. That points at `say` blocking on a suspended
audio device and flushing on wake, rather than at duplicate scheduling — the
log proves no two invocations ever landed within 90 seconds of each other.

**Baseline is 2 seconds** with the output device awake. A `DONE … after 200s`
line would confirm deferred playback. Until one appears, the overlap guard
(an atomic `set -o noclobber` lockfile — `flock` doesn't exist on macOS)
prevents a second announcement while one is still speaking, whatever the
cause.

#### This is a stopgap

It has no idea whether you're on a call — it will happily talk over a meeting.
The replacement is a menu bar app with a settings GUI and a mic/camera guard.
This script stays regardless: it has no dependencies and takes two seconds to
verify, which makes it the thing that still works when the app doesn't.

## The `%` trap — why this calls a script instead of inlining `date`

The obvious one-liner does not work in a crontab:

```cron
# BROKEN — cron eats the % signs
*/15 * * * * /usr/bin/say "It's $(date '+%-I:%M %p')"
```

**In a crontab, `%` is a metacharacter, not a literal.** cron converts every
unescaped `%` to a newline and hands everything after the first one to the
command as *stdin*. So the command that actually runs is
`/usr/bin/say "It's $(date '+'` — an unterminated quote — with the rest fed in
as input. It fails silently, because nothing is watching stderr.

Escaping each one (`\%-I:\%M \%p`) does work, but it is easy to get wrong on a
later edit and impossible to test by running the line in a shell — the shell
and cron disagree about what the text means. Putting the `date` call inside
[`macos/bin/saytime`](../bin/saytime) removes `%` from the crontab entirely,
and makes the logic runnable and testable on its own.

## Install

```bash
crontab macos/cron/crontab
crontab -l                     # confirm
```

`crontab <file>` **replaces** the whole crontab, it doesn't append. That's the
intent here — this file is the complete set of jobs. To add one, edit the file
and re-run, rather than `crontab -e`.

## Verify

```bash
macos/bin/saytime --print      # "It's 2:15 PM" — no audio
macos/bin/saytime              # speaks it

# under a bare environment, the way cron will run it
env -i HOME="$HOME" PATH=/usr/bin:/bin SHELL=/bin/sh macos/bin/saytime --print

pgrep -x cron                  # cron starts on first crontab install
```

Then wait for the next quarter hour and listen.

## Troubleshooting

- **Nothing spoken at the quarter hour** — check the log first. cron mails
  output to the local user, which nothing reads, so redirect it to see errors:
  append `>> /tmp/saytime.log 2>&1` to the crontab line temporarily.
- **`Operation not permitted` in that log** — macOS TCC blocking cron. Grant
  **Full Disk Access** to `/usr/sbin/cron` in System Settings → Privacy &
  Security. Add it with the `+` button and `⌘⇧G` → `/usr/sbin/cron` (it's
  hidden in the file picker otherwise).
- **Spoken twice** — the built-in "Announce the time" is still enabled. Turn it
  off in System Settings → Menu bar → Clock Options.
- **Silent but no error** — output volume, or the announcement is going to a
  device that isn't the one being listened to. `say` uses the current system
  output device at the current system volume, and respects mute.

## Related

- [`macos/bin/saytime`](../bin/saytime) — the script
- [`macos/launchd/README.md`](../launchd/README.md) — the preferred mechanism
  for anything more involved than this
