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
################################################################################

# Deployed by hw-management-bmc-early-config from usr/etc/<HID>/hw-management-bmc-a2d-leakage-config.json
# Override: HW_MANAGEMENT_BMC_A2D_LEAKAGE_CONFIG=/path/to.json
CONFIG_FILE="${HW_MANAGEMENT_BMC_A2D_LEAKAGE_CONFIG:-/etc/hw-management-bmc-a2d-leakage-config.json}"
LOG_TAG="a2d_config"

# i2c-tools (i2ctransfer/i2cdetect) live in /usr/sbin; ensure they are reachable even
# when invoked from a login shell whose PATH omits sbin (e.g. a manual root run).
case ":$PATH:" in
*:/usr/sbin:*) ;;
*) PATH="/usr/sbin:/sbin:$PATH" ;;
esac
export PATH

# Source JSON parser library
if [ -f /usr/bin/hw-management-bmc-json-parser.sh ]; then
	source /usr/bin/hw-management-bmc-json-parser.sh
elif [ -f ./hw-management-bmc-json-parser.sh ]; then
	source ./hw-management-bmc-json-parser.sh
else
	echo "ERROR: hw-management-bmc-json-parser.sh not found"
	exit 1
fi

if [ -f /usr/bin/hw-management-bmc-helpers.sh ]; then
	# shellcheck source=/dev/null
	source /usr/bin/hw-management-bmc-helpers.sh
fi
if ! type check_n_link >/dev/null 2>&1; then
	check_n_link()
	{
		[ -f "$1" ] && ln -sf "$1" "$2"
	}
fi

# Function to check dependencies
check_dependencies()
{
	if ! command -v i2ctransfer >/dev/null 2>&1; then
		log_message "err" "i2ctransfer not found in PATH ($PATH). Install i2c-tools and run as root (it lives in /usr/sbin)."
		return 1
	fi

	if ! command -v awk >/dev/null 2>&1; then
		log_message "err" "awk is not installed. Cannot parse JSON configuration."
		return 1
	fi

	log_message "info" "Using awk for JSON parsing (BusyBox compatible)"
	return 0
}

# Function to check if configuration file exists
check_config_file()
{
	if [ ! -f "$CONFIG_FILE" ]; then
		log_message "err" "Configuration file not found: $CONFIG_FILE"
		return 1
	fi

	# Validate JSON using library function
	if ! json_validate "$CONFIG_FILE"; then
		log_message "err" "Invalid JSON in configuration file: $CONFIG_FILE"
		return 1
	fi

	log_message "info" "Configuration file found and validated: $CONFIG_FILE"
	return 0
}

# Optional JSON field "Probe": true — bind kernel driver (new_device) for IIO sysfs links.
# MAX1363/ADS1015/ADS7924: bind driver (probe runs), then program registers via i2ctransfer -f
# while the driver stays bound so our values are the last writer after probe.
# JSON booleans are unquoted (true/false); json_get_string only sees quoted values — use json_get_bool.
json_probe_true()
{
	local json="$1"
	local v
	v=$(echo "$json" | json_get_bool "Probe" 2>/dev/null) || true
	[ -n "$v" ] || return 1
	v=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
	v=$(printf '%s' "$v" | tr -d "\"'")
	[ "$v" = "true" ] || [ "$v" = "1" ] || [ "$v" = "yes" ]
}

# Map DeviceType to Linux i2c driver name for /sys/.../i2c-<bus>/new_device
# Alternatives: JSON Device[] order is strict — first alternative that passes presence + configure_device
# wins; the next entries are not tried. TI-vs-MAX register heuristics are unreliable when both drivers
# can bind; optional HW_MANAGEMENT_BMC_A2D_USE_ADS_HEURISTIC=1 restores the old MAX skip when the bus
# looks like ADS1015 (legacy).
kernel_driver_for_type()
{
	case "$1" in
	MAX1363) echo "max1363" ;;
	ADS1015) echo "ads1015" ;;
	ADS7924) echo "ads7924" ;;
	*) echo "" ;;
	esac
}

# Instantiate device on I2C bus so the kernel driver binds (when Probe is true).
# If the client already exists with a driver, skip. If the client exists without
# a driver (e.g. after manual unbind), bind via the driver bind sysfs node.
bind_kernel_driver()
{
	local bus="$1" address="$2" device_type="$3"
	local driver
	driver=$(kernel_driver_for_type "$device_type")
	if [ -z "$driver" ]; then
		log_message "warning" "No kernel driver mapping for $device_type — skipping bind"
		return 0
	fi
	local adapter="/sys/bus/i2c/devices/i2c-${bus}"
	if [ ! -d "$adapter" ]; then
		log_message "warning" "I2C adapter not found: $adapter — skipping bind"
		return 1
	fi
	local a="${address#0x}"
	a="${a#0X}"
	local dev_id bind_file
	dev_id=$(printf '%d-%04x' "$bus" $((16#$a)))
	bind_file="/sys/bus/i2c/drivers/${driver}/bind"
	if [ -d "/sys/bus/i2c/devices/$dev_id" ]; then
		if i2c_client_has_bound_driver "$bus" "$address"; then
			log_message "info" "I2C device $dev_id already present with driver bound"
			return 0
		fi
		log_message "info" "I2C device $dev_id present without driver — binding $driver"
		if [ -f "$bind_file" ] && echo "$dev_id" >"$bind_file" 2>/dev/null; then
			sleep 0.5
			return 0
		fi
		log_message "warning" "Bind $driver to $dev_id failed (client present, driver not attached)"
		return 1
	fi
	log_message "info" "Binding $driver at $address on bus $bus (new_device)"
	if ! echo "$driver $address" > "${adapter}/new_device" 2>/dev/null; then
		log_message "warning" "new_device failed for $driver $address on i2c-$bus (driver missing or device conflict) — continuing with raw I2C config"
		return 1
	fi
	sleep 0.5
	return 0
}

# Release driver so i2ctransfer can program device registers (I2C client node remains).
unbind_kernel_driver()
{
	local bus="$1" address="$2"
	local suf devpath driver_name unbind_file dev_id

	suf=$(i2c_addr_sysfs_suffix "$address") || return 1
	devpath="/sys/bus/i2c/devices/${bus}-${suf}"
	[ -L "$devpath/driver" ] || return 0
	driver_name=$(basename "$(readlink "$devpath/driver" 2>/dev/null)" 2>/dev/null) || return 1
	unbind_file="/sys/bus/i2c/drivers/${driver_name}/unbind"
	[ -f "$unbind_file" ] || return 1
	dev_id=$(basename "$devpath")
	if ! echo "$dev_id" >"$unbind_file" 2>/dev/null; then
		log_message "warning" "Failed to unbind $driver_name from $dev_id (Bus $bus, Addr $address) — cannot program registers via raw I2C"
		return 1
	fi
	log_message "info" "Unbound $driver_name from $dev_id for raw register programming"
	sleep 0.2
	return 0
}

# Re-attach driver after raw I2C programming (uses bind, not new_device).
rebind_kernel_driver()
{
	local bus="$1" address="$2" device_type="$3"
	local driver suf dev_id bind_file

	driver=$(kernel_driver_for_type "$device_type")
	[ -n "$driver" ] || return 1
	suf=$(i2c_addr_sysfs_suffix "$address") || return 1
	dev_id="${bus}-${suf}"
	bind_file="/sys/bus/i2c/drivers/${driver}/bind"
	[ -f "$bind_file" ] || return 1
	if echo "$dev_id" >"$bind_file" 2>/dev/null; then
		log_message "info" "Rebound $driver to $dev_id after register programming"
		sleep 0.5
		return 0
	fi
	log_message "warning" "Rebind $driver to $dev_id failed"
	return 1
}

# sysfs name for /sys/bus/i2c/devices/<bus>-<addr> (4-digit hex address).
i2c_addr_sysfs_suffix()
{
	local a="${1#0x}"
	a="${a#0X}"
	[ -n "$a" ] || return 1
	printf '%04x' "$((16#$a))"
}

# True if kernel has registered this client (helps when i2ctransfer fails under a bound driver).
probe_i2c_sysfs_present()
{
	local bus="$1"
	local addr="$2"
	local suf devpath

	suf=$(i2c_addr_sysfs_suffix "$addr") || return 1
	devpath="/sys/bus/i2c/devices/${bus}-${suf}"
	if [ -d "$devpath" ]; then
		log_message info "I2C device present in sysfs: $devpath (use correct Bus vs i2c-N from i2cdetect -l)"
		return 0
	fi
	return 1
}

# True if a kernel driver is bound to this I2C client (raw i2ctransfer to the address usually fails).
i2c_client_has_bound_driver()
{
	local bus="$1"
	local addr="$2"
	local suf devpath

	suf=$(i2c_addr_sysfs_suffix "$addr") || return 1
	devpath="/sys/bus/i2c/devices/${bus}-${suf}"
	[ -L "$devpath/driver" ] && return 0
	return 1
}

# Function to probe I2C device
probe_i2c_device()
{
	local bus="$1"
	local addr="$2"

	# Try to read from device to check if it exists
	# Repeated start with no data write may not be supported by all devices,
	# so we attempt both write-read and read-only methods.
	if i2ctransfer -f -y "$bus" w0@"$addr" r1 >/dev/null 2>&1 || i2ctransfer -f -y "$bus" r1@"$addr" >/dev/null 2>&1; then
		return 0
	fi
	# Driver may own the adapter; raw probe can fail while the device still exists.
	if probe_i2c_sysfs_present "$bus" "$addr"; then
		return 0
	fi
	return 1
}

# Parse two 0xNN bytes from i2ctransfer output (first two matches).
i2c_parse_two_bytes()
{
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -oE '0x[0-9a-f]{1,2}' | head -2 | tr '\n' ' '
}

# First 0xNN token from i2ctransfer line.
i2c_first_hex_byte()
{
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -oE '0x[0-9a-f]{1,2}' | head -1
}

# TI ADS1015/ADS1115 family: pointer register then 16-bit big-endian data (see TI SBAS173).
# This is a register-signature probe (not a bare I2C ACK): pointer 0x00 single-byte read must not
# be the MAX1363-style 0x7f quirk, then pointer 0x01 returns two config bytes that are not 0xff 0xff.
# Used to classify ADS1015 vs MAX1363, and (when HW_MANAGEMENT_BMC_A2D_USE_ADS_HEURISTIC is set) to
# reject MAX/ADS7924 candidates that match the ADS1015/1115 pointer+config pattern at the same address.
discover_ads1015_at()
{
	local bus="$1"
	local addr="$2"
	local sb out b1 b2

	sb=$(i2ctransfer -f -y "$bus" w1@"$addr" 0x00 r1 2>/dev/null) || return 1
	sb=$(i2c_first_hex_byte "$sb")
	if [ "$sb" = "0x7f" ]; then
		return 1
	fi

	out=$(i2ctransfer -f -y "$bus" w1@"$addr" 0x01 r2 2>/dev/null) || return 1
	set -- $(i2c_parse_two_bytes "$out")
	b1="$1"
	b2="$2"
	[ -n "$b1" ] && [ -n "$b2" ] || return 1
	if [ "$b1" = "0xff" ] && [ "$b2" = "0xff" ]; then
		return 1
	fi
	return 0
}

# Relaxed: skip 0x7f single-byte guard; use Conversion register (pointer 0x00, 2 bytes) only — not Config alone,
# so a MAX1363 that tripped the 0x7f guard is not re-classified as ADS1015 via config bytes alone.
discover_ads1015_relaxed_at()
{
	local bus="$1"
	local addr="$2"
	local out b1 b2

	out=$(i2ctransfer -f -y "$bus" w1@"$addr" 0x00 r2 2>/dev/null) || return 1
	set -- $(i2c_parse_two_bytes "$out")
	b1="$1"
	b2="$2"
	[ -n "$b1" ] && [ -n "$b2" ] || return 1
	if [ "$b1" = "0xff" ] && [ "$b2" = "0xff" ]; then
		return 1
	fi
	return 0
}

# MAX1363 / other non-ADS entries: presence only. (Optional legacy: reject MAX when bus looks like ADS1015.)
device_entry_matches_hw()
{
	local bus="$1"
	local address="$2"
	local device_type="$3"

	if ! probe_i2c_device "$bus" "$address"; then
		return 1
	fi

	case "$device_type" in
	MAX1363)
		if [ "${HW_MANAGEMENT_BMC_A2D_USE_ADS_HEURISTIC:-0}" != 0 ] && discover_ads1015_at "$bus" "$address"; then
			log_message "info" "Discovery: bus $bus addr $address responds like ADS1015, not MAX1363 (ADS heuristic) — trying next alternative"
			return 1
		fi
		log_message "info" "Discovery: bus $bus addr $address selected as MAX1363 (presence OK)"
		return 0
		;;
	ADS7924)
		# Optional: skip if discover_ads1015_at succeeds — that means pointer 0x00/0x01 behavior matches
		# TI ADS1015/1115 (see discover_ads1015_at), not a generic "another device ACKed" test.
		if [ "${HW_MANAGEMENT_BMC_A2D_USE_ADS_HEURISTIC:-0}" != 0 ] && discover_ads1015_at "$bus" "$address"; then
			log_message "info" "Discovery: bus $bus addr $address responds like ADS1015, not ADS7924 (ADS heuristic) — trying next alternative"
			return 1
		fi
		log_message "info" "Discovery: bus $bus addr $address selected as ADS7924 (presence OK)"
		return 0
		;;
	*)
		return 0
		;;
	esac
}

