# Hermes cron management (tortuga + rena-vps)

## Inspection
- `hermes cron list` — summary (schedule, mode, last status). Fields the table hides
  (model pin, deliver target, enabled, failure_streak, prompt): read
  `~/.hermes/cron/jobs.json` directly — list of job dicts; `model: null` = inherits
  global `model.default`; `model_snapshot` = model it was created with.
- `jobs.json.bak.*` next to it are goldmines for recreating old jobs (prompt,
  schedule, deliver, pause reason all preserved).

## Lifecycle
- Archive BEFORE remove: copy the job's object to
  `~/.hermes/cron/removed-archive/<id>_<name>.json`, then `hermes cron remove <id>`.
  Removal is instant and undo-less; the archive is the only recovery path.
- Recreating a paused/legacy job: read its archived JSON FIRST — schedule, deliver,
  and especially the pause reason. A job paused over a broken dependency (dead key,
  dead provider) must not be simply resumed; rebuild the dependency or pin, then
  create fresh with an updated prompt.
- `hermes cron create "<cron-expr>" "<prompt>" --name N --deliver D` = agent mode.
  Script jobs: `--script <file-in-~/.hermes/scripts/> --no-agent` (filename only,
  no args — wrap args in a wrapper script).
- Skill flags attach a skill wholesale to every run — attach only skills that carry
  the job's voice/domain. Wrong-skill attachment = wrong persona output on every
  fire; `hermes cron edit <id> --clear-skills` removes.

## Model pinning
- `hermes cron create/edit <id> --model <id> --provider 9router` pins per-job,
  overriding the global default; no pin = follows `model.default`.
- Map through the LLM lane rule BEFORE pinning: glm-5.3 = `glmpro`,
  glm-5.3-flash = `glmflash`, claude/gpt/grok = `trove/<model>`. Then grep
  `/v1/models` (Bearer NINEROUTER_API_KEY) for the exact ID — 747+ models live
  there and names drift; never pin from memory.

## Deliver targets
- `origin` (chat that spawned), `local` (file only, silent), `telegram` (home),
  `platform:chat_id` (e.g. `telegram:-5480703286`). All verified from CLI.
- Choose by content audience: intimate/personal content → `local` or `origin`,
  never a shared topical group.

## Verify a new or edited job
1. Read back `jobs.json` — confirm model/provider/deliver/enabled fields actually
   landed (CLI edit output is one line; the file is the truth).
2. `hermes cron run <id>` — fires immediately, prints `Ran now: succeeded`.
3. Check the job's REAL side effect, not the exit code: file-writing job → stat
   the file's mtime within seconds of the run; report job → find the new PDF in
   the expected dir. A succeeded run with no side effect = pin/target wrong.