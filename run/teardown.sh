#!/usr/bin/env bash
# Stop all running lichtfeld containers. Pass --wipe to reset output/STATUS/logs.
# Usage: teardown.sh [--wipe]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${LFS_IMAGE:-lichtfeld-cloud-worker:latest}"

CONTAINERS=$(docker ps -q --filter ancestor="$TAG" 2>/dev/null || true)
if [[ -n "$CONTAINERS" ]]; then
    docker stop $CONTAINERS > /dev/null
    echo "stopped=$(echo "$CONTAINERS" | wc -w) container(s)"
else
    echo "stopped=0"
fi

if [[ "${1:-}" == "--wipe" ]]; then
    find "$REPO_ROOT/output" -mindepth 1 -not -name ".gitkeep" -delete 2>/dev/null || true
    find "$REPO_ROOT/STATUS" -mindepth 1 -not -name ".gitkeep" -delete 2>/dev/null || true
    find "$REPO_ROOT/logs"   -mindepth 1 -not -name ".gitkeep" -delete 2>/dev/null || true
    echo "wiped=output,STATUS,logs"
fi
