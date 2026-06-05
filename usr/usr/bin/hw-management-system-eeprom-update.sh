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
LOG_FILE="/var/log/eeprom_update.log"

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

################################################################################
# Function: log_message
# Description: Write timestamped messages to log file and stderr
################################################################################
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >&2
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
        log_message "ERROR: Cannot extract I2C bus from path: $eeprom_path"
        return 1
    fi
    
    # Extract address from X-00YY pattern (where YY is hex address)
    if [[ $eeprom_path =~ [0-9]+-00([0-9a-fA-F]+)/eeprom ]]; then
        I2C_ADDR="0x${BASH_REMATCH[1]}"
    elif [[ $eeprom_path =~ [0-9]+-([0-9a-fA-F]+)/eeprom ]]; then
        I2C_ADDR="0x${BASH_REMATCH[1]}"
    else
        log_message "ERROR: Cannot extract I2C address from path: $eeprom_path"
        return 1
    fi
    
    log_message "Extracted from EEPROM path: Bus=$I2C_BUS, Address=$I2C_ADDR"
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
    log_message "Parsing TLV EEPROM header..."
    
    # Read first 11 bytes of EEPROM (TLV header)
    local header=$(dd if="$EEPROM_PATH" bs=1 count=11 2>/dev/null | od -An -tx1)
    
    # Check for TlvInfo signature
    local sig=$(echo "$header" | awk '{print $1$2$3$4$5$6$7$8}')
    if [ "$sig" != "546c76496e666f00" ]; then
        log_message "WARNING: TlvInfo signature not found"
        log_message "Expected: 546c76496e666f00"
        log_message "Got:      $sig"
        return 1
    fi
    
    log_message "TlvInfo signature verified"
    
    # Extract version (byte 8)
    local version=$(echo "$header" | awk '{print $9}')
    log_message "TLV Version: 0x$version"
    
    # Extract total length (bytes 9-10, big-endian)
    local len_high=$(echo "$header" | awk '{print $10}')
    local len_low=$(echo "$header" | awk '{print $11}')
    
    # Convert big-endian to decimal
    TLV_TOTAL_LENGTH=$(printf "%d" $((0x$len_high * 256 + 0x$len_low)))
    
    log_message "TLV Total Length: $TLV_TOTAL_LENGTH bytes (0x$(printf '%04x' $TLV_TOTAL_LENGTH))"
    
    # In ONIE TLV format:
    # - CRC TLV is at the end: [0xFE] [0x04] [CRC-byte0] [CRC-byte1] [CRC-byte2] [CRC-byte3]
    # - CRC is calculated from offset 0x000 up to (but NOT including) the CRC TLV type (0xFE)
    # - Total block size = 11 (header) + TLV_TOTAL_LENGTH
    # - CRC TLV starts at: 11 + TLV_TOTAL_LENGTH - 6 (type + length + 4 bytes CRC)
    # - CRC value location: 11 + TLV_TOTAL_LENGTH - 4
    # - Payload end (last byte before CRC TLV): 11 + TLV_TOTAL_LENGTH - 7
    
    PAYLOAD_START=0x000  # CRC starts from beginning of EEPROM
    
    local payload_end_calc=$((11 + TLV_TOTAL_LENGTH - 7))
    PAYLOAD_END=$(printf "0x%03x" $payload_end_calc)
    
    local crc_offset_calc=$((11 + TLV_TOTAL_LENGTH - 4))
    CRC_OFFSET_START=$(printf "0x%03x" $crc_offset_calc)
    
    log_message "Calculated Payload Range for CRC:"
    log_message "  Start: $PAYLOAD_START ($(hex_to_decimal $PAYLOAD_START) decimal)"
    log_message "  End:   $PAYLOAD_END ($payload_end_calc decimal)"
    log_message "  Length: $((payload_end_calc + 1)) bytes"
    log_message "CRC TLV Type+Length at: 0x$(printf '%03x' $((payload_end_calc + 1))) to 0x$(printf '%03x' $((payload_end_calc + 2)))"
    log_message "CRC Location: $CRC_OFFSET_START (bytes $crc_offset_calc to $((crc_offset_calc + 3)))"
    
    return 0
}

