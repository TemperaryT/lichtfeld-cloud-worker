#!/usr/bin/env bash
# Usage: export_viewer.sh <input.ply> <output_dir>
set -euo pipefail
[[ $# -lt 2 ]] && { echo "usage: export_viewer.sh <input.ply> <output_dir>" >&2; exit 1; }
[[ -f "$1" ]] || { echo "not found: $1" >&2; exit 1; }
mkdir -p "$2"
lichtfeld-studio convert "$1" "$2/scene.html" > /dev/null 2>&1
[[ -s "$2/scene.html" ]] || { echo "export produced empty file" >&2; exit 1; }
echo "viewer=$2/scene.html"
