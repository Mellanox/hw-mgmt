#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# Voltage Regulator DPC Update - Batch Processor
# The purpose is to update configuration of the voltage regulator devices.
# The list of devices and files for flashing are provided by json file.
################################################################################

LOG_TAG="vr_dpc_update_all"
DPC_UPDATE_SCRIPT="/usr/bin/hw-management-vr-dpc-update.sh"

# Function to log messages
log_message()
{
    local level="$1"
    local message="$2"
    logger -t "$LOG_TAG" -p "daemon.$level" "$message"
    echo "[$level] $message"
}

# Function to display usage
usage()
{
    echo "Usage: $0 [OPTIONS] <json_config_file>"
    echo ""
    echo "Batch Voltage Regulator DPC Update from JSON configuration"
    echo ""
    echo "OPTIONS:"
    echo "  --validate-json    Validate JSON configuration file and exit"
    echo "  --help             Display this help message"
    echo ""
    echo "Arguments:"
    echo "  json_config_file   Path to JSON configuration file"
    echo ""
    echo "JSON Format:"
    echo "  {"
    echo "    \"System HID\": \"HI180\","
    echo "    \"Devices\": ["
    echo "      {"
    echo "        \"DeviceType\": \"mp2975\","
    echo "        \"Bus\": 12,"
    echo "        \"ConfigFile\": \"path/to/config.csv\","
    echo "        \"CrcFile\": \"path/to/crc.txt\","
    echo "        \"DeviceConfigFile\": \"path/to/device_config.conf\""
    echo "      }"
    echo "    ]"
    echo "  }"
    echo ""
}

# Function to check dependencies
check_dependencies()
{
    local skip_dpc_check="$1"

    # Check for jq (JSON parser)
    if ! command -v jq >/dev/null 2>&1; then
        log_message "err" "jq is not installed. Please install jq to parse JSON files."
        return 1
    fi

    # Check for DPC update script (skip if only validating)
    if [[ "$skip_dpc_check" != "skip" ]]; then
        if [[ ! -x "$DPC_UPDATE_SCRIPT" ]]; then
            log_message "err" "DPC update script not found or not executable: $DPC_UPDATE_SCRIPT"
            return 1
        fi
    fi

    return 0
}