################################################################################
# Function: dump_tlv_info
# Description: Display TLV structure information
################################################################################
dump_tlv_info() {
    log_message "=========================================="
    log_message "TLV EEPROM STRUCTURE"
    log_message "=========================================="
    
    # Parse header
    if ! parse_tlv_header; then
        log_message "ERROR: Failed to parse TLV header"
        return 1
    fi
    
    log_message ""
    log_message "Structure breakdown:"
    log_message "  0x000-0x007: TlvInfo signature (8 bytes)"
    log_message "  0x008:       Version (1 byte)"
    log_message "  0x009-0x00a: Total length (2 bytes, big-endian)"
    log_message "  0x00b-$PAYLOAD_END: TLV entries"
    log_message "  $CRC_OFFSET_START-$(printf '0x%03x' $(($(hex_to_decimal $CRC_OFFSET_START) + 3))): CRC32 (4 bytes)"
    
    log_message ""
    log_message "First 32 bytes of EEPROM:"
    dd if="$EEPROM_PATH" bs=1 count=32 2>/dev/null | hexdump -C
    
    log_message ""
    log_message "CRC area (last 4 bytes):"
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
    
    # Create temp file
    local temp_file="/tmp/eeprom_crc_calc_$$.bin"
    
    # Read EEPROM data from start up to (but not including) CRC value
    dd if="$EEPROM_PATH" bs=1 skip=$start count=$bytes_to_read of="$temp_file" 2>/dev/null
    
    # Calculate CRC using Python
    local crc_result=$(python3 -c "
import sys

# CRC32 table initialization
def init_crc_table():
    table = []
    for n in range(256):
        c = n
        for k in range(8):
            c = 0xedb88320 ^ (c >> 1) if c & 1 else c >> 1
        table.append(c)
    return table

CRC_TABLE = init_crc_table()

def calc_crc32(data):
    crc = 0xFFFFFFFF
    for byte in data:
        crc = CRC_TABLE[(crc ^ byte) & 0xFF] ^ (crc >> 8)
    return crc ^ 0xFFFFFFFF

with open('$temp_file', 'rb') as f:
    data = f.read()

crc = calc_crc32(data)

# Output in big-endian format (ONIE standard)
print(f'0x{(crc>>24)&0xFF:02x} 0x{(crc>>16)&0xFF:02x} 0x{(crc>>8)&0xFF:02x} 0x{crc&0xFF:02x}')
")
    
    # Clean up temp file
    rm -f "$temp_file"
    
    echo "$crc_result"
}

################################################################################
# Function: check_config_file
################################################################################
check_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_message "Config file not found: $CONFIG_FILE"
        log_message "No fixup needed. Exiting."
        return 1
    fi
    
    if [ ! -s "$CONFIG_FILE" ]; then
        log_message "Config file is empty: $CONFIG_FILE"
        log_message "No fixup needed. Exiting."
        return 1
    fi
    
    log_message "Config file found: $CONFIG_FILE"
    return 0
}

################################################################################
# Function: parse_config_json
################################################################################
parse_config_json() {
    log_message "Parsing configuration file..."
    
    # Check if jq is available
    if command -v jq &> /dev/null; then
        parse_with_jq
    else
        log_message "WARNING: jq not found, using fallback parser"
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
    log_message "Found $updates_count update(s) in config"
    
    if [ "$updates_count" -eq 0 ]; then
        log_message "No updates defined. Exiting."
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
        log_message "No updates defined. Exiting."
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
    
    # EEPROM write cycle time
    sleep 0.02
    
    return $?
}

################################################################################
# Function: i2c_write_verify
################################################################################
i2c_write_verify() {
    local offset="$1"
    local expected_data="$2"
    local retry=0
    
    log_message "Writing $offset: $expected_data"
    
    while [ $retry -lt $MAX_RETRIES ]; do
        # Write byte
        if i2c_write_byte "$offset" "$expected_data"; then
            # Read back
            local read_value=$(i2c_read_byte "$offset")
            
            # Compare
            local expected_norm=$(printf "0x%02x" $(hex_to_decimal "$expected_data"))
            local read_norm=$(printf "0x%02x" $(hex_to_decimal "$read_value"))
            
            if [ "$expected_norm" = "$read_norm" ]; then
                log_message "  Write verified: $read_value"
                return 0
            else
                log_message "  Verify failed: expected $expected_data, read $read_value (attempt $((retry+1)))"
            fi
        else
            log_message "  Write failed (attempt $((retry+1)))"
        fi
        
        retry=$((retry+1))
    done
    
    log_message "  ERROR: Failed after $MAX_RETRIES attempts"
    return 1
}

