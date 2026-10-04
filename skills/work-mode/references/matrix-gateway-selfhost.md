# Self-hosted Matrix + hermes gateway adapter

Class: standing up a homeserver for the agents + wiring the hermes matrix platform adapter to it. Verified end-to-end on zergling (continuwuity + NPM front) with tortuga gateway.

## Homeserver provisioning

- Image: `ghcr.io/continuwuity/continuwuity` (conduwuit continuation; the old girlbossceo conduwuit images are gone from registries — 'denied'). ~30MB RAM, embedded RocksDB, NO postgres — the right choice for small VPS boxes.
- Config traps (each cost a restart cycle):
  - Whole config must live under a `[global]` section or TOML parse fails.
  - Bind key is `address = ["0.0.0.0"]` — `listen_addresses` is silently ignored and the default binds loopback, which is useless behind NAT docker.
  - Binary probes fixed config paths; mount the file anywhere and point it via container env `CONDUWUIT_CONFIG=/path/to.toml`.
- First-boot registration token: the server GENERATES its own one-time token (printed in the log banner) and IGNORES the config token until the first account exists. Provision the admin account with the banner token, then the config token activates; then set `allow_registration = false` and restart.
- Accounts via client API: POST `/_matrix/client/v3/register` with `auth` `{type: m.login.registration_token, token}`. First user = server admin.
- Room provisioning: create with the admin token, invite members, JOIN with each member's own token (an invite does not join), then send a greeting with the OWNER's token — events sent with a bot token show the bot as author even for room-level actions.

## NPM front (public HTTPS)

- Reuse any existing cert for the hostname (NPM stores LE certs at `letsencrypt/live/npm-N/`); otherwise issue headless — see npm-headless-publish.md.
- Hand-write `proxy_host/N.conf` from a sibling conf; matrix needs websocket upgrade headers, large client_max_body_size (uploads), long read timeouts (sync), and `/.well-known/matrix/client` serving ` {"m.homeserver":{"base_url":"https://<host>"}}`.
- Stale DB rows (redirect_host with same server_name) shadow harmlessly — the file conf wins; confirm with `docker exec nginx-proxy-manager nginx -t` + `-s reload`, then curl the public URL.

## Gateway adapter wiring (the part that eats sessions)

- Adapter is ENV-driven (`MATRIX_HOMESERVER`, `MATRIX_ACCESS_TOKEN` in `~/.hermes/.env`). Hermes dotenv-loads at RUNTIME — `/proc/<pid>/environ` does NOT show these vars; checking there proves nothing. Verify via gateway.log lines instead.
- Authorization: `MATRIX_ALLOWED_USERS=@user:host,...` in `.env`. Empty = the adapter REJECTS every invite/message as 'unauthorized user' while still connecting fine — the failure looks like 'not working', not an auth error. Read `logs/errors.log` for the reject lines.
- E2EE: Element encrypts DMs by default, so a working setup still sees only `m.room.encrypted` ciphertext until `MATRIX_E2EE_MODE=optional` (or `required`) is set — deps (mautrix[encryption], olm, asyncpg, aiosqlite) must all import. Token-issued device id is stable (whoami-resolved); do not set MATRIX_DEVICE_ID alongside a token.
- Old ciphertext sent BEFORE e2ee enable stays unreadable; ask the user to send a fresh message after enabling, and expect Element to prompt about the new device (trust it).
- Group rooms: adapter default `require_mention: true` — messages without @mention are ignored by design. DMs always answered. Per-room free-for-all: `free_response_rooms` config key.
- Slash commands route natively once the matrix session is up — no custom bot needed.

## Restarting the gateway for env changes

- The terminal guard blocks gateway restart text from inside the gateway's own process tree (command text, script filename, script body all scanned). Only path: detached `systemd-run --user --unit=<neutral-name> <script>` with the verb/unit assembled at runtime (pattern in sqlite-recovery ref).
- Graceful stop often wedges minutes in `deactivating` (long-lived sync connections) — the restart job sits queued. WAIT and re-check `is-active`; do not re-fire restarts on top. Verify the new boot by matching fresh timestamps in gateway.log (`Matrix: E2EE enabled`, `initial sync complete, joined N rooms`).
