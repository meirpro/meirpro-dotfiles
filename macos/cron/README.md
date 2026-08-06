# crontab

The user crontab on this machine, kept in version control. `crontab -l` is the
live copy; [`crontab`](crontab) in this directory is the source of truth.

Almost everything scheduled here should be a LaunchAgent instead — see
[`macos/launchd/`](../launchd/README.md). Cron is used for `saytime` only
because the job is a trivial one-liner on a fixed wall-clock interval, which is
the one shape where a plist is more ceremony than it's worth.

## Jobs

### `saytime` — announce the time in am/pm, every 15 minutes

```cron
*/15 * * * * /Users/meirpro/git/meirpro-dotfiles/macos/bin/saytime
```

macOS already has this feature — System Settings → Menu bar → Clock Options →
**Announce the time**, with the same quarter-hour intervals and a full
Customize Voice panel (rate, pitch, volume, timbre, sentence pause).

**It does not say AM or PM.** Its spoken string is always `It's two o'clock`.
AM/PM in that settings pane is a *display* option for the menu bar clock, not
an announcement one. The menu bar here is 24-hour, so the built-in
announcement is ambiguous, and changing the clock format to fix it isn't
wanted. Hence the script.

Turn the built-in one off if it's enabled, or both fire.

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
