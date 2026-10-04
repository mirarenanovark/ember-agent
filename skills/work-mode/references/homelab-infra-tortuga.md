# Tortuga homelab infra — live map + repair recipes

## DNS stack (who owns what)

- **:53 = Pi-hole FTL**, native `pihole-FTL.service` (NOT a container).
  Reads `/etc/pihole/pihole.toml` (v6 TOML, root-only 644) — read via
  `pihole-FTL --config dns.upstreams` style CLI, not cat. The old
  `/etc/pihole/setupVars.conf` may not exist anymore.
- **:5335 = unbound**, recursive resolver upstream of Pi-hole
  (`/etc/unbound/unbound.conf`: interface 127.0.0.1, port 5335).
  NOTE: `/etc/unbound/unbound.conf.d/` contains only `*.disabled` files —
  unbound.conf is a monolith; nothing in .d is live.
- /etc/resolv.conf = public resolvers (1.1.1.1/8.8.8.8). Tailscale DNS
  (`tailscale dns status` → disabled) is OFF by owner choice. MagicDNS is
  tailnet-wide enabled; this host just doesn't consume it.
- systemd-resolved, dnsmasq, bind9: installed-away/inactive. Don't enable
  them as "fixes".

## unbound repair (post-crash)

Symptom: unit failed, journal says `error reading auto-trust-anchor-file:
/var/lib/unbound/root.key` + `bad config for validator module`.
1. `ls -la /var/lib/unbound/root.key` — 0 bytes = crash-truncated state.
2. Delete it; rebuild the trust anchor:
   `/usr/lib/unbound/package-helper root_trust_anchor_update`
   (copies seed from /usr/share/dns/root.key, then unbound-anchor grows it).
3. `systemctl restart unbound`; verify: `systemctl is-active unbound` →
   active, `dig @127.0.0.1 -p 5335 example.com` → NOERROR + Query-time
   footer, `dig @127.0.0.1 example.com` → NOERROR (Pi-hole→unbound chain).
- `unbound-checkconf` as non-root fails on root-only /var/lib/unbound —
  a validator error there does NOT prove the live config is broken.
- `systemctl unbound restart` is NOT valid syntax (systemd eats it as unit
  name) and prints nothing; use `systemctl restart unbound`.

## zram — two packages, one owner

- BOTH `zram-tools` (zramswap.service, /etc/default/zramswap) and
  `zram-config` (zram-config.service, /usr/bin/init-zram-swapping) installed.
- zram-config wins the boot race: owns /dev/zram0 (lzo-rle, 50% RAM,
  priority 5, above disk swap sda5 prio -2).
- zramswap.service then fails forever (`zramswap start` → device busy).
  Fix: `systemctl disable --now zramswap` (keep zram-config).
- Verify swap health via `swapon --show` + `zramctl`, not unit state.
- If ever switching to zram-tools ALGO=zstd: stop zram-config first.

## RAM-fault triage (no ECC board)

dmesg/journal says `EDAC ie31200: No ECC` — no hardware error logging.
Signature of bad RAM: GPF storms repeating the SAME non-canonical address,
`BUG: Bad page state` at multiple pfns on the next boot, OOM storms,
short/looping boots (`last -x`). After pulling a stick: compare fault
history (`journalctl --list-boots`, syslog greps) vs clean uptime on the
survivor, `dmidecode -t memory` for slot/serial map, `memtester <size> 2`
backgrounded (apt install memtester) for positive proof.

## Kernel-log forensics without sudo

Agent user sees `-- No entries --` from journalctl (no systemd-journal
group) and `dmesg: Operation not permitted` (kernel.dmesg_restrict).
Working path: `docker run --rm -v /var/log:/hlog:ro ubuntu:24.04` and
grep/awk the plain-text syslog/kern.log by date window. Privileged
nsenter = host root but hits the user-approval gate — keep those calls
single and last; batch read-only forensics through the ro mount.

## Tailscale on this host

100.125.29.66 tortuga, one preauthkey-less node among personal devices;
expired-key peers show in `tailscale status` but pass no traffic — check
expiry/grace before debugging the far end. DNS off (see above).
