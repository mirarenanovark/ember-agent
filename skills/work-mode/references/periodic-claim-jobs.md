# Periodic claim/collector jobs — revive + wire pattern (nanswap case, 2026-09-06)

## Class pattern (order matters)
1. Find the job's remains before assuming it never existed: skills dir,
   skills-archive (a daily cron evicts unused >14d — see skill-manager),
   fact_store probes. "scrapling" turned out to be an archived SKILL
   (scrapling-official v0.4.15, full SKILL.md, on rena-vps), NOT an installed
   library — `import scrapling` fails; using it needs a venv +
   `pip install "scrapling[all]"` + `scrapling install`.
2. Read the job's own evidence: ledger.jsonl + last test report. Nanswap's
   report showed 7/7 claims Sep 3 → mechanism proven, only revival needed work.
3. Test ONE real claim/iteration by hand. Wire the cron only after a verified
   success — never schedule unverified code.
4. Self-healing cron wrapper: health-check the daemon (CDP :9222) → restart if
   down → reopen the tab if missing → run collector. Log to a size-capped file
   (`[ $(stat -c%s) -gt 524288 ] && tail -c 65536` rotate).

## Nanswap nano-faucet deployment (rena-vps, LIVE 2026-09-06)
- Cron (root crontab): `*/30 * * * * /root/.hermes/scripts/nano-faucet-cron.sh >> /root/.hermes/logs/nano-faucet.log 2>&1`
- Wrapper `/root/.hermes/scripts/nano-faucet-cron.sh`: exports PATH incl.
  /root/.local/bin + /root/.hermes/node/bin (rena PATH quirk), heals CDP :9222
  (chrome-headless-shell restart) + reopens the nano-faucet tab via
  `curl -X PUT http://127.0.0.1:9222/json/new?url=...`, then runs collector once
  with RUN_TAG=cron.
- Collector `/root/.hermes/skills/nanswap-faucet/collector.py` (copied from
  skills-archive/nanswap-faucet), stdlib-only raw-CDP websocket.
- Ledger `ledger.jsonl` in the skill dir: 5.04e-6 XNO total at go-live;
  4.2e-7 claims verified twice post-patch.
- Wallet `nano_3u3pehowj3qpyehuyfpsg4c55kdgwq178thix5yfdo44x8oset7ehxp16bc6` —
  hardcoded in collector.py, provenance UNVERIFIED (Rafx asked which address it
  uses; no confirmation yet — replace if he names a different one).

## Collector bugs fixed 2026-09-06 (both invisible until full source read)
1. `get_page_ws` matched `nanswap.com` loosely → attached the BANANO tab (its
   URL also contains nanswap.com), which had been frozen for days. Fix: exact
   `nanswap.com/nano-faucet` match, else raise.
2. First CDP `Runtime.evaluate` after attaching to a long-idle tab TIMES OUT
   once (frozen tab recovers on the next connect). Fix: `evaluate()` retry
   wrapper — 3 attempts, 1s sleep, fresh websocket each attempt.
- Chrome layout on rena: `/opt/chrome-for-agents/.../chrome-headless-shell`
  (261M) is ALSO the DONGHOST_CHROME for the donsetch MCP — never remove.
  Persistent faucet tabs (nano + banano + others) live in that browser; stale
  error tabs linger harmlessly.
