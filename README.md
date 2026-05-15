# lichtfeld-cloud-worker

Containerized LichtFeld Studio for headless Gaussian Splatting on rented GPU compute
(Vast.ai). Trains on a prepped frames directory, produces a PLY artifact and exportable
HTML viewer.

**Phase 1:** standalone container — build, validate, run manually.
**Phase 2:** wired into `automation_server` as a `cloud_burst_lfs` queue job (see `jobs/example.yaml`).

---

## Requirements

- Docker with NVIDIA Container Toolkit
- NVIDIA GPU, CUDA 12.8+, RTX 20/30/40 series (SM 75+)
- Prepped frames directory (COLMAP-ready images, min ~40 frames)

---

## Quick start

```bash
# Build (15–30 min first time — C++23 + CUDA from source)
docker build -t lichtfeld-cloud-worker .

# Validate GPU
docker run --gpus all --rm \
  --entrypoint /opt/lichtfeld/scripts/validate_gpu.sh \
  lichtfeld-cloud-worker

# Validate LichtFeld binary
docker run --gpus all --rm \
  --entrypoint /opt/lichtfeld/scripts/validate_lfs.sh \
  lichtfeld-cloud-worker

# Train
docker run --gpus all --rm \
  -v /path/to/frames:/data:ro \
  -v /path/to/output:/output \
  -e LFS_DATA_PATH=/data \
  -e LFS_OUTPUT_PATH=/output \
  lichtfeld-cloud-worker
```

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `LFS_DATA_PATH` | (required) | Path to prepped frames directory inside container |
| `LFS_OUTPUT_PATH` | `/output` | Output directory inside container |
| `LFS_STRATEGY` | `mcmc` | Training strategy: `mcmc`, `adc`, `igs+` |
| `LFS_ITER` | `30000` | Training iterations |
| `LFS_MAX_WIDTH` | `2560` | Max image width (images scaled down if wider) |

---

## Viewer workflow

After training completes, export and serve the HTML viewer:

```bash
# Export PLY → HTML viewer
PLY=$(find /path/to/output -name "*.ply" | tail -1)
docker run --rm \
  -v /path/to/output:/output \
  --entrypoint /opt/lichtfeld/scripts/export_viewer.sh \
  lichtfeld-cloud-worker "$PLY" /output/viewer

# Serve viewer
docker run --rm \
  -v /path/to/output/viewer:/viewer \
  -p 8080:8080 \
  --entrypoint /opt/lichtfeld/scripts/serve_viewer.sh \
  lichtfeld-cloud-worker /viewer

# SSH tunnel from local machine
ssh -L 8080:localhost:8080 <user>@<instance-ip>
# Open http://localhost:8080/scene.html
```

---

## STATUS.md state machine

`run_train.sh` writes `/output/STATUS.md` at each stage. Phase 2 automation handler polls
this file via SSH (same pattern as `nerfstudio_frames_runner.sh` in `cloud_burst_3dgs`).

```
STATE=TRAINING   → training in progress
STATE=DONE       → PLY artifact ready (NOTE contains ply=<path>)
STATE=FAILED     → error (NOTE contains reason)
```

---

## Image registry (after first successful build)

```bash
docker tag lichtfeld-cloud-worker ghcr.io/<github-username>/lichtfeld-cloud-worker:latest
docker push ghcr.io/<github-username>/lichtfeld-cloud-worker:latest
```

Subsequent Vast instances pull the pre-built image instead of rebuilding (~2 min vs 30 min).

---

## Validation

See `docs/acceptance_test.md` for the full 9-step validation checklist.

---

## Known unknowns (resolve during first build)

- `--strategy` / `--iter` / `--max-width` flag names confirmed on Windows v0.5.2;
  validate against `lichtfeld-studio --help` in the Linux container
- Exact PLY artifact path after training (discovered dynamically by `run_train.sh`)
- Whether vcpkg runtime libs need additional `COPY` in Dockerfile stage 2
  (check: `docker run --entrypoint ldd lichtfeld-cloud-worker /usr/local/bin/lichtfeld-studio`)

---

## Phase 2 integration

When this container is proven, `automation_server` gets:
- `cloud/vast/profiles/lichtfeld.json` — Vast instance profile pointing to this image
- `worker/handlers/cloud_burst_lfs.py` — mirrors `cloud_burst_3dgs.py`; polls STATUS.md
- Dispatch entry in `worker/worker.py`
- `cloud_burst_lfs` section in `docs/pipelines.md`
