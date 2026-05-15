#!/usr/bin/env bash
# Start the HTML viewer server as a detached container. Returns immediately.
# Usage: serve.sh [output_dir] [port]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$REPO_ROOT/output}"
PORT="${2:-8080}"
TAG="${LFS_IMAGE:-lichtfeld-cloud-worker:latest}"
VIEWER_DIR="$OUTPUT_DIR/viewer"

[[ -f "$VIEWER_DIR/scene.html" ]] || { echo "viewer not ready: $VIEWER_DIR/scene.html" >&2; exit 1; }

CID=$(docker run -d \
    -v "$VIEWER_DIR":/viewer:ro \
    -p "$PORT:$PORT" \
    --entrypoint /opt/lichtfeld/scripts/serve_viewer.sh \
    "$TAG" /viewer "$PORT")

echo "serve=started container=$CID port=$PORT"
echo "tunnel: ssh -L ${PORT}:localhost:${PORT} <user>@<host>"
echo "url: http://localhost:${PORT}/scene.html"
