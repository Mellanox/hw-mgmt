#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Leakage A2D config debugger — run on the BMC (as root) to find out WHY
# hw-management-bmc-a2d-leakage-config.sh did not configure any device.
#
# It does not change anything. It prints, side by side:
#   1. environment (user, PATH, i2c-tools availability)
#   2. deployed script "fingerprint" (which feature commits are actually on the box)
#   3. THE KEY CHECK: how many Device[] entries the deployed JSON parser counts per
#      detector (a count < the real number means the parser is truncating the array,
#      e.g. on the "]" of an inline "ChannelId": [..] value)
#   4. raw I2C presence probe of every configured Bus/Address (as the script probes)
#   5. i2cdetect of the configured buses
#   6. IIO devices + their in_voltage*_raw channels
#   7. ads1015/max1363 kernel module + dmesg state
#
# Usage: hw-management-bmc-leakage-debug.sh [CONFIG_JSON]
# Default CONFIG_JSON = /etc/hw-management-bmc-a2d-leakage-config.json

CONFIG="${1:-/etc/hw-management-bmc-a2d-leakage-config.json}"
PARSER=/usr/bin/hw-management-bmc-json-parser.sh
SCRIPT=/usr/bin/hw-management-bmc-a2d-leakage-config.sh
export PATH="/usr/sbin:/sbin:$PATH"

sec() { printf '\n==================== %s ====================\n' "$1"; }
# "0x49" -> "0049"
suf() { local a="${1#0x}"; a="${a#0X}"; printf '%04x' "$((16#$a))" 2>/dev/null; }

sec "1. environment"
echo "user        : $(id -un 2>/dev/null) (uid $(id -u 2>/dev/null))"
echo "PATH        : $PATH"
echo "i2ctransfer : $(command -v i2ctransfer 2>/dev/null || echo MISSING)"
echo "i2cdetect   : $(command -v i2cdetect 2>/dev/null || echo MISSING)"
echo "config json : $CONFIG $( [ -f "$CONFIG" ] && echo '(present)' || echo '(MISSING)')"
echo "parser      : $PARSER $( [ -f "$PARSER" ] && echo '(present)' || echo '(MISSING)')"
echo "config sh   : $SCRIPT $( [ -f "$SCRIPT" ] && echo '(present)' || echo '(MISSING)')"

sec "2. deployed script fingerprint (is the latest code on the box?)"
if [ -f "$SCRIPT" ]; then
	for m in "json_channelid_is_array" "json_channel_id_at" "json_channel_type_at" "json_type_threshold" "resolve_threshold" "json_has_channels_array" "ch_list" "usr/sbin:/sbin"; do
		if grep -q "$m" "$SCRIPT" 2>/dev/null; then echo "  HAS  : $m"; else echo "  MISS : $m"; fi
	done
else
	echo "  (config script not found)"
fi

sec "3. KEY CHECK — Device[] entries the parser actually counts"
if [ -f "$PARSER" ] && [ -f "$CONFIG" ]; then
	# shellcheck source=/dev/null
	. "$PARSER"
	ndet=$(json_count_array_elements "$CONFIG")
	echo "detectors counted: $ndet"
	i=0
	while [ "$i" -lt "${ndet:-0}" ]; do
		blk=$(json_get_array_element "$CONFIG" "$i")
		name=$(echo "$blk" | json_get_string "Name")
		[ -z "$name" ] && { i=$((i + 1)); continue; }
		nch=$(echo "$blk" | json_get_number "NumChnl")
		ndev=$(echo "$blk" | json_count_nested_array "Device")
		# real number of DeviceType keys in this block (ground truth)
		realdev=$(echo "$blk" | grep -c '"DeviceType"')
		flag=""
		[ "${ndev:-0}" != "${realdev:-0}" ] && flag="   <<< MISCOUNT (real=$realdev) — parser truncates Device[]"
		echo "detector[$i] $name  NumChnl=$nch  Device[]_counted=$ndev$flag"
		d=0
		while [ "$d" -lt "${ndev:-0}" ]; do
			dj=$(echo "$blk" | json_get_nested_array_element "Device" "$d")
			echo "    Device[$d]: $(echo "$dj" | json_get_string DeviceType) bus=$(echo "$dj" | json_get_number Bus) addr=$(echo "$dj" | json_get_string Address)"
			d=$((d + 1))
		done
		i=$((i + 1))
	done
	echo
	echo "If Device[]_counted < real, the script never sees the later Device entries"
	echo "(e.g. the ADS1015), so a missing first device => 'No A2D device found'."
