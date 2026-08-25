# zsh options. bash set these via `shopt` in .bash_profile.template /
# bash_options; these are the zsh equivalents (bash's shopt names do
# nothing in zsh). AUTO_CD is why `../photobooth-ai` or a bare dir name
# changes directory without typing `cd`.
setopt AUTO_CD              # bare path / `../foo` → cd (bash: shopt -s autocd)
setopt EXTENDED_GLOB        # advanced globbing (bash: globstar; zsh ** is builtin)
setopt NO_CASE_GLOB         # case-insensitive globbing (bash: nocaseglob)
setopt APPEND_HISTORY HIST_IGNORE_DUPS   # don't clobber history (bash: histappend)

alias rm='safe-rm'
export PATH=~/.npm-global/bin:$PATH

export PATH="$PATH:$HOME/.local/bin"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export PATH="$HOME/bin:$PATH"

# Shell configuration from dotfiles repo.
# Sourced here rather than appended by install.sh: this file is symlinked
# to ~/.zshrc, so the installer's append would write back into the repo
# unreviewed. Keeping it in-tree means a bare symlink also works.
[ -r ~/.aliases ] && source ~/.aliases
[ -r ~/.functions ] && source ~/.functions

# Prompt. Resolved relative to this file's REAL location (${(%):-%x} is
# the sourced file; :A resolves the ~/.zshrc symlink back into the repo,
# :h takes its directory) so the repo can live anywhere without a
# hardcoded path — which is exactly the breakage we just cleaned up.
[ -r "${${(%):-%x}:A:h}/prompt.zsh" ] && source "${${(%):-%x}:A:h}/prompt.zsh"

# NOTE: safe-git-hook.sh is deliberately NOT sourced any more. It existed
# to expose the typed command line to safe-git's rules 4/5, which used to
# text-match the parent shell's argv. Those rules now verify index state
# via a stage token instead (2026-07-23), so nothing reads the capture
# file. Sourcing it would only add a DEBUG trap / preexec hook for no gain.
# Node from nodejs.org, NOT Homebrew — because of Little Snitch.
#
# Homebrew signs node ad-hoc: `Signature=adhoc`, `TeamIdentifier=not set`, so
# the code hash IS the identity. Every upgrade — and every REVISION rebuild,
# which keeps the version and only relinks a dependency — mints a new identity,
# voids the existing rule, and re-prompts. An unanswered prompt is a deny, and
# then node cannot open a socket at all: `wrangler deploy` fails with EBADF
# while curl on the same URL works, which reads as a credential bug and is not
# one. Pinning the node VERSION does not help; the revision rebuild does it too.
#
# The official builds carry a real Developer ID:
#   Authority=Developer ID Application: Node.js Foundation (HX7739G8FX)
# and every release shares that Team ID, so a rule survives upgrades.
#
# ~/.local/node is a symlink to the versioned directory — point it at a new one
# to upgrade, and this line never changes:
#   V=v24.19.0; curl -fsSLO https://nodejs.org/dist/$V/node-$V-darwin-arm64.tar.gz
#   curl -fsSL https://nodejs.org/dist/$V/SHASUMS256.txt | grep " node-$V-darwin-arm64.tar.gz$" | shasum -a 256 -c -
#   tar -xzf node-$V-darwin-arm64.tar.gz -C ~/.local
#   ln -sfn ~/.local/node-$V-darwin-arm64 ~/.local/node
export PATH="$HOME/.local/node/bin:$PATH"

# fzf: Ctrl-R history search, Ctrl-T file insert, Alt-C cd. `fzf --zsh`
# emits the keybindings + completion inline (fzf >= 0.48), which replaces
# the old ~/.fzf.zsh that install.sh used to write into $HOME — same reason
# .aliases is sourced above rather than appended.
command -v fzf >/dev/null && source <(fzf --zsh)
export PATH=$PATH:$HOME/.maestro/bin

# Android SDK — adb / emulator on PATH (JAVA_HOME + ANDROID_HOME for gradle)
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
