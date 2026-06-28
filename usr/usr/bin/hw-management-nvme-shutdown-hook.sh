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

exec /usr/bin/hw-management-nvme-shutdown.sh "$@"
