#!/usr/bin/env bash

# Read JSON input from stdin
input=$(cat)

# === Telemetry write: dump live cost/tokens/rate-limits to session JSON file ===
# Best-effort, runs in background subshell so statusline rendering never blocks.
{
    SESSION_ID=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
    if [ -n "$SESSION_ID" ]; then
        SESSION_FILE="$HOME/.claude/sessions/${SESSION_ID}.json"
        if [ -f "$SESSION_FILE" ]; then
            printf '%s' "$input" | jq --slurpfile session "$SESSION_FILE" '
              ($session[0] // {}) * {
                telemetry: (($session[0].telemetry // {}) * {
                  live: {
                    model_id: .model.id,
                    model_display: .model.display_name,
                    claude_code_version: .version,
                    cost_usd: .cost.total_cost_usd,
                    wall_duration_ms: .cost.total_duration_ms,
                    api_duration_ms: .cost.total_api_duration_ms,
                    lines_added: .cost.total_lines_added,
                    lines_removed: .cost.total_lines_removed,
                    tokens_in: .context_window.total_input_tokens,
                    tokens_out: .context_window.total_output_tokens,
                    context_window_size: .context_window.context_window_size,
                    context_used_percentage: .context_window.used_percentage,
                    context_remaining_percentage: .context_window.remaining_percentage,
                    exceeds_200k_tokens: .exceeds_200k_tokens,
                    rate_limit_5h_pct: .rate_limits.five_hour.used_percentage,
                    rate_limit_5h_resets_at: .rate_limits.five_hour.resets_at,
                    rate_limit_7d_pct: .rate_limits.seven_day.used_percentage,
                    rate_limit_7d_resets_at: .rate_limits.seven_day.resets_at,
                    last_updated: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
                  }
                })
              }
            ' > "${SESSION_FILE}.tmp" 2>/dev/null && mv "${SESSION_FILE}.tmp" "$SESSION_FILE" 2>/dev/null
        fi
    fi
} >/dev/null 2>&1 &

# Extract data from JSON
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
model_name=$(echo "$input" | jq -r '.model.display_name')
session_id=$(echo "$input" | jq -r '.session_id')
short_session_id=$(echo "$session_id" | cut -c1-8)

# Shorten model display: "Opus 4.7 (1M context)" → "Opus 4.7 1M".
# sed leaves input unchanged if the pattern doesn't match, so any
# unexpected display_name format falls back to the full string.
short_model=$(printf '%s' "$model_name" | sed -E 's/^([A-Za-z]+)[[:space:]]+([0-9.]+)[[:space:]]+\(([0-9]+[KM])[[:space:]]+context\)$/\1\2 \3/')
[ -z "$short_model" ] && short_model="$model_name"

# Extract cost and metrics data
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
total_api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')

# Context window percentage — read from harness JSON, NOT ccusage. ccusage
# hardcodes its 🧠 percentage against a 200K denominator, so on the 1M Opus
# context model it reports 5x the real usage. The harness already computes
# the correct percentage knowing the actual model context size.
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Change to the current directory for git operations
cd "$current_dir" 2>/dev/null || true

# Git prompt function — 2 git calls (status + stash), down from 6
prompt_git() {
    local s=''
    local branchName=''

    # Single call: branch, ahead/behind, staged, unstaged, untracked
    local status_output
    status_output=$(git status -b --porcelain --ignore-submodules 2>/dev/null) || return

    # Parse branch name from first line: ## branch...remote [ahead N, behind N]
    local header="${status_output%%$'\n'*}"
    branchName="${header#\#\# }"
    branchName="${branchName%%...*}"
    branchName="${branchName%% *}"
    [ -z "$branchName" ] && branchName="(unknown)"

    # Parse ahead/behind from header (e.g. [ahead 3, behind 1])
    local ahead behind
    if [[ "$header" =~ ahead\ ([0-9]+) ]]; then
        ahead="${BASH_REMATCH[1]}"
        s+="⇡${ahead}"
    fi
    if [[ "$header" =~ behind\ ([0-9]+) ]]; then
        behind="${BASH_REMATCH[1]}"
        s+="⇣${behind}"
    fi

    # Parse file statuses from remaining lines
    local lines="${status_output#*$'\n'}"
    if [ "$lines" != "$status_output" ]; then
        case "$lines" in
            *[MADRC][\ ]*) s+='+' ;;  # staged
        esac
        case "$lines" in
            *\ [MD]*) s+='!' ;;  # unstaged
        esac
        case "$lines" in
            *\?\?*) s+='?' ;;  # untracked
        esac
    fi

    # Stash check (no way to get from git status)
    if git rev-parse --verify refs/stash &>/dev/null 2>&1; then
        s+='$'
    fi

    [ -n "${s}" ] && s=" [${s}]"
    echo " on ${branchName}${s}"
}

