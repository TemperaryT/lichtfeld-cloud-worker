# lichtfeld-cloud-worker

Containerized LichtFeld Studio for headless Gaussian Splatting on rented GPU compute.
Agent-driven: scripts run detached, agent polls `status.sh`, reads logs only on failure.

**Phase 1:** standalone container — build, validate, run.
**Phase 2:** `cloud_burst_lfs` job type in `automation_server` (see `jobs/example.yaml`).

---

## Script layers

```
run/          ← host-side; what the agent calls
  build.sh      start docker build (background)
  validate.sh   GPU + LFS binary checks
  train.sh      start training run (detached container)
  status.sh     poll all state in one call
  export.sh     convert PLY → HTML viewer
  serve.sh      start viewer HTTP server (detached)
  logs.sh       tail a named log on-demand
  teardown.sh   stop containers; --wipe resets all state

scripts/      ← container-internal; copied into image by Dockerfile
  run_train.sh    training entrypoint; writes STATUS.md
  validate_gpu.sh GPU check
  validate_lfs.sh LFS binary + flag check
  export_viewer.sh PLY → HTML
  serve_viewer.sh HTTP server
```

---

## Agent workflow

```bash
# 1. Build (background, ~15-30 min first time)
bash run/build.sh

# 2. Poll until done
bash run/status.sh
# → build=building validate=pending train=pending export=pending

# 3. Validate
bash run/validate.sh
bash run/status.sh
# → build=done validate=done train=pending export=pending
# → note: GPU=NVIDIA GeForce RTX 4090, 24564 MiB LFS=v0.5.2

# 4. Train (detached, 30k iter ~20-60 min depending on GPU)
bash run/train.sh /path/to/frames /path/to/output
bash run/status.sh  # poll every 60s
# → build=done validate=done train=TRAINING export=pending
# → note: strategy=mcmc iter=30000 frames=40
# → build=done validate=done train=DONE export=pending
# → note: ply=final.ply

# 5. Export viewer
bash run/export.sh /path/to/output
bash run/status.sh
# → build=done validate=done train=DONE export=done
# → note: viewer=/path/to/output/viewer/scene.html

# 6. Serve (detached)
bash run/serve.sh /path/to/output 8080
# → serve=started tunnel: ssh -L 8080:localhost:8080 ...

# On failure — read logs
bash run/logs.sh train    # last 50 lines of train.log
bash run/logs.sh build    # last 50 lines of build.log

# Reset for re-run
bash run/teardown.sh --wipe
```

---

## Environment variables (for train.sh)

| Variable | Default | Description |
|---|---|---|
| `LFS_IMAGE` | `lichtfeld-cloud-worker:latest` | Docker image tag |
| `LFS_STRATEGY` | `mcmc` | Training strategy: `mcmc`, `adc`, `igs+` |
| `LFS_ITER` | `30000` | Training iterations |
| `LFS_MAX_WIDTH` | `2560` | Max image width |

---

## STATUS.md states

`run_train.sh` inside the container writes `/output/STATUS.md`:

```
TRAINING → DONE
       └→ FAILED
```

`run/status.sh` reads this plus `STATUS/BUILD`, `STATUS/VALIDATE`, `STATUS/EXPORT`
and prints one compact line.

---

## Known unknowns (resolve during acceptance testing)

- `--strategy` / `--iter` / `--max-width` flag names validated on Windows v0.5.2;
  verify against `lichtfeld-studio --help` in the Linux container
- Exact PLY artifact path (discovered dynamically)
- Whether vcpkg runtime libs need additional `COPY` in Dockerfile stage 2

See `docs/acceptance_test.md` for the full validation checklist.

---

## Phase 2 hook

`automation_server` gets:
- `cloud/vast/profiles/lichtfeld.json` — Vast profile with this image
- `worker/handlers/cloud_burst_lfs.py` — polls STATUS.md via SSH, same as `cloud_burst_3dgs`
- Dispatch entry in `worker/worker.py`
- `cloud_burst_lfs` section in `docs/pipelines.md`
