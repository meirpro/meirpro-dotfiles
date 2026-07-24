---
name: transcribe-audio
description: This skill should be used when the user shares a local audio file (WhatsApp voice notes, .opus, .m4a, .mp3, .wav, voice memos) and wants to know what it says — "listen to this", "transcribe this", "what does this recording say". Runs a locally-cached Whisper model fully offline via the bundled script; no API, no upload.
---

# Transcribe Audio

## Overview

Transcribe local audio files to text using `openai/whisper-large-v3-turbo`
loaded through HuggingFace `transformers` — fully offline once cached
(~1.5GB at `~/.cache/huggingface/hub/models--openai--whisper-large-v3-turbo`).
The Read tool cannot open audio files at all; this skill is the working path.

## Quick Start

```bash
PY=$HOME/git/experiments/OmniVoice/.venv/bin/python3
$PY ~/.claude/skills/transcribe-audio/scripts/transcribe_audio.py "/path/to/audio.opus"
# Force a language (helps accented/multilingual speech):
$PY ~/.claude/skills/transcribe-audio/scripts/transcribe_audio.py "/path/to/audio.opus" --language english
```

The interpreter matters: the script needs `torch` + `transformers` +
`soundfile`. The OmniVoice venv above is the known-good environment on this
machine (transformers 5.x, torch with MPS). If it's gone, any venv with
those three packages works; `ffmpeg` must be on PATH (`brew install ffmpeg`,
already installed).

## Environment discovery — don't repeat these dead ends

- `pip list | grep whisper` finding nothing does NOT mean Whisper is
  unavailable. The `transformers` ASR pipeline loads Whisper weights
  directly — the `openai-whisper` / `faster-whisper` packages are separate
  products and their absence is meaningless. Check for `transformers` +
  cached weights instead: `ls ~/.cache/huggingface/hub/ | grep -i whisper`.
- macOS 26 has no CLI speech-to-text; Shortcuts' "Transcribe Audio" action
  exists but is interactive. Don't burn time hunting for a built-in.

## Handling the output

- **Spoken numbers are unreliable.** Whisper garbles digits routinely
  ("335" ↔ "339", "1,005" ↔ "1,017"). Flag every number in a transcript as
  needing confirmation by ear before anyone acts on it.
- **Hebrew/Yiddish loanwords in English speech** come out mangled
  ("kachad", "davening" may survive; sefer names usually don't). Reconstruct
  from context and say so, don't present the raw form as fact.
- **Short punctuation-only output ("!!!", "you!") is hallucination, not
  transcription.** The script warns when it detects this. It means Whisper
  failed on that audio (accent, distortion, music, crosstalk) — NOT that the
  file is silent (the script prints mean dB; normal speech is ~-15 to -25dB).
  Escalation path, in order:
  1. Re-run with `--language <spoken language>` (try `english`, `hebrew`,
     `yiddish` as appropriate).
  2. Re-run with `--robust` — enables the anti-hallucination recipe
     (temperature fallback, `condition_on_prev_tokens=False`, thresholds)
     and 20s chunking with per-chunk output.
  3. **Look at the audio with a spectrogram** — Claude can't listen but CAN
     read a spectrogram image, and speech (dense vertical syllable
     striations with pauses, energy under ~10kHz) vs music vs silence are
     visually unmistakable:
     `ffmpeg -i in.opus -lavfi "showspectrumpic=s=1200x400:legend=1" spec.png`
     then Read the PNG. This settles "is the file even speech?" decisively
     before burning more model attempts.
  4. Escalate the model: `--model openai/whisper-large-v3` (the full
     non-distilled model, ~3GB first download, noticeably more robust than
     turbo on accented/unclear speech). Turbo's distilled decoder can
     collapse to '!!!' on audio the full model handles.
  5. If still empty, tell the user which file failed and what the
     spectrogram showed, and ask what's in it (speaker, language) rather
     than silently dropping it — partial results from some files ≠ all
     files handled.

  Observed 2026-07-08 (4 WhatsApp voice notes, same sender/day): the root
  cause of the '!!!' files was **clipping** — `ffmpeg -af volumedetect`
  showed `max_volume: 0.0 dB` (full-scale = mic overload), and the zoomed
  spectrogram showed broadband splatter to 10kHz + overload harmonics
  instead of clean voiced-speech striations. Humans parse clipped speech;
  Whisper (any size) doesn't. Outcome matrix from that session:
  - Full large-v3 **rescued the skipped opening** of a partly-degraded
    file that turbo had silently truncated (turbo returned only the tail
    with a "did not predict an ending timestamp" warning). A mid-sentence
    transcript start = re-run with large-v3, there's likely more audio.
  - Fully-clipped files stayed unrecoverable by EVERYTHING: both models,
    language forcing (en/he/yi), --robust chunking, 0.5x/0.8x tempo,
    pitch-shift, task=translate, and ffmpeg `adeclip` + band-limit +
    `speechnorm`. When max_volume is 0.0dB and large-v3 still returns
    punctuation, stop burning compute — ask the human to listen, or get a
    cleaner copy from the sender.
  - Partial rescue matters: transcribe every file and compare — clipping
    is per-file, and cross-corroborating a clean file's numbers against a
    second model run catches digit garbling.

- **HuggingFace downloads via Python can stall or die while the network is
  fine.** Observed 2026-07-08: `snapshot_download` sat at 4.4MB for 40+
  minutes, and in a background shell died with `httpx.ConnectError: Bad
  file descriptor` — while a plain `curl` to the same host ran at 2MB/s.
  Diagnose with a ranged curl
  (`curl -sL -o /dev/null -w "%{speed_download} B/s" -r 0-2097151
  https://huggingface.co/<repo>/resolve/main/model.safetensors`); if that's
  fast, skip the Python downloader entirely and curl the files into a plain
  directory, then pass it as `--model <dir>`:

  ```bash
  D=~/.cache/whisper-large-v3-local; mkdir -p $D
  B="https://huggingface.co/openai/whisper-large-v3/resolve/main"
  for f in config.json generation_config.json preprocessor_config.json \
           tokenizer.json tokenizer_config.json special_tokens_map.json \
           vocab.json merges.txt normalizer.json added_tokens.json; do
    curl -sL -o "$D/$f" "$B/$f" &
  done; wait
  curl -sL -C - -o "$D/model.safetensors" "$B/model.safetensors"  # ~3GB, resumable
  ```

  `transformers` loads a local directory path exactly like a hub id, so
  `--model $D` just works. (whisper-large-v3 weights already live at
  `~/.cache/whisper-large-v3-local/` on this machine from that incident.)

## Self-upgrade rule

**This skill maintains itself.** After every real transcription session,
if anything was learned that would have saved time — a new failure mode, a
better flag/recipe, an environment change (venv moved, model re-downloaded,
new machine), a format quirk — edit this SKILL.md and/or
`scripts/transcribe_audio.py` immediately, in the same session, while the
context is fresh. Concretely:

- New Whisper failure mode observed → add it to "Handling the output" with
  the symptom and the fix that worked.
- Recipe/flag that rescued a bad transcription → fold it into the script as
  an option (or the default if strictly better), not just prose.
- Known-good interpreter path changed → update Quick Start.
- Something documented here turned out wrong → fix it, don't append a
  correction below the stale claim.

Keep the file lean while doing this: fold lessons into the existing
sections, prune anything obsolete. The goal is that the next session runs
one command and hits zero of the potholes this session hit.
