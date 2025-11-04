#!/usr/bin/env python3
"""
Claude Code Notification Hook - Task Completion Announcer
Plays audio clips when Claude completes tasks or needs user input
"""

import sys
import json
import subprocess
from pathlib import Path


def play_audio(audio_file):
    """Play audio file using system audio player"""
    try:
        # Use afplay on macOS
        subprocess.run(["afplay", str(audio_file)], check=True)
    except subprocess.CalledProcessError:
        print(f"Failed to play audio: {audio_file}", file=sys.stderr)
    except FileNotFoundError:
        print(
            "Audio player not found. Install afplay or modify script for your system.",
            file=sys.stderr
        )


def get_audio_file_for_event(event_data):
    """Determine which audio file to play based on event context"""
    # Extract notification type or message content
    notification_type = event_data.get("notification_type", "")
    message = event_data.get("message", "")
    tool_name = event_data.get("tool_name", "")

    # Map events to audio files
    if "task_complete" in notification_type.lower() or "complete" in message.lower():
        return "task_complete.mp3"
    elif "awaiting" in notification_type.lower() or "waiting" in message.lower() or "input" in message.lower():
        return "awaiting_instructions.mp3"
    elif "build" in notification_type.lower() or "build" in message.lower():
        return "build_complete.mp3"
    elif "error" in notification_type.lower() and "fixed" in message.lower():
        return "error_fixed.mp3"
    else:
        # Default to ready sound
        return "ready.mp3"


def main():
    """Main function for Claude Code notification hook"""
    # Get audio directory
    audio_dir = Path(__file__).parent.parent / "audio"

    # Debug log
    log_file = Path.home() / ".claude/hooks/audio_debug.log"

    # Try to read event data from stdin
    try:
        input_data = json.load(sys.stdin)
        with open(log_file, "a") as f:
            f.write(f"\n{'='*60}\n")
            f.write(f"Event data received:\n{json.dumps(input_data, indent=2)}\n")
        audio_file = get_audio_file_for_event(input_data)
        with open(log_file, "a") as f:
            f.write(f"Selected audio: {audio_file}\n")
    except (json.JSONDecodeError, Exception) as e:
        # Fallback to command line argument or default
        if len(sys.argv) > 1:
            audio_file = f"{sys.argv[1]}.mp3"
        else:
            audio_file = "task_complete.mp3"
        with open(log_file, "a") as f:
            f.write(f"\n{'='*60}\n")
            f.write(f"Error reading stdin: {e}\n")
            f.write(f"Using fallback: {audio_file}\n")
        print(f"Could not read event data, using fallback: {audio_file}", file=sys.stderr)

    # Full path to audio file
    audio_path = audio_dir / audio_file

    # Check if audio file exists
    if not audio_path.exists():
        print(f"Audio file not found: {audio_path}", file=sys.stderr)
        # Try fallback to task_complete
        audio_path = audio_dir / "task_complete.mp3"
        if not audio_path.exists():
            print("No audio files found. Check ~/.claude/audio/", file=sys.stderr)
            sys.exit(1)

    # Play the audio
    play_audio(audio_path)


main()
