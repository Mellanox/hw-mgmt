#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# Common helper functions shared across switch BMC configurations

PLATFORM_CONFIG_FILE="/etc/platform_config"

# Default syslog tag for log_message(); set before sourcing this file to override.
: "${LOG_TAG:=hw-management-bmc}"

# Log via logger(1) (syslog / journal) and echo for console capture.
# Args: level (err, info, warning, or legacy ERROR, INFO, WARNING, …), then message
# (remaining words are joined into one message).
log_message() {
	local level="$1"
	shift
	local message="$*"
	local prio

	case "${level,,}" in
		emerg) prio=emerg ;;
		alert) prio=alert ;;
		crit|critical) prio=crit ;;
		err|error) prio=err ;;
		warning|warn) prio=warning ;;
		notice) prio=notice ;;
		info) prio=info ;;
		debug) prio=debug ;;
		*) prio=notice ;;
	esac

	logger -t "$LOG_TAG" -p "daemon.${prio}" "$message"
	echo "[$level] $message"
}

log_event()
{
	echo "$@" | systemd-cat -t hw-management-events -p info
}

log_cpld_dump()
{
    if [ -f "$PLATFORM_CONFIG_FILE" ]; then
        source "$PLATFORM_CONFIG_FILE"
    else
        CPLD_I2C_BUS=5
    fi

	local dump=""	
	for ((offset=0; offset<=240; offset+=1)); do
		hex_offset=$(printf "%02x" $offset)
		raw_output=$(i2ctransfer -f -y $CPLD_I2C_BUS w2@0x31 0x25 0x$hex_offset r1 2>/dev/null)
		byte=$(echo "$raw_output" | awk 'match($0, /0x[0-9a-fA-F]{2}/) {print substr($0, RSTART+2, 2)}')

		# Final validation
		if [[ $byte =~ ^[0-9a-fA-F]{2}$ ]]; then
			dump+=$(printf "%02x " "0x$byte" | tr '[:upper:]' '[:lower:]')
		elif [[ $byte == "ER" ]]; then
			dump+="ER "
		elif [[ $byte == "NA" ]]; then
			dump+="NA "
		else
			dump+="-- "
		fi
	done
	log_event "CPLD dump: ${dump}"
}

# Use mdio to print relevant registers for Marvell PHYs
print_marvell_related_registers()
{
	BUS=1e650018.mdio-1
	PHY=0

	PAGES="0 1 2 3 4 5 6 18"

	for p in $PAGES; do
		echo "================ PAGE $p ================"
		for r in $(seq 0 31); do
			printf "P%02d R%02x: " $p $r
			mdio $BUS mva $PHY raw $p:$r
		done
		echo
	done
}

print_realtek_related_registers()
{
	BUS=1e650000.mdio-1
	PHY=0x01

	PAGES="0 0xa42 0xa43 0xa46 0xd04 0xd08 0xe40 0xe41 0xe42 0xe43 0xe44"

	for p in $PAGES; do
		mdio $BUS phy $PHY raw 0x1f $p
		echo "================ PAGE $p ================"
		for r in $(seq 0 31); do
			printf "P%04x R%02x: " $p $r
			mdio $BUS phy $PHY raw $r
		done
		echo
	done
	mdio $BUS phy $PHY raw 0x1f 0x0
}

set_marvell_related_registers()
{
# 1. Force Marvell Specific Control to "Good" State
# Sets Auto-MDIX enabled, Polarity Correction enabled.
    mdio 1e650018.mdio-1 mva 0 raw copper:16 0x3060

# 2. Ensure Standard Advertisement is correct (Optional but recommended)
# Advertise 1000Base-T Full Duplex
    mdio 1e650018.mdio-1 mva 0 raw copper:9 0x0300
# Advertise 100/10 Full/Half
    mdio 1e650018.mdio-1 mva 0 raw copper:4 0x0de1

# 3. Restart Auto-Negotiation
# Bit 15=0 (No Reset), Bit 12=1 (AN Enable), Bit 9=1 (Restart AN) -> 0x1200 + Speed bits
# 0x1340 is the standard "Go" command.
    mdio 1e650018.mdio-1 mva 0 raw copper:0 0x1340

# Read the values and verify they are set correctly
    val=$(mdio 1e650018.mdio-1 mva 0 raw copper:9); echo "$val" | grep -q "0300" || echo "Verified: copper:9 FAILED (Read: $val)"
    val=$(mdio 1e650018.mdio-1 mva 0 raw copper:4); echo "$val" | grep -q "0de1" || echo "Verified: copper:4 FAILED (Read: $val)"

# Don't check coppers 16 and 0, because their's value can be changed by the device and that is ok.

}

