#!/usr/bin/env python3
"""
Claude Code sound hook — config-driven ringtone + optional voice player.

Plays a ringtone for a given hook event, optionally followed (after a gap) by a
spoken voice clip. All "what plays when" lives in ~/.claude/audio/sounds.json, so
retuning never touches settings.json.

Usage
  play_sound.py <EventKey> [--dry-run]   # e.g. Stop, Notification, PreToolUse:Task
  play_sound.py --cancel                 # stop any in-flight cancelable sequence

Behaviour
  - Silent no-op (exit 0) if config "enabled" is false or ~/.claude/audio/.muted exists.
  - Resolves <EventKey> -> {sounds:[...], voice?, cancelable?, single_flight?} from config.
  - Picks ONE sound at random from the list (1-item list = deterministic). An empty
    "sounds" with a "voice" set is voice-only (no ringtone, no leading gap).
  - Plays detached in its own process group:  afplay <ring?> ; sleep <gap> ; afplay <voice?>
    so the hook returns instantly and the sound keeps playing.
  - cancelable events record their PID; --cancel (wired to UserPromptSubmit) kills the
    whole group, so the moment you continue, the chime/voice stops mid-play.
  - single_flight events take a per-event lock and DROP (not queue) any new fire while
    one is still sounding — so a burst (e.g. a parallel subagent fleet) never overlaps.
  - Always exits 0 — audio is best-effort and must never block or fail the session.
"""

import os
import sys
import json
import signal
import random
import shlex
import subprocess
from pathlib import Path

AUDIO_DIR = Path.home() / ".claude" / "audio"
RING_DIR = AUDIO_DIR / "ringtones"
VOICE_DIR = AUDIO_DIR
CONFIG = AUDIO_DIR / "sounds.json"
MUTE = AUDIO_DIR / ".muted"
STATE = AUDIO_DIR / ".playing.pgid"