# First Device block in this detector with DeviceType MAX1363 (template for ADS1015 → MAX1363 fallback).
detector_first_max1363_json()
{
	local detector_block="$1"
	local num d j dt

	num=$(echo "$detector_block" | json_count_nested_array "Device")
	d=0
	while [ "$d" -lt "$num" ]; do
		j=$(echo "$detector_block" | json_get_nested_array_element "Device" "$d")
		dt=$(echo "$j" | json_get_string "DeviceType")
		if [ "$dt" = "MAX1363" ]; then
			printf '%s' "$j"
			return 0
		fi
		d=$((d + 1))
	done
	return 1
}

# Apply Bus/Address from the alternate-address part (same detector, two Device entries in JSON).
overlay_max1363_template_bus_addr()
{
	local template="$1"
	local bus="$2"
	local address="$3"

	printf '%s\n' "$template" | sed \
		-e "s/\"Bus\":[[:space:]]*[0-9][0-9]*/\"Bus\": $bus/" \
		-e "s/\"Address\":[[:space:]]*\"0x[0-9A-Fa-f][0-9A-Fa-f]*\"/\"Address\": \"$address\"/"
}

# Resolve ADS1015 entry: config read → use ADS1015 JSON; relaxed → ADS1015 JSON; else MAX1363 template at same bus/addr.
resolve_ads1015_device_entry()
{
	local detector_block="$1"
	local device_json="$2"
	local bus="$3"
	local address="$4"
	local max_t merged

	if ! probe_i2c_device "$bus" "$address"; then
		return 1
	fi
	if discover_ads1015_at "$bus" "$address"; then
		log_message "info" "Discovery: bus $bus addr $address matches ADS1015 (config register read)"
		printf '%s' "$device_json"
		return 0
	fi
	if [ "${HW_MANAGEMENT_BMC_A2D_ADS1015_RELAXED:-0}" != 0 ] && discover_ads1015_relaxed_at "$bus" "$address"; then
		log_message "info" "Discovery: bus $bus addr $address matches ADS1015 (relaxed; HW_MANAGEMENT_BMC_A2D_ADS1015_RELAXED)"
		printf '%s' "$device_json"
		return 0
	fi
	max_t=$(detector_first_max1363_json "$detector_block") || true
	if [ -z "$max_t" ]; then
		log_message "info" "Discovery: bus $bus addr $address — not ADS1015 by register probe and no MAX1363 template in detector"
		return 1
	fi
	merged=$(overlay_max1363_template_bus_addr "$max_t" "$bus" "$address")
	log_message "info" "Discovery: bus $bus addr $address — not ADS1015; using MAX1363 init from first Device in this detector"
	printf '%s' "$merged"
	return 0
}

# Concatenate hex bytes from i2ctransfer output or space-separated 0xNN list (lowercase, no separators).
i2c_readback_hex_concat()
{
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -oE '0x[0-9a-f]{1,2}' | sed 's/^0x//' | tr -d '\n'
}

# AND a concatenated hex string (2 chars per byte) with a space-separated 0xNN mask list.
# Used to ignore volatile/status bits during readback verify (e.g. ADS1015 Config OS bit).
# Mask shorter than data: trailing bytes pass through unmasked.
hex_concat_apply_mask()
{
	local data="$1"
	local byte mb pos=0 out="" n=${#data}

	# Expect whole bytes (2 hex chars each). On malformed odd-length input, return the data
	# unmasked so the caller's compare stays byte-exact and still flags a mismatch (fail-safe:
	# never hide a real difference behind a partial-byte mask).
	if [ $((n % 2)) -ne 0 ]; then
		printf '%s' "$data"
		return
	fi

	set -f
	set -- $2
	set +f
	while [ "$pos" -lt "$n" ]; do
		byte="${data:$pos:2}"
		if [ -n "$1" ]; then
			mb="${1#0x}"
			mb="${mb#0X}"
			out="$out$(printf '%02x' $((16#$byte & 16#$mb)))"
			shift
		else
			out="$out$byte"
		fi
		pos=$((pos + 2))
	done
	printf '%s' "$out"
}

# Function to write and verify register
# Optional 7th arg: per-byte verify mask (space-separated 0xNN). Bits cleared in the mask
# are ignored on readback compare — needed for registers with volatile/read-only bits.
write_and_verify_register()
{
	local bus="$1"
	local addr="$2"
	local reg="$3"
	local reg_val="$4"
	local reg_name="$5"
	local device_name="$6"
	local verify_mask="${7:-}"

	# Count number of bytes in reg_val (word-split; reg_val is space-separated hex bytes)
	set -- $reg_val
	local num_bytes="$#"

	# Write register
	log_message "info" "Writing $reg_name on $device_name: Bus $bus, Addr $addr, Reg $reg, Val: $reg_val"

	if ! i2ctransfer -f -y "$bus" w$((num_bytes + 1))@"$addr" "$reg" $reg_val 2>&1; then
		log_message "warning" "Failed to write $reg_name on $device_name (Bus $bus, Addr $addr) - continuing"
		return 1
	fi

	# Small delay to allow device to process the write
	sleep 0.1

	# Read back and verify
	local readback
	readback=$(i2ctransfer -f -y "$bus" w1@"$addr" "$reg" r"$num_bytes" 2>&1)
	local read_status=$?

	if [ "$read_status" -ne 0 ]; then
		log_message "warning" "Failed to read back $reg_name on $device_name (Bus $bus, Addr $addr) - continuing"
		return 1
	fi

	# Normalize: extract 0xNN tokens only (avoids junk text; keeps byte order)
	local read_n exp_n
	read_n=$(i2c_readback_hex_concat "$readback")
	exp_n=$(i2c_readback_hex_concat "$reg_val")

	if [ -n "$verify_mask" ]; then
		read_n=$(hex_concat_apply_mask "$read_n" "$verify_mask")
		exp_n=$(hex_concat_apply_mask "$exp_n" "$verify_mask")
	fi

	if [ "$read_n" != "$exp_n" ]; then
		log_message "warning" "$reg_name mismatch on $device_name (Bus $bus, Addr $addr): expected hex [$exp_n] from [$reg_val], readback hex [$read_n] from i2ctransfer — continuing"
		return 1
	fi

	log_message "info" "$reg_name verified successfully on $device_name"
	return 0
}

# ADS7924: I2C pointer + one or more data bytes (no readback verify).
i2c_write_ads7924_burst()
{
	local bus="$1" addr="$2" ptr="$3"
	shift 3

	if ! i2ctransfer -f -y "$bus" w$(($# + 1))@"$addr" "$ptr" "$@" 2>&1; then
		return 1
	fi
	return 0
}

# Convert voltage (engineering units) to ADS7924 8-bit window comparator code.
# Matches 12-bit IIO raw >> 4 when Scale = volts per 12-bit LSB (Vref/4096).
ads7924_volts_to_code8()
{
	local volts="$1"
	local scale="$2"

	awk -v v="$volts" -v sc="$scale" 'BEGIN {
		if (sc == "" || (sc + 0) == 0) { printf "0\n"; exit }
		c = v / sc
		if (c < 0) c = 0
		if (c >= 4096) c = 4095
		d = int(c / 16)
		if (d > 255) d = 255
		if (d < 0) d = 0
		printf "%d\n", d
	}'
}

# Optional JSON bool: default true when key missing (soft reset before programming).
json_ads7924_soft_reset_default_true()
{
	local json="$1"
	local v

	v=$(echo "$json" | json_get_bool "Ads7924SoftReset" 2>/dev/null) || true
	v=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]' | tr -d "\"'")
	if [ -z "$v" ]; then
		return 0
	fi
	if [ "$v" = "false" ] || [ "$v" = "0" ] || [ "$v" = "no" ]; then
		return 1
	fi
	return 0
}

# First byte of space-separated hex list, or empty.
json_hex_byte_or_empty()
{
	local json="$1"
	local key="$2"
	local s b

	s=$(echo "$json" | json_get_string "$key" 2>/dev/null) || true
	s=$(printf '%s' "$s" | tr -d '"')
	[ -z "$s" ] || [ "$s" = "null" ] && return 1
	set -- $s
	b="$1"
	[ -n "$b" ] || return 1
	printf '%s' "$b"
}

# 0xNN / 0XNN -> decimal (BusyBox ash-safe hex strip).
ads7924_hex_byte_to_uint()
{
	local b x
	b=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
	x="${b#0x}"
	[ -z "$x" ] && return 1
	case "$x" in
	*[!0-9a-f]*) return 1 ;;
	esac
	printf '%d' "$((16#$x))"
}

