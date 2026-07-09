#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Ensure U-Boot ethaddr has a valid BMC MAC.
#
# A valid ethaddr is authoritative. The BMC FRU MAC is only a fallback when
# ethaddr is empty or invalid. The ftgmac100 driver reads eth0 MAC before late
# BMC services run, so setting ethaddr here primarily fixes the next boot.
################################################################################

EEPROM_BMC="/var/run/hw-management/eeprom/eeprom_bmc"
EEPROM_BMC_FALLBACK="/sys/bus/i2c/devices/4-0050/eeprom"

log()
{
	echo "sync-ethaddr: $*"
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
	awk '
		match($0, /MAC:[[:space:]]*([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/) {
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

warn_if_running_mac_differs()
{
	local expected_mac="$1"
	local source="$2"
	local eth0_mac=""

	[ -r /sys/class/net/eth0/address ] || return 0
	eth0_mac="$(normalize_mac "$(cat /sys/class/net/eth0/address 2>/dev/null)")"
	[ -n "$eth0_mac" ] || return 0

	if [ "$eth0_mac" != "$expected_mac" ]; then
		log "WARNING: current eth0 MAC is ${eth0_mac}, ${source} MAC is ${expected_mac}"
		log "WARNING: ethaddr policy may take effect only on next boot"
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

	log "Preserving existing valid ethaddr ${env_mac}"
}

main()
{
	local eeprom=""
	local fru_mac=""
	local env_raw=""
	local env_mac=""

	log "starting"

	env_raw="$(read_ethaddr_raw)"
	env_mac="$(normalize_mac "$env_raw")"

	if [ -n "$env_mac" ] && is_valid_unicast_mac "$env_mac" &&
	   ! is_local_admin_mac "$env_mac"; then
		log "preserving valid ethaddr ${env_mac}"
		if eeprom="$(find_bmc_eeprom)"; then
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
			log "FRU EEPROM is not available; skip ethaddr/FRU comparison"
		fi
		warn_if_running_mac_differs "$env_mac" "ethaddr"
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
		log "ERROR: failed to set ethaddr to ${fru_mac}"
		return 1
	fi

	warn_if_running_mac_differs "$fru_mac" "FRU fallback"
	log "complete"
}

main "$@"
