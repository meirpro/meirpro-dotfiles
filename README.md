# Shell & Claude Code Configuration

My personal development environment configuration including Claude Code customizations and shell enhancements.

## Quickstart

```bash
git clone https://github.com/meirpro/meirpro-dotfiles ~/dotfiles && cd ~/dotfiles && ./install.sh
```

macOS/Linux, interactive. See [Installation](#-installation) below for what it touches and how to opt out of pieces.

## 📁 Repository Structure

```
meirpro-dotfiles/
├── claude/              # Claude Code specific config
│   ├── agents/          # Custom Claude Code agents (12 specialized agents)
│   ├── audio/           # Notification sounds
│   ├── commands/        # Slash commands
│   ├── hooks/           # Event hooks (TypeScript checks, linting, etc.)
│   ├── claude.json      # MCP server configuration
│   ├── CLAUDE.md        # Global instructions for Claude
│   ├── settings.json    # Main Claude Code settings
│   └── statusline-command.sh  # Custom status line script
├── shell/               # Shell configuration (universal configs + templates)
│   ├── .aliases         # Command aliases (extensive collection)
│   ├── .functions       # Shell functions (includes smart cld for Claude Code)
│   ├── .exports         # Environment variables and settings
│   ├── .bash_prompt     # Solarized Dark prompt with git status
│   ├── .zshrc           # Zsh runtime config
│   ├── .zprofile        # Zsh profile config
│   ├── .bash_profile.template  # Template (customize for your machine)
│   └── .bashrc.template        # Template (customize for your machine)
├── git/                 # Git configurations
│   ├── .gitconfig.template     # Git aliases and settings (customize user info)
│   ├── .gitignore_global       # Global gitignore patterns
│   └── .gitattributes          # Git attributes
├── editors/             # Editor configurations
│   ├── .vimrc           # Vim config (Solarized Dark theme)
│   ├── .gvimrc          # Gvim config
│   ├── .inputrc         # Readline config (better tab completion)
│   └── .editorconfig    # Cross-editor settings
├── tools/               # Tool configurations
│   ├── .tmux.conf       # Tmux config (Ctrl+A prefix, vim keys)
│   ├── .screenrc        # GNU Screen config
│   ├── .wgetrc          # Wget defaults
│   └── .curlrc          # Curl defaults
├── macos/               # macOS system config
│   ├── defaults.sh      # `defaults write` settings (run manually)
│   ├── inventory.sh     # Machine inventory snapshot
│   ├── bin/             # Small utilities (saytime — speak the time in am/pm)
│   ├── cron/            # User crontab, version controlled
│   ├── displays.md      # External display / dock setup and history
│   └── launchd/         # LaunchAgents (currently none; disabled autostarts)
├── install.sh           # Installation script
├── README.md            # This file
└── SETUP.md             # Machine-specific setup guide
```

## ✨ Features

### Shell Enhancements

#### Smart `cld` Function
Enhanced Claude Code launcher with intelligent session resume:

```bash
# Normal usage (same as 'claude' command)
cld "help me with this code"

# Resume with partial session ID (auto-completes to full UUID)
cld -r 5c56e09f

# Interactive session picker
cld -r

# Resume and add new query
cld -r 5c56e09f "continue working on that feature"

# Continue most recent session
cld --continue
```

**How it works:**
- Searches your current project's session directory for matching UUIDs
- Auto-completes if only one match is found
- Shows multiple matches if the partial ID is ambiguous
- Skips agent session files for cleaner results

#### Shell Dotfiles (Based on Mathias Bynens' dotfiles)
Comprehensive collection of universal shell configurations:

**From `.aliases` (6.5KB of shortcuts):**
- Navigation: `..`, `...`, `....`, `.....`
- Directory shortcuts: `d`, `dl`, `dt`, `p`, `g`
- Colorized `ls` variants with custom colors
- macOS utilities: flush DNS, cleanup LaunchServices
- Network tools: `ip`, `localip`, `ifactive`
- HTTP shortcuts: `GET`, `POST`, `PUT`, `DELETE` as curl aliases
- System utilities: `update`, `emptytrash`, `show`/`hide` hidden files

**From `.functions` (6.6KB of utilities):**
- `mkd` - Create directory and cd into it
- `cdf` - cd to Finder's current location
- `targz` - Smart tar.gz with compression optimization
- `diff` - Git-colored diff
- `server` - Python HTTP server
- `getcertnames` - SSL certificate inspection
- `tre` - Enhanced tree with colors
- `cld` - Smart Claude Code launcher with resume support
- Plus many more utilities for development...

**From `.exports`:**
- Editor: vim
- Node.js REPL: 32,768 entry history
- Bash history: 32,768 entries (vs default 500)
- Locale: en_US.UTF-8
- Python UTF-8 encoding
- GPG TTY configuration

**From `.bash_prompt` (Solarized Dark):**
- Beautiful prompt with git branch/status
- SSH detection (red hostname)
- Root user detection (red username)
- Git indicators: `+` staged, `!` unstaged, `?` untracked, `$` stashed

### macOS System Defaults

`macos/defaults.sh` captures the settings that aren't in System Settings but change how the machine feels daily — the ones that are easy to forget you ever set, and painful to rediscover on a new machine.

```bash
./macos/defaults.sh            # apply
./macos/defaults.sh --revert   # back to macOS stock
```

**Not run by `install.sh`** — it restarts Finder and Dock, and the menu bar changes need a full logout. Run it deliberately.

What it sets, and why each one earns its place:

- **Menu bar density** — `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` to 0 (stock 12/16). On a 14" screen the notch hides overflowing menu bar items; this roughly halves the footprint per item. Must be written with `-currentHost` or it silently does nothing.
- **Time-only clock** — no date, no day of week, 24-hour. `ShowDate` is tri-state (`2` = never); at the default `0` the date reappears whenever macOS decides there's room.
- **Key repeat** — `KeyRepeat 2` / `InitialKeyRepeat 15` (stock 6/25), and `ApplePressAndHoldEnabled` off so holding a key repeats instead of showing the accent picker.
- **Smart substitutions off** — smart quotes and dashes silently corrupt code and shell commands outside an editor.
- **Instant Dock** — `autohide-delay 0` + faster slide. Matters because the Dock is set to auto-hide, so stock costs a half-second on every reveal.
- **Dock density** — `minimize-to-application` so minimised windows fold into the app icon instead of adding tiles, plus translucent icons for hidden apps.
- **Compact sidebars** — `NSTableViewDefaultSizeMode 1`, same density goal as the menu bar.
- **Finder** — path bar, status bar, expanded save/print dialogs, no `.DS_Store` on network shares or USB drives.
- **Calculate all sizes** — list view shows real folder sizes instead of `--`, so the Size column is useful for the case you actually want it (finding what ate the disk). Buried inside a nested dict, so it needs `PlistBuddy` rather than `defaults write`, and `cfprefsd` has to be flushed first or the daemon rewrites the edit. Costs a few seconds of tree-walking in huge folders; noticeably slow over network shares.
- **Screenshots** — into `~/Pictures/Screenshots`, window drop shadow off.
- **Screenshot shortcuts released** — disables the built-in Cmd-Shift-3/4/5 so **CleanShot X** can bind them. Without this CleanShot silently loses to macOS, which is near-impossible to diagnose on a fresh machine.
- **Terminals** — Terminal.app secure keyboard entry + no line marks; iTerm2 without the quit prompt. Both are set because the choice of terminal is still open.
- **App annoyances** — Photos.app no longer launches when a phone is plugged in, Chrome two-finger swipe-back off (*on trial* — the script documents the one-line undo), TextEdit opens plain-text UTF-8.

The script only manages keys it sets itself. Anything changed through System Settings (Dock size, Finder view style, tap-to-click, hot corners) is left untouched by both apply and `--revert`. Settings deliberately *not* changed — and the reasoning — are documented in a comment block at the bottom of the script.

### macOS LaunchAgents

`macos/launchd/` — startup agents that aren't Claude Code related, plus a record of third-party autostarts deliberately turned off. Full detail in [`macos/launchd/README.md`](macos/launchd/README.md).

- **No agents currently installed.** `pro.meir.displaylink` lived here until the DisplayLink dock was replaced — see [`macos/displays.md`](macos/displays.md).
- **Logitech G HUB, disabled** — `com.logi.ghub` (tray agent) and `com.logi.ghub.updater` (a `KeepAlive` root daemon). Both booted out and `launchctl disable`d so a G HUB reinstall can't quietly reload them.

### External displays

`macos/displays.md` — how this machine drives three external monitors, and why the previous arrangement was replaced.

- **M5 Pro → Kensington SD5000T5 EQ → 3 displays over one Thunderbolt 5 cable, natively.** No DisplayLink, no driver, no purple screen-capture indicator. The M5 Pro drives 3 external displays per Thunderbolt port; M4 Pro/Max capped at 2, which is the only reason DisplayLink was ever needed.
- **The port budget** — on a Thunderbolt dock a downstream port is *either* a display *or* a device. Three monitors consume all three, leaving zero USB-C and making the dock's 60W port unusable. Records the USB-C hub workaround and the MST trap (macOS doesn't support it, so dual-HDMI hubs mirror rather than extend).
- **Hiding the purple screen-capture indicator: does not work on macOS 26.** Kept as a tested dead end — macOS 26 resolves capture to the responsible process and falls back to the binary's code signature, so no launch path escapes attribution. Includes why you should never grant a terminal emulator Screen Recording to work around it.

