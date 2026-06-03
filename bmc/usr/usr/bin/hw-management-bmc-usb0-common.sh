#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Shared usb0 (BMC <-> host CPU) helpers. Sourced by plat-specific-preps and
# hw-management-bmc-ready-common (do not execute directly).

HW_MANAGEMENT_BMC_USB0_CONF="/etc/hw-management-bmc-usb0.conf"
HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT="/etc/systemd/network/00-hw-management-bmc-usb0.network"

# Read KEY=value from /etc/hw-management-bmc-usb0.conf (first match, strip quotes).
_hw_management_bmc_usb0_conf_value()
{
	local key="$1"
	local conf="${2:-$HW_MANAGEMENT_BMC_USB0_CONF}"

	[ -n "$key" ] || return 1
	[ -f "$conf" ] || return 1
	sed -n "s/^[[:space:]]*${key}=//p" "$conf" | head -1 | tr -d " '\""
}

# True when the NOS (e.g. SONiC sonic-usb-network-init) owns usb0 addressing.
hw_management_bmc_usb0_managed_by_nos()
{
	local v

	v=$(_hw_management_bmc_usb0_conf_value USB0_MANAGED_BY_NOS)
	v=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
	case "$v" in
	1 | yes | true) return 0 ;;
	esac
	return 1
}
