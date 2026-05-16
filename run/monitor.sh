#!/usr/bin/env bash
# Unattended polling loop for a LichtFeld smoke test on Vast.
# Fills the polling gap left by smoke_test_direct.sh exiting after launching training.
#
# Run inside tmux on agent LXC. Writes one log line per STATE TRANSITION
# (not per poll) so the log is a compact timeline of the run.
#
# Usage:
#   tmux new-session -s lfs_monitor -d "bash run/monitor.sh <ssh_host> <ssh_port>"
#   tail -f logs/monitor-<ssh_host>.log
#
# Exit codes:
#   0  train reached DONE
#   1  train reached FAILED or crashed, or >3 consecutive SSH failures
#   2  usage / missing args
set -euo pipefail

VAST_HOST="${1:?usage: monitor.sh <ssh_host> <ssh_port> [interval_sec=60]}"
VAST_PORT="${2:?usage: monitor.sh <ssh_host> <ssh_port> [interval_sec=60]}"
INTERVAL="${3:-60}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/monitor-${VAST_HOST}.log"
STATUS_SCRIPT="$REPO_ROOT/run/status_direct.sh"

mkdir -p "$LOG_DIR"

_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_log() { printf '[%s] %s\n' "$(_now)" "$*" | tee -a "$LOG_FILE"; }
# TODO: when Discord webhook is provisioned, add `_notify "$*"` to _log

# Optional notification hook (no-op until Discord webhook is provisioned).
# Wire ~/projects/automation_server/bin/notify.sh here when available.
_notify() { :; }

last_state=""
ssh_failures=0
final_exit=0

_log "monitor started: host=$VAST_HOST port=$VAST_PORT interval=${INTERVAL}s"

while true; do
    # status_direct.sh returns one line: build=X train=Y note=Z
    if state=$( bash "$STATUS_SCRIPT" "$VAST_HOST" "$VAST_PORT" 2>/dev/null ); then
        ssh_failures=0
    else
        ssh_failures=$(( ssh_failures + 1 ))
        if [[ "$ssh_failures" -ge 3 ]]; then
            _log "FAIL: 3 consecutive SSH failures contacting $VAST_HOST:$VAST_PORT"
            _notify "monitor: lost contact with $VAST_HOST"
            final_exit=1
            break
        fi
        sleep "$INTERVAL"
        continue
    fi

    if [[ "$state" != "$last_state" ]]; then
        _log "$state"
        _notify "$state"
        last_state="$state"
    fi

    case "$state" in
        *train=DONE*)
            _log "monitor exiting cleanly — training complete"
            final_exit=0
            break
            ;;
        *train=FAILED*|*train=crashed*)
            _log "monitor exiting nonzero — training failed/crashed"
            final_exit=1
            break
            ;;
    esac

    sleep "$INTERVAL"
done

_log "final state: $last_state  exit=$final_exit"
exit "$final_exit"