def load_config():
    try:
        return json.loads(CONFIG.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def read_event():
    """Best-effort read of the hook's JSON payload from stdin (empty if none/tty)."""
    if sys.stdin.isatty():
        return {}
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def pick_voice_auto(event):
    """Content-aware voice selection (ported from play_audio.py)."""
    nt = str(event.get("notification_type", "")).lower()
    msg = str(event.get("message", "")).lower()
    if "task_complete" in nt or "complete" in msg:
        return "task_complete.mp3"
    if "awaiting" in nt or "waiting" in msg or "input" in msg:
        return "awaiting_instructions.mp3"
    if "build" in nt or "build" in msg:
        return "build_complete.mp3"
    if "error" in nt and "fixed" in msg:
        return "error_fixed.mp3"
    return "ready.mp3"


def cancel():
    """Kill the in-flight cancelable sequence, if any."""
    try:
        pid = int(STATE.read_text().strip())
    except (OSError, ValueError):
        return
    try:
        os.killpg(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        pass
    try:
        STATE.unlink()
    except OSError:
        pass


def lock_path_for(event_key):
    """Per-event single-flight lock file (event key sanitized for a filename)."""
    safe = "".join(c if c.isalnum() else "_" for c in event_key)
    return AUDIO_DIR / f".sf-{safe}.lock"


def acquire_single_flight(lock_path):
    """Atomically claim a single-flight lock so an event never overlaps itself.

    Returns True if claimed (caller plays, and the launched sequence rm's the lock
    when it ends), False if a live holder is already sounding. A stale lock — one
    whose recorded process group is no longer alive — is reclaimed.
    """
    try:
        os.close(os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
        return True
    except FileExistsError:
        pass
    # A lock exists. Reclaim only if its recorded process group is dead.
    try:
        pgid = int(lock_path.read_text().strip() or "0")
    except (OSError, ValueError):
        pgid = 0
    if pgid <= 0:
        return False  # holder just claimed it, hasn't written its pgid yet → busy
    try:
        os.killpg(pgid, 0)  # signal 0 == liveness probe
        return False  # holder still playing
    except ProcessLookupError:
        pass  # holder dead → stale lock, reclaim below
    except OSError:
        return False  # can't probe (e.g. permission) → assume busy
    try:
        lock_path.unlink()
        os.close(os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
        return True
    except (OSError, FileExistsError):
        return False


def launch(ring_path, gap, voice_path, cancelable, lock_path=None):
    """Play ring -> (gap -> voice) detached in a fresh process group.

    Either part may be omitted: ring-only, voice-only, or the full
    ring -> gap -> voice. The gap is inserted only when both are present.
    When lock_path is set, the launched sequence removes it when it ends, so the
    single-flight lock clears the moment this event's sound is over.
    """
    parts = []
    if ring_path is not None:
        parts.append(f"afplay {shlex.quote(str(ring_path))}")
    if voice_path is not None:
        if ring_path is not None:
            parts.append(f"sleep {gap}")
        parts.append(f"afplay {shlex.quote(str(voice_path))}")
    cmd = " ; ".join(parts)
    if lock_path is not None:
        cmd = f"{cmd} ; rm -f {shlex.quote(str(lock_path))}"
    proc = subprocess.Popen(
        ["bash", "-c", cmd],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,  # new session => proc.pid is the process-group leader
    )
    if cancelable:
        try:
            STATE.write_text(str(proc.pid))
        except OSError:
            pass
    if lock_path is not None:
        try:
            lock_path.write_text(str(proc.pid))  # record pgid so a crash leaves a reclaimable lock
        except OSError:
            pass


def resolve(cfg, event_key, event):
    """Return (ring_path_or_None, gap, voice_path_or_None, cancelable, single_flight)
    or None if nothing to play.

    ring_path is None for a voice-only event (empty/missing "sounds" but a "voice" set).
    """
    entry = (cfg.get("events") or {}).get(event_key)
    if not entry:
        return None
    sounds = entry.get("sounds") or []
    ring_path = RING_DIR / random.choice(sounds) if sounds else None

    voice_path = None
    voice = entry.get("voice")
    if voice:
        voice_name = pick_voice_auto(event) if voice == "auto" else voice
        voice_path = VOICE_DIR / voice_name

    if ring_path is None and voice_path is None:
        return None

    gap = cfg.get("gap_seconds", 2)
    cancelable = bool(entry.get("cancelable", False))
    single_flight = bool(entry.get("single_flight", False))
    return ring_path, gap, voice_path, cancelable, single_flight


def main():
    args = sys.argv[1:]
    if "--cancel" in args:
        cancel()
        return

    dry_run = "--dry-run" in args
    positional = [a for a in args if not a.startswith("--")]
    if not positional:
        return
    event_key = positional[0]

    cfg = load_config()
    if not cfg.get("enabled", True) or MUTE.exists():
        if dry_run:
            print(f"[disabled] would skip {event_key}")
        return

    event = read_event()
    resolved = resolve(cfg, event_key, event)
    if resolved is None:
        if dry_run:
            print(f"[no-mapping] nothing configured for {event_key}")
        return

    ring_path, gap, voice_path, cancelable, single_flight = resolved
    if dry_run:
        ring_str = str(ring_path.name) if ring_path else "(none)"
        voice_str = str(voice_path.name) if voice_path else "(none)"
        print(
            f"{event_key}: ring={ring_str} gap={gap}s "
            f"voice={voice_str} cancelable={cancelable} single_flight={single_flight}"
        )
        return

    lock_path = None
    if single_flight:
        lock_path = lock_path_for(event_key)
        if not acquire_single_flight(lock_path):
            return  # this event is already sounding — drop, never overlap

    if cancelable:
        cancel()  # never stack two cancelable sequences
    launch(ring_path, gap, voice_path, cancelable, lock_path)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # best-effort: never surface a hook error to the session
    sys.exit(0)
