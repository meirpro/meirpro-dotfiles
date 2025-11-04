# Machine-Specific Setup Guide

This guide covers the machine-specific software and configurations you'll need to set up separately on a new machine. The dotfiles in this repository provide the **universal configurations**, but you'll need to install the actual tools first.

## 📦 Package Manager

### Homebrew (macOS)

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to PATH (for Apple Silicon Macs)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Disable analytics (already in dotfiles, but can be set before first use)
export HOMEBREW_NO_ANALYTICS=1
```

### Essential Packages

```bash
# Install essential development tools
brew install \
  git \
  bash \
  bash-completion@2 \
  coreutils \
  findutils \
  gnu-sed \
  grep \
  wget \
  curl \
  vim \
  tmux \
  screen \
  jq \
  tree \
  htop
```

## 🔧 Development Tools

### Node.js & NVM

**NVM (Node Version Manager)** - For managing multiple Node.js versions:

```bash
# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# The NVM installer will add these lines to your ~/.bashrc
# (They're already in the .bashrc.template as comments - uncomment them!)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Reload shell
source ~/.bashrc

# Install latest Node.js LTS
nvm install --lts

# Set default Node version
nvm alias default node
```

**Global npm packages location** (already configured in `.npmrc`):

```bash
# Create global npm directory
mkdir -p ~/.npm-global

# Configure npm (this is already in ~/.npmrc if you used the dotfiles)
npm config set prefix '~/.npm-global'

# Add to PATH (already in .bash_profile.template)
export PATH=~/.npm-global/bin:$PATH
```

### Python & pipx

```bash
# Python 3 is pre-installed on macOS, but you can upgrade via Homebrew
brew install python3

# Install pipx for Python tool management
brew install pipx

# Ensure pipx path (already in .bash_profile.template comments)
pipx ensurepath

# The path will be: ~/.local/bin (already in .zshrc)
```

### Git Configuration

After installing git, customize your `.gitconfig`:

```bash
# Edit the template file you copied during installation
vim ~/.gitconfig

# Replace these lines:
# [user]
#     name = Your Name
#     email = your.email@example.com

# With your actual information:
git config --global user.name "Your Actual Name"
git config --global user.email "your.actual.email@example.com"

# Optional: Set up GPG signing
# git config --global user.signingkey YOUR_GPG_KEY_ID
# git config --global commit.gpgsign true
```

### Claude Code

```bash
# Claude Code installation (if not already installed)
# Visit: https://claude.ai/download

# After installation, the dotfiles should already be linked
# But you'll need to add Claude to your PATH manually or through install script

# Check installation
claude --version
```

## 🛠️ Optional Development Tools

### Google Cloud SDK

```bash
# Download and install from:
# https://cloud.google.com/sdk/docs/install-sdk

# The installer will ask to update your PATH
# If using bash, add to ~/.bash_profile (already in template as comments):
# if [ -f '/path/to/google-cloud-sdk/path.bash.inc' ]; then
#   . '/path/to/google-cloud-sdk/path.bash.inc'
# fi
# if [ -f '/path/to/google-cloud-sdk/completion.bash.inc' ]; then
#   . '/path/to/google-cloud-sdk/completion.bash.inc'
# fi
```

### Windsurf (IDE)

```bash
# Download and install from: https://codeium.com/windsurf

# Windsurf adds this to your PATH during installation:
# export PATH="/Users/USERNAME/.codeium/windsurf/bin:$PATH"
#
# You can add this to ~/.bash_profile or ~/.extra for your machine
```

### Postgres.app

```bash
# Download from: https://postgresapp.com/

# After installation, add to PATH (in ~/.extra or ~/.bash_profile):
# export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"
```

### Docker Desktop

```bash
# Download from: https://www.docker.com/products/docker-desktop/

# Docker Desktop adds itself to PATH automatically
```

## 🎨 Terminal Customization

### Solarized Color Scheme

The dotfiles use the Solarized Dark color scheme. You'll need to configure your terminal emulator:

**iTerm2:**
1. Download Solarized theme: https://github.com/altercation/solarized/tree/master/iterm2-colors-solarized
2. iTerm2 → Preferences → Profiles → Colors → Color Presets → Import
3. Select `Solarized Dark.itermcolors`

**macOS Terminal.app:**
1. Download Solarized theme: https://github.com/tomislav/osx-terminal.app-colors-solarized
2. Terminal → Preferences → Profiles → Import
3. Select `Solarized Dark.terminal`

### Fonts

For best compatibility with the prompt and special characters:

```bash
# Install Powerline fonts (optional, for better symbols)
brew tap homebrew/cask-fonts
brew install font-source-code-pro
brew install font-fira-code
brew install font-hack-nerd-font

