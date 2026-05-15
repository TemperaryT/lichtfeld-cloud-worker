# Stage 1: builder — compiles LichtFeld Studio from source with headless flag
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04 AS builder

ARG LFS_TAG=v0.5.2

RUN apt-get update && apt-get install -y \
    gcc-14 g++-14 cmake ninja-build git python3 curl zip unzip pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 14

# vcpkg
RUN git clone https://github.com/microsoft/vcpkg /vcpkg \
    && /vcpkg/bootstrap-vcpkg.sh -disableMetrics

# LichtFeld source — pinned to release tag
RUN git clone --branch ${LFS_TAG} --depth 1 \
    https://github.com/MrNeRF/LichtFeld-Studio /src

WORKDIR /src

# -DLFS_ENFORCE_LINUX_GUI_BACKENDS=OFF is the critical headless flag.
# Without it the build pulls in SDL3 X11/Wayland backends and fails in a
# display-less container.
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DLFS_ENFORCE_LINUX_GUI_BACKENDS=OFF \
    -DCMAKE_TOOLCHAIN_FILE=/vcpkg/scripts/buildsystems/vcpkg.cmake \
    -G Ninja \
    && cmake --build build -j$(nproc)


# Stage 2: runtime — leaner image with just the binary and scripts
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

RUN apt-get update && apt-get install -y \
    python3 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build/LichtFeld-Studio /usr/local/bin/lichtfeld-studio

COPY scripts/ /opt/lichtfeld/scripts/
COPY configs/ /opt/lichtfeld/configs/
RUN chmod +x /opt/lichtfeld/scripts/*.sh

# If ldd shows missing shared libs from the builder stage, add a COPY step here.
# Check with: docker run --entrypoint ldd lichtfeld-cloud-worker /usr/local/bin/lichtfeld-studio

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

VOLUME ["/data", "/output"]

ENTRYPOINT ["/opt/lichtfeld/scripts/run_train.sh"]
