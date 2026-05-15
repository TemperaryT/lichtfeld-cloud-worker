#!/usr/bin/env bash
# Print compact state of all components. One key=value line.
# Called by the agent to poll the full run state in a single SSH call.
# Usage: status.sh
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_state() { [[ -f "$1" ]] && grep '^STATE=' "$1" | cut -d= -f2- || echo "pending"; }
_note()  { [[ -f "$1" ]] && grep '^NOTE='  "$1" | cut -d= -f2- || echo ""; }

BUILD=$(_state    "$REPO_ROOT/STATUS/BUILD")
VALIDATE=$(_state "$REPO_ROOT/STATUS/VALIDATE")
TRAIN=$(_state    "$REPO_ROOT/output/STATUS.md")
EXPORT=$(_state   "$REPO_ROOT/STATUS/EXPORT")

# If container has exited but STATUS.md still says TRAINING, flag it
if [[ "$TRAIN" == "TRAINING" ]]; then
    CID=$(cat "$REPO_ROOT/STATUS/CONTAINER_ID" 2>/dev/null || echo "")
    if [[ -n "$CID" ]]; then
        RUNNING=$(docker inspect -f '{{.State.Running}}' "$CID" 2>/dev/null || echo "false")
        [[ "$RUNNING" == "false" ]] && TRAIN="crashed"
    fi
fi

printf 'build=%s validate=%s train=%s export=%s\n' "$BUILD" "$VALIDATE" "$TRAIN" "$EXPORT"

# Print note line only when there's content (ply path, error, GPU info, etc.)
TRAIN_NOTE=$(_note "$REPO_ROOT/output/STATUS.md")
[[ -n "$TRAIN_NOTE" ]] && echo "note: $TRAIN_NOTE"
