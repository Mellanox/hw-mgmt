#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Cache NVMe shutdown hook eligibility at boot. The hook under
# /usr/lib/systemd/system-shutdown/ reads this flag because
# /var/run/hw-management is gone in the final shutdown phase.
##################################################################################

set -euo pipefail

readonly FLAG_DIR=/var/lib/hw-management
readonly FLAG_FILE=$FLAG_DIR/nvme-shutdown-enabled
readonly LOGGER_TAG="hw-management-nvme-shutdown"

log_msg() { logger -t "$LOGGER_TAG" -p user.notice -- "$@"; }

mkdir -p "$FLAG_DIR"

if /usr/bin/hw-management-nvme-shutdown-condition.sh; then
	echo 1 >"$FLAG_FILE"
	log_msg "NVMe shutdown hook enabled (no-BMC platform with NVMe storage)"
else
	echo 0 >"$FLAG_FILE"
	log_msg "NVMe shutdown hook disabled (BMC present, SATA, or no NVMe)"
fi
