#!/usr/bin/env bash
# setup-claude.sh — Claude Code configuration installer
# Works on: macOS, Linux, Windows (Git Bash / WSL)
#
# Usage:
#   bash setup-claude.sh          # Interactive
#   bash setup-claude.sh --all    # Install everything including audio
#   bash setup-claude.sh --no-audio  # Install without audio prompts

set -e

# Colors (disable on dumb terminals)
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    DIM='\033[2m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' CYAN='' DIM='' NC=''
fi

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows-bash" ;;
        *)        echo "unknown" ;;
    esac
}

OS=$(detect_os)

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Claude Code Configuration Installer${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

# Determine paths
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# On Windows Git Bash, HOME is usually set correctly
CLAUDE_DIR="$HOME/.claude"

echo -e "${YELLOW}Repository:${NC} $REPO_DIR"
echo -e "${YELLOW}Target:${NC}     $CLAUDE_DIR"
echo -e "${DIM}Platform:   $OS${NC}"
echo ""

# Check Claude Code is installed
if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${RED}Error: $CLAUDE_DIR not found.${NC}"
    echo "Install Claude Code first: https://claude.ai/code"
    exit 1
fi

# Backup existing config
backup_dir="$HOME/.claude.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${YELLOW}Creating backup at:${NC} $backup_dir"
cp -r "$CLAUDE_DIR" "$backup_dir"
echo -e "${GREEN}  Backup created${NC}"
echo ""

# Parse arguments
INSTALL_AUDIO=""
for arg in "$@"; do
    case "$arg" in
        --all)      INSTALL_AUDIO="yes" ;;
        --no-audio) INSTALL_AUDIO="no" ;;
    esac
done

# Ask about audio if not specified via args (skip prompt in non-interactive mode)
if [ -z "$INSTALL_AUDIO" ]; then
    if [ -t 0 ]; then
        echo -e "${CYAN}Install audio notifications?${NC} (plays sounds on task completion)"
        echo -e "  Requires: Python 3"
        echo -e "  Audio files: ~2MB"
        echo ""
        read -p "Install audio? (y/N): " -n 1 -r audio_choice
        echo ""
        if [[ "$audio_choice" =~ ^[Yy]$ ]]; then
            INSTALL_AUDIO="yes"
        else
            INSTALL_AUDIO="no"
        fi
        echo ""
    else
        INSTALL_AUDIO="no"
    fi
fi

# Symlink helper — creates symlink with backup of existing files
create_symlink() {
    local source="$1"
    local target="$2"
    local name="$3"

    # Check source exists
    if [ ! -e "$source" ]; then
        echo -e "${DIM}  Skipped $name (source not found)${NC}"
        return
    fi

    # Back up existing non-symlink
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        mv "$target" "${target}.old.$(date +%H%M%S)"
        echo -e "${YELLOW}    Backed up existing $name${NC}"
    fi

    # Remove existing symlink
    if [ -L "$target" ]; then
        rm "$target"
    fi

    # Create symlink
    ln -sf "$source" "$target"
    echo -e "${GREEN}  Linked $name${NC}"
}

# Install directories
echo -e "${YELLOW}Installing directories...${NC}"
create_symlink "$REPO_DIR/hooks" "$CLAUDE_DIR/hooks" "hooks/"
create_symlink "$REPO_DIR/commands" "$CLAUDE_DIR/commands" "commands/"

if [ -d "$REPO_DIR/agents" ]; then
    create_symlink "$REPO_DIR/agents" "$CLAUDE_DIR/agents" "agents/"
fi

if [ "$INSTALL_AUDIO" = "yes" ]; then
    create_symlink "$REPO_DIR/audio" "$CLAUDE_DIR/audio" "audio/"
else
    # Remove audio dir so play_audio.py becomes a no-op
    if [ -L "$CLAUDE_DIR/audio" ]; then
        rm "$CLAUDE_DIR/audio"
    elif [ -d "$CLAUDE_DIR/audio" ]; then
        rm -rf "$CLAUDE_DIR/audio"
    fi
    echo -e "${DIM}  Skipped audio/ (notifications disabled)${NC}"
fi
echo ""

# Install files
echo -e "${YELLOW}Installing files...${NC}"
create_symlink "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json" "settings.json"
create_symlink "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
create_symlink "$REPO_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh" "statusline-command.sh"

if [ -f "$REPO_DIR/claude.json" ]; then
    create_symlink "$REPO_DIR/claude.json" "$CLAUDE_DIR/claude.json" "claude.json"
fi
echo ""

# Make scripts executable
echo -e "${YELLOW}Making scripts executable...${NC}"
chmod +x "$CLAUDE_DIR/hooks"/*.sh 2>/dev/null || true
chmod +x "$CLAUDE_DIR/hooks"/*.py 2>/dev/null || true
chmod +x "$CLAUDE_DIR/statusline-command.sh" 2>/dev/null || true
echo -e "${GREEN}  Done${NC}"
echo ""

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
all_ok=true

check_dep() {
    local cmd="$1"
    local fallback="$2"
    if command -v "$cmd" &>/dev/null; then
        echo -e "${GREEN}  $cmd${NC}"
    elif [ -n "$fallback" ] && command -v "$fallback" &>/dev/null; then
        echo -e "${GREEN}  $fallback (as '$fallback')${NC}"
    else
        echo -e "${RED}  $cmd — not found${NC}"
        all_ok=false
    fi
}

check_dep "git"
check_dep "node"
check_dep "python3" "python"
check_dep "jq"

if [ "$all_ok" = false ]; then
    echo ""
    echo -e "${YELLOW}Missing dependencies. Install with:${NC}"
    case "$OS" in
        macos)         echo "  brew install jq python3 node" ;;
        linux|wsl)     echo "  sudo apt install jq python3 nodejs" ;;
        windows-bash)  echo "  winget install jqlang.jq Python.Python.3 OpenJS.NodeJS" ;;
    esac
fi
echo ""

# Star the repo on GitHub (skip in non-interactive mode)
if [ -t 0 ]; then
    echo -e "${CYAN}Star the meirpro-dotfiles repo on GitHub?${NC}"
    echo -e "  (Helps others on the team discover these tools)"
    read -p "Star repo? (y/N): " -n 1 -r star_choice
    echo ""
    if [[ "$star_choice" =~ ^[Yy]$ ]]; then
        if command -v gh &>/dev/null; then
            if gh api user/starred/meirpro/meirpro-dotfiles -X PUT 2>/dev/null; then
                echo -e "${GREEN}  Starred meirpro/meirpro-dotfiles${NC}"
            else
                echo -e "${YELLOW}  Could not star — run 'gh auth login' first${NC}"
            fi
        else
            echo -e "${YELLOW}  GitHub CLI (gh) not installed. Star manually:${NC}"
            echo -e "${CYAN}  https://github.com/meirpro/meirpro-dotfiles${NC}"
        fi
    fi
fi
echo ""

# Done
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}Features installed:${NC}"
echo "  - Auto TypeScript checking on every file edit"
echo "  - Auto ESLint on every file edit"
echo "  - Auto Prettier formatting on every file edit"
echo "  - Security rules (blocks reading .env, secrets, keys)"
echo "  - Git safety rules (no git add -A, no co-author lines)"
echo "  - Status line with git info, cost tracking, session ID"
if [ "$INSTALL_AUDIO" = "yes" ]; then
    echo "  - Audio notifications on task completion"
fi
echo ""
echo -e "${YELLOW}Next:${NC} Restart Claude Code or start a new session."
echo ""
