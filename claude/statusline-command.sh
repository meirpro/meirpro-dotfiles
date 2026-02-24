#!/usr/bin/env bash

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
model_name=$(echo "$input" | jq -r '.model.display_name')
session_id=$(echo "$input" | jq -r '.session_id')
short_session_id=$(echo "$session_id" | cut -c1-8)

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

    # Parse ahead/behind from header
    case "$header" in
        *\[ahead*behind*\]*) s+='↑↓' ;;
        *\[ahead*\]*)        s+='↑' ;;
        *\[behind*\]*)       s+='↓' ;;
    esac

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

# Format cost, lines, and time info
format_metrics() {
    local cost_info=""
    local lines_info=""
    local time_info=""

    # Format cost (round to appropriate decimal places)
    if [ "$total_cost" != "0" ] && [ "$total_cost" != "null" ]; then
        # Convert to cents for easier integer math, then format
        cost_cents=$(echo "$total_cost * 100" | bc 2>/dev/null || echo "0")
        if [ "$cost_cents" -ge 100 ]; then
            # >= $1.00, show 1 decimal place
            cost_formatted=$(printf "%.1f" "$total_cost")
        else
            # < $1.00, show 2 decimal places
            cost_formatted=$(printf "%.2f" "$total_cost")
        fi
        cost_info="💰\$${cost_formatted}"
    fi

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

    # Combine all metrics
    local metrics=""
    [ -n "$cost_info" ] && metrics="${metrics} ${cost_info}"
    [ -n "$lines_info" ] && metrics="${metrics} ${lines_info}"
    [ -n "$time_info" ] && metrics="${metrics} ${time_info}"

    echo "$metrics"
}

# Get metrics info
metrics_info=$(format_metrics)

# Get ccusage statusline data
ccusage_info=$(bun x ccusage statusline 2>/dev/null || echo "")

# Format the status line with colors (using printf for ANSI codes)
# Current folder name in dark green
status_line="\033[0;32m${working_dir}\033[0m\033[1;35m${git_info}\033[0m \033[2m(${model_name}) 🔑 ${short_session_id}\033[0m"

# Add metrics info if available
if [ -n "$metrics_info" ]; then
    status_line="${status_line}${metrics_info}"
fi

# Add ccusage info if available
if [ -n "$ccusage_info" ]; then
    status_line="${status_line} ${ccusage_info}"
fi

printf "%b" "$status_line"