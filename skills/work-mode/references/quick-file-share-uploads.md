# Quick file-share uploads from tortuga + rena-vps (verified 2026-09-03)

The deployed tool is `~/.hermes/scripts/up.sh` (tortuga) and
`/root/.hermes/scripts/up.sh` (rena-vps). Usage: `up.sh <file> [catbox|tmpfiles|uguu]`.

## Working providers (per-host, verified)

| provider | expiry | tortuga | rena-vps | notes |
|---|---|---|---|---|
| catbox.moe | permanent | ✅ | ❌ "Invalid uploader" (IP block) | default in up.sh |
| tmpfiles.org | 60 min | ✅ | ✅ | API returns viewer page — script extracts real `/dl/` link |
| uguu.se | ~48-72h | ✅ | ✅ | JSON has `\/` escaped slashes — script unescapes before grep |

All keyless, curl-only, Chrome UA recommended.

## DEAD list (verified 2026-09-03 — do NOT re-test pointlessly)

Rafx supplied this list as "temp file share sites"; all five are dead or parked:

- **bayfiles.com** / **anonfiles.com** — domains NXDOMAIN. The 2023 anonfiles
  family (anonfiles/bayfiles/etc.) is dead; NJalla NS records linger, no A records.
- **anonfiles.me** + **anonymfile.com** — resolve ONLY to parity.domains parking
  landers (Namecheap parking; IPs 2.59.170.20 / 104.219.250.37). A stray `api.`
  vhost exists on nginx/1.28.3 but: 404s every clone path (/upload, /api/upload,
  /v2/upload, /api/v2/upload), TLS-rejects curl (unexpected eof / tlsv1
  unrecognized name), AND resets real headless Chrome (puppeteer-core in
  donsetch-test got `ERR_CONNECTION_CLOSED`). Service is gone — parking lander
  change would be the first sign of return.
- **anyfile.co** — GoDaddy for-sale lander.
- **gofile.cc** — urdance.com redirect lander (NOT the real gofile.io, which has
  a proper API if ever wanted).

## Techniques that were needed to reach these conclusions

- **SNI-pin trick** for TLS-fingerprinted hosts: `curl --resolve
  <domain>:443:<origin-IP> -H "Host: api.<domain>" https://<domain>/...` — sends
  SNI for the domain whose cert/IP accepts your TLS config while Host header hits
  the api vhost. Confirmed origin nginx WAS reachable this way (404s prove it) —
  the service itself was just gone, not blocked.
- **TLS downgrade** `--tlsv1.2 --tls-max 1.2` got main-domain anonymfile.com to
  serve (parking page) when default TLS 1.3 failed. api. vhost enforced 1.3+.
- **donsetch-test container as browser-fallback**: has Chrome at
  /opt/chrome-linux64/chrome; puppeteer-core installable in ~15s (`cd /tmp/x &&
  npm i puppeteer-core`). File transfer INTO the container: `docker cp` hits a
  sandbox quirk (lstat phantom) — use `cat file | docker exec -i <c> sh -c 'cat
  > /path'` instead. Local Lightpanda browser backend segfaulted (-11) this day —
  container Chrome is the resilient path for fingerprint-hostile sites.
- **Local scrape backend (localhost:3003) can be down** — web_extract fails with
  connection refused; fall back to curl/donsetch rather than retrying it.
