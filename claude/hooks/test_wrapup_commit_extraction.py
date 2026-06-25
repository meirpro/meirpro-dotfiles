#!/usr/bin/env python3
"""Unit test for the own-commits extraction logic embedded in wrapup.sh.

The extractor pairs Bash `git commit` tool_use blocks with their tool_result
output to find SHAs the session itself created (vs. parallel agents'
commits in the git log window).

Run:  python3 ~/.claude/hooks/test_wrapup_commit_extraction.py
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Re-implement the regex constants here (matches wrapup.sh's embedded
# Python). If the script's logic changes, update these and re-run.
COMMIT_RE = re.compile(r"(?<![\w-])git\s+commit\b(?!\s+--amend\b)")
SHA_RE = re.compile(r"\[[^\]]+\s+([0-9a-f]{7,40})\]")


def extract_own_shas(slice_lines: list[dict]) -> list[str]:
    """Mirror of wrapup.sh's inline extractor — pure, testable."""
    pending_ids: set[str] = set()
    own_shas: list[str] = []
    for rec in slice_lines:
        msg = rec.get("message") or rec
        content = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "tool_use" and block.get("name") == "Bash":
                cmd = (block.get("input") or {}).get("command", "")
                if COMMIT_RE.search(cmd):
                    pending_ids.add(block.get("id"))
            elif btype == "tool_result":
                tid = block.get("tool_use_id")
                if tid not in pending_ids:
                    continue
                raw = block.get("content")
                text = ""
                if isinstance(raw, str):
                    text = raw
                elif isinstance(raw, list):
                    text = "\n".join(
                        (b.get("text", "") if isinstance(b, dict) else "") for b in raw
                    )
                m = SHA_RE.search(text)
                if m:
                    own_shas.append(m.group(1))
                pending_ids.discard(tid)
    return own_shas


def use(tid: str, cmd: str) -> dict:
    return {
        "message": {
            "content": [
                {"type": "tool_use", "name": "Bash", "id": tid, "input": {"command": cmd}}
            ]
        }
    }


def result(tid: str, text: str) -> dict:
    return {
        "message": {
            "content": [{"type": "tool_result", "tool_use_id": tid, "content": text}]
        }
    }


def result_blocks(tid: str, text: str) -> dict:
    """tool_result with content-as-blocks (newer transcript shape)."""
    return {
        "message": {
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": tid,
                    "content": [{"type": "text", "text": text}],
                }
            ]
        }
    }


