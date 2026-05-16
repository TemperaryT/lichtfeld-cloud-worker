#!/usr/bin/env bash
# End-to-end LichtFeld smoke test on a rented Vast.ai instance.
# Assumes the instance was created with a pre-built lichtfeld-cloud-worker image
# (e.g. ghcr.io/temperaryt/lichtfeld-cloud-worker:v0.5.2). LichtFeld, ffmpeg,
# and prep_frames.py deps are already installed.
#
# Run inside a tmux session on agent LXC. Stages 1–5 are foreground (~5 min).
# Training is launched detached on the instance (~30–60 min) — poll separately
# via run/monitor.sh.
#
# Usage: bash run/smoke_test_direct.sh <ssh_host> <ssh_port>
#
# Env overrides (all optional):
#   VIDEO_SOURCE    path to video on VIDEO_RELAY host
#                   default: /mnt/automation_data/inbox/robot_arm.mp4
#   VIDEO_RELAY     SSH host alias that can read VIDEO_SOURCE
#                   default: mjolnir
#   LFS_ITER        training iterations           (default: 30000)
#   LFS_MAX_WIDTH   max image width               (default: 1920)
#   LFS_STRATEGY    training strategy             (default: mcmc)
#   LFS_MAX_CAP     max splat count               (default: 3000000)
#   PREP_TARGET     target frame count            (default: 400)
#   PREP_THRESHOLD  Laplacian blur threshold      (default: 80)
set -euo pipefail

VAST_HOST="${1:?usage: smoke_test_direct.sh <ssh_host> <ssh_port>}"
VAST_PORT="${2:?usage: smoke_test_direct.sh <ssh_host> <ssh_port>}"
VIDEO_SOURCE="${VIDEO_SOURCE:-/mnt/automation_data/inbox/robot_arm.mp4}"
VIDEO_RELAY="${VIDEO_RELAY:-mjolnir}"
LFS_ITER="${LFS_ITER:-30000}"
LFS_MAX_WIDTH="${LFS_MAX_WIDTH:-1920}"
LFS_STRATEGY="${LFS_STRATEGY:-mcmc}"
LFS_MAX_CAP="${LFS_MAX_CAP:-3000000}"
PREP_TARGET="${PREP_TARGET:-400}"
PREP_THRESHOLD="${PREP_THRESHOLD:-80}"

WORKSPACE="/workspace/lichtfeld"
AUTOMATION_ROOT="${AUTOMATION_ROOT:-$HOME/projects/automation_server}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_ssh() { ssh -p "$VAST_PORT" -o StrictHostKeyChecking=no -o BatchMode=yes "root@$VAST_HOST" "$@"; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
die()  { log "FAILED: $*"; exit 1; }

log "=== LichtFeld smoke test: $VAST_HOST:$VAST_PORT ==="
log "config: strategy=$LFS_STRATEGY iter=$LFS_ITER max_width=$LFS_MAX_WIDTH max_cap=$LFS_MAX_CAP"
log "frames: target=$PREP_TARGET threshold=$PREP_THRESHOLD"

# ── 1/5: pre-flight (GPU + LichtFeld + deps already in image) ─────────────────
log "--- 1/5: pre-flight (GPU + pre-built image checks)"
_ssh "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader" \
    || die "GPU not visible — wrong instance image?"
LFS_VERSION=$( _ssh "lichtfeld-studio --version 2>&1 | head -1 || echo missing" )
[[ "$LFS_VERSION" == "missing" ]] && die "lichtfeld-studio binary not found — instance not using pre-built image"
log "lichtfeld-studio: $LFS_VERSION"
_ssh "which ffmpeg >/dev/null && python3 -c 'import cv2, PIL, numpy' 2>/dev/null" \
    || die "ffmpeg / python deps missing — wrong image tag?"
log "ffmpeg + cv2/PIL/numpy: ok"

