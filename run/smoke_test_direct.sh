#!/usr/bin/env bash
# End-to-end LichtFeld smoke test on a rented Vast.ai instance.
# Runs directly on the CUDA devel image — no Docker-in-Docker.
# Run inside a tmux session on agent LXC (~90 min total).
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
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOMATION_ROOT="${AUTOMATION_ROOT:-$HOME/projects/automation_server}"

_ssh() { ssh -p "$VAST_PORT" -o StrictHostKeyChecking=no -o BatchMode=yes "root@$VAST_HOST" "$@"; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
die()  { log "FAILED: $*"; exit 1; }

poll_build() {
    local deadline=$(( $(date +%s) + 2700 ))  # 45 min max
    while [[ $(date +%s) -lt $deadline ]]; do
        local state note
        state=$(_ssh "grep '^STATE=' $WORKSPACE/STATUS/BUILD 2>/dev/null | cut -d= -f2-" || echo "pending")
        note=$(_ssh  "grep '^NOTE='  $WORKSPACE/STATUS/BUILD 2>/dev/null | cut -d= -f2-" || echo "")
        log "build: $state ${note:+($note)}"
        [[ "$state" == "done"   ]] && return 0
        [[ "$state" == "failed" ]] && die "build failed — run: ssh -p $VAST_PORT root@$VAST_HOST 'cat $WORKSPACE/logs/build.log'"
        sleep 60
    done
    die "build timed out after 45 min"
}

log "=== LichtFeld smoke test: $VAST_HOST:$VAST_PORT ==="
log "config: strategy=$LFS_STRATEGY iter=$LFS_ITER max_width=$LFS_MAX_WIDTH max_cap=$LFS_MAX_CAP"
log "frames: target=$PREP_TARGET threshold=$PREP_THRESHOLD"

# ── 1/6: GPU check ────────────────────────────────────────────────────────────
log "--- 1/6: GPU check"
_ssh "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader" \
    || die "GPU not visible — check instance image (requires nvidia/cuda:12.8.0-devel-ubuntu24.04)"

# ── 2/6: Deploy scripts ───────────────────────────────────────────────────────
log "--- 2/6: deploying scripts to $WORKSPACE"
_ssh "mkdir -p $WORKSPACE/run $WORKSPACE/scripts $WORKSPACE/STATUS $WORKSPACE/logs $WORKSPACE/output"

tar -C "$REPO_ROOT" -cf - \
    run/bootstrap_instance.sh \
    scripts/run_train.sh \
    scripts/validate_gpu.sh \
    scripts/validate_lfs.sh \
    | _ssh "tar -C $WORKSPACE -xf -"

scp -P "$VAST_PORT" -o StrictHostKeyChecking=no \
    "$AUTOMATION_ROOT/scripts/prep_frames.py" \
    "root@$VAST_HOST:$WORKSPACE/prep_frames.py"

_ssh "chmod +x $WORKSPACE/run/bootstrap_instance.sh $WORKSPACE/scripts/run_train.sh"

# Install prep_frames deps now (runs in background while video transfers)
_ssh "pip3 install opencv-python-headless pillow numpy -q \
    > $WORKSPACE/logs/pip.log 2>&1 &"
log "scripts deployed; pip install running in background"

# ── 3/6: Transfer video ───────────────────────────────────────────────────────
log "--- 3/6: transferring video via $VIDEO_RELAY relay"
log "source: $VIDEO_RELAY:$VIDEO_SOURCE"
ssh "$VIDEO_RELAY" "cat \"$VIDEO_SOURCE\"" \
    | _ssh "cat > $WORKSPACE/robot_arm.mp4"
VIDEO_SIZE=$( _ssh "du -sh $WORKSPACE/robot_arm.mp4" | cut -f1 )
log "video: $WORKSPACE/robot_arm.mp4  ($VIDEO_SIZE)"

# ── 4/6: Build LichtFeld in tmux (poll until done) ────────────────────────────
log "--- 4/6: building LichtFeld v0.5.2 from source"
log "starting build in tmux session 'lfs_build' on instance — polling every 60s"
_ssh "tmux new-session -d -s lfs_build \
    'bash $WORKSPACE/run/bootstrap_instance.sh; tmux wait-for -S build_done'" || true
# tmux may not have wait-for in older versions; just poll STATUS/BUILD
poll_build
log "build: done"

# ── 5/6: Extract and prep frames ──────────────────────────────────────────────
log "--- 5/6: extracting frames at 3fps (scale to 1920px)"
_ssh "mkdir -p $WORKSPACE/frames_raw"
_ssh "ffmpeg -y -i $WORKSPACE/robot_arm.mp4 \
    -vf 'fps=3,scale=1920:-1' -q:v 2 \
    '$WORKSPACE/frames_raw/frame_%05d.jpg' \
    >> $WORKSPACE/logs/ffmpeg.log 2>&1"
FRAME_COUNT=$( _ssh "ls $WORKSPACE/frames_raw/*.jpg | wc -l" )
log "extracted: $FRAME_COUNT raw frames"

# Wait for pip install if still running
_ssh "pip3 show opencv-python-headless > /dev/null 2>&1 \
    || pip3 install opencv-python-headless pillow numpy -q"

log "filtering: threshold=$PREP_THRESHOLD → target=$PREP_TARGET frames"
_ssh "python3 $WORKSPACE/prep_frames.py \
    --frames $WORKSPACE/frames_raw \
    --output $WORKSPACE/prepped \
    --threshold $PREP_THRESHOLD --target $PREP_TARGET --no-sheet \
    > $WORKSPACE/logs/prep.log 2>&1"
PREPPED_COUNT=$( _ssh "ls $WORKSPACE/prepped/frames/*.jpg 2>/dev/null | wc -l" )
log "prepped: $PREPPED_COUNT frames → $WORKSPACE/prepped/frames"
[[ "$PREPPED_COUNT" -gt 0 ]] || die "no prepped frames — check $WORKSPACE/logs/prep.log"

# ── 6/6: Launch training (detached) ───────────────────────────────────────────
log "--- 6/6: launching training in tmux 'lfs_train' (detached)"
_ssh "tmux new-session -d -s lfs_train \
    'env LFS_DATA_PATH=$WORKSPACE/prepped/frames \
         LFS_OUTPUT_PATH=$WORKSPACE/output \
         LFS_STRATEGY=$LFS_STRATEGY \
         LFS_ITER=$LFS_ITER \
         LFS_MAX_WIDTH=$LFS_MAX_WIDTH \
         LFS_MAX_CAP=$LFS_MAX_CAP \
     bash $WORKSPACE/scripts/run_train.sh'"
sleep 3

TRAIN_STATE=$( _ssh "grep '^STATE=' $WORKSPACE/output/STATUS.md 2>/dev/null | cut -d= -f2-" || echo "pending" )
log "train state: $TRAIN_STATE"

log ""
log "=== smoke test running ==="
log ""
log "poll:     bash run/status_direct.sh $VAST_HOST $VAST_PORT"
log "logs:     ssh -p $VAST_PORT root@$VAST_HOST 'tail -f $WORKSPACE/output/train.log'"
log "download: rsync -avz -e 'ssh -p $VAST_PORT' root@$VAST_HOST:$WORKSPACE/output/ ./output/"
log "destroy:  python3 ~/projects/automation_server/scripts/vast_burst.py destroy <INSTANCE_ID> --yes"
log ""
log "Training target: $LFS_ITER iterations, ~30-60 min depending on GPU."
log "Poll status_direct.sh every few minutes. When train=DONE, download output."