bmc_init_check_link()
{
# Check if eth0 obtained a DHCP IPv4 address (not link-local)
    local iface="eth0"
    local attempt=1
    local max_attempts=5

    while [ $attempt -le $max_attempts ]; do

        # Current global IPv4 (exclude link-local)
        ip4="$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
        if [ -n "$ip4" ] && ! echo "$ip4" | grep -qE '^169\.254\.'; then
            # Verify ip4 came from systemd-networkd DHCP lease
            idx="$(cat /sys/class/net/"$iface"/ifindex 2>/dev/null)"
            if [ -n "$idx" ] && [ -f "/run/systemd/netif/leases/$idx" ]; then
                if grep -q "^ADDRESS=$ip4$" "/run/systemd/netif/leases/$idx"; then
                    echo "eth0 DHCP address: $ip4"
                    return 0
                fi
            fi
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

	# Check if eth0 has an IP address
	IP_ADDRESS=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}')
	if [ -n "$IP_ADDRESS" ]; then
		echo "eth0 IP address: $IP_ADDRESS"
	fi
    echo "eth0 did not obtain DHCP IPv4 address after $max_attempts attempts."
    return 1
}

load_and_reconfigure_ftgmac100()
{
	echo "Loading module ftgmac100"
	modprobe ftgmac100
	sleep 2
	print_marvell_related_registers
	print_realtek_related_registers
	set_marvell_related_registers
	sleep 1
	ip link set eth1 up || true
	ip link set eth0 up || true
	sleep 7
}

