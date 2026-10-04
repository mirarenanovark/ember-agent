# vast.ai self-hosted Wan 2.2 video generation — proven runbook

Marginal cost ~$0.006/clip (50s per 81-frame clip, 4-step lightx2v) on RTX 5090.
Supersedes hosted lanes (Yotta wan3.0 ~$0.35/clip real billing, balance died).

## GPU + host selection (HTTP API, not CLI)

- `vastai search offers` CLI rejects standard filter syntax — POST the query to
  `https://console.vast.ai/api/v0/bundles/?q=<urlencoded json>` with `Authorization:
  Bearer $VAST_API_KEY`. Working filter set:
  `{"gpu_name":{"eq":"RTX 5090"},"reliability2":{"gte":0.99},"inet_down_cost":{"lt":0.005},
   "disk_bw":{"gt":3000},"rentable":{"eq":true},"num_gpus":{"eq":1},
   "host_id":{"notin":BAD_HOSTS}}` — sort by `dph_total` ascending.
- Bandwidth is billed separately in $/GB and varies by host: check `inet_down_cost` /
  `inet_up_cost` per offer. Cheap-$/hr A100 listings can carry $0.5+/session bandwidth —
  compute per-SESSION cost, not $/hr.
- 5090 (fp8 weights) beats A100 80GB on price/perf for this stack by ~3x.
- Keep a BAD_HOSTS blacklist in the provisioning code: hosts where ssh never came up
  or the instance self-stopped get skipped forever. Cheap hosts fail differently from
  good ones (connection refused on the broker port for many minutes, or cur_state
  flips to `stopped` after create).

## Instance lifecycle

- Create: `vastai create instance <offer-id> --image <img> --disk 60 --env '-p 8188:8188'
  --label <label>` — the CLI builds the payload correctly; raw API POST 400s on missing env.
- Response `new_contract` is an INT — cast to str before passing to subprocess args.
- `running` ≠ ready: poll `vastai ssh-url <contract> --raw` AND TCP-connect the port.
  Wait for TCP open, then also poll instance state and fail fast on
  `stopped`/`exited`/`error` (host may auto-purge the contract; destroy then 404s — fine).
- SSH via broker host from `vastai ssh-url` (sshN.vast.ai:PORT); raw IPs often time out.
  Key = the account's registered pubkey (id_ed25519 mira@root on tortuga).
- Always `vastai destroy instance <id> -y`. After any crash/restart of the driving
  process, run `vastai show instances --raw` — orphans bill invisibly.
- `vastai take snapshot` requires a docker registry login — not available; reproducibility
  = one-command e2e setup script instead (~10 min).

## Stack setup on a fresh box (vast_wan_e2e.sh)

1. apt install aria2 FIRST (script uses aria2c -x8; missing binary = silent setup fail
   at the weights step). Also install ffmpeg (chain-frame extraction).
2. ComfyUI: git clone + venv + `pip install torch... --index-url download.pytorch.org/whl/cu128`
   (Blackwell needs cu128+). Export PIP_RETRIES=8 PIP_TIMEOUT=60 — pypi read-timeouts
   killed setups; alternatively use the official `vastai/comfy` template image (id 720337)
   to skip pip entirely (weights still manual; comfy lives at /workspace/ComfyUI, port
   forwarding 8188→18188).
3. Weights (~37GB total, HF `Comfy-Org/Wan_2.2_ComfyUI_Repackaged/split_files/...`, exact
   filenames via HF API tree listing — never guess):
   - diffusion_models: wan2.2_i2v_{high,low}_noise_14B_fp8_scaled.safetensors (14.3GB each)
   - loras: wan2.2_i2v_lightx2v_4steps_lora_v1_{high,low}_noise.safetensors
   - text_encoders: umt5_xxl_fp8_e4m3fn_scaled.safetensors (6.7GB)
   - vae: wan_2.1_vae.safetensors (1.4GB)
   - clip_vision: clip_vision_h.safetensors (1.26GB, from Wan_2.1 repo)
4. Launch comfy detached with `setsid` — plain nohup dies when the vast sshd kills the
   session group on disconnect. Poll `curl 127.0.0.1:8188/system_stats` until ready
   (model load takes minutes after port opens).

## Generation (ComfyUI API graph)

- Build the API-format graph from the official template JSON shipped inside the comfy
  venv (`comfyui_workflow_templates_json/templates/video_wan2_2_14B_i2v.json`), or reuse
  the proven `/tmp`→app copy: dual UNETLoader (high+low noise), LoraLoaderModelOnly ×2,
  WanImageToVideo, CLIPLoader umt5, CLIPVisionLoader/Encode, KSamplerAdvanced ×2
  (steps 0–2 high / 2–4 low), euler/simple, CFG 1, shift 5, SaveVideo.
- POST via python urllib ON THE BOX (curl quoting breaks: "Server got itself in
  trouble"). Patchable node ids in the saved graph: 9=positive text, 11=start image,
  14=length, 15=noise_seed.
- SaveVideo format must be `"mp4"` — `"h264-mp4"` errors the node.
- Poll `/history/<prompt_id>` until `status.status_str` in (success, error); output
  filename from `outputs[*].images[*].filename`, fetch via scp from `ComfyUI/output/`.
- If driving comfy through an ssh remote-python shim, wrap the response in a marker
  (`VIJSON<<...>>`) and regex it out — ssh banner/notice lines corrupt naive
  last-line json.loads, and the failure surfaces as a JSONDecodeError one stack away
  from the real cause.

## Chained scenarios (multi-clip continuity)

- wan_batch_generate.py + wan_scenarios.json: each clip's last frame (ffmpeg -sseof
  -0.1 -frames:v 1) = next clip's start_image; resumable state.json; --only/--resume.
- I2V ANCHORS HARD TO THE FIRST FRAME: a clothed start image never becomes explicit —
  explicit scenarios must chain from the previous clip's nude end-state.
- QC every scenario: ffmpeg frame montage → vision check identity, proportions, and
  explicit anatomy at bottom-half zoom. Rate honestly; user's eyes are final judge.
- ffmpeg concat demuxer → `-c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p` for joins.

## Cost model

- Setup (spin + pip + 37GB download): ~$0.25, ~35 min, one-time per instance.
- Per clip: ~50s → ~$0.006 at $0.35-0.40/hr. Per session of ~10 clips: ~$1.30 all-in.
- Broken instances (dead GPU, OCI runtime error, ssh-never-up) happen — destroy fast,
  blacklist the host, next offer. Real-world: ~1 in 3 first-pick offers fails.
- Restorable image (stopped instance or volume) = $10-12/mo standing (storage_cost
  ~$0.20/GB/mo, billed while stopped, balance-0 = data deletion). Re-download instead
  costs ~$0.04/session — volume only wins past ~250 sessions/month.

## Pitfalls

- vast sshd kills the session group on disconnect → detached processes MUST setsid.
- Read weight filenames from the HF API — a guessed name 404s mid-script.
- `--env '-p 8188:8188'` must be one shell arg; the port map is what makes comfy
  reachable for spot-checks, though ssh-tunnel via remote python works without it.
- Cardless accounts run on credit: check `/api/v0/users/current/` balance before long
  sessions; zero balance stops instances (storage still billed).
- No Rena-facing exposure: outputs land in the chamber (mira-dashboard chamber/videos),
  served over tailnet.