# Configure your terminal to use one of these fonts
```

## 📝 Machine-Specific Files

### ~/.extra

Create `~/.extra` for machine-specific configurations you don't want to commit:

```bash
# Create the file
touch ~/.extra
chmod 600 ~/.extra  # Make it private

# Add machine-specific settings
vim ~/.extra
```

Example `~/.extra` contents:

```bash
#!/usr/bin/env bash

# Local PATH additions
export PATH="$HOME/my-local-tools:$PATH"

# API keys and secrets (DO NOT COMMIT)
export OPENAI_API_KEY="your-key-here"
export ANTHROPIC_API_KEY="your-key-here"

# Work-specific aliases
alias work-vpn="sudo openconnect vpn.company.com"

# Local machine hostname/customization
export LOCAL_MACHINE_NAME="my-macbook"
```

### ~/.path

Create `~/.path` for local PATH modifications:

```bash
# Create the file
touch ~/.path

# Add custom paths
echo 'export PATH="$HOME/custom-bin:$PATH"' >> ~/.path
```

Both `~/.extra` and `~/.path` are sourced by `.bash_profile` if they exist.

## 🔐 SSH Configuration

### SSH Keys

```bash
# Generate new SSH key for GitHub
ssh-keygen -t ed25519 -C "your.email@example.com"

# Start ssh-agent
eval "$(ssh-agent -s)"

# Add key to ssh-agent
ssh-add ~/.ssh/id_ed25519

# Copy public key to clipboard
pbcopy < ~/.ssh/id_ed25519.pub

# Add to GitHub: Settings → SSH and GPG keys → New SSH key
```

### ~/.ssh/config

Create your SSH config (this is machine-specific and not in the repo):

```bash
# Create config file
touch ~/.ssh/config
chmod 600 ~/.ssh/config

# Example config
cat > ~/.ssh/config << 'EOF'
Host github.com
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
```

## 🔧 Vim Setup

### Vim Colors

The `.vimrc` uses Solarized Dark. Install it:

```bash
# Create vim colors directory
mkdir -p ~/.vim/colors

# Download Solarized
curl -o ~/.vim/colors/solarized.vim \
  https://raw.githubusercontent.com/altercation/vim-colors-solarized/master/colors/solarized.vim
```

### Vim Directories

The `.vimrc` expects these directories to exist:

```bash
# Create vim backup/swap/undo directories
mkdir -p ~/.vim/{backups,swaps,undo}
```

## 📋 Verification Checklist

After setup, verify everything works:

```bash
# Shell
echo $SHELL  # Should be /bin/bash or /bin/zsh
bash --version  # Should be >= 4.0

# Node.js
node --version
npm --version
nvm --version

# Python
python3 --version
pipx --version

# Git
git --version
git config user.name  # Should show your name
git config user.email  # Should show your email

# Claude Code
claude --version

# Homebrew
brew --version

# Tools
vim --version
tmux -V
jq --version

# Aliases and functions (from dotfiles)
type ll  # Should show alias
type mkd  # Should show function
type cld  # Should show Claude Code function
```

## 🚨 Common Issues

### "command not found" errors

If you get "command not found" after installing something:

```bash
# Reload your shell configuration
source ~/.bash_profile
# or
source ~/.zshrc

# Check your PATH
echo $PATH

# Verify tool location
which node
which git
which claude
```

### NVM not loading

If NVM doesn't work:

```bash
# Check if NVM is installed
ls -la ~/.nvm

# Verify NVM lines are uncommented in ~/.bashrc
cat ~/.bashrc | grep NVM

# Manually source NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

### Git commits not working

If git asks for user info:

```bash
# Configure git user
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## 📚 Additional Resources

- [Homebrew Documentation](https://docs.brew.sh/)
- [NVM GitHub](https://github.com/nvm-sh/nvm)
- [Mathias Bynens' macOS Defaults](https://github.com/mathiasbynens/dotfiles/blob/main/.macos) - Sensible macOS defaults
- [Claude Code Documentation](https://docs.claude.com/en/docs/claude-code)

## 💡 Tips

1. **Keep `~/.extra` private** - Never commit it to git (it's in .gitignore)
2. **Document your `~/.extra`** - Keep notes on what machine-specific settings you've added
3. **Update this file** - If you find new tools you always install, add them here
4. **Test on fresh machine** - The best way to verify this guide is to try it on a new/clean Mac

---

**Remember:** The dotfiles provide the **configuration**, but you need to install the **tools** first!
