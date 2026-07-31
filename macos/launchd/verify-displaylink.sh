#!/usr/bin/env bash
#
# Health check for the pro.meir.displaylink LaunchAgent.
#
# Answers two questions that `launchctl print` alone can't:
#   1. Did it actually come up at boot, or has it been silently flapping?
#   2. Is it still *working* — i.e. are the dock's displays live — as opposed
#      to merely running? Screen Recording permission can be revoked without
#      killing the process, in which case DisplayLink runs but drives nothing.
#
# Usage:  ./macos/launchd/verify-displaylink.sh
# Exit:   0 all checks pass, 1 at least one FAIL (WARN alone still exits 0)

set -uo pipefail

LABEL="pro.meir.displaylink"
BIN="/Applications/DisplayLink Manager.app/Contents/MacOS/DisplayLinkUserAgent"
ERR_LOG="$HOME/Library/Logs/${LABEL}.err.log"
SERVICE="gui/$(id -u)/${LABEL}"

fails=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fails=$((fails + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

section "Agent registration"

if [[ -L "$HOME/Library/LaunchAgents/${LABEL}.plist" ]]; then
	pass "symlinked into ~/Library/LaunchAgents (repo edits stay live)"
elif [[ -f "$HOME/Library/LaunchAgents/${LABEL}.plist" ]]; then
	warn "plist is a real file, not a symlink — repo edits will NOT propagate"
else
	fail "not installed in ~/Library/LaunchAgents — see README Install"
fi

print_out=$(launchctl print "$SERVICE" 2>&1)
if [[ $? -ne 0 ]]; then
	fail "service not loaded — run: launchctl bootstrap gui/\$UID ~/Library/LaunchAgents/${LABEL}.plist"
	echo
	exit 1
fi
pass "loaded as ${SERVICE}"

state=$(sed -n 's/^[[:space:]]*state = \(.*\)/\1/p' <<<"$print_out" | head -1)
pid=$(sed -n 's/^[[:space:]]*pid = \([0-9]*\).*/\1/p' <<<"$print_out" | head -1)
[[ "$state" == "running" ]] && pass "state = running (pid ${pid})" || fail "state = ${state:-unknown}"

section "Restart / flapping history"

# launchd counts every respawn. A KeepAlive job that is healthy should show 0
# here on a machine that has not slept-and-woken much; a climbing number means
# it is dying and being restarted (check the err log below).
runs=$(sed -n 's/^[[:space:]]*runs = \([0-9]*\)/\1/p' <<<"$print_out" | head -1)
last_exit=$(sed -n 's/^[[:space:]]*last exit code = \(.*\)/\1/p' <<<"$print_out" | head -1)

if [[ "$last_exit" == "(never exited)" ]]; then
	pass "never exited since load"
elif [[ "$last_exit" == "0" ]]; then
	warn "has exited cleanly at least once (runs=${runs:-?}) — KeepAlive restarted it"
else
	warn "last exit code = ${last_exit} (runs=${runs:-?}) — check the err log"
fi

section "Came up at boot?"

if [[ -n "$pid" ]]; then
	# NB: anchor on "{ sec =" — a greedy .* matches the later "usec =" instead.
	boot_epoch=$(sysctl -n kern.boottime | sed -n 's/^{ sec = \([0-9]*\).*/\1/p')
	proc_start=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//')
	proc_epoch=$(date -j -f "%a %b %e %T %Y" "$proc_start" "+%s" 2>/dev/null)
	if [[ -n "$proc_epoch" && -n "$boot_epoch" ]]; then
		delta=$((proc_epoch - boot_epoch))
		up_days=$(( (($(date +%s) - boot_epoch)) / 86400 ))
		if (( delta < 300 )); then
			pass "started ${delta}s after boot — launched at login, not by hand"
		else
			warn "started ${delta}s after boot (uptime ${up_days}d) — expected if you reloaded it manually; reboot to confirm boot behaviour"
		fi
	fi
fi

section "Process topology"

# Exactly one agent process, owned by launchd (ppid 1). Two means DisplayLink's
# own login item is ALSO enabled and started a second, LaunchServices-launched
# copy — disable it in System Settings (see README).
procs=()
while IFS= read -r _p; do [[ -n "$_p" ]] && procs+=("$_p"); done \
	< <(pgrep -f "DisplayLinkUserAgent" 2>/dev/null)
case "${#procs[@]}" in
0) fail "no DisplayLinkUserAgent process running" ;;
1)
	ppid=$(ps -o ppid= -p "${procs[0]}" | tr -d ' ')
	if [[ "$ppid" == "1" ]]; then
		pass "exactly one process (pid ${procs[0]}), owned by launchd"
	else
		warn "one process but ppid=${ppid}, not launchd — started outside the agent?"
	fi
	;;
*) fail "${#procs[@]} DisplayLinkUserAgent processes — DisplayLink's login item is probably still enabled (see README)" ;;
esac

pgrep -qf "DisplayLinkXpcService" &&
	pass "DisplayLinkXpcService running (the component that drives the displays)" ||
	fail "DisplayLinkXpcService not running — displays will not work"

section "Functional check (are displays actually driven?)"

# The real test. A DisplayLink-driven display appears in SPDisplaysDataType
# with no "Connection Type" line, unlike built-in/DisplayPort panels.
displays=$(system_profiler SPDisplaysDataType 2>/dev/null)
external=$(grep -cE '^        [A-Za-z].*:$' <<<"$displays")
if (( external > 1 )); then
	pass "${external} display(s) attached ($((external - 1)) external):"
	grep -E '^        [A-Za-z].*:$' <<<"$displays" | sed 's/^ */         /'
else
	warn "no external displays — either the Anker dock is unplugged, or Screen Recording permission was revoked (see below)"
fi

section "Screen Recording permission"

# TCC.db is unreadable without Full Disk Access, so this is inferred, not read:
# DisplayLink running + XPC alive + zero external displays while the dock is
# plugged in is the signature of a revoked grant.
if (( external > 1 )); then
	pass "inferred OK — displays are being driven, so capture is permitted"
else
	warn "cannot confirm. If the dock IS plugged in, re-grant under:"
	echo "         System Settings → Privacy & Security → Screen Recording"
	echo "         then: launchctl kickstart -k ${SERVICE}"
fi

section "Recent errors"

if [[ -s "$ERR_LOG" ]]; then
	warn "last 5 lines of ~${ERR_LOG#$HOME}:"
	tail -5 "$ERR_LOG" | sed 's/^/         /'
else
	pass "error log empty"
fi

printf '\n'
if (( fails > 0 )); then
	printf '\033[31m%d check(s) failed.\033[0m See macos/launchd/README.md.\n\n' "$fails"
	exit 1
fi
printf '\033[32mAll checks passed.\033[0m\n\n'
