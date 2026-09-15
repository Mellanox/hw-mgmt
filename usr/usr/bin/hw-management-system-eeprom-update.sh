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
################################################################################
# System EEPROM Update Script
# Purpose: Update EEPROM payload data and CRC32 checksum
# Usage:
#   ./script.sh [--check-crc|-c] [--eeprom-path /path/to/eeprom]
################################################################################

set -e

# Configuration
CONFIG_FILE="/etc/vpd_data_fixup.json"
EEPROM_PATH="/sys/devices/platform/AMDI0010:01/i2c-1/1-0051/eeprom"
WP_CONTROL="/var/run/hw-management/system/vpd_wp"
SYSLOG_TAG="hw-mgmt-eeprom"
CRC32_CALCULATOR="/usr/bin/hw-management-eeprom-crc32.py"

# Constants
readonly TLV_HEADER_SIZE=11
readonly EEPROM_WRITE_DELAY=0.02  # EEPROM write cycle time in seconds
readonly SUPPORTED_CONFIG_VERSION="1.0"

# Payload boundaries (will be updated by parse_tlv_header if TLV format detected)
PAYLOAD_START=0x000
PAYLOAD_END=0x2b5
CRC_OFFSET_START=0x2b8
TLV_TOTAL_LENGTH=0

# Retry configuration
MAX_RETRIES=3

# Global variables
I2C_BUS=""
I2C_ADDR=""
WP_REMOVED=0  # Track if write protection was removed

################################################################################
# Function: log_info
# Description: Log informational messages to syslog and stderr
################################################################################
log_info() {
    logger -t "$SYSLOG_TAG" -p user.info "$1"
    echo "$1" >&2
}

################################################################################
# Function: log_err
# Description: Log error messages to syslog and stderr
################################################################################
log_err() {
    logger -t "$SYSLOG_TAG" -p user.err "$1"
    echo "ERROR: $1" >&2
}

################################################################################
# Function: check_dependencies
# Description: Verify all required commands are available
################################################################################
check_dependencies() {
    local missing_deps=()

    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi

    if ! command -v i2ctransfer &> /dev/null; then
        missing_deps+=("i2ctransfer")
    fi

    if ! command -v dd &> /dev/null; then
        missing_deps+=("dd")
    fi

    if ! command -v hexdump &> /dev/null; then
        missing_deps+=("hexdump")
    fi

    if ! command -v logger &> /dev/null; then
        missing_deps+=("logger")
    fi

    if [ ! -x "$CRC32_CALCULATOR" ]; then
        echo "ERROR: CRC32 calculator not found or not executable: $CRC32_CALCULATOR" >&2
        return 1
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "ERROR: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install the missing packages and try again" >&2
        return 1
    fi

    log_info "All dependencies verified"
    return 0
}

################################################################################
# Function: extract_i2c_info_from_path
# Description: Extract I2C bus and address from EEPROM sysfs path
# Example: /sys/devices/platform/AMDI0010:01/i2c-1/1-0051/eeprom
#          Bus: 1, Address: 0x51
################################################################################
extract_i2c_info_from_path() {
    local eeprom_path="$1"
    # Extract bus number from i2c-X pattern
    if [[ $eeprom_path =~ i2c-([0-9]+) ]]; then
        I2C_BUS="${BASH_REMATCH[1]}"
    else
        log_err "Cannot extract I2C bus from path: $eeprom_path"
        return 1
    fi
    # Extract address from X-00YY pattern (where YY is hex address)
    if [[ $eeprom_path =~ [0-9]+-00([0-9a-fA-F]+)/eeprom ]]; then
        I2C_ADDR="0x${BASH_REMATCH[1]}"
    elif [[ $eeprom_path =~ [0-9]+-([0-9a-fA-F]+)/eeprom ]]; then
        I2C_ADDR="0x${BASH_REMATCH[1]}"
    else
        log_err "Cannot extract I2C address from path: $eeprom_path"
        return 1
    fi
    log_info "Extracted from EEPROM path: Bus=$I2C_BUS, Address=$I2C_ADDR"
    return 0
}

