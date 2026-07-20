# Attribution

`get-to-the-point` is a derivative of the **`i-have-adhd`** skill by Ayoub Ghriss,
used under the MIT License.

- Upstream: https://github.com/ayghri/i-have-adhd
- Upstream skill: `skills/i-have-adhd/SKILL.md`
- Forked from `main` on 2026-07-20

## What changed in this fork

The ten output rules, the "when to break the rules" overrides, and the pre-send
check are carried over essentially verbatim — they are the substance of the skill
and they work regardless of why you want them.

What was rewritten:

- **Name** — `i-have-adhd` → `get-to-the-point`. The user does not have ADHD and
  wanted the output shape without the self-diagnosis framing.
- **Framing section** — upstream's "What ADHD changes about reading" became
  "What this optimizes for". The five underlying facts are unchanged; they are
  simply no longer attributed to a condition. E.g. "Working memory is small"
  became "Anything not on screen is forgotten"; "Dopamine is scarce" became
  "Visible progress matters".
- **Description frontmatter** — reworded to lead with the behavior
  ("Skip preamble and recap") instead of the audience. The aggressive
  "trigger on ANY user message" clause is deliberately preserved: this skill is
  an output style, not a task skill, so it must match broadly to fire at all.

Not carried over: upstream's plugin manifests (`.claude-plugin/`,
`.codex-plugin/`, `.agents/`), the Codex `agents/openai.yaml`, logo, and README.
This fork is installed as a plain global skill symlinked from dotfiles per
`claude/skills/CLAUDE.md`, not distributed as a plugin.

## Upstream license

```
MIT License

Copyright (c) 2026 Ayoub Ghriss

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
