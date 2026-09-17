#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# hw-management-bmc-powerctrl: host and board power control via sysfs.
# No dependency on phosphor/OpenBMC services or bmc-boot-complete.
################################################################################

set -euo pipefail

RETRIES=20
# Forced power_off/reset NVMe window. HW_MGMT_BMC_REBOOT_TO=0 skips the wait.
REBOOT_TO=${HW_MGMT_BMC_REBOOT_TO:-5}
if ! [[ "${REBOOT_TO}" =~ ^[0-9]+$ ]]; then
	REBOOT_TO=5
fi
readonly LOGGER_TAG="hw-management-bmc-powerctrl"

# mlxreg-io hwmon directory (hwmon0, hwmon1, … under …/mlxreg-io/hwmon/)
MLX_HWMON_BASE=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon

log_msg() {
	logger -t "$LOGGER_TAG" -p user.notice -- "$@"
}

log_err() {
	logger -t "$LOGGER_TAG" -p user.err -- "$@"
}

# Sets MLX_HWMON to the first resolved hwmon* directory, or returns 1.
resolve_mlx_hwmon() {
	local d
	MLX_HWMON=""
	for d in "$MLX_HWMON_BASE"/hwmon*; do
		if [ -d "$d" ]; then
			MLX_HWMON=$d
			return 0
		fi
	done
	return 1
}

set_host_powerstate_off() {
	:
}

set_host_powerstate_on() {
	:
}

set_requested_host_transition() {
	:
}

wait_for_cpu_shutdown() {
	local retries=${1:-${RETRIES}}
	if ! [[ "${retries}" =~ ^[1-9][0-9]*$ ]]; then
		retries=${RETRIES}
	fi
	log_msg "Requesting CPU shutdown from switch hardware (timeout ${retries}s)"
	# Re-arm: host peripheral-updater is edge-triggered (1 Hz). Leave
	# request low long enough to observe 0, then a new 0->1. Also clear
	# ready from the previous transaction.
	echo 0 >"${MLX_HWMON}/graceful_power_off" 2>/dev/null || true
	echo 0 >"${MLX_HWMON}/cpu_power_off_ready" 2>/dev/null || true
	sleep 1
	echo 1 >"${MLX_HWMON}/graceful_power_off"
	count=0
	cpu_power_off_ready=0
	while true; do
		sleep 1
		count=$((count + 1))
		if [ -r "${MLX_HWMON}/cpu_power_off_ready" ]; then
			cpu_power_off_ready=$(<"${MLX_HWMON}/cpu_power_off_ready")
		else
			cpu_power_off_ready=0
		fi
		if ! [[ "${cpu_power_off_ready}" =~ ^[01]$ ]]; then
			cpu_power_off_ready=0
		fi
		if [ "${cpu_power_off_ready}" -eq 1 ] || [ "${count}" -ge "${retries}" ]; then
			break
		fi
	done
	if [ "${cpu_power_off_ready}" -eq 1 ]; then
		log_msg "CPU reported ready after ${count}s"
	else
		log_msg "CPU did not report ready within ${retries}s; proceeding anyway"
	fi
	echo 0 >"${MLX_HWMON}/graceful_power_off" 2>/dev/null || true
	echo 0 >"${MLX_HWMON}/cpu_power_off_ready" 2>/dev/null || true
}

power_on() {
	log_msg "Power On Host"
	echo 0 >"${MLX_HWMON}/pwr_down"

	if [ -f "${MLX_HWMON}/pwr_button_halt" ]; then
		echo 0 >"${MLX_HWMON}/pwr_button_halt"
	fi

	echo 0 >"${MLX_HWMON}/bmc_to_cpu_ctrl"
	log_msg "Setting CurrentHostState to On"
	set_host_powerstate_on
}

power_off() {
	log_msg "Force Power Off Host"
	if [ "${REBOOT_TO}" -gt 0 ]; then
		log_msg "Non-graceful NVMe-safe wait ${REBOOT_TO}s before power off"
		wait_for_cpu_shutdown "${REBOOT_TO}"
	fi
	echo 1 >"${MLX_HWMON}/pwr_down"

	echo 0 >"${MLX_HWMON}/uart_sel"
	echo 1 >"${MLX_HWMON}/bmc_to_cpu_ctrl"
	log_msg "Setting CurrentHostState to Off"
	set_host_powerstate_off
}

reset() {
	log_msg "Force Power Cycle Host"
	if [ "${REBOOT_TO}" -gt 0 ]; then
		log_msg "Non-graceful NVMe-safe wait ${REBOOT_TO}s before power cycle"
		wait_for_cpu_shutdown "${REBOOT_TO}"
	fi
	echo 1 >"${MLX_HWMON}/pwr_cycle"
	set_host_powerstate_off
}

reset_board() {
	local reset_bypass_file="/var/reset_bypass"
	if [ -f "$reset_bypass_file" ]; then
		log_msg "Power Cycle Bypass Board"
	else
		log_msg "Power Cycle Board"
	fi
	wait_for_cpu_shutdown
	echo 1 >"${MLX_HWMON}/aux_pwr_cycle"
}

grace_off() {
	local grace_reset_bypass_file="/var/grace_reset_bypass"
	if [ -f "$grace_reset_bypass_file" ]; then
		log_msg "$grace_reset_bypass_file exists, removing and skipping graceful power off."
		rm -f "$grace_reset_bypass_file"
		set_requested_host_transition
		return
	fi

	log_msg "Graceful Power Off Host"
	wait_for_cpu_shutdown
	echo 1 >"${MLX_HWMON}/pwr_down"
	echo 0 >"${MLX_HWMON}/uart_sel"
	set_host_powerstate_off
}

grace_reset() {
	log_msg "Graceful Power Cycle Host"
	wait_for_cpu_shutdown
	echo 1 >"${MLX_HWMON}/pwr_cycle"
	set_host_powerstate_off
}

usage() {
	echo "Usage: $0 <power_on|power_off|reset|reset_board|grace_off|grace_reset>" >&2
	echo "    power_off:   force host power off (NVMe wait ${REBOOT_TO}s; 0=immediate)" >&2
	echo "    power_on:    immediate host power on" >&2
	echo "    reset:       force host power cycle (NVMe wait ${REBOOT_TO}s; 0=immediate)" >&2
	echo "    reset_board: graceful host power off and board power cycle" >&2
	echo "    grace_off:   graceful host power off" >&2
	echo "    grace_reset: graceful host power cycle" >&2
}

### MAIN ###
if [ "$#" -eq 0 ]; then
	usage
	exit 1
fi

if ! resolve_mlx_hwmon; then
	log_err "mlxreg-io hwmon not found under ${MLX_HWMON_BASE}/hwmon*"
	exit 1
fi

case "$1" in
power_on) power_on ;;
power_off) power_off ;;
reset) reset ;;
reset_board) reset_board ;;
grace_off) grace_off ;;
grace_reset) grace_reset ;;
*)
	usage
	exit 1
	;;
esac
