# Shell & Claude Code Configuration

My personal development environment configuration including Claude Code customizations and shell enhancements.

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
cd ~/Documents/GitHub
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
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/hooks ~/.claude/hooks
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/commands ~/.claude/commands
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/agents ~/.claude/agents
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/audio ~/.claude/audio
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/settings.json ~/.claude/settings.json
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/statusline-command.sh ~/.claude/statusline-command.sh
ln -sf ~/Documents/GitHub/meirpro-dotfiles/claude/claude.json ~/.claude/claude.json
```

**For Shell Config:**
```bash
# Create symlinks
ln -sf ~/Documents/GitHub/meirpro-dotfiles/shell/aliases.sh ~/.aliases
ln -sf ~/Documents/GitHub/meirpro-dotfiles/shell/functions.sh ~/.functions

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
vim ~/Documents/GitHub/meirpro-dotfiles/shell/functions.sh
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
