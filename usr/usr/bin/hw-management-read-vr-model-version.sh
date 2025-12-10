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
# Voltage Regulator Model and Version Reader
################################################################################

DEVTREE_FILE="/var/run/hw-management/config/devtree"
FIRMWARE_BASE="/var/run/hw-management/firmware"
LOG_TAG="vr_model_version"

# Register addresses for reading model and revision (defaults)
PAGE_REG=0x00

# Function to get device-specific register configuration
get_device_registers()
{
    local device_type="$1"

    case "$device_type" in
        mp29816|mp2891)
            echo "0x9e 0x9f 1 0"  # model_reg rev_reg model_page rev_page
            ;;
        mp2855|mp2888|mp2854)
            echo "0x55 0x43 1 1"
            ;;
        mp2975|mp2974)
            echo "0xba 0xbb 0 0"
            ;;
        tps53679|xdpe12284)
            echo "unsupported"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to log messages
log_message()
{
    local level="$1"
    local message="$2"
    logger -t "$LOG_TAG" -p "daemon.$level" "$message"
    echo "[$level] $message"
}

# Safe i2c command execution with error checking
i2c_cmd()
{
    local cmd="$1"
    local expected_exit="$2"

    if [[ -z "$expected_exit" ]]; then
        expected_exit=0
    fi

    eval "$cmd" >/dev/null 2>&1
    local exit_code=$?

    if [[ $exit_code -ne $expected_exit ]]; then
        return $exit_code
    fi

    return 0
}

# Function to read model ID from device
get_model()
{
    local bus="$1"
    local dev_addr="$2"
    local model_reg="$3"
    local model_page="$4"

    # Set page to model ID page
    if ! i2c_cmd "i2cset -y -f '$bus' '$dev_addr' '$PAGE_REG' '$model_page'"; then
        return 1
    fi

    # Read model ID (word)
    local model_id
    model_id=$(i2cget -y -f "$bus" "$dev_addr" "$model_reg" w 2>/dev/null)

    if [[ -z "$model_id" ]]; then
        return 1
    fi

    echo "$model_id"
    return 0
}

# Function to read revision ID from device
get_revision()
{
    local bus="$1"
    local dev_addr="$2"
    local rev_reg="$3"
    local rev_page="$4"

    # Set page to revision ID page
    if ! i2c_cmd "i2cset -y -f '$bus' '$dev_addr' '$PAGE_REG' '$rev_page'"; then
        return 1
    fi

    # Read revision ID (word)
    local rev_id
    rev_id=$(i2cget -y -f "$bus" "$dev_addr" "$rev_reg" w 2>/dev/null)

    if [[ -z "$rev_id" ]]; then
        return 1
    fi

    echo "$rev_id"
    return 0
}

