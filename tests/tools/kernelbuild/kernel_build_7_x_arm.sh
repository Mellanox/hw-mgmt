#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Linux 7.x arm64 entry point. Sources kernel_build_6_x_arm.sh, which
# sources kernel_build_6_x.sh with --arch arm64.
# Uses the arm64 section of kconfig_7_<minor>.txt and aarch64-linux-gnu-
# unless --cross-compile is passed.
# Optional --third-party-patches and --bmc-patch-table follow the same
# order as kernel_build_7_x.sh. --apply-with-quilt applies them with
# quilt push --fuzz=0. A local conflict fix belongs in
# recipes-kernel/linux/linux-7.<minor>/third-party/<version>/.
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/kernel_build_6_x_arm.sh" "$@"
