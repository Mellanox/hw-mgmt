#!/bin/sh
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
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
need_eep=$SYSFS_EEPROM_COUNTER
max_wait=${BOOT_COMPLETE_MAX_WAIT_SEC:-1800}
poll=${BOOT_COMPLETE_POLL_SEC:-2}
POWER_LOST_FLAG="${BOOT_COMPLETE_POWER_LOST_FLAG:-/run/hw-management-bmc-host-power-lost}"

attr_set() {
	[ "$(cat "$SYS_DIR/$1" 2>/dev/null)" = "1" ]
}

# cpu_temp* exist only while the host is on; SYSFS_THERMAL_COUNTER_HOST_OFF
# applies while it is off (same definition as hw-management-bmc-host-i2c-devices.sh).
thermal_needed() {
	if [ -n "${SYSFS_THERMAL_COUNTER_HOST_OFF:-}" ] &&
	   { attr_set pwr_down || attr_set pwr_button_halt || [ -e "$POWER_LOST_FLAG" ]; }; then
		echo "$SYSFS_THERMAL_COUNTER_HOST_OFF"
	else
		echo "$SYSFS_THERMAL_COUNTER"
	fi
}

elapsed=0
while :; do
	c_sys=$(count_entries "$SYS_DIR")
	c_thr=$(count_entries "$THERMAL_DIR")
	c_eep=$(count_entries "$EEPROM_DIR")
	need_thr=$(thermal_needed)

	if [ "$c_sys" -ge "$need_sys" ] && [ "$c_thr" -ge "$need_thr" ] && [ "$c_eep" -ge "$need_eep" ]; then
		echo "hw-management-bmc-boot-complete: thresholds met (system=$c_sys>=$need_sys thermal=$c_thr>=$need_thr eeprom=$c_eep>=$need_eep)" >&2
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
