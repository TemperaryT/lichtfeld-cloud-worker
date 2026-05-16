# Plan: Pre-built LichtFeld image on GHCR, simplified smoke test

## Context

The current `lichtfeld-cloud-worker` repo builds LichtFeld from source on every Vast rental
(~30 min via `bootstrap_instance.sh`). The Nerfstudio cloud-burst pipeline solved this
elegantly: a pre-built image is specified as the Vast instance image, and Vast pulls + runs
it as the container itself (Vast's `ssh_direct` runtype — no Docker-in-Docker, the instance
IS the container). We want the same for LichtFeld.

**Decisions confirmed:**
- Build platform: **GitHub Actions** (free, repeatable, runs while operator is away ~1 week)
- Image variant: **Multi-stage runtime** (~6–7 GB final image, current Dockerfile already structured this way)

**The result:**
- One git tag push → GHA builds + pushes `ghcr.io/temperaryt/lichtfeld-cloud-worker:v0.5.2`
- Vast rental uses that image; LichtFeld already installed when SSH is ready
- `smoke_test_direct.sh` drops the 30-min build step
- Total smoke test goes from ~90 min → ~30-40 min
- Future rebuilds = push a new tag

**Operator is on the road ~1 week**. After return, Gungnir is back, `cloud_burst_lfs` handler
takes over (Phase 2). This plan delivers everything needed to execute the smoke test
manually before the handler exists.

---

## Confirmed facts (Phase 1 research, 2026-05-15)

| Item | Status |
|---|---|
| Robot arm video on Mjolnir NFS | ✓ `/mnt/automation_data/inbox/robot_arm.mp4` (706 MB) |
| Backup video (alt smoke source) | ✓ `Went_last_scan_pix.mp4` (1.2 GB, same dir) |
| VAST_API_KEY in `automation_server/.env` | ✓ Real value confirmed |
| GitHub auth on agent LXC | ✓ `gh auth status` → TemperaryT, scopes: `repo workflow` |
| `lichtfeld-cloud-worker` git remote | ✓ `github.com/TemperaryT/lichtfeld-cloud-worker` |
| Vast `ssh_direct` ≡ "instance IS the container" | ✓ Confirmed in Vast docs + `scripts/vast_client.py:194` |
| Vast supports GHCR public images (no auth) | ✓ Pulls automatically from `ghcr.io/...` |
| Vast does NOT support Docker-in-Docker | ✓ Explicitly stated in docs |
| Current Dockerfile multi-stage, headless build flag | ✓ `-DLFS_ENFORCE_LINUX_GUI_BACKENDS=OFF` |
| Agent LXC has Docker | ✗ Not installed (irrelevant once GHA builds) |
| Gungnir | ✗ Down (hardware, auto-restart pending) |

---

## Build architecture

```
                   ┌───────────────────────────┐
git tag v0.5.2 ──▶ │ GitHub Actions runner     │
                   │ (4 vCPU, 16 GB RAM, 14 GB)│
                   │ docker/build-push-action  │
                   └────────────┬──────────────┘
                                │ push
                                ▼
                   ┌───────────────────────────┐
                   │ ghcr.io/TemperaryT/       │
                   │ lichtfeld-cloud-worker    │
                   │ :v0.5.2  + :latest        │
                   │ (public visibility)       │
                   └────────────┬──────────────┘
                                │ pull
                                ▼
                   ┌───────────────────────────┐
                   │ Vast.ai instance          │
                   │ (instance IS this image)  │
                   │ LichtFeld pre-installed   │
                   │ ffmpeg, prep deps baked   │
                   └───────────────────────────┘
```

---

## Changes

### 1. `lichtfeld-cloud-worker/.github/workflows/build-and-push.yml` (NEW)

- Triggers: `workflow_dispatch` (manual) + `push: tags: ['v*']`
- Uses `docker/build-push-action@v5` with multi-platform off (linux/amd64 only)
- Build args: `LFS_TAG=${{ github.ref_name }}` and `MAKE_JOBS=2` (memory-safe parallelism)
- Cache: `type=gha` for layer reuse on rebuilds
- Tags published: `:${{ github.ref_name }}` (immutable) + `:latest` (mutable convenience)
- Auth: `permissions: { packages: write, contents: read }` + `GITHUB_TOKEN`
- Expected build time: 60–90 min on first run, 15–30 min on cache hits
- Public visibility configured one-time via `gh api` (documented in workflow header)

