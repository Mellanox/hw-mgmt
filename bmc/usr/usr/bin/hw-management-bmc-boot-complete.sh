#!/bin/sh
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Wait until /var/run/hw-management/{system,thermal,eeprom} each have at least
# the minimum entry counts from /etc/hw-management-bmc-boot-complete.conf (see
# bmc/usr/etc/<HID>/hw-management-bmc-boot-complete.conf in the package).
# Completing successfully signals SONiC BMC that downstream services may start.

set -e

CONF="${BOOT_COMPLETE_CONF:-/etc/hw-management-bmc-boot-complete.conf}"
SYS_DIR=/var/run/hw-management/system
THERMAL_DIR=/var/run/hw-management/thermal
EEPROM_DIR=/var/run/hw-management/eeprom

count_entries() {
	_d="$1"
	if [ ! -d "$_d" ]; then
		echo 0
		return
	fi
	# shellcheck disable=SC2012
	ls -A "$_d" 2>/dev/null | wc -l
}

# Atomic write for bmc/ primary reset_* (same temp+mv pattern as get-reset-cause.sh).
bmc_primary_reset_file_atomic() {
	_dir="$1"
	_name="$2"
	_value="$3"
	_dest="${_dir}/reset_${_name}"
	_tmp="${_dest}.tmp.$$"
	echo "${_value}" >"${_tmp}" || return 1
	mv -f "${_tmp}" "${_dest}"
}

# When CPLD reports auxiliary-power reset under system sysfs, prefer reset_pwr_cycle over
# ambiguous SCU-derived primary flags from early init (see hw-management-bmc-get-reset-cause.sh).
# Runs only after system sysfs is populated (boot-complete gate). HI189 uses reset_aux_pwr_or_fu;
# other platforms may expose reset_aux_pwr_or_ref.
bmc_reset_cause_apply_aux_pwr_correction() {
	aux_attr=""
	aux_val=""

	for attr in reset_aux_pwr_or_ref reset_aux_pwr_or_fu; do
		_f="${SYS_DIR}/${attr}"
		if [ ! -r "${_f}" ]; then
			continue
		fi
		if ! read -r aux_val _ <"${_f}" 2>/dev/null; then
			continue
		fi
		case "${aux_val}" in
		1)
			aux_attr="${attr}"
			break
			;;
		esac
	done

	[ -n "${aux_attr}" ] || return 0

	bmc_dir=/var/run/hw-management/bmc
	if [ ! -d "${bmc_dir}" ]; then
		return 0
	fi

	_changed=0
	# Clear non-pwr_cycle primaries first so readers never see two active flags at once.
	for primary in soft_reboot unknown; do
		_f="${bmc_dir}/reset_${primary}"
		[ -f "${_f}" ] || continue
		if read -r _v _ <"${_f}" 2>/dev/null && [ "${_v}" = "1" ]; then
			if bmc_primary_reset_file_atomic "${bmc_dir}" "${primary}" 0 2>/dev/null; then
				_changed=1
				echo "hw-management-bmc-boot-complete: ${aux_attr}=1, cleared reset_${primary}" >&2
			fi
		fi
	done

	_f="${bmc_dir}/reset_pwr_cycle"
	if [ -f "${_f}" ]; then
		if ! read -r _v _ <"${_f}" 2>/dev/null || [ "${_v}" != "1" ]; then
			if bmc_primary_reset_file_atomic "${bmc_dir}" pwr_cycle 1 2>/dev/null; then
				_changed=1
				echo "hw-management-bmc-boot-complete: ${aux_attr}=1, set reset_pwr_cycle=1 (was ${_v:-?})" >&2
			fi
		fi
	fi

	[ "${_changed}" -eq 1 ] || echo "hw-management-bmc-boot-complete: ${aux_attr}=1, primary already reset_pwr_cycle" >&2

	return 0
}

if [ ! -f "$CONF" ]; then
	echo "hw-management-bmc-boot-complete: missing $CONF" >&2
	exit 1
fi
# shellcheck disable=SC1090
. "$CONF"

: "${SYSFS_SYSTEM_COUNTER:?SYSFS_SYSTEM_COUNTER missing in $CONF}"
: "${SYSFS_THERMAL_COUNTER:?SYSFS_THERMAL_COUNTER missing in $CONF}"
: "${SYSFS_EEPROM_COUNTER:?SYSFS_EEPROM_COUNTER missing in $CONF}"

need_sys=$SYSFS_SYSTEM_COUNTER
need_thr=$SYSFS_THERMAL_COUNTER
need_eep=$SYSFS_EEPROM_COUNTER
max_wait=${BOOT_COMPLETE_MAX_WAIT_SEC:-1800}
poll=${BOOT_COMPLETE_POLL_SEC:-2}

elapsed=0
while :; do
	c_sys=$(count_entries "$SYS_DIR")
	c_thr=$(count_entries "$THERMAL_DIR")
	c_eep=$(count_entries "$EEPROM_DIR")

	if [ "$c_sys" -ge "$need_sys" ] && [ "$c_thr" -ge "$need_thr" ] && [ "$c_eep" -ge "$need_eep" ]; then
		echo "hw-management-bmc-boot-complete: thresholds met (system=$c_sys>=$need_sys thermal=$c_thr>=$need_thr eeprom=$c_eep>=$need_eep)" >&2
		bmc_reset_cause_apply_aux_pwr_correction || true
		exit 0
	fi

	if [ "$elapsed" -eq 0 ] || [ $((elapsed % 60)) -eq 0 ]; then
		if [ "$max_wait" -eq 0 ]; then
			lim_disp="no limit"
		else
			lim_disp="${max_wait}s"
		fi
		echo "hw-management-bmc-boot-complete: waiting system=$c_sys/$need_sys thermal=$c_thr/$need_thr eeprom=$c_eep/$need_eep (${elapsed}s / ${lim_disp})" >&2
	fi

	if [ "$max_wait" -gt 0 ] && [ "$elapsed" -ge "$max_wait" ]; then
		echo "hw-management-bmc-boot-complete: timeout after ${max_wait}s (system=$c_sys/$need_sys thermal=$c_thr/$need_thr eeprom=$c_eep/$need_eep)" >&2
		exit 1
	fi

	sleep "$poll"
	elapsed=$((elapsed + poll))
done
