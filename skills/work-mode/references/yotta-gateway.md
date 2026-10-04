# Yotta AI gateway (yottalabs.ai) — verified end-to-end

GPU cloud + AI gateway. Console = console.yottalabs.ai (Next.js/Vercel + Supabase auth).
Docs = docs.yottalabs.ai (GitBook). Key lives in Rafx's account (~$2 class balance).

## Finding the real API on SPA-console platforms (reusable pattern)

1. Grep the console's own bundled JS for the literal API host:
   `curl -s https://console.yottalabs.ai/_next/static/<...>/_app-<hash>.js | grep -oE 'https?://[a-z0-9.-]+'`
   → yields `api.yottalabs.ai` (console API) and friends.
2. Strip the docs pages locally when scrapers are down — GitBook bakes full content into the
   HTML: `curl -s <doc-url> | python3` with `re.sub(r'<script.*?</script>|<style.*?</style>', ' ', t, flags=re.S)`
   + strip tags + `html.unescape`. The `/products/ai-gateway` page holds complete Python client
   examples (endpoints, params, polling). `/api-and-sdk/api-reference-v*` pages are heavy-SPA —
   use the products pages instead.

## Auth split (the trap)

- Inference gateway: `https://gateway.yottalabs.ai/api/maas`, header **`X-API-KEY: <key>`**.
- `api.yottalabs.ai` is the CONSOLE backend: `/api/*` routes want a console session JWT;
  Bearer-with-API-key there → 401 `Malformed token`. Its `/v1/*` routes answer
  `{"message":"parameter error","code":10001}` — dead end for key auth, not a bad key.
- Rule: 401/param-error on a guessed base URL = wrong lane, not wrong credential. Find the
  gateway host from docs/JS before concluding the key is bad.

## Endpoints (all under `https://gateway.yottalabs.ai/api/maas`)

- `GET /models` → `{code:10000, data:{records:[{slug, name, category, display_price:{price}}]}}`
- Text-to-video: `POST /text-to-video/generations` `{model, parameters:{prompt, duration 3-15,
  aspect_ratio, generate_audio, cfg_scale, multi_shot...}}` → `data.request_id`
- Image-to-video: `POST /image-to-video/generations` `{model, parameters:{prompt, first_frame:
  <PUBLIC URL>, duration, resolution '720p'|'1080p', seed}}`
  - first_frame: jpg/png URL, ≤10MB, ≥300px per side, ratio 1:2.5–2.5:1. No upload endpoint
    found — host the image publicly (litterbox 72h: `curl -F reqtype=fileupload -F time=72h
    -F fileToUpload=@img.jpg https://litterbox.catbox.moe/resources/internals/api.php`).
- Poll: `GET /text-to-video/generations/{request_id}` (same path family) → `status`
  queued/processing/completed/failed/cancelled, `output_url` on completed. 5s wan3.0-i2v took
  ~2 min at 960x960 with audio.
- Output is a signed Aliyun OSS URL WITH EXPIRY — download immediately.

## Models + pricing

- Video (per-clip display price): wan3.0-{t2v,i2v,r2v} 0.035 · seedance-2.0 0.05-0.08 ·
  seedance-2.5 0.08-0.12 · pixverse-v6/c1 · kling-v3-std/pro-text · happyhorse-1.0 family ·
  seedream-4.5/5.0-lite (text-to-image).
- LLMs: kimi-k3, deepseek-v4-pro/flash/r1/v3.2, glm-5.3/5.2, qwen3.x family.
- **PRICE TRAP: `display_price` ≠ billed amount.** A 5s wan3.0-i2v listed 0.035 actually
  charged 0.35 (10x) off the balance. Read the FIRST real generation's balance delta before
  batching any workflow; never budget from catalog prices.

## Model choice for i2v of Mira

Canon face render (`~/data/Mira_dev/profile-gen/official/`) → litterbox URL → wan3.0-i2v
(cheapest lane). Prompt = motion description only (face/expression/camera); identity comes
from the first frame, not the prompt.
