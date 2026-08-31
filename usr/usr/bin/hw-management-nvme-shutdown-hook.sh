#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# systemd-shutdown(8) hook: runs in the final userspace phase, after services
# are stopped and filesystems are unmounted, immediately before the kernel
# poweroff/reboot path (pm_power_off / CPLD halt on no-BMC platforms).
#
# Argument: poweroff | halt | reboot | kexec
##################################################################################

set -euo pipefail

if [ -f /etc/default/hw-management-nvme-shutdown ]; then
	# shellcheck disable=SC1091
	. /etc/default/hw-management-nvme-shutdown
fi

readonly NVME_SHUTDOWN_TIMEOUT_SEC="${NVME_SHUTDOWN_TIMEOUT_SEC:-120}"

if command -v timeout >/dev/null 2>&1; then
	exec timeout --foreground "${NVME_SHUTDOWN_TIMEOUT_SEC}" \
		/usr/bin/hw-management-nvme-shutdown.sh "$@"
fi

exec /usr/bin/hw-management-nvme-shutdown.sh "$@"
