#!/usr/bin/env python3
"""Tests for claude-settings. Run: python3 claude/bin/test_claude_settings.py

Each case runs the real script in a throwaway HOME with its own public and
private sources, so nothing here can touch the live ~/.claude."""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "claude-settings"


class Env:
    def __init__(self, public: dict, private: dict | None):
        self.dir = Path(tempfile.mkdtemp())
        self.home = self.dir / "home"
        (self.home / ".claude").mkdir(parents=True)
        self.public = self.dir / "public.json"
        self.private = self.dir / "private.json"
        self.public.write_text(json.dumps(public))
        if private is not None:
            self.private.write_text(json.dumps(private))
        self.live = self.home / ".claude/settings.json"
        self.snap = self.home / ".claude/.settings.built.json"

    def run(self, *args: str) -> subprocess.CompletedProcess:
        env = dict(
            os.environ,
            HOME=str(self.home),
            CLAUDE_SETTINGS_PUBLIC=str(self.public),
            CLAUDE_SETTINGS_PRIVATE=str(self.private),
        )
        return subprocess.run(
            ["python3", str(SCRIPT), *args], env=env, capture_output=True, text=True
        )

    def read(self, path: Path) -> dict:
        return json.loads(path.read_text())


PUB = {"model": "x", "permissions": {"allow": ["Read"]}}
PRIV = {"autoMode": {"soft_deny": ["$defaults"]}}


class Build(unittest.TestCase):
    def test_merges_public_and_private(self):
        e = Env(PUB, PRIV)
        r = e.run("build")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(e.read(e.live), {**PUB, **PRIV})
        self.assertEqual(e.read(e.snap), e.read(e.live))

    def test_refuses_a_key_in_both_sources(self):
        e = Env(PUB, {"model": "y"})
        r = e.run("build")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("model", r.stderr)
        self.assertFalse(e.live.exists())

    def test_refuses_to_discard_an_agent_edit(self):
        e = Env(PUB, PRIV)
        e.run("build")
        live = e.read(e.live)
        live["permissions"]["allow"].append("Bash(ls:*)")
        e.live.write_text(json.dumps(live))
        r = e.run("build")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("absorb", r.stderr)
        self.assertIn("Bash(ls:*)", e.live.read_text())  # untouched

    def test_first_build_over_an_unknown_file_needs_force(self):
        e = Env(PUB, PRIV)
        e.live.write_text(json.dumps({"something": "else"}))
        self.assertNotEqual(e.run("build").returncode, 0)
        self.assertEqual(e.run("build", "--force").returncode, 0)
        self.assertEqual(e.read(e.live), {**PUB, **PRIV})

    def test_never_writes_through_a_symlink(self):
        e = Env(PUB, PRIV)
        e.live.symlink_to(e.public)  # the old setup: live -> public repo
        e.run("build", "--force")
        self.assertFalse(e.live.is_symlink())
        self.assertNotIn("autoMode", e.public.read_text())

    def test_refuses_an_unsafe_public_base(self):
        e = Env({**PUB, "autoMode": {}}, {})
        r = e.run("build")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("private-only", r.stderr)

    def test_warns_when_the_private_overlay_is_missing(self):
        e = Env(PUB, None)
        r = e.run("build")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("WARNING", r.stderr)
        self.assertEqual(e.read(e.live), PUB)


class Absorb(unittest.TestCase):
    def built(self) -> Env:
        e = Env(PUB, PRIV)
        self.assertEqual(e.run("build").returncode, 0)
        return e

    def edit_live(self, e: Env, fn) -> None:
        live = e.read(e.live)
        fn(live)
        e.live.write_text(json.dumps(live, indent="\t"))  # the formatter's style

    def test_sends_a_public_key_back_to_public(self):
        e = self.built()
        self.edit_live(e, lambda d: d["permissions"]["allow"].append("Bash(ls:*)"))
        r = e.run("absorb")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Bash(ls:*)", e.read(e.public)["permissions"]["allow"])
        self.assertEqual(e.read(e.private), PRIV)
        self.assertEqual(e.run("build").returncode, 0)  # in sync again

    def test_sends_a_private_key_back_to_private(self):
        e = self.built()
        self.edit_live(e, lambda d: d["autoMode"]["soft_deny"].append("Bash(rm:*)"))
        e.run("absorb")
        self.assertIn("Bash(rm:*)", e.read(e.private)["autoMode"]["soft_deny"])
        self.assertEqual(e.read(e.public), PUB)

    def test_a_new_key_goes_private(self):
        e = self.built()
        self.edit_live(e, lambda d: d.__setitem__("newThing", True))
        r = e.run("absorb")
        self.assertIn("new key", r.stdout)
        self.assertTrue(e.read(e.private)["newThing"])
        self.assertNotIn("newThing", e.read(e.public))

    def test_a_removed_key_is_removed_from_its_owner(self):
        e = self.built()
        self.edit_live(e, lambda d: d.pop("model"))
        e.run("absorb")
        self.assertNotIn("model", e.read(e.public))

    def test_stops_on_a_conflict(self):
        e = self.built()
        self.edit_live(e, lambda d: d.__setitem__("model", "from-agent"))
        e.public.write_text(json.dumps({**PUB, "model": "from-source"}))
        r = e.run("absorb")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("model", r.stderr)
        self.assertEqual(e.read(e.public)["model"], "from-source")

    def test_will_not_publish_a_home_path(self):
        e = self.built()
        self.edit_live(
            e, lambda d: d["permissions"]["allow"].append("Read(/Users/someone/x)")
        )
        r = e.run("absorb")
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("/Users/", e.public.read_text())

    def test_reindenting_alone_is_not_an_edit(self):
        e = self.built()
        self.edit_live(e, lambda d: None)
        r = e.run("absorb")
        self.assertIn("nothing to absorb", r.stdout)


class Check(unittest.TestCase):
    def test_in_sync_after_build(self):
        e = Env(PUB, PRIV)
        e.run("build")
        self.assertEqual(e.run("check").returncode, 0)

    def test_reports_an_agent_edit(self):
        e = Env(PUB, PRIV)
        e.run("build")
        e.live.write_text(json.dumps({**PUB, **PRIV, "model": "z"}))
        r = e.run("check")
        self.assertEqual(r.returncode, 1)
        self.assertIn("model", r.stdout)


class Lint(unittest.TestCase):
    def test_flags_tokens_and_private_keys(self):
        for bad in (
            {"remote": {"defaultEnvironmentId": "env_1"}},
            {"env": {"X": "ghp_" + "a" * 36}},
            {"hooks": {"Stop": [{"hooks": [{"command": "/Users/me/x"}]}]}},
        ):
            e = Env(bad, {})
            self.assertNotEqual(e.run("lint").returncode, 0, bad)

    def test_passes_a_clean_base(self):
        self.assertEqual(Env(PUB, {}).run("lint").returncode, 0)


if __name__ == "__main__":
    unittest.main()
