# Team Development Rules

> Shared configuration from [meirpro-dotfiles](https://github.com/meirpro/meirpro-dotfiles).
> Hooks automatically check TypeScript, lint, and format on every file save.

## Code Quality

- Check TypeScript (`npx tsc --noEmit`) and linting (`npm run lint`) after making changes to ensure nothing is broken. Linting issues are suggestions — follow them when correct, but they can occasionally be wrong.
- Don't use placeholder or "coming soon" code — always implement full functionality.
- Format code with the project's formatter (Prettier, etc.) after editing files.
- **Write tests alongside implementation, not after** — write or update tests as you build, not as a separate follow-up step. Tests written after the fact tend to just confirm what the code already does rather than validating correctness.

## Time Estimates — always give both human and AI

Whenever you quote a time estimate for a task (in TODO docs, scope discussions, planning replies, anywhere it would help me decide what to hand off vs do myself), give **both** numbers, every time:

- **Human:** developer-hours assuming the real workflow — read code, decide, type, run CI between iterations, second-guess naming, switch contexts, get pulled into Slack mid-task. This is what you'd quote a teammate.
- **AI:** wall-clock minutes for a Claude Code session, bounded by tool roundtrips, file reads/writes, and tsc/test runs. The clock starts when you have a clear directive and stops when the work is committed and verified.

Format: `~2-4 h human / ~20 min AI`, or for backlog items inside `🟢 / 🟡 / 🔴` annotations: `🟢 ~30 min human / ~5 min AI`.

**Both estimates are workload-based, not a fixed conversion ratio.** What compresses vs what doesn't:

- **Compresses dramatically for AI** (typing, mechanical refactors across many files, regenerating boilerplate, running tsc/test loops, writing test fixtures, navigating large codebases via grep).
- **Compresses moderately** (deciding where a new module belongs, naming, working out an API surface — still faster but you do think before typing).
- **Doesn't compress at all**:
  - Real-device verification (iPhone/Android perf, actual touch handling).
  - External coordination (email to vendor, WhatsApp to publisher, OAuth setup with a third party).
  - Migration verification that requires watching real user data behave across sync.
  - Anything where the bottleneck is "wait for human to look at this and decide" or "wait for CI to deploy and then poke the staging URL."
  - Long debugging sessions where the answer requires accumulated context about *this specific user's* setup or data.

For tasks where AI cannot meaningfully compress, write `AI: n/a — verification only` or `AI: ~5 min prep, then human` so the dual format stays consistent.

**Don't sandbag the AI number.** If the work is mechanical and ~15 minutes is the honest estimate, say 15 minutes — don't pad to feel safer. The whole point of the dual format is that the user can decide quickly which tasks are worth picking up themselves vs handing off.

## Git Safety

> ⚠ **The four staging rules below are ENFORCED at the binary level by
> the `safe-git` wrapper at `~/bin/git` → `meirpro-dotfiles/git/safe-git`.**
> Violating any of them returns exit 64 with a printed explanation —
> the real `git` is never reached. This is intentional: rules in
> CLAUDE.md alone get forgotten in the middle of a long session.
>
> Bypass for legitimate edge cases: prefix the command with
> `GIT_UNSAFE_STAGE=1`. Bypasses are logged to `~/.claude/git-bypass.log`.

- **Always pull the latest changes before starting work**: `git pull origin $(git branch --show-current)`. This avoids merge conflicts and wasted effort from working on stale code.
- **NEVER include these lines in commit messages:**
  ```
  Generated with Claude Code

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```
- **NEVER use `git add -A` or `git add .`** — always stage specific files by name. `-A` and `.` stage every changed file in the tree, including ones edited by parallel agents or generated artifacts. *(Hook-enforced: `safe-git` refuses both before reaching real git.)*
- **NEVER stage files and commit in separate commands** (e.g. `git add file` then `git commit`). Always combine into a single shell invocation: `git add file1 file2 && git commit -m "message"`. *(Hook-enforced: `safe-git` requires `git add ... && git commit` in the parent shell command for any add or commit invocation.)*
- **NEVER use `git commit -a`** — it's `git add -A` in disguise. *(Hook-enforced.)*
- Review `git status` and `git diff` before committing. If you see changed files that you did NOT modify, another agent may be working in parallel — do NOT stage or commit those files.
- **Run tests before committing** if the project has a test suite. Check `package.json` for `test`, `test:unit`, or similar scripts. A quick `npm test` catches regressions before they're pushed.
- **Keep commits small and logically grouped.** Each commit should represent ONE logical change (one feature, one bug fix, one refactor). If you've made changes across many files, split them into multiple commits by concern. A commit touching 10+ files is a warning sign — 94 files in one commit is unacceptable. Large commits are nearly impossible to review, debug, or revert. When in doubt, commit more often, not less.
- **Commit completed work proactively (overrides "only commit when asked").** When you finish writing a file that is logically complete and stands on its own (a spec doc, a standalone module, a self-contained fix), commit it without waiting to be asked. If the file is one piece of a larger change still in progress, hold it and commit it together with the rest once that unit of work is ready. The judgement is "is this a coherent, reviewable unit yet?" — if yes, commit; if it only makes sense alongside not-yet-written changes, wait for them. Still never commit parallel-agent WIP or unrelated dirty files (stage by name).
- **NEVER drop a git stash.** When `git stash pop` fails due to conflicts, resolve the conflicts — don't drop. A dropped stash is irrecoverable. If conflicts are in unrelated files, use `git checkout --theirs <file>` for those files then `git stash pop` again, or apply as a patch with `git stash show -p | git apply`.
- **Assume parallel agents are always active.** Other agents may be editing files at the same time — especially shared files like translation JSONs, CLAUDE.md, or CSS. Before stashing, resetting, or discarding changes, verify which changes are yours. If `git diff` or `git status` shows modifications you didn't make, **do not touch those files** — they belong to another agent. When in doubt, ask the user rather than taking destructive action.
- **Don't recommend destructive git ops to the user.** Never suggest `git reset --hard`, `git clean -fd`, `git checkout -- .`, or `git branch -D` — not even when the working tree looks "messy" or local has diverged from origin. Parallel sessions/agents routinely leave uncommitted WIP that looks unattributed but is real work; suggesting `--hard` makes the user destroy it. If cleanup is genuinely needed, suggest `git stash -u` first so the user can `stash pop` afterwards. If the goal is just "get to a clean origin/master state," create a fresh branch off `origin/master` instead — local master can stay divergent.

## Code Style

- **Respect the existing code style** in any file you edit. Match the file's existing patterns for quotes (single vs double), semicolons, indentation, and naming conventions. Don't reformat or restyle code you didn't change — it creates noisy diffs and obscures the real changes.
- **Don't `cd` into directories to run commands** — use full paths directly. Avoid `cd some/dir && command`; prefer `command some/dir/file` or pass the path as an argument.

## Secrets & Environment Safety

- NEVER read, display, or commit: `.env`, `.env.local`, `.env.production`, `.env.staging`, or any file containing secrets (API keys, credentials, certificates).
- **Exception**: `.env.example` files are safe to read and commit — they contain placeholder values, not real secrets.
- NEVER commit files matching: `*.pem`, `*.key`, `*.crt`, `secrets/`, `credentials/`.
- When referencing environment variables, describe what they do — never output their values.
- **Extracting secrets from `.env*`**: never use shell text tools (`grep`/`sed`/`awk`) — use `python3 <<'EOF' ... EOF` (quoted delimiter, NOT `-c`), pass the value to subprocess via `env={**os.environ, "X": v}` (never argv), and regex-redact `postgres(?:ql)?://\S+` from captured stderr before printing. Target tools can echo connection strings in error messages, so `capture_output=True` + redaction is mandatory.

## File Handling

- When the user provides a file or image path (especially relative paths like `~/Desktop/screenshot.png` or `Documents/file.txt`), always use the Read tool to access the file. Don't assume or guess the content — explicitly read it first.

## Dev Server

- Before starting a dev server, always check if one is already running on the expected port. Look up the port in `package.json` scripts (or other config like `vite.config.ts`, `wrangler.toml`), then run `lsof -ti :<port>` to check. If the port is already in use, skip starting the server and use the existing one.

## Session Time Tracking

Two complementary timing systems run in parallel:

### claude-timed (PTY wrapper)
`claude-timed` wraps Claude in a pseudo-terminal and measures typing/agent/idle time at millisecond precision. Data lives in `~/.claude/timings/*.jsonl` (one file per session). On session exit, it auto-calls `session_wrapup.sh` to log a mechanical summary to `~/.claude/time-log.jsonl`. View stats with `claude-timed --stats [today|week|month|all]`.

Forked from [martinambrus/claude_timings_wrapper](https://github.com/martinambrus/claude_timings_wrapper); fork lives at `~/Documents/GitHub/claude_timings_wrapper` (npm-linked globally). Phone-home (update checker) has been removed. The `cld` shell function wraps `claude-timed` with a fallback to plain `claude` if the wrapper is unavailable.

### Session hooks (heartbeat + wrapup)
- **Parallel agent support**: Each agent gets its own session file at `~/.claude/sessions/{session_id}.json`. The heartbeat reads `session_id` from stdin to update the correct file. Wrapup detects overlapping sessions and logs `parallel_with` in the time entry.
- **`/wrapup` for mid-session topic changes** — run `/wrapup` when changing subjects to log a time segment with an AI-generated summary. The `/wrapup` skill runs exact pre-approved bash commands (no improvisation). Follow its steps precisely.
- **Don't ask for permission** to run `/wrapup` — just do it as part of the natural workflow. Keep the summary concise and specific (e.g., "Added session heartbeat hook and crash recovery to time tracking system").
- If the user explicitly says to skip wrapup or not to run it, respect that.
- **Weekly report**: Run `bash ~/.claude/hooks/session_report.sh [days]` for a summary with agent-hours, wall time, parallelism ratio, and active sessions.
- **Symlink caution**: Hook scripts live in `meirpro-dotfiles/claude/hooks/` as real files, symlinked from `~/.claude/hooks/`. Never use `ln -sf` when the target is already a symlink — it follows the chain and overwrites the source. Always `rm` first, then `ln -s`.
- **External hook scripts** (e.g., `claude_timings_wrapper/hooks/`) are referenced by **full absolute path** in `settings.json`, not copied or symlinked into `~/.claude/hooks/`. This avoids conflicts with the meirpro-dotfiles symlink structure.
- **Queue drains run on a launchd timer, not SessionStart.** `flush_wrapup_queue.sh` is driven by `pro.meir.cc.flush-wrapup-queue` (30-min interval + RunAtLoad). See `claude/launchd/README.md` for install/verify/uninstall.
- **macOS TCC daemon stuck in stale state** — symptoms: tools fail with `Working directory "..." no longer exists` even though the dir is fine in the actual shell, *or* `Operation not permitted` reading a perfectly valid file (e.g. `python3 can't open file '~/.claude/hooks/play_audio.py'`). The hook-script symptom is the loud one, but the working-directory-disappearance is the more obvious signal — every tool call returns the same EPERM. The script, paths, chmod, and symlinks are all fine; TCC is just denying syscalls. Fix: kill **all** `tccd` processes (there are typically two — one system, one per-user — both may be stuck):

  ```bash
  ps -A | grep -i '[t]ccd'   # see what's running (1 or 2 PIDs expected)
  sudo killall tccd          # kills every tccd, system auto-respawns them
  ```

  Don't chmod or re-symlink — that's not the problem. After the kill, retry the next tool call; it'll succeed once the new tccd reads permissions cleanly.

## After opening a PR

Use `ghmp <pr-num>` (defined in `meirpro-dotfiles/shell/functions.sh`) to squash-merge a PR and ff-pull the target branch in one shot. Three forms:

```bash
ghmp 80                                 # current branch
ghmp 80 staging/partition-done          # named target branch
ghmp --wait 80 staging/partition-done   # also wait for PR-level CI
```

**Default behavior is merge-immediately-if-mergeable**, not wait-for-CI. The user explicitly preferred this: the post-merge push to the target branch runs CI anyway (~3 min saved per PR vs. running CI twice). If post-merge CI on the target fails, we revert there.

The function refuses to merge when GitHub reports the PR isn't cleanly mergeable: `CONFLICTING`, `UNKNOWN` (after retries), `MERGED`/`CLOSED`. It retries through transient `gh` 502/503 hiccups. `--wait` adds the old PR-CI-must-succeed safety net for risky branches.

Run `type ghmp` to confirm the function is loaded; if not, source `~/.bashrc`/`~/.zshrc` or open a fresh shell.

## Available macOS Tools

- **CleanShot X** — screenshot and screen recording app with a built-in editor for annotations, censoring, and cropping. Open images for editing with `open -a "CleanShot X" <path>`. Useful for censoring sensitive data (names, emails) in screenshots before committing. User saves the edited file via CleanShot's "Save As" dialog.
- **Clop.app** — image/video/PDF file size optimizer. Open files with `open -a Clop <path>`. Not the preferred automated approach (prefer `cwebp` or scripts for WebP conversion), but a valid manual tool the user has available for quick optimization.

## Database Safety

- Default to dry-run mode for any destructive database operation. Require explicit user confirmation before modifying or deleting data.
- Test queries with SELECT first to verify scope before running UPDATE/DELETE.
- Use idempotent migrations (IF NOT EXISTS / IF EXISTS patterns) so migrations are safe to run multiple times.

# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
