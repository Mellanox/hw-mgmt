#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# BMC Early I2C Device Initialization Script
#
# This script creates early I2C devices by reading from a machine-specific
# configuration file: /etc/bmc-early-i2c-devices.json
#
# JSON format:
# {
#     "devices": [
#         {
#             "bus": 0,
#             "address": "0x4c",
#             "driver": "sbtsi",
#             "description": "CPU temperature sensor interface"
#         }
#     ]
# }
################################################################################

CONFIG_FILE="/etc/bmc-early-i2c-devices.json"

# Source the JSON parser library
# shellcheck source=/dev/null
source /usr/bin/switch_json_parser.sh

# Check if I2C device already exists in sysfs
# Usage: device_exists <bus> <addr>
# Returns: 0 if exists, 1 if not
device_exists()
{
    local bus="$1"
    local addr="$2"
    
    # Convert address to 4-digit format (e.g., 0x4c -> 004c)
    local addr_sysfs
    addr_sysfs=$(printf "%04x" "$addr")
    local device_path="/sys/bus/i2c/devices/${bus}-${addr_sysfs}"
    
    [[ -e "$device_path" ]]
}

# Create an I2C device by writing to sysfs new_device file
# Usage: create_device <bus> <addr> <driver> <description>
create_device()
{
    local bus="$1"
    local addr="$2"
    local driver="$3"
    local description="$4"
    
    local new_device_path="/sys/bus/i2c/devices/i2c-${bus}/new_device"
    local addr_hex
    addr_hex=$(printf "0x%02x" "$addr")
    
    if device_exists "$bus" "$addr"; then
        echo "Device already exists: i2c-${bus}:${addr_hex}"
        return 0
    fi
    
    echo "Creating ${driver} device (i2c-${bus}:${addr_hex}) - ${description}"
    
    if ! echo "${driver} ${addr_hex}" > "$new_device_path" 2>/dev/null; then
        echo "Warning: Failed to create device"
        return 1
    fi
    
    return 0
}

# Parse address (supports hex string like '0x4c' or integer)
# Usage: parse_address <addr>
# Returns: decimal integer
parse_address()
{
    local addr="$1"
    
    # Remove leading/trailing whitespace
    addr="${addr#"${addr%%[![:space:]]*}"}"
    addr="${addr%"${addr##*[![:space:]]}"}"
    
    # Check if hex format (0x or 0X prefix)
    if [[ "$addr" =~ ^0[xX] ]]; then
        printf "%d" "$addr"
    else
        echo "$addr"
    fi
}

main()
{
    echo "BMC Early I2C Device Initialization"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: Configuration file ${CONFIG_FILE} not found"
        return 1
    fi
    
    # Validate JSON file
    if ! json_validate "$CONFIG_FILE"; then
        echo "ERROR: Failed to parse JSON config file"
        return 1
    fi
    
    # Count devices in the array
    local device_count
    device_count=$(cat "$CONFIG_FILE" | json_count_nested_array "devices")
    
    if [[ "$device_count" -eq 0 ]]; then
        echo "WARNING: No devices configured"
        return 0
    fi
    
    # Process each device
    local i=0
    while [[ $i -lt $device_count ]]; do
        # Get the device object
        local device_json
        device_json=$(cat "$CONFIG_FILE" | json_get_nested_array_element "devices" "$i")
        
        if [[ -z "$device_json" ]]; then
            echo "Warning: Skipping empty device entry at index $i"
            ((i++))
            continue
        fi
        
        # Extract fields from the device object
        local bus addr_str driver description
        bus=$(echo "$device_json" | json_get_number "bus")
        addr_str=$(echo "$device_json" | json_get_string "address")
        driver=$(echo "$device_json" | json_get_string "driver")
        description=$(echo "$device_json" | json_get_string "description")
        
        # Validate required fields
        if [[ -z "$bus" ]] || [[ -z "$addr_str" ]] || [[ -z "$driver" ]]; then
            echo "Warning: Skipping malformed device entry at index $i (missing bus, address, or driver)"
            ((i++))
            continue
        fi
        
        # Parse the address
        local addr
        addr=$(parse_address "$addr_str")
        
        # Create the device
        create_device "$bus" "$addr" "$driver" "$description"
        
        ((i++))
    done
    
    echo "BMC Early I2C Device Initialization complete"
    return 0
}

main "$@"
