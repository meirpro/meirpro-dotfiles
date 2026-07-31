# macOS LaunchAgents

System-level LaunchAgents that aren't tied to Claude Code. (Claude Code's own
agents live in [`claude/launchd/`](../../claude/launchd/README.md).)

Plists here are templates; installation symlinks them into
`~/Library/LaunchAgents/` and loads them with `launchctl bootstrap`, so edits
in this repo are live after a bootout/bootstrap cycle.

**Path caveat:** plists cannot shell-expand `~` or `$HOME`. The log paths below
are hardcoded to `/Users/meirpro`. Rewrite them for another home directory:
`sed -i '' "s|/Users/meirpro|$HOME|g" *.plist`.

## Agents

### `pro.meir.displaylink.plist`

Starts DisplayLink Manager at login under launchd instead of via its own login
item, so it restarts on crash and logs to a known path.

- **Program:** `/Applications/DisplayLink Manager.app/Contents/MacOS/DisplayLinkUserAgent`
- **Triggers:** `RunAtLoad` + `KeepAlive`
- **Session:** `Aqua` only (not the login window)
- **Logs:** `~/Library/Logs/pro.meir.displaylink.{out,err}.log`
- **Health check:** [`verify-displaylink.sh`](#verify)

**This agent is a stopgap. See [Remove this once the dock is
replaced](#remove-this-once-the-dock-is-replaced) — the underlying need for
DisplayLink went away with the M5 Pro.**

#### Why it exists

The Anker Prime DL7400 dock drives all three external displays through
DisplayLink. Its upstream is a 10Gb/s USB-C *data* port — not Thunderbolt, not
DP Alt Mode — so the 2×HDMI + 1×DP on its back are DisplayLink outputs, not GPU
outputs. Every pixel is screen-captured, compressed over USB, and decompressed
by the dock.

That means `DisplayLink Manager` must be running whenever the dock is in use,
and macOS shows the purple screen-capture indicator the entire time. Which is
accurate: the screen genuinely is being captured.

#### Required companion step (not scriptable)

DisplayLink registers its own login item that starts the `.app` through
LaunchServices. If it stays enabled you get two instances.

Turn it off in **System Settings → General → Login Items & Extensions → Allow
in the Background → DisplayLink Manager**. There is no supported CLI for
toggling an `SMAppService` registration.

DisplayLink updates re-enable it. Re-check after any DisplayLink update —
`verify-displaylink.sh` catches it by counting processes.

#### Related items left alone deliberately

- `/Library/LaunchAgents/com.displaylink.loginscreen.plist` —
  `LimitLoadToSessionType: LoginWindow`, so it only runs at the login window.
- `com.displaylink.CrashRestartHelper` — embedded agent inside the app bundle.
  It sees `DisplayLinkUserAgent` already running and stays idle. No conflict
  observed.

## Stopping DisplayLink completely

`killall` alone will never work, and neither will Quit from the menu bar.
**Four** separate things restart it, so a partial teardown looks like the app
refusing to die — you kill it and a new PID appears instantly.

| Component | Restarted by | How to stop it |
|---|---|---|
| `DisplayLinkUserAgent` | `pro.meir.displaylink` (`KeepAlive`) | bootout the agent *first* |
| `CrashRestartHelper` | the main agent | `killall` |
| `DisplayLinkXpcService` | **`com.displaylink.XpcService`** | `launchctl bootout` |
| everything, at next login | DisplayLink's login item | System Settings (see above) |

The XPC service is the one that traps people. It's registered as a LaunchAgent
*inside the app bundle* at
`/Applications/DisplayLink Manager.app/Contents/Library/LaunchAgents/`, so
launchd owns it (`ppid 1`) and respawns it immediately on kill. It has to be
booted out by label, not killed.

```bash
# Stop everything, in this order
launchctl bootout "gui/$UID/pro.meir.displaylink"
killall CrashRestartHelper DisplayLinkUserAgent 2>/dev/null
launchctl bootout "gui/$UID/com.displaylink.XpcService"

# Confirm
pgrep -lf -i displaylink || echo "none"
```

External displays go black immediately. Expected, and reversible.

```bash
# Start it again — XpcService and CrashRestartHelper re-register themselves
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/pro.meir.displaylink.plist"
```

**The bootout is not permanent.** DisplayLink's own login item restarts
everything at next login. To keep it off across reboots, disable that login
item — the same step needed to avoid the two-instance problem above.

## Hiding the purple indicator: does not work on macOS 26

Recorded so nobody burns another afternoon on it. **Tested and failed on macOS
26.6 (Tahoe, build 25G72), 2026-07-30.**

The [widely-circulated
workaround](https://niclake.me/mac-displaylink/) launches
`DisplayLinkUserAgent` directly instead of letting LaunchServices boot the
`.app`, on the theory that Control Center can't resolve a bundle identity for
the process and therefore draws no menu bar entry. It worked on Sequoia. It
does not work now.

macOS 26 resolves capture to the **responsible process** — the ancestor GUI app
that spawned the tree — and falls back to the binary's own code signature when
there isn't one. There is no launch path that yields *no* identity:

| Launch method | Attributed to | Result |
|---|---|---|
| LaunchServices (`open`, login item) | DisplayLink's signature | icon shown |
| launchd agent (ppid 1) | DisplayLink's signature | icon shown |
| `screen` from Terminal/WezTerm | **the terminal's** signature | icon shown, + prompts to grant *the terminal* Screen Recording |

Both were verified directly, with the dock attached and displays live.

**Do not grant a terminal emulator Screen Recording** to make the third row
"work." That would let every script, `npm postinstall`, and shell one-liner you
ever run capture the screen under the terminal's grant, with the indicator
naming only "Terminal". Strictly worse than the icon.

Supporting evidence: an [Apple developer forum
thread](https://developer.apple.com/forums/thread/807323) reports that macOS
26.1 changed how background Unix executables register for Screen Recording.
`RecordingIndicatorUtility` lists no Tahoe support and requires disabling SIP.
`YellowDot` only makes the dot blend in — and needs Screen Recording itself.

### What the indicator actually guarantees

Two independent layers, and the trick only ever defeated one:

1. **TCC permission (the gate)** — nothing captures the screen without an
   explicit grant under Privacy & Security → Screen Recording. Never bypassed
   by any of this.
2. **The menu bar indicator (the reminder)** — signals capture is happening
   right now.

Suppression, when it worked, was **per process** — other apps still showed the
icon. What it cost was the indicator's real purpose: catching an
already-authorized app recording when you don't expect it. Treat the icon as a
signal, not a guarantee; the Screen Recording list in System Settings is what
actually enumerates what *can* watch you.

## Remove this once the dock is replaced

**The M5 Pro (`Mac17,9`) drives 3 external displays natively over a single
Thunderbolt port.** M4 Pro/Max capped at 2 per port, which is the only reason
DisplayLink was ever needed here. Confirmed by [Apple's own
documentation](https://support.apple.com/en-us/101571).

Replacing the DL7400 with a Thunderbolt 5 dock eliminates DisplayLink entirely
— and with it the purple indicator, the driver, the DRM black screens on
Netflix/Prime/Disney+, the compression latency, and the CPU overhead.

### Status (2026-07-30)

**Undecided, leaning Kensington SD5000T5 EQ.** Emailed Plugable to ask whether
the TBT-UDH2 drives three displays on `Mac17,9` / M5 Pro — it's the only TB5
dock with dual built-in HDMI 2.1, which would mean one adapter instead of
three, at the lowest price of any option. Plugable's own KB still only
discusses M4 and calls TB5 triple-display "optional", so it needs confirming
before buying. **If they confirm → TBT-UDH2. If not → Kensington.**

Staying on the DL7400 until then. Purple indicator stays; it's accurate.

### Dock comparison

Almost no TB5 dock has HDMI — Apple caps dock HDMI at 4K/75Hz, so CalDigit and
others dropped it in favour of Thunderbolt ports. USB-C→HDMI adapters are
needed and live on the dock permanently (a one-time setup, not a daily cable).

| Dock | Price | HDMI | DP | Downstream TB5 | Adapters | USB-C power |
|---|---|---|---|---|---|---|
| **Anker DL7400** (current) | $270 | **2** | **1** | none | **0** | **100W** |
| Kensington SD5000T5 EQ | $299–380 | 0 | 0 | 3 | 3 | 15W |
| CalDigit TS5 | $399 | 0 | 0 | 3 | 3 | 15–20W |
| CalDigit TS5 Plus | $499 | 0 | 1 | 2 | 2 | 36W |
| Sonnet Echo 21 SuperDock | $499 | 1 | 1 | 3 | 1–2 | 15W |
| Plugable TBT-UDH2 *(unconfirmed)* | $279–349 | **2** | 0 | 3 | 1 | ? |

Kensington and both CalDigits are vendor-confirmed for M5 Pro triple display.
Ethernet: 2.5Gb on Kensington/TS5, 10Gb on TS5 Plus/Sonnet. All charge the host
at 140W.

**The DL7400 is not strictly worse.** It wins on native video ports and on
downstream charging — 100W vs 15W means it can fast-charge a phone or iPad,
which none of the replacements can. The swap buys correctness (no capture, no
driver, no DRM black screens on Netflix/Prime/Disney+, no compression latency,
no CPU overhead, 80–120Gb/s upstream that can host Thunderbolt SSDs), not more
ports. Skip the TS5 Plus unless the 36W downstream matters — its DP 2.1 only
pays off above 4K/144Hz, and these monitors are 1080p.

### Sources

- [Apple — how many displays connect to MacBook Pro](https://support.apple.com/en-us/101571)
- [Macworld — M5 Pro/Max enable 3–4 displays over one cable](https://www.macworld.com/article/3088215/m5-pro-max-macbooks-finally-break-apples-multi-monitor-shackles.html)
- [Kensington — M5 Pro triple displays over TB5](https://www.kensington.com/news/docking-connectivity-blog/macbook-pro-m5-pro-and-m5-max-unlock-triple-displays-with-thunderbolt-5-docking-stations/)
- [CalDigit TS5](https://www.caldigit.com/thunderbolt-5-dock-ts5/) · [TS5 Plus](https://www.caldigit.com/thunderbolt-5-dock-ts5-plus/)
- [Macworld — Sonnet Echo 21 review](https://www.macworld.com/article/3145505/sonnet-echo-21-thunderbolt-5-superdock-review.html)
- [Anker DL7400 product page](https://www.anker.com/products/a83b3-anker-prime-charging-docking-station-14-in-1-triple-display-140w)
- [Nic Lake — the indicator workaround that no longer works](https://niclake.me/mac-displaylink/)
- [Apple Developer Forums — Tahoe 26.1 background executable Screen Recording registration](https://developer.apple.com/forums/thread/807323)

**Teardown when the new dock arrives:**

```bash
launchctl bootout "gui/$UID" "$HOME/Library/LaunchAgents/pro.meir.displaylink.plist"
rm "$HOME/Library/LaunchAgents/pro.meir.displaylink.plist"
rm ~/Library/Logs/pro.meir.displaylink.*.log
# then uninstall DisplayLink Manager, and delete this agent + verify script
```

Also re-enable DisplayLink's login item first if you keep the app for any
reason.

## Install

```bash
# 1. Symlink the plist (edits in the repo stay live)
ln -sf "$PWD/macos/launchd/pro.meir.displaylink.plist" \
       "$HOME/Library/LaunchAgents/pro.meir.displaylink.plist"

# 2. launchd does not create the log directory
mkdir -p "$HOME/Library/Logs"

# 3. Kill the bundle-launched instance so launchd owns the process
killall DisplayLinkUserAgent

# 4. Load into the GUI session (RunAtLoad starts it immediately)
launchctl bootstrap "gui/$UID" \
  "$HOME/Library/LaunchAgents/pro.meir.displaylink.plist"
```

Then do the [login-item step](#required-companion-step-not-scriptable).

## Verify

```bash
./macos/launchd/verify-displaylink.sh
```

Checks registration, load state, restart/flapping history, whether it came up
at boot, process topology (exactly one, owned by launchd), whether the XPC
service is alive, how many displays are actually being driven, and the tail of
the error log. Exits non-zero on failure; WARN alone still exits 0.

The Screen Recording check is **inferred, not read** — `TCC.db` needs Full Disk
Access. DisplayLink running with the dock attached and zero external displays
is the signature of a revoked grant.

## Uninstall

```bash
launchctl bootout "gui/$UID" \
  "$HOME/Library/LaunchAgents/pro.meir.displaylink.plist"
rm "$HOME/Library/LaunchAgents/pro.meir.displaylink.plist"
open "/Applications/DisplayLink Manager.app"
```

Then re-enable the login item in System Settings to restore normal startup.

## Editing a plist

```bash
launchctl bootout   "gui/$UID" "$HOME/Library/LaunchAgents/<label>.plist"
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/<label>.plist"
```

The LaunchAgents entry is a symlink back to this repo, so the edit is live on
save; the cycle just forces launchd to re-read the file.

## Troubleshooting

- **Two `DisplayLinkUserAgent` processes** — DisplayLink's login item is still
  enabled. Disable it (see above) and `killall DisplayLinkUserAgent`.
- **Displays stopped working** — check the `.err.log`. If macOS revoked the
  Screen Recording grant, re-grant it and
  `launchctl kickstart -k "gui/$UID/pro.meir.displaylink"`.
- **"Could not find specified service"** — the agent isn't loaded. Run
  `bootstrap` from [Install](#install).
- **Brightness/Contrast errors in the log** — `CommandStatusCodeV1(rawValue: 7)`
  is DisplayLink failing DDC control on monitors that don't support it.
  Cosmetic; the displays work.

## Disabled autostart items

Not agents this repo installs — third-party autostarts turned **off** on this
machine, recorded so a reinstall doesn't silently bring them back.

### Logitech G HUB

G HUB ships two autostarts and re-enables both on every reinstall or update.
Neither is needed unless actively remapping a Logitech device.

| Item | Location | Why it's off |
|---|---|---|
| `com.logi.ghub` | `/Library/LaunchAgents/` | `RunAtLoad`, Aqua session — tray agent running for no reason |
| `com.logi.ghub.updater` | `/Library/LaunchDaemons/` | `KeepAlive` **as root**, permanently resident updater |

```bash
# User agent (no sudo)
launchctl bootout  "gui/$UID/com.logi.ghub"
launchctl disable  "gui/$UID/com.logi.ghub"

# Root daemon (sudo)
sudo launchctl bootout system/com.logi.ghub.updater
sudo launchctl disable system/com.logi.ghub.updater
sudo pkill -f lghub_updater
```

`disable` persists across reboots, so a reinstall that re-drops the plists still
won't load them — but verify after a G HUB update:

```bash
launchctl print-disabled "gui/$UID" | grep -i logi
sudo launchctl print-disabled system | grep -i logi
```

To restore, swap `disable` for `enable` and `bootout` for `bootstrap`.
