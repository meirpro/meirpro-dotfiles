#!/bin/bash
# scan_git.sh — walk git log(s) and batch-POST commits to CC API
# Usage:
#   scan_git.sh <repo_path>                     # incremental (uses checkpoint)
#   scan_git.sh <repo_path> --since=<date>      # full history from date
#   scan_git.sh --all-tracked                   # walk all repos from ~/Documents/GitHub
#   scan_git.sh --all-tracked --since=<date>    # full history on all tracked

set -eu

STATE_FILE="$HOME/.claude/scan-state.json"
TRACK_KEY_FILE="$HOME/.claude/track-key"
API_URL="https://cc.meir.pro/api/commits/batch"
PROJECTS_URL="https://cc.meir.pro/api/projects"

[ -f "$TRACK_KEY_FILE" ] || { echo "missing track-key" >&2; exit 1; }
TRACK_KEY=$(cat "$TRACK_KEY_FILE")

scan_repo() {
    local repo_path="$1"
    local since_arg="${2:-}"

    [ -d "$repo_path/.git" ] || { echo "not a git repo: $repo_path" >&2; return 0; }

    local branch
    branch=$(git -C "$repo_path" branch --show-current 2>/dev/null || echo "")

    local log_range
    if [ -n "$since_arg" ]; then
        log_range="$since_arg"
    else
        local last_sha=""
        if [ -f "$STATE_FILE" ]; then
            last_sha=$(jq -r --arg k "$repo_path" '.[$k] // empty' "$STATE_FILE" 2>/dev/null)
        fi
        if [ -n "$last_sha" ]; then
            if git -C "$repo_path" rev-parse --verify "$last_sha" >/dev/null 2>&1; then
                log_range="${last_sha}..HEAD"
            else
                log_range="HEAD"
            fi
        else
            log_range="HEAD"
        fi
    fi

    git -C "$repo_path" log "$log_range" --format="%H%x00%aI%x00%an <%ae>%x00%s%x00%P" --no-merges 2>/dev/null | \
    TRACK_KEY="$TRACK_KEY" API_URL="$API_URL" REPO_PATH="$repo_path" BRANCH="$branch" \
    python3 -c "$(cat <<'PYEOF'
import json, os, sys, subprocess
import urllib.request, urllib.error

TRACK_KEY = os.environ['TRACK_KEY']
API_URL = os.environ['API_URL']
REPO_PATH = os.environ['REPO_PATH']
BRANCH = os.environ['BRANCH']

BATCH_SIZE = 100
batch = []
total_inserted = 0
total_skipped = 0

def flush(batch):
    global total_inserted, total_skipped
    if not batch:
        return
    data = json.dumps({'commits': batch}).encode()
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={
            'Content-Type': 'application/json',
            'X-Track-Key': TRACK_KEY,
            'User-Agent': 'cc-scan-git/1.0',
        },
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read())
            total_inserted += body.get('inserted', 0)
            total_skipped += body.get('skipped', 0)
    except Exception as e:
        print(f'batch failed: {e}', file=sys.stderr)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split('\x00')
    if len(parts) < 5:
        continue
    sha, committed_at, author, message, parents_str = parts[:5]

    try:
        numstat = subprocess.run(
            ['git', '-C', REPO_PATH, 'show', '--numstat', '--format=', sha],
            capture_output=True, text=True, timeout=5
        ).stdout
        ins, dels, files = 0, 0, 0
        for nl in numstat.strip().split('\n'):
            p = nl.split('\t')
            if len(p) >= 3:
                try: ins += int(p[0])
                except: pass
                try: dels += int(p[1])
                except: pass
                files += 1
    except Exception:
        ins, dels, files = 0, 0, 0

    batch.append({
        'sha': sha,
        'repo_path': REPO_PATH,
        'committed_at': committed_at,
        'author': author,
        'message': message,
        'branch': BRANCH,
        'parent_shas': [p for p in parents_str.split(' ') if p],
        'files_changed': files,
        'insertions': ins,
        'deletions': dels,
    })
    if len(batch) >= BATCH_SIZE:
        flush(batch)
        batch = []

flush(batch)

print(f'{REPO_PATH}: inserted={total_inserted}, skipped={total_skipped}')
PYEOF
)"

    local head_sha
    head_sha=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null)
    if [ -n "$head_sha" ]; then
        if [ -f "$STATE_FILE" ]; then
            local updated
            updated=$(jq --arg k "$repo_path" --arg v "$head_sha" '. + {($k): $v}' "$STATE_FILE" 2>/dev/null)
            if [ -n "$updated" ]; then
                echo "$updated" > "$STATE_FILE"
            fi
        else
            echo "{\"$repo_path\": \"$head_sha\"}" > "$STATE_FILE"
        fi
    fi
}

SINCE_ARG=""
REPO_ARG=""
ALL_TRACKED=0

while [ $# -gt 0 ]; do
    case "$1" in
        --all-tracked)
            ALL_TRACKED=1
            shift
            ;;
        --since=*)
            SINCE_ARG="$1"
            shift
            ;;
        --since)
            SINCE_ARG="--since=$2"
            shift 2
            ;;
        *)
            REPO_ARG="$1"
            shift
            ;;
    esac
done

if [ "$ALL_TRACKED" -eq 1 ]; then
    for repo in /Users/lightwing/Documents/GitHub/*/; do
        repo_path="${repo%/}"
        if [ -d "$repo_path/.git" ]; then
            scan_repo "$repo_path" "$SINCE_ARG"
        fi
    done
elif [ -n "$REPO_ARG" ]; then
    scan_repo "$REPO_ARG" "$SINCE_ARG"
else
    echo "Usage: scan_git.sh <repo_path> [--since=<date>]" >&2
    echo "       scan_git.sh --all-tracked [--since=<date>]" >&2
    exit 1
fi