################################################################################
# Function: usage
################################################################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -c, --check-crc              Check CRC32 without making changes
    -i, --info                   Display TLV EEPROM structure information
    -e, --eeprom-path PATH       Specify EEPROM sysfs path
                                 Default: /sys/devices/platform/AMDI0010:01/i2c-1/1-0051/eeprom
    -h, --help                   Show this help message

Examples:
    $0                           # Normal update mode
    $0 --info                    # Show TLV structure and boundaries
    $0 --check-crc               # Check CRC only
    $0 -e /sys/.../i2c-2/2-0050/eeprom  # Use different EEPROM

EOF
    exit 0
}

################################################################################
# Function: parse_tlv_header
################################################################################
parse_tlv_header() {
    log_info "Parsing TLV EEPROM header..."
    # Read first TLV_HEADER_SIZE bytes of EEPROM (TLV header)
    local header=$(dd if="$EEPROM_PATH" bs=1 count=$TLV_HEADER_SIZE 2>/dev/null | od -An -tx1)
    if [ -z "$header" ]; then
        log_err "Failed to read EEPROM header"
        return 1
    fi
    # Check for TlvInfo signature
    local sig=$(echo "$header" | awk '{print $1$2$3$4$5$6$7$8}')
    if [ "$sig" != "546c76496e666f00" ]; then
        log_info "WARNING: TlvInfo signature not found"
        log_info "Expected: 546c76496e666f00"
        log_info "Got:      $sig"
        return 1
    fi
    log_info "TlvInfo signature verified"
    # Extract version (byte 8)
    local version=$(echo "$header" | awk '{print $9}')
    log_info "TLV Version: 0x$version"
    # Extract total length (bytes 9-10, big-endian)
    local len_high=$(echo "$header" | awk '{print $10}')
    local len_low=$(echo "$header" | awk '{print $11}')
    # Validate hex values
    if [[ ! "$len_high" =~ ^[0-9a-fA-F]{2}$ ]] || [[ ! "$len_low" =~ ^[0-9a-fA-F]{2}$ ]]; then
        log_err "Invalid TLV length bytes: high=$len_high, low=$len_low"
        return 1
    fi
    # Convert big-endian to decimal
    TLV_TOTAL_LENGTH=$(printf "%d" $((0x$len_high * 256 + 0x$len_low)))
    # Sanity check: TLV length should be reasonable (e.g., 10 to 8192 bytes)
    if [ "$TLV_TOTAL_LENGTH" -lt 10 ] || [ "$TLV_TOTAL_LENGTH" -gt 8192 ]; then
        log_err "TLV total length out of reasonable range: $TLV_TOTAL_LENGTH"
        return 1
    fi
    log_info "TLV Total Length: $TLV_TOTAL_LENGTH bytes (0x$(printf '%04x' $TLV_TOTAL_LENGTH))"
    # In ONIE TLV format:
    # - CRC TLV is at the end: [0xFE] [0x04] [CRC-byte0] [CRC-byte1] [CRC-byte2] [CRC-byte3]
    # - CRC is calculated from offset 0x000 up to (but NOT including) the CRC TLV type (0xFE)
    # - Total block size = TLV_HEADER_SIZE + TLV_TOTAL_LENGTH
    # - CRC TLV starts at: TLV_HEADER_SIZE + TLV_TOTAL_LENGTH - 6 (type + length + 4 bytes CRC)
    # - CRC value location: TLV_HEADER_SIZE + TLV_TOTAL_LENGTH - 4
    # - Payload end (last byte before CRC TLV): TLV_HEADER_SIZE + TLV_TOTAL_LENGTH - 7
    PAYLOAD_START=0x000  # CRC starts from beginning of EEPROM
    local payload_end_calc=$((TLV_HEADER_SIZE + TLV_TOTAL_LENGTH - 7))
    PAYLOAD_END=$(printf "0x%03x" $payload_end_calc)
    local crc_offset_calc=$((TLV_HEADER_SIZE + TLV_TOTAL_LENGTH - 4))
    CRC_OFFSET_START=$(printf "0x%03x" $crc_offset_calc)
    log_info "Calculated Payload Range for CRC:"
    log_info "  Start: $PAYLOAD_START ($(hex_to_decimal $PAYLOAD_START) decimal)"
    log_info "  End:   $PAYLOAD_END ($payload_end_calc decimal)"
    log_info "  Length: $((payload_end_calc + 1)) bytes"
    log_info "CRC TLV Type+Length at: 0x$(printf '%03x' $((payload_end_calc + 1))) to 0x$(printf '%03x' $((payload_end_calc + 2)))"
    log_info "CRC Location: $CRC_OFFSET_START (bytes $crc_offset_calc to $((crc_offset_calc + 3)))"
    return 0
}

