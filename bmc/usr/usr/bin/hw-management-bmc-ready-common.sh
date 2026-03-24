#!/bin/bash
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# BMC VPD EEPROM (system HID / BOM): defaults below match HI193 (24c512 @ 5-0051).
# If /etc/hw-management-bmc-eeprom.conf exists (deployed from usr/etc/<HID>/ by
# hw-management-bmc-plat-specific-preps.sh), it is sourced and overrides these.
# A platform may also assign variables before sourcing this script.
# shellcheck disable=SC2034
# (I2C bus/address: metadata for tooling; EEPROM access uses eeprom_file.)
BMC_VPD_EEPROM_I2C_BUS=5
BMC_VPD_EEPROM_I2C_ADDRES=0x51
BMC_VPD_EEPROM_HID_OFFSET=22
BMC_VPD_EEPROM_HID_SIZE=5
BMC_VPD_EEPROM_BOM_SIZE=192
eeprom_file=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0f600.i2c-bus/i2c-5/5-0051/eeprom

HW_MANAGEMENT_BMC_EEPROM_CONF="/etc/hw-management-bmc-eeprom.conf"
if [ -r "$HW_MANAGEMENT_BMC_EEPROM_CONF" ]; then
	# shellcheck source=/dev/null
	. "$HW_MANAGEMENT_BMC_EEPROM_CONF"
fi

#######################################
# Wait for GP_STBY_PG (BMC standby-ready) via sysfs GPIO value file.
# Uses global BMC_STBY_READY (path to the value file), set in
# bmc_init_sysfs_gpio() from hw-management-bmc-gpio-set.sh before this runs.
# ARGUMENTS:
#   $1 timeout (seconds, default 10) — max wall time to wait
#   $2 interval (seconds, default 1) — sleep between polls
# RETURN:
#   0 if the value reads 1 within the timeout
#   1 on timeout, or if BMC_STBY_READY is unset / not readable
#######################################
wait_bmc_standby_ready()
{
	local timeout_sec=${1:-10}
	local interval_secs=${2:-1}
	local start_time=$EPOCHSECONDS

	if [ -z "${BMC_STBY_READY:-}" ] || [ ! -r "$BMC_STBY_READY" ]; then
		echo "[ERROR] BMC_STBY_READY is not set or not readable: ${BMC_STBY_READY:-<unset>}"
		return 1
	fi

	echo "Wait for BMC standby Ready, timeout = ${timeout_sec} secs..."
	echo "Expecting $BMC_STBY_READY set HIGH"

	while true; do
		local ready_status
		read -r ready_status < "$BMC_STBY_READY" || true
		ready_status="${ready_status//$'\r'/}"

		if [ "${ready_status}" = "1" ]; then
			echo "BMC standby ready asserted"
			return 0
		fi

		echo "Waiting for BMC standby ready signal, elapsed $((EPOCHSECONDS - start_time))s"
		sleep "$interval_secs"

		if ((EPOCHSECONDS - start_time >= timeout_sec)); then
			echo "[ERROR] BMC standby not ready in ${timeout_sec} secs"
			return 1
		fi
	done
}

#######################################
# Wait until system folder under /var/run/hw-management exists (udev → userspace).
# Uses global system_path from hw-management-bmc-helpers.sh (…/system).
# RETURN: 0 if directory appears, 1 on timeout or if system_path is unset
#######################################
wait_platform_drv()
{
	local plat_driver_timeout_ms=20000
	local count=0

	if [ -z "${system_path:-}" ]; then
		echo "[ERROR] system_path unset; cannot wait for platform driver"
		return 1
	fi

	while true; do
		if [ -d "$system_path" ]; then
			return 0
		fi

		if [ "${count}" -eq "${plat_driver_timeout_ms}" ]; then
			echo "ERROR: timed out waiting for $system_path to become available"
			return 1
		fi

		if ((count % 1000 == 0)); then
			echo "Waiting for $system_path to become available, $count ms passed"
		fi
		sleep 0.1
		count=$((count + 100))
	done
}