# ADS1015 config register MUX high byte (AINn single-ended vs GND); channel 0..3.
ads1015_mux_high_byte()
{
	case "$1" in
	0) printf '%s' 0xc2 ;;
	1) printf '%s' 0xd2 ;;
	2) printf '%s' 0xe2 ;;
	3) printf '%s' 0xf2 ;;
	*) return 1 ;;
	esac
}

# MAX1363 config byte: scan/monitor upper channel (single-ended), ch = 0..3 (TI datasheet Table 2).
max1363_scan_to_cs_config_byte()
{
	case "$1" in
	0) printf '%s' 0x01 ;;
	1) printf '%s' 0x03 ;;
	2) printf '%s' 0x05 ;;
	3) printf '%s' 0x07 ;;
	*) return 1 ;;
	esac
}

# Monitor-setup channel tag in platform CfgRegVal blob (first 0x1x byte selects channel).
max1363_monitor_channel_tag_byte()
{
	case "$1" in
	0) printf '%s' 0x11 ;;
	1) printf '%s' 0x13 ;;
	2) printf '%s' 0x15 ;;
	3) printf '%s' 0x1f ;;
	*) return 1 ;;
	esac
}

# Adjust MAX1363 CfgRegVal (1-based channels). Patches the monitor tag byte for
# hw_channel_id and the scan-to-CS range for scan_channel_id (defaults to
# hw_channel_id). With an array ChannelId, pass the HIGHEST mapped input as
# scan_channel_id so the scan range still covers every mapped channel, while the
# monitor tag tracks the first mapped input.
max1363_cfg_reg_val_for_channel()
{
	local cfg_reg_val="$1"
	local hw_channel_id="$2"
	local scan_channel_id="${3:-$2}"
	local ch scan_ch b out first_mon scan_b mon_b

	[ -n "$cfg_reg_val" ] || return 1
	if [ -z "$hw_channel_id" ] || [ "$hw_channel_id" -lt 1 ] 2>/dev/null; then
		printf '%s' "$cfg_reg_val"
		return 0
	fi
	ch=$((hw_channel_id - 1))
	[ "$ch" -le 3 ] || return 1
	scan_ch=$((scan_channel_id - 1))
	[ "$scan_ch" -ge "$ch" ] && [ "$scan_ch" -le 3 ] 2>/dev/null || scan_ch=$ch
	scan_b=$(max1363_scan_to_cs_config_byte "$scan_ch") || return 1
	mon_b=$(max1363_monitor_channel_tag_byte "$ch") || return 1

	first_mon=0
	out=""
	for b in $cfg_reg_val; do
		b=$(echo "$b" | tr -d '"')
		case "$b" in
		0x01|0x03|0x05|0x07)
			b="$scan_b"
			;;
		0x11|0x13|0x15|0x1f)
			if [ "$first_mon" -eq 0 ]; then
				b="$mon_b"
				first_mon=1
			fi
			;;
		esac
		out="$out${out:+ }$b"
	done
	printf '%s' "$out"
}

# Program MAX1363 register burst from JSON CfgReg/CfgRegVal (channel-aware when ChannelId set).
# Optional 6th arg post_driver=post_driver: driver may stay bound (i2ctransfer -f).
configure_max1363_raw_i2c()
{
	local device_json="$1"
	local device_name="$2"
	local bus="$3"
	local address="$4"
	local hw_channel_id="${5:-0}"
	local post_driver="${6:-}"

	local cfg_reg cfg_reg_val patched hw_ch scan_ch k cid

	if [ "$post_driver" = "post_driver" ]; then
		log_message "info" "MAX1363 $device_name: post-driver I2C programming"
	fi

	cfg_reg=$(echo "$device_json" | json_get_string "CfgReg")
	cfg_reg_val=$(echo "$device_json" | json_get_string "CfgRegVal")
	cfg_reg_val=$(echo "$cfg_reg_val" | tr -d '"')
	cfg_reg=$(echo "$cfg_reg" | tr -d '"')

	if [ -z "$cfg_reg" ] || [ -z "$cfg_reg_val" ] || [ "$cfg_reg" = "null" ] || [ "$cfg_reg_val" = "null" ]; then
		log_message "warning" "MAX1363 $device_name: CfgReg/CfgRegVal missing — skipping raw init"
		return 1
	fi

	hw_ch="$hw_channel_id"
	if [ -z "$hw_ch" ] || [ "$hw_ch" -lt 1 ] 2>/dev/null; then
		hw_ch=$(json_device_hw_channel_id "$device_json" 1)
	fi

	# With an array ChannelId the chip serves several inputs: keep the scan-to-CS
	# range covering the HIGHEST mapped input so every mapped channel is converted
	# (otherwise the scan would narrow to the first input and higher channels go
	# stale). The monitor tag still tracks the first mapped input (hw_ch).
	scan_ch="$hw_ch"
	if json_channelid_is_array "$device_json"; then
		k=1
		while cid=$(json_channel_id_at "$device_json" "$k"); do
			[ "$cid" -gt "$scan_ch" ] 2>/dev/null && scan_ch="$cid"
			k=$((k + 1))
		done
	fi

	patched=$(max1363_cfg_reg_val_for_channel "$cfg_reg_val" "$hw_ch" "$scan_ch") || patched="$cfg_reg_val"
	if [ "$patched" != "$cfg_reg_val" ]; then
		log_message "info" "MAX1363 $device_name: CfgRegVal adjusted (monitor ch $hw_ch, scan to ch $scan_ch): $cfg_reg_val -> $patched"
	fi

	if write_and_verify_register "$bus" "$address" "$cfg_reg" "$patched" "Configuration Register" "$device_name"; then
		return 0
	fi
	return 1
}

# All MAX1363 leak sensors on this platform are wired with Vdd as the ADC reference
# (full-scale = Vdd ~3.28 V, i.e. Scale 0.0008 V/LSB). With no "vref" regulator in the
# devicetree the ti-max1363 driver defaults to its internal 2.048 V reference and rails
# inputs above it to raw 4095; forcing Vdd via sysfs restores correct conversions. Call
# after the kernel driver is (re)bound so the IIO voltage_reference node exists.
MAX1363_IIO_REFERENCE="Vdd"

