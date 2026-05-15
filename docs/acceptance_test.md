# LichtFeld Cloud Worker — Acceptance Test

Run these steps on a Vast.ai GPU instance (CUDA 12.8+, RTX 30/40 series).
Steps 1–3 can be run locally (no GPU needed for build syntax check).
Steps 4–9 require a live GPU instance.

---

## Prerequisites

```bash
git clone <this-repo> && cd lichtfeld-cloud-worker
# Have a prepped frames directory available (COLMAP-ready images, min 40 frames)
FRAMES_DIR=/path/to/prepped/frames
OUTPUT_DIR=/path/to/output
```

---

## Step 1 — Container builds from clean base

```bash
docker build -t lichtfeld-cloud-worker . --progress=plain
```

**Pass criteria:** exits 0, binary present in image.

**Known unknowns to resolve here:**
- Whether `-DLFS_ENFORCE_LINUX_GUI_BACKENDS=OFF` is accepted by CMake
- Whether vcpkg dependencies resolve cleanly
- Build time (expected 15–30 min; document for runbook)

---

## Step 2 — GPU visible inside container

```bash
docker run --gpus all --rm \
  --entrypoint /opt/lichtfeld/scripts/validate_gpu.sh \
  lichtfeld-cloud-worker
```

**Pass criteria:** `nvidia-smi` shows GPU, CUDA runtime loads, exits 0.

---

## Step 3 — LichtFeld binary launches

```bash
docker run --gpus all --rm \
  --entrypoint /opt/lichtfeld/scripts/validate_lfs.sh \
  lichtfeld-cloud-worker
```

**Pass criteria:** binary launches, help/version output visible, expected flags found.

**If flags are missing:** Update `run_train.sh` to match actual flag names and document
the difference from the Windows v0.5.2 baseline here.

---

## Step 4 — Headless training smoke run (100 iterations)

```bash
mkdir -p "$OUTPUT_DIR"
docker run --gpus all --rm \
  -v "$FRAMES_DIR":/data:ro \
  -v "$OUTPUT_DIR":/output \
  -e LFS_DATA_PATH=/data \
  -e LFS_OUTPUT_PATH=/output \
  -e LFS_STRATEGY=mcmc \
  -e LFS_ITER=100 \
  lichtfeld-cloud-worker
```

**Pass criteria:**
- Container exits 0
- `$OUTPUT_DIR/STATUS.md` contains `STATE=DONE`
- `$OUTPUT_DIR/train.log` exists and is non-empty
- A `.ply` file exists somewhere under `$OUTPUT_DIR`

**Document here:** actual PLY artifact path for Phase 2 handler.

---

## Step 5 — Export viewer

```bash
PLY=$(find "$OUTPUT_DIR" -name "*.ply" | tail -1)
docker run --gpus all --rm \
  -v "$OUTPUT_DIR":/output \
  --entrypoint /opt/lichtfeld/scripts/export_viewer.sh \
  lichtfeld-cloud-worker /output/$(basename "$PLY") /output/viewer
```

**Pass criteria:** `$OUTPUT_DIR/viewer/scene.html` exists, size > 0.

---

## Step 6 — Viewer serves over HTTP

```bash
docker run --rm \
  -v "$OUTPUT_DIR/viewer":/viewer \
  -p 8080:8080 \
  --entrypoint /opt/lichtfeld/scripts/serve_viewer.sh \
  lichtfeld-cloud-worker /viewer 8080 &

curl -sI http://localhost:8080/scene.html | head -5
```

**Pass criteria:** HTTP 200, Content-Type text/html.

---

## Step 7 — SSH tunnel access

On the cloud instance:
```bash
# serve_viewer.sh running on :8080
```

On the local machine:
```bash
ssh -L 8080:localhost:8080 <user>@<instance-ip>
# Open http://localhost:8080/scene.html in browser
```

**Pass criteria:** scene loads in browser, 3DGS splat is visible and navigable.

---

## Step 8 — Reproducibility on second instance

Push image to GHCR after step 4 passes:
```bash
docker tag lichtfeld-cloud-worker ghcr.io/<github-username>/lichtfeld-cloud-worker:latest
docker push ghcr.io/<github-username>/lichtfeld-cloud-worker:latest
```

On a fresh Vast.ai instance:
```bash
docker pull ghcr.io/<github-username>/lichtfeld-cloud-worker:latest
# repeat step 4 with pulled image
```

**Pass criteria:** same output, no build required on second instance.

---

## Step 9 — Failure path

```bash
docker run --gpus all --rm \
  -v "$OUTPUT_DIR":/output \
  -e LFS_DATA_PATH=/nonexistent \
  -e LFS_OUTPUT_PATH=/output \
  lichtfeld-cloud-worker
```

**Pass criteria:**
- Container exits nonzero
- `$OUTPUT_DIR/STATUS.md` contains `STATE=FAILED`
- Error message is human-readable

---

## Results log

| Step | Date | Instance | Result | Notes |
|---|---|---|---|---|
| 1 Build | | | | |
| 2 GPU | | | | |
| 3 LFS binary | | | | |
| 4 Smoke train | | | | actual PLY path: |
| 5 Export | | | | |
| 6 HTTP viewer | | | | |
| 7 SSH tunnel | | | | |
| 8 Second instance | | | | |
| 9 Failure path | | | | |
