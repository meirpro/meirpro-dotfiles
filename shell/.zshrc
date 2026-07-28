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
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