bmc_init_eth()
{
	local rc=1

	# Ensure MAC driver is present
	echo "Loading module ftgmac100"
	modprobe ftgmac100
	sleep 7

	# Step 1: First check that eth1 gains carrier (with retries and driver bounce)
	if [ ! -d /sys/class/net/eth1 ]; then
		echo "eth1 sysfs not found; aborting NIC init."
		return
	fi

	for ((i=0; i<2; i++)); do
		if [ "${i}" -gt 0 ]; then
			echo "Reloading ftgmac100 (retry ${i})"
			load_and_reconfigure_ftgmac100
		fi
		if ethtool eth1 2>/dev/null | grep -q "Link detected: yes"; then
			echo "Link detected on eth1"
			rc=0
			break
		fi
		echo "No carrier on eth1; current state:"
		ethtool eth1 || true
		echo "Bouncing eth1 and reloading ftgmac100..."
		ifconfig eth1 down >/dev/null 2>&1 || true
		modprobe -r ftgmac100 || true
		sleep 1
	done

	# Always leave driver loaded
	if ! lsmod | grep -q '^ftgmac100'; then
		echo "Reloading ftgmac100 (final)"
		load_and_reconfigure_ftgmac100
	fi
	if [ "${rc}" -ne 0 ]; then
		if ethtool eth1 2>/dev/null | grep -q "Link detected: yes"; then
			echo "Link detected on eth1 after retries"
			rc=0
		else
			echo "WARN: eth1 carrier not detected after retries; current state:"
		    ethtool eth1 || true
		fi
	fi

	# Optional: configure PHY LED if eth1 carrier is up
	if [ "${rc}" -eq 0 ]; then
		echo "Configuring PHY for LED"
		mdio 1e650018.mdio-1 mva 0x00 raw 3:17 0x4405
		mdio 1e650018.mdio-1 mva 0x00 raw 3:16 0x1117
	fi

	# Step 2: If DHCP is enabled on eth0 and no IP is obtained, do recovery with 2 retries
	# Older systemd: detect DHCP from status or .network files
	dhcp_enabled=0
	if networkctl status eth0 2>/dev/null | grep -qE 'DHCP4:\s*yes|DHCP:\s*yes'; then
		echo "Detected eth0 DHCP via networkctl status"
		dhcp_enabled=1
	else
		netfile=$(grep -REl '^\s*Name\s*=\s*eth0(\s|$)' /etc/systemd/network/*.network /lib/systemd/network/*.network 2>/dev/null | head -n1)
		if [ -n "$netfile" ] && grep -Eq '^\s*DHCP\s*=\s*(yes|ipv4|both|true)\b' "$netfile"; then
			echo "Detected eth0 DHCP in ${netfile}"
			dhcp_enabled=1
		else
			echo "DHCP not enabled for eth0 (no matching .network with DHCP)"
		fi
	fi
	if [ "${dhcp_enabled}" -eq 1 ]; then
		echo "eth0 has DHCP enabled; checking for IPv4 address"
		if bmc_init_check_link; then
			echo "eth0 obtained IP via DHCP"
		else
			echo "eth0 did not obtain IP via DHCP; attempting recovery (2 retries)"
			echo "eth0 MACAddress property: $(busctl introspect xyz.openbmc_project.Network /xyz/openbmc_project/network/eth0 xyz.openbmc_project.Network.MACAddress)"
			for ((r=1; r<=2; r++)); do
				echo "Recovery attempt ${r}: bouncing eth0 and renewing DHCP"
				ip link set eth0 down
				sleep 1
				ip link set eth0 up
				sleep 2
				# Try networkd first; if not managing, fall back to udhcpc
				systemctl start systemd-networkd || true
				networkctl reload || true
				idx=$(cat /sys/class/net/eth0/ifindex 2>/dev/null)
				if [ -n "$idx" ] && [ -e "/run/systemd/netif/links/$idx" ]; then
					echo "eth0 is managed by systemd-networkd (link ${idx}); renewing via networkctl"
					networkctl renew eth0 || true
				else
					echo "eth0 is not managed by systemd-networkd; attempting udhcpc fallback"
					udhcpc -q -n -i eth0 || true
				fi
				if bmc_init_check_link; then
					echo "eth0 obtained IP via DHCP after retry ${r}"
					break
				else
					echo "Retry ${r}: eth0 still has no IPv4 address"
				fi
			done
			# Final state snapshot
			echo "Final eth0 state after DHCP recovery attempts:"
			(ip -4 addr show dev eth0; ethtool eth0 2>/dev/null ) || true
		fi
	else
		echo "eth0 DHCP not enabled; skipping DHCP recovery"
	fi

}

# Read CPLD config1 register bits 2:0 (decimal) - management board revision / flavour.
# Prefer /var/run/hw-management/system/config1; fallback to i2ctransfer.
# Used to distinguish hid180 flavours (e.g. revision 3 => hi185-style leakage/rtc).
get_mgmt_board_revision() {
	local config1_val
	local config_file="/var/run/hw-management/system/config1"
	if [ -f "$config_file" ]; then
		config1_val=$(cat "$config_file" 2>/dev/null)
	else
		local raw
		raw=$(i2ctransfer -f -y 5 w2@0x31 0x25 0xfb r1 2>/dev/null | awk '{print $NF}')
		config1_val=$((raw))
	fi
	echo $((config1_val & 7))
}

# Per-A2D init-time leakage flags under /var/run/hw-management/system/leakage<n>
# (n = detector index). Value 0 means leakage was detected during init for that detector.
# Returns 0 (shell true) if any such file exists and reads 0 — caller must not hand over to CPU.
# Returns 1 if there is nothing to check or no detector reports 0.
leak_detection_on_init() {
	local system_dir="/var/run/hw-management/system"
	local f val

	if [ ! -d "$system_dir" ]; then
		return 1
	fi

	local leak_files
	shopt -s nullglob
	leak_files=( "$system_dir"/leakage[0-9]* )
	shopt -u nullglob

	for f in "${leak_files[@]}"; do
		[ -f "$f" ] || continue
		val=$(tr -d '[:space:]' <"$f" 2>/dev/null)
		if [ "$val" = "0" ]; then
			log_message "warning" "A2D leakage at init: ${f##*/}=0; blocking BMC to CPU (UART/power/control)"
			return 0
		fi
	done
	return 1
}
