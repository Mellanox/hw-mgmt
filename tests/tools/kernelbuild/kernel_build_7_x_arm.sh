#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Linux 7.x arm64 entry point.
# Uses ARCH=arm64, the arm64 section of kconfig_<major>_<minor>.txt,
# and aarch64-linux-gnu- unless --cross-compile is passed.
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/kernel_build_6_x_arm.sh" "$@"
