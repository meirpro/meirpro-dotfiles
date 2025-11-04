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

# Ask what to install
echo -e "${BLUE}What would you like to install?${NC}"
echo "  1) Claude Code configuration only"
echo "  2) Shell configuration only (aliases, functions)"
echo "  3) Both (recommended)"
echo
read -p "Select option (1-3): " -n 1 -r
echo
INSTALL_CHOICE=$REPLY

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
    local backup_dir="$HOME/.claude.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Creating backup at:${NC} $backup_dir"
    cp -r "$CLAUDE_DIR" "$backup_dir"
    echo -e "${GREEN}✓ Backup created${NC}"
    echo

    # Create symlinks for directories
    echo -e "${YELLOW}Creating symlinks for directories...${NC}"
    create_symlink "$REPO_DIR/claude/hooks" "$CLAUDE_DIR/hooks" "hooks/"
    create_symlink "$REPO_DIR/claude/commands" "$CLAUDE_DIR/commands" "commands/"
    create_symlink "$REPO_DIR/claude/agents" "$CLAUDE_DIR/agents" "agents/"
    create_symlink "$REPO_DIR/claude/audio" "$CLAUDE_DIR/audio" "audio/"
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
    echo -e "${YELLOW}Creating symlinks for shell configuration...${NC}"
    create_symlink "$REPO_DIR/shell/aliases.sh" "$HOME/.aliases" ".aliases"
    create_symlink "$REPO_DIR/shell/functions.sh" "$HOME/.functions" ".functions"
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
    echo "  • Custom status line with session tracking"
    echo "  • TypeScript/lint hooks for automatic code checking"
    echo "  • Audio notification hooks"
    echo "  • Slash commands: /commit-emoji, /commit"
    echo "  • 12 specialized agents for code quality"
    echo
fi

if [[ $INSTALL_CHOICE =~ ^[23]$ ]]; then
    echo -e "${YELLOW}Shell features installed:${NC}"
    echo "  • Enhanced cld function with smart session ID matching"
    echo "  • Custom aliases and functions"
    echo "  • Usage: cld -r 5c56e09f (resume with partial ID)"
    echo
fi

echo -e "${YELLOW}Next steps:${NC}"
if [[ $INSTALL_CHOICE =~ ^[23]$ ]]; then
    echo "  1. Reload your shell: source $SHELL_RC"
    echo "  2. Test shell functions: cld -r <partial-session-id>"
fi
if [[ $INSTALL_CHOICE =~ ^[13]$ ]]; then
    echo "  • Restart Claude Code or start a new session"
    echo "  • Try /commit-emoji to test slash commands"
fi
echo

echo -e "${YELLOW}Local settings:${NC}"
if [[ $INSTALL_CHOICE =~ ^[13]$ ]]; then
    echo "  • Create ~/.claude/settings.local.json for local-only overrides"
fi
echo "  • All symlinked files can be edited in the repo for version control"
echo

echo -e "${GREEN}Enjoy your enhanced development environment! ✨${NC}"
