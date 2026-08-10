---
name: multi-agent-verification
description: "Structure and cost a delegated verify-then-fix run — when the task is to confirm a system behaves as intended across several dimensions and then fix what's found, and the work is big enough to hand to parallel subagents. Also use when estimating or quoting such a run (agent counts, wall time, subagent spend). Measured on a real run 2026-06. Not for a single bug, a code review, or any task one session can finish inline."
---

# Multi-agent verify-then-fix

Two delegated phases. The orchestrating session scouts inline first — find the
exact files, grab `file:line` anchors for each behavior — then stays thin.
Delegation is what keeps the main context flat and the session usable
afterwards.

## Phase 1 — adversarial verification

Background, non-frontier / sonnet-class agents.

- **One verifier per behavior dimension.** A "works" verdict requires
  **executed tests** — scratch tests written in the project's real test
  harness, run, then deleted. Never code-reading alone. Code-reading supports
  only "the path doesn't exist" claims, with `file:line` citations.
- **Every reported issue goes to a second, adversarial skeptic agent** that
  tries to refute it with its own executed tests before it counts as
  confirmed. This kills plausible-but-wrong findings before any fix effort is
  spent, and the survivors arrive with ready-made repro tests and exact
  anchors — which is what makes Phase 2 cheap.
- **Parallel agents share the checkout.** Each owns a uniquely-named scratch
  test file, deletes it when done, touches nothing else, never commits.

## Phase 2 — grouped fix delegation

Decisions pre-made by the orchestrator and written into the prompts.

- **Group fixes by file ownership, not topic.** No two parallel agents may
  touch the same file; groups sharing a file run sequentially. Expect
  cross-file fallout no agent owns — a signature change breaking a caller
  outside every group. The orchestrator fixes those seams itself.
- **Each agent** works test-first, self-times with `date +%s` per fix and
  reports per-fix elapsed, runs only its own tests, reports typecheck errors
  only in its own files, never commits, never runs repo-wide formatters.
- **The orchestrator** then runs the full suite + typecheck, **attributes any
  failures before reacting** (parallel sessions may have broken something
  unrelated — check `git status` for files no agent owned), and commits in
  small logical chunks by named files. Files entangled with another session's
  uncommitted work get held and reported, not committed.

## Measured economics

One full run, 2026-06. Use to calibrate estimates.

| Phase | Scale | Wall | Subagent tokens | Cost |
|---|---|---|---|---|
| Verification | 8 dimensions → 25 agents, ~160 executed tests | ~18 min | ~1.5M | ~$22 |
| Fixes | 16 confirmed issues → 5 grouped agents (3 parallel + 1 sequenced + orchestrator seams) | ~31 min | ~344k | ~$12 |

- **16/17 findings survived the skeptics** — the adversarial pass is worth its
  cost.
- **The fix phase cost roughly half the verification phase** despite writing
  all the code. Tightly-specced agents — file lists, acceptance tests,
  decisions already made — don't wander.
- Individual fix groups ran ~2–10 min; a 4-fix group ~7 min.
- **Orchestrator context grew only ~4 percentage points across the entire fix
  phase.** That headroom is the point: delegation isn't just parallelism, it's
  what lets one session verify, fix, commit, and still handle follow-ups.

## Estimate calibration

A verified bug with a repro test and a `file:line` anchor, delegated to a
specced sonnet-class agent, lands in **~2–10 min AI each** (a batch of ~16:
~30 min AI wall).

Quote verification-of-a-subsystem as **~20 min AI + ~$20–25 in subagent
spend**, and say the spend out loud — it's billed differently from the
orchestrator's own time.

See the time-estimate rule in the global CLAUDE.md for the
`~2-4 h human / ~20 min AI` dual format these numbers feed.
