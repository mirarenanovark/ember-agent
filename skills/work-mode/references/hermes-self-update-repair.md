# Hermes self-update repair (PM-managed installs)

## Signature (all from ONE interrupted/mangled `hermes update`)
- `~/.local/bin/hermes` → `line 4: .../venv/bin/hermes: No such file or directory`
- Gateway journal at boot: `No adapter available for telegram` (+ the mira-menu hook echo)
- Cron scheduler: `Restart-safe cron worker dispatch failed ... ModuleNotFoundError: No module named 'ruamel'`
- Runtime-backed tools (web_extract etc.) fail with the same import error — the
  error signature following you across surfaces = shared-runtime breakage.

## Diagnose (one batched call)
1. `systemctl --user cat hermes-gateway.service` — ExecStart names the in-tree
   launcher (`~/.hermes/hermes-agent/.hermes/bin/hermes gateway run`), NOT the
   venv; the venv is resolved at runtime by hermes_bootstrap → venv_sync.
2. `ls ~/.hermes/installs/<install-hash>/` — `source-completion-pending`
   ("source update tail not finished") = env built, tail never ran. `facts.json`
   beside it names the selected venv path + extras (telegram, matrix, ...).
3. Import-test `ruamel.yaml` in the facts.json venv python → OK there but
   ModuleNotFoundError from the bare toolchain python = consumers launch on the
   wrong interpreter; that is the whole disease.

## Repair (in order)
1. `~/.hermes/hermes-agent/.hermes/bin/hermes pm repair` — prepare_launch sees
   the pending marker, finishes the tail, re-execs into the managed venv.
   Verify: no `source-completion-pending` left in the install dir.
2. Re-pin the user shim: rewrite `~/.local/bin/hermes` to `exec` the LIVE venv
   from facts.json (`~/.hermes/installs/<hash>/environments/<env-hash>/venv/bin/hermes "$@"`),
   chmod +x, then `hermes --version` must print a version and exit 0.
3. Restart the gateway so platform adapters load on the fixed runtime:
   `gdbus call --session --dest org.freedesktop.systemd1 --object-path /org/freedesktop/systemd1 --method org.freedesktop.systemd1.Manager.RestartUnit 'hermes-gateway.service' replace`
   (works where in-tree systemctl restart is guard-blocked).
4. Verify the restart LANDED: `systemctl --user status` shows `active (running)
   since` AFTER the repair timestamp + a new MainPID. `is-active` alone lies.
5. Telegram close-out: journal since the new boot has no `No adapter available`;
   probe both egress legs (direct + `--proxy socks5h://127.0.0.1:1093`), and
   `~/.hermes/cache/tg-smart-proxy.log` names the leg actually carrying traffic.

## Gotchas
- The env dir hash CHANGES on every update/repair — never hardcode it in unit
  files; the `~/.local/bin/hermes` shim is the only place a path may be pinned,
  and it must be re-pinned each time.
- First minutes after restart can log transient SOCKS/proxy errors while
  tg-tunnel cycles; the watchdog heals in ~2 min — judge by the quiet journal
  AFTER that window, not the first 60 seconds.
- `hermes pm sync` does not exist (verbs: lock/install/env/doctor/repair/gc/
  bundle/status/update) — `pm repair` is the finisher.
- An interrupted `pm repair` may still have completed its effect (Orphan
  recovery warning) — re-check the pending marker + gateway start time before
  re-running anything.
