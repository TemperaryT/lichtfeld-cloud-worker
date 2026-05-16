#!/usr/bin/env bash
# Single SSH round-trip poll of a direct-on-Vast LichtFeld run.
# Returns one compact line: build=<state> train=<state> note=<...>
# Usage: bash run/status_direct.sh <ssh_host> <ssh_port>
#
# STATUS/BUILD is only present when bootstrap_instance.sh ran (fallback path).
# With the pre-built image, build=done is implicit and the file may be absent —
# the script reports build=preinstalled in that case.
set -euo pipefail

VAST_HOST="${1:?usage: status_direct.sh <ssh_host> <ssh_port>}"
VAST_PORT="${2:?usage: status_direct.sh <ssh_host> <ssh_port>}"
WORKSPACE="/workspace/lichtfeld"

# One remote shell, three file reads, single line out.
ssh -p "$VAST_PORT" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "root@$VAST_HOST" \
    "WORKSPACE=$WORKSPACE bash -s" <<'REMOTE'
_state() {
    if [[ -f "$1" ]]; then
        grep '^STATE=' "$1" | head -1 | cut -d= -f2-
    else
        echo "$2"
    fi
}
_note() {
    [[ -f "$1" ]] && grep '^NOTE=' "$1" | head -1 | cut -d= -f2- || true
}
BUILD=$(_state "$WORKSPACE/STATUS/BUILD" "preinstalled")
TRAIN=$(_state "$WORKSPACE/output/STATUS.md" "pending")
NOTE=$(_note  "$WORKSPACE/output/STATUS.md")
printf 'build=%s train=%s note=%s\n' "$BUILD" "$TRAIN" "$NOTE"
REMOTE
