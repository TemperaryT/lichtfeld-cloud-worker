#!/usr/bin/env bash
# Container entrypoint. All verbose output goes to train.log only.
# Writes /output/STATUS.md at each state transition — the agent polls this.
set -euo pipefail

LFS_DATA_PATH="${LFS_DATA_PATH:-}"
LFS_OUTPUT_PATH="${LFS_OUTPUT_PATH:-/output}"
LFS_STRATEGY="${LFS_STRATEGY:-mcmc}"
LFS_ITER="${LFS_ITER:-30000}"
LFS_MAX_WIDTH="${LFS_MAX_WIDTH:-2560}"
STATUS_FILE="$LFS_OUTPUT_PATH/STATUS.md"
LOG_FILE="$LFS_OUTPUT_PATH/train.log"

write_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    printf 'STATE=%s\nNOTE=%s\nUPDATED=%s\n' "$1" "${2:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE"
}

die() { write_status "FAILED" "$1"; echo "FAILED: $1" >&2; exit 1; }
trap 'write_status "FAILED" "line $LINENO"; exit 1' ERR

[[ -z "$LFS_DATA_PATH" ]] && die "LFS_DATA_PATH not set"
[[ -d "$LFS_DATA_PATH" ]] || die "LFS_DATA_PATH not found: $LFS_DATA_PATH"

frame_count=$(find "$LFS_DATA_PATH" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) | wc -l)
[[ "$frame_count" -eq 0 ]] && die "no image files in $LFS_DATA_PATH"

mkdir -p "$LFS_OUTPUT_PATH"
write_status "TRAINING" "strategy=$LFS_STRATEGY iter=$LFS_ITER frames=$frame_count"

# All output to log file only — no tee, no stdout noise
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
    >> "$LOG_FILE" 2>&1

PLY=$(find "$LFS_OUTPUT_PATH" -name "*.ply" -not -path "*/\.*" | sort | tail -1)
[[ -z "$PLY" ]] && die "no PLY artifact found — check logs/train"

write_status "DONE" "ply=$(basename "$PLY")"
