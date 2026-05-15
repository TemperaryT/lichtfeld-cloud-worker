#!/usr/bin/env bash
# Usage: serve_viewer.sh <viewer_dir> [port]
set -euo pipefail

[[ $# -lt 1 ]] && { echo "usage: serve_viewer.sh <viewer_dir> [port]"; exit 1; }
VIEWER_DIR="$1"
PORT="${2:-8080}"

[[ -d "$VIEWER_DIR" ]] || { echo "directory not found: $VIEWER_DIR"; exit 1; }

echo "serving: $VIEWER_DIR on :$PORT"
echo "SSH tunnel: ssh -L ${PORT}:localhost:${PORT} <user>@<instance-ip>"
echo "browser:   http://localhost:${PORT}/scene.html"
echo ""
cd "$VIEWER_DIR" && python3 -m http.server "$PORT"
