#!/usr/bin/env python3
"""
Shared session-file resolver for Claude Code hook scripts.

Handles two file formats in ~/.claude/sessions/:
- UUID-named: <session_id>.json with snake_case fields (created by session_tracker.sh)
- PID-named:  <pid>.json with camelCase fields (created by Claude Code natively)

The fast path is `<session_id>.json`. When a hook is called for a session whose
UUID file doesn't exist (e.g., session predates the tracker hook installation),
we scan PID-named files for one whose `sessionId` field matches, then migrate
it to UUID format in place.
"""

import glob
import json
import os
import sys
from datetime import datetime, timezone

SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")


def ts_to_iso(ms):
    """Convert ms epoch (int or string) to ISO 8601 UTC string."""
    return datetime.fromtimestamp(int(ms) / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def migrate_record(d):
    """Convert a record from any known format to canonical UUID-format dict.

    Preserves all known fields. Adds a `migrated_from` marker if the source
    was PID format, so we can audit migrations later.
    """
    sid = d.get("session_id") or d.get("sessionId")
    if not sid:
        return None

    out = {
        "session_id": sid,
        "start": d.get("start") or (ts_to_iso(d["startedAt"]) if "startedAt" in d else now_iso()),
        "last_seen": d.get("last_seen") or d.get("start") or (ts_to_iso(d["startedAt"]) if "startedAt" in d else now_iso()),
        "active_minutes": d.get("active_minutes", 0),
    }

    project_path = d.get("project_path") or d.get("cwd") or ""
    out["project_path"] = project_path
    out["project"] = d.get("project") or (os.path.basename(project_path.rstrip("/")) if project_path else "?")
    out["branch"] = d.get("branch", "n/a")
    out["recent_commits"] = d.get("recent_commits", [])
    out["uncommitted_changes"] = d.get("uncommitted_changes", 0)

    # Preserve wrapup state
    if "last_wrapup" in d:
        out["last_wrapup"] = d["last_wrapup"]
    if "wrapup_count" in d:
        out["wrapup_count"] = d["wrapup_count"]

    # Mark migration source for auditing
    if "pid" in d and "migrated_from_pid" not in d:
        out["migrated_from_pid"] = d["pid"]
        if d.get("active_minutes", 0) == 0 and "startedAt" in d:
            out["migration_note"] = "active_minutes lost — heartbeat orphan before fix"

    return out


def resolve_session_file(session_id, create_if_missing=False):
    """Return the path to the UUID-format file for this session_id.

    Tries:
    1. <session_id>.json (fast path)
    2. Scan *.json for one whose sessionId/session_id matches; migrate to UUID format
    3. If create_if_missing, create a fresh UUID file with minimal fields
    4. Return None if nothing found and create_if_missing is False

    Side effect: when a PID-format file is found and migrated, the original PID
    file is removed and the new UUID file is written.
    """
    if not os.path.isdir(SESSIONS_DIR):
        os.makedirs(SESSIONS_DIR, exist_ok=True)

    uuid_path = os.path.join(SESSIONS_DIR, f"{session_id}.json")
    if os.path.isfile(uuid_path):
        return uuid_path

    # Scan for orphan match
    for path in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        try:
            with open(path) as f:
                data = json.load(f)
        except Exception:
            continue
        sid = data.get("session_id") or data.get("sessionId")
        if sid != session_id:
            continue
        # Found it — migrate
        migrated = migrate_record(data)
        if migrated is None:
            continue
        with open(uuid_path, "w") as f:
            json.dump(migrated, f, indent=2)
        if os.path.abspath(path) != os.path.abspath(uuid_path):
            try:
                os.remove(path)
            except OSError:
                pass
        return uuid_path

    if create_if_missing:
        # Caller wants us to create a fresh file
        fresh = {
            "session_id": session_id,
            "start": now_iso(),
            "last_seen": now_iso(),
            "active_minutes": 0,
            "project": "?",
            "project_path": "?",
            "branch": "n/a",
            "recent_commits": [],
            "uncommitted_changes": 0,
        }
        with open(uuid_path, "w") as f:
            json.dump(fresh, f, indent=2)
        return uuid_path

    return None


def migrate_all_orphans():
    """One-shot: find all PID-format files without a UUID counterpart and migrate them.

    Returns a list of (old_path, new_path, sid, migration_note) tuples.
    """
    if not os.path.isdir(SESSIONS_DIR):
        return []

    migrated = []
    for path in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        basename = os.path.basename(path)
        # Skip files that are already UUID-named
        if "-" in basename.replace(".json", "") and len(basename) > 30:
            continue
        try:
            with open(path) as f:
                data = json.load(f)
        except Exception:
            continue
        sid = data.get("session_id") or data.get("sessionId")
        if not sid:
            continue
        uuid_path = os.path.join(SESSIONS_DIR, f"{sid}.json")
        if os.path.exists(uuid_path) and os.path.abspath(uuid_path) != os.path.abspath(path):
            # UUID file already exists separately — don't overwrite, just delete the orphan
            try:
                os.remove(path)
                migrated.append((path, uuid_path, sid, "duplicate removed (UUID file already existed)"))
            except OSError:
                pass
            continue
        record = migrate_record(data)
        if record is None:
            continue
        with open(uuid_path, "w") as f:
            json.dump(record, f, indent=2)
        if os.path.abspath(path) != os.path.abspath(uuid_path):
            try:
                os.remove(path)
            except OSError:
                pass
        migrated.append((path, uuid_path, sid, record.get("migration_note", "migrated cleanly")))

    return migrated


# CLI mode for standalone invocation
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: session_lib.py <resolve|migrate-all> [args]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "resolve":
        if len(sys.argv) < 3:
            print("usage: session_lib.py resolve <session_id>", file=sys.stderr)
            sys.exit(1)
        path = resolve_session_file(sys.argv[2], create_if_missing=False)
        if path:
            print(path)
        else:
            sys.exit(2)

    elif cmd == "resolve-or-create":
        if len(sys.argv) < 3:
            print("usage: session_lib.py resolve-or-create <session_id>", file=sys.stderr)
            sys.exit(1)
        path = resolve_session_file(sys.argv[2], create_if_missing=True)
        print(path)

    elif cmd == "migrate-all":
        results = migrate_all_orphans()
        for old, new, sid, note in results:
            print(f"{sid}: {os.path.basename(old)} → {os.path.basename(new)} ({note})")
        print(f"\n{len(results)} session(s) migrated.")

    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
