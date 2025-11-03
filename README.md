# Claude Code Configuration

My personal Claude Code configuration including hooks, commands, agents, and custom status line.

## 📁 Repository Structure

```
claude-code-config/
├── agents/              # Custom Claude Code agents
│   ├── code-documentation-enhancer.md
│   ├── code-metrics-analyzer.md
│   ├── code-quality-auditor.md
│   ├── code-refactoring-specialist.md
│   ├── code-style-enforcer.md
│   ├── documentation-generator.md
│   ├── error-handling-specialist.md
│   ├── image-cataloger.md
│   ├── jewish-figure-researcher.md
│   ├── performance-optimizer.md
│   └── unit-test-generator.md
├── audio/               # Notification sounds
│   ├── awaiting_instructions.mp3
│   ├── build_complete.mp3
│   ├── error_fixed.mp3
│   ├── ready.mp3
│   └── task_complete.mp3
├── commands/            # Slash commands
│   ├── commit-emoji.md
│   └── commit.md
├── hooks/               # Event hooks
│   ├── debug_hook.py
│   ├── format_code.sh
│   ├── log_bash.sh
│   ├── log_pre_tool_use.py
│   ├── macos_notification.py
│   ├── on_notification.sh
│   ├── play_audio.py
│   ├── ts_check.py
│   ├── ts_check.sh
│   ├── ts_lint.py
│   └── ts_lint.sh
├── CLAUDE.md            # Global instructions for Claude
├── claude.json          # MCP server configuration
├── settings.json        # Main Claude Code settings
├── statusline-command.sh # Custom status line script
├── install.sh           # Installation script
└── README.md            # This file
```

## ✨ Features

### Custom Status Line
Displays comprehensive session information:
- 📁 Current directory and git branch
- 🔑 Session ID (8-char short)
- 💰 Session cost in USD
- 📝 Lines added/removed with colors
- ⏱️ Session duration and API time

Example: `SweetRoboTeam on main (Sonnet 4.5) 🔑 40d7da24 💰$0.59 📝 +107/-26 ⏱️ 10h29m (API: 15m22s)`

### Hooks
- **PostToolUse**: Automatic TypeScript checking and linting after file edits
- **PreToolUse**: Bash command logging
- **Notification**: Audio notifications for task completion
- **Code Formatting**: Automatic code formatting on file changes

### Slash Commands
- `/commit-emoji` - Creates well-formatted commits with conventional commit messages and emoji
- `/commit` - Standard commit with conventional format

### Agents
Specialized agents for code quality, documentation, refactoring, performance optimization, and more.

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
git clone https://github.com/YOUR_USERNAME/claude-code-config.git

# Run the install script
cd claude-code-config
chmod +x install.sh
./install.sh
```

The install script will:
1. Backup your existing `~/.claude` configuration
2. Create symlinks from `~/.claude` to this repository
3. Preserve local-only files (settings.local.json, history, etc.)

### Manual Install

If you prefer manual installation:

```bash
# Backup existing config
cp -r ~/.claude ~/.claude.backup

# Create symlinks for each directory/file
ln -sf ~/Documents/GitHub/claude-code-config/hooks ~/.claude/hooks
ln -sf ~/Documents/GitHub/claude-code-config/commands ~/.claude/commands
ln -sf ~/Documents/GitHub/claude-code-config/agents ~/.claude/agents
ln -sf ~/Documents/GitHub/claude-code-config/audio ~/.claude/audio
ln -sf ~/Documents/GitHub/claude-code-config/settings.json ~/.claude/settings.json
ln -sf ~/Documents/GitHub/claude-code-config/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/Documents/GitHub/claude-code-config/statusline-command.sh ~/.claude/statusline-command.sh
ln -sf ~/Documents/GitHub/claude-code-config/claude.json ~/.claude/claude.json
```

## 🔧 Configuration

### Status Line
The status line script (`statusline-command.sh`) is configured in `settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

### Hooks
Hooks are configured to run on specific events:
- **PostToolUse** (Write|Edit|MultiEdit): TypeScript check, lint, format
- **PreToolUse** (Bash): Command logging
- **Notification**: Audio playback

### MCP Servers
MCP servers are configured in `claude.json`. Currently includes:
- Playwright (browser automation)
- Neon (database management)
- Context7 (documentation lookup)

## 📝 Customization

### Adding Your Own Hooks
1. Create a new script in `hooks/`
2. Make it executable: `chmod +x hooks/your-hook.sh`
3. Add to `settings.json` under the appropriate hook event

### Adding Custom Commands
1. Create a markdown file in `commands/`
2. Write your command prompt in the markdown
3. Use with `/your-command-name`

### Adding Custom Agents
1. Create a markdown file in `agents/`
2. Define the agent's capabilities and instructions
3. Claude Code will automatically discover it

## 🔒 Security Notes

- `settings.local.json` is gitignored for local-only overrides
- Sensitive directories (`.env*`, `secrets/`, etc.) are excluded
- API keys and tokens should never be committed
- The `.gitignore` file protects common sensitive patterns

## 🛠️ Dependencies

The hooks and status line require:
- **jq**: JSON parsing (`brew install jq`)
- **bc**: Mathematical calculations (pre-installed on macOS)
- **git**: Version control (pre-installed on macOS)
- **Python 3**: For Python-based hooks (pre-installed on macOS)

## 📚 Learn More

- [Claude Code Documentation](https://docs.claude.com/en/docs/claude-code)
- [Custom Status Line Guide](https://docs.claude.com/en/docs/claude-code/statusline.md)
- [Hooks Documentation](https://docs.claude.com/en/docs/claude-code/hooks.md)
- [MCP Servers](https://docs.claude.com/en/docs/claude-code/mcp-servers.md)

## 📄 License

MIT License - Feel free to use and modify for your own needs!

## 🤝 Contributing

This is a personal configuration repository, but feel free to fork and adapt for your own use!
