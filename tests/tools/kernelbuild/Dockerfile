# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Build environment for kernel_build_6_x.sh and the scripts that source it
# (kernel_build_7_x.sh, *_arm.sh, *_sonic_bmc.sh).
#
# The scripts build and run this image by themselves, so no manual
# "docker build" is needed. To build it by hand:
#
#   docker build -t hw-mgmt-kernel-build -f Dockerfile .
#
# The image holds only tools. The kernel tree, hw-mgmt checkout, and output
# are bind-mounted by the script at the same absolute paths as on the host.
#
# Packages match:
#   - the tools kernel_build_6_x.sh checks: tar, xz, git, stg, python3, make,
#     wget/curl, gcc, dpkg-checkbuilddeps, dpkg-architecture;
#   - the Build-Depends of "make deb-pkg" (scripts/package/mkdebian):
#     debhelper, bc, bison, cpio, flex, kmod, rsync, libelf-dev, libssl-dev,
#     gcc for the package architecture;
#   - the arm64 / aspeed (SONiC BMC) cross toolchain and libssl-dev:arm64.
#
# Cross toolchain: on an amd64 image the arm64 compiler, its libc headers
# (dpkg-genbuildinfo compiles <unistd.h> with the cross gcc), and
# libssl-dev:arm64 are installed. On an arm64 image the x86-64 ones are
# installed instead.

ARG BASE_IMAGE=debian:bookworm
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN set -eux; \
    native="$(dpkg --print-architecture)"; \
    case "$native" in \
        amd64) foreign=arm64; cross_gcc="gcc-aarch64-linux-gnu libc6-dev-arm64-cross" ;; \
        arm64) foreign=amd64; cross_gcc="gcc-x86-64-linux-gnu libc6-dev-amd64-cross" ;; \
        *) echo "unsupported image architecture: $native" >&2; exit 1 ;; \
    esac; \
    dpkg --add-architecture "$foreign"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bc \
        binutils \
        bison \
        build-essential \
        ca-certificates \
        cpio \
        curl \
        debhelper \
        dpkg-dev \
        dwarves \
        fakeroot \
        file \
        flex \
        gawk \
        git \
        kmod \
        libdw-dev \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        lz4 \
        openssl \
        perl \
        pkg-config \
        python3 \
        python3-pip \
        python3-yaml \
        rsync \
        stgit \
        tar \
        wget \
        xz-utils \
        zstd \
        $cross_gcc \
        "libssl-dev:${foreign}"; \
    rm -rf /var/lib/apt/lists/*; \
    # python3 is called "python" by some hw-mgmt tools
    ln -sf /usr/bin/python3 /usr/local/bin/python; \
    # deploy_kernel_patches.py starts with "#!/usr/bin/python"
    [ -e /usr/bin/python ] || ln -s /usr/bin/python3 /usr/bin/python

# The script runs the container with the caller's uid/gid, which have no
# passwd entry here. git and stg then need a HOME they can write to.
ENV HOME=/tmp

WORKDIR /work
CMD ["/bin/bash"]
