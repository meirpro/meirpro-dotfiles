#!/usr/bin/env python3
"""
transcript_to_session.py — synthesize a session file from a Claude Code
transcript JSONL.

USE CASE
========

The user's `session_heartbeat.sh` hook creates `~/.claude/sessions/<SID>.json`
lazily on the first Stop event. For old/abandoned/computer-was-closed
sessions, that file may never exist — but Claude Code always writes the
TRANSCRIPT at `~/.claude/projects/-<encoded-cwd>/<SID>.jsonl`. The
transcript holds everything we need to backfill the session file:

  - real start time         (first `timestamp` in the file)
  - real end time           (last `timestamp` in the file)
  - project cwd             (`cwd` field on user entries)
  - git branch              (`gitBranch` field — last value wins)
  - model id                (`message.model` on assistant entries)
  - token usage             (sum of `message.usage` fields)
  - cost estimate           (token totals × per-model pricing)
  - message/tool counts     (entry type counts)
  - active vs idle minutes  (sum gaps between adjacent timestamps,
                             clamped to a per-gap ceiling so a
                             closed-laptop gap doesn't inflate "active")

USAGE
=====

  transcript_to_session.py synthesize <SID>
      Locate the transcript, build a stub session file at
      ~/.claude/sessions/<SID>.json (only if it doesn't already exist),
      print the JSON written.

  transcript_to_session.py extract <SID>
      Print just the extracted JSON to stdout. Doesn't touch any file.

  transcript_to_session.py find-transcript <SID>
      Print the absolute path to the transcript, or empty.

Designed to be called from the /wrapup skill, but useful standalone.
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime, timezone

SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")

# Per-model pricing (USD / 1M tokens). Add new models as they ship.
# These are the public Anthropic rates as of mid-2026; if Anthropic
# changes pricing, update here and re-run any historical extracts.
PRICING = {
    "claude-opus-4-7":     {"in": 15.0,  "out": 75.0,  "cache_create": 18.75, "cache_read": 1.50},
    "claude-opus-4-6":     {"in": 15.0,  "out": 75.0,  "cache_create": 18.75, "cache_read": 1.50},
    "claude-sonnet-4-6":   {"in": 3.0,   "out": 15.0,  "cache_create": 3.75,  "cache_read": 0.30},
    "claude-haiku-4-5":    {"in": 1.0,   "out": 5.0,   "cache_create": 1.25,  "cache_read": 0.10},
    "claude-haiku-4-5-20251001": {"in": 1.0, "out": 5.0, "cache_create": 1.25, "cache_read": 0.10},
}

# Gap-cap for active-minute calculation. A 4-hour gap between adjacent
# transcript entries is the user sleeping, not active work — count only
# the first N seconds of any gap toward "active".
ACTIVE_GAP_CAP_S = 5 * 60   # 5 minutes


def find_transcript(sid: str) -> str:
    """Return absolute path to the transcript JSONL for `sid`, or ''."""
    candidates = glob.glob(os.path.join(PROJECTS_DIR, "*", f"{sid}.jsonl"))
    return candidates[0] if candidates else ""


def parse_iso(ts: str) -> datetime | None:
    """Parse an ISO-8601 timestamp like '2026-05-24T06:24:51.065Z'."""
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def estimate_cost(model: str, usage_totals: dict) -> float:
    """
    UNRELIABLE — leaves a token-based ballpark. Observed empirically to
    overshoot the Anthropic-billed cost by 4× on at least one session
    (677cbeb4: status-line $258, this estimate $1005). The transcript
    JSONL has no native cost_usd field, so this is purely tokens × rates.
    Suspected discrepancies vs real billing: cache-read rate windowing,
    batching discounts, rate-limit-induced retries that get refunded.

    For authoritative cost, use `telemetry.live.cost_usd` from the
    session file (heartbeat-maintained) when it exists. For
    transcript-only sessions, prefer "unknown" over a misleading
    estimate — the caller should treat the returned number with
    suspicion and surface it as ESTIMATE in any UI.
    """
    rates = PRICING.get(model)
    if not rates:
        return 0.0
    return (
        usage_totals.get("input_tokens", 0) * rates["in"] / 1_000_000
        + usage_totals.get("output_tokens", 0) * rates["out"] / 1_000_000
        + usage_totals.get("cache_creation_input_tokens", 0) * rates["cache_create"] / 1_000_000
        + usage_totals.get("cache_read_input_tokens", 0) * rates["cache_read"] / 1_000_000
    )


def extract(sid: str) -> dict:
    """
    Walk the transcript JSONL and aggregate every field we need to
    synthesize a session file. Returns a dict ready to JSON-serialize.
    Raises SystemExit(1) if the transcript isn't found.
    """
    path = find_transcript(sid)
    if not path:
        sys.stderr.write(f"transcript_to_session: no transcript for {sid}\n")
        sys.exit(1)

    first_ts = last_ts = None
    cwd = ""
    branch = ""           # last branch wins — usually the final working branch
    model = ""            # last model on an assistant entry wins
    type_counts = {}
    tool_use_ids = set()
    usage = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
    }
    # Active-minute estimate: sum gaps between adjacent timestamps,
    # clamping each gap to ACTIVE_GAP_CAP_S so a multi-hour idle window
    # contributes only its capped amount.
    active_s = 0.0
    prev_dt = None

    with open(path) as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue

            t = d.get("type", "?")
            type_counts[t] = type_counts.get(t, 0) + 1

            if d.get("cwd"):
                cwd = d["cwd"]
            if d.get("gitBranch"):
                branch = d["gitBranch"]
            if d.get("toolUseID"):
                tool_use_ids.add(d["toolUseID"])

            msg = d.get("message")
            if isinstance(msg, dict):
                if msg.get("model"):
                    model = msg["model"]
                u = msg.get("usage") or {}
                for k in usage:
                    if isinstance(u.get(k), int):
                        usage[k] += u[k]

            ts = d.get("timestamp")
            dt = parse_iso(ts) if ts else None
            if dt:
                if first_ts is None:
                    first_ts = dt
                last_ts = dt
                if prev_dt is not None:
                    gap = (dt - prev_dt).total_seconds()
                    if gap > 0:
                        active_s += min(gap, ACTIVE_GAP_CAP_S)
                prev_dt = dt

    if first_ts is None:
        # transcript exists but has no timestamps — pathological
        first_ts = last_ts = datetime.now(timezone.utc)

    wall_s = (last_ts - first_ts).total_seconds()
    cost_usd = estimate_cost(model, usage)
    project = os.path.basename(cwd.rstrip("/")) if cwd else "?"

    return {
        "session_id": sid,
        "start": first_ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "last_seen": last_ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "active_minutes": int(round(active_s / 60)),
        "project_path": cwd or "?",
        "project": project,
        "branch": branch or "n/a",
        "recent_commits": [],         # left empty — caller's job to git log
        "uncommitted_changes": 0,
        "telemetry": {
            "live": {
                "model_id": model or "unknown",
                "wall_duration_ms": int(wall_s * 1000),
                "api_duration_ms": int(active_s * 1000),  # gap-capped — proxy only
                "tokens_in": usage["input_tokens"]
                             + usage["cache_creation_input_tokens"]
                             + usage["cache_read_input_tokens"],
                "tokens_out": usage["output_tokens"],
                "usage_breakdown": usage,
                # Explicitly absent: cost_usd. Transcript-derived cost
                # estimates were 4× off in testing; the only authoritative
                # source is heartbeat-maintained telemetry.live.cost_usd
                # (which doesn't exist for transcript-only sessions). The
                # field is left out rather than filled with a misleading
                # estimate. Callers needing a ballpark can call
                # estimate_cost() on the usage_breakdown and label clearly.
                "cost_usd_estimate_unreliable": round(cost_usd, 4),
            },
            "synth": {
                "source": "transcript",
                "transcript_path": path,
                "type_counts": type_counts,
                "tool_use_count": len(tool_use_ids),
                # `wall_unreliable` is FALSE here: wall comes from real
                # transcript-edge timestamps. Caveat: those span the
                # user's closed-laptop hours too (in 677cbeb4 the
                # 146h span includes overnight gaps).
                "wall_unreliable": False,
                # Reminder to the caller that cost was NOT recovered.
                "cost_unrecoverable_reason": "transcript has no native cost_usd; token-based estimate observed 4× off",
            },
        },
    }


def synthesize(sid: str) -> dict:
    """
    Build a session file from the transcript and write it to
    SESSIONS_DIR/<sid>.json. Skips the write if a file already exists
    (we don't want to clobber a live heartbeat-maintained file).
    Returns the dict that was written (or already present).
    """
    target = os.path.join(SESSIONS_DIR, f"{sid}.json")
    if os.path.exists(target):
        sys.stderr.write(
            f"transcript_to_session: {target} already exists — leaving it alone\n"
        )
        with open(target) as f:
            return json.load(f)

    data = extract(sid)
    os.makedirs(SESSIONS_DIR, exist_ok=True)
    with open(target, "w") as f:
        json.dump(data, f, indent=2)
    return data


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("cmd", choices=["synthesize", "extract", "find-transcript"])
    p.add_argument("sid", help="session UUID")
    args = p.parse_args()

    if args.cmd == "find-transcript":
        print(find_transcript(args.sid))
    elif args.cmd == "extract":
        print(json.dumps(extract(args.sid), indent=2))
    elif args.cmd == "synthesize":
        print(json.dumps(synthesize(args.sid), indent=2))


if __name__ == "__main__":
    main()
