#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Ensure U-Boot ethaddr has a valid BMC MAC.
#
# A valid ethaddr is authoritative. The BMC FRU MAC is only a fallback when
# ethaddr is empty or invalid. After selecting the MAC, apply it to the running
# eth0 interface too so the current boot is fixed without waiting for a reboot.
################################################################################

EEPROM_BMC="/var/run/hw-management/eeprom/eeprom_bmc"
EEPROM_BMC_FALLBACK="/sys/bus/i2c/devices/4-0050/eeprom"

log()
{
	echo "sync-ethaddr: $*"
}

log_crit()
{
	log "CRITICAL: $*"
	if command -v logger >/dev/null 2>&1; then
		logger -p user.crit -t hw-management-bmc-sync-ethaddr "$*"
	fi
}

bring_eth0_up()
{
	local reason="$1"
	local i

	for i in 1 2 3; do
		if ip link set eth0 up 2>/dev/null; then
			if [ "$i" -gt 1 ]; then
				log "brought eth0 up on attempt ${i} (${reason})"
			fi
			return 0
		fi
		sleep 0.5
	done

	log_crit "failed to bring eth0 up after MAC change (${reason})"
	return 1
}

normalize_mac()
{
	local mac="$1"

	mac="${mac//-/:}"
	mac="$(echo "$mac" | tr '[:upper:]' '[:lower:]')"
	if [[ "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
		echo "$mac"
	fi
}

mac_first_octet()
{
	local mac="$1"
	local first="${mac%%:*}"

	printf "%d" "0x${first}"
}

is_valid_unicast_mac()
{
	local mac
	mac="$(normalize_mac "$1")"
	[ -n "$mac" ] || return 1

	case "$mac" in
	00:00:00:00:00:00|ff:ff:ff:ff:ff:ff)
		return 1
		;;
	esac

	local first
	first="$(mac_first_octet "$mac")"
	# Multicast bit set means the address is not a valid interface MAC.
	[ $((first & 1)) -eq 0 ]
}

is_local_admin_mac()
{
	local mac
	mac="$(normalize_mac "$1")"
	[ -n "$mac" ] || return 1

	local first
	first="$(mac_first_octet "$mac")"
	[ $((first & 2)) -ne 0 ]
}

extract_fru_mac_field()
{
	# Avoid awk {N} interval quantifiers; BusyBox awk may not support them.
	awk '
		match($0, /MAC:[[:space:]]*[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/) {
			mac = substr($0, RSTART, RLENGTH)
			sub(/^MAC:[[:space:]]*/, "", mac)
			print mac
			exit
		}
	'
}

wait_for_bmc_eeprom()
{
	local i

	for i in 1 2 3 4 5; do
		if find_bmc_eeprom; then
			return 0
		fi
		sleep 1
	done

	return 1
}

wait_for_bmc_eeprom_short()
{
	local i

	for i in 1 2 3 4 5; do
		if find_bmc_eeprom; then
			return 0
		fi
		sleep 0.2
	done

	return 1
}

find_bmc_eeprom()
{
	if [ -r "$EEPROM_BMC" ]; then
		echo "$EEPROM_BMC"
		return 0
	fi
	if [ -r "$EEPROM_BMC_FALLBACK" ]; then
		echo "$EEPROM_BMC_FALLBACK"
		return 0
	fi

	return 1
}

read_fru_mac()
{
	local eeprom="$1"
	local mac=""

	if command -v ipmi-fru >/dev/null 2>&1; then
		mac="$(ipmi-fru --fru-file="$eeprom" 2>/dev/null | extract_fru_mac_field)"
		if [ -n "$mac" ]; then
			echo "sync-ethaddr: FRU MAC read using ipmi-fru" >&2
		fi
	fi

	if [ -z "$mac" ] && command -v strings >/dev/null 2>&1; then
		mac="$(strings "$eeprom" 2>/dev/null | extract_fru_mac_field)"
		if [ -n "$mac" ]; then
			echo "sync-ethaddr: WARNING: FRU MAC read using strings fallback" >&2
		fi
	fi

	normalize_mac "$mac"
}

read_ethaddr_raw()
{
	local value=""

	if ! command -v fw_printenv >/dev/null 2>&1; then
		return 0
	fi

	value="$(fw_printenv -n ethaddr 2>/dev/null || true)"
	if [ -z "$value" ]; then
		value="$(fw_printenv ethaddr 2>/dev/null | sed -n 's/^ethaddr=//p')"
	fi

	echo "$value"
}

set_ethaddr()
{
	local mac="$1"

	if ! command -v fw_setenv >/dev/null 2>&1; then
		log "ERROR: fw_setenv is not available"
		return 1
	fi

	fw_setenv ethaddr "$mac"
}

clear_ethaddr()
{
	if ! command -v fw_setenv >/dev/null 2>&1; then
		log "WARNING: fw_setenv is not available; cannot clear invalid ethaddr"
		return 0
	fi

	fw_setenv ethaddr
}

uboot_env_tools_available()
{
	local missing=0

	if ! command -v fw_printenv >/dev/null 2>&1; then
		log "WARNING: fw_printenv is not available"
		missing=1
	fi

	if ! command -v fw_setenv >/dev/null 2>&1; then
		log "WARNING: fw_setenv is not available"
		missing=1
	fi

	return "$missing"
}

renew_eth0_dhcp()
{
	if command -v systemctl >/dev/null 2>&1; then
		systemctl start systemd-networkd 2>/dev/null || true
	fi

	if command -v networkctl >/dev/null 2>&1; then
		networkctl reload 2>/dev/null || true
		if networkctl renew eth0 2>/dev/null; then
			log "renewed eth0 DHCP using networkctl"
			return 0
		fi
	fi

	if command -v dhclient >/dev/null 2>&1; then
		dhclient -r eth0 2>/dev/null || true
		if dhclient eth0 2>/dev/null; then
			log "renewed eth0 DHCP using dhclient"
			return 0
		fi
	fi

	if command -v udhcpc >/dev/null 2>&1; then
		if udhcpc -q -n -i eth0 2>/dev/null; then
			log "renewed eth0 DHCP using udhcpc"
			return 0
		fi
	fi

	log "WARNING: could not renew eth0 DHCP automatically"
	return 0
}

apply_runtime_mac()
{
	local expected_mac="$1"
	local source="$2"
	local eth0_mac=""

	[ -r /sys/class/net/eth0/address ] || return 0
	eth0_mac="$(normalize_mac "$(cat /sys/class/net/eth0/address 2>/dev/null)")"
	[ -n "$eth0_mac" ] || return 0

	if [ "$eth0_mac" != "$expected_mac" ]; then
		log "WARNING: current eth0 MAC is ${eth0_mac}, ${source} MAC is ${expected_mac}"
		log "applying ${source} MAC to running eth0"
		if ! command -v ip >/dev/null 2>&1; then
			log "WARNING: ip command is not available; cannot update running eth0"
			return 0
		fi
		if ! ip link set eth0 down; then
			log "WARNING: failed to set eth0 down"
			return 0
		fi
		if ! ip link set eth0 address "$expected_mac"; then
			log "WARNING: failed to set eth0 MAC to ${expected_mac}"
			bring_eth0_up "MAC set failed; restoring link" || true
			return 0
		fi
		if ! bring_eth0_up "MAC updated"; then
			return 0
		fi
		renew_eth0_dhcp
	fi
}

handle_missing_fru()
{
	local env_raw="$1"
	local env_mac="$2"

	log "WARNING: BMC FRU MAC is missing or invalid"

	if [ -z "$env_raw" ]; then
		log "ethaddr is empty; leaving it empty so U-Boot can choose fallback"
		return 0
	fi

	if [ -z "$env_mac" ] || ! is_valid_unicast_mac "$env_mac"; then
		log "WARNING: clearing invalid ethaddr ${env_raw}"
		clear_ethaddr
		return 0
	fi

	if is_local_admin_mac "$env_mac"; then
		log "WARNING: clearing locally-administered ethaddr ${env_mac}"
		clear_ethaddr
		return 0
	fi
}

main()
{
	local eeprom=""
	local fru_mac=""
	local env_raw=""
	local env_mac=""

	log "starting"

	if ! uboot_env_tools_available; then
		log "WARNING: skipping ethaddr sync because U-Boot env tools are missing"
		log "complete"
		return 0
	fi

	env_raw="$(read_ethaddr_raw)"
	env_mac="$(normalize_mac "$env_raw")"

	if [ -n "$env_mac" ] && is_valid_unicast_mac "$env_mac" &&
	   ! is_local_admin_mac "$env_mac"; then
		log "preserving valid ethaddr ${env_mac}"
		if eeprom="$(wait_for_bmc_eeprom_short)"; then
			fru_mac="$(read_fru_mac "$eeprom")"
			if is_valid_unicast_mac "$fru_mac" && ! is_local_admin_mac "$fru_mac"; then
				if [ "$env_mac" != "$fru_mac" ]; then
					log "WARNING: ethaddr ${env_mac} differs from FRU MAC ${fru_mac}"
					log "WARNING: preserving ethaddr because it has priority"
				fi
			else
				log "WARNING: cannot compare ethaddr with missing, invalid, or LAA FRU MAC"
			fi
		else
			log "FRU EEPROM is not available after short wait; skip ethaddr/FRU comparison"
		fi
		apply_runtime_mac "$env_mac" "ethaddr"
		log "complete"
		return 0
	fi

	if [ -n "$env_raw" ]; then
		log "WARNING: ethaddr ${env_raw} is invalid or locally-administered"
	fi

	if ! eeprom="$(wait_for_bmc_eeprom)"; then
		log "WARNING: BMC FRU EEPROM is not available"
		handle_missing_fru "$env_raw" "$env_mac"
		return 0
	fi

	fru_mac="$(read_fru_mac "$eeprom")"
	if ! is_valid_unicast_mac "$fru_mac" || is_local_admin_mac "$fru_mac"; then
		if [ -n "$fru_mac" ]; then
			log "WARNING: BMC FRU MAC ${fru_mac} is invalid or locally-administered"
		fi
		handle_missing_fru "$env_raw" "$env_mac"
		return 0
	fi

	log "setting ethaddr to FRU fallback MAC ${fru_mac}"
	if ! set_ethaddr "$fru_mac"; then
		log_crit "failed to persist ethaddr ${fru_mac}; continuing best-effort"
	fi

	apply_runtime_mac "$fru_mac" "FRU fallback"
	log "complete"
	return 0
}

main "$@"