################################################################################
# Function: dump_tlv_info
# Description: Display TLV structure information
################################################################################
dump_tlv_info() {
    log_info "=========================================="
    log_info "TLV EEPROM STRUCTURE"
    log_info "=========================================="
    # Parse header
    if ! parse_tlv_header; then
        log_err "Failed to parse TLV header"
        return 1
    fi
    log_info ""
    log_info "Structure breakdown:"
    log_info "  0x000-0x007: TlvInfo signature (8 bytes)"
    log_info "  0x008:       Version (1 byte)"
    log_info "  0x009-0x00a: Total length (2 bytes, big-endian)"
    log_info "  0x00b-$PAYLOAD_END: TLV entries"
    log_info "  $CRC_OFFSET_START-$(printf '0x%03x' $(($(hex_to_decimal $CRC_OFFSET_START) + 3))): CRC32 (4 bytes)"
    log_info ""
    log_info "First 32 bytes of EEPROM:"
    dd if="$EEPROM_PATH" bs=1 count=32 2>/dev/null | hexdump -C
    log_info ""
    log_info "CRC area (last 4 bytes):"
    local crc_start=$(hex_to_decimal $CRC_OFFSET_START)
    dd if="$EEPROM_PATH" bs=1 skip=$crc_start count=4 2>/dev/null | hexdump -C
}

################################################################################
# Function: calculate_crc32
# Description: Calculate CRC32 using Python (ONIE TLV standard)
# CRC covers 0x000 to 0x2b7 (everything except the CRC value itself)
################################################################################
calculate_crc32() {
    local start=$(hex_to_decimal $PAYLOAD_START)
    local crc_offset=$(hex_to_decimal $CRC_OFFSET_START)

    # Calculate how many bytes to read (up to but not including CRC value)
    # This includes the CRC TLV header (type and length)
    local bytes_to_read=$((crc_offset - start))

    # Create secure temp file
    local temp_file=$(mktemp) || {
        log_err "Failed to create temporary file"
        return 1
    }
    # Ensure cleanup on function exit
    trap "rm -f '$temp_file'" RETURN
    # Read EEPROM data from start up to (but not including) CRC value
    if ! dd if="$EEPROM_PATH" bs=1 skip=$start count=$bytes_to_read of="$temp_file" 2>/dev/null; then
        log_err "Failed to read EEPROM data for CRC calculation"
        return 1
    fi

    # Calculate CRC using external Python script
    local crc_result=$("$CRC32_CALCULATOR" "$temp_file" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_err "CRC calculation failed: $crc_result"
        return 1
    fi

    if [ -z "$crc_result" ]; then
        log_err "CRC calculation returned empty result"
        return 1
    fi
    echo "$crc_result"
}

################################################################################
# Function: check_config_file
################################################################################
check_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Config file not found: $CONFIG_FILE"
        log_info "No fixup needed. Exiting."
        return 1
    fi

    if [ ! -s "$CONFIG_FILE" ]; then
        log_info "Config file is empty: $CONFIG_FILE"
        log_info "No fixup needed. Exiting."
        return 1
    fi

    log_info "Config file found: $CONFIG_FILE"
    return 0
}