### 2. `lichtfeld-cloud-worker/Dockerfile` (MODIFY)

- Add `ARG MAKE_JOBS=$(nproc)` and replace `cmake --build build -j$(nproc)` with `-j${MAKE_JOBS}` — lets GHA pass `MAKE_JOBS=2` to stay within 16 GB RAM
- Runtime stage: add `ffmpeg python3-pip` + `pip3 install --break-system-packages opencv-python-headless pillow numpy` so `prep_frames.py` runs without setup on the instance
- Remove `VOLUME ["/data","/output"]` (Phase-1 use is direct, not docker-run with volumes; volumes complicate ssh_direct mode)
- Keep ENTRYPOINT for Phase-2 docker-run compatibility (Vast `ssh_direct` overrides it anyway)

### 3. `automation_server/cloud/vast/profiles/lichtfeld.json` (MODIFY)

```json
{
  "max_dph": 0.75,
  "min_gpu_vram": 16000,
  "min_gpus": 1,
  "min_reliability": 0.95,
  "min_cuda": 12.0,
  "disk": 60,
  "image": "ghcr.io/temperaryt/lichtfeld-cloud-worker:v0.5.2",
  "offer_type": "ondemand",
  "search_limit": 10
}
```

- `image`: swap from `nvidia/cuda:12.8.0-devel-ubuntu24.04` → our pre-built image
- `disk`: 80 → 60 GB (image is ~7 GB; ~50 GB workspace is plenty for 400 frames + PLY)

### 4. `lichtfeld-cloud-worker/run/smoke_test_direct.sh` (MODIFY)

Drop stages 2 + 4 (script deploy + bootstrap build). New flow:

1. **GPU + LFS check** — `nvidia-smi`, `lichtfeld-studio --version` (must both succeed)
2. **Transfer video** — pipe via Mjolnir relay (unchanged)
3. **Extract frames** — ffmpeg already in image; no install
4. **Prep frames** — SCP `prep_frames.py` from automation_server (still keep it external — small enough); deps already baked
5. **Launch training** — `tmux new-session -d -s lfs_train ...` (unchanged)
6. **Exit, print poll command**

Total time: ~30-40 min instead of ~90.

### 5. `lichtfeld-cloud-worker/run/status_direct.sh` (MODIFY for token efficiency)

Collapse 3 SSH round-trips into 1:

```bash
_ssh "printf 'build=%s train=%s note=%s\n' \
    \"\$(grep '^STATE=' /workspace/lichtfeld/STATUS/BUILD 2>/dev/null | cut -d= -f2-)\" \
    \"\$(grep '^STATE=' /workspace/lichtfeld/output/STATUS.md 2>/dev/null | cut -d= -f2-)\" \
    \"\$(grep '^NOTE=' /workspace/lichtfeld/output/STATUS.md 2>/dev/null | cut -d= -f2-)\""
```

One line out, one SSH round-trip. Note: in the pre-built-image world `STATUS/BUILD` is always `done` (or absent) — kept for fallback compat.

### 6. `lichtfeld-cloud-worker/run/build_and_push.sh` (NEW)

Convenience wrapper around `gh`:

```bash
# Usage: bash run/build_and_push.sh [tag]   (default tag: v0.5.2)
gh workflow run build-and-push.yml -f tag="${1:-v0.5.2}"
gh run watch  # follows latest run
```

So operator can fire-and-forget from agent LXC without leaving the shell.

### 7. `lichtfeld-cloud-worker/run/monitor.sh` (NEW — unattended polling loop)

For the operator's week away, fills the polling gap left by `smoke_test_direct.sh` exiting
after training launches. Long-running tmux companion that emits one log line per state
transition and exits cleanly when the run terminates.

```bash
# Usage: bash run/monitor.sh <ssh_host> <ssh_port> [interval=60]
# Run in its own tmux pane/window on agent LXC. Reattach any time:
#   tmux attach -t lfs_smoke
# Or read from elsewhere:
#   tail -f ~/projects/lichtfeld-cloud-worker/logs/monitor-<host>.log
```