# Function to validate JSON configuration
validate_json_config()
{
    local json_file="$1"
    local validation_errors=0

    echo "Validating JSON configuration: $json_file"
    echo "=========================================="

    if [[ ! -f "$json_file" ]]; then
        echo "[ERROR] JSON configuration file not found: $json_file"
        return 1
    fi

    # Validate JSON syntax
    echo -n "Checking JSON syntax... "
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        echo "FAILED"
        echo "[ERROR] Invalid JSON syntax in file: $json_file"
        jq empty "$json_file" 2>&1
        return 1
    fi
    echo "OK"

    # Check System HID
    echo -n "Checking System HID... "
    local system_hid
    system_hid=$(jq -r '."System HID"' "$json_file" 2>/dev/null)

    if [[ -z "$system_hid" ]] || [[ "$system_hid" == "null" ]]; then
        echo "FAILED"
        echo "[ERROR] Missing 'System HID' field"
        validation_errors=$((validation_errors + 1))
    elif ! echo "$system_hid" | grep -qE '^[Hh][Ii][0-9]{3}$'; then
        echo "FAILED"
        echo "[ERROR] Invalid 'System HID' format. Expected format: HI### or hi### (where ### is 3 digits)"
        validation_errors=$((validation_errors + 1))
    else
        echo "OK (System HID: $system_hid)"
    fi

    # Check Devices array
    echo -n "Checking Devices array... "
    local devices_check
    devices_check=$(jq -e '.Devices | type' "$json_file" 2>/dev/null)

    if [[ "$devices_check" != '"array"' ]]; then
        echo "FAILED"
        echo "[ERROR] 'Devices' field is missing or not an array"
        validation_errors=$((validation_errors + 1))
        return 1
    fi

    local num_devices
    num_devices=$(jq '.Devices | length' "$json_file")

    # Validate num_devices is numeric
    if [[ -z "$num_devices" ]] || ! echo "$num_devices" | grep -qE '^[0-9]+$'; then
        echo "WARNING (Invalid device count, defaulting to 0)"
        num_devices=0
    fi

    if [[ "$num_devices" -eq 0 ]]; then
        echo "WARNING (No devices defined)"
    else
        echo "OK ($num_devices device(s) found)"
    fi

    # Validate each device
    echo ""
    echo "Validating devices:"
    echo "-------------------"

    dev_idx=0
    while [ $dev_idx -lt $num_devices ]; do
        echo "Device $((dev_idx+1)):"

        # Extract device information
        local device_type
        local bus
        local config_file
        local crc_file
        local device_config_file

        device_type=$(jq -r ".Devices[$dev_idx].DeviceType" "$json_file" 2>/dev/null)
        bus=$(jq -r ".Devices[$dev_idx].Bus" "$json_file" 2>/dev/null)
        config_file=$(jq -r ".Devices[$dev_idx].ConfigFile" "$json_file" 2>/dev/null)
        crc_file=$(jq -r ".Devices[$dev_idx].CrcFile" "$json_file" 2>/dev/null)
        device_config_file=$(jq -r ".Devices[$dev_idx].DeviceConfigFile" "$json_file" 2>/dev/null)

        # Validate DeviceType
        if [[ -z "$device_type" ]] || [[ "$device_type" == "null" ]]; then
            echo "  [ERROR] Missing 'DeviceType'"
            validation_errors=$((validation_errors + 1))
        else
            echo "  DeviceType: $device_type"
        fi

        # Validate Bus
        if [[ -z "$bus" ]] || [[ "$bus" == "null" ]]; then
            echo "  [ERROR] Missing 'Bus'"
            validation_errors=$((validation_errors + 1))
        elif ! echo "$bus" | grep -qE '^[0-9]+$'; then
            echo "  [ERROR] Invalid 'Bus' value (must be a number): $bus"
            validation_errors=$((validation_errors + 1))
        else
            echo "  Bus: $bus"
        fi

        # Validate ConfigFile
        if [[ -z "$config_file" ]] || [[ "$config_file" == "null" ]]; then
            echo "  [ERROR] Missing 'ConfigFile'"
            validation_errors=$((validation_errors + 1))
        else
            echo "  ConfigFile: $config_file"
            if [[ ! -f "$config_file" ]]; then
                echo "    [WARNING] File does not exist"
            fi
        fi

        # Validate CrcFile
        if [[ -z "$crc_file" ]] || [[ "$crc_file" == "null" ]]; then
            echo "  [ERROR] Missing 'CrcFile'"
            validation_errors=$((validation_errors + 1))
        else
            echo "  CrcFile: $crc_file"
            if [[ ! -f "$crc_file" ]]; then
                echo "    [WARNING] File does not exist"
            fi
        fi

        # Validate DeviceConfigFile
        if [[ -z "$device_config_file" ]] || [[ "$device_config_file" == "null" ]]; then
            echo "  [ERROR] Missing 'DeviceConfigFile'"
            validation_errors=$((validation_errors + 1))
        else
            echo "  DeviceConfigFile: $device_config_file"
            if [[ ! -f "$device_config_file" ]]; then
                echo "    [WARNING] File does not exist"
            fi
        fi

        echo ""
        dev_idx=$((dev_idx + 1))
    done

    # Summary
    echo "=========================================="
    if [[ $validation_errors -eq 0 ]]; then
        echo "Validation: PASSED"
        echo "JSON configuration is valid and ready to use."
        return 0
    else
        echo "Validation: FAILED"
        echo "Found $validation_errors error(s) in JSON configuration."
        return 1
    fi
}

