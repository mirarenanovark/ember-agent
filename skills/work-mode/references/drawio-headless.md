# Headless draw.io authoring + delivery (no drawio binary on tortuga)

When producing an editable `.drawio` diagram (infra map, architecture) on
this box: no drawio desktop/binary → author raw XML, validate with the
skill's script, deliver file + encoded viewer URL. Never try the skill's
NL/HTML/PNG export paths — they shell out to the missing binary.

## Procedure

1. `skill_view(drawio-skill)` first; for precise multi-node layouts read its
   `references/xml-authoring.md`. Author XML directly in a write_file —
   do not attempt diagramctl NL generation headless.
2. Gather facts LIVE before drawing (systemctl --user list-units, docker ps,
   tailscale ip, proxy_host conf greps) — diagram must match reality, not
   memory. NPM confs: upstreams live in `set $server`/`set $port` vars, a
   bare `grep proxy_pass` misses them.
3. Structure that validates clean:
   - Host/container boxes = top-level vertices; member nodes = children
     (`parent="<box-id>"`) with x/y RELATIVE to the box. Sibling nodes placed
     inside a box's rect trigger overlap warnings; parenting removes them.
   - Cross-box edges: `parent="1"`, absolute waypoint Arrays. Intra-box
     edges: parent = the box.
   - Pin `exitX/exitY/entryX/entryY` (0..1) on busy edges so waypoints stay
     deterministic between validate runs.
4. Iterate `python3 ~/.hermes/skills/creative/drawio-skill/scripts/validate.py
   --score <file>` — treat score as layout lint:
   - Route inter-box edges through the empty gutter column between boxes;
     going OVER the top of everything beats threading between boxes.
   - A waypoint ring around the whole canvas (below boxes, up the far side)
   resolves routes that would otherwise cross 2+ boxes.
   - Residual ~60 on a dense map = acceptable. Fix errors and box overlaps;
   do not chase every edge crossing to zero.
5. Deliver:
   - The `.drawio` file (send as MEDIA: — editable in draw.io desktop/web).
   - Shareable link: `python3 .../scripts/encode_drawio_url.py <file>` →
     viewer.diagrams.net URL with diagram embedded. Zero deps, works
     without the binary.

## Conventions (this user's stack maps)

- Host container labeled `HOSTNAME — role (key IP)`; one fill-color family
  per host; user = `mxgraph.basic.smiley` top-center; title cell with date.
- Artifacts under `/home/xor/data/Mira_dev/`.
