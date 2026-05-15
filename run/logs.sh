#!/usr/bin/env bash
# Tail a named log. Called on-demand when status shows failed or done.
# Usage: logs.sh <build|train|validate> [lines]
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-train}"
LINES="${2:-50}"

case "$TARGET" in
    build)    FILE="$REPO_ROOT/logs/build.log" ;;
    validate) FILE="$REPO_ROOT/logs/validate.log" ;;
    train)    FILE="$REPO_ROOT/output/train.log" ;;
    *)        echo "unknown: $TARGET (build|train|validate)" >&2; exit 1 ;;
esac

[[ -f "$FILE" ]] || { echo "not found: $FILE" >&2; exit 1; }
tail -n "$LINES" "$FILE"