# Build status line
working_dir=$(basename "$current_dir")

# Get git info
git_info=$(prompt_git)

# Format lines and time info. Cost is computed below as a fallback; the
# primary cost display comes from ccusage (richer: session/today/block).
format_metrics() {
    local lines_info=""
    local time_info=""

    # Format lines info with colors
    if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
        if [ "$lines_removed" != "0" ]; then
            lines_info="📝 \033[0;32m+${lines_added}\033[0m/\033[0;31m-${lines_removed}\033[0m"
        else
            lines_info="📝 \033[0;32m+${lines_added}\033[0m"
        fi
    fi

    # Format duration helper function
    format_duration() {
        local duration_ms="$1"
        local time_seconds=$(echo "scale=0; $duration_ms / 1000" | bc 2>/dev/null || echo "0")

        if [ "$time_seconds" -ge 3600 ]; then
            # 1 hour or more: show hours and minutes (e.g., "6h58m")
            local hours=$(echo "scale=0; $time_seconds / 3600" | bc 2>/dev/null || echo "0")
            local minutes=$(echo "scale=0; ($time_seconds % 3600) / 60" | bc 2>/dev/null || echo "0")
            echo "${hours}h${minutes}m"
        elif [ "$time_seconds" -ge 60 ]; then
            # 1 minute or more but less than 1 hour: show minutes and seconds (e.g., "5m30s")
            local minutes=$(echo "scale=0; $time_seconds / 60" | bc 2>/dev/null || echo "0")
            local seconds=$(echo "scale=0; $time_seconds % 60" | bc 2>/dev/null || echo "0")
            echo "${minutes}m${seconds}s"
        else
            # Less than 1 minute: show seconds (e.g., "45s")
            echo "${time_seconds}s"
        fi
    }

    # Format time info (total session duration and API duration)
    local session_time=""
    local api_time=""

    if [ "$total_duration_ms" != "0" ] && [ "$total_duration_ms" != "null" ]; then
        local time_seconds=$(echo "scale=0; $total_duration_ms / 1000" | bc 2>/dev/null || echo "0")
        if [ "$time_seconds" -gt 0 ]; then
            session_time=$(format_duration "$total_duration_ms")
        fi
    fi

    if [ "$total_api_duration_ms" != "0" ] && [ "$total_api_duration_ms" != "null" ]; then
        local api_seconds=$(echo "scale=0; $total_api_duration_ms / 1000" | bc 2>/dev/null || echo "0")
        if [ "$api_seconds" -gt 0 ]; then
            api_time=$(format_duration "$total_api_duration_ms")
        fi
    fi

    # Combine session and API time
    if [ -n "$session_time" ] && [ -n "$api_time" ]; then
        time_info="⏱️ ${session_time} (API: ${api_time})"
    elif [ -n "$session_time" ]; then
        time_info="⏱️ ${session_time}"
    elif [ -n "$api_time" ]; then
        time_info="⏱️ API: ${api_time}"
    fi

    # Combine metrics
    local metrics=""
    [ -n "$lines_info" ] && metrics="${metrics} ${lines_info}"
    [ -n "$time_info" ] && metrics="${metrics} ${time_info}"

    echo "$metrics"
}

# Compute local cost as a FALLBACK only — used when ccusage is unavailable
# or returns nothing. ccusage's display is preferred because it includes
# today/block totals and the block-reset countdown.
local_cost_info=""
if [ "$total_cost" != "0" ] && [ "$total_cost" != "null" ]; then
    cost_cents=$(echo "$total_cost * 100" | bc 2>/dev/null || echo "0")
    cost_cents="${cost_cents%.*}"  # bc returns "74.00" — strip decimal so [ -ge ] gets an integer
    if [ "$cost_cents" -ge 100 ]; then
        cost_formatted=$(printf "%.1f" "$total_cost")
    else
        cost_formatted=$(printf "%.2f" "$total_cost")
    fi
    local_cost_info="💰 \$${cost_formatted}"
fi

# Get metrics info
metrics_info=$(format_metrics)

# Get ccusage statusline data — must pipe $input on stdin, otherwise
# ccusage prints "❌ No input provided" to STDOUT (not stderr) and that
# leaks into the statusline. Belt-and-suspenders: drop any ❌-prefixed
# error string in case ccusage emits one anyway.
ccusage_info=$(printf '%s' "$input" | bun x ccusage statusline 2>/dev/null || true)
case "$ccusage_info" in
    ❌*) ccusage_info="" ;;
