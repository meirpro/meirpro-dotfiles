# macOS LaunchAgents

System-level launchd items that aren't tied to Claude Code. (Claude Code's own
agents live in [`claude/launchd/`](../../claude/launchd/README.md).)

Plists here are templates; installation symlinks them into
`~/Library/LaunchAgents/` and loads them with `launchctl bootstrap`, so edits
in this repo are live after a bootout/bootstrap cycle.

**Path caveat:** plists cannot shell-expand `~` or `$HOME`. Log paths are
hardcoded to `/Users/meirpro`. Rewrite them for another home directory:
`sed -i '' "s|/Users/meirpro|$HOME|g" *.plist`.

## Agents

**None currently installed.**

`pro.meir.displaylink` lived here until 2026-08-14. It supervised DisplayLink
Manager, which the old Anker DL7400 dock required to drive external displays.
Both the dock and DisplayLink are gone — the M5 Pro drives three displays
natively through a Thunderbolt 5 dock. See [`macos/displays.md`](../displays.md)
for that story, including why the purple screen-capture indicator could not be
hidden on macOS 26. The agent and its `verify-displaylink.sh` health check are
in git history if ever needed.

## Install (template)

```bash
# 1. Symlink the plist (edits in the repo stay live)
ln -sf "$PWD/macos/launchd/<label>.plist" \
       "$HOME/Library/LaunchAgents/<label>.plist"

# 2. launchd does not create the log directory
mkdir -p "$HOME/Library/Logs"

# 3. Load into the GUI session (RunAtLoad starts it immediately)
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/<label>.plist"
```

Reload after editing a plist — the symlink makes the edit live on save, but
launchd caches the parsed file:

```bash
launchctl bootout   "gui/$UID" "$HOME/Library/LaunchAgents/<label>.plist"
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/<label>.plist"
```

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
# User agent (no sudo) — done 2026-07-30
launchctl bootout  "gui/$UID/com.logi.ghub"
launchctl disable  "gui/$UID/com.logi.ghub"

# Root daemon (sudo) — STILL OUTSTANDING
sudo launchctl bootout system/com.logi.ghub.updater
sudo launchctl disable system/com.logi.ghub.updater
sudo pkill -f lghub_updater
```

The user agent is booted out and disabled. **The root daemon is not** — it
needs an interactive sudo password, which an agent session can't supply.

`disable` persists across reboots, so a reinstall that re-drops the plists
still won't load them — but verify after a G HUB update:

```bash
launchctl print-disabled "gui/$UID" | grep -i logi
sudo launchctl print-disabled system | grep -i logi
```

To restore, swap `disable` for `enable` and `bootout` for `bootstrap`.

## Leftovers from uninstalled software

`/Library/LaunchAgents/com.displaylink.loginscreen.plist` survived the
DisplayLink uninstall. It's `LimitLoadToSessionType: LoginWindow`, so it only
runs at the login window and does nothing now that the binary it launches is
gone — harmless, but tidy it up with:

```bash
sudo rm /Library/LaunchAgents/com.displaylink.loginscreen.plist
```

Background Task Management also still holds ~13 stale DisplayLink references
(`sfltool dumpbtm | grep -i displaylink`). These are orphaned registration
records; macOS clears them on its own. Don't run `sfltool resetbtm` to force
it — that wipes *every* login item on the machine.