# Function to get model and version for supported device types
get_model_version()
{
    local voltmon_type="$1"
    local bus="$2"
    local dev_addr="$3"
    local device_name="$4"

    # Get device-specific register configuration
    local reg_config
    reg_config=$(get_device_registers "$voltmon_type")

    # Check if device type supports model/revision reading
    if [[ "$reg_config" == "unsupported" ]]; then
        log_message "debug" "Device type $voltmon_type does not support model/version reading"
        return 0
    elif [[ "$reg_config" == "unknown" ]]; then
        log_message "debug" "Device type $voltmon_type is unknown - skipping model/version reading"
        return 0
    fi

    # Parse register configuration: model_reg rev_reg model_page rev_page
    local reg_array=($reg_config)
    local model_reg="${reg_array[0]}"
    local rev_reg="${reg_array[1]}"
    local model_page="${reg_array[2]}"
    local rev_page="${reg_array[3]}"

    log_message "info" "Reading model/version for $voltmon_type device: $device_name (bus $bus, addr $dev_addr, regs: model=$model_reg/$model_page, rev=$rev_reg/$rev_page)"

    # Read model ID
    local model_id
    model_id=$(get_model "$bus" "$dev_addr" "$model_reg" "$model_page")
    local model_status=$?

    # Read revision ID
    local rev_id
    rev_id=$(get_revision "$bus" "$dev_addr" "$rev_reg" "$rev_page")
    local rev_status=$?

    # Create device firmware directory if it doesn't exist
    local firmware_dir="$FIRMWARE_BASE/$device_name"
    if [[ ! -d "$firmware_dir" ]]; then
        mkdir -p "$firmware_dir"
        log_message "info" "Created firmware directory: $firmware_dir"
    fi

    # Write device type (driver name) for visibility
    echo "$voltmon_type" > "$firmware_dir/device_name"

    # Write model ID if successfully read
    if [[ $model_status -eq 0 ]] && [[ -n "$model_id" ]]; then
        echo "$model_id" > "$firmware_dir/model_id"
        log_message "info" "Stored model ID for $device_name: $model_id"
    else
        log_message "warning" "Failed to read model ID for $device_name"
    fi

    # Write revision ID if successfully read
    if [[ $rev_status -eq 0 ]] && [[ -n "$rev_id" ]]; then
        echo "$rev_id" > "$firmware_dir/rev_id"
        log_message "info" "Stored revision ID for $device_name: $rev_id"
    else
        log_message "warning" "Failed to read revision ID for $device_name"
    fi

    # Copy to UI firmware folder if it exists
    copy_to_ui_firmware "$device_name" "$voltmon_type" "$firmware_dir"

    # Return success if at least one was read
    if [[ $model_status -eq 0 ]] || [[ $rev_status -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Function to copy model/revision to UI firmware folder
copy_to_ui_firmware()
{
    local device_name="$1"
    local device_type="$2"
    local firmware_dir="$3"
    local ui_voltage_base="/var/run/hw-management/ui/voltage"

    # Check if UI folder exists
    if [[ ! -d "$ui_voltage_base" ]]; then
        log_message "debug" "UI voltage folder does not exist - skipping UI firmware copy"
        return 0
    fi

    # Check if device folder exists in UI
    local ui_device_dir="$ui_voltage_base/$device_name"
    if [[ ! -d "$ui_device_dir" ]]; then
        log_message "debug" "UI device folder not found: $ui_device_dir - skipping"
        return 0
    fi

    # Find PMIC prefix from any file in the device directory
    local pmic_prefix=""
    for file in "$ui_device_dir"/*; do
        if [[ -e "$file" ]]; then
            local filename=$(basename "$file")
            # Extract PMIC prefix (everything before first '+')
            pmic_prefix=$(echo "$filename" | cut -d'+' -f1)
            if [[ -n "$pmic_prefix" ]] && [[ "$pmic_prefix" == PMIC-* ]]; then
                break
            fi
        fi
    done

    if [[ -z "$pmic_prefix" ]]; then
        log_message "debug" "No PMIC prefix found in $ui_device_dir - skipping"
        return 0
    fi

    log_message "info" "Found PMIC prefix for $device_name: $pmic_prefix"

    # Create UI firmware directory structure
    local ui_firmware_dir="$ui_voltage_base/firmware/$pmic_prefix"
    if [[ ! -d "$ui_firmware_dir" ]]; then
        mkdir -p "$ui_firmware_dir"
        log_message "info" "Created UI firmware directory: $ui_firmware_dir"
    fi

    # Write device type (driver name) for visibility
    echo "$device_type" > "$ui_firmware_dir/device_name"

    # Copy model_id if it exists
    if [[ -f "$firmware_dir/model_id" ]]; then
        cp "$firmware_dir/model_id" "$ui_firmware_dir/model_id"
        log_message "info" "Copied model_id to $ui_firmware_dir/model_id"
    fi

    # Copy rev_id if it exists
    if [[ -f "$firmware_dir/rev_id" ]]; then
        cp "$firmware_dir/rev_id" "$ui_firmware_dir/rev_id"
        log_message "info" "Copied rev_id to $ui_firmware_dir/rev_id"
    fi

    return 0
}

# Function to parse devtree file and process voltage monitors
parse_devtree()
{
    if [[ ! -f "$DEVTREE_FILE" ]]; then
        log_message "err" "Devtree file not found: $DEVTREE_FILE"
        return 1
    fi

    log_message "info" "Parsing devtree file: $DEVTREE_FILE"

    # Read devtree into array (space-separated fields)
    local devtree_content
    devtree_content=$(cat "$DEVTREE_FILE")

    # Convert to array
    local fields=($devtree_content)
    local num_fields=${#fields[@]}

    log_message "info" "Found $num_fields fields in devtree"

    local devices_processed=0
    local devices_skipped=0

    # Parse in groups of 4: driver_name address bus internal_name
    for ((i=0; i<num_fields; i+=4)); do
        # Check if we have all 4 fields
        if [[ $((i+3)) -ge $num_fields ]]; then
            break
        fi

        local driver_name="${fields[$i]}"
        local address="${fields[$((i+1))]}"
        local bus="${fields[$((i+2))]}"
        local internal_name="${fields[$((i+3))]}"

        # Check if internal name matches "voltmon" pattern
        if [[ "$internal_name" == *voltmon* ]]; then
            log_message "info" "Found voltmon device: $internal_name (driver: $driver_name, bus: $bus, addr: $address)"

            if get_model_version "$driver_name" "$bus" "$address" "$internal_name"; then
                ((devices_processed++))
            else
                ((devices_skipped++))
            fi
        fi
    done

    log_message "info" "Processing complete: $devices_processed devices processed, $devices_skipped skipped"

    return 0
}

# Function to get PMIC prefix for a device
get_pmic_prefix()
{
    local device_name="$1"
    local ui_voltage_base="/var/run/hw-management/ui/voltage"
    
    # Check if UI folder exists
    if [[ ! -d "$ui_voltage_base" ]]; then
        echo ""
        return 0
    fi
    
    # Check if device folder exists in UI
    local ui_device_dir="$ui_voltage_base/$device_name"
    if [[ ! -d "$ui_device_dir" ]]; then
        echo ""
        return 0
    fi
    
    # Find PMIC prefix from any file in the device directory
    local pmic_prefix=""
    for file in "$ui_device_dir"/*; do
        if [[ -e "$file" ]]; then
            local filename=$(basename "$file")
            # Extract PMIC prefix (everything before first '+')
            pmic_prefix=$(echo "$filename" | cut -d'+' -f1)
            if [[ -n "$pmic_prefix" ]] && [[ "$pmic_prefix" == PMIC-* ]]; then
                echo "$pmic_prefix"
                return 0
            fi
        fi
    done
    
    echo ""
    return 0
}

# Function to display voltmon information
show_voltmon_info()
{
    if [[ ! -f "$DEVTREE_FILE" ]]; then
        echo "Error: Devtree file not found: $DEVTREE_FILE"
        return 1
    fi

    # Check dependencies
    if ! check_dependencies; then
        echo "Error: Required I2C tools not available"
        return 1
    fi

    # Read devtree into array (space-separated fields)
    local devtree_content
    devtree_content=$(cat "$DEVTREE_FILE")

    # Convert to array
    local fields=($devtree_content)
    local num_fields=${#fields[@]}

    # Print header
    printf "%-25s %-15s %-15s %-15s %-15s\n" "Voltmon Name" "PMIC Index" "Device Name" "Model" "Revision Id"
    printf "%-25s %-15s %-15s %-15s %-15s\n" "==========================" "===============" "===============" "===============" "==============="

    # Parse in groups of 4: driver_name address bus internal_name
    for ((i=0; i<num_fields; i+=4)); do
        # Check if we have all 4 fields
        if [[ $((i+3)) -ge $num_fields ]]; then
            break
        fi

        local driver_name="${fields[$i]}"
        local address="${fields[$((i+1))]}"
        local bus="${fields[$((i+2))]}"
        local internal_name="${fields[$((i+3))]}"

        # Check if internal name matches "voltmon" pattern
        if [[ "$internal_name" == *voltmon* ]]; then
            local pmic_prefix=$(get_pmic_prefix "$internal_name")
            local device_type="$driver_name"
            local model_id="N/A"
            local rev_id="N/A"

            # Get device-specific register configuration
            local reg_config
            reg_config=$(get_device_registers "$driver_name")

            # Check if device type supports model/revision reading
            if [[ "$reg_config" == "unsupported" ]]; then
                model_id="Not supported"
                rev_id="Not supported"
            elif [[ "$reg_config" == "unknown" ]]; then
                model_id="Unknown device"
                rev_id="Unknown device"
            else
                # Parse register configuration: model_reg rev_reg model_page rev_page
                local reg_array=($reg_config)
                local model_reg="${reg_array[0]}"
                local rev_reg="${reg_array[1]}"
                local model_page="${reg_array[2]}"
                local rev_page="${reg_array[3]}"

                # Read model ID directly from device
                local model_result
                model_result=$(get_model "$bus" "$address" "$model_reg" "$model_page" 2>/dev/null)
                if [[ $? -eq 0 ]] && [[ -n "$model_result" ]]; then
                    model_id="$model_result"
                fi

                # Read revision ID directly from device
                local rev_result
                rev_result=$(get_revision "$bus" "$address" "$rev_reg" "$rev_page" 2>/dev/null)
                if [[ $? -eq 0 ]] && [[ -n "$rev_result" ]]; then
                    rev_id="$rev_result"
                fi
            fi

            # Display information in one line
            printf "%-25s %-15s %-15s %-15s %-15s\n" "$internal_name" "${pmic_prefix:-}" "$device_type" "$model_id" "$rev_id"
        fi
    done

    echo ""
    return 0
}

# Function to check dependencies
check_dependencies()
{
    if ! command -v i2cget >/dev/null 2>&1; then
        log_message "err" "i2cget is not installed. Cannot read I2C devices."
        return 1
    fi

    if ! command -v i2cset >/dev/null 2>&1; then
        log_message "err" "i2cset is not installed. Cannot configure I2C devices."
        return 1
    fi

    return 0
}

# Function to display usage information
usage()
{
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Voltage Regulator Model/Version Reader"
    echo ""
    echo "OPTIONS:"
    echo "  --show    Display information for all voltage monitors"
    echo "  --help    Display this help message"
    echo ""
}

# Main execution
main()
{
    local show_mode=0

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --show)
                show_mode=1
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # If --show mode, display information and exit
    if [[ $show_mode -eq 1 ]]; then
        show_voltmon_info
        exit $?
    fi

    # Normal operation: read and store model/version information
    log_message "info" "Voltage Regulator Model/Version Reader"

    # Check dependencies
    if ! check_dependencies; then
        log_message "err" "Dependency check failed - exiting"
        exit 1
    fi

    # Create firmware base directory if it doesn't exist
    if [[ ! -d "$FIRMWARE_BASE" ]]; then
        mkdir -p "$FIRMWARE_BASE"
        log_message "info" "Created firmware base directory: $FIRMWARE_BASE"
    fi

    # Parse devtree and process devices
    parse_devtree

    log_message "info" "Voltage Regulator Model/Version Reader Completed"
    exit 0
}

# Execute main function
main "$@"

