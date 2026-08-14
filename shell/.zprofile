
eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_ANALYTICS=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export POWERSHELL_TELEMETRY_OPTOUT=1
export GRADIO_ANALYTICS_ENABLED=False
export HF_HUB_DISABLE_TELEMETRY=1
# Stays ON globally. Claude Code is the one exception: its Remote Control
# refuses to start with this set, because RC gates on feature-flag evaluation
# and treats the flag service as tracking. Rather than drop the signal for
# every other tool, ~/bin/claude wraps the binary and unsets it for that one
# process — see claude/claude-wrapper. GUI apps (Claude desktop) never
# inherited this anyway; shell exports don't reach Finder/Dock launches.
export DO_NOT_TRACK=1