### cron

`macos/cron/` — the user crontab, version controlled. Almost everything belongs in `macos/launchd/` instead; cron is used for one job where a plist would be more ceremony than the job is worth. Full detail in [`macos/cron/README.md`](macos/cron/README.md).

- **`saytime`, every 15 minutes** — speaks the time as "It's 2:15 PM". macOS has this built in (Menu bar → Clock Options → Announce the time) with the same intervals and voice controls, but it **never says AM or PM** — its string is always "It's two o'clock", and the AM/PM toggle in that pane only affects the menu bar *display*. The menu bar here is 24-hour, so the built-in announcement is ambiguous. Turn the built-in off if it's on, or both fire.
- **`%` is a cron metacharacter** — the obvious one-liner `say "It's $(date '+%-I:%M %p')"` is broken in a crontab. cron turns every unescaped `%` into a newline and pipes the remainder in as stdin, so the command dies on an unterminated quote, silently. That's why the `date` call lives in [`macos/bin/saytime`](macos/bin/saytime) and the crontab line contains no `%` at all.

### Claude Code Customizations

#### Custom Status Line
Displays comprehensive session information:
- 📁 Current directory and git branch
- 🔑 Session ID (8-char short)
- 💰 Session cost in USD
- 📝 Lines added/removed with colors
- ⏱️ Session duration and API time

