#!/usr/bin/env zsh
#
# zsh prompt with git state.
#
# Why this file exists: shell/.bash_prompt is bash-only (it assigns PS1
# and uses bash escape syntax), so zsh users got the stock
# `user@host dir %` prompt and no git information at all. This is the
# zsh equivalent.
#
# Symbols deliberately match claude/statusline-command.sh, so the shell
# prompt and the Claude Code status line read identically:
#
#   ⇡N  commits ahead of upstream      +  staged changes
#   ⇣N  commits behind upstream        !  unstaged changes
#   $   something is stashed           ?  untracked files
#
# Cost: one `git status -b --porcelain` per prompt, plus one cheap
# `git rev-parse` for the stash check. The old .bash_prompt used ~6 git
# calls; the status line was already optimised this way and this reuses
# that approach.
#
# Layout is two lines on purpose: the full path is shown (%~), which on
# a deep tree easily runs 60+ columns, and a single-line prompt would
# leave almost no room to type. Line 2 is just the prompt character, so
# your command always starts at the same column.
#
# Tweaks:
#   - Literal absolute path instead of ~-abbreviated: change %~ to %d
#   - Single line: join the two PROMPT lines and drop the newline
#   - `command git` is used throughout so the ~/bin/git safe-git wrapper
#     is bypassed for these read-only calls — it would pass them through
#     anyway, but this skips the extra exec per prompt.

autoload -Uz add-zsh-hook

# Populated by the precmd hook below; rendered by PROMPT.
typeset -g __PROMPT_GIT=""

__prompt_git_info() {
    __PROMPT_GIT=""

    local status_output
    status_output="$(command git status -b --porcelain --ignore-submodules 2>/dev/null)" || return

    # Header line: `## branch...remote [ahead N, behind M]`
    local header="${status_output%%$'\n'*}"
    local branch="${header#\#\# }"
    branch="${branch%%...*}"
    branch="${branch%% *}"
    [[ -z "$branch" ]] && branch="(unknown)"

    local s="" n
    if [[ "$header" == *"ahead "* ]]; then
        n="${header#*ahead }"; n="${n%%[,\]]*}"
        s+="⇡${n}"
    fi
    if [[ "$header" == *"behind "* ]]; then
        n="${header#*behind }"; n="${n%%[,\]]*}"
        s+="⇣${n}"
    fi

    # Walk the porcelain lines and read the two status columns directly.
    # (Substring globbing over the whole blob can false-positive on
    # filenames that happen to contain the status letters.)
    local line x y staged=0 unstaged=0 untracked=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == '## '* ]] && continue
        x="${line[1]}"
        y="${line[2]}"
        if [[ "$x" == '?' ]]; then
            untracked=1
            continue
        fi
        [[ "$x" != ' ' ]] && staged=1
        [[ "$y" != ' ' ]] && unstaged=1
    done <<< "$status_output"

    (( staged ))    && s+='+'
    (( unstaged ))  && s+='!'
    (( untracked )) && s+='?'

    command git rev-parse --verify refs/stash &>/dev/null && s+='$'

    if [[ -n "$s" ]]; then
        __PROMPT_GIT=" on ${branch} [${s}]"
    else
        __PROMPT_GIT=" on ${branch}"
    fi
}

# Single line when it fits, two lines when the path would crowd what you
# type. Same adaptive behaviour as claude/statusline-command.sh, which
# picks its layout by comparing visible width against the terminal.
#
# Threshold = leave at least PROMPT_MIN_TYPING columns to type in. In
# ~ or ~/Documents the prompt stays on one line; deep in a repo it
# breaks so your command still starts at column 3.
: ${PROMPT_MIN_TYPING:=50}

__prompt_layout() {
    local plain="${(%):-%~}${__PROMPT_GIT}"
    if (( ${#plain} + 2 > COLUMNS - PROMPT_MIN_TYPING )); then
        __PROMPT_SEP=$'\n'
    else
        __PROMPT_SEP=' '
    fi
}

typeset -g __PROMPT_SEP=' '

__prompt_precmd() { __prompt_git_info; __prompt_layout; }
add-zsh-hook precmd __prompt_precmd

# PROMPT_SUBST lets ${__PROMPT_GIT} re-expand on every redraw. Colour is
# applied here rather than inside the variable: with PROMPT_SUBST the
# substituted text is not rescanned for %F escapes, so embedding them in
# the variable would print them literally.
setopt PROMPT_SUBST

PROMPT='%F{green}%~%f%F{magenta}${__PROMPT_GIT}%f${__PROMPT_SEP}%F{blue}❯%f '
