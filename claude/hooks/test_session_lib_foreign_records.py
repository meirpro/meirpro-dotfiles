#!/usr/bin/env python3
"""Guard test: session_lib must never delete Claude Code's own session records.

Shipped-almost: the "heartbeat eats the registry" bug (caught 2026-07-28,
before the heartbeat hook was enabled). resolve_session_file() globs
~/.claude/sessions/*.json and matched on `sessionId` — the camelCase key
Claude Code itself writes in its PID-named registry files — then removed the
matched file after migrating it. Enabling session_heartbeat.sh would have
deleted the live session's registry entry on first fire, breaking /resume
and session naming.

Run directly: python3 test_session_lib_foreign_records.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import session_lib


class ForeignRecordSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="session_lib_test_")
        self._orig_dir = session_lib.SESSIONS_DIR
        session_lib.SESSIONS_DIR = self.tmp

    def tearDown(self):
        session_lib.SESSIONS_DIR = self._orig_dir
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, name, data):
        path = os.path.join(self.tmp, name)
        with open(path, "w") as f:
            json.dump(data, f)
        return path

    def test_claude_code_native_record_survives_migration(self):
        """A PID-named camelCase record (Claude Code's own) is copied, never removed."""
        sid = "2e8b3003-aaaa-bbbb-cccc-000000000001"
        native = self._write("52613.json", {
            "pid": 52613,
            "sessionId": sid,
            "cwd": "/Users/x/git/proj",
            "startedAt": 1785188474108,
            "peerProtocol": 1,
            "kind": "interactive",
            "entrypoint": "cli",
        })

        resolved = session_lib.resolve_session_file(sid)

        self.assertTrue(os.path.isfile(native),
                        "Claude Code's native registry file was deleted")
        self.assertEqual(resolved, os.path.join(self.tmp, f"{sid}.json"))
        with open(resolved) as f:
            migrated = json.load(f)
        self.assertEqual(migrated["session_id"], sid)

    def test_our_legacy_record_is_still_cleaned_up(self):
        """Our own old snake_case orphan (no pid/peerProtocol) is migrated AND removed."""
        sid = "2e8b3003-aaaa-bbbb-cccc-000000000002"
        ours = self._write("legacy-name.json", {
            "session_id": sid,
            "start": "2026-07-01T00:00:00Z",
            "active_minutes": 12,
        })

        resolved = session_lib.resolve_session_file(sid)

        self.assertFalse(os.path.isfile(ours),
                         "our legacy record should be removed after migration")
        self.assertTrue(os.path.isfile(resolved))

    def test_fast_path_untouched(self):
        """An existing UUID-named file is returned as-is; nothing else touched."""
        sid = "2e8b3003-aaaa-bbbb-cccc-000000000003"
        uuid_file = self._write(f"{sid}.json", {"session_id": sid, "start": "2026-07-01T00:00:00Z"})
        bystander = self._write("99999.json", {"pid": 99999, "sessionId": "other", "peerProtocol": 1})

        resolved = session_lib.resolve_session_file(sid)

        self.assertEqual(resolved, uuid_file)
        self.assertTrue(os.path.isfile(bystander))


if __name__ == "__main__":
    unittest.main(verbosity=2)
