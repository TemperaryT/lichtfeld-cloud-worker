# Runbook: LichtFeld Smoke Test (Direct on Vast)

**Status:** Ready to execute. All scripts built. No instance rented yet.

This runs the full pipeline on a rented Vast.ai GPU — bypasses worker-01/Gungnir entirely.

```
robot_arm.mp4 (Mjolnir NFS)
  → transfer to Vast instance
  → ffmpeg: extract ~400-600 raw frames
  → prep_frames.py: blur filter → 400 sharp frames
  → LichtFeld MCMC 30k iter → PLY
  → download output
```

Total time: ~90 min (30 min build + 5 min frames + 30-60 min training)

---

## Prerequisites

- `VAST_API_KEY` in `~/projects/automation_server/.env` — confirmed set
- Video at `/mnt/automation_data/inbox/robot_arm.mp4` on Mjolnir NFS — confirmed
- Scripts at `~/projects/lichtfeld-cloud-worker/` — committed

---

## Step 1 — Search and rent instance

```bash
cd ~/projects/automation_server
source .env && export VAST_API_KEY

python3 scripts/vast_burst.py search --profile cloud/vast/profiles/lichtfeld.json
```

Pick the cheapest offer. Profile requires: 16GB+ VRAM, CUDA 12.0+, ≤$0.75/hr, 80GB disk.
Image: `nvidia/cuda:12.8.0-devel-ubuntu24.04`

```bash
OFFER_ID=<id from search>
python3 scripts/vast_burst.py create "$OFFER_ID" \
    --profile cloud/vast/profiles/lichtfeld.json \
    --label lichtfeld-smoke-01
# → prints instance_id

INSTANCE_ID=<instance_id from output>
python3 scripts/vast_burst.py wait "$INSTANCE_ID"
# → {"ssh_host": "...", "ssh_port": ...}

SSH_HOST=<ssh_host>
SSH_PORT=<ssh_port>
```

---

## Step 2 — Run smoke test in tmux

```bash
tmux new-session -s lfs_smoke

cd ~/projects/lichtfeld-cloud-worker
bash run/smoke_test_direct.sh $SSH_HOST $SSH_PORT
```

The script runs sequentially through 6 stages with progress logs. Polling is built in.
You can detach (`Ctrl-B D`) and reattach (`tmux attach -t lfs_smoke`) at any point.

---

## Step 3 — Monitor training (after script exits)

`smoke_test_direct.sh` exits after launching training. Poll manually:

```bash
bash run/status_direct.sh $SSH_HOST $SSH_PORT
# build=done train=TRAINING  note: strategy=mcmc iter=30000 frames=400
# ... wait 30-60 min ...
# build=done train=DONE      note: ply=final.ply
```

To tail live training output:
```bash
ssh -p $SSH_PORT root@$SSH_HOST 'tail -f /workspace/lichtfeld/output/train.log'
```

---

## Step 4 — Download results

```bash
mkdir -p ~/results/robot-arm-v1
rsync -avz -e "ssh -p $SSH_PORT" \
    root@$SSH_HOST:/workspace/lichtfeld/output/ \
    ~/results/robot-arm-v1/
# Expect: *.ply, train.log, STATUS.md
```

Record the PLY size and training time in LOG.md. These calibrate future runs.

---

## Step 5 — Export viewer (optional)

```bash
bash run/export.sh ~/results/robot-arm-v1
# → ~/results/robot-arm-v1/viewer/scene.html

bash run/serve.sh ~/results/robot-arm-v1 8080
# → tunnel: ssh -L 8080:localhost:8080 op@192.168.4.61
```

---

## Step 6 — Destroy instance

```bash
python3 ~/projects/automation_server/scripts/vast_burst.py destroy "$INSTANCE_ID" --yes
```

Do not leave the instance running after the smoke test — GPU time is billed per hour.

---

## On failure

| Symptom | Check |
|---|---|
| Build stuck at `installing_deps` or `cloning` | `ssh -p $SSH_PORT root@$SSH_HOST 'tail -30 /workspace/lichtfeld/logs/build.log'` |
| Training `FAILED` with flag error | `ssh -p $SSH_PORT root@$SSH_HOST 'lichtfeld-studio --help'` — compare flags |
| `--max-cap` not recognized | Remove `LFS_MAX_CAP=3000000` from the re-run command |
| `--train` not recognized | Remove `--train` from `scripts/run_train.sh` and re-push |
| No PLY after training | Check `train.log`; may need `--train` flag OR different output path |
| Frame count zero | Check `logs/prep.log`; lower `--threshold` (try 50) |

### Re-run training only (after flags fixed)

```bash
ssh -p $SSH_PORT root@$SSH_HOST "tmux new-session -d -s lfs_retrain \
  'env LFS_DATA_PATH=/workspace/lichtfeld/prepped/frames \
       LFS_OUTPUT_PATH=/workspace/lichtfeld/output \
       LFS_STRATEGY=mcmc LFS_ITER=30000 LFS_MAX_WIDTH=1920 LFS_MAX_CAP=3000000 \
   bash /workspace/lichtfeld/scripts/run_train.sh'"
bash run/status_direct.sh $SSH_HOST $SSH_PORT
```

---

## Known unknowns (discover during this run)

1. Does `--train` flag exist in v0.5.2 Linux build? (`--help` will show it)
2. Does `--max-cap` exist? (remove if not)
3. Exact PLY output path — script uses `find *.ply` dynamically
4. Build time on actual Vast hardware — may vary 15-60 min
5. Does headless build flag suppress all GUI deps cleanly? — build log will show

Document actual findings in LOG.md after the run.

---

## After the smoke test

1. Record in LOG.md: build time, training time, PLY file size, GPU model, cost
2. Update `scripts/run_train.sh` if any flags need correction
3. Open Phase 2: `cloud_burst_lfs` handler in automation_server
   - Mirror `cloud_burst_3dgs.py` pattern
   - Polls STATUS.md via SSH (same contract as this runbook)
   - Dispatch entry in `worker/worker.py`
