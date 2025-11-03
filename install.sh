#!/usr/bin/env bash

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Claude Code Configuration Installer${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Get the directory where this script is located
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLAUDE_DIR="$HOME/.claude"

echo -e "${YELLOW}Repository:${NC} $REPO_DIR"
echo -e "${YELLOW}Target:${NC} $CLAUDE_DIR"
echo

# Check if Claude Code is installed
if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${RED}Error: ~/.claude directory not found${NC}"
    echo "Please install Claude Code first: https://claude.ai/code"
    exit 1
fi

# Function to create backup
create_backup() {
    local backup_dir="$HOME/.claude.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Creating backup at:${NC} $backup_dir"
    cp -r "$CLAUDE_DIR" "$backup_dir"
    echo -e "${GREEN}✓ Backup created${NC}"
    echo
}

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

# Ask for confirmation
echo -e "${YELLOW}This will:${NC}"
echo "  1. Create a backup of your existing ~/.claude directory"
echo "  2. Create symlinks from ~/.claude to this repository"
echo "  3. Preserve local-only files (history, todos, etc.)"
echo
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation cancelled${NC}"
    exit 0
fi
echo

# Create backup
create_backup

# Create symlinks for directories
echo -e "${YELLOW}Creating symlinks for directories...${NC}"
create_symlink "$REPO_DIR/hooks" "$CLAUDE_DIR/hooks" "hooks/"
create_symlink "$REPO_DIR/commands" "$CLAUDE_DIR/commands" "commands/"
create_symlink "$REPO_DIR/agents" "$CLAUDE_DIR/agents" "agents/"
create_symlink "$REPO_DIR/audio" "$CLAUDE_DIR/audio" "audio/"
echo

# Create symlinks for files
echo -e "${YELLOW}Creating symlinks for files...${NC}"
create_symlink "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json" "settings.json"
create_symlink "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
create_symlink "$REPO_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh" "statusline-command.sh"
create_symlink "$REPO_DIR/claude.json" "$CLAUDE_DIR/claude.json" "claude.json"
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

# Success message
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Installation Complete! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${YELLOW}What's installed:${NC}"
echo "  • Custom status line with session tracking"
echo "  • TypeScript/lint hooks for automatic code checking"
echo "  • Audio notification hooks"
echo "  • Slash commands: /commit-emoji, /commit"
echo "  • 12 specialized agents for code quality"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Restart Claude Code or start a new session"
echo "  2. Verify status line appears at the bottom"
echo "  3. Try /commit-emoji to test slash commands"
echo "  4. Edit a TypeScript file to test hooks"
echo
echo -e "${YELLOW}Local settings:${NC}"
echo "  Create ~/.claude/settings.local.json for local-only overrides"
echo "  (This file is gitignored and won't be synced)"
echo
echo -e "${GREEN}Enjoy your enhanced Claude Code experience! ✨${NC}"
