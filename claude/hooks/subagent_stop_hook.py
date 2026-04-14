#!/usr/bin/env python3
"""
SubagentStop hook — records sub-agent metadata on the parent session JSON file.

Reads stdin for: session_id, agent_id, agent_type, agent_transcript_path
Computes duration as (last_ts - first_ts) of the agent transcript
Appends to telemetry.sub_agents (deduped by basename of agent_transcript_path)

Best-effort — never blocks the hook. Exit 0 always.
"""

import json
import os
import sys
from datetime import datetime, timezone

SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")


def parse_iso(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None


def compute_duration_ms(transcript_path):
    """First-to-last timestamp of the agent transcript, in ms."""
    if not transcript_path or not os.path.isfile(transcript_path):
        return None
    first_ts = None
    last_ts = None
    try:
        with open(transcript_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                ts = rec.get("timestamp") or rec.get("ts")
                dt = parse_iso(ts)
                if dt is None:
                    continue
                if first_ts is None:
                    first_ts = dt
                last_ts = dt
    except Exception:
        return None
    if first_ts is None or last_ts is None:
        return None
    delta = (last_ts - first_ts).total_seconds() * 1000
    return max(0, int(delta))


def main():
    try:
        stdin_data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    session_id = stdin_data.get("session_id")
    if not session_id:
        sys.exit(0)

    agent_id = stdin_data.get("agent_id") or "unknown"
    agent_type = stdin_data.get("agent_type") or "unknown"
    transcript_path = stdin_data.get("agent_transcript_path")

    session_file = os.path.join(SESSIONS_DIR, f"{session_id}.json")
    if not os.path.isfile(session_file):
        sys.exit(0)

    try:
        with open(session_file) as f:
            session = json.load(f)
    except Exception:
        sys.exit(0)

    telemetry = session.setdefault("telemetry", {})
    sub_agents = telemetry.setdefault("sub_agents", {})
    processed = telemetry.setdefault("processed_subagent_files", [])

    # Dedup by transcript basename
    basename = os.path.basename(transcript_path) if transcript_path else f"{agent_id}.unknown"
    if basename in processed:
        sys.exit(0)

    duration_ms = compute_duration_ms(transcript_path)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    sub_agents[agent_id] = {
        "type": agent_type,
        "duration_ms": duration_ms,
        "transcript_basename": basename,
        "recorded_at": now_iso,
    }
    processed.append(basename)

    # Recompute totals
    totals = telemetry.setdefault("totals", {})
    totals["sub_agent_count"] = len(sub_agents)
    totals["sub_agent_total_ms"] = sum(
        (sa.get("duration_ms") or 0) for sa in sub_agents.values()
    )

    # Compute parallelism factor if api_duration_ms is available from live data
    live = telemetry.get("live", {})
    api_duration_ms = live.get("api_duration_ms")
    if api_duration_ms and api_duration_ms > 0 and totals["sub_agent_total_ms"] > 0:
        totals["parallelism_factor"] = round(
            totals["sub_agent_total_ms"] / api_duration_ms, 3
        )
    else:
        totals["parallelism_factor"] = None

    try:
        with open(session_file, "w") as f:
            json.dump(session, f, indent=2)
    except Exception:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
