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
	python -c $'import SimpleHTTPServer;\nmap = SimpleHTTPServer.SimpleHTTPRequestHandler.extensions_map;\nmap[""] = "text/plain";\nfor key, value in map.items():\n\tmap[key] = value + ";charset=UTF-8";\nSimpleHTTPServer.test();' "$port";
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
# Usage: cld [options] [query]
#        cld -r <partial-session-id> [query]  # Resume session with partial ID (searches for match)
function cld() {
	if [[ "$1" == "-r" ]]; then
		shift
		local partial_id="$1"

		# If no ID provided, use interactive picker
		if [[ -z "$partial_id" ]]; then
			claude --resume
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
			claude --resume "${matches[0]}" "$@"
		elif [[ ${#matches[@]} -gt 1 ]]; then
			echo "Multiple sessions found matching '$partial_id':"
			printf '  %s\n' "${matches[@]}"
			echo "Please provide more characters to uniquely identify the session."
		else
			# No matches found, maybe it's a full ID or try interactive
			shift
			claude --resume "$partial_id" "$@"
		fi
	else
		claude "$@"
	fi
}

# Unset the alias version of cld if it exists (since aliases load before functions)
unalias cld 2>/dev/null


# ─────────────────────────────────────────────────────────────────────
# ghmp — wait for a GitHub PR's CI, merge it (squash), then fast-forward
# the local target branch.
#
# Usage:
#   ghmp <pr-num>                  # pulls into the current branch after merge
#   ghmp <pr-num> <local-branch>   # pulls into the named branch
#
# Refuses to merge if CI does not conclude SUCCESS. Polls every 20s.
# Designed to live in the dotfiles so any agent (or you) can reach for
# it instead of re-typing the `until ... && gh pr merge && git pull`
# pipeline by hand every time.
# ─────────────────────────────────────────────────────────────────────
function ghmp() {
	local pr="$1"
	local branch="${2:-$(git branch --show-current)}"

	if [[ -z "$pr" ]]; then
		echo "usage: ghmp <pr-num> [local-branch]" >&2
		return 64
	fi
	if [[ -z "$branch" ]]; then
		echo "ghmp: no target branch (not on a branch and no second arg)" >&2
		return 64
	fi

	echo "→ waiting for CI on PR #$pr"
	# Loop until the rollup has SOMETHING terminal in it. New PRs may
	# show empty rollup for a few seconds while Actions queues; that's
	# why we don't trust just the first poll. Transient API failures
	# (502/503, network blips) are tolerated — the next iteration just
	# retries instead of exiting the caller.
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

	echo "→ merging PR #$pr (squash)"
	gh pr merge "$pr" --squash || return $?

	echo "→ pulling $branch"
	git checkout "$branch" >/dev/null 2>&1 || {
		echo "ghmp: could not checkout $branch" >&2
		return 1
	}
	git pull --ff-only && git log --oneline -3
}
