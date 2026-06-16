#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Minimalistic leakage HW-vs-SW test.
#
# For every device in the A2D leakage JSON it prints the I2C/HW probe result
# next to what the SW runtime tree (/var/run/hw-management/leakage) actually
# represents, with a PASS/FAIL verdict; then the live reading vs thresholds per
# configured SW channel.
#
# Usage: hw-management-bmc-leakage-validate.sh [LEAKAGE_BASE] [CONFIG_JSON]
# Defaults: /var/run/hw-management/leakage  /etc/hw-management-bmc-a2d-leakage-config.json
# Exit: 0 if no FAIL rows, 1 otherwise.

LEAKAGE_BASE="${1:-${LEAKAGE_BASE:-/var/run/hw-management/leakage}}"
CONFIG_JSON="${2:-${CONFIG_JSON:-/etc/hw-management-bmc-a2d-leakage-config.json}}"

read_attr() { [ -e "$1" ] && tr -d '\r\n' <"$1" 2>/dev/null; }

# "0x49" -> "0049" (sysfs i2c client suffix)
hexsuf() { local a="${1#0x}"; a="${a#0X}"; printf '%04x' "$((16#$a))" 2>/dev/null; }

# raw*scale -> volts (empty on bad input)
to_volts() {
	awk -v r="$1" -v s="$2" 'BEGIN { if (r=="" || s=="" || (r+0)!=r || (s+0)!=s) exit 1; printf "%.3f", r*s }'
}

# DeviceType|Bus|Address|ChannelId tuples from the JSON (BusyBox-awk friendly).
parse_devices() {
	awk '
	function flush() { if (dt!="") printf "%s|%s|%s|%s\n", dt, bus, addr, ch; dt="";bus="";addr="";ch="" }
	/"DeviceType"/ { flush(); v=$0; sub(/.*"DeviceType"[ \t]*:[ \t]*"/,"",v); sub(/".*/,"",v); dt=v }
	/"Bus"/        { v=$0; sub(/.*"Bus"[ \t]*:[ \t]*/,"",v);  sub(/[^0-9].*/,"",v); bus=v }
	/"Address"/    { v=$0; sub(/.*"Address"[ \t]*:[ \t]*"/,"",v); sub(/".*/,"",v); addr=v }
	/"ChannelId"/  { v=$0; sub(/.*"ChannelId"[ \t]*:[ \t]*/,"",v); sub(/[^0-9].*/,"",v); ch=v }
	END { flush() }
	' "$1"
}

# I2C presence probe: ACK / no / n/a (no i2ctransfer).
i2c_probe() {
	command -v i2ctransfer >/dev/null 2>&1 || { echo "n/a"; return; }
	if i2ctransfer -f -y "$1" r1@"$2" >/dev/null 2>&1 ||
		i2ctransfer -f -y "$1" w0@"$2" r1 >/dev/null 2>&1; then
		echo "ACK"
	else
		echo "no"
	fi
}

# Build SW map: "bus:suffix -> i/j raw volts" from every leakage/*/*/input symlink.
SW_MAP=""
build_sw_map() {
	local link d j i rt key bus suf raw scale volts
	for link in "$LEAKAGE_BASE"/*/*/input; do
		[ -e "$link" ] || continue
		d=$(dirname "$link"); j=$(basename "$d"); i=$(basename "$(dirname "$d")")
		rt=$(readlink -f "$link" 2>/dev/null)
		key=$(printf '%s\n' "$rt" | tr '/' '\n' | grep -E '^[0-9]+-[0-9a-fA-F]{4}$' | head -1)
		bus=${key%-*}; suf=$(printf '%s' "${key#*-}" | tr 'A-F' 'a-f')
		raw=$(read_attr "$link")
		scale=$(read_attr "$d/scale")
		volts=$(to_volts "$raw" "$scale" 2>/dev/null)
		SW_MAP="${SW_MAP}${bus}:${suf}|${i}/${j}|${raw:- }|${volts:- }
"
	done
}

# Lookup SW row by bus:suffix -> "i/j|raw|volts" or empty.
sw_lookup() { printf '%s' "$SW_MAP" | awk -F'|' -v k="$1" '$1==k {print $2"|"$3"|"$4; exit}'; }