################################################################################
# Function: system_eeprom_update_payload_data
################################################################################
system_eeprom_update_payload_data() {
    log_message "Starting EEPROM payload data update..."
    
    local failed=0
    local update_count=0
    
    # Parse updates from JSON using jq
    if command -v jq &> /dev/null; then
        update_count=$(jq '.updates | length' "$CONFIG_FILE")
        
        for i in $(seq 0 $((update_count - 1))); do
            local offset=$(jq -r ".updates[$i].offset" "$CONFIG_FILE")
            local data=$(jq -r ".updates[$i].data" "$CONFIG_FILE")
            local desc=$(jq -r ".updates[$i].description" "$CONFIG_FILE")
            
            log_message "Processing: $desc"
            
            # Read current value
            local current_value=$(i2c_read_byte "$offset")
            log_message "Offset $offset: current=$current_value, target=$data"
            
            # Compare
            local current_norm=$(printf "0x%02x" $(hex_to_decimal "$current_value"))
            local target_norm=$(printf "0x%02x" $(hex_to_decimal "$data"))
            
            if [ "$current_norm" != "$target_norm" ]; then
                log_message "  Updating..."
                if ! i2c_write_verify "$offset" "$data"; then
                    log_message "  ERROR: Failed to update offset $offset"
                    failed=$((failed+1))
                fi
            else
                log_message "  Already correct, skipping"
            fi
        done
    else
        # Fallback: parse manually
        log_message "Using fallback parser for updates"
        
        while IFS= read -r line; do
            if echo "$line" | grep -q '"offset"'; then
                local offset=$(echo "$line" | sed 's/.*: *"\([^"]*\)".*/\1/')
                local next_line
                read -r next_line
                local data=$(echo "$next_line" | sed 's/.*: *"\([^"]*\)".*/\1/')
                
                # Read current value
                local current_value=$(i2c_read_byte "$offset")
                log_message "Offset $offset: current=$current_value, target=$data"
                
                # Compare
                local current_norm=$(printf "0x%02x" $(hex_to_decimal "$current_value"))
                local target_norm=$(printf "0x%02x" $(hex_to_decimal "$data"))
                
                if [ "$current_norm" != "$target_norm" ]; then
                    log_message "  Updating..."
                    if ! i2c_write_verify "$offset" "$data"; then
                        log_message "  ERROR: Failed to update offset $offset"
                        failed=$((failed+1))
                    fi
                else
                    log_message "  Already correct, skipping"
                fi
            fi
        done < "$CONFIG_FILE"
    fi
    
    if [ $failed -gt 0 ]; then
        log_message "ERROR: $failed operations failed"
        return 1
    fi
    
    log_message "Payload data update completed"
    return 0
}

################################################################################
# Function: system_eeprom_update_payload_crc32_checksum
################################################################################
system_eeprom_update_payload_crc32_checksum() {
    log_message "Starting CRC32 update..."
    
    # Calculate CRC32
    local crc_bytes=$(calculate_crc32)
    local byte_array=($crc_bytes)
    
    log_message "CRC32 bytes: ${byte_array[*]}"
    
    # Write CRC32 bytes
    local crc_offset=$CRC_OFFSET_START
    local index=0
    
    for byte in "${byte_array[@]}"; do
        local offset=$(printf "0x%03x" $(($(hex_to_decimal $crc_offset) + index)))
        
        if ! i2c_write_verify "$offset" "$byte"; then
            log_message "ERROR: Failed to write CRC32 byte $index"
            return 1
        fi
        
        index=$((index+1))
    done
    
    log_message "CRC32 written successfully"
    
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
    
    log_message "Validating CRC32..."
    local crc_offset=$CRC_OFFSET_START
    local stored_crc=""
    
    for i in 0 1 2 3; do
        local offset=$(printf "0x%03x" $(($(hex_to_decimal $crc_offset) + i)))
        local byte=$(i2c_read_byte "$offset")
        stored_crc="$stored_crc $byte"
    done
    
    log_message "Stored:   $stored_crc"
    log_message "Expected: ${expected_array[*]}"
    
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
        log_message "CRC32 validation PASSED"
        return 0
    else
        log_message "ERROR: CRC32 validation FAILED"
        return 1
    fi
}