max1363_set_iio_reference()
{
	local bus="$1"
	local address="$2"
	local a dev_id iio_dir vr d dirs

	a="${address#0x}"
	a="${a#0X}"
	dev_id=$(printf '%d-%04x' "$bus" $((16#$a)))

	# IIO device dirs, same discovery order as find_iio_channel_raw: under the I2C
	# client, then /sys/bus/iio/devices entries whose device link is this client.
	dirs=""
	for d in /sys/bus/i2c/devices/"$dev_id"/iio:device*; do
		[ -e "$d" ] && dirs="$dirs $d"
	done
	for d in /sys/bus/iio/devices/iio:device*; do
		[ -e "$d" ] || continue
		[ "$(basename "$(readlink -f "$d/device" 2>/dev/null)" 2>/dev/null)" = "$dev_id" ] && dirs="$dirs $d"
	done

	for iio_dir in $dirs; do
		vr="$iio_dir/voltage_reference"
		[ -w "$vr" ] || continue
		if echo "$MAX1363_IIO_REFERENCE" >"$vr" 2>/dev/null; then
			log_message "info" "MAX1363 $dev_id: voltage_reference=$MAX1363_IIO_REFERENCE (now: $(cat "$vr" 2>/dev/null))"
			return 0
		fi
		log_message "err" "MAX1363 $dev_id: failed to set voltage_reference=$MAX1363_IIO_REFERENCE (available: $(cat "${vr}_available" 2>/dev/null)) - readings may rail to full scale (driver internal 2.048 V reference)"
		return 1
	done
	log_message "err" "MAX1363 $dev_id: no voltage_reference sysfs node — cannot set $MAX1363_IIO_REFERENCE reference; readings may rail to full scale (driver internal 2.048 V reference)"
	return 1
}

# True when ADS1015 config low byte has COMP_QUE=11 (comparator disabled, TI SBAS173).
ads1015_cfg_comp_disabled()
{
	local lo="$1"
	local v

	v=$((${lo}))
	v=$((v & 3))
	[ "$v" -eq 3 ]
}

# Write ti-ads1015 IIO scale (±4.096 V PGA) to one sysfs path.
ads1015_write_iio_scale_path()
{
	local scale_path="$1"
	local avail_path v

	[ -n "$scale_path" ] || return 1
	[ -e "$scale_path" ] || return 1

	for v in "4096 11" "2.000000" "2.0" "2"; do
		if echo "$v" >"$scale_path" 2>/dev/null; then
			log_message "info" "ADS1015 IIO scale -> $scale_path ($v) for ±4.096 V PGA"
			return 0
		fi
	done

	avail_path="${scale_path}_available"
	if [ -r "$avail_path" ]; then
		v=$(awk '$1 == 4096 && $2 == 11 { print $1, $2; exit }' "$avail_path" 2>/dev/null)
		if [ -n "$v" ] && echo "$v" >"$scale_path" 2>/dev/null; then
			log_message "info" "ADS1015 IIO scale -> $scale_path (from available: $v)"
			return 0
		fi
	fi
	return 1
}

# ti-ads1015 defaults to PGA index 2 (±2048 mV). Inputs above ~2 V clip to raw 2047.
# Board init uses ±4096 mV (MUX bytes 0xc2/0xd2); set IIO scale to match before reads.
# Tries per-channel in_voltage<N>_scale, then shared in_voltage_scale (driver-dependent).
ads1015_set_iio_scale_for_raw()
{
	local raw_path="$1"
	local scale_path iio_dir shared_scale

	[ -n "$raw_path" ] || return 1
	iio_dir=$(dirname "$raw_path")
	scale_path="${raw_path%_raw}_scale"
	shared_scale="$iio_dir/in_voltage_scale"

	if [ -e "$scale_path" ] && ads1015_write_iio_scale_path "$scale_path"; then
		return 0
	fi
	if [ -e "$shared_scale" ] && [ "$shared_scale" != "$scale_path" ] &&
		ads1015_write_iio_scale_path "$shared_scale"; then
		return 0
	fi

	if [ ! -e "$scale_path" ] && [ ! -e "$shared_scale" ]; then
		log_message "warning" "ADS1015 IIO scale sysfs missing under $iio_dir (no per-channel or shared scale)"
	else
		log_message "warning" "ADS1015 IIO scale not set under $iio_dir — driver default ±2.048 V may clip to raw 2047"
	fi
	return 1
}

# Program ADS1015 config (and optional window comparator Lo/Hi) per MUX channel (TI SBAS173).
# Optional 7th arg post_driver=post_driver: driver may stay bound (i2ctransfer -f).
configure_ads1015_raw_i2c()
{
	local device_json="$1"
	local device_name="$2"
	local bus="$3"
	local address="$4"
	local num_channels="$5"
	local hw_channel_id="${6:-0}"
	local post_driver="${7:-}"

	local cfg_lo lo_val hi_val lo_reg hi_reg mux mux_handoff ch nch ch_end ch_step failed skip_thresh mode_msg
	local t ch_label ch_list k cid

	if [ "$post_driver" = "post_driver" ]; then
		log_message "info" "ADS1015 $device_name: post-driver I2C programming"
	fi

	cfg_lo="0x94"
	t=$(echo "$device_json" | json_get_string "CfgRegVal" 2>/dev/null) || true
	t=$(echo "$t" | tr -d '"')
	if [ -n "$t" ] && [ "$t" != "null" ]; then
		set -- $t
		shift
		[ -n "$1" ] && cfg_lo="$1"
	fi

	skip_thresh=0
	if ads1015_cfg_comp_disabled "$cfg_lo"; then
		skip_thresh=1
		mode_msg="polling (comparator disabled, cfg_lo=$cfg_lo)"
	else
		mode_msg="window comparator (cfg_lo=$cfg_lo)"
	fi

	local default_lo default_hi
	default_lo="0x20 0x00"
	default_hi="0x7f 0xf0"
	t=$(echo "$device_json" | json_get_string "LoThreshRegVal" 2>/dev/null) || true
	t=$(echo "$t" | tr -d '"')
	[ -n "$t" ] && [ "$t" != "null" ] && default_lo="$t"
	t=$(echo "$device_json" | json_get_string "HiThreshRegVal" 2>/dev/null) || true
	t=$(echo "$t" | tr -d '"')
	[ -n "$t" ] && [ "$t" != "null" ] && default_hi="$t"

	lo_reg="0x02"
	hi_reg="0x03"
	t=$(echo "$device_json" | json_get_string "LoThreshReg" 2>/dev/null) || true
	t=$(echo "$t" | tr -d '"')
	[ -n "$t" ] && [ "$t" != "null" ] && lo_reg="$t"
	t=$(echo "$device_json" | json_get_string "HiThreshReg" 2>/dev/null) || true
	t=$(echo "$t" | tr -d '"')
	[ -n "$t" ] && [ "$t" != "null" ] && hi_reg="$t"

	# Build the list of 0-based MUX indices to program.
	#   - explicit hw_channel_id (per-channel device map): just that channel
	#   - ChannelId array (BOM alternative): exactly the mapped hardware channels
	#   - otherwise: contiguous 0..num_channels-1 (legacy sequential)
	ch_list=""
	if [ -n "$hw_channel_id" ] && [ "$hw_channel_id" -ge 1 ] 2>/dev/null; then
		ch_list=$((hw_channel_id - 1))
		log_message "info" "ADS1015 $device_name: per-channel init ($mode_msg, hardware channel $hw_channel_id / MUX index $ch_list)"
	elif json_channelid_is_array "$device_json"; then
		k=1
		while [ "$k" -le "${num_channels:-0}" ]; do
			cid=$(json_channel_id_at "$device_json" "$k") || break
			if [ "$cid" -ge 1 ] 2>/dev/null; then
				ch_list="$ch_list${ch_list:+ }$((cid - 1))"
			fi
			k=$((k + 1))
		done
		log_message "info" "ADS1015 $device_name: per-channel init ($mode_msg, ChannelId MUX indices: ${ch_list:-none})"
	else
		nch=4
		if [ -n "$num_channels" ] && [ "$num_channels" -ge 1 ] 2>/dev/null; then
			nch="$num_channels"
			[ "$nch" -gt 4 ] && nch=4
		fi
		ch=0
		while [ "$ch" -lt "$nch" ]; do
			ch_list="$ch_list${ch_list:+ }$ch"
			ch=$((ch + 1))
		done
		log_message "info" "ADS1015 $device_name: per-channel init ($mode_msg, channel MUX indices: $ch_list)"
	fi

	failed=0
	for ch in $ch_list; do
		mux=$(ads1015_mux_high_byte "$ch") || {
			failed=1
			break
		}
		lo_val="$default_lo"
		hi_val="$default_hi"
		ch_label=$((ch + 1))
		t=$(json_optional_scalar "$device_json" "Ads1015LoThreshCh${ch_label}") && lo_val="$t"
		t=$(json_optional_scalar "$device_json" "Ads1015HiThreshCh${ch_label}") && hi_val="$t"

		# Config high byte bit 15 (OS) is a volatile single-shot/status bit, not stored config:
		# write 1 starts a conversion, read returns 0 while converting (continuous mode reads 0).
		# Mask it off (0x7f) so verify checks MUX/PGA/MODE/comparator bits without false-failing.
		if ! write_and_verify_register "$bus" "$address" 0x01 \
			"$mux $cfg_lo" "ADS1015 Config ch $ch" "$device_name" "0x7f 0xff"; then
			failed=1
		fi
		if [ "$skip_thresh" -eq 0 ]; then
			if ! write_and_verify_register "$bus" "$address" "$lo_reg" \
				"$lo_val" "ADS1015 Lo_thresh ch $ch" "$device_name"; then
				failed=1
			fi
			if ! write_and_verify_register "$bus" "$address" "$hi_reg" \
				"$hi_val" "ADS1015 Hi_thresh ch $ch" "$device_name"; then
				failed=1
			fi
		fi
	done

	if [ "$failed" -ne 0 ]; then
		log_message "warning" "ADS1015 $device_name: one or more channel programs failed"
		return 1
	fi

	# Leave MUX on the configured channel and read conversion so pointer reg is 0x00 before driver bind.
	if [ -n "$hw_channel_id" ] && [ "$hw_channel_id" -ge 1 ] 2>/dev/null; then
		mux_handoff=$(ads1015_mux_high_byte $((hw_channel_id - 1))) || mux_handoff=""
	else
		mux_handoff=$(ads1015_mux_high_byte 0) || mux_handoff=""
	fi
	if [ -n "$mux_handoff" ]; then
		i2ctransfer -f -y "$bus" w3@"$address" 0x01 "$mux_handoff" "$cfg_lo" >/dev/null 2>&1 || true
		sleep 0.01
		i2ctransfer -f -y "$bus" w1@"$address" 0x00 r2 >/dev/null 2>&1 || true
	fi

	if [ -n "$hw_channel_id" ] && [ "$hw_channel_id" -ge 1 ] 2>/dev/null; then
		log_message "info" "ADS1015 $device_name: raw I2C configuration complete (MUX channel $((hw_channel_id - 1)) selected for driver handoff)"
	else
		log_message "info" "ADS1015 $device_name: raw I2C configuration complete (MUX channel 0 selected for driver handoff)"
	fi
	return 0
}

# Program ADS7924 over raw I2C (TI SBAS482 register map).
# Optional 6th arg post_driver=post_driver: driver may stay bound (i2ctransfer -f); soft reset
# is skipped so we do not undo kernel probe state.
configure_ads7924_raw_i2c()
{
	local device_json="$1"
	local device_name="$2"
	local bus="$3"
	local address="$4"
	local num_channels="$5"
	local post_driver="${6:-}"

	local scale_s v_min v_max ll ul i b c t gtype
	local int_b slp_b acq_b pwr_b mode_b awake_b aen_b
	local ul0 ll0 ul1 ll1 ul2 ll2 ul3 ll3
	local k cid ctype cvmin cvmax cll cul hw

	if ! scale_s=$(json_optional_scalar "$device_json" "Scale"); then
		log_message "warning" "ADS7924 $device_name: Scale required for alarm threshold codes — skipping raw init"
		return 1
	fi

	# Global fallback window: legacy device-level scalars, or (new schema) the first
	# channel's type. Per-channel windows below override this per hardware input.
	gtype=""
	if json_has_channels_array "$device_json"; then
		gtype=$(json_channel_type_at "$device_json" 1) || gtype=""
	fi

	v_min=""
	v_max=""
	if v_min=$(resolve_threshold "$device_json" "$gtype" "NormalMin"); then
		:
	elif v_min=$(resolve_threshold "$device_json" "$gtype" "WarningMin"); then
		:
	else
		log_message "warning" "ADS7924 $device_name: need NormalMin or WarningMin for LLR — skipping raw init"
		return 1
	fi
	if v_max=$(resolve_threshold "$device_json" "$gtype" "NormalMax"); then
		:
	elif v_max=$(resolve_threshold "$device_json" "$gtype" "WarningMax"); then
		:
	else
		log_message "warning" "ADS7924 $device_name: need NormalMax or WarningMax for ULR — skipping raw init"
		return 1
	fi

	ll=$(ads7924_volts_to_code8 "$v_min" "$scale_s")
	ul=$(ads7924_volts_to_code8 "$v_max" "$scale_s")
	if [ "$ul" -le "$ll" ]; then
		ul=$((ll + 1))
		[ "$ul" -gt 255 ] && ul=255
		[ "$ul" -le "$ll" ] && ll=$((ul - 1))
		[ "$ll" -lt 0 ] && ll=0
	fi

	ul0=$ul
	ll0=$ll
	ul1=$ul
	ll1=$ll
	ul2=$ul
	ll2=$ll
	ul3=$ul
	ll3=$ll

	# Per-channel-type windows (new schema): each Channels[k] maps a hardware input
	# (Id) to a Type whose NormalMin/Max (or WarningMin/Max) defines that input's
	# ULR/LLR. Explicit Ads7924UlChN/Ads7924LlChN hex overrides below still win.
	if json_has_channels_array "$device_json"; then
		k=1
		while [ "$k" -le "${num_channels:-0}" ] 2>/dev/null; do
			cid=$(json_channel_id_at "$device_json" "$k") || { k=$((k + 1)); continue; }
			if [ "$cid" -lt 1 ] 2>/dev/null || [ "$cid" -gt 4 ] 2>/dev/null; then
				k=$((k + 1))
				continue
			fi
			ctype=$(json_channel_type_at "$device_json" "$k") || ctype=""
			cvmin=$(resolve_threshold "$device_json" "$ctype" "NormalMin") ||
				cvmin=$(resolve_threshold "$device_json" "$ctype" "WarningMin") || cvmin=""
			cvmax=$(resolve_threshold "$device_json" "$ctype" "NormalMax") ||
				cvmax=$(resolve_threshold "$device_json" "$ctype" "WarningMax") || cvmax=""
			if [ -n "$cvmin" ] && [ -n "$cvmax" ]; then
				cll=$(ads7924_volts_to_code8 "$cvmin" "$scale_s")
				cul=$(ads7924_volts_to_code8 "$cvmax" "$scale_s")
				if [ "$cul" -le "$cll" ]; then
					cul=$((cll + 1))
					[ "$cul" -gt 255 ] && cul=255
					[ "$cul" -le "$cll" ] && cll=$((cul - 1))
					[ "$cll" -lt 0 ] && cll=0
				fi
				hw=$((cid - 1))
				case "$hw" in
				0) ul0=$cul; ll0=$cll ;;
				1) ul1=$cul; ll1=$cll ;;
				2) ul2=$cul; ll2=$cll ;;
				3) ul3=$cul; ll3=$cll ;;
				esac
				log_message "info" "ADS7924 $device_name: channel $k (input $cid, type ${ctype:-?}) window LLR=$cll ULR=$cul"
			fi
			k=$((k + 1))
		done
	fi

	if [ -n "$num_channels" ] && [ "$num_channels" -ge 1 ] 2>/dev/null; then
		i=1
		while [ "$i" -le "$num_channels" ] && [ "$i" -le 4 ]; do
			b=$(json_hex_byte_or_empty "$device_json" "Ads7924UlCh${i}")
			if [ -n "$b" ] && c=$(ads7924_hex_byte_to_uint "$b"); then
				if [ "$c" -lt 0 ] || [ "$c" -gt 255 ]; then
					log_message "warning" "ADS7924 $device_name: Ads7924UlCh${i} value $c out of 0–255 — ignoring override"
				else
					case "$i" in
					1) ul0=$c ;;
					2) ul1=$c ;;
					3) ul2=$c ;;
					4) ul3=$c ;;
					esac
				fi
			fi
			b=$(json_hex_byte_or_empty "$device_json" "Ads7924LlCh${i}")
			if [ -n "$b" ] && c=$(ads7924_hex_byte_to_uint "$b"); then
				if [ "$c" -lt 0 ] || [ "$c" -gt 255 ]; then
					log_message "warning" "ADS7924 $device_name: Ads7924LlCh${i} value $c out of 0–255 — ignoring override"
				else
					case "$i" in
					1) ll0=$c ;;
					2) ll1=$c ;;
					3) ll2=$c ;;
					4) ll3=$c ;;
					esac
				fi
			fi
			i=$((i + 1))
		done
	fi

	int_b="0xe0"
	slp_b="0x00"
	acq_b="0x00"
	pwr_b="0x00"
	mode_b="0xcc"
	awake_b="0x80"
	aen_b="0x0f"
	t=$(json_hex_byte_or_empty "$device_json" "Ads7924IntConfig") && int_b="$t"
	t=$(json_hex_byte_or_empty "$device_json" "Ads7924SlpConfig") && slp_b="$t"
	t=$(json_hex_byte_or_empty "$device_json" "Ads7924AcqConfig") && acq_b="$t"
	t=$(json_hex_byte_or_empty "$device_json" "Ads7924PwrConfig") && pwr_b="$t"
	t=$(json_hex_byte_or_empty "$device_json" "Ads7924Mode") && mode_b="$t"
	t=$(json_hex_byte_or_empty "$device_json" "Ads7924AwakeMode") && awake_b="$t"
	t=$(json_hex_byte_or_empty "$device_json" "Ads7924AlarmEnable") && aen_b="$t"

	if [ "$post_driver" != "post_driver" ] && json_ads7924_soft_reset_default_true "$device_json"; then
		log_message "info" "ADS7924 $device_name: software reset (write 0xaa to RESET)"
		if ! i2c_write_ads7924_burst "$bus" "$address" 0x16 0xaa; then
			log_message "warning" "ADS7924 $device_name: soft reset write failed"
			return 1
		fi
		sleep 0.05
	elif [ "$post_driver" = "post_driver" ]; then
		log_message "info" "ADS7924 $device_name: post-driver programming (soft reset skipped)"
	fi

	if ! i2c_write_ads7924_burst "$bus" "$address" 0x00 0x00; then
		log_message "warning" "ADS7924 $device_name: IDLE mode write failed"
		return 1
	fi
	sleep 0.02

	if ! write_and_verify_register "$bus" "$address" 0x8a \
		"$(printf '0x%02x 0x%02x 0x%02x 0x%02x 0x%02x 0x%02x 0x%02x 0x%02x' "$ul0" "$ll0" "$ul1" "$ll1" "$ul2" "$ll2" "$ul3" "$ll3")" \
		"ADS7924 ULR/LLR burst" "$device_name"; then
		return 1
	fi

	# INTCONFIG/SLPCONFIG/ACQCONFIG/PWRCONFIG: write only (no readback verify). Some parts may expose
	# read-only bits in these registers; byte-exact verify would false-fail like MODECNTRL/INTCNTRL.
	log_message "info" "ADS7924 $device_name: INT/SLP/ACQ/PWR burst (no readback verify)"
	if ! i2c_write_ads7924_burst "$bus" "$address" 0x92 $int_b $slp_b $acq_b $pwr_b; then
		log_message "warning" "ADS7924 $device_name: INT/SLP/ACQ/PWR burst write failed"
		return 1
	fi
	sleep 0.02

	log_message "info" "ADS7924 $device_name: enabling alarms (INTCNTRL, no readback verify)"
	if ! i2c_write_ads7924_burst "$bus" "$address" 0x01 $aen_b; then
		log_message "warning" "ADS7924 $device_name: INTCNTRL write failed"
		return 1
	fi
	sleep 0.02

	# Clear any stale alarm interrupt before starting the scan. TI SBAS482: reading
	# INTCONFIG (0x12) clears a latched alarm-condition interrupt.
	log_message "info" "ADS7924 $device_name: clearing stale alarm (read INTCONFIG 0x12)"
	i2ctransfer -f -y "$bus" w1@"$address" 0x12 r1 >/dev/null 2>&1 || true
	sleep 0.002

	log_message "info" "ADS7924 $device_name: AWAKE then MODE ($awake_b then $mode_b)"
	if ! i2c_write_ads7924_burst "$bus" "$address" 0x00 $awake_b; then
		log_message "warning" "ADS7924 $device_name: AWAKE write failed"
		return 1
	fi
	sleep 0.002
	if ! i2c_write_ads7924_burst "$bus" "$address" 0x00 $mode_b; then
		log_message "warning" "ADS7924 $device_name: MODE write failed"
		return 1
	fi

	if [ "$post_driver" = "post_driver" ]; then
		log_message "info" "ADS7924 $device_name: post-driver I2C configuration complete"
	else
		log_message "info" "ADS7924 $device_name: raw I2C configuration complete"
	fi
	return 0
}

