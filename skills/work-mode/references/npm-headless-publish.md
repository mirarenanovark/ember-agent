# Publishing a zergling service on a NPM subdomain (headless, no API creds)

NPM admin password unknown → do NOT brute-force. Everything is doable via files + docker exec. Host: zergling (172.235.53.167), NPM data at /home/xor/data/docker_data/nginx_manager/{data,letsencrypt}.

## Procedure

1. **DNS**: DuckDNS auto-wildcards `*.zergling.duckdns.org` → host IP. Verify: `getent hosts <name>.zergling.duckdns.org`. No DNS-step needed per subdomain.
2. **Attach the service to `appbridge`** (NPM's docker network) so nginx can proxy by container name:
   `docker network connect appbridge <container>`.
   GOTCHA: runtime-only. On the next container recreate/update the attach is LOST and the URL 502s — re-run, or add the network to the compose file.
3. **Issue the cert headless** with certbot INSIDE the NPM container (it ships certbot + dns-duckdns plugin; DNS challenge = no port juggling):
   ```
   printf 'dns_duckdns_token=<token>\n' > /home/xor/data/docker_data/nginx_manager/letsencrypt/duckdns.ini  # chmod 600
   docker exec nginx-proxy-manager certbot certonly \
     --authenticator dns-duckdns --dns-duckdns-credentials /etc/letsencrypt/duckdns.ini \
     -d <name>.zergling.duckdns.org --non-interactive --agree-tos -m kthieve@gmail.com
   ```
   (token lives in NPM DB redirection/proxy host meta; duckdns.ini path inside ctr = /etc/letsencrypt via mount.)
   Result lands in letsencrypt/live/<certname>/ — next free npm-N name.
4. **Write the conf**: copy an existing proxy_host/N.conf as template, or minimal server block: listen 80 (ACME + redirect) + 443 ssl with `ssl_certificate /etc/letsencrypt/live/<certname>/fullchain.pem`, `set $server "<container-name>"; set $port <port>; include conf.d/include/proxy.conf;`. Filename = next free proxy_host/N.conf.

### Static-site variant (no upstream container)

For plain file hosting (HTML/JS builds): skip the appbridge attach. Put files
under `.../nginx_manager/data/www/<name>/` (the data dir mounts at `/data`
in-container) and in the 443 block use:

```
root /data/www/<name>;
index index.html;
location / { try_files $uri $uri/ =404; }
```

Cert WITHOUT the duckdns creds file (HTTP-01 webroot works because wildcard
DNS already resolves the name): write the conf HTTP-ONLY first (listen 80 +
ACME location + static root), reload, then:

```
docker exec nginx-proxy-manager certbot certonly --webroot \
  -w /data/letsencrypt-acme-challenge -d <name>.zergling.duckdns.org \
  --non-interactive --agree-tos --register-unsafely-without-email \
  --cert-name npm-<N>
```

PITFALL: `include conf.d/include/letsencrypt-acme-challenge.conf` may NOT
EXIST in the NPM data dir — the include silently fails and certbot 404s the
challenge ("Invalid response from .../.well-known/acme-challenge/"). Use an
inline location instead: `location /.well-known/acme-challenge/ { root
/data/letsencrypt-acme-challenge; }` — self-contained, no include dependency.

PITFALL: DuckDNS wildcard resolves EXACTLY ONE level (`*.zergling.duckdns.org`).
Deeper labels (`x.y.zergling.duckdns.org`) NEVER resolve — certbot fails and
the URL dead-ends for the user even with a perfect conf. Never publish a
multi-level subdomain; host the endpoint under a PATH on an existing name
(same-domain scoped location, below). (Certs are also per-exact-hostname —
a parent cert never covers a child label.)

### Cross-host variant (proxy to a service on ANOTHER machine, scoped path)

For publishing one narrow endpoint of a service that lives on a different
host (e.g. an approval button bound to tortuga's tailnet IP, published via
zergling's NPM): skip appbridge entirely and `proxy_pass http://<tailnet-ip>:<port>`.

1. Verify reachability BEFORE writing the conf: `docker exec nginx-proxy-manager
   curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://<tailnet-ip>:<port>/`
   — a 404 from the target is fine (alive), a timeout means routing is broken.
2. Use the same TWO-STAGE conf as the static variant: the stage-1 HTTP-only conf
   works for proxied targets too — the ACME challenge include serves the challenge
   path itself, the upstream is never touched. Issue the webroot cert, then flip
   to the full pair.
3. SCOPE THE PATH — publish the ACTION, never the admin surface: expose only the
   narrowest location prefix that fulfills the public purpose
   (`location /approve/ { proxy_pass ...; }`) and `location / { return 404; }`
   everything else. Privileged endpoints (`/register`, config, health) stay
   tailnet-only and unreachable through the public name.
4. Confirm the published page works THROUGH the proxy path with no edits:
   relative forms/links (`action=""`, relative hrefs) traverse cleanly; an
   absolute internal URL baked into the response breaks public taps — grep the
   server source for its own bind IP before publishing.
5. Verify the full semantic loop from outside: unauth/no-token → 404/403, valid
   token → success page, token replay → 403 (single-use held). Then a real test
   end-to-end through the same public URL the user will tap.

Then flip the conf to the pair (80 = ACME include + `return 301`), reload
again. Content-only redeploys = re-copy files into `www/<name>/`, NO reload.
Hand-written N.conf files are INVISIBLE in the NPM admin UI but fully
functional — future edits must go to the file, never hunted in the panel.
5. **Apply + verify**: `docker exec nginx-proxy-manager nginx -t && docker exec nginx-proxy-manager nginx -s reload`. 'conflicting server name ... ignored' warning = a stale DB row claims the hostname; the FILE conf wins — verify by behavior, don't chase the warning.
6. **Verify from OUTSIDE the box** (curl over real internet or another host): unauth → expect 401/307/redirect; wrong creds rejected; http→https 301; and one AUTHENTICATED request with a real API key where applicable. HTTP 200 from inside the host is not evidence.

### Cross-host full-service variant (dynamic service on another tailnet host)

For proxying a WHOLE dynamic service (admin UI, API) on another tailnet host:
same two-stage cert, then 443 block with full header forwarding:

```
location / {
  proxy_pass http://<tailnet-ip>:<port>;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

Bind the target service to its TAILNET IP (not 127.0.0.1) so NPM reaches it
(pass `--bind <tailnet-ip>` or equivalent). Verify the chain end-to-end
externally: login page loads, wrong password rejected, session cookie set.

### Same-domain scoped location (dynamic app beside static files)

Serve an app under a PATH of an already-published static domain (no new
subdomain, no new cert): add ONE location block ABOVE the static root in
the existing 443 server block:

```
location /admin {
  proxy_pass http://<tailnet-ip>:<port>;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}
root /data/www/<name>;
location / { try_files $uri $uri/ =404; }
```

App must emit RELATIVE URLs (or honor X-Forwarded-*) so assets/form posts
traverse the prefix. Verify the full auth loop externally: login page,
wrong password rejected, session cookie set, API 401 without cookie.

### Auto-deploy via systemd path unit (static sites)

When a local build regenerates `out/` and the site serves from zergling, wire
auto-deploy so rsync is never manual:

```
# ~/.config/systemd/user/<name>-deploy.service   Type=oneshot, ExecStart=rsync -r --delete out/ → www/<name>/
# ~/.config/systemd/user/<name>-deploy.path       PathChanged=/abs/path/to/out
```

`systemctl --user enable --now <name>.path`. Any write to out/ fires the
rsync oneshot — no build-script changes. Watcher is always armed: touching
out/ files during debugging triggers real deploys.

## Precedents

- blog.zergling.duckdns.org → static www/blog/ (weblog: stdlib SSG, cert npm-16)
  + editor at /admin (same-domain scoped location → tortuga tailnet :8111).
  edit.blog.* multi-level name ABANDONED (DNS never resolves); npm-17 cert
  orphaned — free number, but never re-point that conf.

- chat.zergling.duckdns.org → matrix:6167 (websocket + client_max_body_size 50M + well-known) — references/matrix-gateway-selfhost.md
- 9router.zergling.duckdns.org → 9router:20128 (API + dashboard; fresh cert npm-10)
- clean.zergling.duckdns.org/approve/ → tortuga tailnet approval button (cross-host scoped-path variant, webroot cert npm-15, two-stage conf). Numbering note: hand-written confs skip numbers (14.conf sat unused) — pick next free by `ls`, not by count.
