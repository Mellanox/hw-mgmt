#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Shared usb0 (BMC <-> host CPU) helpers. Sourced by plat-specific-preps and
# hw-management-bmc-ready-common (do not execute directly).

HW_MANAGEMENT_BMC_USB0_CONF="/etc/hw-management-bmc-usb0.conf"
HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT="/etc/systemd/network/00-hw-management-bmc-usb0.network"
# Well-known paths for SONiC (or other NOS) to own usb0; checked before HID platform file.
HW_MANAGEMENT_BMC_USB0_NOS_CONF="/etc/bmc-network-sonic.conf"
HW_MANAGEMENT_BMC_USB0_NOS_CONF_ALT="/etc/bmc-usb-network.conf"

# Print path to installed NOS usb0 config, or return 1 if absent.
hw_management_bmc_usb0_nos_conf_path()
{
	if [ -f "$HW_MANAGEMENT_BMC_USB0_NOS_CONF" ]; then
		printf '%s\n' "$HW_MANAGEMENT_BMC_USB0_NOS_CONF"
		return 0
	fi
	if [ -f "$HW_MANAGEMENT_BMC_USB0_NOS_CONF_ALT" ]; then
		printf '%s\n' "$HW_MANAGEMENT_BMC_USB0_NOS_CONF_ALT"
		return 0
	fi
	return 1
}

# Read KEY=value from /etc/hw-management-bmc-usb0.conf (first match, strip quotes).
# key must be a fixed literal (no sed metacharacters); callers use USB0_* names only.
_hw_management_bmc_usb0_conf_value()
{
	local key="$1"
	local conf="${2:-$HW_MANAGEMENT_BMC_USB0_CONF}"

	[ -n "$key" ] || return 1
	[ -f "$conf" ] || return 1
	sed -n "s|^[[:space:]]*${key}=||p" "$conf" | head -1 | tr -d " '\""
}

# True when USB0_MANAGED_BY_NOS is set in the given conf (default: runtime usb0.conf).
hw_management_bmc_usb0_managed_by_nos_from()
{
	local v
	local conf="${1:-$HW_MANAGEMENT_BMC_USB0_CONF}"

	v=$(_hw_management_bmc_usb0_conf_value USB0_MANAGED_BY_NOS "$conf")
	v=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
	case "$v" in
	1 | yes | true) return 0 ;;
	esac
	return 1
}

# True when the NOS (e.g. SONiC sonic-usb-network-init) owns usb0 addressing.
hw_management_bmc_usb0_managed_by_nos()
{
	hw_management_bmc_usb0_managed_by_nos_from "$HW_MANAGEMENT_BMC_USB0_CONF"
}
