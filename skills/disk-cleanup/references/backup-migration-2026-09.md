# Migration case: sillytavern backups off /home (2026-09)

Order of operations that worked, as a reusable pattern for "move big tree to
another disk AND keep a copy on this one":

1. Copy BOTH trees to the new disk first (`rsync -aH`, one target dir per
   source) — sources untouched until every copy verifies.
2. `rm -rf` the copied sources on the old disk — this is where the space is
   actually freed; do it before building any same-disk keep-copy.
3. THEN build the keep-copy as a hardlink tree (`cp -al`) from what remains
   relevant, or from the new-disk copy if the keep-dir must sit on the old
   disk's filesystem.

Key rule: never build the same-disk keep-copy while the source still exists —
a real copy doubles usage and a nearly-full disk wedges mid-copy (watch `df`
during every copy; abort on the spike). Hardlink manifest verify:
`find . -type f -printf '%P %s\n' | sort | sha256sum` on both trees, compare
hashes — `du -s` totals differ by directory-entry rounding and false-fail.

Also: check the keep-copy target's ownership before starting — app dirs under
`data/` can be root-owned while their parent is user-writable; one level up is
a legitimate fallback location (tell the user which path was used).

Container logs without sudo: the nsenter truncate pass (SKILL.md §3) worked on
the snap docker data-root for every container including a 150M+ json.log.
