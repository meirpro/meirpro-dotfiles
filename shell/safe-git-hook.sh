# safe-git command-capture hook — bash + zsh.
#
# Writes the most recent shell command line to ~/.cache/safe-git-cmd-$$
# so the `safe-git` wrapper can verify atomic stage+commit chains even
# on interactive macOS shells, where `ps -o command= -p $PPID` only
# returns the shell name (`-bash` / `-zsh`) and not the pipeline being
# executed.
#
# # Why this hook exists
#
# `safe-git` (meirpro-dotfiles/git/safe-git) enforces:
#   - `git add` must be chained with `git commit -m` in one shell command.
#   - `git commit` must be preceded by `git add <files>` in one shell command.
#
# To check this, the wrapper needs the FULL command line the user typed.
# On Linux, /proc/$PPID/cmdline exposes it. On macOS, it doesn't — so
# this hook captures it via the shell's pre-execution hook (DEBUG trap
# in bash, preexec in zsh) and parks it where the wrapper can read it.
#
# Without this hook, `safe-git` still works for non-interactive contexts
# (Claude Code's `bash -c "<pipeline>"`, shell scripts) — those expose
# the pipeline in their direct argv. The hook is what makes the wrapper
# usable from a normal interactive prompt.
#
# # Installation
#
# Source this file from your interactive shell init. For bash:
#
#   # in ~/.bash_profile (or ~/.functions if you load that):
#   [ -r ~/Documents/GitHub/meirpro-dotfiles/shell/safe-git-hook.sh ] && \
#     source ~/Documents/GitHub/meirpro-dotfiles/shell/safe-git-hook.sh
#
# For zsh:
#
#   # in ~/.zshrc:
#   [ -r ~/Documents/GitHub/meirpro-dotfiles/shell/safe-git-hook.sh ] && \
#     source ~/Documents/GitHub/meirpro-dotfiles/shell/safe-git-hook.sh
#
# Idempotent — sourcing twice is harmless.
#
# # Safety
#
# The capture file path is per-shell-process (`$$`), the wrapper trusts
# it only if mtime is ≤ 10 seconds old, and the EXIT trap removes the
# file on shell exit. A stale file from a previous shell with the same
# recycled PID would be rejected by the mtime check before it could be
# misused.

# Already installed? Bail. (Sourced twice from competing init paths is
# common — bash_profile, then .functions, etc.)
if [ -n "${__SAFE_GIT_HOOK_INSTALLED:-}" ]; then
    return 0 2>/dev/null || true
fi
__SAFE_GIT_HOOK_INSTALLED=1

# ─────────────────────────────────────────────────────────────────
# Recorder — writes the user's most recent typed command to the
# per-shell cache file. Called by the bash DEBUG trap OR the zsh
# preexec hook depending on which shell is running.
# ─────────────────────────────────────────────────────────────────
__safe_git_record() {
    local last
    if [ -n "${BASH_VERSION:-}" ]; then
        # Bash path. DEBUG fires before every simple command; skip
        # internal noise so we don't write garbage:
        #   - COMP_LINE is set during completion.
        #   - BASH_SUBSHELL > 0 means we're inside a forked subshell;
        #     we only want the outermost user-typed line.
        [ -n "${COMP_LINE:-}" ] && return
        [ "${BASH_SUBSHELL:-0}" -gt 0 ] && return
        # `history 1` returns the most recent line as the user typed
        # it (including the full `&&` chain) regardless of how many
        # simple commands it contains. Strip the leading history
        # number `   123  command…`.
        last="$(HISTTIMEFORMAT= history 1 2>/dev/null | sed 's/^[[:space:]]*[0-9]\{1,\}[[:space:]]*//')"
    else
        # Zsh path. preexec passes the whole pipeline as $1.
        last="${1:-}"
    fi
    [ -z "$last" ] && return
    mkdir -p "$HOME/.cache" 2>/dev/null
    printf '%s\n' "$last" > "$HOME/.cache/safe-git-cmd-$$" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────
# Cleanup on shell exit. Prevents PID recycling from re-using a
# stale capture file in a future shell.
# ─────────────────────────────────────────────────────────────────
__safe_git_cleanup() {
    rm -f "$HOME/.cache/safe-git-cmd-$$" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────
# Bash: install DEBUG + EXIT traps. Interactive shells only —
# non-interactive (script) bash already exposes its argv via PPID's
# ps output and doesn't need this hook.
# ─────────────────────────────────────────────────────────────────
if [ -n "${BASH_VERSION:-}" ]; then
    case "$-" in
        *i*)
            trap '__safe_git_record' DEBUG
            trap '__safe_git_cleanup' EXIT
            ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────
# Zsh: install preexec + zshexit hooks via add-zsh-hook.
# ─────────────────────────────────────────────────────────────────
if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null
    if (( ${+functions[add-zsh-hook]} )); then
        add-zsh-hook preexec __safe_git_record
        add-zsh-hook zshexit __safe_git_cleanup
    fi
fi
