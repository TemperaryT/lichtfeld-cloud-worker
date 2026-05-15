#!/usr/bin/env bash
# Usage: serve_viewer.sh <viewer_dir> [port]
set -euo pipefail
[[ $# -lt 1 ]] && { echo "usage: serve_viewer.sh <viewer_dir> [port]" >&2; exit 1; }
[[ -d "$1" ]] || { echo "not found: $1" >&2; exit 1; }
PORT="${2:-8080}"
echo "tunnel: ssh -L ${PORT}:localhost:${PORT} <user>@<host>"
echo "url: http://localhost:${PORT}/scene.html"
cd "$1" && exec python3 -m http.server "$PORT" > /dev/null 2>&1
