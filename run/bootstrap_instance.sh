#!/usr/bin/env bash
# Build LichtFeld Studio from source on a Vast.ai CUDA devel instance.
# Target image: nvidia/cuda:12.8.0-devel-ubuntu24.04
# Idempotent — skips build if lichtfeld-studio is already in PATH.
# Writes STATUS/BUILD for polling. All verbose output goes to logs/build.log.
# Usage: bash run/bootstrap_instance.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LFS_TAG="${LFS_TAG:-v0.5.2}"
LFS_SRC="${LFS_SRC:-/workspace/LichtFeld-Studio}"
VCPKG_ROOT="${VCPKG_ROOT:-/opt/vcpkg}"
LOG="$REPO_ROOT/logs/build.log"
STATUS="$REPO_ROOT/STATUS/BUILD"

mkdir -p "$REPO_ROOT/logs" "$REPO_ROOT/STATUS"

_write() { printf 'STATE=%s\nNOTE=%s\nUPDATED=%s\n' "$1" "${2:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS"; }
_log()   { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }
die()    { _write "failed" "$1"; _log "FAILED: $1"; exit 1; }
trap 'die "unexpected error at line $LINENO"' ERR

# Skip if already built
if command -v lichtfeld-studio &>/dev/null; then
    _write "done" "already installed: $(which lichtfeld-studio)"
    echo "build=skipped lichtfeld-studio already in PATH"
    exit 0
fi

_log "=== LichtFeld bootstrap: $LFS_TAG ==="

# Verify CUDA dev environment
command -v nvcc &>/dev/null || die "nvcc not found — requires nvidia/cuda:12.8.0-devel image"
_log "nvcc: $(nvcc --version | grep release | awk '{print $6}' | tr -d ,)"

# ── deps ──────────────────────────────────────────────────────────────────────
_write "installing_deps" ""
_log "installing build deps..."
apt-get update -qq >> "$LOG" 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    gcc-14 g++-14 ninja-build git curl zip unzip \
    pkg-config libssl-dev python3-pip >> "$LOG" 2>&1
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14 >> "$LOG" 2>&1
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 14 >> "$LOG" 2>&1
pip3 install cmake --break-system-packages -q >> "$LOG" 2>&1
_log "cmake: $(cmake --version | head -1)  gcc: $(gcc --version | head -1 | awk '{print $1,$3}')"

# ── vcpkg ─────────────────────────────────────────────────────────────────────
_write "cloning" "vcpkg"
if [[ ! -d "$VCPKG_ROOT/.git" ]]; then
    _log "cloning vcpkg..."
    git clone https://github.com/microsoft/vcpkg "$VCPKG_ROOT" >> "$LOG" 2>&1
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics >> "$LOG" 2>&1
else
    _log "vcpkg: already present at $VCPKG_ROOT"
fi

# ── LichtFeld source ──────────────────────────────────────────────────────────
_write "cloning" "LichtFeld-Studio $LFS_TAG"
if [[ ! -d "$LFS_SRC/.git" ]]; then
    _log "cloning LichtFeld-Studio $LFS_TAG..."
    git clone --branch "$LFS_TAG" --depth 1 \
        https://github.com/MrNeRF/LichtFeld-Studio "$LFS_SRC" >> "$LOG" 2>&1
else
    _log "source: already present at $LFS_SRC"
fi

# ── cmake configure ────────────────────────────────────────────────────────────
_write "building" "cmake configure"
_log "configuring (headless, no GUI backends)..."
cmake -B "$LFS_SRC/build" \
    -S "$LFS_SRC" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLFS_ENFORCE_LINUX_GUI_BACKENDS=OFF \
    -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
    -G Ninja \
    >> "$LOG" 2>&1

# ── compile ────────────────────────────────────────────────────────────────────
_write "building" "compiling on $(nproc) cores — 15-30 min"
_log "compiling on $(nproc) cores..."
cmake --build "$LFS_SRC/build" -j$(nproc) >> "$LOG" 2>&1

# ── install ────────────────────────────────────────────────────────────────────
BINARY="$LFS_SRC/build/LichtFeld-Studio"
[[ -f "$BINARY" ]] || die "build completed but binary not found at $BINARY"
chmod +x "$BINARY"
ln -sf "$BINARY" /usr/local/bin/lichtfeld-studio

VERSION=$(lichtfeld-studio --version 2>&1 | head -1 || echo "binary present")
_write "done" "$VERSION"
_log "done: $VERSION"
echo "build=done binary=$BINARY"
