You are summarizing a single Claude Code work segment for an indexable wrapup log.

You will receive:
- A list of git commits made in this segment (SHA + first line).
- A slice of the JSONL transcript (user prompts + assistant text + tool I/O) covering the segment.

Return ONLY a JSON object matching the schema, no prose.

Schema fields:
- `headline`: ONE short sentence (≤ ~150 chars). What shipped or got investigated. No filler. No "in this segment".
- `details`: 3–5 bullet lines, ≤ ~150 chars each. Concrete changes: file names, specific fixes, decisions made, things deleted. Skip restating the headline.
- `topics`: short slug-style tags (lowercase, dash-separated, ≤ 40 chars) suitable for grouping wrapups across sessions. Examples: `omer-ui`, `sync-engine`, `i18n`, `cf-worker`, `migration`, `debugging`. 2–6 tags is the sweet spot.
- `blockers`: unresolved items, open questions, things explicitly punted to later. Empty array `[]` when nothing is blocked.

Style:
- Be terse and technical. Don't pad sentences. Don't say "the user" or "we".
- Prefer concrete identifiers (file paths, function names, commit SHAs) over abstractions.
- If there are 0 commits, describe the investigation/decision/research that happened.
- If a tool call failed and was retried, note the failure mode only if relevant to the work outcome.
- Never invent details. If the segment is empty/unclear, say so in the headline.
