#!/usr/bin/env bash
# Start a training run as a detached Docker container.
# Returns immediately. Poll STATUS.md with: bash run/status.sh
# Usage: train.sh <frames_dir> <output_dir>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMES_DIR="${1:-$REPO_ROOT/data}"
OUTPUT_DIR="${2:-$REPO_ROOT/output}"
TAG="${LFS_IMAGE:-lichtfeld-cloud-worker:latest}"

[[ -d "$FRAMES_DIR" ]] || { echo "frames_dir not found: $FRAMES_DIR" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR" "$REPO_ROOT/STATUS"

# Clear state from any previous run
rm -f "$OUTPUT_DIR/STATUS.md" "$REPO_ROOT/STATUS/EXPORT"

CID=$(docker run -d --gpus all \
    -v "$FRAMES_DIR":/data:ro \
    -v "$OUTPUT_DIR":/output \
    -e LFS_DATA_PATH=/data \
    -e LFS_OUTPUT_PATH=/output \
    -e LFS_STRATEGY="${LFS_STRATEGY:-mcmc}" \
    -e LFS_ITER="${LFS_ITER:-30000}" \
    -e LFS_MAX_WIDTH="${LFS_MAX_WIDTH:-2560}" \
    "$TAG")

echo "$CID" > "$REPO_ROOT/STATUS/CONTAINER_ID"
echo "train=started container=$CID"
echo "poll: bash run/status.sh"