################################################################################
# Function: remove_write_protection
################################################################################
remove_write_protection() {
    log_message "Removing write protection..."
    
    if [ -f "$WP_CONTROL" ]; then
        echo 0 > "$WP_CONTROL"
        log_message "Write protection removed"
        return 0
    else
        log_message "WARNING: WP control not found"
        return 1
    fi
}

################################################################################
# Function: restore_write_protection
################################################################################
restore_write_protection() {
    log_message "Restoring write protection..."
    
    if [ -f "$WP_CONTROL" ]; then
        echo 1 > "$WP_CONTROL"
        log_message "Write protection restored"
        return 0
    else
        log_message "WARNING: WP control not found"
        return 1
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################
main() {
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
                log_message "ERROR: Unknown option: $1"
                usage
                ;;
        esac
    done
    
    log_message "=========================================="
    log_message "System EEPROM Update Started"
    log_message "=========================================="
    log_message "EEPROM Path: $EEPROM_PATH"
    log_message "Mode: $MODE"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR: Must run as root"
        exit 1
    fi

    # Parse TLV header to get correct payload boundaries
    log_message ""
    if ! parse_tlv_header; then
        log_message "WARNING: Could not parse TLV header, using default boundaries"
        log_message "  PAYLOAD_START=$PAYLOAD_START"
        log_message "  PAYLOAD_END=$PAYLOAD_END"
        log_message "  CRC_OFFSET_START=$CRC_OFFSET_START"
    fi
    log_message ""
    
    # Handle dump info mode
    if [ "$MODE" = "info" ]; then
        dump_tlv_info
        exit 0
    fi
    
    # Check if EEPROM exists
    if [ ! -f "$EEPROM_PATH" ]; then
        log_message "ERROR: EEPROM not found at $EEPROM_PATH"
        exit 1
    fi
    
    # Extract I2C bus and address from EEPROM path
    if ! extract_i2c_info_from_path "$EEPROM_PATH"; then
        log_message "ERROR: Failed to extract I2C information from path"
        exit 1
    fi
    
    # If check mode, just calculate and validate CRC
    if [ "$MODE" = "check" ]; then
        log_message "=========================================="
        log_message "CRC CHECK MODE"
        log_message "=========================================="
        
        # Calculate expected CRC
        log_message "Calculating CRC32 from payload data..."
        local expected_crc=$(calculate_crc32)
        local expected_array=($expected_crc)
        
        log_message "Expected CRC32: ${expected_array[*]}"
        
        # Read stored CRC from EEPROM
        log_message "Reading stored CRC32 from EEPROM..."
        local crc_offset=$CRC_OFFSET_START
        local stored_crc=""
        
        for i in 0 1 2 3; do
            local offset=$(printf "0x%03x" $(($(hex_to_decimal $crc_offset) + i)))
            split_offset "$offset"
            local byte=$(i2ctransfer -f -y $I2C_BUS w2@$I2C_ADDR $OFFSET_HIGH $OFFSET_LOW r1)
            stored_crc="$stored_crc $byte"
        done
        
        log_message "Stored CRC32:   $stored_crc"
        
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
            log_message "=========================================="
            log_message "CRC32 VALIDATION: PASSED ✓"
            log_message "=========================================="
            exit 0
        else
            log_message "=========================================="
            log_message "CRC32 VALIDATION: FAILED ✗"
            log_message "=========================================="
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
        log_message "ERROR: Failed to parse config or no updates defined"
        exit 0
    fi
    
    # Remove write protection
    remove_write_protection || log_message "WARNING: WP control failed"
    
    # Update payload data
    if ! system_eeprom_update_payload_data; then
        log_message "ERROR: Payload update failed"
        restore_write_protection
        exit 1
    fi
    
    # Update CRC32
    if ! system_eeprom_update_payload_crc32_checksum; then
        log_message "ERROR: CRC32 update failed"
        restore_write_protection
        exit 1
    fi
    
    # Restore write protection
    restore_write_protection
    
    log_message "=========================================="
    log_message "EEPROM Update Completed Successfully"
    log_message "=========================================="
    
    exit 0
}

# Run main
main "$@"