#######################################
# Read CPU part from /proc/cpuinfo and write hex type to $config_path/cpu_type.
# Uses global config_path from hw-management-bmc-helpers.sh.
#######################################
get_cpu_type()
{
	local cpu_pn cpu_type

	if [ -z "${config_path:-}" ]; then
		echo "[ERROR] config_path unset; cannot store cpu_type"
		return 1
	fi

	cpu_pn=$(grep -m1 "CPU part" /proc/cpuinfo | awk '{print $4}')
	cpu_pn=$(printf '%s' "$cpu_pn" | cut -c 3- | tr '[:lower:]' '[:upper:]')
	cpu_pn=0x${cpu_pn}
	cpu_type=$cpu_pn
	printf '%s\n' "$cpu_type" > "${config_path}/cpu_type"
}

#######################################
# Read hardware ID from BMC VPD EEPROM into $config_path/hid.
# Globals: BMC_VPD_EEPROM_HID_{OFFSET,SIZE}, eeprom_file (defaults + optional /etc/hw-management-bmc-eeprom.conf).
#######################################
get_system_hw_id()
{
	local offset num_bytes raw_data

	if [ -z "${config_path:-}" ]; then
		echo "[ERROR] config_path unset; cannot store hid"
		return 1
	fi
	if [ -z "${eeprom_file:-}" ] || [ ! -r "$eeprom_file" ]; then
		echo "[ERROR] eeprom_file not readable: ${eeprom_file:-<unset>}"
		return 1
	fi

	offset=$BMC_VPD_EEPROM_HID_OFFSET
	num_bytes=$BMC_VPD_EEPROM_HID_SIZE
	raw_data=$(dd if="$eeprom_file" bs=1 skip="$offset" count="$num_bytes" 2>/dev/null) || true

	printf '%s' "$raw_data" > "${config_path}/hid"
	echo "System hardware Id is $raw_data"
}

#######################################
# Parse BOM from EEPROM for known HID prefixes; writes $config_path/bom.
# Globals: BMC_VPD_EEPROM_BOM_SIZE, eeprom_file (defaults + optional /etc/…eeprom.conf), config_path.
#######################################
get_system_hw_bom()
{
	local num_bytes offset raw_data hid bom

	if [ -z "${config_path:-}" ]; then
		echo "[ERROR] config_path unset; cannot store bom"
		return 1
	fi
	if [ -z "${eeprom_file:-}" ] || [ ! -r "$eeprom_file" ]; then
		echo "[ERROR] eeprom_file not readable: ${eeprom_file:-<unset>}"
		return 1
	fi

	num_bytes=$BMC_VPD_EEPROM_BOM_SIZE
	offset=$(dd if="$eeprom_file" bs=1 count=128 2>/dev/null | strings -a -n 3 -t d | awk 'match($2, /V[0-9]-/) { print $1 + RSTART - 1; exit }')
	bom=""

	hid=$(tr -d '\r\n' < "${config_path}/hid")
	case "$hid" in
	HI189|HI190|HI191|HI192|HI193|HI183)
		if ! [[ "${offset:-}" =~ ^[0-9]+$ ]]; then
			echo "[WARNING] BOM offset not found in EEPROM (Vx- tag); skipping BOM parse"
			return 0
		fi
		raw_data=$(dd if="$eeprom_file" bs=1 skip="$offset" count="$num_bytes" 2>/dev/null | tr -d '\0') || true

		local -a data_array item_array
		IFS=$'\xff' read -r -a data_array <<< "$raw_data"
		for item_data in "${data_array[@]}"; do
			IFS=$' ' read -r -a item_array <<< "$item_data"
			bom=$bom${item_array[0]}
		done

		printf '%s\n' "$bom" > "${config_path}/bom"
		echo "System hardware BOM record is $bom"
		;;
	*)
		;;
	esac
}

