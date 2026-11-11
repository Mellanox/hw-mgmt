#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Linux 7.x SONiC BMC entry point.
# arm64 tools, aspeed kconfig, and the same three patch layers as
# kernel_build_6_x_sonic_bmc.sh. --third-party-patches is required.
#

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/kernel_build_6_x_sonic_bmc.sh" "$@"
