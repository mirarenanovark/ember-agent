# 9router as Hermes provider — lane map (verified 2026-09-03/04)

Endpoint: `https://zergling.tail28e85.ts.net/v1` (tailnet; tortuga resolves via
/etc/hosts `100.83.110.118 zergling.tail28e85.ts.net`). Key: `NINEROUTER_API_KEY`
in ~/.hermes/.env, copy at ~/.hermes/mira-files/private/9router_key.txt
(same key as 9router's dashboard "Default Key").

## The syntax trap

9router model IDs contain slashes (`glm/glm-5.3`, `bzl/auto:free`), colliding
with Hermes' `provider/model` parsing. `-m 9router/glm/glm-5.3` and
`-m glm/glm-5.3@9router` all send garbage upstream → "HTTP 400: modelCode:
does not exist". Verified working:
- `hermes -m "bzl/auto:free" --provider 9router` → "lane test ok"
- config dict: `model.default: {provider: 9router, model: glm/glm-5.3-flash}`
  (applied, answered, then restored scalar default)
- from Telegram: plain `/model glm-5.3` (z.ai direct, no slash) works; for
  9router lanes either ask Mira to set it or use the dict form.

## Verified lanes (all 200 + correct answers, Sep 3)
- `glm/*` (5.3, 5.3-flash, 5.2, 5.1, 5, 4.7, 4.6v) — Rafx's own z.ai
  subscription key, connection "kthive" in 9router DB. Same quota as direct
  z.ai (subscription windows apply to the key regardless of path); the win is
  9router's usage tracking/logging.
- `bzl/auto:free` — TRUE free lane, auto-routed (picked qwen/qwen3.7-flash), 2.4s.
- `ds/deepseek-v4-flash` — works (~1.8s).

## Dead/stale lanes
- `ollama/*` — retired upstream (410 "glm-5 was retired 2026-07-15").
- `kimchi/*` — credits exhausted (402).
- Kiro / OpenCode Free — absent from /v1/models despite older memory notes.

## Cron model pins (lane rule, verified live)

Per-job model on Hermes crons: `hermes cron create/edit <id> --model <id>
--provider 9router` (overrides global default). Map through Rafx's lane rule
FIRST — glm-5.3 = `glmpro`, glm-5.3-flash = `glmflash`, claude/gpt/grok =
`trove/<model>` — then grep `GET /v1/models` (Bearer NINEROUTER_API_KEY) for the
exact ID before pinning; 747+ models live there and names drift. Full cron
class (archive/remove/recreate/verify): references/cron-management.md.

## Gotchas
- Plain-IP `http://100.83.110.118:20128/v1/*` serves 404 on subpaths — only the
  tailscale-serve HTTPS route exposes the full API. Use the hostname.
- 9router dashboard password file on zergling is STALE (login 401, lockout
  after 5). To read/modify state use its sqlite directly:
  `/root/.9router/db/data.sqlite` (tables: providerConnections, apiKeys,
  usageHistory). Never insert rows ad-hoc without cloning the exact data JSON
  shape — and prefer asking Rafx to do dashboard changes.
- Model groups agreed with Rafx (build pending his go): A1 pro = glm/glm-5.3
  via 9router; A2 flash = glm-5.3-flash pinned per-job; B free workers =
  bzl/auto:free → glm/glm-5.3-flash@9router → direct z.ai flash. OpenRouter
  stays manual-only (maintenance tier). DeepSeek rung pending his $1.5 recharge
  confirm.