# Read optional scalar from device JSON (string or number).
json_optional_scalar()
{
	local json="$1"
	local key="$2"
	local v
	v=$(echo "$json" | json_get_string "$key" 2>/dev/null) || true
	v=$(echo "$v" | tr -d '"')
	if [ -z "$v" ] || [ "$v" = "null" ]; then
		v=$(echo "$json" | json_get_number "$key" 2>/dev/null) || true
	fi
	if [ -z "$v" ] || [ "$v" = "null" ]; then
		return 1
	fi
	echo "$v"
}

# True (0) when the device JSON has a top-level "<name>" array (e.g. Channels / Types).
json_device_has_array()
{
	local json="$1"
	local name="$2"
	echo "$json" | awk -v name="$name" '
	BEGIN { buf = "" }
	{ buf = buf $0 }
	END {
		p = "\"" name "\""
		i = index(buf, p)
		if (i == 0) exit 1
		j = i + length(p)
		while (j <= length(buf) && substr(buf, j, 1) ~ /[ \t]/) j++
		if (substr(buf, j, 1) != ":") exit 1
		j++
		while (j <= length(buf) && substr(buf, j, 1) ~ /[ \t]/) j++
		if (substr(buf, j, 1) == "[") exit 0
		exit 1
	}'
}

# True (0) when the device JSON carries a Channels[] array ({Id,Type} per channel).
json_has_channels_array()
{
	json_device_has_array "$1" "Channels"
}

# True (0) when the device JSON carries a Types[] array (per-type thresholds).
json_has_types_array()
{
	json_device_has_array "$1" "Types"
}

# The n-th (1-based) Channels[] entry object, or empty.
json_channel_entry_at()
{
	local device_json="$1"
	local n="$2"
	[ -n "$n" ] && [ "$n" -ge 1 ] 2>/dev/null || return 1
	echo "$device_json" | json_get_nested_array_element "Channels" "$((n - 1))"
}

# Type label of the n-th (1-based) logical channel. New schema: Channels[n].Type.
# Legacy: device-level "Type". Returns 1 when no type is defined.
json_channel_type_at()
{
	local device_json="$1"
	local n="$2"
	local entry v

	if json_has_channels_array "$device_json"; then
		entry=$(json_channel_entry_at "$device_json" "$n") || return 1
		[ -n "$entry" ] || return 1
		v=$(echo "$entry" | json_get_string "Type")
		[ -n "$v" ] && [ "$v" != "null" ] && { printf '%s' "$v"; return 0; }
		return 1
	fi

	v=$(echo "$device_json" | json_get_string "Type" 2>/dev/null) || true
	v=$(echo "$v" | tr -d '"')
	[ -n "$v" ] && [ "$v" != "null" ] && { printf '%s' "$v"; return 0; }
	return 1
}

# Threshold scalar for a channel type from the device Types[] array.
# Usage: json_type_threshold <device_json> <type_name> <key>
# Prints the value and returns 0; returns 1 when Types/type/key is absent.
json_type_threshold()
{
	local device_json="$1"
	local type_name="$2"
	local key="$3"
	local n i elem etype val

	[ -n "$type_name" ] || return 1
	json_has_types_array "$device_json" || return 1
	n=$(echo "$device_json" | json_count_nested_array "Types")
	[ -n "$n" ] && [ "$n" -ge 1 ] 2>/dev/null || return 1

	i=0
	while [ "$i" -lt "$n" ]; do
		elem=$(echo "$device_json" | json_get_nested_array_element "Types" "$i")
		etype=$(echo "$elem" | json_get_string "Type")
		if [ "$etype" = "$type_name" ]; then
			if val=$(json_optional_scalar "$elem" "$key"); then
				printf '%s' "$val"
				return 0
			fi
			return 1
		fi
		i=$((i + 1))
	done
	return 1
}

# Resolve one threshold key for a channel: prefer the per-type Types[] entry, then
# fall back to a device-level scalar (legacy schema only). When a Types[] array is
# present the device-level scalar fallback is skipped so a value from a different
# type entry is never read by mistake.
resolve_threshold()
{
	local device_json="$1"
	local chan_type="$2"
	local key="$3"
	local v

	if [ -n "$chan_type" ] && v=$(json_type_threshold "$device_json" "$chan_type" "$key"); then
		printf '%s' "$v"
		return 0
	fi
	if json_has_types_array "$device_json"; then
		return 1
	fi
	json_optional_scalar "$device_json" "$key"
}

