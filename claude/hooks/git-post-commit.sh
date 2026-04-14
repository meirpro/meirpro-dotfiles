#!/bin/bash
# git-post-commit.sh — runs on every local commit via global core.hooksPath
# Writes commit metadata to ~/.claude/git-commits-queue.jsonl for later flush.
# Must be FAST — git commits wait for hook completion.

QUEUE_FILE="$HOME/.claude/git-commits-queue.jsonl"

REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_PATH" ] && exit 0

SHA=$(git rev-parse HEAD 2>/dev/null)
[ -z "$SHA" ] && exit 0

AUTHOR=$(git log -1 --format="%an <%ae>" "$SHA" 2>/dev/null)
MESSAGE=$(git log -1 --format="%s" "$SHA" 2>/dev/null)
TIMESTAMP=$(git log -1 --format="%aI" "$SHA" 2>/dev/null)
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
PARENT_SHAS=$(git log -1 --format="%P" "$SHA" 2>/dev/null)

# Numstat summary: insertions, deletions, files
read -r INS DEL FILES <<< "$(git show --numstat --format="" "$SHA" 2>/dev/null | \
    awk 'BEGIN {ins=0; del=0; files=0} {ins+=$1; del+=$2; files++} END {print ins, del, files}')"

PAYLOAD=$(jq -cn \
    --arg sha "$SHA" \
    --arg repo_path "$REPO_PATH" \
    --arg author "$AUTHOR" \
    --arg message "$MESSAGE" \
    --arg committed_at "$TIMESTAMP" \
    --arg branch "$BRANCH" \
    --arg parent_shas "$PARENT_SHAS" \
    --argjson files_changed "${FILES:-0}" \
    --argjson insertions "${INS:-0}" \
    --argjson deletions "${DEL:-0}" \
    '{
      sha: $sha,
      repo_path: $repo_path,
      author: $author,
      message: $message,
      committed_at: $committed_at,
      branch: $branch,
      parent_shas: ($parent_shas | split(" ") | map(select(length > 0))),
      files_changed: $files_changed,
      insertions: $insertions,
      deletions: $deletions
    }' 2>/dev/null)

[ -z "$PAYLOAD" ] && exit 0

echo "$PAYLOAD" >> "$QUEUE_FILE"

# Fall-through to repo-local post-commit hook if one exists
REPO_HOOK="$REPO_PATH/.git/hooks/post-commit"
if [ -x "$REPO_HOOK" ] && [ "$(readlink -f "$REPO_HOOK" 2>/dev/null || echo "$REPO_HOOK")" != "$(readlink -f "$0" 2>/dev/null || echo "$0")" ]; then
    "$REPO_HOOK" "$@"
fi

exit 0
