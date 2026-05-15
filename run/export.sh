#!/usr/bin/env bash
# Convert the training PLY artifact to a standalone HTML viewer. Synchronous.
# Usage: export.sh [output_dir]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$REPO_ROOT/output}"
TAG="${LFS_IMAGE:-lichtfeld-cloud-worker:latest}"
STATUS="$REPO_ROOT/STATUS/EXPORT"

mkdir -p "$REPO_ROOT/STATUS"
_write() { printf 'STATE=%s\nNOTE=%s\nUPDATED=%s\n' "$1" "${2:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS"; }

PLY=$(find "$OUTPUT_DIR" -name "*.ply" -not -path "*/\.*" | sort | tail -1)
[[ -z "$PLY" ]] && { _write "failed" "no PLY in $OUTPUT_DIR"; echo "export=failed no PLY" >&2; exit 1; }

VIEWER_DIR="$OUTPUT_DIR/viewer"
mkdir -p "$VIEWER_DIR"

docker run --gpus all --rm \
    -v "$OUTPUT_DIR":/output \
    --entrypoint /opt/lichtfeld/scripts/export_viewer.sh \
    "$TAG" "/output/$(basename "$PLY")" /output/viewer > /dev/null 2>&1

if [[ -s "$VIEWER_DIR/scene.html" ]]; then
    _write "done" "viewer=$VIEWER_DIR/scene.html"
    echo "export=done viewer=$VIEWER_DIR/scene.html"
else
    _write "failed" "scene.html missing or empty"
    echo "export=failed scene.html missing" >&2
    exit 1
fi