Example: `SweetRoboTeam on main (Sonnet 4.5) 🔑 40d7da24 💰$0.59 📝 +107/-26 ⏱️ 10h29m (API: 15m22s)`

#### Hooks
- **PostToolUse**: Automatic TypeScript checking and linting after file edits
- **PreToolUse**: Bash command logging
- **Notification**: Audio notifications for task completion
- **Code Formatting**: Automatic code formatting on file changes

#### Slash Commands
- `/commit-emoji` - Creates well-formatted commits with conventional commit messages and emoji
- `/commit` - Standard commit with conventional format

#### Agents
12 specialized agents for:
- Code quality auditing
- Documentation generation
- Refactoring assistance
- Performance optimization
- Error handling improvements
- Unit test generation
- Code metrics analysis
- And more...

#### MCP Servers
Pre-configured MCP servers:
- **Playwright** - Browser automation
- **Neon** - Database management
- **Context7** - Documentation lookup

## 🎨 Attribution

The shell dotfiles in this repository are based on and inspired by:
- **[Mathias Bynens' dotfiles](https://github.com/mathiasbynens/dotfiles)** - Primary source for shell configurations, aliases, and functions
- **[Nicolas Gallagher's dotfiles](https://github.com/necolas/dotfiles)** - Bash prompt with git integration
- **[Paul Irish's dotfiles](https://github.com/paulirish/dotfiles)** - Additional shell wisdom

Custom additions include Claude Code integration (`cld` function) and personal preferences.

## 🚀 Installation

### Prerequisites
- Claude Code installed
- `jq` for JSON parsing: `brew install jq`
- `bc` for calculations (usually pre-installed on macOS)
- Python 3 (for Python hooks)

### Quick Install

```bash
# Clone the repository
cd ~/git
git clone https://github.com/YOUR_USERNAME/meirpro-dotfiles.git
cd meirpro-dotfiles

# Run the install script
chmod +x install.sh
./install.sh
```

The install script will prompt you to choose:
1. **Claude Code configuration only** - Just Claude Code enhancements
2. **Shell configuration only** - Aliases, functions, exports, prompts, and tool configs
3. **Both (recommended)** - Complete development environment

The installer will:
- Backup existing configurations
- Create symlinks from `~/.claude` and home directory to this repository
- Copy template files (`.bash_profile`, `.bashrc`, `.gitconfig`) for customization
- Update your shell RC file to source dotfiles
- Make scripts executable
- Check for required dependencies

### What Gets Installed

**Claude Code (Option 1 or 3):**
- Symlinks from `~/.claude/` to `claude/` directory
- Preserves local-only files (history, todos, etc.)

**Shell Config (Option 2 or 3):**
- Symlinks universal dotfiles:
  - `~/.aliases` → `shell/.aliases`
  - `~/.functions` → `shell/.functions`
  - `~/.exports` → `shell/.exports`
  - `~/.bash_prompt` → `shell/.bash_prompt`
  - `~/.zshrc` → `shell/.zshrc`
  - `~/.zprofile` → `shell/.zprofile`
  - `~/.vimrc` → `editors/.vimrc`
  - `~/.inputrc` → `editors/.inputrc`
  - `~/.tmux.conf` → `tools/.tmux.conf`
  - And more...
- Copies template files for customization:
  - `~/.bash_profile` (from `.bash_profile.template`)
  - `~/.bashrc` (from `.bashrc.template`)
  - `~/.gitconfig` (from `.gitconfig.template`)
- Updates your shell RC file to source dotfiles

### Manual Install

If you prefer manual installation:

**For Claude Code:**
```bash
# Backup existing config
cp -r ~/.claude ~/.claude.backup

# Create symlinks
ln -sf ~/git/meirpro-dotfiles/claude/hooks ~/.claude/hooks
ln -sf ~/git/meirpro-dotfiles/claude/commands ~/.claude/commands
ln -sf ~/git/meirpro-dotfiles/claude/agents ~/.claude/agents
ln -sf ~/git/meirpro-dotfiles/claude/audio ~/.claude/audio
ln -sf ~/git/meirpro-dotfiles/claude/settings.json ~/.claude/settings.json
ln -sf ~/git/meirpro-dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/git/meirpro-dotfiles/claude/statusline-command.sh ~/.claude/statusline-command.sh
ln -sf ~/git/meirpro-dotfiles/claude/claude.json ~/.claude/claude.json
```

**For Shell Config:**
```bash
# Create symlinks
ln -sf ~/git/meirpro-dotfiles/shell/aliases.sh ~/.aliases
ln -sf ~/git/meirpro-dotfiles/shell/functions.sh ~/.functions

# Add to ~/.bash_profile or ~/.zshrc
echo '[ -r ~/.aliases ] && source ~/.aliases' >> ~/.bash_profile
echo '[ -r ~/.functions ] && source ~/.functions' >> ~/.bash_profile

# Reload shell
source ~/.bash_profile
```

## 🔧 Configuration

### Shell Functions

The `cld` function automatically finds sessions by partial ID. How it works:

1. Takes a partial session ID (e.g., `5c56e09f`)
2. Searches in `~/.claude/projects/<current-project>/`
3. Finds files matching `5c56e09f*.jsonl`
4. Auto-resumes if exactly one match is found
5. Shows matches if multiple sessions match
6. Falls back to Claude's native behavior if no matches

### Claude Code Status Line

The status line script (`statusline-command.sh`) is configured in `settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

### Customizing Hooks

Hooks are configured to run on specific events. Edit `claude/settings.json` to add or modify hooks:

```json
{
  "hooks": {
    "postToolUse": [
      {
        "tools": ["Write", "Edit", "MultiEdit"],
        "command": "bash ~/.claude/hooks/ts_check.sh"
      }
    ]
  }
}
```

## 📝 Customization

### Adding Your Own Shell Functions

Edit `shell/functions.sh` in the repo:

```bash
# Your custom function
function myfunction() {
    echo "Hello from my custom function!"
}
```

Changes are immediately available after sourcing: `source ~/.functions`

Since it's symlinked, your changes are automatically version controlled!

### Adding Your Own Aliases

Edit `shell/aliases.sh` in the repo:

```bash
alias myalias="echo 'My custom alias'"
```

### Adding Claude Code Hooks

1. Create a new script in `claude/hooks/`
2. Make it executable: `chmod +x claude/hooks/your-hook.sh`
3. Add to `claude/settings.json` under the appropriate hook event

### Adding Custom Slash Commands

1. Create a markdown file in `claude/commands/`
2. Write your command prompt in the markdown
3. Use with `/your-command-name`

### Adding Custom Agents

1. Create a markdown file in `claude/agents/`
2. Define the agent's capabilities and instructions
3. Claude Code will automatically discover it

## 🔒 Security Notes

- `settings.local.json` is gitignored for local-only overrides
- Sensitive directories (`.env*`, `secrets/`, etc.) are excluded
- API keys and tokens should never be committed
- The `.gitignore` file protects common sensitive patterns
- Shell config files are symlinked, so edits are version controlled

## 🛠️ Dependencies

**Required:**
- **jq**: JSON parsing (`brew install jq`)
- **bc**: Mathematical calculations (pre-installed on macOS)
- **git**: Version control (pre-installed on macOS)
- **Python 3**: For Python-based hooks (pre-installed on macOS)

The install script will check for these and warn if any are missing.

## 💡 Tips & Tricks

### Session Management with `cld`

```bash
# List recent sessions in current project
ls -lt ~/.claude/projects/-$(pwd | sed 's/\//-/g')/*.jsonl | head -5

# Resume most recent
cld --continue

# Resume with partial ID (just first 8 chars of UUID)
cld -r 5c56e09f
```

### Editing Config While Maintaining Version Control

Since files are symlinked, you can edit them in either location:

```bash
# Edit in home directory (changes reflected in repo)
vim ~/.functions

# Or edit in repo (changes reflected in home)
vim ~/git/meirpro-dotfiles/shell/functions.sh
```

Both edit the same file! Commit your changes from the repo directory.

### Local-Only Overrides

For settings you don't want to commit:

**Claude Code:**
```bash
# Create local settings file (gitignored)
vim ~/.claude/settings.local.json
```

**Shell:**
```bash
# Use ~/.extra for local shell config (if your bash_profile sources it)
vim ~/.extra
```

## 📚 Learn More

- [Claude Code Documentation](https://docs.claude.com/en/docs/claude-code)
- [Custom Status Line Guide](https://docs.claude.com/en/docs/claude-code/statusline.md)
- [Hooks Documentation](https://docs.claude.com/en/docs/claude-code/hooks.md)
- [MCP Servers](https://docs.claude.com/en/docs/claude-code/mcp-servers.md)

## 🎯 Project Philosophy

This repo aims to:
- **Keep configs in version control** - Never lose your perfect setup again
- **Make switching machines easy** - Clone and install on any new machine
- **Stay organized** - Separate Claude Code and shell configs logically
- **Remain flexible** - Easy to customize and extend

## 📄 License

MIT License - Feel free to use and modify for your own needs!

## 🤝 Contributing

This is a personal configuration repository, but feel free to:
- Fork and adapt for your own use
- Submit issues for bugs or suggestions
- Share your own customizations!

---

**Made with ❤️ by a developer who got tired of losing shell configurations**