esac

# ccusage prefixes its output with "🤖 <model> | " — strip it because the
# model is already shown on line 1.
case "$ccusage_info" in
    🤖*) ccusage_info="${ccusage_info#*| }" ;;
esac

# Trim ccusage output:
#   - " session" word after the cost figure (label is redundant — every
#     number on the bar is per-session)
#   - the today/block segment when both are $0 (subscription users see this)
#   - the burn rate when it's $0
#   - the entire 🧠 chunk: ccusage's percentage uses a 200K denominator
#     and is wrong on the 1M Opus model — we compute it ourselves below
#     from the harness's correct context_window data.
#
# Delimiter is # (not |) because BSD sed -E treats \| as the ERE
# alternation operator with no "literal pipe" meaning — " \| 🔥 ..."
# silently expands to "match one space OR ..." and eats the wrong char.
# The character class [|] removes the ambiguity.
ccusage_info=$(printf '%s' "$ccusage_info" | sed -E '
    s# session##
    s# / \$0+\.0+ today / \$0+\.0+ block \([^)]*\)##
    s# [|] 🔥 \$0+\.0+/hr##
    s# [|] 🧠 [0-9,]+ \([0-9]+%\)##
')

# Compute 🧠 locally so the percentage is correct for any model (including
# the 1M-context Opus variant ccusage doesn't know about, which it
# hardcodes against a 200K denominator).
ctx_info=""
[ -n "$ctx_pct" ] && ctx_info="🧠 ${ctx_pct}%"

# Heartbeat indicator — seconds since last_seen in the session file. Goes
# stale (climbs unboundedly) if the heartbeat hook stops firing, which is
# itself a useful symptom of the session-file clobber bug. Cheap: one jq
# call against a local file. Easy to remove if it stops earning its place.
heartbeat_info=""
session_file="$HOME/.claude/sessions/${session_id}.json"
if [ -f "$session_file" ]; then
    last_seen=$(jq -r '.last_seen // empty' "$session_file" 2>/dev/null)
    if [ -n "$last_seen" ]; then
        # TZ=UTC is required: BSD date treats trailing 'Z' as a literal
        # character (not a UTC marker) and otherwise interprets the time
        # in the local timezone, producing a 4-hour offset on EDT.
        last_seen_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_seen" +%s 2>/dev/null || echo 0)
        if [ "$last_seen_epoch" -gt 0 ]; then
            age_s=$(( $(date +%s) - last_seen_epoch ))
            if [ "$age_s" -ge 60 ]; then
                heartbeat_info="💗 $((age_s / 60))m$((age_s % 60))s"
            elif [ "$age_s" -ge 0 ]; then
                heartbeat_info="💗 ${age_s}s"
            fi
        fi
    fi
fi

# Two-part layout: identity (dir + git + model + session) and stats
# (metrics + cost + context + heartbeat). Rendered as one line when it
# fits, split to two lines on narrow terminals.
identity="\033[0;32m${working_dir}\033[0m\033[1;35m${git_info}\033[0m \033[2m${short_model} 🔑 ${short_session_id}\033[0m"

stats=""
[ -n "$metrics_info" ] && stats="${stats}${metrics_info}"
if [ -n "$ccusage_info" ]; then
    stats="${stats} ${ccusage_info}"
elif [ -n "$local_cost_info" ]; then
    stats="${stats} ${local_cost_info}"
fi
[ -n "$ctx_info" ] && stats="${stats} ${ctx_info}"
[ -n "$heartbeat_info" ] && stats="${stats} ${heartbeat_info}"
stats="${stats# }"  # strip leading space

single="${identity} ${stats}"

# Decide single vs split by visible length (ANSI stripped) vs terminal
# width. bash's ${#var} counts code points, so wide emojis undercount
# by ~1 cell each; add a small fudge for the handful of emojis we emit.
# tput needs /dev/tty because stdin is the JSON blob from the harness.
cols=$(exec 2>/dev/null; tput cols </dev/tty)
[ -z "$cols" ] && cols="${COLUMNS:-120}"
visible=$(printf '%b' "$single" | sed $'s/\x1b\\[[0-9;]*m//g')
visible_len=$(( ${#visible} + 8 ))

if [ -n "$stats" ] && [ "$visible_len" -gt "$cols" ]; then
    printf "%b\n%b" "$identity" "$stats"
else
    printf "%b" "$single"
fi