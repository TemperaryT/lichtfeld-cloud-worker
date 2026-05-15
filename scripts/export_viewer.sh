#!/usr/bin/env bash
# Usage: export_viewer.sh <input.ply> <output_dir>
# Produces: <output_dir>/scene.html (standalone viewer)
set -euo pipefail

[[ $# -lt 2 ]] && { echo "usage: export_viewer.sh <input.ply> <output_dir>"; exit 1; }
INPUT="$1"
OUTPUT_DIR="$2"

[[ -f "$INPUT" ]] || { echo "input not found: $INPUT"; exit 1; }
mkdir -p "$OUTPUT_DIR"

lichtfeld-studio convert "$INPUT" "$OUTPUT_DIR/scene.html"

SIZE=$(stat -c%s "$OUTPUT_DIR/scene.html" 2>/dev/null || echo 0)
[[ "$SIZE" -eq 0 ]] && { echo "export produced empty file"; exit 1; }
echo "viewer: $OUTPUT_DIR/scene.html (${SIZE} bytes)"
