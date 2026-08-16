#!/usr/bin/env bash
# Light - reviewed

# Create a new directory and enter it
function mkd() {
	mkdir -p "$@" && cd "$_";
}

# Change working directory to the top-most Finder window location
function cdf() { # short for `cdfinder`
	cd "$(osascript -e 'tell app "Finder" to POSIX path of (insertion location as alias)')";
}

# Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
function targz() {
	local tmpFile="${@%/}.tar";
	tar -cvf "${tmpFile}" --exclude=".DS_Store" "${@}" || return 1;

	size=$(
		stat -f"%z" "${tmpFile}" 2> /dev/null; # macOS `stat`
		stat -c"%s" "${tmpFile}" 2> /dev/null;  # GNU `stat`
	);

	local cmd="";
	if (( size < 52428800 )) && hash zopfli 2> /dev/null; then
		# the .tar file is smaller than 50 MB and Zopfli is available; use it
		cmd="zopfli";
	else
		if hash pigz 2> /dev/null; then
			cmd="pigz";
		else
			cmd="gzip";
		fi;
	fi;

	echo "Compressing .tar ($((size / 1000)) kB) using \`${cmd}\`…";
	"${cmd}" -v "${tmpFile}" || return 1;
	[ -f "${tmpFile}" ] && rm "${tmpFile}";

	zippedSize=$(
		stat -f"%z" "${tmpFile}.gz" 2> /dev/null; # macOS `stat`
		stat -c"%s" "${tmpFile}.gz" 2> /dev/null; # GNU `stat`
	);

	echo "${tmpFile}.gz ($((zippedSize / 1000)) kB) created successfully.";
}

# Determine size of a file or total size of a directory
function fs() {
	if du -b /dev/null > /dev/null 2>&1; then
		local arg=-sbh;
	else
		local arg=-sh;
	fi
	if [[ -n "$@" ]]; then
		du $arg -- "$@";
	else
		du $arg .[^.]* ./*;
	fi;
}

# Use Git’s colored diff when available
hash git &>/dev/null;
if [ $? -eq 0 ]; then
	function diff() {
		git diff --no-index --color-words "$@";
	}
fi;

# Create a data URL from a file
function dataurl() {
	local mimeType=$(file -b --mime-type "$1");
	if [[ $mimeType == text/* ]]; then
		mimeType="${mimeType};charset=utf-8";
	fi
	echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')";
}

# Start an HTTP server from a directory, optionally specifying the port
function server() {
	local port="${1:-8000}";
	sleep 1 && open "http://localhost:${port}/" &
	# Set the default Content-Type to `text/plain` instead of `application/octet-stream`
	# And serve everything as UTF-8 (although not technically correct, this doesn’t break anything for binary files)
	#
	# python3 port. Three differences from the python2 original:
	#   - SimpleHTTPServer became http.server
	#   - test() no longer reads argv; the port is a keyword arg
	#   - extensions_map is now a MINIMAL dict (only '', .py, .c, .h) rather
	#     than being seeded from the mimetypes table, so appending charset
	#     to it alone would leave .html/.css/.js without one. We seed it
	#     from mimetypes first to restore the original behaviour.
	# list(m) rather than m.items() because we mutate while iterating.
	python3 -c $'import sys, mimetypes, http.server as h;\nmimetypes.init();\nm = h.SimpleHTTPRequestHandler.extensions_map;\nm.update(mimetypes.types_map);\nm[""] = "text/plain";\nfor k in list(m):\n\tm[k] = m[k].split(";")[0] + ";charset=UTF-8";\nh.test(HandlerClass=h.SimpleHTTPRequestHandler, port=int(sys.argv[1]))' "$port";
}

# Start a PHP server from a directory, optionally specifying the port
# (Requires PHP 5.4.0+.)
function phpserver() {
	local port="${1:-4000}";
	local ip=$(ipconfig getifaddr en1);
	sleep 1 && open "http://${ip}:${port}/" &
	php -S "${ip}:${port}";
}

# Compare original and gzipped file size
function gz() {
	local origsize=$(wc -c < "$1");
	local gzipsize=$(gzip -c "$1" | wc -c);
	local ratio=$(echo "$gzipsize * 100 / $origsize" | bc -l);
	printf "orig: %d bytes\n" "$origsize";
	printf "gzip: %d bytes (%2.2f%%)\n" "$gzipsize" "$ratio";
}

# Run `dig` and display the most useful info
function digga() {
	dig +nocmd "$1" any +multiline +noall +answer;
}
# GOTTA_TRY

# Show all the names (CNs and SANs) listed in the SSL certificate
# for a given domain
function getcertnames() {
	if [ -z "${1}" ]; then
		echo "ERROR: No domain specified.";
		return 1;
	fi;

	local domain="${1}";
	echo "Testing ${domain}…";
	echo ""; # newline

	local tmp=$(echo -e "GET / HTTP/1.0\nEOT" \
		| openssl s_client -connect "${domain}:443" -servername "${domain}" 2>&1);

	if [[ "${tmp}" = *"-----BEGIN CERTIFICATE-----"* ]]; then
		local certText=$(echo "${tmp}" \
			| openssl x509 -text -certopt "no_aux, no_header, no_issuer, no_pubkey, \
			no_serial, no_sigdump, no_signame, no_validity, no_version");
		echo "Common Name:";
		echo ""; # newline
		echo "${certText}" | grep "Subject:" | sed -e "s/^.*CN=//" | sed -e "s/\/emailAddress=.*//";
		echo ""; # newline
		echo "Subject Alternative Name(s):";
		echo ""; # newline
		echo "${certText}" | grep -A 1 "Subject Alternative Name:" \
			| sed -e "2s/DNS://g" -e "s/ //g" | tr "," "\n" | tail -n +2;
		return 0;
	else
		echo "ERROR: Certificate not found.";
		return 1;
	fi;
}

