# Claude Code Hook Sounds

A config-driven sound system for Claude Code. Plays a **ringtone** (and optionally a
spoken **voice clip** after a short gap) when Claude Code fires lifecycle hook events —
finishing a turn, waiting on you, dispatching subagents, starting/ending a session, etc.

> **Status:** currently **ON** (`enabled: true` in `sounds.json`). Silence with
> `claude-sounds off`. Check anytime with `claude-sounds status`.

---

## Quick controls

```bash
claude-sounds on        # enable all hook sounds
claude-sounds off       # silence everything (hooks stay wired, just no-op)
claude-sounds toggle    # flip on<->off
claude-sounds status    # show current state
```

`off` is the master kill-switch: the player checks `enabled` first and exits before
playing **anything** — no ringtones and no voice clips, on any event. Fully reversible.

---

## How it works

- Every sound-producing hook in `~/.claude/settings.json` calls one thin dispatcher:
  `python3 ~/.claude/hooks/play_sound.py <EventKey>`.
- That script reads **`~/.claude/audio/sounds.json`** — the single source of truth for
  *what plays when*. **Retuning never touches `settings.json`; you only edit `sounds.json`.**
- For each event it picks **one sound at random** from that event's list, then plays it
  detached (so the hook returns instantly and the session never blocks).
- If the event has a `voice`, it plays `ring → wait gap_seconds → voice`. An event may
  also be **voice-only** — leave `sounds` empty and set a `voice`, and just the spoken
  clip plays with no ringtone and no leading gap. (This is how `Stop` is configured.)
- "Cancelable" events (Stop, Notification) record their process group; when you submit
  your next prompt, `UserPromptSubmit` runs `play_sound.py --cancel`, which kills the
  in-flight sequence — so the chime/voice stops the moment you continue.

---

## Files

| Path | Role |
|---|---|
| `~/.claude/audio/sounds.json` | **The config you edit.** Event → sounds/voice/options. |
| `~/.claude/audio/ringtones/` | Ringtone `.mp3` library. |
| `~/.claude/audio/*.mp3` | Voice clips (`task_complete`, `awaiting_instructions`, `ready`, `build_complete`, `error_fixed`). |
| `~/.claude/hooks/play_sound.py` | The player (random pick, ring→gap→voice, cancel). |
| `~/.claude/hooks/claude-sounds` | The `on/off/toggle/status` switch. |
| `~/.claude/settings.json` → `hooks` | Wires events to the player (see below). |

> `play_sound.py` and `claude-sounds` are real files in the **meirpro-dotfiles** repo
> (`claude/hooks/`), surfaced here via the symlinked `~/.claude/hooks/` directory — so
> they're version-controlled. `sounds.json` and the mp3s live only under `~/.claude/audio/`.

---

## Current mapping

| Hook event | Ringtone | then voice (after `gap_seconds`) | notes |
|---|---|---|---|
| `Stop` (turn finished) | *(none — voice only)* | `ready.mp3` — says **"ready"** | cancel-on-continue ✅ |
| `Notification` (waiting / permission) | `kim-possible-beep.mp3` | `auto` (content-aware) | cancel-on-continue ✅ |
| `SubagentStop` (a subagent finished + closed) | `batman-screen-change.mp3` / `batman-wave.mp3` (random) | `task_complete.mp3` — says **"task completed successfully"** | **single-flight** (never overlaps — see below) |
| `SessionStart` (`startup`) | `mario-bros-level-1-2.mp3` | — | — |
| `SessionEnd` | `mario-game-over.mp3` | — | — |

Spare ringtones in `ringtones/` (unassigned): `daffy-duck-evil-laugh`, `mario-level-up`,
`mario-jump`, `batman`, `road-runner-beep-beep`, `road-runner-beep-beep-short`.

### The turn-end & subagent voices

`Stop` fires every time Claude finishes a turn, so its sound is the one you hear most.
It is **voice-only** (no ringtone) and plays `ready.mp3` ("ready") — a neutral line
that's true no matter how the turn ended (success, a question, or a reported error).

`SubagentStop` fires when a dispatched subagent finishes and closes — a genuine,
discrete task completion — so it plays the batman ringtone followed by `task_complete.mp3`
("task completed successfully"). The clips and what they say:

| Voice clip | Says (approx.) | Where it fits |
|---|---|---|
| `ready.mp3` | "ready" | **`Stop`** — neutral turn-end, true regardless of outcome |
| `task_complete.mp3` | "task completed successfully" | **`SubagentStop`** — a worker genuinely completed its task |
| `awaiting_instructions.mp3` | "awaiting instructions" | spare — `Notification` `auto` uses it for "waiting" content |
| `build_complete.mp3` | "build complete" | spare — narrow, only apt after a build |
| `error_fixed.mp3` | "error fixed" | spare — narrow, only apt after a fix |

