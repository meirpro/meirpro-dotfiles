#!/usr/bin/env python3
"""
Claude Code Notification Hook - Task Completion Announcer
Plays audio clips when Claude completes tasks or needs user input.

Cross-platform: macOS (afplay), Linux (paplay/aplay), Windows (start).
Exits silently (code 0) if audio files are missing or player unavailable.
"""

import sys
import json
import subprocess
import platform
from pathlib import Path


def play_audio(audio_file):
    """Play audio file using the platform's audio player."""
    system = platform.system()
    try:
        if system == "Darwin":
            subprocess.run(["afplay", str(audio_file)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif system == "Linux":
            # Try paplay (PulseAudio) first, then aplay (ALSA)
            for player in ["paplay", "aplay", "mpv", "ffplay"]:
                try:
                    args = [player, str(audio_file)]
                    if player == "ffplay":
                        args = ["ffplay", "-nodisp", "-autoexit", str(audio_file)]
                    subprocess.run(args, check=True,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    return
                except FileNotFoundError:
                    continue
        elif system == "Windows":
            # Use PowerShell to play audio on Windows
            subprocess.run(
                ["powershell", "-c",
                 f'(New-Object Media.SoundPlayer "{audio_file}").PlaySync()'],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        pass  # Silently fail — audio is optional


def get_audio_file_for_event(event_data):
    """Determine which audio file to play based on event context."""
    notification_type = event_data.get("notification_type", "").lower()
    message = event_data.get("message", "").lower()

    if "task_complete" in notification_type or "complete" in message:
        return "task_complete.mp3"
    elif "awaiting" in notification_type or "waiting" in message or "input" in message:
        return "awaiting_instructions.mp3"
    elif "build" in notification_type or "build" in message:
        return "build_complete.mp3"
    elif "error" in notification_type and "fixed" in message:
        return "error_fixed.mp3"
    else:
        return "ready.mp3"


def main():
    """Main function for Claude Code notification hook."""
    audio_dir = Path(__file__).parent.parent / "audio"

    # Exit silently if audio directory doesn't exist (user opted out)
    if not audio_dir.exists() or not any(audio_dir.glob("*.mp3")):
        sys.exit(0)

    # Try to read event data from stdin
    try:
        input_data = json.load(sys.stdin)
        audio_file = get_audio_file_for_event(input_data)
    except (json.JSONDecodeError, Exception):
        if len(sys.argv) > 1:
            audio_file = f"{sys.argv[1]}.mp3"
        else:
            audio_file = "task_complete.mp3"

    audio_path = audio_dir / audio_file

    if not audio_path.exists():
        # Try fallback
        audio_path = audio_dir / "task_complete.mp3"
        if not audio_path.exists():
            sys.exit(0)

    play_audio(audio_path)


main()
