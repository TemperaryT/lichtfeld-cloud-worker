#!/usr/bin/env bash
set -euo pipefail

echo "=== nvidia-smi ==="
nvidia-smi

echo ""
echo "=== GPU model + VRAM ==="
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader

echo ""
echo "=== CUDA runtime ==="
python3 -c "
import ctypes, sys
try:
    ctypes.cdll.LoadLibrary('libcuda.so.1')
    print('libcuda.so.1: OK')
except OSError as e:
    print(f'libcuda.so.1: FAILED — {e}')
    sys.exit(1)
"

echo ""
echo "validate_gpu: PASS"