#######################################
# Run pre/post init hook script supplied by the NOS (field workarounds until FW update).
# ARGUMENTS:
#   $1 — pre | post
# RETURN:
#   0
#######################################
run_hook()
{
	local hook_file hook_phase retval
	hook_file="/usr/local/bin/hw-management-bmc-fixup.sh"
	hook_phase=$1

	case "$hook_phase" in
	pre|post) ;;
	*)
		logger -t "bmc_ready_hook" -p daemon.err "run_hook: invalid argument '${hook_phase:-}', expected pre or post"
		return 1
		;;
	esac

	if [ ! -f "$hook_file" ]; then
		logger -t "bmc_ready_hook" -p daemon.info "No hook file, ${hook_phase} init hooks are not performed."
		return 0
	fi

	if [ ! -x "$hook_file" ]; then
		logger -t "bmc_ready_hook" -p daemon.info "File '$hook_file' is not executable. Changing permissions."
		chmod +x "$hook_file"
	fi

	mkdir -p /var/run/hw-management/config
	cp -f "$hook_file" /var/run/hw-management/config/last-executed-fixup.sh
	"$hook_file" "$hook_phase"
	retval=$?

	printf '%s\n' "$retval" >"/var/run/hw-management/config/fixup-status-${hook_phase}"
	if [ "$retval" -eq 0 ]; then
		logger -t "bmc_ready_hook" -p daemon.info "File '$hook_file' was executed successfully with parameter: ${hook_phase}."
	else
		logger -t "bmc_ready_hook" -p daemon.err "Execution of '$hook_file' with parameter ${hook_phase} failed with return value ${retval}."
	fi
	return 0
}

#######################################
# Chassis power state hook (stub — extend in platform code if needed).
#######################################
set_chassis_powerstate_on()
{
	:
}

#######################################
# Switch UART and power toward host CPU for error paths (temporary bus control).
# Uses: leak_detection_on_init, log_message (helpers-common); BMC_* sysfs paths and
# set_host_powerstate_on (helpers.sh). LOG_TAG should be set by the caller script.
# Redirects use unquoted BMC_* paths so hwmon* globs expand (see helpers.sh).
#######################################
bmc_to_cpu_tmp()
{
	if leak_detection_on_init; then
		log_message "warning" "A2D leakage at init; skipping temporary BMC to CPU (UART, power, control)"
		return
	fi
	# Switch UART to CPU.
	# shellcheck disable=SC2086
	echo 2 >$BMC_TO_CPU_UART
	log_message "info" "Switch console to the host CPU"
	# Power on CPU power domain through CPLD.
	# shellcheck disable=SC2086
	echo 0 >$BMC_CPU_PWR_ON
	log_message "info" "Power on the host CPU"
	set_chassis_powerstate_on
	set_host_powerstate_on
	# Temporary: set CPU as master of I2C tree and signal control.
	# shellcheck disable=SC2086
	echo 0 >$BMC_TO_CPU_CTRL
}

#######################################
# Same as bmc_to_cpu_tmp but does not write bmc_to_cpu_ctrl (normal boot path).
#######################################
bmc_to_cpu()
{
	if leak_detection_on_init; then
		log_message "warning" "A2D leakage at init; skipping BMC to CPU (UART, power, control)"
		return
	fi
	# Switch UART to CPU.
	# shellcheck disable=SC2086
	echo 2 >$BMC_TO_CPU_UART
	log_message "info" "Switch console to the host CPU"
	# Power on CPU power domain through CPLD.
	# shellcheck disable=SC2086
	echo 0 >$BMC_CPU_PWR_ON
	log_message "info" "Power on the host CPU"
	set_chassis_powerstate_on
	set_host_powerstate_on
}

bmc_init_bootargs()
{
       # Standalone BMC system, no system EEPROM.
	if [ ! -d /sys/class/net/eth1 ]; then
		fw_setenv bootargs "console=ttyS12,115200n8 root=/dev/ram rw earlycon"
	fi

	bootargs=$(fw_printenv bootargs)
	#if echo ${bootargs} | grep -q "ttyS2" && echo ${bootargs} | grep -q "46:44:8a:c8:7f:bf"; then
	#	return
	#fi
	if echo ${bootargs} | grep -q "46:44:8a:c8:7f:bf"; then
		return
	fi

	fw_setenv bootargs "console=ttyS12,115200n8 root=/dev/ram rw earlycon g_ether.host_addr=46:44:8a:c8:7f:bf g_ether.dev_addr=46:44:8a:c8:7f:bd"
}

# Removes ipmi permissions from a user (OpenBMC D-Bus user manager; not used on SONiC BMC).
remove_ipmitools_permissions()
{
    echo "Skipping ipmi permission change (no D-Bus user manager)"
    return 0
}

create_nosbmc_user()
{
    echo "Skipping nosbmc user setup (no D-Bus user manager)"
    return 0
}