################################################################################
# Function: validate_config_version
################################################################################
validate_config_version() {
    local config_version=""

    if command -v jq &> /dev/null; then
        config_version=$(jq -r '.version // "legacy"' "$CONFIG_FILE" 2>/dev/null)
    else
        # Fallback: try to extract version with grep
        if grep -q '"version"' "$CONFIG_FILE" 2>/dev/null; then
            config_version=$(grep '"version"' "$CONFIG_FILE" | sed 's/.*: *"\([^"]*\)".*/\1/' | head -1)
        else
            config_version="legacy"
        fi
    fi

    if [ "$config_version" = "legacy" ]; then
        log_info "Config version not specified, assuming legacy format (backward compatible)"
        return 0
    fi

    log_info "Config version: $config_version"

    if [ "$config_version" != "$SUPPORTED_CONFIG_VERSION" ]; then
        log_err "Unsupported config version: $config_version (supported: $SUPPORTED_CONFIG_VERSION)"
        return 1
    fi

    return 0
}

################################################################################
# Function: parse_config_json
################################################################################
parse_config_json() {
    log_info "Parsing configuration file..."

    # Validate config version first
    if ! validate_config_version; then
        return 1
    fi

    # Check if jq is available
    if command -v jq &> /dev/null; then
        parse_with_jq
    else
        log_info "WARNING: jq not found, using fallback parser"
        parse_with_grep
    fi

    return $?
}

################################################################################
# Function: parse_with_jq
################################################################################
parse_with_jq() {
    # Extract updates array
    local updates_count=$(jq '.updates | length' "$CONFIG_FILE")
    log_info "Found $updates_count update(s) in config"

    if [ "$updates_count" -eq 0 ]; then
        log_info "No updates defined. Exiting."
        return 1
    fi

    return 0
}

################################################################################
# Function: parse_with_grep
################################################################################
parse_with_grep() {
    # Check if updates exist
    if ! grep -q '"offset"' "$CONFIG_FILE"; then
        log_info "No updates defined. Exiting."
        return 1
    fi

    return 0
}

################################################################################
# Function: hex_to_decimal
################################################################################
hex_to_decimal() {
    printf "%d" "$1"
}

################################################################################
# Function: decimal_to_hex
################################################################################
decimal_to_hex() {
    printf "0x%02x" "$1"
}

################################################################################
# Function: split_offset
################################################################################
split_offset() {
    local offset_dec=$(hex_to_decimal "$1")
    OFFSET_HIGH=$(decimal_to_hex $((offset_dec >> 8)))
    OFFSET_LOW=$(decimal_to_hex $((offset_dec & 0xFF)))
}

################################################################################
# Function: i2c_read_byte
################################################################################
i2c_read_byte() {
    local offset="$1"
    split_offset "$offset"

    local value=$(i2ctransfer -f -y $I2C_BUS w2@$I2C_ADDR $OFFSET_HIGH $OFFSET_LOW r1)
    echo "$value"
}

################################################################################
# Function: i2c_write_byte
################################################################################
i2c_write_byte() {
    local offset="$1"
    local data="$2"
    split_offset "$offset"

    i2ctransfer -f -y $I2C_BUS w3@$I2C_ADDR $OFFSET_HIGH $OFFSET_LOW $data

    # EEPROM write cycle time (delay for write completion)
    sleep $EEPROM_WRITE_DELAY

    return $?
}

################################################################################
# Function: i2c_write_verify
################################################################################
i2c_write_verify() {
    local offset="$1"
    local expected_data="$2"
    local retry=0

    log_info "Writing $offset: $expected_data"

    while [ $retry -lt $MAX_RETRIES ]; do
        # Write byte
        if i2c_write_byte "$offset" "$expected_data"; then
            # Read back
            local read_value=$(i2c_read_byte "$offset")

            # Compare
            local expected_norm=$(printf "0x%02x" $(hex_to_decimal "$expected_data"))
            local read_norm=$(printf "0x%02x" $(hex_to_decimal "$read_value"))

            if [ "$expected_norm" = "$read_norm" ]; then
                log_info "  Write verified: $read_value"
                return 0
            else
                log_info "  Verify failed: expected $expected_data, read $read_value (attempt $((retry+1)))"
            fi
        else
            log_info "  Write failed (attempt $((retry+1)))"
        fi

        retry=$((retry+1))
    done

    log_err "Failed after $MAX_RETRIES attempts"
    return 1
}

