# Tailscale serve — exposing localhost-only services (validated 2026-09-02, 9router on zergling)

## When
A service bound to 127.0.0.1 on a VPS/host (deliberately not public) needs to be
reachable by Rafx from his own devices without an SSH tunnel. NOTE (2026-09-02,
Rafx): he does NOT browse from tortuga — "i dont directly use your machine. as long
as YOU can access it, it's fine." So: expose it, verify it yourself via curl, and
hand him the URL; do not over-engineer tortuga-side name resolution.

## Recipe (proven end-to-end)
1. Check whether tailscale actually exists: `tailscale version` on the host. Do NOT
   trust memory — zergling's old install had vanished silently.
2. If missing: `curl -fsSL https://tailscale.com/install.sh | sh` then
   `systemctl enable --now tailscaled`.
3. `nohup tailscale up --hostname=<name> >/tmp/ts-up.log 2>&1 &` — it prints a login
   URL (https://login.tailscale.com/a/<id>). No auth key is stored anywhere on our
   machines, so the USER must open that link and approve. Post the link, then poll
   `tailscale status` (loop, ~2 min) until the node shows JOINED; grab `tailscale ip -4`.
4. Expose, TWO flavors (both tailnet-only, app port stays 127.0.0.1-bound — docker:
   `-p 127.0.0.1:PORT:PORT`, never 0.0.0.0):
   - HTTPS + name: `tailscale serve --bg --https=443 http://127.0.0.1:PORT`
     → https://<host>.<tailnet>.ts.net with valid TLS.
   - PLAIN HTTP on the ORIGINAL port (Rafx prefers `machinename:port` style):
     `tailscale serve --bg --http=PORT http://127.0.0.1:PORT` → serve listens on
     that same port number on the tailnet IP and proxies to the loopback app.
     Then `http://zergling:20128` works from any MagicDNS device. Add ONE flavor
     per port; combine both when unsure.
5. Verify from another tailnet machine (tortuga):
   `curl --resolve <host>.tail28e85.ts.net:443:<ts-ip> https://<host>.tail28e85.ts.net/`
   expecting the app's status code (9router = 307 → login). For the http-port
   flavor: `curl --resolve <host>:PORT:<ts-ip> http://<host>:PORT/`.
   Undo: `tailscale serve --https=443 off` / `--http=PORT off`.

## Quirks
- Tortuga has Tailscale DNS disabled (resolv.conf nameservers 1.1.1.1/8.8.8.8), so
  *.ts.net names and short MagicDNS names do NOT resolve there — curl exit 6. That
  is a tortuga-side DNS choice, not a broken serve. Always verify with --resolve,
  or browse from Windows/Android devices whose Tailscale client handles MagicDNS.
- Writing the name→ts-ip mapping into tortuga's /etc/hosts needs root (no stored
  xor sudo password) — default to --resolve verification instead of fighting it.
- Known tailnet: kthieve@gmail.com, MagicDNS suffix tail28e85.ts.net.
- Known nodes (2026-09-02): tortuga 100.125.29.66, aurora 100.76.103.123 (often
  offline), zergling 100.83.110.118. dark-garden-7035 (100.103.38.37, offline 174d)
  = Rena's OLD node — evidence her install predates the one found missing.
- PORT COLLISION (2026-09-04, WGDashboard on zergling): tailscaled BINDS the
  serve port on the tailnet IP (100.x.y.z:PORT AND its IPv6), so a later
  `docker -p PORT:PORT` (0.0.0.0 bind) fails "address already in use" even
  though nothing shows on `ss` for 0.0.0.0. Fix: publish the container on a
  DIFFERENT host port and point serve at it (e.g. host 10443 → ctr 10086, serve
  --https=10086 http://127.0.0.1:10443). Also: recreating the published container
  STALE-ifies an existing tailscale serve target — after any `docker compose up
  -d` recreate, re-run the serve command and re-verify (got a 502 until repointed).