else
	echo "  (parser or config missing — cannot run the key check)"
fi

sec "4. raw I2C presence probe per configured Bus/Address"
if ! command -v i2ctransfer >/dev/null 2>&1; then
	echo "  i2ctransfer missing — skipping"
else
	# device tuples straight from JSON text (ignores ChannelId arrays)
	awk '
	function flush(){ if(dt!=""&&bus!=""&&addr!="") printf "%s %s %s\n", dt, bus, addr; dt="";bus="";addr="" }
	/"DeviceType"/{flush(); v=$0; sub(/.*"DeviceType"[ \t]*:[ \t]*"/,"",v); sub(/".*/,"",v); dt=v}
	/"Bus"/{v=$0; sub(/.*"Bus"[ \t]*:[ \t]*/,"",v); sub(/[^0-9].*/,"",v); bus=v}
	/"Address"/{v=$0; sub(/.*"Address"[ \t]*:[ \t]*"/,"",v); sub(/".*/,"",v); addr=v}
	END{flush()}
	' "$CONFIG" | while read -r dt bus addr; do
		if i2ctransfer -f -y "$bus" w0@"$addr" r1 >/dev/null 2>&1 ||
			i2ctransfer -f -y "$bus" r1@"$addr" >/dev/null 2>&1; then
			st="ACK"
		else
			st="no-ack"
		fi
		cli="/sys/bus/i2c/devices/${bus}-$(suf "$addr")"
		if [ -d "$cli" ]; then
			drv="no-driver"
			[ -e "$cli/driver" ] && drv="driver=$(basename "$(readlink -f "$cli/driver" 2>/dev/null)")"
			sysinfo="sysfs-client($drv)"
		else
			sysinfo="no-sysfs-client"
		fi
		printf '  %-8s bus %-3s %-6s : i2c=%-7s %s\n' "$dt" "$bus" "$addr" "$st" "$sysinfo"
	done
fi

sec "5. i2cdetect of configured buses"
buses=$(awk '/"Bus"/{v=$0; sub(/.*"Bus"[ \t]*:[ \t]*/,"",v); sub(/[^0-9].*/,"",v); print v}' "$CONFIG" | sort -un)
if command -v i2cdetect >/dev/null 2>&1; then
	for b in $buses; do
		echo "-- bus $b --"
		i2cdetect -y -r "$b" 2>/dev/null || i2cdetect -y "$b" 2>/dev/null || echo "  (i2cdetect failed on bus $b)"
	done
else
	echo "  i2cdetect missing — skipping"
fi

sec "6. IIO devices (in_voltage*_raw)"
found=0
for d in /sys/bus/iio/devices/iio:device*; do
	[ -e "$d" ] || continue
	found=1
	p=$(readlink -f "$d/device" 2>/dev/null)
	printf '  %s -> %s\n     channels: ' "$d" "$(basename "$p" 2>/dev/null)"
	ls "$d" 2>/dev/null | grep -E '^in_voltage[0-9]+_raw$' | tr '\n' ' '
	echo
done
[ "$found" -eq 0 ] && echo "  (no IIO devices)"

sec "7. kernel modules / dmesg"
lsmod 2>/dev/null | grep -E 'ads1015|max1363' || echo "  (ads1015/max1363 not listed by lsmod)"
echo "  -- recent dmesg --"
dmesg 2>/dev/null | grep -iE 'ads1015|max1363|leak' | tail -n 20 || echo "  (no matching dmesg / no permission)"

echo
echo "==================== DONE ===================="
echo "Primary thing to read: section 3. Device[]_counted should equal the real"
echo "number of Device entries per detector (2). A MISCOUNT there is the root cause."
