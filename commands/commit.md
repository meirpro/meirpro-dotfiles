---
description: "Creates well-formatted commits with conventional commit messages and emoji for current session changes"
allowed-tools:
  [
    "Bash(git add:*)",
    "Bash(git status:*)",
    "Bash(git commit:*)",
    "Bash(git diff:*)",
    "Bash(git log:*)",
  ]
---

# Claude Command: Commit

Creates well-formatted commits with conventional commit messages and emoji for files changed in the current Claude Code session.

## Usage

```
/commit
/commit --no-verify
```

## Process

1. Analyze git status for session changes (modified and untracked files)
2. **IGNORE** any pre-staged files (they're from another session - can't trust them)
3. Review diff to identify logical changes
4. Suggest splitting if multiple unrelated changes detected
5. Stage files and create commit with emoji conventional format in one command: `git add <files> && git commit -m "message"`

## Important: Session-Focused Safety

**You are committing only changes made in THIS Claude Code session.**

- **Include**: Modified files (M) and new untracked files (??)
- **IGNORE**: Pre-staged files (A) - these are from previous sessions
- **Warn**: If attempting to commit unrelated changes
- **Goal**: Atomic, focused commits for the current work

## Commit Format

`<emoji> <type>: <description>`

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring without changing behavior
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `chore`: Build process, tooling, dependencies

**Rules:**

- Use imperative mood ("add" not "added")
- Keep first line under 72 characters
- Make atomic commits (single logical purpose)
- Split unrelated changes into separate commits

## Emoji Map

✨ feat | 🐛 fix | 📝 docs | 💄 style | ♻️ refactor | ⚡ perf | ✅ test | 🔧 chore | 🚀 ci | 🚨 warnings | 🔒️ security | 🚚 move | 🏗️ architecture | ➕ add-dep | ➖ remove-dep | 🌱 seed | 🧑‍💻 dx | 🏷️ types | 👔 business | 🚸 ux | 🩹 minor-fix | 🥅 errors | 🔥 remove | 🎨 structure | 🚑️ hotfix | 🎉 init | 🔖 release | 🚧 wip | 💚 ci-fix | 📌 pin-deps | 👷 ci-build | 📈 analytics | ✏️ typos | ⏪️ revert | 📄 license | 💥 breaking | 🍱 assets | ♿️ accessibility | 💡 comments | 🗃️ db | 🔊 logs | 🔇 remove-logs | 🙈 gitignore | 📸 snapshots | ⚗️ experiment | 🚩 flags | 💫 animations | ⚰️ dead-code | 🦺 validation | ✈️ offline

## Split Criteria

Consider splitting commits when you see:
- Different concerns (UI + API changes)
- Mixed types (feat + fix in same commit)
- Different file patterns (components + utils + config)
- Large changes that can be broken down logically

## Command Pattern

Always stage and commit in one command to avoid leaving files staged:

```bash
git add file1.ts file2.ts && git commit -m "$(cat <<'EOF'
✨ feat: add user authentication system
EOF
)"
```

## Options

`--no-verify`: Skip pre-commit hooks if configured

## Important: Commit Message Guidelines

**NEVER include these lines in commit messages:**
```
🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

Keep commit messages clean and focused on the actual changes without any generated attribution lines.

## Example Workflow

1. Check status: `git status --porcelain`
2. Identify session files: Modified (M) and Untracked (??) only
3. Review diffs: `git diff` for modified, show new file contents
4. Analyze for split: Are these changes related?
5. Create commit: `git add <files> && git commit -m "<emoji> <type>: <description>"`
