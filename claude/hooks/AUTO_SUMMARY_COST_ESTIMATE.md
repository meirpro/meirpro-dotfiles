# Auto-summary cost estimate — 2026-04-21

Hypothetical estimates for the planned SessionEnd auto-wrapup feature.
Summarization via `claude -p --model haiku-4-5 --output-format json` on
JSONL content since last manual wrapup. To be audited against real data
once the feature has been running for a few days.

## Input assumptions

- Pre-filtered JSONL fed to `claude -p` capped at ~20KB.
- 20KB ≈ **5,000–6,000 input tokens** (JSONL is ~3.5 chars/token, dense).
- Output: 1–2 sentence summary ≈ **50–100 output tokens**.
- Default model: **Haiku 4.5** (sufficient for single-sentence narration).
- Assumed cadence: **~10 session-exits per day** (rough — user runs heavy
  parallel-agent workflows, actual may be higher).

## Per-call cost

At Haiku 4.5 pricing ($1/M in, $5/M out) with 5,000 in + 100 out:

| Component | Math | Cost |
|---|---|---|
| Input  | 5,000 × $1 / 1M  | $0.0050 |
| Output |   100 × $5 / 1M  | $0.0005 |
| **Total per call** | | **~$0.0055** |

## Projected totals (Haiku 4.5)

| Cadence | Per day | Per month |
|---|---|---|
| 10 exits/day | $0.055 | ~$1.65 |
| 20 exits/day | $0.11  | ~$3.30 |
| 50 exits/day | $0.28  | ~$8.25 |

Sonnet 4.6 equivalent (for comparison): ~3× higher — ~$5/month at 10
exits, ~$25/month at 50.

Note: on a Max plan these count against plan quota, not billed separately.
Dollar figures are for **plan-consumption visibility**, not invoicing.

## What to save per call

Each auto-summary segment line in `~/.claude/wrapup-segments.jsonl`
carries an `auto_summary_meta` block:

```json
{
  "model": "claude-haiku-4-5",
  "input_tokens": 5123,
  "output_tokens": 87,
  "cache_read_input_tokens": 0,
  "cache_creation_input_tokens": 0,
  "cost_usd": 0.0058,
  "duration_ms": 1240,
  "duration_api_ms": 890,
  "headless_session_id": "abc-def-...",
  "is_error": false
}
```

## Audit procedure

When revisiting (current date > 2026-04-21 + a few days) AND auto-summary
has shipped:

1. **Actual total spent:**
   ```bash
   jq -r '.auto_summary_meta.cost_usd // empty' ~/.claude/wrapup-segments.jsonl \
     | paste -sd+ - | bc
   ```
2. **Count auto-summary calls:**
   ```bash
   jq -c 'select(.trigger=="auto-on-exit")' ~/.claude/wrapup-segments.jsonl | wc -l
   ```
3. **Average input tokens per call:**
   ```bash
   jq -r '.auto_summary_meta.input_tokens // empty' ~/.claude/wrapup-segments.jsonl \
     | awk '{s+=$1; n++} END{if(n) print s/n}'
   ```
4. **Average duration:**
   ```bash
   jq -r '.auto_summary_meta.duration_ms // empty' ~/.claude/wrapup-segments.jsonl \
     | awk '{s+=$1; n++} END{if(n) print s/n "ms"}'
   ```
5. Compare to baselines in this doc:
   - Actual avg input tokens vs **5,000**
   - Actual per-call cost vs **$0.0055**
   - Actual exits/day vs **10/day**
6. Write findings in the "Audit results" section below.

## Unknowns to resolve during audit

- Does `claude -p` on the Max plan return a non-null `total_cost_usd`?
  If always null, derive cost from tokens × published rates at save time.
- Does prompt caching kick in (`cache_read_input_tokens > 0`)? Likely
  no for one-shot `-p` with unique prompts, but worth confirming.
- JSONL filter output size distribution: if consistently under 5K tokens,
  costs drop; if it leaks to 30KB+ often, costs 1.5×+. May need a tighter
  cap or smarter filter.
- Does `duration_ms` match or exceed `duration_api_ms`? Large delta =
  hook-side overhead worth optimizing.

---

## Audit results

*(to be filled in on next check)*
