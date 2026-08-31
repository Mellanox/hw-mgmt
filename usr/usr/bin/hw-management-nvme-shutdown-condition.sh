#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Return 0 when the NVMe shutdown hook should run:
#   - NVMe block devices are present under /dev/nvme*
#   - platform has no BMC (software-only shutdown path)
#
# Do not treat a 0 reading of bmc_present as proof of no BMC: on some
# BMC hosts (e.g. HI180) that GPIO is a false negative. Skip known BMC
# SKUs even when bmc_present/gp_bmc_presnt read 0 or are missing.
#
# Return 1 to skip.
#
# At systemd-shutdown time /var/run/hw-management is usually gone, so a flag
# cached at boot in /var/lib/hw-management/nvme-shutdown-enabled is used.
##################################################################################

set -euo pipefail

readonly LOGGER_TAG="hw-management-nvme-shutdown"
readonly HW_MGMT_SYSTEM=/var/run/hw-management/system
readonly FLAG_DIR=/var/lib/hw-management
readonly FLAG_FILE=$FLAG_DIR/nvme-shutdown-enabled

log_dbg() { logger -t "$LOGGER_TAG" -p user.debug -- "$@"; }

read_attr() {
	local path=$1

	[ -f "$path" ] || return 1
	tr -d '[:space:]' <"$path"
}

# Host DMI product_sku values for BMC-equipped L1 systems. Presence of
# cpu_shutdown_req / cpu_power_off_ready sysfs is NOT used: mlx-platform
# exports those on no-BMC boards as well.
bmc_sku_platform() {
	local sku

	sku=$(read_attr /sys/devices/virtual/dmi/id/product_sku 2>/dev/null) || \
		sku=$(read_attr "$HW_MGMT_SYSTEM/sku" 2>/dev/null) || \
		sku=""

	case "$sku" in
	HI180|HI181|HI182|HI183|HI185|HI186|HI187|HI188|HI193|HI194|HI195|HI197|HI199|HI200|HI201)
		log_dbg "BMC SKU $sku, skip NVMe shutdown hook"
		return 0
		;;
	esac
	return 1
}

bmc_is_present() {
	local path val

	if bmc_sku_platform; then
		return 0
	fi

	for path in \
		"$HW_MGMT_SYSTEM/bmc_present" \
		/sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/gp_bmc_presnt
	do
		val=$(read_attr "$path" 2>/dev/null) || continue
		case "$val" in
		1)
			log_dbg "BMC present ($path=1), skip NVMe shutdown hook"
			return 0
			;;
		esac
	done

	return 1
}

nvme_block_devices_exist() {
	local dev

	for dev in /dev/nvme*; do
		[ -b "$dev" ] || continue
		return 0
	done

	return 1
}

nvme_storage_configured() {
	if nvme_block_devices_exist; then
		return 0
	fi

	log_dbg "No NVMe block devices under /dev/nvme*, skip hook"
	return 1
}

evaluate_platform_eligibility() {
	if bmc_is_present; then
		return 1
	fi

	if ! nvme_storage_configured; then
		return 1
	fi

	return 0
}

read_cached_eligibility() {
	local val

	val=$(read_attr "$FLAG_FILE" 2>/dev/null) || return 1
	[ "$val" -eq 1 ]
}

main() {
	if [ ! -d "$HW_MGMT_SYSTEM" ]; then
		if read_cached_eligibility; then
			exit 0
		fi
		log_dbg "hw-management tree absent and cache disabled, skip hook"
		exit 1
	fi

	if evaluate_platform_eligibility; then
		exit 0
	fi

	exit 1
}

main "$@"