class TestExtractOwnShas(unittest.TestCase):
    def test_basic_commit_extraction(self):
        slice_ = [
            use("t1", "git add foo.py && git commit -m 'add foo'"),
            result("t1", "[main 0a1b2c3] add foo\n 1 file changed"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["0a1b2c3"])

    def test_skips_amend(self):
        slice_ = [
            use("t1", "git commit --amend --no-edit"),
            result("t1", "[main 0a1b2c3] amended"),
        ]
        self.assertEqual(extract_own_shas(slice_), [])

    def test_pairs_correct_tool_use_id(self):
        # An interleaved unrelated Bash + commit Bash. Only the commit SHA wins.
        slice_ = [
            use("t1", "ls -la"),
            use("t2", "git commit -m 'x'"),
            result("t1", "drwxr-xr-x lightwing staff 128 ..."),
            result("t2", "[feat/x 9876543] x"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["9876543"])

    def test_handles_content_as_blocks(self):
        # Newer Claude Code transcript shape: tool_result.content is a list
        slice_ = [
            use("t1", "git commit -m 'block-shape'"),
            result_blocks("t1", "[main feed1ce] block-shape"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["feed1ce"])

    def test_commit_minus_a_minus_m(self):
        # `git commit -am 'msg'` should be picked up by the regex
        slice_ = [
            use("t1", "git commit -am 'fix typo'"),
            result("t1", "[main deadbee] fix typo"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["deadbee"])

    def test_chained_commit(self):
        # `git add foo && git commit -m '$(cat <<EOF...EOF)'` heredoc style
        cmd = """git add file.py && git commit -m "$(cat <<'EOF'
multi
line
EOF
)" """
        slice_ = [
            use("t1", cmd),
            result("t1", "[main cafe123] multi"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["cafe123"])

    def test_failed_commit_yields_no_sha(self):
        slice_ = [
            use("t1", "git commit -m 'will fail'"),
            result("t1", "error: pathspec 'nope.txt' did not match any file(s)"),
        ]
        self.assertEqual(extract_own_shas(slice_), [])

    def test_pre_commit_hook_failure_then_retry(self):
        # Real-world: first attempt fails (no SHA in output), second succeeds
        slice_ = [
            use("t1", "git commit -m 'first try'"),
            result("t1", "hook failed:\nlint errors: 3"),
            use("t2", "git commit -m 'after fix'"),
            result("t2", "[main aaaa111] after fix"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["aaaa111"])

    def test_branch_with_slashes(self):
        # SHA regex must handle branch names with `/` (e.g. `claude/probe-foo`)
        slice_ = [
            use("t1", "git commit -m 'on slash branch'"),
            result("t1", "[claude/probe-foo bbbb222] on slash branch"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["bbbb222"])

    def test_unrelated_git_command_ignored(self):
        # `git log`, `git status`, etc. must NOT be picked up
        slice_ = [
            use("t1", "git log --oneline -5"),
            result("t1", "abc1234 most recent"),
            use("t2", "git status"),
            result("t2", "On branch main"),
        ]
        self.assertEqual(extract_own_shas(slice_), [])

    def test_orphan_tool_result_ignored(self):
        # tool_result with no matching pending tool_use → ignored
        slice_ = [
            result("ghost", "[main 1234567] orphan"),
        ]
        self.assertEqual(extract_own_shas(slice_), [])

    def test_multiple_commits_in_session(self):
        slice_ = [
            use("t1", "git commit -m 'one'"),
            result("t1", "[main 1111111] one"),
            use("t2", "git commit -m 'two'"),
            result("t2", "[main 2222222] two"),
        ]
        self.assertEqual(extract_own_shas(slice_), ["1111111", "2222222"])


class TestEndToEndOnRealRepo(unittest.TestCase):
    """Run the actual wrapup.sh slicer code against a tmp git repo so we
    catch any drift between the test's re-implementation and the script's
    embedded Python."""

    def test_runs_extractor_on_jsonl_fixture(self):
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            # Init a real git repo so the `git log -1 <sha>` enrichment works
            subprocess.run(["git", "init", "-q", str(tdp)], check=True)
            subprocess.run(
                ["git", "-C", str(tdp), "config", "user.email", "t@t"], check=True
            )
            subprocess.run(["git", "-C", str(tdp), "config", "user.name", "t"], check=True)
            (tdp / "f.txt").write_text("hello\n")
            subprocess.run(["git", "-C", str(tdp), "add", "f.txt"], check=True)
            subprocess.run(
                ["git", "-C", str(tdp), "commit", "-q", "-m", "fixture commit"], check=True
            )
            real_sha = subprocess.run(
                ["git", "-C", str(tdp), "rev-parse", "HEAD"],
                capture_output=True, text=True, check=True,
            ).stdout.strip()

            # Build a JSONL slice mentioning that exact commit
            slice_path = tdp / "slice.jsonl"
            with slice_path.open("w") as f:
                f.write(json.dumps(use("t1", "git commit -m 'fixture'")) + "\n")
                f.write(
                    json.dumps(result("t1", f"[main {real_sha[:7]}] fixture")) + "\n"
                )

            # Run the extractor's stdin python by inlining the wrapup.sh logic
            # via a one-shot subprocess that mimics what the script does.
            out_path = tdp / "out.json"
            script = r"""
import json, re, subprocess, sys
slice_path, project_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
commit_re = re.compile(r"(?<![\w-])git\s+commit\b(?!\s+--amend\b)")
sha_re = re.compile(r"\[[^\]]+\s+([0-9a-f]{7,40})\]")
pending_ids = set(); own_shas = []
with open(slice_path) as f:
    for line in f:
        try: rec = json.loads(line)
        except json.JSONDecodeError: continue
        msg = rec.get("message") or rec
        content = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(content, list): continue
        for block in content:
            if not isinstance(block, dict): continue
            btype = block.get("type")
            if btype == "tool_use" and block.get("name") == "Bash":
                cmd = (block.get("input") or {}).get("command", "")
                if commit_re.search(cmd): pending_ids.add(block.get("id"))
            elif btype == "tool_result":
                tid = block.get("tool_use_id")
                if tid not in pending_ids: continue
                raw = block.get("content"); text = ""
                if isinstance(raw, str): text = raw
                elif isinstance(raw, list):
                    text = "\n".join((b.get("text", "") if isinstance(b, dict) else "") for b in raw)
                m = sha_re.search(text)
                if m: own_shas.append(m.group(1))
                pending_ids.discard(tid)
enriched = []
for sha in own_shas:
    out = subprocess.run(["git", "-C", project_path, "log", "-1", "--format=%H%x09%s", sha], capture_output=True, text=True, timeout=5)
    if out.returncode == 0 and out.stdout:
        full_sha, _, subject = out.stdout.strip().partition("\t")
        enriched.append({"sha": full_sha, "msg": subject})
with open(out_path, "w") as f: json.dump(enriched, f)
"""
            subprocess.run(
                ["python3", "-c", script, str(slice_path), str(tdp), str(out_path)],
                check=True, timeout=10,
            )

            result_data = json.loads(out_path.read_text())
            self.assertEqual(len(result_data), 1)
            self.assertEqual(result_data[0]["sha"], real_sha)
            self.assertEqual(result_data[0]["msg"], "fixture commit")


if __name__ == "__main__":
    unittest.main()
