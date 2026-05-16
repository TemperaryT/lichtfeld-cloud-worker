# Runbook: LichtFeld Smoke Test (Pre-built Image on Vast)

**Status:** Ready to execute once the GHCR image is published and public.

The image is pulled by Vast as the instance image — no Docker-in-Docker, no per-rental
build. Bypasses worker-01/Gungnir entirely.

```
ghcr.io/temperaryt/lichtfeld-cloud-worker:v0.5.2
  → Vast instance boots AS this image (LichtFeld + ffmpeg + python deps preinstalled)
  → SCP video from Mjolnir (via agent LXC relay)
  → ffmpeg: extract ~400-600 raw frames
  → prep_frames.py: blur filter → 400 sharp frames
  → LichtFeld MCMC 30k iter → PLY
  → monitor.sh polls until DONE
  → rsync output back to laptop
```

Total time: ~30–40 min per run (image pull 5–10 min + frame prep 5 min + training 30–60 min).

---

## One-time setup — publish image to GHCR

**Skip if already done** (image visible at https://github.com/TemperaryT?tab=packages).

```bash
cd ~/projects/lichtfeld-cloud-worker
bash run/build_and_push.sh v0.5.2
# Triggers GHA workflow, watches it to completion (~60-90 min first time).

# Once succeeded, make the package public ONCE:
gh api -X PATCH /user/packages/container/lichtfeld-cloud-worker/visibility \
    -f visibility=public

# Verify:
gh api /users/temperaryt/packages/container/lichtfeld-cloud-worker | jq .visibility
# → "public"
```

---

## Per-run workflow

### Step 1 — rent instance

```bash
cd ~/projects/automation_server
source .env && export VAST_API_KEY

python3 scripts/vast_burst.py search --profile cloud/vast/profiles/lichtfeld.json
```

Profile requires: 16 GB+ VRAM, CUDA 12.0+, ≤$0.75/hr, 60 GB disk, RTX 30/40 series.

```bash
OFFER_ID=<id from search>
python3 scripts/vast_burst.py create "$OFFER_ID" \
    --profile cloud/vast/profiles/lichtfeld.json \
    --label lichtfeld-smoke-01

INSTANCE_ID=<instance_id from output>
python3 scripts/vast_burst.py wait "$INSTANCE_ID"
# → {"ssh_host": "...", "ssh_port": ...}

SSH_HOST=<ssh_host>
SSH_PORT=<ssh_port>
```

### Step 2 — run smoke test in tmux

```bash
tmux new-session -s lfs_smoke

cd ~/projects/lichtfeld-cloud-worker
bash run/smoke_test_direct.sh "$SSH_HOST" "$SSH_PORT"
```

Stages 1–5 run foreground (~5 min total: pre-flight, video transfer, frame extract+prep,
launch training). Training is launched detached in tmux on the instance — the script
exits with poll/download/destroy commands printed.

### Step 3 — start monitor in its own tmux session

```bash
tmux new-session -d -s lfs_monitor -- bash run/monitor.sh "$SSH_HOST" "$SSH_PORT"

# Read the timeline any time (zero token cost — just file reads):
tail -f logs/monitor-${SSH_HOST}.log
```

`monitor.sh` polls every 60 s, logs state transitions only, and exits when
training reaches DONE or FAILED. Detach freely.

### Step 4 — download results

```bash
mkdir -p ~/results/robot-arm-v1
rsync -avz -e "ssh -p $SSH_PORT" \
    "root@${SSH_HOST}:/workspace/lichtfeld/output/" \
    ~/results/robot-arm-v1/
# Expect: *.ply, train.log, STATUS.md
```

### Step 5 — destroy instance

```bash
python3 ~/projects/automation_server/scripts/vast_burst.py destroy "$INSTANCE_ID" --yes
```

Do not leave the instance running — GPU is billed per hour.

---

## On failure

| Symptom | Check |
|---|---|
| `lichtfeld-studio: missing` in stage 1 | Instance not using pre-built image; check `lichtfeld.json` profile and `Step 1` outputs |
| `GPU not visible` in stage 1 | Wrong instance image / image incompatible with GPU |
| Training `FAILED` with flag error | `ssh -p $SSH_PORT root@$SSH_HOST 'lichtfeld-studio --help'` and compare to `scripts/run_train.sh` |
| `--max-cap` unrecognized | Remove `LFS_MAX_CAP=3000000` env var |
| `--train` unrecognized | Remove `--train` from `scripts/run_train.sh` and re-tag/re-build image |
| Frame count zero | Check `/workspace/lichtfeld/logs/prep.log` on instance; lower `--threshold` (e.g. 50) |

### Re-run training only after fixing flags

```bash
ssh -p $SSH_PORT root@$SSH_HOST "tmux kill-session -t lfs_train 2>/dev/null; tmux new-session -d -s lfs_train \
  'env LFS_DATA_PATH=/workspace/lichtfeld/prepped/frames \
       LFS_OUTPUT_PATH=/workspace/lichtfeld/output \
       LFS_STRATEGY=mcmc LFS_ITER=30000 LFS_MAX_WIDTH=1920 LFS_MAX_CAP=3000000 \
   bash /opt/lichtfeld/scripts/run_train.sh'"
bash run/monitor.sh "$SSH_HOST" "$SSH_PORT"
```

---

## Known unknowns (validate during the first run)

1. Does `--train` flag exist in v0.5.2 Linux build? (`lichtfeld-studio --help` confirms)
2. Does `--max-cap` exist? (remove if not)
3. Exact PLY output path — script uses `find *.ply` dynamically
4. GHA build time for first publication — expect 60–90 min

Record actuals in LOG.md after first successful run.

---

## Fallback path (build-from-source on Vast)

If GHCR is broken or you need to test an unreleased LichtFeld branch:

1. Search/rent with a **different** profile pointing at `nvidia/cuda:12.8.0-devel-ubuntu24.04`
2. SCP `run/bootstrap_instance.sh` to instance
3. Run it — builds LichtFeld in tmux (~30 min on GPU instance)
4. Proceed with `smoke_test_direct.sh` (pre-flight check will succeed once the binary is present)

This path is documented for emergencies — the pre-built image is the primary route.

---

## Phase 2 hook (when Gungnir is back)

The same GHCR image becomes the contract for `cloud_burst_lfs` handler in automation_server.
The handler mirrors `worker/handlers/cloud_burst_3dgs.py`: claims a job from Redis, calls
`vc.create_instance` with `cloud/vast/profiles/lichtfeld.json`, polls STATUS.md via SSH,
uploads PLY to B2, destroys instance.