# True (0) when the device JSON has a ChannelId array (vs a scalar / absent), OR a
# Channels[] array. Both forms mean a single present chip serves several logical
# channels (BOM-alternative mode); runtime channel dirs are named by mapped input.
json_channelid_is_array()
{
	if json_has_channels_array "$1"; then
		return 0
	fi
	echo "$1" | awk '
	BEGIN { buf = "" }
	{ buf = buf $0 }
	END {
		p = "\"ChannelId\""
		i = index(buf, p)
		if (i == 0) exit 1
		j = i + length(p)
		while (j <= length(buf) && substr(buf, j, 1) ~ /[ \t]/) j++
		if (substr(buf, j, 1) != ":") exit 1
		j++
		while (j <= length(buf) && substr(buf, j, 1) ~ /[ \t]/) j++
		if (substr(buf, j, 1) == "[") exit 0
		exit 1
	}'
}

# n-th value (1-based) of the channel hardware input map. New schema: Channels[n].Id.
# Legacy: n-th value of a ChannelId array, or the scalar ChannelId, from device JSON.
# Prints the value and returns 0; returns 1 if the channel/ChannelId is absent or out of range.
json_channel_id_at()
{
	local device_json="$1"
	local n="$2"
	local entry v

	if json_has_channels_array "$device_json"; then
		entry=$(json_channel_entry_at "$device_json" "$n") || return 1
		[ -n "$entry" ] || return 1
		v=$(echo "$entry" | json_get_number "Id")
		[ -n "$v" ] || return 1
		printf '%s' "$v"
		return 0
	fi

	echo "$device_json" | awk -v n="$n" '
	BEGIN { buf = "" }
	{ buf = buf $0 }
	END {
		p = "\"ChannelId\""
		i = index(buf, p)
		if (i == 0) exit 1
		j = i + length(p)
		while (j <= length(buf) && substr(buf, j, 1) ~ /[ \t]/) j++
		if (substr(buf, j, 1) != ":") exit 1
		j++
		while (j <= length(buf) && substr(buf, j, 1) ~ /[ \t]/) j++
		if (substr(buf, j, 1) == "[") {
			# array: return the n-th integer element (1-based)
			j++
			cnt = 0; num = ""
			while (j <= length(buf)) {
				c = substr(buf, j, 1)
				if (c ~ /[0-9]/) {
					num = num c
				} else if (c == "," || c == "]") {
					if (num != "") {
						cnt++
						if (cnt == n) { print num + 0; exit 0 }
						num = ""
					}
					if (c == "]") exit 1
				}
				j++
			}
			exit 1
		}
		# scalar: same value for any logical channel (legacy per-device single channel)
		start = j
		while (j <= length(buf) && substr(buf, j, 1) ~ /[0-9]/) j++
		if (j > start) { print substr(buf, start, j - start); exit 0 }
		exit 1
	}'
}

# Hardware A2D channel for a logical channel (1-based). Honors a ChannelId array
# (per logical channel) or a scalar ChannelId; defaults to the logical index.
json_device_hw_channel_id()
{
	local device_json="$1"
	local logical_ch="$2"
	local v

	if v=$(json_channel_id_at "$device_json" "$logical_ch"); then
		echo "$v"
	else
		echo "$logical_ch"
	fi
}

# True when each Device[] entry is a distinct I2C target for one logical channel (not BOM alternatives).
leak_detector_per_channel_devices()
{
	local block="$1"
	local num_devices num_channels d addrs key bus addr dj

	num_devices=$(echo "$block" | json_count_nested_array "Device")
	num_channels=$(echo "$block" | json_get_number "NumChnl")
	[ -z "$num_channels" ] && num_channels=0
	[ "$num_devices" -eq "$num_channels" ] || return 1
	[ "$num_channels" -gt 0 ] || return 1

	addrs=""
	d=0
	while [ "$d" -lt "$num_devices" ]; do
		dj=$(echo "$block" | json_get_nested_array_element "Device" "$d")
		# An array ChannelId means this Device serves every logical channel itself
		# (BOM alternative), so the detector is NOT a per-channel device map.
		if json_channelid_is_array "$dj"; then
			return 1
		fi
		bus=$(echo "$dj" | json_get_number "Bus")
		addr=$(echo "$dj" | json_get_string "Address")
		addr=$(echo "$addr" | tr -d '"')
		key="${bus}:${addr}"
		case " $addrs " in
		*" $key "*) return 1 ;;
		esac
		addrs="$addrs $key"
		d=$((d + 1))
	done
	return 0
}

