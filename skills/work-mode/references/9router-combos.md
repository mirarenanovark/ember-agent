# 9router combos — orchestration top tier (verified 2026-09-08)

Combos live in `/root/.9router/db/data.sqlite` (zergling), table `combos`
(id, name, kind, models JSON). Read/edit via ssh root@100.83.110.118 python3 sqlite3
(host has no sqlite3 CLI; 9router local :20128 there, tortuga reaches it via SSH tunnel :20129).

Current combos: glmpro [glm/glm-5.3, nanogpt/z-ai/glm-5.2], glmflash [3× flash],
lab-workers [10 members], advisors [grok-4.5 → grok-4.6 → glmpro].

Combo edit pattern: UPDATE the `models` JSON in the combos row (python3 heredoc over ssh),
then test one real prompt and check usageHistory for which provider served it.
Dead members (claude-fable-5 junk upstream, gpt-5.6-sol paywall) were removed from
'advisors' by Rafx — don't re-add without a fresh probe.

SSH map (from tortuga/local): mira@tortuga works (id_ed25519, root does NOT);
zergling = root@100.83.110.118 (id_ed25519; tailnet IP via `getent hosts zergling.tail28e85.ts.net`);
rena fallback root@89.34.230.188 keyless from tortuga.