################################################################################
# Function: system_eeprom_update_payload_data
################################################################################
system_eeprom_update_payload_data() {
    log_info "Starting EEPROM payload data update..."

    local failed=0
    local update_count=0

    # Parse updates from JSON using jq
    if command -v jq &> /dev/null; then
        update_count=$(jq '.updates | length' "$CONFIG_FILE")

        for i in $(seq 0 $((update_count - 1))); do
            local offset=$(jq -r ".updates[$i].offset" "$CONFIG_FILE")
            local data=$(jq -r ".updates[$i].data" "$CONFIG_FILE")
            local desc=$(jq -r ".updates[$i].description" "$CONFIG_FILE")
            local expected=$(jq -r ".updates[$i].expected_current // \"null\"" "$CONFIG_FILE")

            log_info "Processing: $desc"

            # Read current value
            local current_value=$(i2c_read_byte "$offset")
            local current_norm=$(printf "0x%02x" $(hex_to_decimal "$current_value"))
            local target_norm=$(printf "0x%02x" $(hex_to_decimal "$data"))

            # Display current and target values
            if [ "$expected" != "null" ]; then
                log_info "Offset $offset: current=$current_value, expected=$expected, target=$data"
            else
                log_info "Offset $offset: current=$current_value, target=$data"
            fi

            # Validate expected_current if specified
            if [ "$expected" != "null" ]; then
                local expected_norm=$(printf "0x%02x" $(hex_to_decimal "$expected"))
                if [ "$current_norm" != "$expected_norm" ]; then
                    log_err "Expected value mismatch at $offset: current=$current_value, expected=$expected"
                    log_err "Skipping update for safety. EEPROM may be in unexpected state."
                    failed=$((failed+1))
                    continue
                fi
                log_info "  Expected value verified"
            fi

            # Compare current with target
            if [ "$current_norm" != "$target_norm" ]; then
                log_info "  Updating..."
                if ! i2c_write_verify "$offset" "$data"; then
                    log_err "Failed to update offset $offset"
                    failed=$((failed+1))
                fi
            else
                log_info "  Already correct, skipping"
            fi
        done
    else
        # Fallback: parse manually (less reliable)
        log_info "WARNING: Using fallback parser for updates (jq recommended for reliability)"
        log_info "Fallback parser assumes specific JSON formatting"
        log_info "WARNING: expected_current validation not supported in fallback mode"

        while IFS= read -r line; do
            if echo "$line" | grep -q '"offset"'; then
                local offset=$(echo "$line" | sed 's/.*: *"\([^"]*\)".*/\1/')

                # Validate offset format
                if [[ ! "$offset" =~ ^0x[0-9a-fA-F]+$ ]]; then
                    log_info "WARNING: Skipping invalid offset format: $offset"
                    continue
                fi

                # Validate offset format
                if [[ ! "$offset" =~ ^0x[0-9a-fA-F]+$ ]]; then
                    log_info "WARNING: Skipping invalid offset format: $offset"
                    continue
                fi

                local next_line
                read -r next_line
                local data=$(echo "$next_line" | sed 's/.*: *"\([^"]*\)".*/\1/')

                # Validate data format
                if [[ ! "$data" =~ ^0x[0-9a-fA-F]+$ ]]; then
                    log_info "WARNING: Skipping invalid data format: $data"
                    continue
                fi

                # Read current value
                local current_value=$(i2c_read_byte "$offset")
                local current_norm=$(printf "0x%02x" $(hex_to_decimal "$current_value"))
                local target_norm=$(printf "0x%02x" $(hex_to_decimal "$data"))

                log_info "Offset $offset: current=$current_value, target=$data"

                # Compare current with target
                if [ "$current_norm" != "$target_norm" ]; then
                    log_info "  Updating..."
                    if ! i2c_write_verify "$offset" "$data"; then
                        log_err "Failed to update offset $offset"
                        failed=$((failed+1))
                    fi
                else
                    log_info "  Already correct, skipping"
                fi
            fi
        done < "$CONFIG_FILE"
    fi

    if [ $failed -gt 0 ]; then
        log_err "$failed operations failed"
        return 1
    fi

    log_info "Payload data update completed"
    return 0
}