# Space-separated 0xNN bytes -> unsigned integer (big-endian).
hex_bytes_to_uint_be()
{
	local sum=0
	local x
	for x in $1; do
		x="${x#0x}"
		x="${x#0X}"
		sum=$((sum * 256 + 16#$x))
	done
	echo "$sum"
}

# sysfs path for IIO raw sample: in_voltage<idx>_raw (or Nth in_voltage*_raw) under the client.
# Order: explicit iio:deviceN paths (no find/glob pitfalls), find, match IIO by device basename == dev_id
# (readlink -f equality fails on some sysfs layouts), then sorted fallbacks.
find_iio_channel_raw()
{
	local dev_id="$1"
	local idx="$2"
	local base f iio dn rp bn list

	base="/sys/bus/i2c/devices/${dev_id}"
	[ -d "$base" ] || return 1

	# 0) Direct paths (IIO ADC under I2C client): iio:device0 … under the I2C client
	for dn in 0 1 2 3 4 5 6 7; do
		for f in "$base/iio:device${dn}/in_voltage${idx}_raw" "$base/iio:device${dn}/in_voltage${idx}_input"; do
			if [ -f "$f" ] || [ -r "$f" ]; then
				echo "$f"
				return 0
			fi
		done
	done

	# 1) find by name (no \( \) — BusyBox-friendly); sysfs nodes are often readable special files
	for f in $(find "$base" -name "in_voltage${idx}_raw" 2>/dev/null) $(find "$base" -name "in_voltage${idx}_input" 2>/dev/null); do
		if [ -n "$f" ] && { [ -f "$f" ] || [ -r "$f" ]; }; then
			echo "$f"
			return 0
		fi
	done

	# 2) /sys/bus/iio/devices — match IIO device whose device symlink basename is 27-0049 etc.
	for iio in /sys/bus/iio/devices/iio:device*; do
		[ -e "$iio" ] || continue
		rp=$(readlink -f "$iio/device" 2>/dev/null)
		[ -n "$rp" ] || continue
		bn=$(basename "$rp")
		[ "$bn" = "$dev_id" ] || continue
		for f in "$iio/in_voltage${idx}_raw" "$iio/in_voltage${idx}_input"; do
			if [ -f "$f" ] || [ -r "$f" ]; then
				echo "$f"
				return 0
			fi
		done
	done

	# 3) Nth in_voltage*_raw under client (sorted)
	list=$(find "$base" -name 'in_voltage*_raw' 2>/dev/null | LC_ALL=C sort)
	if [ -n "$list" ]; then
		f=$(echo "$list" | awk -v n="$((idx + 1))" 'NR == n { print; exit }')
		if [ -n "$f" ] && { [ -f "$f" ] || [ -r "$f" ]; }; then
			echo "$f"
			return 0
		fi
	fi

	# 4) Single-channel legacy
	for iio in "$base"/iio:device*; do
		[ -d "$iio" ] || continue
		if [ -f "$iio/in_voltage_raw" ] || [ -r "$iio/in_voltage_raw" ]; then
			echo "$iio/in_voltage_raw"
			return 0
		fi
	done
	return 1
}

# Per-channel files under /var/run/.../leakage/<i>/<j>/ (see README).
# warn/crit/lwarn/lcrit from WarningMax/CriticalMax/WarningMin/CriticalMin.
# min: LoThreshRegVal×Scale, else NormalMin, else WarningMin.
# max: HiThreshRegVal×Scale, else NormalMax, else WarningMax.
# Thresholds are resolved per channel type (chan_type, 8th arg) from the device
# Types[] array; legacy device-level scalars are used when no Types[] is present.
populate_leakage_channel_dir()
{
	local ch_dir="$1"
	local ch_num="$2"
	local device_json="$3"
	local bus="$4"
	local address="$5"
	local device_type="$6"
	local hw_channel_id="${7:-}"
	local chan_type="${8:-}"

	rm -f "$ch_dir/min" "$ch_dir/max" "$ch_dir/warn" "$ch_dir/crit" "$ch_dir/lwarn" "$ch_dir/lcrit" "$ch_dir/type" "$ch_dir/scale" "$ch_dir/input" "$ch_dir/channel_name"

	if [ -z "$hw_channel_id" ]; then
		hw_channel_id=$(json_device_hw_channel_id "$device_json" "$ch_num")
	fi
	# Resolve the channel type from Channels[] (new schema) when the caller did not
	# pass one explicitly; falls back to the legacy device-level Type.
	if [ -z "$chan_type" ]; then
		chan_type=$(json_channel_type_at "$device_json" "$ch_num") || chan_type=""
	fi

	local scale_s=""
	if scale_s=$(json_optional_scalar "$device_json" "Scale"); then
		echo "$scale_s" >"$ch_dir/scale"
	fi
	local sc_num="${scale_s:-1}"
	[ -z "$sc_num" ] && sc_num=1

	local v
	if v=$(resolve_threshold "$device_json" "$chan_type" "WarningMax"); then
		echo "$v" >"$ch_dir/warn"
	fi
	if v=$(resolve_threshold "$device_json" "$chan_type" "CriticalMax"); then
		echo "$v" >"$ch_dir/crit"
	fi
	if v=$(resolve_threshold "$device_json" "$chan_type" "WarningMin"); then
		echo "$v" >"$ch_dir/lwarn"
	fi
	if v=$(resolve_threshold "$device_json" "$chan_type" "CriticalMin"); then
		echo "$v" >"$ch_dir/lcrit"
	fi
	if [ -n "$chan_type" ]; then
		echo "$chan_type" >"$ch_dir/type"
	fi

	local lo_hex hi_hex
	lo_hex=$(echo "$device_json" | json_get_string "LoThreshRegVal" 2>/dev/null) || true
	hi_hex=$(echo "$device_json" | json_get_string "HiThreshRegVal" 2>/dev/null) || true
	lo_hex=$(echo "$lo_hex" | tr -d '"')
	hi_hex=$(echo "$hi_hex" | tr -d '"')

	# ADS1015 Lo/Hi registers are hardware-only; sysfs min/max align with MAX1363 via Warning*.
	if [ "$device_type" != "ADS1015" ]; then
		if [ -n "$lo_hex" ] && [ "$lo_hex" != "null" ]; then
			local lo_u
			lo_u=$(hex_bytes_to_uint_be "$lo_hex")
			awk -v u="$lo_u" -v s="$sc_num" 'BEGIN { printf "%.12g\n", u * s }' >"$ch_dir/min"
		fi
		if [ -n "$hi_hex" ] && [ "$hi_hex" != "null" ]; then
			local hi_u
			hi_u=$(hex_bytes_to_uint_be "$hi_hex")
			awk -v u="$hi_u" -v s="$sc_num" 'BEGIN { printf "%.12g\n", u * s }' >"$ch_dir/max"
		fi
	fi

	# min/max when Lo/Hi register hex absent (e.g. MAX1363): per-type NormalMin/NormalMax, else WarningMin/WarningMax
	if [ ! -f "$ch_dir/min" ]; then
		if v=$(resolve_threshold "$device_json" "$chan_type" "NormalMin"); then
			echo "$v" >"$ch_dir/min"
		elif v=$(resolve_threshold "$device_json" "$chan_type" "WarningMin"); then
			echo "$v" >"$ch_dir/min"
		fi
	fi
	if [ ! -f "$ch_dir/max" ]; then
		if v=$(resolve_threshold "$device_json" "$chan_type" "NormalMax"); then
			echo "$v" >"$ch_dir/max"
		elif v=$(resolve_threshold "$device_json" "$chan_type" "WarningMax"); then
			echo "$v" >"$ch_dir/max"
		fi
	fi

	if json_probe_true "$device_json"; then
		local a="${address#0x}"
		a="${a#0X}"
		local dev_id raw_path _try
		dev_id=$(printf '%d-%04x' "$bus" $((16#$a)))
		raw_path=""
		for _try in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
			raw_path=$(find_iio_channel_raw "$dev_id" "$((hw_channel_id - 1))")
			[ -n "$raw_path" ] && [ -f "$raw_path" ] && break
			sleep 0.2
		done
		if [ -n "$raw_path" ] && [ -f "$raw_path" ]; then
			if [ "$device_type" = "ADS1015" ]; then
				ads1015_set_iio_scale_for_raw "$raw_path"
			fi
			check_n_link "$raw_path" "$ch_dir/input"
			log_message "info" "Channel $ch_num input (hardware channel $hw_channel_id) -> $raw_path"
		else
			log_message "warning" "No IIO raw sysfs for channel $ch_num (hardware channel $hw_channel_id, device $dev_id, type $device_type) — check /sys/bus/i2c/devices/$dev_id and /sys/bus/iio/devices"
		fi
	fi
}

# Runtime layout (per A2D / leak-detector index i):
#   /var/run/hw-management/leakage/<i>/device_type
#   /var/run/hw-management/leakage/<i>/device_name   — Name from JSON
#   /var/run/hw-management/leakage/<i>/<j>/input (symlink if Probe) — kernel raw reading
#   /var/run/hw-management/leakage/<i>/<j>/{min,max,warn,crit,lwarn,lcrit,type,scale} — see README
#   min/max: LoThreshRegVal/HiThreshRegVal (× Scale), else NormalMin/NormalMax, else WarningMin/WarningMax
#   /var/run/hw-management/leakage/<i>/<j>/channel_name — ChnlNames[k] text under channel dir
# Seventh argument: space-separated channel names (from JSON ChnlNames).
# Eighth argument: detector Name from JSON.
create_channel_infrastructure()
{
	local device_index="$1"
	local device_type="$2"
	local num_channels="$3"
	local device_json="$4"
	local bus="$5"
	local address="$6"
	local chnames="$7"
	local detector_name="${8:-}"

	if [ ! -d "/var/run/hw-management" ]; then
		log_message "info" "/var/run/hw-management does not exist - skipping channel infrastructure creation"
		return 0
	fi

	local leakage_base="/var/run/hw-management/leakage/$device_index"
	mkdir -p "$leakage_base"
	rm -f "$leakage_base/device_name"
	echo "$device_type" >"$leakage_base/device_type"
	if [ -n "$detector_name" ]; then
		echo "$detector_name" >"$leakage_base/device_name"
	fi
	log_message "info" "Leakage runtime: $leakage_base (device_type=$device_type)"
	write_reference_status_marker "$leakage_base" "$device_type"

	if json_probe_true "$device_json"; then
		sleep 0.5
	fi

	local ch=1
	local channel_name hw_ch ch_dir_num chan_type
	while [ "$ch" -le "$num_channels" ]; do
		hw_ch=$(json_device_hw_channel_id "$device_json" "$ch")
		# Channel directory is named by the (hardware) channel Id so a non-sequential
		# map such as Channels[].Id [1,4] surfaces as leakage/<i>/1 and leakage/<i>/4,
		# and the input symlink targets in_voltage<Id-1>_raw.
		ch_dir_num="$hw_ch"
		[ -n "$ch_dir_num" ] && [ "$ch_dir_num" -ge 1 ] 2>/dev/null || ch_dir_num="$ch"
		# Per-channel type (Channels[ch].Type) selects the Types[] threshold set.
		chan_type=$(json_channel_type_at "$device_json" "$ch") || chan_type=""
		mkdir -p "$leakage_base/$ch_dir_num"
		populate_leakage_channel_dir "$leakage_base/$ch_dir_num" "$ch_dir_num" "$device_json" "$bus" "$address" "$device_type" "$hw_ch" "$chan_type"
		channel_name=$(echo "$chnames" | awk -v c="$ch" '{print $c}')
		if [ -n "$channel_name" ]; then
			echo "$channel_name" >"$leakage_base/$ch_dir_num/channel_name"
			log_message "info" "Channel $ch_dir_num channel_name=$channel_name (hardware channel $hw_ch)"
		fi
		ch=$((ch + 1))
	done

	return 0
}

# Record/clear a runtime marker when the MAX1363 Vdd reference could not be set, so a
# railed configuration is observable in the leakage tree (not only the system log).
write_reference_status_marker()
{
	local leakage_base="$1"
	local device_type="$2"
	if [ "$device_type" = "MAX1363" ] && [ "${MAX1363_REF_FAILED:-0}" = "1" ]; then
		echo "voltage_reference not set to ${MAX1363_IIO_REFERENCE}; readings may rail to full scale (driver internal 2.048 V reference)" >"$leakage_base/reference_error"
	else
		rm -f "$leakage_base/reference_error"
	fi
}

# One logical channel under leakage/<i>/<logical_ch>/ (per-channel Device[] map).
populate_single_leakage_channel()
{
	local device_index="$1"
	local logical_ch="$2"
	local device_type="$3"
	local device_json="$4"
	local bus="$5"
	local address="$6"
	local chnames="$7"
	local detector_name="$8"

	if [ ! -d "/var/run/hw-management" ]; then
		log_message "info" "/var/run/hw-management does not exist - skipping channel infrastructure creation"
		return 0
	fi

	local leakage_base hw_ch channel_name chan_type
	leakage_base="/var/run/hw-management/leakage/$device_index"
	mkdir -p "$leakage_base"
	if [ -n "$detector_name" ]; then
		echo "$detector_name" >"$leakage_base/device_name"
	fi
	if [ ! -f "$leakage_base/device_type" ]; then
		echo "$device_type" >"$leakage_base/device_type"
	fi
	write_reference_status_marker "$leakage_base" "$device_type"

	if json_probe_true "$device_json"; then
		sleep 0.5
	fi

	hw_ch=$(json_device_hw_channel_id "$device_json" "$logical_ch")
	# Per-channel device-map: a single channel entry maps to logical channel 1 of
	# this Device[]; resolve its type from Channels[] (new schema) when present.
	chan_type=$(json_channel_type_at "$device_json" 1) || chan_type=""
	mkdir -p "$leakage_base/$logical_ch"
	populate_leakage_channel_dir "$leakage_base/$logical_ch" "$logical_ch" "$device_json" "$bus" "$address" "$device_type" "$hw_ch" "$chan_type"
	channel_name=$(echo "$chnames" | awk -v c="$logical_ch" '{print $c}')
	if [ -n "$channel_name" ]; then
		echo "$channel_name" >"$leakage_base/$logical_ch/channel_name"
		log_message "info" "Channel $logical_ch channel_name=$channel_name (hardware channel $hw_ch)"
	fi
	log_message "info" "Leakage runtime channel $logical_ch under $leakage_base (device_type=$device_type, hardware channel $hw_ch)"
	return 0
}

# Program device registers over raw I2C (i2ctransfer -f). When post_driver is set, the
# kernel driver may remain bound after probe.
configure_a2d_registers_raw()
{
	local device_json="$1"
	local device_name="$2"
	local bus="$3"
	local address="$4"
	local device_type="$5"
	local num_channels="$6"
	local hw_channel_id="${7:-0}"
	local post_driver="${8:-}"

	local cfg_reg cfg_reg_val lo_thresh_reg lo_thresh_val hi_thresh_reg hi_thresh_val
	local success failed

	cfg_reg=$(echo "$device_json" | json_get_string "CfgReg")
	cfg_reg_val=$(echo "$device_json" | json_get_string "CfgRegVal")
	lo_thresh_reg=$(echo "$device_json" | json_get_string "LoThreshReg")
	lo_thresh_val=$(echo "$device_json" | json_get_string "LoThreshRegVal")
	hi_thresh_reg=$(echo "$device_json" | json_get_string "HiThreshReg")
	hi_thresh_val=$(echo "$device_json" | json_get_string "HiThreshRegVal")

	if [ "$device_type" = "ADS7924" ]; then
		configure_ads7924_raw_i2c "$device_json" "$device_name" "$bus" "$address" "$num_channels" "$post_driver"
		return $?
	fi
	if [ "$device_type" = "ADS1015" ]; then
		configure_ads1015_raw_i2c "$device_json" "$device_name" "$bus" "$address" "$num_channels" "$hw_channel_id" "$post_driver"
		return $?
	fi
	if [ "$device_type" = "MAX1363" ]; then
		configure_max1363_raw_i2c "$device_json" "$device_name" "$bus" "$address" "$hw_channel_id" "$post_driver"
		return $?
	fi

	success=0
	failed=0

	if [ -n "$cfg_reg" ] && [ -n "$cfg_reg_val" ] && [ "$cfg_reg" != "null" ] && [ "$cfg_reg_val" != "null" ]; then
		if write_and_verify_register "$bus" "$address" "$cfg_reg" "$cfg_reg_val" "Configuration Register" "$device_name"; then
			success=$((success + 1))
		else
			failed=$((failed + 1))
		fi
	fi

	if [ -n "$lo_thresh_reg" ] && [ -n "$lo_thresh_val" ] && [ "$lo_thresh_reg" != "null" ] && [ "$lo_thresh_val" != "null" ]; then
		if write_and_verify_register "$bus" "$address" "$lo_thresh_reg" "$lo_thresh_val" "Low Threshold Register" "$device_name"; then
			success=$((success + 1))
		else
			failed=$((failed + 1))
		fi
	fi

	if [ -n "$hi_thresh_reg" ] && [ -n "$hi_thresh_val" ] && [ "$hi_thresh_reg" != "null" ] && [ "$hi_thresh_val" != "null" ]; then
		if write_and_verify_register "$bus" "$address" "$hi_thresh_reg" "$hi_thresh_val" "High Threshold Register" "$device_name"; then
			success=$((success + 1))
		else
			failed=$((failed + 1))
		fi
	fi

	log_message "info" "Device configuration for $device_name: $success successful, $failed failed"
	[ "$failed" -eq 0 ]
}

# Args: device_json, device_name, num_channels, chnames (space-separated words from ChnlNames)
# Fifth argument: optional hardware ChannelId (1-based, 0 = sequential 1..num_channels).
configure_device()
{
	local device_json="$1"
	local device_name="$2"
	local num_channels="$3"
	local chnames="$4"
	local hw_channel_id="${5:-0}"

	local device_type bus address need_rebind

	device_type=$(echo "$device_json" | json_get_string "DeviceType")
	bus=$(echo "$device_json" | json_get_number "Bus")
	address=$(echo "$device_json" | json_get_string "Address")
	need_rebind=0
	MAX1363_REF_FAILED=0

	log_message "info" "Checking $device_type device at Bus $bus, Address $address for $device_name"

	# 1) Presence probe (SMBus/i2ctransfer or sysfs client) — no part ID from address
	if ! probe_i2c_device "$bus" "$address"; then
		log_message "info" "Presence probe failed at Bus $bus, Address $address — try next alternative"
		return 1
	fi
	log_message "info" "Presence probe OK at Bus $bus, Address $address (DeviceType=$device_type from JSON)"

	log_message "info" "Configuring $device_type for $device_name..."

	# Probe: bind driver (probe runs), then program registers as the last writer.
	if json_probe_true "$device_json"; then
		case "$device_type" in
		ADS7924|MAX1363|ADS1015)
			if ! bind_kernel_driver "$bus" "$address" "$device_type"; then
				log_message "info" "$device_type $device_name: driver bind failed — try next Device alternative"
				return 1
			fi
			if ! configure_a2d_registers_raw "$device_json" "$device_name" "$bus" "$address" \
				"$device_type" "$num_channels" "$hw_channel_id" post_driver; then
				log_message "info" "$device_type $device_name: post-probe register programming failed — try next Device alternative"
				return 1
			fi
			# MAX1363: force the Vdd ADC reference while the driver is bound and the IIO
			# sysfs is up, else the ti-max1363 default 2.048 V internal reference rails
			# inputs above it to raw 4095. Record the outcome so a railed reference is
			# observable in the leakage tree.
			if [ "$device_type" = "MAX1363" ] && ! max1363_set_iio_reference "$bus" "$address"; then
				MAX1363_REF_FAILED=1
			fi
			log_message "info" "Device configuration complete for $device_name"
			return 0
			;;
		esac
	fi

	# 2) Bind kernel driver first when Probe is true (instantiates client; driver probe may run once).
	if json_probe_true "$device_json"; then
		if ! bind_kernel_driver "$bus" "$address" "$device_type"; then
			log_message "warning" "Initial driver bind failed for $device_name (bus $bus addr $address) — continuing; will retry after register programming"
		fi
	fi

	# 3) Unbind so i2ctransfer can program registers (MAX1363 / ADS1015).
	if i2c_client_has_bound_driver "$bus" "$address"; then
		if ! unbind_kernel_driver "$bus" "$address"; then
			log_message "info" "Leak detector $device_name: driver unbind failed — try next Device alternative"
			return 1
		fi
		need_rebind=1
	fi

	# 4) Raw register programming — final values for all supported A2D types.
	if ! configure_a2d_registers_raw "$device_json" "$device_name" "$bus" "$address" "$device_type" "$num_channels" "$hw_channel_id"; then
		log_message "info" "Register programming failed — try next Device alternative"
		if [ "$need_rebind" -eq 1 ] && json_probe_true "$device_json"; then
			rebind_kernel_driver "$bus" "$address" "$device_type"
		fi
		return 1
	fi

	# 5) Rebind for IIO sysfs when Probe is true and we unbound for step 4.
	if json_probe_true "$device_json"; then
		if [ "$need_rebind" -eq 1 ]; then
			if ! rebind_kernel_driver "$bus" "$address" "$device_type"; then
				if ! probe_i2c_sysfs_present "$bus" "$address"; then
					log_message "info" "Rebind failed and no I2C client in sysfs — try next alternative"
					return 1
				fi
			fi
		elif ! i2c_client_has_bound_driver "$bus" "$address"; then
			if ! bind_kernel_driver "$bus" "$address" "$device_type"; then
				if ! probe_i2c_sysfs_present "$bus" "$address"; then
					log_message "info" "Bind failed and no I2C client in sysfs — try next alternative"
					return 1
				fi
			fi
		fi
	fi

	log_message "info" "Device configuration complete for $device_name"
	return 0
}

# Resolve one Device[] entry for a leak detector. Sets resolved_json and resolved_type on success.
resolve_leak_device_entry()
{
	local detector_block="$1"
	local device_json="$2"
	local d="$3"
	local detector_name="$4"
	local address bus device_type rc_ads

	resolved_json=""
	resolved_type=""
	address=$(echo "$device_json" | json_get_string "Address")
	bus=$(echo "$device_json" | json_get_number "Bus")
	device_type=$(echo "$device_json" | json_get_string "DeviceType")

	if [ "$device_type" = "ADS1015" ]; then
		if [ "$d" -gt 0 ]; then
			if ! probe_i2c_device "$bus" "$address"; then
				log_message "info" "Leak detector $detector_name: ADS1015 fallback — presence failed at bus $bus addr $address"
				return 1
			fi
			resolved_json="$device_json"
			resolved_type="ADS1015"
			return 0
		fi
		resolved_json=$(resolve_ads1015_device_entry "$detector_block" "$device_json" "$bus" "$address")
		rc_ads=$?
		if [ "$rc_ads" -ne 0 ] || [ -z "$resolved_json" ]; then
			return 1
		fi
		resolved_type=$(echo "$resolved_json" | json_get_string "DeviceType")
		return 0
	fi

	if ! device_entry_matches_hw "$bus" "$address" "$device_type"; then
		return 1
	fi
	resolved_json="$device_json"
	resolved_type="$device_type"
	return 0
}

# Function to process all leak detectors
process_leak_detectors()
{
	local num_detectors
	num_detectors=$(json_count_array_elements "$CONFIG_FILE")

	log_message "info" "Found $num_detectors leak detector configurations"

	local total_configured=0
	local total_skipped=0

	local i=0
	while [ "$i" -lt "$num_detectors" ]; do
		local detector_block detector_name num_channels chnames num_devices d device_json address bus device_type device_found resolved_json resolved_type cfg_rc rc_ads
		detector_block=$(json_get_array_element "$CONFIG_FILE" "$i")

		detector_name=$(echo "$detector_block" | json_get_string "Name")

		num_channels=$(echo "$detector_block" | json_get_number "NumChnl")
		[ -z "$num_channels" ] && num_channels=0

		chnames=""
		if [ "$num_channels" -gt 0 ]; then
			while IFS= read -r ch_name; do
				[ -z "$ch_name" ] && continue
				chnames="$chnames${chnames:+ }$ch_name"
			done <<EOF
$(echo "$detector_block" | json_get_array "ChnlNames")
EOF
		fi

		num_devices=$(echo "$detector_block" | json_count_nested_array "Device")

		if [ -z "$detector_name" ]; then
			i=$((i + 1))
			continue
		fi

		log_message "info" "Processing leak detector: $detector_name (Channels: $num_channels)"

		device_found=0
		if leak_detector_per_channel_devices "$detector_block"; then
			local channels_configured logical_ch hw_channel_id
			log_message "info" "Leak detector $detector_name: per-channel Device[] map ($num_devices entries)"
			channels_configured=0
			d=0
			while [ "$d" -lt "$num_devices" ]; do
				device_json=$(echo "$detector_block" | json_get_nested_array_element "Device" "$d")
				if ! resolve_leak_device_entry "$detector_block" "$device_json" "$d" "$detector_name"; then
					d=$((d + 1))
					continue
				fi
				logical_ch=$((d + 1))
				hw_channel_id=$(json_device_hw_channel_id "$resolved_json" "$logical_ch")
				bus=$(echo "$resolved_json" | json_get_number "Bus")
				address=$(echo "$resolved_json" | json_get_string "Address")
				configure_device "$resolved_json" "$detector_name" 1 "$chnames" "$hw_channel_id"
				cfg_rc=$?
				if [ "$cfg_rc" -ne 0 ]; then
					log_message "info" "Leak detector $detector_name: channel $logical_ch (hardware $hw_channel_id) did not complete"
					d=$((d + 1))
					continue
				fi
				populate_single_leakage_channel "$((i + 1))" "$logical_ch" "$resolved_type" "$resolved_json" "$bus" "$address" "$chnames" "$detector_name"
				channels_configured=$((channels_configured + 1))
				d=$((d + 1))
			done
			if [ "$channels_configured" -gt 0 ]; then
				device_found=1
				total_configured=$((total_configured + 1))
				log_message "info" "Leak detector $detector_name: configured $channels_configured of $num_devices channel device(s)"
			fi
		else
		d=0
		while [ "$d" -lt "$num_devices" ]; do
			device_json=$(echo "$detector_block" | json_get_nested_array_element "Device" "$d")
			if ! resolve_leak_device_entry "$detector_block" "$device_json" "$d" "$detector_name"; then
				d=$((d + 1))
				continue
			fi
			bus=$(echo "$resolved_json" | json_get_number "Bus")
			address=$(echo "$resolved_json" | json_get_string "Address")

			configure_device "$resolved_json" "$detector_name" "$num_channels" "$chnames" 0
			cfg_rc=$?
			if [ "$cfg_rc" -ne 0 ]; then
				log_message "info" "Leak detector $detector_name: alternative $((d + 1)) did not complete — trying next Device entry"
				d=$((d + 1))
				continue
			fi
			device_found=1
			total_configured=$((total_configured + 1))
			create_channel_infrastructure "$((i + 1))" "$resolved_type" "$num_channels" "$resolved_json" "$bus" "$address" "$chnames" "$detector_name"
			break
		done
		fi

		if [ "$device_found" -eq 0 ]; then
			log_message "warning" "No A2D device found for $detector_name"
			total_skipped=$((total_skipped + 1))
		fi

		i=$((i + 1))
	done

	log_message "info" "A2D configuration complete: $total_configured devices configured, $total_skipped detectors skipped"
}

# Main execution
main()
{
	log_message "info" "A2D Leakage Detection Configuration Tool"

	if ! check_dependencies; then
		log_message "err" "Dependency check failed - exiting"
		exit 1
	fi

	if ! check_config_file; then
		log_message "err" "Configuration file check failed - exiting"
		exit 1
	fi

	process_leak_detectors

	log_message "info" "A2D Configuration Script Completed"

	exit 0
}

main "$@"