Behavior:
- Polls `status_direct.sh` every 60s (configurable, third arg)
- Writes to `logs/monitor-<host>.log` ONLY when state changes (no log spam)
- Detects: `train=DONE`, `train=FAILED`, `train=crashed`, SSH connection failures (3 in a row → log and continue)
- On DONE/FAILED: writes final summary line + exits zero/nonzero accordingly
- Tail of log is the entire timeline of the run — easy to inspect later
- No Discord/webhook integration yet (Discord webhook not provisioned per NOW.md);
  leave a single TODO hook where it would slot in

This is the "what's happening" answer for the operator/LLM check-ins:
just `tail logs/monitor-<host>.log` — no token cost during the run, full timeline available.

### 8. `lichtfeld-cloud-worker/run/bootstrap_instance.sh` (KEEP — demote to fallback)

Don't delete. Useful if GHA breaks, or for testing a new LichtFeld release branch before
tagging the image. Update its docstring to flag it as "fallback / one-off" path.

### 9. `lichtfeld-cloud-worker/docs/runbook_smoke_test.md` (MODIFY)

Rewrite step 1 (build) to be a **one-time setup**:

```
ONE-TIME (already done by previous operator session, skip unless re-building):
  bash run/build_and_push.sh v0.5.2
  # Wait ~60-90 min, then mark package public:
  gh api -X PATCH /user/packages/container/lichtfeld-cloud-worker/visibility -f visibility=public
```

Then the per-run steps stay: rent → smoke_test_direct.sh → poll → download → destroy.

### 10. `lichtfeld-cloud-worker/README.md` (MODIFY)

Add a short "Image: ghcr.io/temperaryt/lichtfeld-cloud-worker:v0.5.2" line up top with the
rebuild command. Move the existing Docker section (Phase 2) further down.

### 11. `automation_server/NOW.md` + `LOG.md` (MODIFY)

NOW: replace the current smoke-test-direct instructions with the new image-pull flow. Note
the GHA workflow as the one-time setup.
LOG: append a new entry summarizing the pivot to pre-built image strategy.

---

## Polling and health-check ownership

Who polls — and when — depends on the phase:

| Phase | Owner | Cadence | Notes |
|---|---|---|---|
| Build (now: pre-built image, 5–10 min Vast pull) | `vast_burst.py wait` | 10s, ≤5 min timeout | Existing logic, unchanged |
| Frame extract + prep (5 min) | `smoke_test_direct.sh` foreground | sequential | Synchronous SSH calls, fail fast |
| Training (30–60 min, **the polling gap**) | `run/monitor.sh` in tmux | 60s default | NEW — fills the gap once `smoke_test_direct.sh` exits |
| Operator/LLM check-in | `tail logs/monitor-<host>.log` | on-demand | Zero token cost during the run |
| Failure recovery (now) | Operator inspects `logs/`, re-runs targeted stage | manual | Documented in runbook |
| Phase 2 (Gungnir back) | `cloud_burst_lfs.py` worker handler | 10–30s + Postgres heartbeat | Mirrors `cloud_burst_3dgs.py`; N8N timeout sweeper catches stalls |

**Why monitor.sh and not LLM-driven polling for the smoke test**: the operator is on the
road for a week. A polling loop running on agent LXC under tmux costs nothing in tokens,
captures the full timeline in a log, and survives terminal disconnects. The LLM check-in
becomes a 5-line `tail` on whatever cadence the operator wants — no `ScheduleWakeup`
loops, no autonomous polling. When the worker daemon exists (Phase 2), monitor.sh is
retired in favor of the daemon's built-in heartbeat.

**Failure detection**:
- `monitor.sh` detects `train=FAILED`, `train=crashed`, or 3 consecutive SSH failures → exits nonzero, writes summary
- `status_direct.sh` returns `pending` for missing STATUS files (instance still booting / scripts not yet deployed) — monitor.sh treats this as informational, not a failure

---

## Implementation model

This plan is intentionally mechanical: one new GHA workflow, one new bash script
(`monitor.sh`), one new helper (`build_and_push.sh`), targeted edits to Dockerfile +
existing scripts + profile JSON + docs. **Sonnet 4.6 can implement it end-to-end.**
Opus reserved for two scenarios:
- GHA build fails with a non-obvious error (e.g., vcpkg port conflict, OOM signature)
- We discover the Vast `ssh_direct` startup needs custom onstart behavior we didn't anticipate

