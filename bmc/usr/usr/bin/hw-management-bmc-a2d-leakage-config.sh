#!/bin/bash
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

# Deployed by hw-management-bmc-early-config from usr/etc/<HID>/hw-management-a2d-leakage-config.json
CONFIG_FILE="/etc/hw-management-bmc/a2d-leakage-config.json"
LOG_TAG="a2d_config"

# Source JSON parser library (BusyBox compatible)
if [ -f /usr/bin/switch_json_parser.sh ]; then
    source /usr/bin/switch_json_parser.sh
elif [ -f ./switch_json_parser.sh ]; then
    source ./switch_json_parser.sh
else
    echo "ERROR: switch_json_parser.sh not found"
    exit 1
fi

if [ -f /usr/bin/hw-management-bmc-helpers.sh ]; then
	# shellcheck source=/dev/null
	. /usr/bin/hw-management-bmc-helpers.sh
fi
if ! declare -F check_n_link >/dev/null 2>&1; then
	check_n_link()
	{
		[[ -f "$1" ]] && ln -sf "$1" "$2"
	}
fi

# Function to log messages
log_message()
{
    local level="$1"
    local message="$2"
    logger -t "$LOG_TAG" -p "daemon.$level" "$message"
    echo "[$level] $message"
}

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
    if [[ ! -f "$CONFIG_FILE" ]]; then
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
json_probe_true()
{
	local json="$1"
	local v
	v=$(echo "$json" | json_get_string "Probe" 2>/dev/null) || true
	v=$(echo "$v" | tr '[:upper:]' '[:lower:]')
	v="${v//\"/}"
	v="${v//\'/}"
	[[ "$v" == "true" ]] || [[ "$v" == "1" ]] || [[ "$v" == "yes" ]]
}

