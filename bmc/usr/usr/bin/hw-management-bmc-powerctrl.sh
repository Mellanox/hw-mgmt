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
	echo 1 >"${MLX_HWMON}/graceful_power_off"
	count=0
	while true; do
		sleep 1
		count=$((count + 1))
		cpu_power_off_ready=$(<"${MLX_HWMON}/cpu_power_off_ready")
		if [ "${cpu_power_off_ready}" -eq 1 ] || [ "${count}" -eq "${RETRIES}" ]; then
			break
		fi
	done
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
	echo 1 >"${MLX_HWMON}/pwr_down"

	echo 0 >"${MLX_HWMON}/uart_sel"
	echo 1 >"${MLX_HWMON}/bmc_to_cpu_ctrl"
	log_msg "Setting CurrentHostState to Off"
	set_host_powerstate_off
}

reset() {
	log_msg "Force Power Cycle Host"
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
	echo "    power_off:   immediate force host power off" >&2
	echo "    power_on:    immediate host power on" >&2
	echo "    reset:       immediate force host power cycle" >&2
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
