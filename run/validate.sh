#!/usr/bin/env bash
# Run GPU + LFS validation checks. Synchronous (fast — no training).
# Writes STATUS/VALIDATE. All output goes to logs/validate.log.
# Usage: validate.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${LFS_IMAGE:-lichtfeld-cloud-worker:latest}"
LOG="$REPO_ROOT/logs/validate.log"
STATUS="$REPO_ROOT/STATUS/VALIDATE"

mkdir -p "$REPO_ROOT/logs" "$REPO_ROOT/STATUS"
_write() { printf 'STATE=%s\nNOTE=%s\nUPDATED=%s\n' "$1" "${2:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS"; }
_write "running" ""

{
    docker run --gpus all --rm "$TAG" /opt/lichtfeld/scripts/validate_gpu.sh
    docker run --gpus all --rm "$TAG" /opt/lichtfeld/scripts/validate_lfs.sh
} > "$LOG" 2>&1

RC=$?
if [[ $RC -eq 0 ]]; then
    NOTE=$(grep -E '^(GPU|LFS|flags_missing)=' "$LOG" | tr '\n' ' ' | xargs)
    _write "done" "$NOTE"
    echo "validate=done note=$NOTE"
else
    _write "failed" "see logs/validate.log"
    echo "validate=failed log=logs/validate.log" >&2
    exit 1
fi
