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

## Code Style

- **Respect the existing code style** in any file you edit. Match the file's existing patterns for quotes (single vs double), semicolons, indentation, and naming conventions. Don't reformat or restyle code you didn't change — it creates noisy diffs and obscures the real changes.
- **Don't `cd` into directories to run commands** — use full paths directly. Avoid `cd some/dir && command`; prefer `command some/dir/file` or pass the path as an argument.

## Secrets & Environment Safety

- NEVER read, display, or commit: `.env`, `.env.local`, `.env.production`, `.env.staging`, or any file containing secrets (API keys, credentials, certificates).
- **Exception**: `.env.example` files are safe to read and commit — they contain placeholder values, not real secrets.
- NEVER commit files matching: `*.pem`, `*.key`, `*.crt`, `secrets/`, `credentials/`.
- When referencing environment variables, describe what they do — never output their values.

## File Handling

- When the user provides a file or image path (especially relative paths like `~/Desktop/screenshot.png` or `Documents/file.txt`), always use the Read tool to access the file. Don't assume or guess the content — explicitly read it first.

## Dev Server

- Before starting a dev server, always check if one is already running on the expected port. Look up the port in `package.json` scripts (or other config like `vite.config.ts`, `wrangler.toml`), then run `lsof -ti :<port>` to check. If the port is already in use, skip starting the server and use the existing one.

## Session Time Tracking

A session timer runs automatically via hooks. Run `/wrapup` to log a time entry with a summary of work done.

- **Parallel agent support**: Each agent gets its own session file at `~/.claude/sessions/{session_id}.json`. The heartbeat reads `session_id` from stdin to update the correct file. Wrapup detects overlapping sessions and logs `parallel_with` in the time entry.
- **Run `/wrapup` when changing subjects** — if the user shifts to a different feature, bug, or topic, run `/wrapup` to close out the current work segment before moving on. This keeps time entries granular and useful for weekly reports.
- **Run `/wrapup` after completing a task** — when implementation is done and tests pass (or after a successful `/verify`), run `/wrapup` to log the completed work.
- **Multiple wrapups per session are fine** — each one logs a separate segment. The timer resets after each wrapup, so segments don't overlap.
- **Don't ask for permission** to run `/wrapup` — just do it as part of the natural workflow. Keep the summary concise and specific (e.g., "Added session heartbeat hook and crash recovery to time tracking system").
- If the user explicitly says to skip wrapup or not to run it, respect that.
- **Weekly report**: Run `bash ~/.claude/hooks/session_report.sh [days]` for a summary with agent-hours, wall time, parallelism ratio, and active sessions.
- **Symlink caution**: Hook scripts live in `meirpro-dotfiles/claude/hooks/` as real files, symlinked from `~/.claude/hooks/`. Never use `ln -sf` when the target is already a symlink — it follows the chain and overwrites the source. Always `rm` first, then `ln -s`.

## Database Safety

- Default to dry-run mode for any destructive database operation. Require explicit user confirmation before modifying or deleting data.
- Test queries with SELECT first to verify scope before running UPDATE/DELETE.
- Use idempotent migrations (IF NOT EXISTS / IF EXISTS patterns) so migrations are safe to run multiple times.
