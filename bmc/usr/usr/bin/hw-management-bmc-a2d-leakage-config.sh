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
		log_message "err" "i2ctransfer is not installed. Cannot configure I2C devices."
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

# Optional JSON field "Probe": true — bind kernel driver (new_device) before register writes so
# the driver does not later overwrite programmed thresholds/configuration.
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
	*) echo "" ;;
	esac
}

# Instantiate device on I2C bus so the kernel driver binds (when Probe is true).
# If the client already exists (e.g. early-i2c-init), skip quietly.
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
	local dev_id
	dev_id=$(printf '%d-%04x' "$bus" $((16#$a)))
	if [ -d "/sys/bus/i2c/devices/$dev_id" ]; then
		log_message "info" "I2C device $dev_id already present — assuming driver or early init"
		return 0
	fi
	log_message "info" "Binding $driver at $address on bus $bus (new_device before register config)"
	if ! echo "$driver $address" > "${adapter}/new_device" 2>/dev/null; then
		log_message "warning" "new_device failed for $driver $address on i2c-$bus (driver missing or device conflict) — continuing with raw I2C config"
		return 1
	fi
	sleep 0.2
	return 0
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
# Heuristic (not address-based): MAX1363 bring-up often returns 0x7f on single-byte read of pointer 0x00;
# then require Configuration register (pointer 0x01, 2 bytes) not 0xFF 0xFF.
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

# Function to write and verify register
write_and_verify_register()
{
	local bus="$1"
	local addr="$2"
	local reg="$3"
	local reg_val="$4"
	local reg_name="$5"
	local device_name="$6"

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

	if [ "$read_n" != "$exp_n" ]; then
		log_message "warning" "$reg_name mismatch on $device_name (Bus $bus, Addr $addr): expected hex [$exp_n] from [$reg_val], readback hex [$read_n] from i2ctransfer — continuing"
		return 1
	fi

	log_message "info" "$reg_name verified successfully on $device_name"
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
populate_leakage_channel_dir()
{
	local ch_dir="$1"
	local ch_num="$2"
	local device_json="$3"
	local bus="$4"
	local address="$5"
	local device_type="$6"

	rm -f "$ch_dir/min" "$ch_dir/max" "$ch_dir/warn" "$ch_dir/crit" "$ch_dir/lwarn" "$ch_dir/lcrit" "$ch_dir/type" "$ch_dir/scale" "$ch_dir/input" "$ch_dir/channel_name"

	local scale_s=""
	if scale_s=$(json_optional_scalar "$device_json" "Scale"); then
		echo "$scale_s" >"$ch_dir/scale"
	fi
	local sc_num="${scale_s:-1}"
	[ -z "$sc_num" ] && sc_num=1

	local v
	if v=$(json_optional_scalar "$device_json" "WarningMax"); then
		echo "$v" >"$ch_dir/warn"
	fi
	if v=$(json_optional_scalar "$device_json" "CriticalMax"); then
		echo "$v" >"$ch_dir/crit"
	fi
	if v=$(json_optional_scalar "$device_json" "WarningMin"); then
		echo "$v" >"$ch_dir/lwarn"
	fi
	if v=$(json_optional_scalar "$device_json" "CriticalMin"); then
		echo "$v" >"$ch_dir/lcrit"
	fi
	if v=$(json_optional_scalar "$device_json" "Type"); then
		echo "$v" >"$ch_dir/type"
	fi

	local lo_hex hi_hex
	lo_hex=$(echo "$device_json" | json_get_string "LoThreshRegVal" 2>/dev/null) || true
	hi_hex=$(echo "$device_json" | json_get_string "HiThreshRegVal" 2>/dev/null) || true
	lo_hex=$(echo "$lo_hex" | tr -d '"')
	hi_hex=$(echo "$hi_hex" | tr -d '"')

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

	# min/max when Lo/Hi register hex absent (e.g. MAX1363): optional NormalMin/NormalMax scalars, else WarningMin/WarningMax
	if [ ! -f "$ch_dir/min" ]; then
		if v=$(json_optional_scalar "$device_json" "NormalMin"); then
			echo "$v" >"$ch_dir/min"
		elif v=$(json_optional_scalar "$device_json" "WarningMin"); then
			echo "$v" >"$ch_dir/min"
		fi
	fi
	if [ ! -f "$ch_dir/max" ]; then
		if v=$(json_optional_scalar "$device_json" "NormalMax"); then
			echo "$v" >"$ch_dir/max"
		elif v=$(json_optional_scalar "$device_json" "WarningMax"); then
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
			raw_path=$(find_iio_channel_raw "$dev_id" "$((ch_num - 1))")
			[ -n "$raw_path" ] && [ -f "$raw_path" ] && break
			sleep 0.2
		done
		if [ -n "$raw_path" ] && [ -f "$raw_path" ]; then
			check_n_link "$raw_path" "$ch_dir/input"
			log_message "info" "Channel $ch_num input -> $raw_path"
		else
			log_message "warning" "No IIO raw sysfs for channel $ch_num (device $dev_id, type $device_type) — check /sys/bus/i2c/devices/$dev_id and /sys/bus/iio/devices"
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
	echo "$device_type" >"$leakage_base/device_type"
	if [ -n "$detector_name" ]; then
		echo "$detector_name" >"$leakage_base/device_name"
	fi
	log_message "info" "Leakage runtime: $leakage_base (device_type=$device_type)"

	if json_probe_true "$device_json"; then
		sleep 0.5
	fi

	local ch=1
	local channel_name
	while [ "$ch" -le "$num_channels" ]; do
		mkdir -p "$leakage_base/$ch"
		populate_leakage_channel_dir "$leakage_base/$ch" "$ch" "$device_json" "$bus" "$address" "$device_type"
		channel_name=$(echo "$chnames" | awk -v c="$ch" '{print $c}')
		if [ -n "$channel_name" ]; then
			echo "$channel_name" >"$leakage_base/$ch/channel_name"
			log_message "info" "Channel $ch channel_name=$channel_name"
		fi
		ch=$((ch + 1))
	done

	return 0
}

# Args: device_json, device_name, num_channels, chnames (space-separated words from ChnlNames)
configure_device()
{
	local device_json="$1"
	local device_name="$2"
	local num_channels="$3"
	local chnames="$4"

	# Extract device parameters using library functions
	local device_type bus address cfg_reg cfg_reg_val lo_thresh_reg lo_thresh_val hi_thresh_reg hi_thresh_val
	device_type=$(echo "$device_json" | json_get_string "DeviceType")
	bus=$(echo "$device_json" | json_get_number "Bus")
	address=$(echo "$device_json" | json_get_string "Address")
	cfg_reg=$(echo "$device_json" | json_get_string "CfgReg")
	cfg_reg_val=$(echo "$device_json" | json_get_string "CfgRegVal")
	lo_thresh_reg=$(echo "$device_json" | json_get_string "LoThreshReg")
	lo_thresh_val=$(echo "$device_json" | json_get_string "LoThreshRegVal")
	hi_thresh_reg=$(echo "$device_json" | json_get_string "HiThreshReg")
	hi_thresh_val=$(echo "$device_json" | json_get_string "HiThreshRegVal")

	log_message "info" "Checking $device_type device at Bus $bus, Address $address for $device_name"

	# 1) Presence probe (SMBus/i2ctransfer or sysfs client) — no part ID from address
	if ! probe_i2c_device "$bus" "$address"; then
		log_message "info" "Presence probe failed at Bus $bus, Address $address — try next alternative"
		return 1
	fi
	log_message "info" "Presence probe OK at Bus $bus, Address $address (DeviceType=$device_type from JSON)"

	log_message "info" "Configuring $device_type for $device_name..."

	# 2) Optional kernel driver bind before register access (JSON Probe)
	if json_probe_true "$device_json"; then
		if ! bind_kernel_driver "$bus" "$address" "$device_type"; then
			if ! probe_i2c_sysfs_present "$bus" "$address"; then
				log_message "info" "Bind failed and no I2C client in sysfs — try next alternative"
				return 1
			fi
		fi
	fi

	# 3) Register writes via i2ctransfer only when no kernel driver owns the client — otherwise
	#    userspace gets "No such device or address"; configuration is expected from the driver / IIO.
	if i2c_client_has_bound_driver "$bus" "$address"; then
		log_message "info" "Kernel driver bound — skipping raw i2ctransfer register writes for $device_name (Bus $bus, Addr $address); use driver sysfs or program before bind if needed"
		log_message "info" "Device configuration complete for $device_name: register writes skipped (driver active)"
		return 0
	fi

	local success=0
	local failed=0

	# Write and verify configuration register (if provided)
	if [ -n "$cfg_reg" ] && [ -n "$cfg_reg_val" ] && [ "$cfg_reg" != "null" ] && [ "$cfg_reg_val" != "null" ]; then
		if write_and_verify_register "$bus" "$address" "$cfg_reg" "$cfg_reg_val" "Configuration Register" "$device_name"; then
			success=$((success + 1))
		else
			failed=$((failed + 1))
		fi
	fi

	# Write and verify low threshold register (if provided)
	if [ -n "$lo_thresh_reg" ] && [ -n "$lo_thresh_val" ] && [ "$lo_thresh_reg" != "null" ] && [ "$lo_thresh_val" != "null" ]; then
		if write_and_verify_register "$bus" "$address" "$lo_thresh_reg" "$lo_thresh_val" "Low Threshold Register" "$device_name"; then
			success=$((success + 1))
		else
			failed=$((failed + 1))
		fi
	fi

	# Write and verify high threshold register (if provided)
	if [ -n "$hi_thresh_reg" ] && [ -n "$hi_thresh_val" ] && [ "$hi_thresh_reg" != "null" ] && [ "$hi_thresh_val" != "null" ]; then
		if write_and_verify_register "$bus" "$address" "$hi_thresh_reg" "$hi_thresh_val" "High Threshold Register" "$device_name"; then
			success=$((success + 1))
		else
			failed=$((failed + 1))
		fi
	fi

	log_message "info" "Device configuration complete for $device_name: $success successful, $failed failed"

	if [ "$failed" -gt 0 ]; then
		log_message "info" "Register programming had failures — try next Device alternative"
		return 1
	fi

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
		d=0
		while [ "$d" -lt "$num_devices" ]; do
			device_json=$(echo "$detector_block" | json_get_nested_array_element "Device" "$d")
			address=$(echo "$device_json" | json_get_string "Address")
			bus=$(echo "$device_json" | json_get_number "Bus")

			device_type=$(echo "$device_json" | json_get_string "DeviceType")
			resolved_json=""
			resolved_type=""

			if [ "$device_type" = "ADS1015" ]; then
				if [ "$d" -gt 0 ]; then
					# Explicit fallback after an earlier Device[] entry — use JSON as-is (no TI/MAX template swap).
					if ! probe_i2c_device "$bus" "$address"; then
						log_message "info" "Leak detector $detector_name: ADS1015 fallback — presence failed at bus $bus addr $address"
						d=$((d + 1))
						continue
					fi
					resolved_json="$device_json"
					resolved_type="ADS1015"
				else
					resolved_json=$(resolve_ads1015_device_entry "$detector_block" "$device_json" "$bus" "$address")
					rc_ads=$?
					if [ "$rc_ads" -ne 0 ] || [ -z "$resolved_json" ]; then
						d=$((d + 1))
						continue
					fi
					resolved_type=$(echo "$resolved_json" | json_get_string "DeviceType")
				fi
			else
				if ! device_entry_matches_hw "$bus" "$address" "$device_type"; then
					d=$((d + 1))
					continue
				fi
				resolved_json="$device_json"
				resolved_type="$device_type"
			fi

			configure_device "$resolved_json" "$detector_name" "$num_channels" "$chnames"
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