# Map DeviceType to Linux i2c driver name for /sys/.../i2c-<bus>/new_device
kernel_driver_for_type()
{
	case "$1" in
	MAX1363) echo "max1363" ;;
	ADS7142) echo "ads7142" ;;
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
	if [[ -z "$driver" ]]; then
		log_message "warning" "No kernel driver mapping for $device_type — skipping bind"
		return 0
	fi
	local adapter="/sys/bus/i2c/devices/i2c-${bus}"
	if [[ ! -d "$adapter" ]]; then
		log_message "warning" "I2C adapter not found: $adapter — skipping bind"
		return 1
	fi
	local a="${address#0x}"
	a="${a#0X}"
	local dev_id
	printf -v dev_id '%d-%04x' "$bus" $((16#$a))
	if [[ -d "/sys/bus/i2c/devices/$dev_id" ]]; then
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
    else
        return 1
    fi
}

# Function to detect device type by address
detect_device_type()
{
    local addr="$1"
 
    # Remove 0x prefix if present
    addr="${addr#0x}"
    addr="${addr#0X}"

    case "$addr" in
        34|35)
            echo "MAX1363"
            ;;
        48|49)
            echo "ADS7142"
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
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

    # Count number of bytes in reg_val
    local val_bytes=($reg_val)
    local num_bytes=${#val_bytes[@]}

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

    if [[ $read_status -ne 0 ]]; then
        log_message "warning" "Failed to read back $reg_name on $device_name (Bus $bus, Addr $addr) - continuing"
        return 1
    fi

    # Normalize the readback value (remove 0x prefixes, spaces, and newlines)
    readback=$(echo "$readback" | sed 's/0x//g' | tr -d ' \n')
    local expected=$(echo "$reg_val" | sed 's/0x//g' | tr -d ' ')

    if [[ "$readback" != "$expected" ]]; then
        log_message "warning" "$reg_name mismatch on $device_name (Bus $bus, Addr $addr): expected [$reg_val], got [$readback] - continuing"
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
	v="${v//\"/}"
	if [[ -z "$v" || "$v" == "null" ]]; then
		v=$(echo "$json" | json_get_number "$key" 2>/dev/null) || true
	fi
	[[ -z "$v" || "$v" == "null" ]] && return 1
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
		sum=$(( sum * 256 + 16#$x ))
	done
	echo "$sum"
}

# sysfs path for IIO raw sample: in_voltage<idx>_raw under client's iio:device*.
find_iio_channel_raw()
{
	local dev_id="$1"
	local idx="$2"
	local f iio
	for iio in /sys/bus/i2c/devices/"$dev_id"/iio:device*; do
		[[ -d "$iio" ]] || continue
		for f in "$iio/in_voltage${idx}_raw" "$iio/in_voltage${idx}_input"; do
			[[ -f "$f" ]] && { echo "$f"; return 0; }
		done
	done
	for iio in /sys/bus/i2c/devices/"$dev_id"/iio:device*; do
		[[ -d "$iio" ]] || continue
		[[ -f "$iio/in_voltage_raw" ]] && { echo "$iio/in_voltage_raw"; return 0; }
	done
	return 1
}

# Per-channel files under /var/run/.../leakage/<i>/<j>/ (see README).
populate_leakage_channel_dir()
{
	local ch_dir="$1"
	local ch_num="$2"
	local device_json="$3"
	local bus="$4"
	local address="$5"
	local device_type="$6"

	rm -f "$ch_dir/min" "$ch_dir/max" "$ch_dir/crit" "$ch_dir/emerg" "$ch_dir/scale" "$ch_dir/input"

	local scale_s=""
	if scale_s=$(json_optional_scalar "$device_json" "Scale"); then
		echo "$scale_s" > "$ch_dir/scale"
	fi
	local sc_num="${scale_s:-1}"
	[[ -z "$sc_num" ]] && sc_num=1

	local v
	if v=$(json_optional_scalar "$device_json" "CriticalMax"); then
		echo "$v" > "$ch_dir/crit"
	fi
	if v=$(json_optional_scalar "$device_json" "EmergencyMax"); then
		echo "$v" > "$ch_dir/emerg"
	fi

	local lo_hex hi_hex
	lo_hex=$(echo "$device_json" | json_get_string "LoThreshRegVal" 2>/dev/null) || true
	hi_hex=$(echo "$device_json" | json_get_string "HiThreshRegVal" 2>/dev/null) || true
	lo_hex="${lo_hex//\"/}"
	hi_hex="${hi_hex//\"/}"

	if [[ -n "$lo_hex" && "$lo_hex" != "null" ]]; then
		local lo_u
		lo_u=$(hex_bytes_to_uint_be "$lo_hex")
		awk -v u="$lo_u" -v s="$sc_num" 'BEGIN { printf "%.12g\n", u * s }' > "$ch_dir/min"
	fi
	if [[ -n "$hi_hex" && "$hi_hex" != "null" ]]; then
		local hi_u
		hi_u=$(hex_bytes_to_uint_be "$hi_hex")
		awk -v u="$hi_u" -v s="$sc_num" 'BEGIN { printf "%.12g\n", u * s }' > "$ch_dir/max"
	fi

	if json_probe_true "$device_json"; then
		local a="${address#0x}"
		a="${a#0X}"
		local dev_id
		printf -v dev_id '%d-%04x' "$bus" $((16#$a))
		local raw_path
		raw_path=$(find_iio_channel_raw "$dev_id" "$((ch_num - 1))")
		if [[ -n "$raw_path" ]]; then
			check_n_link "$raw_path" "$ch_dir/input"
			log_message "info" "Channel $ch_num input -> $raw_path"
		else
			log_message "warning" "No IIO raw sysfs for channel $ch_num (device $dev_id, type $device_type)"
		fi
	fi
}

# Runtime layout (per A2D / leak-detector index i):
#   /var/run/hw-management/leakage/<i>/device_type
#   /var/run/hw-management/leakage/<i>/<j>/input (symlink if Probe) — kernel raw reading
#   /var/run/hw-management/leakage/<i>/<j>/{min,max,crit,emerg,scale} — see README
#   /var/run/hw-management/leakage/<i>/<ChnlNames[k]> -> symlink to channel number
create_channel_infrastructure()
{
	local device_index="$1"
	local device_type="$2"
	local num_channels="$3"
	local device_json="$4"
	local bus="$5"
	local address="$6"
	shift 6
	local channel_names=("$@")

	if [[ ! -d "/var/run/hw-management" ]]; then
		log_message "info" "/var/run/hw-management does not exist - skipping channel infrastructure creation"
		return 0
	fi

	local leakage_base="/var/run/hw-management/leakage/$device_index"
	mkdir -p "$leakage_base"
	echo "$device_type" > "$leakage_base/device_type"
	log_message "info" "Leakage runtime: $leakage_base (device_type=$device_type)"

	if json_probe_true "$device_json"; then
		sleep 0.5
	fi

	for ((ch=1; ch<=num_channels; ch++)); do
		mkdir -p "$leakage_base/$ch"
		populate_leakage_channel_dir "$leakage_base/$ch" "$ch" "$device_json" "$bus" "$address" "$device_type"
		if [[ $ch -le ${#channel_names[@]} ]] && [[ -n "${channel_names[$ch-1]}" ]]; then
			local channel_name="${channel_names[$ch-1]}"
			rm -f "$leakage_base/$channel_name"
			ln -s "$ch" "$leakage_base/$channel_name"
			log_message "info" "Channel $ch -> $leakage_base/$channel_name"
		fi
	done

	return 0
}

# Function to configure a single device
configure_device()
{
    local device_json="$1"
    local device_name="$2"
    local num_channels="$3"
    shift 3
    local channel_names=("$@")

    # Extract device parameters using library functions
    local device_type=$(echo "$device_json" | json_get_string "DeviceType")
    local bus=$(echo "$device_json" | json_get_number "Bus")
    local address=$(echo "$device_json" | json_get_string "Address")
    local cfg_reg=$(echo "$device_json" | json_get_string "CfgReg")
    local cfg_reg_val=$(echo "$device_json" | json_get_string "CfgRegVal")
    local lo_thresh_reg=$(echo "$device_json" | json_get_string "LoThreshReg")
    local lo_thresh_val=$(echo "$device_json" | json_get_string "LoThreshRegVal")
    local hi_thresh_reg=$(echo "$device_json" | json_get_string "HiThreshReg")
    local hi_thresh_val=$(echo "$device_json" | json_get_string "HiThreshRegVal")


    log_message "info" "Checking $device_type device at Bus $bus, Address $address for $device_name"

    # Probe device
    if ! probe_i2c_device "$bus" "$address"; then
        log_message "info" "Device not present at Bus $bus, Address $address - skipping"
        return 0
    fi

    # Verify device type matches address convention
    local expected_type=$(detect_device_type "$address")
    if [[ "$expected_type" != "$device_type" ]]; then
        log_message "warning" "Device type mismatch: config says $device_type but address $address suggests $expected_type"
    fi

    log_message "info" "Found $device_type at Bus $bus, Address $address - configuring..."

    # Bind kernel driver first when requested (before register writes)
    if json_probe_true "$device_json"; then
        bind_kernel_driver "$bus" "$address" "$device_type" || true
    fi

    # Configure registers
    local success=0
    local failed=0

    # Write and verify configuration register (if provided)
    if [[ -n "$cfg_reg" ]] && [[ -n "$cfg_reg_val" ]] && [[ "$cfg_reg" != "null" ]] && [[ "$cfg_reg_val" != "null" ]]; then
        if write_and_verify_register "$bus" "$address" "$cfg_reg" "$cfg_reg_val" "Configuration Register" "$device_name"; then
            ((success++))
        else
            ((failed++))
        fi
    fi

    # Write and verify low threshold register (if provided)
    if [[ -n "$lo_thresh_reg" ]] && [[ -n "$lo_thresh_val" ]] && [[ "$lo_thresh_reg" != "null" ]] && [[ "$lo_thresh_val" != "null" ]]; then
        if write_and_verify_register "$bus" "$address" "$lo_thresh_reg" "$lo_thresh_val" "Low Threshold Register" "$device_name"; then
            ((success++))
        else
            ((failed++))
        fi
    fi

    # Write and verify high threshold register (if provided)
    if [[ -n "$hi_thresh_reg" ]] && [[ -n "$hi_thresh_val" ]] && [[ "$hi_thresh_reg" != "null" ]] && [[ "$hi_thresh_val" != "null" ]]; then
        if write_and_verify_register "$bus" "$address" "$hi_thresh_reg" "$hi_thresh_val" "High Threshold Register" "$device_name"; then
            ((success++))
        else
            ((failed++))
        fi
    fi

    log_message "info" "Device configuration complete for $device_name: $success successful, $failed failed"

    return 0
}

# Function to process all leak detectors
process_leak_detectors()
{
    local num_detectors
    # Count top-level detector objects using library function
    num_detectors=$(json_count_array_elements "$CONFIG_FILE")
    
    log_message "info" "Found $num_detectors leak detector configurations"

    local total_configured=0
    local total_skipped=0

    # Iterate through each leak detector
    for ((i=0; i<num_detectors; i++)); do
        # Get detector block using library function
        local detector_block=$(json_get_array_element "$CONFIG_FILE" "$i")
        
        local detector_name=$(echo "$detector_block" | json_get_string "Name")
        
        # Extract channel information (common for all device alternatives)
        local num_channels=$(echo "$detector_block" | json_get_number "NumChnl")
        [[ -z "$num_channels" ]] && num_channels=0
        
        # Get channel names using library function
        local channel_names=()
        if [[ "$num_channels" -gt 0 ]]; then
            while IFS= read -r ch_name; do
                [[ -n "$ch_name" ]] && channel_names+=("$ch_name")
            done < <(echo "$detector_block" | json_get_array "ChnlNames")
        fi
        
        # Get number of device alternatives using library function
        local num_devices=$(echo "$detector_block" | json_count_nested_array "Device")

        # Skip if detector name is empty (parsing error)
        if [[ -z "$detector_name" ]]; then
            continue
        fi
        
        log_message "info" "Processing leak detector: $detector_name (Channels: $num_channels)"

        # Iterate through each device alternative for this detector
        local device_found=0
        for ((d=0; d<num_devices; d++)); do
            local device_json=$(echo "$detector_block" | json_get_nested_array_element "Device" "$d")
            local address=$(echo "$device_json" | json_get_string "Address")
            local bus=$(echo "$device_json" | json_get_number "Bus")

            # Check if this device is present
            if probe_i2c_device "$bus" "$address"; then
                local device_type
                device_type=$(echo "$device_json" | json_get_string "DeviceType")
                configure_device "$device_json" "$detector_name" "$num_channels" "${channel_names[@]}"
                device_found=1
                ((total_configured++))
                # One directory per leak-detector entry (1-based index in JSON array)
                create_channel_infrastructure "$((i + 1))" "$device_type" "$num_channels" "$device_json" "$bus" "$address" "${channel_names[@]}"
                break  # Only configure the first detected device for this detector
            fi
        done

        if [[ $device_found -eq 0 ]]; then
            log_message "warning" "No A2D device found for $detector_name"
            ((total_skipped++))
        fi
    done

    log_message "info" "A2D configuration complete: $total_configured devices configured, $total_skipped detectors skipped"
}

# Main execution
main()
{
    log_message "info" "A2D Leakage Detection Configuration Tool"

    # Check dependencies
    if ! check_dependencies; then
        log_message "err" "Dependency check failed - exiting"
        exit 1
    fi

    # Check configuration file
    if ! check_config_file; then
        log_message "err" "Configuration file check failed - exiting"
        exit 1
    fi

    # Process all leak detectors
    process_leak_detectors

    log_message "info" "A2D Configuration Script Completed"

    exit 0
}

# Execute main function
main "$@"

