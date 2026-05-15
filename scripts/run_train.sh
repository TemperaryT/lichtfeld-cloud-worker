#!/usr/bin/env bash
# LichtFeld training wrapper. Runs inside the container.
# Writes STATUS.md so Phase 2 automation_server handler can poll it.
set -euo pipefail

LFS_DATA_PATH="${LFS_DATA_PATH:-}"
LFS_OUTPUT_PATH="${LFS_OUTPUT_PATH:-/output}"
LFS_STRATEGY="${LFS_STRATEGY:-mcmc}"
LFS_ITER="${LFS_ITER:-30000}"
LFS_MAX_WIDTH="${LFS_MAX_WIDTH:-2560}"
STATUS_FILE="${LFS_OUTPUT_PATH}/STATUS.md"
LOG_FILE="${LFS_OUTPUT_PATH}/train.log"

write_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    printf 'STATE=%s\nNOTE=%s\nUPDATED=%s\n' "$1" "${2:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE"
}

die() {
    write_status "FAILED" "$1"
    echo "FAILED: $1" >&2
    exit 1
}

trap 'write_status "FAILED" "unexpected error at line $LINENO"; exit 1' ERR

# Validate inputs
[[ -z "$LFS_DATA_PATH" ]] && die "LFS_DATA_PATH not set"
[[ -d "$LFS_DATA_PATH" ]] || die "LFS_DATA_PATH not found: $LFS_DATA_PATH"

frame_count=$(find "$LFS_DATA_PATH" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) | wc -l) || frame_count=0
[[ "$frame_count" -eq 0 ]] && die "no image files in $LFS_DATA_PATH"
echo "found $frame_count frames in $LFS_DATA_PATH"

mkdir -p "$LFS_OUTPUT_PATH"
write_status "TRAINING" "strategy=$LFS_STRATEGY iter=$LFS_ITER frames=$frame_count"

# Windows v0.5.2 confirmed flags: --headless --train --no-interop --data-path --output-path --log-file
# --strategy / --iter / --max-width need validation against Linux --help output.
# If strategy/iter flags differ, update here and document in docs/acceptance_test.md.
lichtfeld-studio \
    --headless \
    --train \
    --no-interop \
    --data-path "$LFS_DATA_PATH" \
    --output-path "$LFS_OUTPUT_PATH" \
    --strategy "$LFS_STRATEGY" \
    --iter "$LFS_ITER" \
    --max-width "$LFS_MAX_WIDTH" \
    --log-file "$LOG_FILE" \
    2>&1 | tee -a "$LOG_FILE"

# Discover PLY — exact output path not yet documented; find dynamically.
# Document actual path during acceptance testing and consider pinning it.
PLY=$(find "$LFS_OUTPUT_PATH" -name "*.ply" -not -path "*/\.*" | sort | tail -1)
if [[ -z "$PLY" ]]; then
    echo "--- last 50 lines of train.log ---"
    tail -50 "$LOG_FILE" || true
    die "no PLY artifact found after training"
fi

write_status "DONE" "ply=$PLY"
echo "artifact: $PLY"
