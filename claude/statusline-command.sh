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

# Hide ccusage fields that are stuck at $0 (subscription users see today/block
# as $0 because no API charge, and burn rate is 0 when nothing is being billed).
# Patterns only match the all-zero form, so the moment any of these become
# non-zero (e.g. you blow past subscription quota), they reappear automatically.
#
# Delimiter is # (not |) and the literal pipe is written as [|]: BSD sed -E
# treats \| as the ERE alternation operator with no special "literal pipe"
# meaning, so " \| 🔥 ..." silently expands to "match one space OR ..." and
# eats the wrong character. The character class [|] removes the ambiguity.
ccusage_info=$(printf '%s' "$ccusage_info" | sed -E '
    s# / \$0+\.0+ today / \$0+\.0+ block \([^)]*\)##
    s# [|] 🔥 \$0+\.0+/hr##
')

# Build a two-line status. Line 1 packs identity + work-volume metrics
# (📝 lines, ⏱️ time) so they're always above the fold. Line 2 carries
# the cost / context-window data from ccusage (or the local cost fallback).
line1="\033[0;32m${working_dir}\033[0m\033[1;35m${git_info}\033[0m \033[2m${short_model} 🔑 ${short_session_id}\033[0m"
[ -n "$metrics_info" ] && line1="${line1}${metrics_info}"

line2=""
if [ -n "$ccusage_info" ]; then
    line2="${ccusage_info}"
elif [ -n "$local_cost_info" ]; then
    line2="${local_cost_info}"
fi

if [ -n "$line2" ]; then
    printf "%b\n%b" "$line1" "$line2"
else
    printf "%b" "$line1"
fi