# Function to process JSON configuration
process_json_config()
{
    local json_file="$1"

    if [[ ! -f "$json_file" ]]; then
        log_message "err" "JSON configuration file not found: $json_file"
        return 1
    fi

    log_message "info" "Processing JSON configuration: $json_file"

    # Validate JSON syntax
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        log_message "err" "Invalid JSON syntax in file: $json_file"
        return 1
    fi

    local total_devices=0
    local successful_updates=0
    local failed_updates=0
    local failed_devices=()

    # Extract system information
    local system_hid
    local num_devices

    system_hid=$(jq -r '."System HID"' "$json_file")

    if [[ -z "$system_hid" ]] || [[ "$system_hid" == "null" ]]; then
        log_message "err" "Missing System HID in configuration"
        return 1
    fi

    num_devices=$(jq '.Devices | length // 0' "$json_file")

    # Validate num_devices is numeric
    if [[ -z "$num_devices" ]] || ! echo "$num_devices" | grep -qE '^[0-9]+$'; then
        log_message "warning" "Invalid device count from JSON, defaulting to 0"
        num_devices=0
    fi

    log_message "info" "Processing System HID: $system_hid with $num_devices device(s)"

    # Iterate through each device
    dev_idx=0
    while [ $dev_idx -lt $num_devices ]; do
        total_devices=$((total_devices + 1))

        # Extract device information
        local device_type
        local bus
        local config_file
        local crc_file
        local device_config_file

        device_type=$(jq -r ".Devices[$dev_idx].DeviceType" "$json_file")
        bus=$(jq -r ".Devices[$dev_idx].Bus" "$json_file")
        config_file=$(jq -r ".Devices[$dev_idx].ConfigFile" "$json_file")
        crc_file=$(jq -r ".Devices[$dev_idx].CrcFile" "$json_file")
        device_config_file=$(jq -r ".Devices[$dev_idx].DeviceConfigFile" "$json_file")

        log_message "info" "Device $total_devices: Type=$device_type, Bus=$bus"

        # Validate extracted fields
        if [[ -z "$device_type" ]] || [[ "$device_type" == "null" ]]; then
            log_message "err" "Missing DeviceType for device $dev_idx"
            failed_updates=$((failed_updates + 1))
            failed_devices+=("unknown $bus unknown")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$bus" ]] || [[ "$bus" == "null" ]]; then
            log_message "err" "Missing Bus for device $dev_idx"
            failed_updates=$((failed_updates + 1))
            failed_devices+=("$device_type unknown unknown")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$config_file" ]] || [[ "$config_file" == "null" ]]; then
            log_message "err" "Missing ConfigFile for device $dev_idx"
            failed_updates=$((failed_updates + 1))
            failed_devices+=("$device_type $bus unknown")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$crc_file" ]] || [[ "$crc_file" == "null" ]]; then
            log_message "err" "Missing CrcFile for device $dev_idx"
            failed_updates=$((failed_updates + 1))
            failed_devices+=("$device_type $bus unknown")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$device_config_file" ]] || [[ "$device_config_file" == "null" ]]; then
            log_message "err" "Missing DeviceConfigFile for device $dev_idx"
            failed_updates=$((failed_updates + 1))
            failed_devices+=("$device_type $bus unknown")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        # Convert system HID to lowercase for command
        local system_hid_lower
        system_hid_lower=$(echo "$system_hid" | tr '[:upper:]' '[:lower:]')

        # Try to get slave address from devtree file
        local slave_addr="unknown"
        if [[ -f "/var/run/hw-management/config/devtree" ]]; then
            # Search for device on the specified bus
            # Format in devtree: device_type slave_addr bus device_name
            slave_addr=$(awk -v dt="$device_type" -v b="$bus" '$1 == dt && $3 == b {print $2; exit}' /var/run/hw-management/config/devtree 2>/dev/null || echo "unknown")
        fi

        # Build command (using array to prevent argument injection)
        local cmd=("$DPC_UPDATE_SCRIPT" "$bus" "$device_type" "$system_hid_lower" "$config_file" "$crc_file" "$device_config_file")

        log_message "info" "Executing: ${cmd[*]}"

        # Execute DPC update script
        if "${cmd[@]}"; then
            log_message "info" "Successfully updated device: $device_type on bus $bus"
            successful_updates=$((successful_updates + 1))
        else
            log_message "err" "Failed to update device: $device_type on bus $bus"
            failed_updates=$((failed_updates + 1))
            failed_devices+=("$device_type $bus $slave_addr")
        fi

        dev_idx=$((dev_idx + 1))
    done

    # Summary
    log_message "info" "======================================"
    log_message "info" "Batch Update Summary:"
    log_message "info" "  System HID:        $system_hid"
    log_message "info" "  Total Devices:     $total_devices"
    log_message "info" "  Successful:        $successful_updates"
    log_message "info" "  Failed:            $failed_updates"

    if [[ $failed_updates -gt 0 ]]; then
        log_message "info" ""
        log_message "info" "Failed Devices:"
        local idx=0
        while [ $idx -lt ${#failed_devices[@]} ]; do
            log_message "info" "  ${failed_devices[$idx]}"
            idx=$((idx + 1))
        done
    fi

    log_message "info" "======================================"

    if [[ $failed_updates -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Main execution
main()
{
    local validate_only=0
    local json_file=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --validate-json)
                validate_only=1
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -n "$json_file" ]]; then
                    echo "Error: Multiple JSON files specified. Only one configuration file allowed."
                    usage
                    exit 1
                fi
                json_file="$1"
                shift
                ;;
        esac
    done

    # Check if JSON file is provided
    if [[ -z "$json_file" ]]; then
        echo "Error: JSON configuration file not specified"
        usage
        exit 1
    fi

    # If validation mode, validate and exit
    if [[ $validate_only -eq 1 ]]; then
        # Check dependencies (skip DPC script check for validation)
        if ! check_dependencies "skip"; then
            echo "Error: Dependency check failed - jq is required"
            exit 1
        fi

        # Validate JSON
        if validate_json_config "$json_file"; then
            exit 0
        else
            exit 1
        fi
    fi

    # Normal operation: batch update
    log_message "info" "Voltage Regulator DPC Batch Update Started"

    # Check dependencies
    if ! check_dependencies; then
        log_message "err" "Dependency check failed - exiting"
        exit 1
    fi

    # Process JSON configuration
    if process_json_config "$json_file"; then
        log_message "info" "Voltage Regulator DPC Batch Update Completed Successfully"
        exit 0
    else
        log_message "err" "Voltage Regulator DPC Batch Update Completed with Errors"
        exit 1
    fi
}

# Execute main function
main "$@"