# Normalize `open` across Linux, macOS, and Windows.
# This is needed to make the `o` function (see below) cross-platform.
if [ ! $(uname -s) = 'Darwin' ]; then
	if grep -q Microsoft /proc/version; then
		# Ubuntu on Windows using the Linux subsystem
		alias open='explorer.exe';
	else
		alias open='xdg-open';
	fi
fi

# `o` with no arguments opens the current directory, otherwise opens the given
# location
function o() {
	if [ $# -eq 0 ]; then
		open .;
	else
		open "$@";
	fi;
}

# `tre` is a shorthand for `tree` with hidden files and color enabled, ignoring
# the `.git` directory, listing directories first. The output gets piped into
# `less` with options to preserve color and line numbers, unless the output is
# small enough for one screen.
function tre() {
	tree -aC -I '.git|node_modules|bower_components' --dirsfirst "$@" | less -FRNX;
}

# Claude Code shortcut with resume support
# Uses claude-timed wrapper when available, falls back to plain claude
# Usage: cld [options] [query]
#        cld -r <partial-session-id> [query]  # Resume session with partial ID (searches for match)
function cld() {
	local cmd="claude"
	if command -v claude-timed &>/dev/null; then
		cmd="claude-timed"
		printf '\033[32m⏱ Timed session\033[0m — stats: \033[36mclaude-timed --stats today\033[0m\n' >&2
	else
		printf '\033[33m[cld] claude-timed not found, using claude directly\033[0m\n' >&2
	fi

	if [[ "$1" == "-r" ]]; then
		shift
		local partial_id="$1"

		# If no ID provided, use interactive picker
		if [[ -z "$partial_id" ]]; then
			"$cmd" --resume
			return
		fi

		# Find the current project directory based on working directory
		local project_dir=$(pwd | sed 's/\//-/g')
		local sessions_dir="$HOME/.claude/projects/$project_dir"

		# Search for sessions matching the partial ID
		local matches=()
		if [[ -d "$sessions_dir" ]]; then
			while IFS= read -r file; do
				local basename=$(basename "$file" .jsonl)
				if [[ "$basename" == agent-* ]]; then
					continue  # Skip agent files
				fi
				matches+=("$basename")
			done < <(find "$sessions_dir" -maxdepth 1 -name "${partial_id}*.jsonl" -type f)
		fi

		# If exactly one match found, use it
		if [[ ${#matches[@]} -eq 1 ]]; then
			shift  # Remove the partial ID from arguments
			"$cmd" --resume "${matches[@]:0:1}" "$@"  # [@]:0:1 = first elem in BOTH bash(0-idx) and zsh(1-idx); ${matches[0]} is empty in zsh
		elif [[ ${#matches[@]} -gt 1 ]]; then
			echo "Multiple sessions found matching '$partial_id':"
			printf '  %s\n' "${matches[@]}"
			echo "Please provide more characters to uniquely identify the session."
		else
			# No matches found, maybe it's a full ID or try interactive
			shift
			"$cmd" --resume "$partial_id" "$@"
		fi
	else
		"$cmd" "$@"
	fi
}

# Unset the alias version of cld if it exists (since aliases load before functions)
unalias cld 2>/dev/null


# ─────────────────────────────────────────────────────────────────────
# ghmp — merge a GitHub PR and fast-forward the local target branch.
# Refuses to merge when GitHub reports the PR is not cleanly mergeable
# (conflicts, etc.).
#
# Merges with a MERGE COMMIT by default, keeping every commit and its
# original author. Pass --squash to collapse the branch into one commit.
#
# Usage:
#   ghmp <pr-num>                   # pulls into the current branch
#   ghmp <pr-num> <local-branch>    # pulls into the named branch
#   ghmp --squash <pr-num>          # collapse to a single commit
#   ghmp --wait <pr-num> [branch]   # also wait for PR-level CI
#                                   #   to conclude SUCCESS before merging
# Flags may be combined and given in any order.
#
# Default behavior merges immediately on a green-mergeable PR — saves
# 3-ish minutes of redundant CI (the post-merge push runs CI again on
# the target branch anyway). Use --wait when you want the PR-level
# safety net (e.g. a long branch you don't fully trust).
#
# Refuses on:
#   - non-MERGEABLE mergeability (CONFLICTING, UNKNOWN, BEHIND)
#   - mergeStateStatus indicating BLOCKED / DIRTY / BEHIND
#   - --wait mode: CI conclusion ≠ SUCCESS
# Tolerates transient gh API errors (502/503) by retrying.
# ─────────────────────────────────────────────────────────────────────
function ghmp() {
	local wait_ci=0
	local squash=0
	while [[ "$1" == --* ]]; do
		case "$1" in
			--wait) wait_ci=1 ;;
			--squash) squash=1 ;;
			--merge) squash=0 ;;
			*)
				echo "ghmp: unknown flag $1" >&2
				echo "usage: ghmp [--wait] [--squash] <pr-num> [local-branch]" >&2
				return 64
				;;
		esac
		shift
	done
	local pr="$1"
	local branch="${2:-$(git branch --show-current)}"

	if [[ -z "$pr" ]]; then
		echo "usage: ghmp [--wait] [--squash] <pr-num> [local-branch]" >&2
		return 64
	fi
	if [[ -z "$branch" ]]; then
		echo "ghmp: no target branch (not on a branch and no second arg)" >&2
		return 64
	fi

	# 1. Check mergeability. Right after a push GitHub takes a moment to
	# recompute — observed sequence: UNKNOWN → momentary CONFLICTING →
	# MERGEABLE. We give CONFLICTING and UNKNOWN a short grace period
	# (12× 5 s = 1 min total) so the flicker doesn't bail us out
	# prematurely; a real conflict will still be reported.
	echo "→ checking mergeability of PR #$pr"
	local mergeable="" mergeStateStatus="" tries=0
	while (( tries < 12 )); do
		local view
		if view=$(gh pr view "$pr" --json mergeable,mergeStateStatus,state 2>/dev/null); then
			mergeable=$(echo "$view" | jq -r '.mergeable // ""')
			mergeStateStatus=$(echo "$view" | jq -r '.mergeStateStatus // ""')
			local state=$(echo "$view" | jq -r '.state // ""')
			if [[ "$state" == "MERGED" ]]; then
				echo "✓ PR #$pr already merged."
				break
			fi
			if [[ "$state" == "CLOSED" ]]; then
				echo "✗ PR #$pr is closed." >&2
				return 1
			fi
			# Stable enough to act on: MERGEABLE → proceed. CONFLICTING
			# only after the grace window has expired (still flickering
			# from a recent push otherwise).
			if [[ "$mergeable" == "MERGEABLE" ]]; then
				break
			fi
		else
			echo "  (gh API hiccup — retrying)" >&2
		fi
		(( tries++ ))
		sleep 5
	done

	if [[ "$mergeable" == "CONFLICTING" ]]; then
		echo "✗ PR #$pr is CONFLICTING — rebase first, then re-run." >&2
		return 1
	fi
	if [[ "$mergeable" != "MERGEABLE" ]]; then
		echo "✗ PR #$pr mergeable=$mergeable mergeStateStatus=$mergeStateStatus" >&2
		echo "  Refusing to merge in an uncertain state." >&2
		return 1
	fi

	# 2. (--wait only) wait for PR-level CI to conclude before merging.
	if (( wait_ci )); then
		echo "→ waiting for CI on PR #$pr (--wait mode)"
		while :; do
			local rollup
			if rollup=$(gh pr view "$pr" --json statusCheckRollup --jq \
				'[.statusCheckRollup[]? | .conclusion // ""] | join(",")' 2>/dev/null); then
				if echo "$rollup" | grep -qE "SUCCESS|FAILURE|CANCELLED|TIMED_OUT"; then
					break
				fi
			else
				echo "  (gh API hiccup — retrying)" >&2
			fi
			sleep 20
		done
		local conclusion
		conclusion=$(gh pr view "$pr" --json statusCheckRollup --jq \
			'[.statusCheckRollup[]? | .conclusion] | first // "EMPTY"')
		if [[ "$conclusion" != "SUCCESS" ]]; then
			echo "✗ CI conclusion: $conclusion — refusing to merge." >&2
			gh pr view "$pr" --json statusCheckRollup --jq \
				'.statusCheckRollup[]? | "  - \(.name // "?"): \(.conclusion // .status)"' >&2
			return 1
		fi
	fi

	# 3. Merge. Default PRESERVES history (a merge commit); --squash opts
	# into collapsing the branch to one commit.
	#
	# The default flipped 2026-08-16. Squashing is right for a scratch branch
	# whose intermediate commits are noise, but it was wrong as the DEFAULT:
	# it discards per-commit reasoning on any branch where the commits were
	# authored to be read, and it rewrites authorship to the PR author — the
	# very thing that blocks sweetrobo/crm's deploy gate when you merge
	# someone else's PR. A merge commit keeps both.
	if (( squash )); then
		echo "→ merging PR #$pr (squash)"
		gh pr merge "$pr" --squash || return $?
	else
		echo "→ merging PR #$pr (merge commit, history preserved)"
		gh pr merge "$pr" --merge || return $?
	fi

	# 4. Fast-forward the local target branch WITHOUT moving HEAD.
	#
	# This used to `git checkout "$branch"` first. That is wrong on a shared
	# working tree: HEAD is a shared resource, so switching it yanks every
	# parallel agent and the user onto another branch mid-edit. safe-git
	# rule 7 (added 2026-07-21) refuses exactly that, which made every ghmp
	# run fail its ff-pull — the merge landed server-side but the local
	# branch never advanced. The old CLAUDE.md note blaming worktrees for
	# "could not checkout main" was really this, one layer down.
	#
	# `git fetch origin <branch>:<branch>` advances the local ref directly
	# and leaves HEAD alone. Git refuses it when the target is checked out
	# (here or in another worktree), so handle the current-branch case with
	# a plain ff-pull, which needs no checkout either.
	echo "→ advancing $branch"
	if [[ "$branch" == "$(git branch --show-current)" ]]; then
		git pull --ff-only && git log --oneline -3
	elif git fetch origin "$branch:$branch"; then
		git log --oneline -3 "$branch"
	else
		echo "ghmp: could not fast-forward $branch — it may be checked out in another worktree." >&2
		echo "  The merge itself succeeded; only the local ref lagged." >&2
		return 1
	fi
}


# ─────────────────────────────────────────────────────────────────────
# claude-sounds — master switch for Claude Code hook sounds.
# Flips "enabled" in ~/.claude/audio/sounds.json; the play_sound.py hook
# no-ops on every event when off. Thin wrapper over the standalone script
# (claude/hooks/claude-sounds in this repo, also symlinked to ~/bin so it
# works in every shell + non-interactive sessions, like git/ghmp).
#
# Usage: claude-sounds [on|off|toggle|status]
# ─────────────────────────────────────────────────────────────────────
function claude-sounds() {
	"$HOME/.claude/hooks/claude-sounds" "$@"
}
