#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Linux 7.x SONiC BMC entry point. Sources kernel_build_6_x_sonic_bmc.sh,
# which sources kernel_build_6_x.sh. arm64 tools, aspeed kconfig, and
# --third-party-patches is required.
#
# Patch order:
#   1. Patch_Status_Table.txt (linux-7.<minor>/, sonic)
#   2. The directory given to --third-party-patches. fetch_sonic_aspeed_patches.sh
#      downloads the Nexthop AST2700 patches and the NVIDIA SPC6 DTS.
#      series order when series exists. Do not put nvidia_aspeed_bmc
#      patches here; layer 3 already applies them.
#      A same-named fix under
#      recipes-kernel/linux/linux-7.<minor>/third-party/<version>/
#      replaces the download. Send that fix to SONiC. Do not add the
#      Nexthop patch to the hw-mgmt series.
#   3. Patch_BMC_Status_Table.txt
# --apply-with-quilt applies all three layers with quilt push --fuzz=0.
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/kernel_build_6_x_sonic_bmc.sh" "$@"
