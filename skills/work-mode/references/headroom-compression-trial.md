# Headroom compression proxy — trial results (Rena VPS, 2026-09-03)

headroom v0.26.0 (uv tool on Rena, ~/.local/bin/headroom). A/B tested with a
186KB/200-item crawl-style JSON payload (needle questions) direct vs proxied,
upstream openrouter deepseek-chat (Rena's z.ai key was quota-dead at the time;
compression math is model-independent).

## Numbers
- Tokens: 32,878 → ~8,117 prompt (66% by proxy stats, 74% wall) per request.
- Latency: 3.9s direct → 7-37s proxied (first-hit slow, warm ~7s).
- Shallow answers (counts, status tallies, URLs): 100% preserved — SmartCrusher
  keeps field names + small values + error statuses.
- Deep answers (needle inside large text fields): WRONG in all 5 proxied runs —
  all 200 markdown bodies replaced with `<<ccr:hash>>` markers, INCLUDING error
  items (docs' "errors never dropped" means the error STATUS, not its text).

## Root cause
Recovery needs a `headroom_retrieve` tool call. The proxy does NOT inject that
tool into OpenAI-format /v1/chat/completions requests, and single-shot calls
can't tool-loop. `headroom mcp serve` initializes fine (serverInfo headroom 1.28)
but tools/list hung in a stdio probe — wiring it into Hermes mcp_servers is the
missing link before any deployment.

## Working invocation notes
- `HEADROOM_COMPRESS_USER_MESSAGES=1` env REQUIRED or user-role JSON is passed
  through untouched (docs confirm: default false, "coding profile turns this on").
- `--openai-api-url <url>` sets the upstream (auth passthrough via client's
  Bearer). `--disable-kompress` keeps it structural-only (no ML model download —
  Rena's disk/RAM are tight). `--no-telemetry` for beacon off.
- `--log-messages --log-file` gives request_messages vs compressed_messages in
  JSONL — how the needle-loss was proven.
- Killing the proxy from ssh: DON'T `pkill -f "headroom proxy"` — the pattern
  matches the ssh session's own command string and kills your shell (exit 255,
  connection drops). Read the pid from `curl 127.0.0.1:8787/health` →
  config.pid, then `kill $PID`.

## Parked setup (Rafx said "do this later" 2026-09-03)
1. systemd unit headroom-proxy.service on Rena: headroom proxy --port 8787
   --openai-api-url https://api.z.ai/api/paas/v4 --disable-kompress --no-telemetry,
   env HEADROOM_COMPRESS_USER_MESSAGES=1 (unit file drafted at /tmp on tortuga,
   re-create it).
2. Register `headroom mcp serve` in Rena's mcp_servers (firecrawl entry shows
   the config shape) → headroom_retrieve becomes callable.
3. Point her zai base_url at http://127.0.0.1:8787 (9router-style passthrough
   of her key) + gateway restart.
Verdict stands: real savings on exactly her traffic shape, but NOT deploy-safe
until retrieval is wired; structure-safe queries only until then.

## UPDATE 2026-09-04 — DEPLOYED ON ZERGLING (9router front)

headroom 0.37.0 via `uv tool install headroom-ai[proxy] --with jsonschema`
(plain install lacks fastapi → "Proxy dependencies not installed" crash).
`/etc/systemd/system/headroom-proxy.service`: `headroom proxy --port 8787
--openai-api-url http://127.0.0.1:20128/v1 --disable-kompress --no-telemetry`,
env HEADROOM_COMPRESS_USER_MESSAGES=1, enabled. Exposed tailnet-only:
`tailscale serve --bg --https=8443 http://127.0.0.1:8787`.

A/B (121KB/300-item needle JSON, glm/glm-5.3-flash via 9router):
direct 30,496 prompt tokens → proxied 13,994 (54% cut), needle ZEBRA-7741
correct on BOTH paths. KEY FINDING: streaming ("stream": true) is what makes
deep answers survive — no tool-injection needed. NON-STREAM through the proxy
FAILS: 9router appends stray `data: [DONE]` after the non-stream JSON body
(nonstandard); headroom chokes → 502 proxy_error. Always stream.
api-airforce free models share a 1-req/min global limit across direct+proxy —
use own-connection models (glm/glm-5.3-flash) for tests.
Usage pattern + guardrails → token-lean-flow skill, Layer 2.

## Health watchdog (2026-09-04, cron 505a8f0c8dbd "headroom-health")

Script ~/.hermes/scripts/headroom_health.py, cron daily 09:00 UTC, no_agent,
silent unless degraded (stdout only when OK; script itself Telegram-alerts on
failure). WATCHDOG LESSON: never gate "degraded" on LIFETIME cumulative stats
(/stats tokens_saved, total_compressions) — they only grow, so any nonzero
value trips a naive "anomalous" condition and fires a false alert on the first
run (Rafx got paged 2026-09-04, told me "fix or make this silent").
Deterministic A/B instead: fixed 200-item payload, fixed measured baseline
(direct 16,630 prompt tok on glm/glm-5.3-flash @ 9router), alert only if
proxied > 60% of baseline (<40% cut) or proxy dead. Baseline drifts with
model/payload changes — re-measure, don't hardcode a new number blind.

## Later-session A/B numbers (2026-09-04, smaller payload)

200-item payload: direct 16,630 → proxied 3,746-3,884 (77-78% cut), ~3s warm.
Smaller payloads compress BETTER (SmartCrusher floor is per-item).

## TIER BENCHMARK, headroom A/B + blind judge (2026-09-04, Rafx-driven)

Context: deciding glm-5.3 (orchestrator) vs glm-5.3-flash (worker) division.
Direct-9router A/B (NOT proxied, same 200-item mechanical audit task):

| | glm-5.3 | glm-5.3-flash |
|---|---|---|
| input | 18,927 | 19,013 (equal — flash reads as much) |
| output | 2,021 | 1,101 |
| reasoning | 1,286 | 357 |
| time | 82.6s | 43.4s (1.9× faster) |
| est cost | $0.0169 | $0.0014 (92% cheaper) |

Quality checked THREE ways (this is the reusable method):
1. Python-computed ground truth (20 files, line counts, grep targets) — both
   tiers matched exactly. Free, objective; prefer whenever output is checkable.
2. Blind judge: glm-5.3 graded anonymized A/B outputs vs ground truth →
   flash 9.8 vs 5.3's 9.6. Judge cost ~$0.01 (9.7K in / 2.1K out). Proof-grade
   comparisons only, not every task.
3. Orchestrator spot-verify = standing default.

Benchmark recipe: `hermes -z "$TASK" -m <model> --yolo --usage-file
/tmp/usage_X.json` → usage JSON has input/output/cache_read/reasoning/api_calls.
flash quirk: reasoning model — max_tokens < ~150 gives finish=length + EMPTY
content (looks like a failure but is just truncation of thinking tokens).
Flash = reasoning model means non-trivial replies always pay a thinking floor
(~46 tok even for "OK"). Verdict that locked the two-tier rule: flash is
equal-or-better on self-contained mechanical work.
