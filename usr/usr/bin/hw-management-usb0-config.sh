#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Configure host usb0 from the resolved platform conf
# (/etc/<SKU>/hw-management-usb0.conf, else /etc/hw-management-usb0.conf).
# Called by hw-management-ifupdown.sh.
# Exit 0: this script owns usb0 (address applied). Caller must not ifup,
# even if the optional DHCP server failed — ifup cannot offer a BMC lease.
# Exit 1: conf absent/unusable or address not applied (caller may ifup).

source /usr/bin/hw-management-helpers.sh

CONF=$(host_usb0_conf_path)
IFACE="${1:-usb0}"
PIDFILE="/run/hw-management-usb0-dnsmasq.pid"
LEASEFILE="/run/hw-management-usb0.leases"

usb0_conf_value()
{
	local key="$1"
	[ -f "$CONF" ] || return 1
	sed -n "s|^[[:space:]]*${key}=||p" "$CONF" | head -1 | sed 's/[[:space:]]*#.*//' | tr -d " '\""
}

usb0_is_true()
{
	local v
	v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
	case "$v" in
	1 | yes | true) return 0 ;;
	esac
	return 1
}

cidr_to_netmask()
{
	local bits="${1#*/}"
	case "$bits" in
	8) printf '%s\n' "255.0.0.0" ;;
	16) printf '%s\n' "255.255.0.0" ;;
	24) printf '%s\n' "255.255.255.0" ;;
	30) printf '%s\n' "255.255.255.252" ;;
	*) printf '%s\n' "255.255.0.0" ;;
	esac
}

start_usb0_dhcp_server()
{
	local host_cidr="$1"
	local bmc_ip="$2"
	local host_ip netmask

	host_ip="${host_cidr%%/*}"
	bmc_ip="${bmc_ip%%/*}"
	netmask=$(cidr_to_netmask "$host_cidr")

	if ! command -v dnsmasq >/dev/null 2>&1; then
		log_err "USB0_DHCP_SERVER set but dnsmasq is not installed"
		return 1
	fi
	if [ -f "$PIDFILE" ]; then
		kill "$(cat "$PIDFILE")" 2>/dev/null || true
		rm -f "$PIDFILE"
	fi
	if ! dnsmasq --interface="$IFACE" --bind-interfaces --except-interface=lo \
		--listen-address="$host_ip" --port=0 \
		--dhcp-range="${bmc_ip},${bmc_ip},${netmask},12h" \
		--dhcp-option=3 \
		--pid-file="$PIDFILE" \
		--dhcp-leasefile="$LEASEFILE" \
		--conf-file=/dev/null; then
		log_err "failed to start usb0 DHCP server (dnsmasq)"
		return 1
	fi
	log_info "usb0 DHCP server: offer ${bmc_ip} on ${IFACE} (host ${host_ip})"
}

if [ ! -f "$CONF" ]; then
	exit 1
fi

addr=$(usb0_conf_value USB0_ADDRESS) || addr=""
bmc_addr=$(usb0_conf_value USB0_BMC_ADDRESS) || bmc_addr=""
dhcp_srv=$(usb0_conf_value USB0_DHCP_SERVER) || dhcp_srv=""

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
	log_info "usb0 host address ${addr} from ${CONF}"
else
	log_err "failed to set ${IFACE} ${addr}"
	exit 1
fi

# Address is applied: always exit 0 after this so ifup does not run.
# ifup cannot start a DHCP server; a failed dnsmasq must not hand usb0 back.
if usb0_is_true "$dhcp_srv"; then
	[ -n "$bmc_addr" ] || bmc_addr="169.254.100.1"
	dhcp_ok=0
	for i in 1 2 3 4 5; do
		if start_usb0_dhcp_server "$addr" "$bmc_addr"; then
			dhcp_ok=1
			break
		fi
		log_info "usb0 DHCP server start failed (attempt $i/5)"
		sleep 1
	done
	if [ "$dhcp_ok" -ne 1 ]; then
		log_err "usb0 DHCP server failed; BMC DHCP client will get no lease (not falling back to ifup)"
	fi
fi

exit 0
