# ~/.claude/skills/ — where global skills actually live

**User-authored global skills belong in the dotfiles repo, symlinked here —
never as loose directories in `~/.claude/skills/`.** A loose directory is
machine-local: not in git, doesn't survive a machine move, invisible to the
user's other machines. (This file itself is a symlink into the dotfiles repo;
so are `transcribe-audio` and `lottie-animations` — they're the reference
examples.)

## Creating a new global skill

1. Author it directly at
   `~/git/meirpro-dotfiles/claude/skills/<name>/`
   (or if a tool like `init_skill.py` already created it under
   `~/.claude/skills/<name>/`, **move** it: `mv ~/.claude/skills/<name>
   ~/git/meirpro-dotfiles/claude/skills/<name>`).
2. Symlink it back with an **absolute** target:

   ```bash
   ln -s ~/git/meirpro-dotfiles/claude/skills/<name> \
         /Users/lightwing/.claude/skills/<name>
   ```

3. Verify the skill still resolves through the symlink (list its files, run
   the skill-creator validator on the symlinked path).
4. `git add claude/skills/<name>` in meirpro-dotfiles, commit, **push**.

## Cautions

- **Never `ln -sf` when the link path already exists as a symlink** — it can
  follow the chain and clobber the real source (per the global CLAUDE.md
  symlink caution). `rm` the old link first, then `ln -s`.
- Machine-specific paths inside a skill (venv interpreters, model caches)
  are fine but must be labeled as such in the SKILL.md, with a note on how
  to recreate the environment elsewhere.
- The many other directories here (downloaded third-party skill packs,
  `some-skills/`, the relative `../../.agents/skills/*` links) predate this
  convention — leave them alone; the rule applies to skills authored or
  maintained for this user going forward.