################################################################################
# Function: system_eeprom_update_payload_crc32_checksum
################################################################################
system_eeprom_update_payload_crc32_checksum() {
    log_info "Starting CRC32 update..."

    # Calculate CRC32
    local crc_bytes=$(calculate_crc32)
    local byte_array=($crc_bytes)

    log_info "CRC32 bytes: ${byte_array[*]}"

    # Write CRC32 bytes
    local crc_offset=$CRC_OFFSET_START
    local index=0

    for byte in "${byte_array[@]}"; do
        local offset=$(printf "0x%03x" $(($(hex_to_decimal $crc_offset) + index)))

        if ! i2c_write_verify "$offset" "$byte"; then
            log_err "Failed to write CRC32 byte $index"
            return 1
        fi

        index=$((index+1))
    done

    log_info "CRC32 written successfully"

    # Validate
    validate_crc32_checksum
    return $?
}

################################################################################
# Function: validate_crc32_checksum
################################################################################
validate_crc32_checksum() {
    local expected_crc=$(calculate_crc32)
    local expected_array=($expected_crc)

    log_info "Validating CRC32..."
    local crc_offset=$CRC_OFFSET_START
    local stored_crc=""

    for i in 0 1 2 3; do
        local offset=$(printf "0x%03x" $(($(hex_to_decimal $crc_offset) + i)))
        local byte=$(i2c_read_byte "$offset")
        stored_crc="$stored_crc $byte"
    done

    log_info "Stored:   $stored_crc"
    log_info "Expected: ${expected_array[*]}"

    local stored_array=($stored_crc)
    local match=1

    for i in 0 1 2 3; do
        local stored_norm=$(printf "0x%02x" $(hex_to_decimal "${stored_array[$i]}"))
        local expected_norm=$(printf "0x%02x" $(hex_to_decimal "${expected_array[$i]}"))

        if [ "$stored_norm" != "$expected_norm" ]; then
            match=0
            break
        fi
    done

    if [ $match -eq 1 ]; then
        log_info "CRC32 validation PASSED"
        return 0
    else
        log_err "CRC32 validation FAILED"
        return 1
    fi
}

################################################################################
# Function: remove_write_protection
################################################################################
remove_write_protection() {
    log_info "Removing write protection..."

    if [ -f "$WP_CONTROL" ]; then
        if echo 0 > "$WP_CONTROL" 2>/dev/null; then
            WP_REMOVED=1
            log_info "Write protection removed"
            return 0
        else
            log_err "Failed to remove write protection"
            return 1
        fi
    else
        log_info "WARNING: WP control not found at $WP_CONTROL"
        return 1
    fi
}

################################################################################
# Function: restore_write_protection
################################################################################
restore_write_protection() {
    # Only restore if we actually removed it
    if [ "$WP_REMOVED" -eq 0 ]; then
        return 0
    fi

    log_info "Restoring write protection..."

    if [ -f "$WP_CONTROL" ]; then
        if echo 1 > "$WP_CONTROL" 2>/dev/null; then
            WP_REMOVED=0
            log_info "Write protection restored"
            return 0
        else
            log_err "Failed to restore write protection"
            return 1
        fi
    else
        log_info "WARNING: WP control not found at $WP_CONTROL"
        return 1
    fi
}

################################################################################
# Function: cleanup_on_exit
# Description: Ensure write protection is restored on exit
################################################################################
cleanup_on_exit() {
    local exit_code=$?
    if [ "$WP_REMOVED" -eq 1 ]; then
        log_info "Cleanup: Ensuring write protection is restored..."
        restore_write_protection
    fi
    exit $exit_code
}

