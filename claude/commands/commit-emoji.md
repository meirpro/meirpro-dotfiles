---
description: "Creates well-formatted commits with conventional commit messages and emoji"
allowed-tools:
  [
    "Bash(git add:*)",
    "Bash(git status:*)",
    "Bash(git commit:*)",
    "Bash(git diff:*)",
    "Bash(git log:*)",
  ]
---

# Claude Command: Commit (Emoji Test Version)

Creates well-formatted commits with conventional commit messages and emoji.

## Usage

```
/commit-emoji
/commit-emoji --no-verify
```

## Process

1. Check staged files, commit only staged files if any exist
2. Analyze diff for multiple logical changes
3. Suggest splitting if needed
4. Create commit with emoji conventional format
5. Use single command pattern: `git add <files> && git commit -m "message"`

## Commit Format

`<emoji> <type>: <description>`

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `perf`: Performance
- `test`: Tests
- `chore`: Build/tools

**Rules:**

- Imperative mood ("add" not "added")
- First line <72 chars
- Atomic commits (single purpose)
- Split unrelated changes

## Emoji Map

✨ feat | 🐛 fix | 📝 docs | 💄 style | ♻️ refactor | ⚡ perf | ✅ test | 🔧 chore | 🚀 ci | 🚨 warnings | 🔒️ security | 🚚 move | 🏗️ architecture | ➕ add-dep | ➖ remove-dep | 🌱 seed | 🧑‍💻 dx | 🏷️ types | 👔 business | 🚸 ux | 🩹 minor-fix | 🥅 errors | 🔥 remove | 🎨 structure | 🚑️ hotfix | 🎉 init | 🔖 release | 🚧 wip | 💚 ci-fix | 📌 pin-deps | 👷 ci-build | 📈 analytics | ✏️ typos | ⏪️ revert | 📄 license | 💥 breaking | 🍱 assets | ♿️ accessibility | 💡 comments | 🗃️ db | 🔊 logs | 🔇 remove-logs | 🙈 gitignore | 📸 snapshots | ⚗️ experiment | 🚩 flags | 💫 animations | ⚰️ dead-code | 🦺 validation | ✈️ offline

## Split Criteria

Different concerns | Mixed types | File patterns | Large changes

## Command Pattern

Always stage and commit in one command to avoid leaving files staged:

```bash
git add file1.ts file2.ts && git commit -m "$(cat <<'EOF'
✨ feat: add new feature
EOF
)"
```

## Options

`--no-verify`: Skip pre-commit hooks (if configured in your project)

## Important: Commit Message Guidelines

**NEVER include these lines in commit messages:**
```
🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

Keep commit messages clean and focused on the actual changes without any generated attribution lines.

## Notes

- If files are staged, commit only those
- If no files are staged, analyze all changes
- Always use `git add <files> && git commit` pattern to avoid leaving files staged
- Suggest splitting unrelated changes
