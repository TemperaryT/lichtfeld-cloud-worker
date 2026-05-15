#!/usr/bin/env bash
# GPU validation — called by run/validate.sh, output goes to logs/validate.log.
set -euo pipefail

GPU=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
[[ -z "$GPU" ]] && { echo "nvidia-smi failed"; exit 1; }

python3 -c "import ctypes; ctypes.cdll.LoadLibrary('libcuda.so.1')" 2>/dev/null \
    || { echo "libcuda.so.1 not found"; exit 1; }

echo "GPU=$GPU"
