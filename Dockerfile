# Stage 1: builder — compiles LichtFeld Studio from source with headless flag
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04 AS builder

ARG LFS_TAG=v0.5.2
ARG MAKE_JOBS=2

# Note: Ubuntu 24.04's apt cmake is 3.28, but LichtFeld needs >=3.30.
# Install cmake via pip (pulls 3.31+). bootstrap_instance.sh does the same.
#
# vcpkg ports often require additional build tools (nasm for x264, autotools
# for many C libs, bison/flex for parsers). Pre-installing avoids piecemeal
# retry cycles when transitive deps fail.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    gcc-14 g++-14 ninja-build git python3 python3-pip curl zip unzip pkg-config \
    libssl-dev ca-certificates \
    nasm yasm autoconf autoconf-archive automake libtool m4 bison flex gettext texinfo gperf \
    libgl-dev libglu1-mesa-dev libglx-dev libegl-dev mesa-common-dev \
    && pip3 install --no-cache-dir --break-system-packages -q cmake \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 14

# vcpkg
RUN git clone --quiet https://github.com/microsoft/vcpkg /vcpkg \
    && /vcpkg/bootstrap-vcpkg.sh -disableMetrics

# LichtFeld source — pinned to release tag
RUN git clone --quiet --branch ${LFS_TAG} --depth 1 \
    https://github.com/MrNeRF/LichtFeld-Studio /src

WORKDIR /src

# -DLFS_ENFORCE_LINUX_GUI_BACKENDS=OFF is the critical headless flag.
# Without it the build pulls in SDL3 X11/Wayland backends and fails in a
# display-less container.
#
# MAKE_JOBS is overridable via build-arg; GHA passes 2 to fit in 16 GB RAM.
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DLFS_ENFORCE_LINUX_GUI_BACKENDS=OFF \
    -DCMAKE_TOOLCHAIN_FILE=/vcpkg/scripts/buildsystems/vcpkg.cmake \
    -G Ninja \
    && cmake --build build -j${MAKE_JOBS}


# Stage 2: runtime — leaner image, includes ffmpeg + python deps so the
# smoke test pipeline (frame extract + prep_frames.py) runs without setup.
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    python3 python3-pip curl ca-certificates ffmpeg tmux \
    && pip3 install --no-cache-dir --break-system-packages -q \
        opencv-python-headless pillow numpy \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build/LichtFeld-Studio /usr/local/bin/lichtfeld-studio

COPY scripts/ /opt/lichtfeld/scripts/
COPY configs/ /opt/lichtfeld/configs/
RUN chmod +x /opt/lichtfeld/scripts/*.sh

# If ldd shows missing shared libs from the builder stage, add a COPY step here.
# Check with: docker run --entrypoint ldd lichtfeld-cloud-worker /usr/local/bin/lichtfeld-studio

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# No VOLUME — Phase 1 use is direct on Vast (ssh_direct mode), not docker-run.
# ENTRYPOINT kept for Phase 2 docker-run compatibility; Vast ssh_direct overrides it.
ENTRYPOINT ["/opt/lichtfeld/scripts/run_train.sh"]
