#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# SONiC BMC (AST2700) entry point for kernel_build_6_x.sh.
# Toolchain and make ARCH match the arm64 build. Kernel options come from
# the [aspeed:upstream] and [aspeed:downstream] sections of kconfig_6_*.txt.
#
# Patches are applied in three layers:
#   1. recipes-kernel/linux/Patch_Status_Table.txt
#      (files under recipes-kernel/linux/linux-<major.minor>/)
#   2. Every *.patch in --third-party-patches, in filename order.
#      These are the Sonic patches. They are not filtered by a status table.
#   3. recipes-kernel/linux/Patch_BMC_Status_Table.txt
#      (also taken from linux-<major.minor>/, selected for sonic)
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
    cat <<EOF
Usage:
  ${0##*/} [options] <build_path> <hw_mgmt_path> <kernel_version> \\
      --third-party-patches <sonic_patch_dir>

Build a 6.x SONiC BMC kernel.

The toolchain is the arm64 one (ARCH=arm64, aarch64-linux-gnu- unless
--cross-compile is set). .config is filled from the aspeed sections of
recipes-kernel/linux/kconfig_<major>_<minor>.txt.

Patch order:
  1. Patch_Status_Table.txt for --os-type (this script uses sonic)
  2. Each *.patch in <sonic_patch_dir>, sorted by name
  3. Patch_BMC_Status_Table.txt for sonic

Options are the same as kernel_build_6_x.sh. --third-party-patches is required.
--os-type sonic, --arch arm64, and the aspeed kconfig section are set by
this script. A --cross-compile prefix on the command line is kept.

Example:
  ${0##*/} /tmp/bmc-build /path/to/hw-mgmt 6.12.94 \\
      --third-party-patches /path/to/sonic-patches
EOF
}

has_third_party=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            exit 0
            ;;
        --third-party-patches|--third_party_patches|--third-party-patches=*|--third_party_patches=*)
            has_third_party=1
            ;;
    esac
done

if [[ "$has_third_party" -eq 0 ]]; then
    printf 'error: --third-party-patches <sonic_patch_dir> is required\n' >&2
    printf 'try: %s --help\n' "$0" >&2
    exit 2
fi

exec "$script_dir/kernel_build_6_x.sh" "$@" \
    --arch arm64 \
    --deploy-arch aspeed \
    --os-type sonic \
    --bmc-patch-table Patch_BMC_Status_Table.txt
