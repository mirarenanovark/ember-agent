# z.ai GLM Coding Plan quota endpoint (2026-09-04)

The ONLY programmatic view into the GLM Coding Plan 5h window / monthly cap.
Everything else (/usage, /quota, coding variants) 404s. Discovered by reading
9router's source: `open-sse/services/usage/glm.js` ← registry
`open-sse/providers/registry/glm.js` → `transport.usage.url`.

## Call

```
curl -H "Authorization: Bearer $GLM_API_KEY" \
     -H "Accept: application/json" \
     https://api.z.ai/api/monitor/usage/quota/limit
```

## Response shape (data.limits[])

- `TOKENS_LIMIT` + `unit:3, number:5` → **the 5h token window**:
  `percentage` = used%, `nextResetTime` = epoch ms.
- `TIME_LIMIT` → monthly cap (same fields).
- `data.level` = plan tier ("lite", etc.).
- usageDetails[] breaks out search tools (search-prime / web-reader / zread).

Example live read (2026-09-04): lite plan, 13% of 5h window used, reset
00:04 UTC, monthly 0%.

## Use

- Check before assuming quota headroom on heavy days; alert-worthy ≥75% of
the 5h window or ≥80% monthly.
- Natural home: fold into headroom-health daily cron (alongside proxy check).
- 9router dashboard shows the same numbers for its kthive glm connection —
but direct curl works from anywhere with the key.

## Related pattern: finding hidden usage APIs

When a router/proxy tool (9router, claude-code-router, etc.) displays quota
info a provider doesn't document, grep its bundled source for the provider's
registry entry — `transport.usage` / `getUsage` reveals the upstream endpoint.
Docker images: `docker exec <ctr> sh -c 'cat <path>'`.
