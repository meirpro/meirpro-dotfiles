# Team Development Rules

> Shared configuration from [meirpro-dotfiles](https://github.com/meirpro/meirpro-dotfiles).
> Hooks automatically check TypeScript, lint, and format on every file save.

## Code Quality

- Check TypeScript (`npx tsc --noEmit`) and linting (`npm run lint`) after making changes to ensure nothing is broken. Linting issues are suggestions — follow them when correct, but they can occasionally be wrong.
- Don't use placeholder or "coming soon" code — always implement full functionality.
- Format code with the project's formatter (Prettier, etc.) after editing files.
- **Write tests alongside implementation, not after** — write or update tests as you build, not as a separate follow-up step. Tests written after the fact tend to just confirm what the code already does rather than validating correctness.
## Git Safety

- **Always pull the latest changes before starting work**: `git pull origin $(git branch --show-current)`. This avoids merge conflicts and wasted effort from working on stale code.
- **NEVER include these lines in commit messages:**
  ```
  Generated with Claude Code

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```
- **NEVER use `git add -A` or `git add .`** — always stage specific files by name to avoid accidentally committing secrets or unrelated changes.
- **NEVER stage files and commit in separate commands** (e.g. `git add file` then `git commit`). Always combine into a single command: `git add file1 file2 && git commit -m "message"`. This prevents other parallel agents from accidentally committing each other's work.
- Review `git status` and `git diff` before committing. If you see changed files that you did NOT modify, another agent may be working in parallel — do NOT stage or commit those files.
- **Run tests before committing** if the project has a test suite. Check `package.json` for `test`, `test:unit`, or similar scripts. A quick `npm test` catches regressions before they're pushed.
- **Keep commits small and logically grouped.** Each commit should represent ONE logical change (one feature, one bug fix, one refactor). If you've made changes across many files, split them into multiple commits by concern. A commit touching 10+ files is a warning sign — 94 files in one commit is unacceptable. Large commits are nearly impossible to review, debug, or revert. When in doubt, commit more often, not less.
- **NEVER drop a git stash.** When `git stash pop` fails due to conflicts, resolve the conflicts — don't drop. A dropped stash is irrecoverable. If conflicts are in unrelated files, use `git checkout --theirs <file>` for those files then `git stash pop` again, or apply as a patch with `git stash show -p | git apply`.
- **Assume parallel agents are always active.** Other agents may be editing files at the same time — especially shared files like translation JSONs, CLAUDE.md, or CSS. Before stashing, resetting, or discarding changes, verify which changes are yours. If `git diff` or `git status` shows modifications you didn't make, **do not touch those files** — they belong to another agent. When in doubt, ask the user rather than taking destructive action.

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

## Available macOS Tools

- **CleanShot X** — screenshot and screen recording app with a built-in editor for annotations, censoring, and cropping. Open images for editing with `open -a "CleanShot X" <path>`. Useful for censoring sensitive data (names, emails) in screenshots before committing. User saves the edited file via CleanShot's "Save As" dialog.
- **Clop.app** — image/video/PDF file size optimizer. Open files with `open -a Clop <path>`. Not the preferred automated approach (prefer `cwebp` or scripts for WebP conversion), but a valid manual tool the user has available for quick optimization.

## Database Safety

- Default to dry-run mode for any destructive database operation. Require explicit user confirmation before modifying or deleting data.
- Test queries with SELECT first to verify scope before running UPDATE/DELETE.
- Use idempotent migrations (IF NOT EXISTS / IF EXISTS patterns) so migrations are safe to run multiple times.