# Compact threshold verdict from runtime min/max/lwarn/lcrit.
status_for() {
	local i_j="$1" volts="$2"
	local base="$LEAKAGE_BASE/${i_j%/*}/${i_j#*/}"
	local mn mx lw lc
	mn=$(read_attr "$base/min"); mx=$(read_attr "$base/max")
	lw=$(read_attr "$base/lwarn"); lc=$(read_attr "$base/lcrit")
	awk -v v="$volts" -v mn="$mn" -v mx="$mx" -v lw="$lw" -v lc="$lc" 'BEGIN {
		if (v=="" || (v+0)!=v) { print "NO-READ"; exit }
		if (lc!="" && (lc+0)==lc && v<=lc+0) { print "LEAK-CRIT"; exit }
		if (lw!="" && (lw+0)==lw && v<=lw+0) { print "LEAK-WARN"; exit }
		if (mn!="" && (mn+0)==mn && v< mn+0) { print "BELOW-MIN"; exit }
		if (mx!="" && (mx+0)==mx && v> mx+0) { print "ABOVE-MAX(dry)"; exit }
		print "NORMAL"
	}'
}

# --- run ---------------------------------------------------------------------
echo "leakage HW/SW test  $(date 2>/dev/null)  host=$(hostname 2>/dev/null)"
echo "config=$CONFIG_JSON  leakage=$LEAKAGE_BASE"
[ -f "$CONFIG_JSON" ] || { echo "FAIL: config JSON not found"; exit 1; }
[ -d "$LEAKAGE_BASE" ] || echo "warn: leakage runtime dir missing ($LEAKAGE_BASE)"
build_sw_map

pass=0; fail=0; absent=0; i2c_present=0
echo
printf '%-8s %-3s %-6s %-3s %-5s %-12s %s\n' DEV BUS ADDR CH I2C SW-CHANNEL RESULT
printf '%s\n' "-------- --- ------ --- ----- ------------ ------"
while IFS='|' read -r dt bus addr ch; do
	[ -n "$dt" ] && [ -n "$bus" ] && [ -n "$addr" ] || continue
	probe=$(i2c_probe "$bus" "$addr")
	[ "$probe" = "ACK" ] && i2c_present=$((i2c_present + 1))
	suf=$(hexsuf "$addr")
	sw=$(sw_lookup "${bus}:${suf}")
	swch="${sw%%|*}"; [ -n "$swch" ] || swch="-"

	if [ "$probe" = "ACK" ] && [ "$swch" != "-" ]; then
		res="PASS"; pass=$((pass + 1))
	elif [ "$probe" = "ACK" ] && [ "$swch" = "-" ]; then
		res="FAIL (hw present, no sw)"; fail=$((fail + 1))
	elif [ "$probe" = "no" ] && [ "$swch" != "-" ]; then
		res="FAIL (sw link, hw gone)"; fail=$((fail + 1))
	elif [ "$probe" = "no" ]; then
		res="absent (not populated)"; absent=$((absent + 1))
	else
		# i2ctransfer unavailable: judge on SW only
		if [ "$swch" != "-" ]; then res="sw-ok (no i2c)"; pass=$((pass + 1)); else res="no sw"; fi
	fi
	printf '%-8s %-3s %-6s %-3s %-5s %-12s %s\n' \
		"$dt" "$bus" "$addr" "${ch:-def}" "$probe" "$swch" "$res"
done <<EOF
$(parse_devices "$CONFIG_JSON")
EOF

echo
printf '%-12s %-18s %-6s %-7s %-14s %s\n' SW-CHANNEL SOURCE RAW VOLTS STATUS THRESH
printf '%s\n' "------------ ------------------ ------ ------- -------------- ------"
sw_rows=0
for link in "$LEAKAGE_BASE"/*/*/input; do
	[ -e "$link" ] || continue
	sw_rows=$((sw_rows + 1))
	d=$(dirname "$link"); j=$(basename "$d"); i=$(basename "$(dirname "$d")")
	rt=$(readlink -f "$link" 2>/dev/null)
	src=$(basename "$rt" 2>/dev/null)
	raw=$(read_attr "$link"); scale=$(read_attr "$d/scale")
	volts=$(to_volts "$raw" "$scale" 2>/dev/null)
	st=$(status_for "$i/$j" "$volts")
	thr="min$(read_attr "$d/min")/max$(read_attr "$d/max")"
	printf '%-12s %-18s %-6s %-7s %-14s %s\n' \
		"$i/$j" "${src:-?}" "${raw:-?}" "${volts:-?}" "$st" "$thr"
done
[ "$sw_rows" -eq 0 ] && echo "(no SW channels with input)"

echo
echo "SUMMARY: i2c_present=$i2c_present sw_channels=$sw_rows  pass=$pass fail=$fail absent=$absent"
[ "$fail" -eq 0 ]
