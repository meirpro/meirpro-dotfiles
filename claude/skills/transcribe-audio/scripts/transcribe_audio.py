#!/usr/bin/env python3
"""
Transcribe a local audio file (WhatsApp voice notes, .opus/.m4a/.mp3/.wav/
anything ffmpeg can decode) to text using a locally-cached Whisper model.

Runs fully offline once the model is cached — no API key, no upload, no
per-file cost. Uses HuggingFace `transformers`' ASR pipeline with
openai/whisper-large-v3-turbo (NOT the `openai-whisper` or `faster-whisper`
pip packages — those are a red herring; `pip list | grep whisper` will show
nothing even when this works fine).

Usage:
    python3 transcribe_audio.py "/path/to/audio.opus"
    python3 transcribe_audio.py "/path/to/audio.opus" --language en
    python3 transcribe_audio.py "/path/to/audio.opus" --python /path/to/venv/bin/python3

If run with the system python and `transformers`/`torch` aren't installed,
re-exec yourself with --python pointing at a venv that has them (see
SKILL.md for how to find or create one).
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path


def convert_to_wav(src: Path) -> Path:
    """Pre-convert to 16kHz mono WAV via ffmpeg. Not strictly required (the
    ASR pipeline can decode most formats directly via ffmpeg internally),
    but a clean WAV avoids occasional container/codec-specific decode
    quirks and makes duration/silence checks trivial."""
    if shutil.which("ffmpeg") is None:
        raise RuntimeError(
            "ffmpeg not found on PATH. Install it (`brew install ffmpeg`) "
            "or pass an already-decoded .wav file."
        )
    tmp = Path(tempfile.mkdtemp()) / "audio.wav"
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-ar", "16000", "-ac", "1", str(tmp)],
        check=True,
        capture_output=True,
    )
    return tmp


def check_audio_level(wav_path: Path) -> float:
    """Return mean volume in dB via ffmpeg volumedetect. Used only to warn
    the user when a suspicious transcript (e.g. just '!!!') might actually
    be near-silent audio rather than a real transcription failure."""
    result = subprocess.run(
        ["ffmpeg", "-i", str(wav_path), "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True,
        text=True,
    )
    for line in result.stderr.splitlines():
        if "mean_volume" in line:
            return float(line.split(":")[1].strip().split(" ")[0])
    return float("nan")


def looks_hallucinated(text: str) -> bool:
    """Whisper's silence/unclear-audio failure mode: short repeated
    punctuation or filler ('!!!', 'you!', 'Thank you.') instead of an
    error. Detect it so callers can escalate instead of trusting it."""
    stripped = text.strip()
    return len(stripped) < 5 or all(c in "!?. " for c in stripped)


def transcribe(
    audio_path: str, language: str | None, model_name: str, robust: bool = False
) -> str:
    warnings.filterwarnings("ignore")
    from transformers import pipeline
    import torch
    import soundfile as sf

    src = Path(audio_path).expanduser()
    if not src.exists():
        raise FileNotFoundError(src)

    device = "mps" if torch.backends.mps.is_available() else (
        "cuda" if torch.cuda.is_available() else "cpu"
    )
    print(f"Loading {model_name} on {device} ...", file=sys.stderr)
    asr = pipeline("automatic-speech-recognition", model=model_name, device=device)

    wav_path = convert_to_wav(src)
    try:
        mean_db = check_audio_level(wav_path)
        audio, sr = sf.read(str(wav_path))
        duration = len(audio) / sr

        gen: dict = {}
        if language:
            gen["language"] = language

        if not robust:
            kwargs = {}
            # Long-form (>30s) generation REQUIRES return_timestamps=True or
            # transformers raises: "You have passed more than 3000 mel input
            # features (> 30 seconds) which automatically enables long-form
            # generation which requires the model to predict timestamp
            # tokens."
            if duration > 30:
                kwargs["return_timestamps"] = True
            if gen:
                kwargs["generate_kwargs"] = gen
            result = asr({"array": audio, "sampling_rate": sr}, **kwargs)
            text = result["text"].strip()
        else:
            # Anti-hallucination recipe (the same fallback stack the original
            # openai-whisper CLI uses): temperature ladder + quality
            # thresholds + no conditioning on previous output, applied to
            # 20s chunks so one bad stretch can't poison the whole file.
            gen.update(
                {
                    "temperature": (0.0, 0.2, 0.4, 0.6, 0.8, 1.0),
                    "logprob_threshold": -1.0,
                    "no_speech_threshold": 0.6,
                    "compression_ratio_threshold": 1.35,
                    "condition_on_prev_tokens": False,
                }
            )
            chunk_s = 20
            pieces = []
            for start in range(0, int(duration) + 1, chunk_s):
                seg = audio[start * sr : (start + chunk_s) * sr]
                if len(seg) < sr // 2:  # skip trailing fragments <0.5s
                    continue
                out = asr(
                    {"array": seg, "sampling_rate": sr}, generate_kwargs=dict(gen)
                )["text"].strip()
                print(f"  [{start:>4}s] {out!r}", file=sys.stderr)
                if not looks_hallucinated(out):
                    pieces.append(out)
            text = " ".join(pieces).strip()

        if looks_hallucinated(text):
            print(
                f"WARNING: transcript looks empty/hallucinated ({text!r}) "
                f"despite {duration:.1f}s of audio at {mean_db:.1f}dB mean "
                "volume. This is a known Whisper failure mode on unclear "
                "speech (heavy accent/distortion/non-verbal audio) rather "
                "than silence if mean_db is within normal speech range "
                "(~-15 to -25dB). "
                + (
                    "Confirm by ear what's actually in the file."
                    if robust
                    else "Re-run with --robust before giving up."
                ),
                file=sys.stderr,
            )
        return text
    finally:
        shutil.rmtree(wav_path.parent, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio_path", help="Path to the audio file")
    parser.add_argument(
        "--language",
        default=None,
        help="Force a language (e.g. 'english', 'hebrew'). Default: auto-detect.",
    )
    parser.add_argument(
        "--model",
        default="openai/whisper-large-v3-turbo",
        help="HuggingFace model id or local path (default: whisper-large-v3-turbo).",
    )
    parser.add_argument(
        "--robust",
        action="store_true",
        help="Anti-hallucination mode: temperature-fallback recipe over 20s "
        "chunks. Slower; use when the default pass returns '!!!'-style "
        "hallucinated output.",
    )
    args = parser.parse_args()

    text = transcribe(args.audio_path, args.language, args.model, robust=args.robust)
    print(text)


if __name__ == "__main__":
    main()
