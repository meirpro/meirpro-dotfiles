#!/bin/bash
# flush_wrapup_queue.sh — retry queued wrapup segment pushes to cc.meir.pro
# Usage: bash ~/.claude/hooks/flush_wrapup_queue.sh
#
# Reads ~/.claude/wrapup-queue.jsonl one entry at a time. For each entry:
#   1. GET /api/wrapup_segments?session_id=..&segment_num=.. — if a row
#      already exists on CC, skip (manual backfills + in-queue duplicates
#      are safe). The CC endpoint has no replay guard, so dedupe is our job.
#   2. POST the payload to /api/wrapup_segments.
#   3. Successful + already-on-CC entries are dropped from the queue.
#      Failed entries stay queued for the next run.
#
# Residual queue is written via tempfile + rename so the file is never
# truncated mid-iteration (interrupted run leaves either the original
# or the new queue intact, never a half-written one).

QUEUE_FILE="$HOME/.claude/wrapup-queue.jsonl"
TRACK_KEY_FILE="$HOME/.claude/track-key"
API_BASE="https://cc.meir.pro/api/wrapup_segments"

if [ ! -f "$QUEUE_FILE" ]; then
    echo "no queue file"
    exit 0
fi

if [ ! -s "$QUEUE_FILE" ]; then
    rm -f "$QUEUE_FILE"
    echo "queue file empty"
    exit 0
fi

if [ ! -f "$TRACK_KEY_FILE" ]; then
    echo "missing track key" >&2
    exit 1
fi

QUEUE_FILE="$QUEUE_FILE" \
API_BASE="$API_BASE" \
TRACK_KEY_VAL=$(cat "$TRACK_KEY_FILE") \
python3 <<'PYEOF'
import json, os, sys, time
import urllib.request, urllib.error, urllib.parse

queue_file = os.environ["QUEUE_FILE"]
api_base = os.environ["API_BASE"]
track_key = os.environ["TRACK_KEY_VAL"].strip()
tmp_path = queue_file + ".tmp"

if not track_key:
    print("track key empty", file=sys.stderr)
    sys.exit(1)

headers = {
    "Content-Type": "application/json",
    "X-Track-Key": track_key,
}

def already_on_cc(session_id, segment_num):
    """Return True if CC already has a row for this (session, segment)."""
    qs = urllib.parse.urlencode({
        "session_id": session_id,
        "segment_num": segment_num,
    })
    req = urllib.request.Request(
        f"{api_base}?{qs}",
        headers={"X-Track-Key": track_key},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.loads(resp.read().decode())
        rows = body.get("wrapup_segments", [])
        return len(rows) > 0
    except Exception as e:
        # GET failed — treat as unknown and surface to caller so the entry
        # stays queued. We never assume "no" on a probe failure, that
        # would risk double-posting on the next run.
        raise RuntimeError(f"dedupe probe failed: {e}")

def post_payload(payload):
    req = urllib.request.Request(
        api_base,
        data=json.dumps(payload).encode(),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        if resp.status not in (200, 201):
            raise RuntimeError(f"HTTP {resp.status}")

processed = 0
posted = 0
deduped = 0
failed = 0
malformed = 0
seen_in_run = set()  # (session_id, segment_num) we've already drained this run
residual = []

with open(queue_file) as f:
    queue_lines = [ln for ln in f.read().splitlines() if ln.strip()]

for line in queue_lines:
    processed += 1
    try:
        payload = json.loads(line)
    except Exception:
        malformed += 1
        residual.append(line)  # keep unparseable lines so user can fix
        continue

    sid = payload.get("session_id")
    seg = payload.get("segment_num")
    if not sid or seg is None:
        malformed += 1
        residual.append(line)
        continue

    key = (sid, seg)

    # In-queue dedupe: if we already drained an identical (sid, seg) this
    # run, skip — CC will have the row from earlier in the loop.
    if key in seen_in_run:
        deduped += 1
        continue

    try:
        if already_on_cc(sid, seg):
            deduped += 1
            seen_in_run.add(key)
            continue
    except RuntimeError as e:
        failed += 1
        residual.append(line)
        print(f"  probe failed for {sid[:8]}/seg{seg}: {e}", file=sys.stderr)
        continue

    try:
        post_payload(payload)
        posted += 1
        seen_in_run.add(key)
    except Exception as e:
        failed += 1
        residual.append(line)
        print(f"  POST failed for {sid[:8]}/seg{seg}: {e}", file=sys.stderr)

# Write residual via tempfile + rename (atomic — no truncated mid-run state).
if residual:
    with open(tmp_path, "w") as f:
        for ln in residual:
            f.write(ln + "\n")
    os.replace(tmp_path, queue_file)
else:
    # Everything drained; remove the file so the next run sees "no queue".
    try:
        os.remove(queue_file)
    except FileNotFoundError:
        pass

print(json.dumps({
    "processed": processed,
    "posted": posted,
    "already_on_cc": deduped,
    "failed": failed,
    "malformed": malformed,
    "remaining_in_queue": len(residual),
}, indent=2))

# Exit non-zero if anything is still queued — easy hook into cron alerts.
sys.exit(0 if not residual else 1)
PYEOF