---

## Token-efficiency principles applied throughout

1. **One SSH round-trip per poll** — `status_direct.sh` returns one line summarizing all state
2. **All build/training output → log files on instance** — agent reads via `run/logs.sh <stage>` only when something fails
3. **`smoke_test_direct.sh` log prefix** — single-line stage transitions, no progress bars
4. **`set +x` everywhere** — no shell tracing
5. **`apt-get install -y -qq`** and `ffmpeg -loglevel warning` in Dockerfile to reduce build noise
6. **STATUS files are key=value triples** — easy to grep, never multi-line
7. **No tail -f in scripts** — agent decides when to fetch logs

---

## Files to create / modify

| Path | Action |
|---|---|
| `lichtfeld-cloud-worker/.github/workflows/build-and-push.yml` | NEW |
| `lichtfeld-cloud-worker/run/build_and_push.sh` | NEW |
| `lichtfeld-cloud-worker/run/monitor.sh` | NEW (fills polling gap during training) |
| `lichtfeld-cloud-worker/Dockerfile` | MODIFY: MAKE_JOBS arg, runtime deps (ffmpeg, python pkgs) |
| `lichtfeld-cloud-worker/run/smoke_test_direct.sh` | MODIFY: drop bootstrap + script-deploy stages; print monitor.sh launch command |
| `lichtfeld-cloud-worker/run/status_direct.sh` | MODIFY: single SSH round-trip |
| `lichtfeld-cloud-worker/run/bootstrap_instance.sh` | KEEP, update docstring (fallback path) |
| `lichtfeld-cloud-worker/docs/runbook_smoke_test.md` | MODIFY: one-time image build vs per-run |
| `lichtfeld-cloud-worker/README.md` | MODIFY: GHCR image up top |
| `automation_server/cloud/vast/profiles/lichtfeld.json` | MODIFY: new image, disk 60 |
| `automation_server/NOW.md` | MODIFY: new flow |
| `automation_server/LOG.md` | APPEND: pre-built image pivot entry |

---

## Verification path

1. **GHA build succeeds** — `gh run watch` returns success, image visible at
   `https://github.com/TemperaryT?tab=packages`
2. **Make package public** —
   `gh api -X PATCH /user/packages/container/lichtfeld-cloud-worker/visibility -f visibility=public`
   then `gh api /users/temperaryt/packages/container/lichtfeld-cloud-worker | jq .visibility` = `public`
3. **Vast can pull** — `python3 scripts/vast_burst.py search --profile cloud/vast/profiles/lichtfeld.json`
   returns offers (no auth error on the image field)
4. **Instance comes up** — `python3 scripts/vast_burst.py wait <id>` returns SSH info within 5-10 min
5. **LichtFeld binary present** — `ssh -p <port> root@<host> "lichtfeld-studio --version"` succeeds
   without any setup
6. **ffmpeg + prep deps present** — `ssh ... "which ffmpeg && python3 -c 'import cv2,PIL,numpy'"`
7. **End-to-end smoke** — `bash run/smoke_test_direct.sh <host> <port>` completes in ~30-40 min
   total, producing a PLY in `/workspace/lichtfeld/output/`
8. **Destroy when done** — `python3 scripts/vast_burst.py destroy <id> --yes`

---

## When operator returns (Gungnir back, ~1 week)

1. **Resolve N8N sweeper** — re-store `N8N_API_KEY` in `.env`, re-import fixed
   `automation_timeout_sweeper.json`; stale job `bc2e1b04` then auto-cleans
2. **Phase 2: `cloud_burst_lfs` handler** — mirrors `worker/handlers/cloud_burst_3dgs.py`:
   - Reads `cloud/vast/profiles/lichtfeld.json` (same pre-built image)
   - Calls `vc.create_instance` + `vc.wait_for_ready`
   - SCPs frames to `/workspace/cloud_burst/input/`
   - Triggers training via SSH (same `run_train.sh` baked in image)
   - Polls STATUS.md (same contract)
   - Pulls output, uploads PLY to B2, calls `vc.destroy_instance`
3. **N8N dispatch entry** — add `cloud_burst_lfs` to `worker/worker.py` dispatcher
4. **`docs/pipelines.md`** — document the new contract
