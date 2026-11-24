#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Linux 7.x entry point. This sources kernel_build_6_x.sh. $0 stays
# kernel_build_7_x.sh, which selects kernel.org v7.x and a Kernel-7.*
# section. Patch files come from recipes-kernel/linux/linux-7.<minor>/
# and kconfig from kconfig_7_<minor>.txt.
#
# Flow, shared with the 6.x scripts:
#   1. Patch_Status_Table.txt for the NOS (--os-type).
#   2. Optional --third-party-patches, series order when series exists.
#      linux-7.<minor>/third-party/<version>/<same-name> replaces a
#      downloaded patch. That is a local conflict fix to send upstream,
#      not an hw-mgmt series patch.
#   3. Optional --bmc-patch-table, after the third-party layer.
# An arm64 or aspeed point-release overlay under
# linux-7.<minor>/<nos>/{arm,aspeed}/<kver>/ overwrites the base patch.
# The third-party fix directory wins over that overlay.
#
# Missing linux-7.3.1.tar.xz falls back to linux-7.3.tar.xz. Missing
# kconfig_7_3.txt falls back to the closest older kconfig_*.txt.
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/kernel_build_6_x.sh" "$@"
