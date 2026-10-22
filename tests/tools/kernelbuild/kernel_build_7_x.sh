#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Linux 7.x entry point for kernel_build_6_x.sh.
# The version must be 7.x. The tarball comes from kernel.org v7.x.
# Patch selection uses the Kernel-7.<minor> section, and the deploy tool
# reads recipes-kernel/linux/linux-7.<minor>/ and kconfig_7_<minor>.txt
# (for example linux-7.0/ and kconfig_7_0.txt).
# Missing linux-7.3.1.tar.xz falls back to linux-7.3.tar.xz. Missing
# kconfig_7_3.txt falls back to the closest older kconfig_*.txt.
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/kernel_build_6_x.sh" "$@"
