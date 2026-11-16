#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Keep I2C devices in the host CPU power domain (e.g. AMD SB-TSI, i2c-15:0x4c)
# in step with host power. Since kernel 6.12.58 sbtsi_temp accesses the chip
# in probe(), so a client created while the host is off never binds and is
# never re-probed. "sync" instantiates the devices while the host is on and
# deletes them while it is off; "status" prints their bind state.
#
# Host off: system/pwr_down or pwr_button_halt reads 1 (CPU_OFF in
# hw-management-bmc-ready.sh), or the power-lost flag latched by
# hw-management-bmc-events.sh on CPU_UNEXP_POWER_OFF exists.
#
# Config: /etc/hw-management-bmc-host-i2c-devices.json, same schema as
# hw-management-bmc-early-i2c-devices.json.

CONFIG_FILE="${HOST_I2C_CONFIG:-/etc/hw-management-bmc-host-i2c-devices.json}"
SYS_DIR="${HOST_I2C_SYS_DIR:-/var/run/hw-management/system}"
POWER_LOST_FLAG="${HOST_I2C_POWER_LOST_FLAG:-/run/hw-management-bmc-host-power-lost}"
LOCK_FILE=/run/lock/hw-management-bmc-host-i2c-devices.lock
BIND_RETRIES="${HOST_I2C_BIND_RETRIES:-10}"
ATTR_WAIT_SEC="${HOST_I2C_ATTR_WAIT_SEC:-30}"

# shellcheck source=/dev/null
source /usr/bin/hw-management-bmc-json-parser.sh

log()
{
	logger -t hw-management-bmc-host-i2c -p "user.$1" -- "${*:2}"
}

attr_set()
{
	[ "$(cat "$SYS_DIR/$1" 2>/dev/null)" = "1" ]
}

host_is_on()
{
	! attr_set pwr_down && ! attr_set pwr_button_halt && [ ! -e "$POWER_LOST_FLAG" ]
}

dev_delete()
{
	printf '0x%02x\n' "$2" 2>/dev/null > "/sys/bus/i2c/devices/i2c-$1/delete_device"
}

# The driver core does not retry a failed probe; re-create the client until
# it binds, and do not leave an unbound client behind.
attach_one()
{
	local bus="$1" addr="$2" driver="$3" dev i
	dev=$(printf '/sys/bus/i2c/devices/%s-%04x' "$bus" "$addr")

	[ -e "$dev/driver" ] && return 0
	for ((i = 1; i <= BIND_RETRIES; i++)); do
		[ -e "$dev" ] && dev_delete "$bus" "$addr"
		printf '%s 0x%02x\n' "$driver" "$addr" 2>/dev/null > "/sys/bus/i2c/devices/i2c-$bus/new_device"
		if [ -e "$dev/driver" ]; then
			log info "attached $driver i2c-$bus:$(printf '0x%02x' "$addr") after $i probe(s)"
			return 0
		fi
		sleep 1
	done
	dev_delete "$bus" "$addr"
	log err "$driver i2c-$bus:$(printf '0x%02x' "$addr") did not bind after $BIND_RETRIES probes"
	return 1
}

detach_one()
{
	local bus="$1" addr="$2" driver="$3"
	[ -e "$(printf '/sys/bus/i2c/devices/%s-%04x' "$bus" "$addr")" ] || return 0
	dev_delete "$bus" "$addr" && log info "detached $driver i2c-$bus:$(printf '0x%02x' "$addr")"
}

status_one()
{
	local dev state
	dev=$(printf '/sys/bus/i2c/devices/%s-%04x' "$1" "$2")
	if [ ! -e "$dev" ]; then state=absent
	elif [ -e "$dev/driver" ]; then state=bound
	else state=unbound; fi
	printf '%s i2c-%s:0x%02x %s\n' "$3" "$1" "$2" "$state"
}

for_each_device()
{
	local count i dev_json bus addr driver rc=0

	count=$(json_count_nested_array "devices" < "$CONFIG_FILE")
	for ((i = 0; i < count; i++)); do
		dev_json=$(json_get_nested_array_element "devices" "$i" < "$CONFIG_FILE")
		bus=$(echo "$dev_json" | json_get_number "bus")
		addr=$(echo "$dev_json" | json_get_string "address")
		driver=$(echo "$dev_json" | json_get_string "driver")
		[ -n "$bus" ] && [ -n "$addr" ] && [ -n "$driver" ] || continue
		"$1" "$bus" "$((addr))" "$driver" || rc=1
	done
	return $rc
}

[ -f "$CONFIG_FILE" ] || exit 0
json_validate "$CONFIG_FILE" || { log err "invalid JSON: $CONFIG_FILE"; exit 1; }

case "${1:-}" in
status)
	for_each_device status_one
	;;
sync)
	# Serialize with other callers (ready.sh, powerctrl.sh, events.sh).
	exec 9>"$LOCK_FILE"
	flock 9
	# system/ links are created by the udev regio handler and may not exist
	# yet when hw-management-bmc-ready.sh runs early in boot.
	for ((i = 0; i < ATTR_WAIT_SEC; i++)); do
		[ -e "$SYS_DIR/pwr_down" ] && break
		sleep 1
	done
	if [ ! -e "$SYS_DIR/pwr_down" ]; then
		log err "$SYS_DIR/pwr_down not present after ${ATTR_WAIT_SEC}s"
		exit 1
	fi
	if host_is_on; then
		for_each_device attach_one
	else
		for_each_device detach_one
	fi
	;;
*)
	echo "Usage: $0 sync|status" >&2
	exit 1
	;;
esac