################################################################################
# MAIN EXECUTION
################################################################################
main() {
    # Set up cleanup trap to ensure write protection is restored
    trap cleanup_on_exit EXIT INT TERM

    # Parse command line arguments
    MODE="update"

    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--check-crc)
                MODE="check"
                shift
                ;;
            -i|--info)
                MODE="info"
                shift
                ;;
            -e|--eeprom-path)
                EEPROM_PATH="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_err "Unknown option: $1"
                usage
                ;;
        esac
    done

    log_info "=========================================="
    log_info "System EEPROM Update Started"
    log_info "=========================================="
    log_info "EEPROM Path: $EEPROM_PATH"
    log_info "Mode: $MODE"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_err "Must run as root"
        exit 1
    fi

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Parse TLV header to get correct payload boundaries
    log_info ""
    if ! parse_tlv_header; then
        log_info "WARNING: Could not parse TLV header, using default boundaries"
        log_info "  PAYLOAD_START=$PAYLOAD_START"
        log_info "  PAYLOAD_END=$PAYLOAD_END"
        log_info "  CRC_OFFSET_START=$CRC_OFFSET_START"
    fi
    log_info ""

    # Handle dump info mode
    if [ "$MODE" = "info" ]; then
        dump_tlv_info
        exit 0
    fi

    # Check if EEPROM exists
    if [ ! -f "$EEPROM_PATH" ]; then
        log_err "EEPROM not found at $EEPROM_PATH"
        exit 1
    fi

    # Extract I2C bus and address from EEPROM path
    if ! extract_i2c_info_from_path "$EEPROM_PATH"; then
        log_err "Failed to extract I2C information from path"
        exit 1
    fi

    # If check mode, just calculate and validate CRC
    if [ "$MODE" = "check" ]; then
        log_info "=========================================="
        log_info "CRC CHECK MODE"
        log_info "=========================================="

        # Calculate expected CRC
        log_info "Calculating CRC32 from payload data..."
        local expected_crc=$(calculate_crc32)
        local expected_array=($expected_crc)

        log_info "Expected CRC32: ${expected_array[*]}"

        # Read stored CRC from EEPROM
        log_info "Reading stored CRC32 from EEPROM..."
        local crc_offset=$CRC_OFFSET_START
        local stored_crc=""

        for i in 0 1 2 3; do
            local offset=$(printf "0x%03x" $(($(hex_to_decimal $crc_offset) + i)))
            split_offset "$offset"
            local byte=$(i2ctransfer -f -y $I2C_BUS w2@$I2C_ADDR $OFFSET_HIGH $OFFSET_LOW r1)
            stored_crc="$stored_crc $byte"
        done

        log_info "Stored CRC32:   $stored_crc"

        # Compare
        local stored_array=($stored_crc)
        local match=1

        for i in 0 1 2 3; do
            local stored_norm=$(printf "0x%02x" $(hex_to_decimal "${stored_array[$i]}"))
            local expected_norm=$(printf "0x%02x" $(hex_to_decimal "${expected_array[$i]}"))

            if [ "$stored_norm" != "$expected_norm" ]; then
                match=0
                break
            fi
        done

        if [ $match -eq 1 ]; then
            log_info "=========================================="
            log_info "CRC32 VALIDATION: PASSED [OK]"
            log_info "=========================================="
            exit 0
        else
            log_info "=========================================="
            log_info "CRC32 VALIDATION: FAILED [ERROR]"
            log_info "=========================================="
            exit 1
        fi
    fi

    # Normal update mode continues below...

    # Check if config file exists and has content
    if ! check_config_file; then
        exit 0
    fi

    # Parse configuration
    if ! parse_config_json; then
        log_err "Failed to parse config or no updates defined"
        exit 0
    fi

    # Remove write protection
    if ! remove_write_protection; then
        log_err "Failed to remove write protection - cannot proceed with updates"
        exit 1
    fi

    # Update payload data
    if ! system_eeprom_update_payload_data; then
        log_err "Payload update failed"
        exit 1
    fi

    # Update CRC32
    if ! system_eeprom_update_payload_crc32_checksum; then
        log_err "CRC32 update failed"
        exit 1
    fi

    # Restore write protection (trap will also ensure this happens)
    restore_write_protection

    log_info "=========================================="
    log_info "EEPROM Update Completed Successfully"
    log_info "=========================================="

    exit 0
}

# Run main
main "$@"
