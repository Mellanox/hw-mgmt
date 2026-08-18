#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Configure host usb0 from /etc/hw-management-usb0.conf.
# Exit 0 if addressing was applied; exit 1 to fall back to ifup.

source /usr/bin/hw-management-helpers.sh

CONF="${HW_MANAGEMENT_USB0_CONF:-/etc/hw-management-usb0.conf}"
IFACE="${1:-usb0}"

if [ ! -f "$CONF" ]; then
	exit 1
fi

addr=$(sed -n 's/^[[:space:]]*USB0_ADDRESS=//p' "$CONF" | head -1 | sed 's/[[:space:]]*#.*//' | tr -d " '\"")
if [ -z "$addr" ] || ! printf '%s' "$addr" | grep -qE '^[0-9]+(\.[0-9]+){3}/[0-9]+$'; then
	log_info "hw-management-usb0-config: no valid USB0_ADDRESS in ${CONF}"
	exit 1
fi

if [ ! -e "/sys/class/net/${IFACE}" ]; then
	log_info "Interface ${IFACE} is missing"
	exit 0
fi

ip link set "$IFACE" up 2>/dev/null || true
if ip addr replace "$addr" dev "$IFACE" 2>/dev/null; then
	log_info "usb0 host address ${addr}"
	exit 0
fi
log_err "failed to set ${IFACE} ${addr}"
exit 1
