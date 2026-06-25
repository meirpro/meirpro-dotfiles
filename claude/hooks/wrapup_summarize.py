#!/usr/bin/env python3
"""wrapup_summarize.py — generate structured Haiku summary for a wrapup segment.

Reads a JSONL transcript slice + commit list, calls `claude -p` with the
wrapup prompt and a JSON schema, writes the result to an output file.

CLI:
  wrapup_summarize.py \\
    --transcript-slice <path>      # JSONL slice since prev wrapup ts
    --commits-file <path>          # JSON: [{"sha":"abc1234","msg":"..."}]
    --out <path>                   # write structured JSON here
    [--timeout-seconds 90]
    [--budget-usd 0.10]

Auth: uses ANTHROPIC_API_KEY + `--bare` (fast, ~3-8s) if env var set;
      otherwise falls back to the user's keychain OAuth without `--bare`
      (slower ~15-30s on first call due to harness boot, but works
      without any setup).

On Haiku failure (any non-zero exit, timeout, malformed JSON, missing
structured_output): writes a fallback JSON derived from commit messages
and sets `_fallback: true` with `_fallback_reason`. Exit 0 in both paths
so the orchestrator always has a usable summary file.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

PROMPT_FILE = Path(__file__).parent / "wrapup_summarize_prompt.md"
HAIKU_MODEL = "claude-haiku-4-5-20251001"
MAX_TRANSCRIPT_BYTES = 200 * 1024  # 200KB cap before truncation

SCHEMA: dict[str, Any] = {
    "type": "object",
    "required": ["headline", "details", "topics", "blockers"],
    "properties": {
        "headline": {"type": "string", "maxLength": 250},
        "details": {
            "type": "array",
            "items": {"type": "string", "maxLength": 250},
            "minItems": 0,
            "maxItems": 5,
        },
        "topics": {
            "type": "array",
            "items": {"type": "string", "maxLength": 40},
            "maxItems": 8,
        },
        "blockers": {
            "type": "array",
            "items": {"type": "string", "maxLength": 250},
            "maxItems": 5,
        },
    },
}


def commits_fallback(commits: list[dict[str, str]], reason: str) -> dict[str, Any]:
    """Derive a usable summary purely from commit messages when Haiku fails."""
    if not commits:
        return {
            "headline": "exploratory segment — no commits, Haiku unavailable",
            "details": [],
            "topics": [],
            "blockers": [],
            "_fallback": True,
            "_fallback_reason": reason,
        }
    first_msg = commits[0]["msg"]
    extra = f" (+{len(commits) - 1} more)" if len(commits) > 1 else ""
    return {
        "headline": (first_msg[:230] + extra)[:250],
        "details": [c["msg"][:240] for c in commits[:5]],
        "topics": [],
        "blockers": [],
        "_fallback": True,
        "_fallback_reason": reason,
    }


def load_transcript_slice(path: Path) -> str:
    """Return the slice as a string, truncated to MAX_TRANSCRIPT_BYTES.

    Truncation strategy: keep the tail (most recent activity wins).
    """
    raw = path.read_bytes()
    if len(raw) <= MAX_TRANSCRIPT_BYTES:
        return raw.decode("utf-8", errors="replace")
    truncated = raw[-MAX_TRANSCRIPT_BYTES:]
    # Find the next newline so we don't start mid-record
    nl = truncated.find(b"\n")
    if nl > 0:
        truncated = truncated[nl + 1 :]
    return (
        f"[... transcript truncated to last {MAX_TRANSCRIPT_BYTES} bytes ...]\n"
        + truncated.decode("utf-8", errors="replace")
    )


def build_user_input(transcript: str, commits: list[dict[str, str]]) -> str:
    commit_block = (
        "\n".join(f"  {c['sha'][:8]}  {c['msg']}" for c in commits)
        if commits
        else "  (no commits this segment)"
    )
    return (
        "=== COMMITS THIS SEGMENT ===\n"
        f"{commit_block}\n\n"
        "=== TRANSCRIPT SLICE ===\n"
        f"{transcript}\n"
    )


def run_claude(
    user_input: str, timeout_seconds: int, budget_usd: float
) -> tuple[dict[str, Any] | None, str | None]:
    """Returns (parsed_structured_output, error_reason). One of them is None."""
    if not PROMPT_FILE.exists():
        return None, f"prompt_file_missing: {PROMPT_FILE}"

    claude_bin = shutil.which("claude")
    if not claude_bin:
        return None, "claude_cli_not_found"

    cmd = [
        claude_bin,
        "-p",
        "--model",
        HAIKU_MODEL,
        "--output-format",
        "json",
        "--json-schema",
        json.dumps(SCHEMA),
        "--append-system-prompt",
        PROMPT_FILE.read_text(),
        "--max-budget-usd",
        str(budget_usd),
    ]
    # --bare is fastest + cheapest but requires ANTHROPIC_API_KEY. Fall back
    # to keychain OAuth (no --bare) when the env var isn't set, accepting
    # the slower first call.
    if os.environ.get("ANTHROPIC_API_KEY"):
        cmd.insert(2, "--bare")

    try:
        proc = subprocess.run(
            cmd,
            input=user_input,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return None, f"haiku_timeout_{timeout_seconds}s"
    except OSError as e:
        return None, f"haiku_spawn_failed: {e}"

    if proc.returncode != 0:
        # claude -p reports auth/budget/etc. via stdout JSON even on non-zero
        snippet = (proc.stdout or proc.stderr or "")[:200].replace("\n", " ")
        return None, f"haiku_exit_{proc.returncode}: {snippet}"

    try:
        envelope = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None, "haiku_stdout_not_json"

    if envelope.get("is_error"):
        return None, f"haiku_api_error: {envelope.get('result', '')[:200]}"

    structured = envelope.get("structured_output")
    if not isinstance(structured, dict):
        return None, "haiku_no_structured_output"

    # Sanity-check required keys (the schema enforces this server-side, but
    # be defensive — the model can still return partial structures)
    for key in ("headline", "details", "topics", "blockers"):
        if key not in structured:
            return None, f"haiku_missing_field: {key}"
    if not isinstance(structured["headline"], str) or not structured["headline"].strip():
        return None, "haiku_empty_headline"

    return structured, None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcript-slice", required=True)
    ap.add_argument("--commits-file", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout-seconds", type=int, default=90)
    ap.add_argument("--budget-usd", type=float, default=0.10)
    args = ap.parse_args()

    transcript_path = Path(args.transcript_slice)
    commits_path = Path(args.commits_file)
    out_path = Path(args.out)

    transcript = load_transcript_slice(transcript_path) if transcript_path.exists() else ""
    try:
        commits = json.loads(commits_path.read_text()) if commits_path.exists() else []
    except json.JSONDecodeError:
        commits = []

    user_input = build_user_input(transcript, commits)

    summary, err = run_claude(user_input, args.timeout_seconds, args.budget_usd)
    if summary is None:
        summary = commits_fallback(commits, err or "unknown")
        # Log to stderr so wrapup.sh can surface the fallback reason
        print(f"wrapup_summarize: Haiku failed ({err}) — using commit fallback", file=sys.stderr)

    out_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
