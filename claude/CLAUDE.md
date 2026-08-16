# Development Rules

> Shared configuration from [meirpro-dotfiles](https://github.com/meirpro/meirpro-dotfiles).
> Hooks check TypeScript, lint, and format on every file save.
>
> Machine-specific facts (hosts, credential paths, installed tools, local
> plumbing) do **not** belong here — this repo is public. They live in the
> private `meirpro-machine` repo, which imports this file.

## Git Safety

> ⚠ The four staging rules and the branch-move ban are **enforced at the binary
> level** by the `safe-git` wrapper (`~/bin/git` → `meirpro-dotfiles/git/safe-git`).
> Violations return exit 64 with an explanation; real `git` is never reached.
> That's deliberate — rules in CLAUDE.md alone get forgotten mid-session.
>
> Enforced: no `git add -A` / `git add .` / `git commit -a`; `add` and `commit`
> must be one shell invocation (`git add f1 f2 && git commit -m "…"`); no
> HEAD-moving `checkout`/`switch`. Bypasses are scoped and logged to
> `~/.claude/git-bypass.log` — `GIT_UNSAFE_STAGE=1` for staging,
> `GIT_UNSAFE_BRANCH=1` for one branch move, and the branch bypass needs the
> user's explicit in-conversation permission for that specific move.

The wrapper catches the above. These have no safety net:

- **Pull before starting work**: `git pull origin $(git branch --show-current)`.
- **Never** put `Generated with Claude Code` or `Co-Authored-By: Claude` in a
  commit message.
- **Stage by name, always.** `-A` and `.` sweep in files edited by parallel
  agents and generated artifacts. Review `git status` / `git diff` first — if
  you see changes you didn't make, they're another agent's. Don't stage them,
  don't stash them, don't discard them. Ask.
- **A checkout's branch is a shared resource.** Sessions run in parallel in one
  working directory, so switching moves the branch for *everyone* (observed
  2026-06-24: a commit stranded on another session's branch + a migration-number
  collision; 2026-07-21: an agent minted four `ship/*` branches to imitate a
  missing `npm run ship` — a missing tool means ASK, not imitate). Work on the
  branch the checkout is already on. When another branch is needed, ask which:
  switch the shared checkout, or an isolated
  `git worktree add .claude/worktrees/<name> -b <branch>`. There is no default.
- **Never create worktrees under `/tmp`** (or `/private/tmp`, `$TMPDIR`) —
  macOS purges tmp on reboot and on a 3-day timer, silently destroying
  uncommitted work and orphaning the registration. Use the repo's
  `.claude/worktrees/<name>/`, and gitignore that dir *before* the first one.
  Same for any scratch checkout meant to outlive one command. Caveat: a nested
  worktree is edit isolation, **not** the test oracle — run the authoritative
  suite in the main checkout or CI.
- **Never drop a git stash.** If `git stash pop` conflicts, resolve it. A
  dropped stash is irrecoverable. For conflicts in unrelated files, use
  `git checkout --theirs <file>` then pop again, or
  `git stash show -p | git apply`.
- **Don't recommend destructive git ops.** Never suggest `git reset --hard`,
  `git clean -fd`, `git checkout -- .`, or `git branch -D` — not even when the
  tree looks messy. Parallel sessions leave real WIP that looks unattributed.
  Suggest `git stash -u` so it's recoverable, or branch off `origin/master`
  fresh if the goal is just a clean state.
- **Run tests before committing** if the project has a suite.
- **Keep commits small.** One logical change each. A commit touching 10+ files
  is a warning sign.
- **Commit completed work proactively** (this overrides "only commit when
  asked"). When a file is logically complete and stands on its own, commit it.
  If it's one piece of a larger in-progress change, hold it until that unit is
  ready. Never commit parallel-agent WIP or unrelated dirty files.

## Regression Ratchet

**When a bug class ships, fixing the code isn't the fix — making that class
impossible to reintroduce silently is.** Anything seen once should be caught
**mechanically** forever after, by deterministic code, never by anyone
remembering. One tooth per incident; not a big-bang setup. (`hayom` is the
worked reference: 18+ custom ESLint rules, codebase-walking guard tests, and a
meta-test guarding the lint config itself.)

Lifecycle for every non-trivial bug:

1. Fix the code.
2. Add a mechanical guard that *would have caught it* — a uniquely-named custom
   ESLint rule, a `no-restricted-syntax`/`no-restricted-imports` selector, or a
   test that walks the source tree when an AST selector can't express the
   pattern.
3. Document the incident in the guard's header: what it bans, why it's a bug
   class (with PR/commit SHA), and what it deliberately does *not* flag.
4. If the guard itself has a failure mode, guard the guard.
5. Wire it into the gate so it runs unattended (CI + the save-time hook).

**Prefer uniquely-named custom rules over `no-restricted-syntax`.** ESLint flat
config *replaces* rather than merges a rule's options when several blocks match
the same file — last block wins — so a late `no-restricted-syntax` block can
silently disable every earlier selector (observed: ~8 days inert). A custom
rule can neither clobber nor be clobbered. If you must use
`no-restricted-syntax`, duplicate selectors into the last-matching block and
pin it with a test that calls both `eslint.calculateConfigForFile()` **and**
`eslint.lintText()` — a clobbered selector still *appears* present while being
inert.

**Escape hatches are explicit, inline, and reasoned** — a greppable marker with
a justification (`// allow-whole-done: <reason>`), never a file-level disable.
**Pair a rule with its seam**: if it bans direct use of some names in favor of
a choke-point module, add a sync test asserting the list still matches that
module's real exports.

Don't retrofit a whole lint stack mid-task to add one guard — add the rule now,
note "formalize into ESLint/CI" as follow-up.

## Time Estimates — always give both

Whenever you quote a time estimate, give **both** numbers:

- **Human**: developer-hours for the real workflow — read, decide, type, wait
  on CI, switch contexts.
- **AI**: wall-clock minutes for a Claude Code session, from clear directive to
  committed and verified.

Format: `~2-4 h human / ~20 min AI`.

These are workload-based, not a fixed ratio. **Doesn't compress at all**:
real-device verification, external coordination (vendor email, third-party
OAuth), migration verification against real user data, anything gated on a
human looking at it, and long debugging that needs accumulated context about
this specific setup. For those write `AI: n/a — verification only`.

**Don't sandbag the AI number.** If it's honestly 15 minutes, say 15.

For structuring and costing a delegated verify-then-fix run, use the
`multi-agent-verification` skill.

## Code Quality

- Check `npx tsc --noEmit` and `npm run lint` after changes. Lint findings are
  suggestions — follow them when correct; they can be wrong.
- No placeholder or "coming soon" code — implement the full thing.
- Format with the project's formatter after editing.
- **Write tests alongside implementation, not after.** Tests written after the
  fact confirm what the code does rather than validating correctness.

## Code Style

- **Respect the existing style** in any file you edit — quotes, semicolons,
  indentation, naming. Don't restyle code you didn't change; it buries the real
  diff.
- **Prefer a path argument over `cd`** (`command some/dir/file`). When a tool
  genuinely needs the directory, keep the `cd` in the *same* invocation — many
  runners reset the working directory between commands, so a standalone `cd`
  silently doesn't apply.

## Secrets & Environment Safety

- **Never** read, display, or commit `.env`, `.env.local`, `.env.production`,
  `.env.staging`, or anything holding API keys, credentials, or certificates.
  `.env.example` is fine — it holds placeholders.
- **Never** commit `*.pem`, `*.key`, `*.crt`, `secrets/`, `credentials/`.
- Describe what an environment variable does; never output its value.
- **Extracting a secret from `.env*`**: never use shell text tools
  (`grep`/`sed`/`awk`). Use `python3 <<'EOF' … EOF` (quoted delimiter, not
  `-c`), pass the value to a subprocess via
  `env={**os.environ, "X": v}` (never argv), and regex-redact
  `postgres(?:ql)?://\S+` from captured stderr before printing — target tools
  echo connection strings in error messages, so `capture_output=True` plus
  redaction is mandatory.

## Database Safety

- Default to dry-run for any destructive operation; require explicit
  confirmation before modifying or deleting data.
- `SELECT` first to verify scope before `UPDATE`/`DELETE`.
- Idempotent migrations (`IF NOT EXISTS` / `IF EXISTS`) so they're safe to
  re-run.

## Dev Server

Before starting a dev server, check whether one is already running. Find the
port in `package.json` scripts (or `vite.config.ts`, `wrangler.toml`), then
`lsof -ti :<port>`. If it's in use, use the existing server.

## MCP Server Config

**Never pin a stdio MCP server to `npx …@latest`.** Claude Code spawns stdio
servers synchronously at session start and blocks the prompt until they're up.
The `@latest` dist-tag forces `npx` to hit the registry on *every* launch even
when cached, so a slow network hangs the whole session behind it. Pin an exact
version (e.g. `@playwright/mcp@0.0.76`) and bump deliberately.

## Global vs per-project: plugins, MCPs, skills

**Cheap-and-universal → global; expensive-or-stack-specific → per-project.**
The cost differs by category:

- **Plugins** load into every session and cost tokens each time → keep the
  global core lean, opt into the rest per-project.
- **MCP servers** spawn at every session start and *block the prompt* → global
  should be near-zero. There is **no** installed-globally-but-off mode for MCPs
  (unlike plugins): a global MCP always runs, so per-project config is the only
  way to avoid paying startup cost in unrelated sessions.
- **Skills** are invoked on demand; only their one-line descriptions sit in
  context → cheapest, but a pile of stack-specific ones still bloats every
  session.

Enable per-project with `claude plugin enable <plugin> -s project` or the
repo's `.claude/settings.json` → `enabledPlugins` (project scope overrides
global), then `/reload-plugins`. ⚠ `claude plugin list` and `/doctor` can
report stale errors from the *running* session until a reload — verify against
on-disk `enabledPlugins`, not the live list.

**"Install globally, default off, enable per-project"** is the intended pattern
for a stack plugin used in several repos: install at user scope, leave `false`
in the global `enabledPlugins`, set `true` in each relevant repo.

## After opening a PR

`ghmp <pr-num>` (defined in `meirpro-dotfiles/shell/functions.sh`) merges a PR
and ff-pulls the target branch in one shot:

```bash
ghmp 80                                 # current branch
ghmp 80 staging/partition-done          # named target
ghmp --squash 80                        # collapse the branch to one commit
ghmp --wait 80 staging/partition-done   # also wait for PR-level CI
```

Flags may be combined and given in any order.

**Merges with a MERGE COMMIT by default** (changed 2026-08-16; it squashed
before). Squashing is right for a scratch branch whose intermediate commits are
noise, but as the *default* it silently discarded per-commit reasoning on
branches whose commits were written to be read, and rewrote authorship to the
PR author — which is what blocks `sweetrobo/crm`'s deploy gate when you merge
someone else's PR. Reach for `--squash` deliberately, per branch.

Default is also merge-immediately-if-mergeable, not wait-for-CI — the
post-merge push runs CI anyway (~3 min saved per PR). If post-merge CI fails,
revert there. It refuses `CONFLICTING`, `UNKNOWN` (after retries), and
`MERGED`/`CLOSED`, and retries transient `gh` 502/503s.

### Merging a worktree PR into a fast-moving main

The trap, learned 2026-07-02: **a worktree's green verify only proves the main
it forked from, never the main it merges into.**

- **Re-check `origin/main` is green immediately before firing `ghmp`** — you
  may be stacking onto an already-red main, and commits landing during your
  conflict-resolution window were never in your local verify. Gate with
  `gh run list --branch main --workflow "CI + Deploy" --limit 3 --json headSha,conclusion`.
  If the latest completed run failed, stop and find out whose commit broke it.
- **`ghmp` from inside a worktree** prints `could not checkout main` and skips
  the local ff-pull. The merge still succeeded server-side. Confirm by content
  on `origin/main`, not by local branch state:
  `git fetch origin main && git show origin/main:<file> | grep <sentinel>`.
- **Suite composition changes execution order.** Merging big branches can
  expose a latent order-dependency in an *untouched* test. CI on the merged
  main is the only oracle for the combined suite.
- **Trust only a foreground exit code.** `npm run verify | tail` and
  backgrounded runs both masked a real `exit 1`. Use
  `npm run verify > /tmp/verify.log 2>&1; echo "EXIT:$?"` and gate on the code.
- **Set the expectation up front**: each resolve-and-verify pass is ~25–35 min,
  and they must be sequential — each merge moves main.