> **Why `SubagentStop` is single-flight:** it fires once per subagent, so a parallel
> fleet (10–25 agents) would otherwise stack 25 overlapping "task completed successfully"
> at the end of a run. With `"single_flight": true`, only one sequence sounds at a time
> and any fire arriving while it plays is **dropped** (not queued) — one clean chime per
> burst, never a pileup.

---

## Editing `sounds.json`

```jsonc
{
  "enabled": true,            // master on/off (claude-sounds flips this)
  "gap_seconds": 2,           // pause between ringtone and voice
  "events": {
    "Stop": {
      "sounds": [],                        // empty + a voice set → voice-only (no ringtone)
      "voice": "ready.mp3",                // the spoken clip; plays on its own here
      "cancelable": true                   // optional: killed on your next prompt
    },
    "SubagentStop": {
      "sounds": ["batman-screen-change.mp3", "batman-wave.mp3"],  // 2+ = random rotation
      "voice": "task_complete.mp3",        // batman ring → gap → this voice
      "single_flight": true                // never overlaps itself; bursts are dropped
    }
  }
}
```

**Per-event keys:**

| Key | Meaning |
|---|---|
| `sounds` | Array of filenames in `ringtones/`. One is chosen at random per fire. A 1-item list = always that sound. Empty/missing = no ringtone (the event is then voice-only if a `voice` is set, otherwise silent). |
| `voice` | Optional. Filename in `~/.claude/audio/`, **or** `"auto"` to pick the voice clip from the notification's content (waiting → `awaiting_instructions`, complete → `task_complete`, etc.). Omit for ringtone-only; set it with an empty `sounds` for voice-only. |
| `cancelable` | Optional `true`. The sequence is killed when you submit your next prompt. |
| `single_flight` | Optional `true`. The event never overlaps itself: while one sequence is sounding, any new fire is **dropped** (not queued). Use for events that fire in bursts (e.g. `SubagentStop` in a parallel fleet). |

**Common edits**
- *Add randomness:* add more filenames to a `sounds` array.
- *Swap a sound:* change the filename (must exist in `ringtones/`).
- *Change the pause:* edit `gap_seconds`.
- *Disable one event:* remove its entry (or empty `sounds` **and** drop `voice` — an
  empty `sounds` alone still plays the voice).
- *Disable everything:* `claude-sounds off`.

After editing, sanity-check what an event would play without making noise:

```bash
python3 ~/.claude/hooks/play_sound.py Stop --dry-run
```

---

## Adding a new ringtone

Drop an `.mp3` into `~/.claude/audio/ringtones/`, then reference its filename in any
event's `sounds` array. (Keep names descriptive, kebab-case.)

## Wiring a brand-new event

The available hook events Claude Code fires include: `PreToolUse`, `PostToolUse`,
`Notification`, `Stop`, `SubagentStop`, `UserPromptSubmit`, `SessionStart`,
`SessionEnd`, `PreCompact`. To sound on one not yet wired:

1. Add a `"<EventKey>": { "sounds": [...] }` block to `sounds.json`.
2. Add a hook in `~/.claude/settings.json` → `hooks.<Event>` calling
   `python3 ~/.claude/hooks/play_sound.py <EventKey>` (with a `matcher` if the event
   supports one — e.g. tool name for `PreToolUse`/`PostToolUse`, `startup` for
   `SessionStart`). The `<EventKey>` you pass is just the lookup key into `sounds.json`;
   for matcher-scoped hooks use a compound key like `PreToolUse:Task`.

---

## Troubleshooting

- **No sound at all:** check `claude-sounds status`. If `off`, run `claude-sounds on`.
- **Edited `settings.json` and nothing fires:** Claude Code's settings watcher may not
  hot-reload new hooks mid-session. Open `/hooks` once (forces a reload) or restart.
  Edits to `sounds.json` *do* take effect immediately (read fresh on every event).
- **A specific event is silent:** `python3 ~/.claude/hooks/play_sound.py <EventKey> --dry-run`
  prints what it would play (or `[no-mapping]` / `[disabled]`).
- **Audio plays but you can't hear it:** the player uses macOS `afplay`; confirm system
  volume / output device.

---

## Design notes

- **Thin hooks, fat config:** all "what plays when" lives in `sounds.json`, so the wiring
  in `settings.json` is stable and you rarely touch it.
- **Non-blocking + cancelable:** sounds run in their own process group (`start_new_session`),
  so the hook returns instantly and the whole `ring → sleep → voice` chain can be killed
  cleanly in one `os.killpg`.
- **Best-effort:** the player always exits 0 and swallows errors — a missing file or audio
  glitch never blocks or fails a Claude Code turn.
