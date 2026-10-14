#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# arm64 entry point for kernel_build_6_x.sh.
# Uses ARCH=arm64, the arm64 section of kconfig_<major>_<minor>.txt,
# and aarch64-linux-gnu- unless --cross-compile is passed.
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$script_dir/kernel_build_6_x.sh" "$@" --arch arm64
