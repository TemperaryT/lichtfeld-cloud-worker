#!/usr/bin/env bash
# Start a Docker image build in the background.
# Returns immediately. Poll with: bash run/status.sh
# Usage: build.sh [tag]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-lichtfeld-cloud-worker:latest}"
LOG="$REPO_ROOT/logs/build.log"
STATUS="$REPO_ROOT/STATUS/BUILD"

mkdir -p "$REPO_ROOT/logs" "$REPO_ROOT/STATUS"

_write() { printf 'STATE=%s\nNOTE=%s\nUPDATED=%s\n' "$1" "${2:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS"; }
_write "building" "tag=$TAG"

nohup bash -c "
    if docker build -t '$TAG' '$REPO_ROOT' >> '$LOG' 2>&1; then
        SIZE=\$(docker image inspect '$TAG' --format='{{.Size}}' 2>/dev/null \
            | awk '{printf \"%.1fGB\", \$1/1073741824}' || echo unknown)
        printf 'STATE=done\nNOTE=tag=$TAG size=%s\nUPDATED=%s\n' \
            \"\$SIZE\" \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" > '$STATUS'
    else
        printf 'STATE=failed\nNOTE=see logs/build.log\nUPDATED=%s\n' \
            \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" > '$STATUS'
    fi
" >> "$LOG" 2>&1 &

echo "build=started pid=$! log=logs/build.log"
echo "poll: bash run/status.sh"
