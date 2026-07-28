#!/usr/bin/env bash

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Shell & Claude Code Configuration Installer${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Get the directory where this script is located
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLAUDE_DIR="$HOME/.claude"

echo -e "${YELLOW}Repository:${NC} $REPO_DIR"
echo

# Function to create symlink with backup
create_symlink() {
    local source="$1"
    local target="$2"
    local name="$3"

    # If target exists and is not a symlink, back it up
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo -e "${YELLOW}  Backing up existing $name${NC}"
        mv "$target" "${target}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Remove existing symlink if it exists
    if [ -L "$target" ]; then
        rm "$target"
    fi

    # Create new symlink
    ln -sf "$source" "$target"
    echo -e "${GREEN}  ✓ Linked $name${NC}"
}

# Function to check if shell config is already sourced
check_shell_config() {
    local shell_rc="$1"
    local pattern="$2"

    if [ -f "$shell_rc" ] && grep -q "$pattern" "$shell_rc"; then
        return 0  # Already configured
    else
        return 1  # Not configured
    fi
}

# Ask what to install. Guard the prompt with `[ -t 0 ]`: `read` returns
# non-zero on EOF when stdin isn't a TTY (piped, CI, run from an agent),
# and `set -e` would then abort before the script does anything. Default
# to "3" (both) non-interactively, overridable with INSTALL_CHOICE=N.
# (Fix originally proposed in the stale fork PR #1; extracted here.)
echo -e "${BLUE}What would you like to install?${NC}"
echo "  1) Claude Code configuration only"
echo "  2) Shell configuration only (dotfiles, aliases, functions, git, vim, tools)"
echo "  3) Both (recommended)"
echo
if [ -z "${INSTALL_CHOICE:-}" ]; then
    if [ -t 0 ]; then
        read -p "Select option (1-3): " -n 1 -r
        echo
        INSTALL_CHOICE=$REPLY
    else
        INSTALL_CHOICE=3
        echo "  (non-interactive: defaulting to 3 — both)"
    fi
fi

# Validate choice
if [[ ! $INSTALL_CHOICE =~ ^[1-3]$ ]]; then
    echo -e "${RED}Invalid choice. Installation cancelled${NC}"
    exit 1
fi

echo

# ============================================================================
# CLAUDE CODE INSTALLATION
# ============================================================================
if [[ $INSTALL_CHOICE =~ ^[13]$ ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Installing Claude Code Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    # Check if Claude Code is installed
    if [ ! -d "$CLAUDE_DIR" ]; then
        echo -e "${RED}Error: ~/.claude directory not found${NC}"
        echo "Please install Claude Code first: https://claude.ai/code"
        exit 1
    fi

    echo -e "${YELLOW}Target:${NC} $CLAUDE_DIR"
    echo

    # Create backup
    backup_dir="$HOME/.claude.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Creating backup at:${NC} $backup_dir"
    cp -r "$CLAUDE_DIR" "$backup_dir"
    echo -e "${GREEN}✓ Backup created${NC}"
    echo

    # Ask about audio notifications (non-interactive → skip; see note above)
    echo -e "${BLUE}Install audio notifications?${NC} (plays sounds on task completion)"
    echo "  Requires: Python 3"
    echo "  Audio files: ~2MB"
    echo
    if [ -t 0 ]; then
        read -p "Install audio? (y/N): " -n 1 -r audio_choice
        echo
    else
        audio_choice="n"
        echo "  (non-interactive: skipping audio)"
    fi
    echo

    # Create symlinks for directories
    echo -e "${YELLOW}Creating symlinks for directories...${NC}"
    create_symlink "$REPO_DIR/claude/hooks" "$CLAUDE_DIR/hooks" "hooks/"
    create_symlink "$REPO_DIR/claude/commands" "$CLAUDE_DIR/commands" "commands/"
    if [ -d "$REPO_DIR/claude/agents" ]; then
        create_symlink "$REPO_DIR/claude/agents" "$CLAUDE_DIR/agents" "agents/"
    fi
    if [[ "$audio_choice" =~ ^[Yy]$ ]]; then
        create_symlink "$REPO_DIR/claude/audio" "$CLAUDE_DIR/audio" "audio/"
    else
        # Remove audio dir so play_audio.py becomes a no-op
        if [ -L "$CLAUDE_DIR/audio" ]; then rm "$CLAUDE_DIR/audio"; fi
        if [ -d "$CLAUDE_DIR/audio" ]; then rm -rf "$CLAUDE_DIR/audio"; fi
        echo -e "${YELLOW}  Skipped audio/ (notifications disabled)${NC}"
    fi
    echo

    # Create symlinks for files
    echo -e "${YELLOW}Creating symlinks for files...${NC}"
    create_symlink "$REPO_DIR/claude/settings.json" "$CLAUDE_DIR/settings.json" "settings.json"
    create_symlink "$REPO_DIR/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
    create_symlink "$REPO_DIR/claude/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh" "statusline-command.sh"
    create_symlink "$REPO_DIR/claude/claude.json" "$CLAUDE_DIR/claude.json" "claude.json"
    echo

    # Check for required dependencies
    echo -e "${YELLOW}Checking dependencies...${NC}"

    check_dependency() {
        if command -v "$1" &> /dev/null; then
            echo -e "${GREEN}  ✓ $1 installed${NC}"
            return 0
        else
            echo -e "${RED}  ✗ $1 not found${NC}"
            return 1
        fi
    }

    all_deps_ok=true
    check_dependency "jq" || all_deps_ok=false
    check_dependency "bc" || all_deps_ok=false
    check_dependency "git" || all_deps_ok=false
    check_dependency "python3" || all_deps_ok=false

    echo

    if [ "$all_deps_ok" = false ]; then
        echo -e "${YELLOW}Missing dependencies detected. Install with:${NC}"
        echo "  brew install jq"
        echo
    fi

    # Make scripts executable
    echo -e "${YELLOW}Making scripts executable...${NC}"
    chmod +x "$CLAUDE_DIR/hooks"/*.sh "$CLAUDE_DIR/hooks"/*.py 2>/dev/null || true
    chmod +x "$CLAUDE_DIR/statusline-command.sh"
    echo -e "${GREEN}✓ Scripts are executable${NC}"
    echo

    # Star the repo (non-interactive → skip; see note above)
    echo -e "${BLUE}Star the meirpro-dotfiles repo on GitHub?${NC}"
    echo "  (Helps others on the team discover these tools)"
    if [ -t 0 ]; then
        read -p "Star repo? (y/N): " -n 1 -r star_choice
        echo
    else
        star_choice="n"
    fi
    if [[ "$star_choice" =~ ^[Yy]$ ]]; then
        if command -v gh &>/dev/null; then
            if gh api user/starred/meirpro/meirpro-dotfiles -X PUT 2>/dev/null; then
                echo -e "${GREEN}  Starred meirpro/meirpro-dotfiles${NC}"
            else
                echo -e "${YELLOW}  Could not star — run 'gh auth login' first${NC}"
            fi
        else
            echo -e "${YELLOW}  GitHub CLI (gh) not installed. Star manually:${NC}"
            echo "  https://github.com/meirpro/meirpro-dotfiles"
        fi
    fi
    echo

    echo -e "${GREEN}✓ Claude Code configuration installed${NC}"
    echo
fi

# ============================================================================
# SHELL CONFIGURATION INSTALLATION
# ============================================================================
if [[ $INSTALL_CHOICE =~ ^[23]$ ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Installing Shell Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    # Create symlinks for shell configs
    echo -e "${YELLOW}Creating symlinks for shell dotfiles...${NC}"
    # Canonical sources are aliases.sh / functions.sh, NOT the .aliases /
    # .functions dotfiles (removed 2026-07-23). shell/ghmp sources
    # functions.sh by path as its single source of truth, and README.md +
    # claude/CLAUDE.md both document functions.sh — the installer used to
    # link the stale dotfile copies, so `ghmp` was never defined.
    create_symlink "$REPO_DIR/shell/aliases.sh" "$HOME/.aliases" ".aliases"
    create_symlink "$REPO_DIR/shell/functions.sh" "$HOME/.functions" ".functions"
    create_symlink "$REPO_DIR/shell/.exports" "$HOME/.exports" ".exports"
    create_symlink "$REPO_DIR/shell/.bash_prompt" "$HOME/.bash_prompt" ".bash_prompt"
    create_symlink "$REPO_DIR/shell/.zshrc" "$HOME/.zshrc" ".zshrc"
    create_symlink "$REPO_DIR/shell/.zprofile" "$HOME/.zprofile" ".zprofile"
    echo

    # Create symlinks for editor configs
    echo -e "${YELLOW}Creating symlinks for editor configuration...${NC}"
    create_symlink "$REPO_DIR/editors/.vimrc" "$HOME/.vimrc" ".vimrc"
    create_symlink "$REPO_DIR/editors/.gvimrc" "$HOME/.gvimrc" ".gvimrc"
    create_symlink "$REPO_DIR/editors/.inputrc" "$HOME/.inputrc" ".inputrc"
    create_symlink "$REPO_DIR/editors/.editorconfig" "$HOME/.editorconfig" ".editorconfig"
    echo

    # Create symlinks for tool configs
    echo -e "${YELLOW}Creating symlinks for tool configuration...${NC}"
    create_symlink "$REPO_DIR/tools/wezterm.lua" "$HOME/.wezterm.lua" ".wezterm.lua (RTL/Hebrew terminal)"
    create_symlink "$REPO_DIR/tools/.tmux.conf" "$HOME/.tmux.conf" ".tmux.conf"
    create_symlink "$REPO_DIR/tools/.screenrc" "$HOME/.screenrc" ".screenrc"
    create_symlink "$REPO_DIR/tools/.wgetrc" "$HOME/.wgetrc" ".wgetrc"
    create_symlink "$REPO_DIR/tools/.curlrc" "$HOME/.curlrc" ".curlrc"
    echo

    # Create symlinks for git configs
    echo -e "${YELLOW}Creating symlinks for git configuration...${NC}"
    create_symlink "$REPO_DIR/git/.gitignore_global" "$HOME/.gitignore" ".gitignore (global)"

    # NO symlink for .gitattributes — deliberately. Git 2.45.1 hardened the
    # attributes stack against symlinked config files, so a symlinked
    # ~/.gitattributes makes every diff of a file under $HOME print
    #   warning: unable to access '~/.gitattributes':
    #   Too many levels of symbolic links
    # even though nothing is looping. shared.gitconfig now points
    # core.attributesfile straight at "$REPO_DIR/git/.gitattributes"
    # instead, so no file in $HOME is needed at all. Removing a stale one
    # left by an earlier install; see git/shared.gitconfig for the detail.
    if [ -L "$HOME/.gitattributes" ]; then
        rm "$HOME/.gitattributes"
        echo -e "${GREEN}  ✓ removed stale ~/.gitattributes symlink (see shared.gitconfig)${NC}"
    fi

    # safe-git wrapper at ~/bin/git intercepts dangerous git invocations
    # (git add -A, git add ., split stage/commit, bare commit -a) before
    # they reach the real git binary. PATH lookup must resolve ~/bin
    # earlier than /opt/homebrew/bin for this to work — the bash_profile
    # template already prepends it last so later additions can't push it
    # behind. Bypass with GIT_UNSAFE_STAGE=1.
    chmod +x "$REPO_DIR/git/safe-git"
    mkdir -p "$HOME/bin"
    create_symlink "$REPO_DIR/git/safe-git" "$HOME/bin/git" "git wrapper (~/bin/git → safe-git)"

    # ghmp as an executable too, so non-interactive shells (subagents, CI
    # one-liners) can call it without sourcing ~/.zshrc first. The wrapper
    # resolves functions.sh relative to its own real path, so the symlink
    # works from anywhere the repo is checked out.
    chmod +x "$REPO_DIR/shell/ghmp"
    create_symlink "$REPO_DIR/shell/ghmp" "$HOME/bin/ghmp" "ghmp (~/bin/ghmp)"
    echo

    # Copy template files (don't symlink these - user needs to customize)
    echo -e "${YELLOW}Copying template files for customization...${NC}"

    if [ ! -f "$HOME/.bash_profile" ]; then
        cp "$REPO_DIR/shell/.bash_profile.template" "$HOME/.bash_profile"
        echo -e "${GREEN}  ✓ Created .bash_profile (customize as needed)${NC}"
    else
        echo -e "${BLUE}  • .bash_profile exists (skipping, see .bash_profile.template)${NC}"
    fi

    if [ ! -f "$HOME/.bashrc" ]; then
        cp "$REPO_DIR/shell/.bashrc.template" "$HOME/.bashrc"
        echo -e "${GREEN}  ✓ Created .bashrc (customize as needed)${NC}"
    else
        echo -e "${BLUE}  • .bashrc exists (skipping, see .bashrc.template)${NC}"
    fi

    if [ ! -f "$HOME/.gitconfig" ]; then
        cp "$REPO_DIR/git/.gitconfig.template" "$HOME/.gitconfig"
        echo -e "${GREEN}  ✓ Created .gitconfig (ADD YOUR NAME & EMAIL!)${NC}"
        echo -e "${YELLOW}    Run: git config --global user.name \"Your Name\"${NC}"
        echo -e "${YELLOW}    Run: git config --global user.email \"your@email.com\"${NC}"
    else
        echo -e "${BLUE}  • .gitconfig exists (skipping, see .gitconfig.template)${NC}"
    fi
    echo

    # Create vim directories
    echo -e "${YELLOW}Creating vim directories...${NC}"
    mkdir -p "$HOME/.vim/"{backups,swaps,undo,colors}
    echo -e "${GREEN}  ✓ Created vim directories${NC}"
    echo

    # Detect shell and update config
    SHELL_NAME=$(basename "$SHELL")
    echo -e "${YELLOW}Detected shell:${NC} $SHELL_NAME"
    echo

    case "$SHELL_NAME" in
        bash)
            SHELL_RC="$HOME/.bash_profile"
            SOURCE_CMD='[ -r ~/.aliases ] && source ~/.aliases; [ -r ~/.functions ] && source ~/.functions'
            ;;
        zsh)
            SHELL_RC="$HOME/.zshrc"
            SOURCE_CMD='[ -r ~/.aliases ] && source ~/.aliases; [ -r ~/.functions ] && source ~/.functions'
            ;;
        *)
            echo -e "${YELLOW}Unsupported shell: $SHELL_NAME${NC}"
            echo "Please manually source ~/.aliases and ~/.functions in your shell config"
            SHELL_RC=""
            ;;
    esac

    if [ -n "$SHELL_RC" ]; then
        # Check if already configured
        if check_shell_config "$SHELL_RC" "source.*\.aliases\|source.*\.functions"; then
            echo -e "${GREEN}✓ Shell config already sourcing aliases and functions${NC}"
        else
            echo -e "${YELLOW}Adding source commands to $SHELL_RC${NC}"
            echo "" >> "$SHELL_RC"
            echo "# Shell configuration from dotfiles repo" >> "$SHELL_RC"
            echo "$SOURCE_CMD" >> "$SHELL_RC"
            echo -e "${GREEN}✓ Updated $SHELL_RC${NC}"
        fi
        echo
    fi

    echo -e "${GREEN}✓ Shell configuration installed${NC}"
    echo
fi

# ============================================================================
# SUCCESS MESSAGE
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Installation Complete! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

if [[ $INSTALL_CHOICE =~ ^[13]$ ]]; then
    echo -e "${YELLOW}Claude Code features installed:${NC}"
    echo "  • Auto TypeScript checking on every file edit"
    echo "  • Auto ESLint on every file edit"
    echo "  • Auto Prettier formatting on every file edit"
    echo "  • Security rules (blocks reading .env, secrets, keys)"
    echo "  • Git safety rules (no git add -A, no co-author lines)"
    echo "  • Custom status line with git info, cost tracking, session ID"
    if [[ "$audio_choice" =~ ^[Yy]$ ]]; then
        echo "  • Audio notifications on task completion"
    fi
    echo
fi

if [[ $INSTALL_CHOICE =~ ^[23]$ ]]; then
    echo -e "${YELLOW}Shell dotfiles installed (based on Mathias Bynens' dotfiles):${NC}"
    echo "  • Comprehensive aliases (6.5KB) - navigation, git, network, HTTP shortcuts"
    echo "  • Useful functions (6.6KB) - mkd, cdf, targz, diff, server, cld, etc."
    echo "  • Environment exports - vim editor, large history, UTF-8 locale"
    echo "  • Solarized Dark bash prompt with git status"
    echo "  • Vim configuration with Solarized theme"
    echo "  • Git configuration with extensive aliases"
    echo "  • Tool configs - tmux, wget, curl, inputrc"
    echo "  • Usage: cld -r 5c56e09f (resume Claude session with partial ID)"
    echo
fi

echo -e "${YELLOW}Next steps:${NC}"
if [[ $INSTALL_CHOICE =~ ^[23]$ ]]; then
    echo "  1. Reload your shell: source ~/.bash_profile (or source ~/.zshrc)"
    echo "  2. Customize .gitconfig: git config --global user.name \"Your Name\""
    echo "  3. Customize .gitconfig: git config --global user.email \"your@email.com\""
    echo "  4. Review SETUP.md for installing tools (NVM, Homebrew packages, etc.)"
    echo "  5. Test functions: try 'll', 'mkd test', 'cld -r <partial-id>'"
fi
if [[ "$(uname)" == "Darwin" ]]; then
    echo "  • Apply macOS system defaults: ./macos/defaults.sh"
    echo "    (key repeat, menu bar density, instant Dock, Finder path bar)"
    echo "    Not run automatically — it restarts Finder/Dock and needs a logout."
fi
if [[ $INSTALL_CHOICE =~ ^[13]$ ]]; then
    echo "  • Restart Claude Code or start a new session"
    echo "  • Try /commit-emoji to test slash commands"
fi
echo

echo -e "${YELLOW}Important files to customize:${NC}"
if [[ $INSTALL_CHOICE =~ ^[23]$ ]]; then
    echo "  • ~/.gitconfig - Add your name and email (REQUIRED)"
    echo "  • ~/.bash_profile - Add machine-specific PATH additions"
    echo "  • ~/.extra - Create for local settings you don't want to commit"
fi
if [[ $INSTALL_CHOICE =~ ^[13]$ ]]; then
    echo "  • ~/.claude/settings.local.json - Create for local Claude overrides"
fi
echo

echo -e "${YELLOW}Attribution:${NC}"
echo "  Shell dotfiles based on Mathias Bynens' dotfiles"
echo "  https://github.com/mathiasbynens/dotfiles"
echo

echo -e "${YELLOW}Learn more:${NC}"
echo "  • See README.md for full features and documentation"
echo "  • See SETUP.md for tool installation guide"
echo "  • All symlinked files can be edited in the repo for version control"
echo

echo -e "${GREEN}Enjoy your enhanced development environment! ✨${NC}"
