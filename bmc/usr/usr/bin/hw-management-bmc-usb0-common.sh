#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# SPDX-License-Identifier: BSD-3-Clause
#
# Shared usb0 (BMC <-> host CPU) helpers. Sourced by plat-specific-preps and
# hw-management-bmc-ready-common (do not execute directly).

HW_MANAGEMENT_BMC_USB0_CONF="/etc/hw-management-bmc-usb0.conf"
HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT="/etc/systemd/network/00-hw-management-bmc-usb0.network"
# Well-known paths for SONiC (or other NOS) to own usb0; checked before HID platform file.
HW_MANAGEMENT_BMC_USB0_NOS_CONF="/etc/bmc-network-sonic.conf"
HW_MANAGEMENT_BMC_USB0_NOS_CONF_ALT="/etc/bmc-usb-network.conf"
# Static fallback when USB0_MODE=static and USB0_ADDRESS is unset.
HW_MANAGEMENT_BMC_USB0_DEFAULT_STATIC="169.254.100.1/16"

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
	sed -n "s|^[[:space:]]*${key}=||p" "$conf" | head -1 | sed 's/[[:space:]]*#.*//' | tr -d " '\""
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

# Resolve USB0_MODE: none | dhcp | static.
# USB0_MANAGED_BY_NOS wins. Legacy conf with only USB0_ADDRESS is static.
# Otherwise default is dhcp (aligned with OpenBMC).
hw_management_bmc_usb0_resolve_mode()
{
	local conf="${1:-$HW_MANAGEMENT_BMC_USB0_CONF}"
	local mode addr

	if hw_management_bmc_usb0_managed_by_nos_from "$conf"; then
		printf '%s\n' "none"
		return 0
	fi
	mode=$(_hw_management_bmc_usb0_conf_value USB0_MODE "$conf")
	mode=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
	addr=$(_hw_management_bmc_usb0_conf_value USB0_ADDRESS "$conf")
	if [ -z "$mode" ]; then
		if [ -n "$addr" ]; then
			mode="static"
		else
			mode="dhcp"
		fi
	fi
	printf '%s\n' "$mode"
}

hw_management_bmc_usb0_write_dhcp_unit()
{
	local unit="${1:-$HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT}"

	mkdir -p "$(dirname "$unit")"
	rm -f "$unit"
	cat > "$unit" <<'EOF'
[Match]
Name=usb0

[Link]
RequiredForOnline=no

[Network]
DHCP=ipv4
LinkLocalAddressing=no
ConfigureWithoutCarrier=true

[DHCP]
UseDNS=false
UseNTP=false
UseHostname=false
UseRoutes=false
EOF
	chmod 0644 "$unit"
}

hw_management_bmc_usb0_write_static_unit()
{
	local addr="$1"
	local unit="${2:-$HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT}"

	mkdir -p "$(dirname "$unit")"
	rm -f "$unit"
	if [ -f /usr/etc/systemd/network/00-hw-management-bmc-usb0.network ]; then
		sed "s|__USB0_ADDRESS__|${addr}|g" /usr/etc/systemd/network/00-hw-management-bmc-usb0.network \
			>"$unit"
	else
		cat > "$unit" <<EOF
[Match]
Name=usb0

[Link]
RequiredForOnline=no

[Network]
DHCP=no
LinkLocalAddressing=no
ConfigureWithoutCarrier=true
Address=${addr}
EOF
	fi
	chmod 0644 "$unit"
}

# Render /etc/systemd/network/00-hw-management-bmc-usb0.network from runtime conf.
hw_management_bmc_usb0_render_network()
{
	local conf="${1:-$HW_MANAGEMENT_BMC_USB0_CONF}"
	local mode addr

	mode=$(hw_management_bmc_usb0_resolve_mode "$conf")
	case "$mode" in
	none)
		rm -f "$HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT"
		echo "plat-specific: USB0_MODE=none (or USB0_MANAGED_BY_NOS); no usb0 .network"
		;;
	dhcp)
		hw_management_bmc_usb0_write_dhcp_unit
		echo "plat-specific: wrote $HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT (usb0 DHCP client)"
		;;
	static)
		addr=$(_hw_management_bmc_usb0_conf_value USB0_ADDRESS "$conf")
		if [ -z "$addr" ] || ! printf '%s' "$addr" | grep -qE '^[0-9a-fA-F.:]+/[0-9]+$'; then
			addr="$HW_MANAGEMENT_BMC_USB0_DEFAULT_STATIC"
			echo "plat-specific: USB0_MODE=static; using default USB0_ADDRESS=${addr}"
		fi
		hw_management_bmc_usb0_write_static_unit "$addr"
		echo "plat-specific: wrote $HW_MANAGEMENT_BMC_USB0_NETWORK_UNIT (usb0 ${addr})"
		;;
	*)
		echo "plat-specific: unknown USB0_MODE=${mode}, skip usb0 .network" >&2
		;;
	esac
}
