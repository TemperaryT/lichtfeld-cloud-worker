#!/usr/bin/env bash
# Poll status of a direct-on-Vast LichtFeld run (no Docker).
# Usage: bash run/status_direct.sh <ssh_host> <ssh_port>
VAST_HOST="${1:?usage: status_direct.sh <ssh_host> <ssh_port>}"
VAST_PORT="${2:?usage: status_direct.sh <ssh_host> <ssh_port>}"
WORKSPACE="/workspace/lichtfeld"

_ssh() { ssh -p "$VAST_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$VAST_HOST" "$@" 2>/dev/null; }

BUILD=$( _ssh "grep '^STATE=' $WORKSPACE/STATUS/BUILD 2>/dev/null | cut -d= -f2-"        || echo "pending" )
TRAIN=$( _ssh "grep '^STATE=' $WORKSPACE/output/STATUS.md 2>/dev/null | cut -d= -f2-"    || echo "pending" )
NOTE=$(  _ssh "grep '^NOTE='  $WORKSPACE/output/STATUS.md 2>/dev/null | cut -d= -f2-"    || echo "" )

printf 'build=%s train=%s\n' "$BUILD" "$TRAIN"
[[ -n "$NOTE" ]] && echo "note: $NOTE"
