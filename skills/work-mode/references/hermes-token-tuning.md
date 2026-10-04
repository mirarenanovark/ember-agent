# Hermes token-tuning — audit + applied settings (2026-09-04)

Config knobs that govern per-request token spend on Hermes (from
docs/developer-guide/context-compression-and-caching + live config). Audit
before re-deriving; these were the values AFTER Rafx's approved changes.

## Applied (2026-09-04, Rafx "go")

- `compression.proactive_prune_tokens: 60000` — deterministic, NO-LLM pruning
  (dedup byte-identical tool results, summarize oversized non-tail ones,
  truncate fat tool_call args, retire old image payloads) once history passes
  60K tokens. Critical on big-window models: glm-5.3 has 1M context so the 50%
  full-compression trigger (500K) essentially NEVER fires on a messaging-day
  session — without this, old tool results re-ship verbatim every turn forever.
  Never touches the protected tail (protect_last_n=20) or unique content.
- `auxiliary.compression`: model glm-5.3-flash, provider glm, base_url
  https://api.z.ai/api/coding/paas/v4, api_key_env GLM_API_KEY — session
  summaries/compaction bill at flash rate.
- `delegation.model: glm-5.3-flash` — all delegate_task children on flash.

## Evaluated, deliberately NOT applied

- `micro_compact: true` — rolling per-turn compaction; breaks the prompt-cache
  prefix EVERY pass. Saves tokens but costs more in cache misses at
  Telegram-session scale. Opt-in for always-on heavy sessions only.
- `idle_compact_after_seconds` — neutral here; sessions resume rarely.
- Lowering `threshold` (0.5) — lean tail_mode already handles big sessions well
  (docs: 49K vs 162K retained on 500K sessions, higher recall with recovery).

## Key mechanics (verified in source + docs)

- Three gates: gateway session hygiene (85%, fixed) > agent compressor (50%,
  configurable) > proactive prune (token cap, deterministic).
- Gateway hygiene intentionally higher than agent compressor — setting both to
  50% caused premature compression every turn in long gateway sessions.
- Summary failures arm escalating cooldowns (60s→300s→900s); provider-proven
  context-overflow bypasses the cooldown for one bounded attempt.
- tail_mode `lean`: clamped tail 2.5% × window (10K floor/25K cap) + verbatim
  user messages + regex anchor index + session_search recovery pointer. Old
  tool results in the tail demote to one-line stubs.
- Config takes effect NEXT session/gateway restart — never mid-chat (prompt
  cache preservation is the point).

## z.ai subscription usage — queryable after all (updated 2026-09-04, later same day)

Earlier probe result (all /usage /quota variants 404, no rate-limit headers)
was correct but incomplete: the working endpoint is
`GET https://api.z.ai/api/monitor/usage/quota/limit` (Bearer key) → 5h window
used%, monthly cap, reset timestamps, plan tier. Discovered by reading 9router's
bundled source (`open-sse/providers/registry/glm.js` → transport.usage).
Full response shape + the source-grep pattern: references/zai-quota-endpoint.md.
9router's usageHistory table remains the path for per-request routed-traffic
breakdowns (the quota endpoint is percentages-only).