# ── 2/5: workspace + prep_frames.py ───────────────────────────────────────────
log "--- 2/5: prepare workspace; deploy prep_frames.py"
_ssh "mkdir -p $WORKSPACE/output $WORKSPACE/frames_raw $WORKSPACE/prepped $WORKSPACE/logs"
scp -P "$VAST_PORT" -o StrictHostKeyChecking=no -q \
    "$AUTOMATION_ROOT/scripts/prep_frames.py" \
    "root@$VAST_HOST:$WORKSPACE/prep_frames.py"
log "prep_frames.py: deployed"

# ── 3/5: transfer video via Mjolnir relay ─────────────────────────────────────
log "--- 3/5: transferring video via $VIDEO_RELAY relay"
log "source: $VIDEO_RELAY:$VIDEO_SOURCE"
ssh "$VIDEO_RELAY" "cat \"$VIDEO_SOURCE\"" \
    | _ssh "cat > $WORKSPACE/robot_arm.mp4"
VIDEO_SIZE=$( _ssh "du -sh $WORKSPACE/robot_arm.mp4" | cut -f1 )
log "video: $WORKSPACE/robot_arm.mp4  ($VIDEO_SIZE)"

# ── 4/5: extract + prep frames ────────────────────────────────────────────────
log "--- 4/5: extracting frames at 3fps (scale to 1920px)"
_ssh "ffmpeg -y -loglevel warning -i $WORKSPACE/robot_arm.mp4 \
    -vf 'fps=3,scale=1920:-1' -q:v 2 \
    '$WORKSPACE/frames_raw/frame_%05d.jpg' \
    >> $WORKSPACE/logs/ffmpeg.log 2>&1"
FRAME_COUNT=$( _ssh "ls $WORKSPACE/frames_raw/*.jpg | wc -l" )
log "extracted: $FRAME_COUNT raw frames"

log "filtering: threshold=$PREP_THRESHOLD → target=$PREP_TARGET frames"
_ssh "python3 $WORKSPACE/prep_frames.py \
    --frames $WORKSPACE/frames_raw \
    --output $WORKSPACE/prepped \
    --threshold $PREP_THRESHOLD --target $PREP_TARGET --no-sheet \
    > $WORKSPACE/logs/prep.log 2>&1"
PREPPED_COUNT=$( _ssh "ls $WORKSPACE/prepped/frames/*.jpg 2>/dev/null | wc -l" )
log "prepped: $PREPPED_COUNT frames"
[[ "$PREPPED_COUNT" -gt 0 ]] || die "no prepped frames — check $WORKSPACE/logs/prep.log"

# ── 5/5: launch training in tmux on the instance ──────────────────────────────
log "--- 5/5: launching training in tmux 'lfs_train' (detached)"
_ssh "tmux new-session -d -s lfs_train \
    'env LFS_DATA_PATH=$WORKSPACE/prepped/frames \
         LFS_OUTPUT_PATH=$WORKSPACE/output \
         LFS_STRATEGY=$LFS_STRATEGY \
         LFS_ITER=$LFS_ITER \
         LFS_MAX_WIDTH=$LFS_MAX_WIDTH \
         LFS_MAX_CAP=$LFS_MAX_CAP \
     bash /opt/lichtfeld/scripts/run_train.sh'"
sleep 3

TRAIN_STATE=$( _ssh "grep '^STATE=' $WORKSPACE/output/STATUS.md 2>/dev/null | cut -d= -f2-" || echo "pending" )
log "train state: $TRAIN_STATE"

log ""
log "=== smoke test running ==="
log ""
log "Recommended: start the monitor in its own tmux window/pane:"
log "  tmux new-session -d -s lfs_monitor -- bash $REPO_ROOT/run/monitor.sh $VAST_HOST $VAST_PORT"
log "  tail -f $REPO_ROOT/logs/monitor-$VAST_HOST.log"
log ""
log "Manual one-shot poll:"
log "  bash $REPO_ROOT/run/status_direct.sh $VAST_HOST $VAST_PORT"
log ""
log "Download on completion:"
log "  rsync -avz -e 'ssh -p $VAST_PORT' root@$VAST_HOST:$WORKSPACE/output/ ./output/"
log ""
log "Destroy when done:"
log "  python3 $AUTOMATION_ROOT/scripts/vast_burst.py destroy <INSTANCE_ID> --yes"
