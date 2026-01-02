#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# Cartridge EEPROM Flashing Tool
################################################################################

LOG_TAG="cartridge_flash"

# Global flag for dry-run mode
DRY_RUN=0

# Use mktemp for secure temporary directory creation
# Falls back to /tmp if mktemp unavailable or fails (unlikely on modern systems)
if command -v mktemp >/dev/null 2>&1; then
    TEMP_DIR=$(mktemp -d -t hw-mgmt-cartridge-flash.XXXXXXXXXX 2>/dev/null)
    # Verify mktemp succeeded (check for non-empty path and directory existence)
    if [[ -z "$TEMP_DIR" ]] || [[ ! -d "$TEMP_DIR" ]]; then
        # mktemp failed, fall through to manual creation
        TEMP_DIR=""
    else
        TEMP_DIR_CREATED=1
    fi
fi

# Fallback to manual creation if mktemp unavailable or failed
if [[ -z "$TEMP_DIR" ]]; then
    # Fallback: use PID + random suffix to avoid race condition
    TEMP_DIR="/tmp/hw-mgmt-cartridge-flash-$$-${RANDOM}"
    # Use mkdir with -p to handle race, but check if directory already exists
    if ! mkdir -p "$TEMP_DIR" 2>/dev/null || ! chmod 700 "$TEMP_DIR" 2>/dev/null; then
        # If directory creation/chmod fails, try with additional random suffix
        TEMP_DIR="/tmp/hw-mgmt-cartridge-flash-$$-${RANDOM}-${RANDOM}"
        if ! mkdir -p "$TEMP_DIR" 2>/dev/null || ! chmod 700 "$TEMP_DIR" 2>/dev/null; then
            echo "FATAL: Failed to create temporary directory" >&2
            exit 1
        fi
    fi
    TEMP_DIR_CREATED=1
fi

# Cleanup function
cleanup_temp_dir()
{
    if [[ -n "$TEMP_DIR_CREATED" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Register cleanup on exit
trap cleanup_temp_dir EXIT INT TERM

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
    echo "   or: $0 --modify-bin <bin_file> <offset> <hex_data>"
    echo ""
    echo "Cartridge EEPROM Flashing Tool"
    echo ""
    echo "OPTIONS:"
    echo "  --dry-run              Compare binary files with EEPROM content and report"
    echo "                         mismatches without flashing (read-only mode)"
    echo "  --validate-json        Validate JSON configuration file and exit"
    echo "  --dump-current-content Dump current EEPROM content to /tmp/cartridge{n}_readback.bin"
    echo "                         for all devices in JSON config (read-only mode)"
    echo "  --modify-bin <file> <offset> <data>"
    echo "                         Modify a single byte in binary file at specified offset"
    echo "                         offset: decimal byte position (0-based)"
    echo "                         data: hex value (e.g., 0x32 or 32)"
    echo "  --help                 Display this help message"
    echo ""
    echo "Arguments:"
    echo "  json_config_file       Path to JSON configuration file"
    echo ""
    echo "Examples:"
    echo "  $0 config.json"
    echo "  $0 --dry-run config.json"
    echo "  $0 --dump-current-content config.json"
    echo "  $0 --modify-bin cartridge.bin 29 0x32"
    echo ""
    echo "JSON Format:"
    echo "  {"
    echo "    \"Devices\": ["
    echo "      {"
    echo "        \"Index\": 1,"
    echo "        \"DeviceType\": \"24c02\","
    echo "        \"Bus\": 64,"
    echo "        \"SlaveAddr\": \"0x50\","
    echo "        \"CartridgeBinFile\": \"path/to/cartridge.bin\""
    echo "      }"
    echo "    ]"
    echo "  }"
    echo ""
}

# Function to check dependencies
check_dependencies()
{
    local skip_dd_check="$1"

    # Check for jq (JSON parser)
    if ! command -v jq >/dev/null 2>&1; then
        log_message "err" "jq is not installed. Please install jq to parse JSON files."
        return 1
    fi

    # Check for dd (skip if only validating)
    if [[ "$skip_dd_check" != "skip" ]]; then
        if ! command -v dd >/dev/null 2>&1; then
            log_message "err" "dd command not found"
            return 1
        fi
    fi

    return 0
}

# Function to convert hex address to 4-digit format
# Input: 0x50 or 50
# Output: 0050
format_slave_addr()
{
    local addr="$1"
    # Remove 0x prefix if present and explicitly interpret as base 16
    # This avoids "invalid octal number" errors for addresses like 0x50
    # Handle invalid hex gracefully
    local hex_addr="${addr#0x}"

    # Validate hex characters only (0-9, a-f, A-F)
    if ! echo "$hex_addr" | grep -qE '^[0-9a-fA-F]+$'; then
        log_message "err" "Invalid hex address: $addr (contains non-hex characters)"
        echo "0000"
        return 1
    fi

    # Safely convert with error handling
    local result
    if result=$(printf "%04x" "$((16#$hex_addr))" 2>/dev/null); then
        echo "$result"
        return 0
    else
        log_message "err" "Failed to parse hex address: $addr"
        echo "0000"
        return 1
    fi
}

# Function to get EEPROM size in bytes based on device type
get_eeprom_size()
{
    local device_type="$1"

    case "$device_type" in
        24c01|24c1)
            echo "128"
            ;;
        24c02|24c2)
            echo "256"
            ;;
        24c04|24c4)
            echo "512"
            ;;
        24c08|24c8)
            echo "1024"
            ;;
        24c16)
            echo "2048"
            ;;
        24c32)
            echo "4096"
            ;;
        24c64)
            echo "8192"
            ;;
        24c128)
            echo "16384"
            ;;
        24c256)
            echo "32768"
            ;;
        24c512)
            echo "65536"
            ;;
        *)
            log_message "warning" "Unknown device type: $device_type, defaulting to 256 bytes"
            echo "256"
            ;;
    esac
}

# Function to ensure EEPROM device exists in sysfs
ensure_device_exists()
{
    local device_type="$1"
    local bus="$2"
    local slave_addr="$3"
    local slave_addr_formatted="$4"

    local eeprom_path="/sys/class/i2c-dev/i2c-${bus}/device/${bus}-${slave_addr_formatted}/eeprom"

    if [[ -f "$eeprom_path" ]]; then
        log_message "info" "EEPROM device already exists: $eeprom_path"
        return 0
    fi

    log_message "info" "Creating EEPROM device: $device_type at bus $bus address $slave_addr"

    # Create new device
    local new_device_path="/sys/bus/i2c/devices/i2c-${bus}/new_device"
    if [[ ! -f "$new_device_path" ]]; then
        log_message "err" "Cannot create device - sysfs path not found: $new_device_path"
        return 1
    fi

    # Try to create device, handle "already exists" case gracefully
    # Validate inputs before using in sysfs write operation
    # device_type should be alphanumeric (e.g., 24c02, 24c512)
    if ! echo "$device_type" | grep -qE '^[a-zA-Z0-9]+$'; then
        log_message "err" "Invalid device_type format: $device_type (must be alphanumeric)"
        return 1
    fi

    # Use printf instead of echo to prevent command injection
    # Capture stderr from the sysfs write operation using a temp file
    # (stderr from redirection operations cannot be captured via command substitution)
    local create_err_file="${TEMP_DIR}/device_create_err_$$"
    local create_status
    printf "%s %s" "$device_type" "$slave_addr" >"$new_device_path" 2>"$create_err_file"
    create_status=$?
    local create_err
    create_err=$(cat "$create_err_file" 2>/dev/null)
    rm -f "$create_err_file"

    if [[ $create_status -ne 0 ]]; then
        # Check if failure is due to device already existing (race condition)
        # Different kernel versions may report different error messages
        if echo "$create_err" | grep -qiE "file exists|device or resource busy|address already in use|in use"; then
            log_message "info" "Device already exists (created by another process or previous run)"
        else
            log_message "err" "Failed to create device: $device_type $slave_addr on bus $bus: $create_err"
            return 1
        fi
    fi

    # Wait for device to appear (max 2 seconds)
    local wait_count=0
    while [[ ! -f "$eeprom_path" ]] && [[ $wait_count -lt 20 ]]; do
        sleep 0.1
        wait_count=$((wait_count + 1))
    done

    if [[ ! -f "$eeprom_path" ]]; then
        log_message "err" "Device created but EEPROM not accessible: $eeprom_path"
        return 1
    fi

    log_message "info" "EEPROM device created successfully: $eeprom_path"
    return 0
}

# Function to dump EEPROM content
dump_eeprom()
{
    local bus="$1"
    local slave_addr_formatted="$2"
    local output_file="$3"
    local eeprom_size="$4"

    local eeprom_path="/sys/class/i2c-dev/i2c-${bus}/device/${bus}-${slave_addr_formatted}/eeprom"

    if [[ ! -f "$eeprom_path" ]]; then
        log_message "err" "EEPROM not accessible: $eeprom_path"
        return 1
    fi

    log_message "info" "Dumping EEPROM from $eeprom_path to $output_file (${eeprom_size} bytes)"

    # Read EEPROM content based on device size
    # Use 256-byte blocks for better performance (avoid 65536 separate syscalls for large EEPROMs)
    local block_size=256
    local block_count=$(( (eeprom_size + block_size - 1) / block_size ))

    # Capture dd stderr to detect I2C errors
    local dd_err
    dd_err=$(dd if="$eeprom_path" of="$output_file" bs="$block_size" count="$block_count" iflag=fullblock 2>&1 >/dev/null)
    local dd_status=$?

    if [[ $dd_status -ne 0 ]]; then
        log_message "err" "Failed to dump EEPROM from $eeprom_path: $dd_err"
        return 1
    fi

    # Truncate to exact size (dd may read slightly more due to block alignment)
    # Using truncate command is much faster than bs=1 approach
    # Fallback to dd if truncate is not available
    if command -v truncate >/dev/null 2>&1; then
        if ! truncate -s "$eeprom_size" "$output_file" 2>/dev/null; then
            log_message "err" "Failed to truncate dump to exact size"
            return 1
        fi
    else
        # Fallback: use dd with bs=1 if truncate not available
        log_message "warning" "truncate command not available, using dd fallback"
        local temp_file="${output_file}.tmp"
        if ! dd if="$output_file" of="$temp_file" bs=1 count="$eeprom_size" 2>/dev/null; then
            log_message "err" "Failed to truncate dump to exact size (dd fallback)"
            rm -f "$temp_file"
            return 1
        fi
        mv "$temp_file" "$output_file"
    fi

    # Verify actual bytes read to detect partial I2C operations
    local read_bytes
    read_bytes=$(stat -c%s "$output_file" 2>/dev/null || echo 0)
    if [[ $read_bytes -ne $eeprom_size ]]; then
        log_message "err" "Partial EEPROM read detected: got $read_bytes bytes, expected $eeprom_size bytes"
        log_message "err" "This may indicate I2C bus errors or EEPROM access issues"
        rm -f "$output_file"
        return 1
    fi

    log_message "info" "EEPROM dumped successfully (${read_bytes} bytes verified)"

    return 0
}

# Function to compare two binary files
compare_files()
{
    local file1="$1"
    local file2="$2"

    if [[ ! -f "$file1" ]]; then
        log_message "err" "File not found: $file1"
        return 2
    fi

    if [[ ! -f "$file2" ]]; then
        log_message "err" "File not found: $file2"
        return 2
    fi

    if cmp -s "$file1" "$file2"; then
        return 0  # Files are identical
    else
        # Log byte offset where files differ for debugging
        local cmp_output
        cmp_output=$(cmp "$file1" "$file2" 2>&1)
        if [[ -n "$cmp_output" ]]; then
            log_message "info" "Files differ: $cmp_output"
        fi
        return 1  # Files are different
    fi
}

# Function to flash EEPROM
flash_eeprom()
{
    local bin_file="$1"
    local bus="$2"
    local slave_addr_formatted="$3"
    local eeprom_size="$4"

    local eeprom_path="/sys/class/i2c-dev/i2c-${bus}/device/${bus}-${slave_addr_formatted}/eeprom"
    local device_path="/sys/class/i2c-dev/i2c-${bus}/device/${bus}-${slave_addr_formatted}"

    if [[ ! -f "$eeprom_path" ]]; then
        log_message "err" "EEPROM not accessible: $eeprom_path"
        return 1
    fi

    if [[ ! -f "$bin_file" ]]; then
        log_message "err" "Binary file not found: $bin_file"
        return 1
    fi

    # Check binary file size
    local bin_size
    bin_size=$(stat -c%s "$bin_file" 2>/dev/null || echo 0)

    if [[ $bin_size -eq 0 ]]; then
        log_message "err" "Binary file is empty: $bin_file"
        return 1
    fi

    if [[ $bin_size -gt $eeprom_size ]]; then
        log_message "err" "Binary file size ($bin_size bytes) exceeds EEPROM capacity ($eeprom_size bytes)"
        return 1
    fi

    log_message "info" "Flashing EEPROM: $bin_file ($bin_size bytes) -> $eeprom_path ($eeprom_size bytes capacity)"

    # Check for write_protect attribute and disable it if present
    local wp_attr="${device_path}/write_protect"
    local wp_original=""
    if [[ -f "$wp_attr" ]]; then
        wp_original=$(cat "$wp_attr" 2>/dev/null)
        log_message "info" "Found write_protect attribute, current value: $wp_original"
        if ! echo 0 > "$wp_attr" 2>/dev/null; then
            log_message "warning" "Failed to disable write_protect attribute"
        else
            log_message "info" "Write protection disabled"
        fi
    else
        log_message "info" "No write_protect attribute found in sysfs"
    fi

    # Check for nvmem write_protect (alternative location)
    local nvmem_wp="${device_path}/nvmem0/write_protect"
    local nvmem_wp_original=""
    if [[ -f "$nvmem_wp" ]]; then
        nvmem_wp_original=$(cat "$nvmem_wp" 2>/dev/null)
        log_message "info" "Found nvmem write_protect: $nvmem_wp_original"
        if ! echo 0 > "$nvmem_wp" 2>/dev/null; then
            log_message "warning" "Failed to disable nvmem write_protect"
        else
            log_message "info" "nvmem write protection disabled"
        fi
    fi

    # Helper function to restore write protection (called before any return)
    restore_write_protection()
    {
        # Restore write_protect if it was changed
        if [[ -n "$wp_original" ]] && [[ -f "$wp_attr" ]]; then
            if ! echo "$wp_original" > "$wp_attr" 2>/dev/null; then
                log_message "warning" "Failed to restore write_protect attribute to $wp_original"
            else
                log_message "info" "Write protection restored to: $wp_original"
            fi
        fi

        # Restore nvmem write_protect if it was changed
        if [[ -n "$nvmem_wp_original" ]] && [[ -f "$nvmem_wp" ]]; then
            if ! echo "$nvmem_wp_original" > "$nvmem_wp" 2>/dev/null; then
                log_message "warning" "Failed to restore nvmem write_protect to $nvmem_wp_original"
            else
                log_message "info" "nvmem write protection restored to: $nvmem_wp_original"
            fi
        fi
    }

    # Save original permissions before modifying
    local original_perms
    original_perms=$(stat -c "%a" "$eeprom_path" 2>/dev/null)
    if [[ -z "$original_perms" ]]; then
        log_message "warning" "Could not read original EEPROM permissions, assuming 644"
        original_perms="644"
    fi

    # Ensure EEPROM is writable
    if ! chmod 666 "$eeprom_path" 2>/dev/null; then
        log_message "err" "Failed to set write permissions on EEPROM: $eeprom_path"
        restore_write_protection  # Restore before returning
        return 1
    fi

    # Try to unbind and rebind the EEPROM driver to clear any caches
    # This forces the driver to re-read the device on next access
    local device_name="${bus}-${slave_addr_formatted}"
    local unbind_path="/sys/bus/i2c/drivers/at24/unbind"
    local bind_path="/sys/bus/i2c/drivers/at24/bind"

    if [[ -f "$unbind_path" ]] && [[ -f "$bind_path" ]]; then
        log_message "info" "Unbinding EEPROM driver to clear cache"
        if echo "$device_name" > "$unbind_path" 2>/dev/null; then
            sleep 0.2
            log_message "info" "Rebinding EEPROM driver"
            if echo "$device_name" > "$bind_path" 2>/dev/null; then
                sleep 0.5
                log_message "info" "Driver rebound successfully"
            else
                log_message "warning" "Failed to rebind driver, continuing anyway"
            fi
        else
            log_message "info" "Driver unbind not needed or failed (device may be in use)"
        fi
    fi

    # For small EEPROMs (like 24c02 = 256 bytes), use byte-by-byte write for reliability
    # Block writes can fail on some EEPROM drivers
    local dd_output
    local dd_status

    if [[ $bin_size -le 512 ]]; then
        # Use bs=1 for small EEPROMs to ensure every byte is written
        log_message "info" "Using byte-by-byte write for small EEPROM"
        dd_output=$(dd if="$bin_file" of="$eeprom_path" bs=1 count="$bin_size" conv=fsync 2>&1)
        dd_status=$?
    else
        # Use block size for larger EEPROMs
        local block_size=256
        local block_count=$(( (bin_size + block_size - 1) / block_size ))
        dd_output=$(dd if="$bin_file" of="$eeprom_path" bs="$block_size" count="$block_count" iflag=fullblock conv=fsync 2>&1)
        dd_status=$?
    fi

    # Restore original permissions
    if ! chmod "$original_perms" "$eeprom_path" 2>/dev/null; then
        log_message "warning" "Failed to restore original EEPROM permissions"
    fi

    # Always restore write protection before returning
    restore_write_protection

    if [[ $dd_status -ne 0 ]]; then
        log_message "err" "Failed to flash EEPROM: $dd_output"
        return 1
    fi

    log_message "info" "Write operation completed, dd reported success"

    # Add delay for EEPROM write completion
    # EEPROM write cycle time varies by size: ~5ms per page (typically 32-128 bytes)
    # Increase delays for better reliability
    local write_delay
    if [[ $bin_size -le 256 ]]; then
        write_delay=1.0  # Small EEPROMs (24c01, 24c02) - increased from 0.5
    elif [[ $bin_size -le 2048 ]]; then
        write_delay=2.0  # Medium EEPROMs (24c04-24c16) - increased from 1.0
    elif [[ $bin_size -le 8192 ]]; then
        write_delay=3.0  # Large EEPROMs (24c32-24c64) - increased from 2.0
    else
        write_delay=5.0  # Very large EEPROMs (24c128-24c512) - increased from 3.0
    fi

    log_message "info" "Waiting ${write_delay}s for EEPROM write completion"
    sleep "$write_delay"

    log_message "info" "EEPROM write completed (content verification will be performed by caller)"
    return 0
}

# Function to process a single cartridge device
# Return codes: 0 = flashed successfully, 2 = skipped (already matching), 3 = dry-run mismatch, 1 = failed
process_cartridge()
{
    local index="$1"
    local device_type="$2"
    local bus="$3"
    local slave_addr="$4"
    local bin_file="$5"

    log_message "info" "=========================================="
    log_message "info" "Processing Cartridge $index: $device_type at Bus $bus Addr $slave_addr"

    # Validate binary file exists
    if [[ ! -f "$bin_file" ]]; then
        log_message "err" "Binary file not found: $bin_file"
        return 1
    fi

    # Get EEPROM size based on device type
    local eeprom_size
    eeprom_size=$(get_eeprom_size "$device_type")
    log_message "info" "EEPROM size for $device_type: $eeprom_size bytes"

    # Check binary file size
    local bin_size
    bin_size=$(stat -c%s "$bin_file" 2>/dev/null || echo 0)

    if [[ $bin_size -eq 0 ]]; then
        log_message "err" "Binary file is empty: $bin_file"
        return 1
    fi

    if [[ $bin_size -gt $eeprom_size ]]; then
        log_message "err" "Binary file size ($bin_size bytes) exceeds EEPROM capacity ($eeprom_size bytes)"
        return 1
    fi

    # Format slave address (0x50 -> 0050) with validation
    local slave_addr_formatted
    slave_addr_formatted=$(format_slave_addr "$slave_addr")
    if [[ $? -ne 0 ]]; then
        log_message "err" "Invalid slave address format: $slave_addr"
        return 1
    fi

    # Step 1: Ensure device exists in sysfs
    if ! ensure_device_exists "$device_type" "$bus" "$slave_addr" "$slave_addr_formatted"; then
        log_message "err" "Failed to ensure device exists"
        return 1
    fi

    # Step 2: Dump current EEPROM content (full EEPROM size for accurate comparison)
    # Reading full EEPROM ensures we detect any garbage data beyond binary size
    local temp_dump="${TEMP_DIR}/cartridge-${bus}-${slave_addr_formatted}.bin"
    log_message "info" "Dumping full EEPROM content ($eeprom_size bytes) for comparison"
    if ! dump_eeprom "$bus" "$slave_addr_formatted" "$temp_dump" "$eeprom_size"; then
        log_message "err" "Failed to dump EEPROM"
        return 1
    fi

    # Step 3: Compare current content with target binary (only first bin_size bytes)
    # For proper comparison, truncate EEPROM dump to binary size
    log_message "info" "Comparing EEPROM content (first $bin_size bytes) with target binary"
    local temp_dump_truncated="${temp_dump}.cmp"

    # Use optimized block size for truncation
    local trunc_block_size=256
    local trunc_block_count=$(( (bin_size + trunc_block_size - 1) / trunc_block_size ))
    if ! dd if="$temp_dump" of="$temp_dump_truncated" bs="$trunc_block_size" count="$trunc_block_count" iflag=fullblock 2>/dev/null; then
        log_message "err" "Failed to truncate EEPROM dump for comparison"
        rm -f "$temp_dump" "$temp_dump_truncated"
        return 1
    fi

    # Truncate to exact size (use same fallback logic as dump_eeprom)
    if command -v truncate >/dev/null 2>&1; then
        if ! truncate -s "$bin_size" "$temp_dump_truncated" 2>/dev/null; then
            log_message "err" "Failed to adjust truncated dump to exact size"
            rm -f "$temp_dump" "$temp_dump_truncated"
            return 1
        fi
    else
        # Fallback: use dd if truncate not available
        local temp_final="${temp_dump_truncated}.final"
        if ! dd if="$temp_dump_truncated" of="$temp_final" bs=1 count="$bin_size" 2>/dev/null; then
            log_message "err" "Failed to adjust truncated dump to exact size (dd fallback)"
            rm -f "$temp_dump" "$temp_dump_truncated" "$temp_final"
            return 1
        fi
        mv "$temp_final" "$temp_dump_truncated"
    fi

    if compare_files "$temp_dump_truncated" "$bin_file"; then
        log_message "info" "EEPROM content matches target - skipping flash"
        rm -f "$temp_dump" "$temp_dump_truncated"
        return 2  # Return 2 to indicate skip
    fi

    log_message "info" "EEPROM content differs from target"
    rm -f "$temp_dump_truncated"

    # In dry-run mode, report the mismatch and return without flashing
    if [[ $DRY_RUN -eq 1 ]]; then
        log_message "info" "[DRY-RUN] Would flash EEPROM, but dry-run mode is enabled"
        log_message "info" "[DRY-RUN] Mismatch detected - cartridge would be updated"
        rm -f "$temp_dump"
        return 3  # Return 3 to indicate dry-run mismatch
    fi

    log_message "info" "Proceeding with flash"

    # Step 4: Flash EEPROM
    if ! flash_eeprom "$bin_file" "$bus" "$slave_addr_formatted" "$eeprom_size"; then
        log_message "err" "Failed to flash EEPROM"
        rm -f "$temp_dump"
        return 1
    fi

    # Step 5: Verify flashing succeeded
    # Read back full EEPROM to detect any writes beyond expected bounds
    log_message "info" "Verifying flash operation"

    # Unbind/rebind driver again before verification to ensure we read from hardware, not cache
    local device_name="${bus}-${slave_addr_formatted}"
    local unbind_path="/sys/bus/i2c/drivers/at24/unbind"
    local bind_path="/sys/bus/i2c/drivers/at24/bind"

    if [[ -f "$unbind_path" ]] && [[ -f "$bind_path" ]]; then
        log_message "info" "Unbinding driver before verification to ensure fresh read from EEPROM"
        if echo "$device_name" > "$unbind_path" 2>/dev/null; then
            sleep 0.2
            if echo "$device_name" > "$bind_path" 2>/dev/null; then
                sleep 0.5
                log_message "info" "Driver rebound for verification"
            fi
        fi
    fi

    local verify_dump="${TEMP_DIR}/cartridge-${bus}-${slave_addr_formatted}-verify.bin"
    log_message "info" "Dumping full EEPROM ($eeprom_size bytes) for comprehensive verification"
    if ! dump_eeprom "$bus" "$slave_addr_formatted" "$verify_dump" "$eeprom_size"; then
        log_message "err" "Failed to dump EEPROM for verification"
        rm -f "$temp_dump" "$verify_dump"
        return 1
    fi

    # Step 6: Compare verified content with target binary
    # Truncate verify dump to bin_size for comparison
    local verify_dump_truncated="${verify_dump}.cmp"

    # Use dd to extract exactly bin_size bytes for comparison
    if ! dd if="$verify_dump" of="$verify_dump_truncated" bs=1 count="$bin_size" 2>/dev/null; then
        log_message "err" "Failed to truncate verification dump for comparison"
        rm -f "$temp_dump" "$verify_dump" "$verify_dump_truncated"
        return 1
    fi

    if compare_files "$verify_dump_truncated" "$bin_file"; then
        log_message "info" "Flash verification PASSED - EEPROM content matches target"
        rm -f "$verify_dump" "$verify_dump_truncated" "$temp_dump"
        return 0  # Return 0 to indicate successful flash
    else
        log_message "err" "Flash verification FAILED - EEPROM content does not match target"
        rm -f "$temp_dump" "$verify_dump" "$verify_dump_truncated"
        return 1
    fi
}

# Function to dump current EEPROM content for all devices
dump_current_content()
{
    local json_file="$1"

    if [[ ! -f "$json_file" ]]; then
        log_message "err" "JSON configuration file not found: $json_file"
        return 1
    fi

    log_message "info" "Dumping Current EEPROM Content"
    log_message "info" "=========================================="

    # Validate JSON syntax
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        log_message "err" "Invalid JSON syntax in file: $json_file"
        return 1
    fi

    # Extract device count
    local num_devices
    num_devices=$(jq '.Devices | length // 0' "$json_file")

    # Validate num_devices is numeric
    if [[ -z "$num_devices" ]] || ! echo "$num_devices" | grep -qE '^[0-9]+$'; then
        log_message "warning" "Invalid device count from JSON, defaulting to 0"
        num_devices=0
    fi

    if [[ "$num_devices" -eq 0 ]]; then
        log_message "err" "No devices found in JSON configuration"
        return 1
    fi

    log_message "info" "Found $num_devices cartridge device(s) to dump"

    local success_count=0
    local failed_count=0

    # Iterate through each device
    local dev_idx=0
    while [ $dev_idx -lt $num_devices ]; do
        # Extract device information
        local index
        local device_type
        local bus
        local slave_addr

        index=$(jq -r ".Devices[$dev_idx].Index" "$json_file")
        device_type=$(jq -r ".Devices[$dev_idx].DeviceType" "$json_file")
        bus=$(jq -r ".Devices[$dev_idx].Bus" "$json_file")
        slave_addr=$(jq -r ".Devices[$dev_idx].SlaveAddr" "$json_file")

        log_message "info" "=========================================="
        log_message "info" "Dumping Cartridge $index: $device_type at Bus $bus Addr $slave_addr"

        # Validate extracted fields
        if [[ -z "$device_type" ]] || [[ "$device_type" == "null" ]]; then
            log_message "err" "Missing DeviceType for device $dev_idx"
            failed_count=$((failed_count + 1))
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$bus" ]] || [[ "$bus" == "null" ]]; then
            log_message "err" "Missing Bus for device $dev_idx"
            failed_count=$((failed_count + 1))
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$slave_addr" ]] || [[ "$slave_addr" == "null" ]]; then
            log_message "err" "Missing SlaveAddr for device $dev_idx"
            failed_count=$((failed_count + 1))
            dev_idx=$((dev_idx + 1))
            continue
        fi

        # Get EEPROM size
        local eeprom_size
        eeprom_size=$(get_eeprom_size "$device_type")
        log_message "info" "EEPROM size for $device_type: $eeprom_size bytes"

        # Format slave address
        local slave_addr_formatted
        slave_addr_formatted=$(format_slave_addr "$slave_addr")
        if [[ $? -ne 0 ]]; then
            log_message "err" "Invalid slave address format: $slave_addr"
            failed_count=$((failed_count + 1))
            dev_idx=$((dev_idx + 1))
            continue
        fi

        # Ensure device exists
        if ! ensure_device_exists "$device_type" "$bus" "$slave_addr" "$slave_addr_formatted"; then
            log_message "err" "Failed to ensure device exists"
            failed_count=$((failed_count + 1))
            dev_idx=$((dev_idx + 1))
            continue
        fi

        # Output file name
        local output_file="/tmp/cartridge${index}_readback.bin"

        # Dump EEPROM
        if dump_eeprom "$bus" "$slave_addr_formatted" "$output_file" "$eeprom_size"; then
            log_message "info" "Successfully dumped to: $output_file"

            # Show hex preview of first 64 bytes
            if command -v hexdump >/dev/null 2>&1; then
                log_message "info" "Preview (first 64 bytes):"
                hexdump -C "$output_file" 2>/dev/null | head -4 | awk '{print "  " $0}' | logger -t "$LOG_TAG" -p "daemon.info"
                hexdump -C "$output_file" 2>/dev/null | head -4 | awk '{print "  " $0}'
            fi

            success_count=$((success_count + 1))
        else
            log_message "err" "Failed to dump EEPROM"
            failed_count=$((failed_count + 1))
        fi

        dev_idx=$((dev_idx + 1))
    done

    # Summary
    log_message "info" "=========================================="
    log_message "info" "Dump Summary:"
    log_message "info" "  Total Devices:  $num_devices"
    log_message "info" "  Success:        $success_count"
    log_message "info" "  Failed:         $failed_count"
    log_message "info" "=========================================="

    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Function to modify a byte in a binary file
modify_bin_file()
{
    local bin_file="$1"
    local offset="$2"
    local hex_data="$3"

    echo "=========================================="
    echo "Binary File Modifier"
    echo "=========================================="

    # Validate binary file exists
    if [[ ! -f "$bin_file" ]]; then
        echo "ERROR: Binary file not found: $bin_file"
        return 1
    fi

    # Validate offset is numeric
    if ! echo "$offset" | grep -qE '^[0-9]+$'; then
        echo "ERROR: Offset must be a decimal number: $offset"
        return 1
    fi

    # Get file size
    local file_size
    file_size=$(stat -c%s "$bin_file" 2>/dev/null || echo 0)

    if [[ $file_size -eq 0 ]]; then
        echo "ERROR: Binary file is empty or cannot read size"
        return 1
    fi

    # Validate offset is within file bounds
    if [[ $offset -ge $file_size ]]; then
        echo "ERROR: Offset $offset is beyond file size ($file_size bytes)"
        return 1
    fi

    # Parse hex data (remove 0x prefix if present)
    local hex_value="${hex_data#0x}"
    hex_value="${hex_value#0X}"

    # Validate hex format
    if ! echo "$hex_value" | grep -qE '^[0-9a-fA-F]{1,2}$'; then
        echo "ERROR: Invalid hex data format: $hex_data (must be 1-2 hex digits)"
        return 1
    fi

    # Ensure 2-digit format
    if [[ ${#hex_value} -eq 1 ]]; then
        hex_value="0${hex_value}"
    fi

    # Convert to uppercase for consistency
    hex_value=$(echo "$hex_value" | tr '[:lower:]' '[:upper:]')

    echo "File:         $bin_file"
    echo "Size:         $file_size bytes"
    echo "Offset:       $offset (0x$(printf '%x' $offset))"
    echo ""

    # Show current byte value
    if command -v hexdump >/dev/null 2>&1; then
        local current_byte
        current_byte=$(hexdump -v -s "$offset" -n 1 -e '1/1 "%02X"' "$bin_file" 2>/dev/null)
        echo "Current byte: 0x$current_byte"
    fi

    echo "New value:    0x$hex_value"
    echo ""

    # Create backup
    local backup_file="${bin_file}.backup"
    if ! cp "$bin_file" "$backup_file" 2>/dev/null; then
        echo "ERROR: Failed to create backup file: $backup_file"
        return 1
    fi
    echo "Backup created: $backup_file"

    # Modify the byte using hex-to-binary conversion
    # Use multiple methods with fallback to ensure portability and safety
    # Avoid printf '%b' which interprets escape sequences and corrupts data
    local write_success=0
    local write_method=""

    # Method 1: Try Python (most reliable for binary data)
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex('${hex_value}'))" 2>/dev/null | \
           dd of="$bin_file" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null; then
            write_success=1
            write_method="python3"
        fi
    fi

    # Method 2: Try xxd (reliable hex-to-binary conversion)
    if [[ $write_success -eq 0 ]] && command -v xxd >/dev/null 2>&1; then
        if echo "$hex_value" | xxd -r -p | dd of="$bin_file" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null; then
            write_success=1
            write_method="xxd"
        fi
    fi

    # Method 3: Try Perl (widely available, safe for binary)
    if [[ $write_success -eq 0 ]] && command -v perl >/dev/null 2>&1; then
        if perl -e "print pack('H*', '${hex_value}')" | dd of="$bin_file" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null; then
            write_success=1
            write_method="perl"
        fi
    fi

    # Method 4: Fallback to printf (avoid %b, use octal for safety)
    # Convert hex to octal to avoid escape sequence interpretation
    if [[ $write_success -eq 0 ]]; then
        local octal_value=$(printf '%o' "0x${hex_value}")
        if printf "\\${octal_value}" | dd of="$bin_file" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null; then
            write_success=1
            write_method="printf-octal"
        fi
    fi

    if [[ $write_success -eq 0 ]]; then
        echo "ERROR: Failed to modify byte at offset $offset (no suitable method available)"
        echo "Restoring from backup..."
        mv "$backup_file" "$bin_file"
        return 1
    fi

    echo "Byte modified successfully using $write_method"
    echo ""

    # Verify the modification
    if command -v hexdump >/dev/null 2>&1; then
        local new_byte
        new_byte=$(hexdump -v -s "$offset" -n 1 -e '1/1 "%02X"' "$bin_file" 2>/dev/null)
        echo "Verification:"
        echo "  New byte value: 0x$new_byte"

        if [[ "$new_byte" == "$hex_value" ]]; then
            echo "  Status: SUCCESS - Byte modified correctly"
        else
            echo "  Status: FAILED - Byte value doesn't match expected"
            echo "Restoring from backup..."
            mv "$backup_file" "$bin_file"
            return 1
        fi
    fi

    echo ""
    echo "=========================================="
    echo "Modification completed successfully"
    echo "Original file backed up to: $backup_file"
    echo "=========================================="

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
    num_devices=$(jq '.Devices | length // 0' "$json_file")

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

    local dev_idx=0
    while [ $dev_idx -lt $num_devices ]; do
        echo "Device $((dev_idx+1)):"

        # Extract device information
        local index
        local device_type
        local bus
        local slave_addr
        local bin_file

        index=$(jq -r ".Devices[$dev_idx].Index" "$json_file" 2>/dev/null)
        device_type=$(jq -r ".Devices[$dev_idx].DeviceType" "$json_file" 2>/dev/null)
        bus=$(jq -r ".Devices[$dev_idx].Bus" "$json_file" 2>/dev/null)
        slave_addr=$(jq -r ".Devices[$dev_idx].SlaveAddr" "$json_file" 2>/dev/null)
        bin_file=$(jq -r ".Devices[$dev_idx].CartridgeBinFile" "$json_file" 2>/dev/null)

        # Validate Index
        if [[ -z "$index" ]] || [[ "$index" == "null" ]]; then
            echo "  [ERROR] Missing 'Index'"
            validation_errors=$((validation_errors + 1))
        else
            echo "  Index: $index"
        fi

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
        elif ! echo "$bus" | grep -qE '^[0-9]+$' || [[ "$bus" -lt 0 ]] || [[ "$bus" -gt 65535 ]]; then
            echo "  [ERROR] Invalid 'Bus' value (must be 0-65535): $bus"
            validation_errors=$((validation_errors + 1))
        else
            echo "  Bus: $bus"
        fi

        # Validate SlaveAddr
        if [[ -z "$slave_addr" ]] || [[ "$slave_addr" == "null" ]]; then
            echo "  [ERROR] Missing 'SlaveAddr'"
            validation_errors=$((validation_errors + 1))
        else
            echo "  SlaveAddr: $slave_addr"
        fi

        # Validate CartridgeBinFile
        if [[ -z "$bin_file" ]] || [[ "$bin_file" == "null" ]]; then
            echo "  [ERROR] Missing 'CartridgeBinFile'"
            validation_errors=$((validation_errors + 1))
        else
            echo "  CartridgeBinFile: $bin_file"
            if [[ ! -f "$bin_file" ]]; then
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

    if [[ $DRY_RUN -eq 1 ]]; then
        log_message "info" "=========================================="
        log_message "info" "DRY-RUN MODE ENABLED"
        log_message "info" "Will compare EEPROM content with binary files"
        log_message "info" "No flashing will be performed"
        log_message "info" "=========================================="
    fi

    # Validate JSON syntax
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        log_message "err" "Invalid JSON syntax in file: $json_file"
        return 1
    fi

    local total_devices=0
    local successful_flashes=0
    local skipped_flashes=0
    local failed_flashes=0
    local failed_devices=()

    # Extract device count
    local num_devices
    num_devices=$(jq '.Devices | length // 0' "$json_file")

    # Validate num_devices is numeric
    if [[ -z "$num_devices" ]] || ! echo "$num_devices" | grep -qE '^[0-9]+$'; then
        log_message "warning" "Invalid device count from JSON, defaulting to 0"
        num_devices=0
    fi

    log_message "info" "Found $num_devices cartridge device(s) to process"

    # Iterate through each device
    local dev_idx=0
    while [ $dev_idx -lt $num_devices ]; do
        total_devices=$((total_devices + 1))

        # Extract device information
        local index
        local device_type
        local bus
        local slave_addr
        local bin_file

        index=$(jq -r ".Devices[$dev_idx].Index" "$json_file")
        device_type=$(jq -r ".Devices[$dev_idx].DeviceType" "$json_file")
        bus=$(jq -r ".Devices[$dev_idx].Bus" "$json_file")
        slave_addr=$(jq -r ".Devices[$dev_idx].SlaveAddr" "$json_file")
        bin_file=$(jq -r ".Devices[$dev_idx].CartridgeBinFile" "$json_file")

        # Validate extracted fields
        if [[ -z "$device_type" ]] || [[ "$device_type" == "null" ]]; then
            log_message "err" "Missing DeviceType for device $dev_idx"
            failed_flashes=$((failed_flashes + 1))
            failed_devices+=("Index:${index:-unknown} Bus:${bus:-unknown} Addr:${slave_addr:-unknown}")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$bus" ]] || [[ "$bus" == "null" ]]; then
            log_message "err" "Missing Bus for device $dev_idx"
            failed_flashes=$((failed_flashes + 1))
            failed_devices+=("Index:${index:-unknown} Type:$device_type Addr:${slave_addr:-unknown}")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$slave_addr" ]] || [[ "$slave_addr" == "null" ]]; then
            log_message "err" "Missing SlaveAddr for device $dev_idx"
            failed_flashes=$((failed_flashes + 1))
            failed_devices+=("Index:${index:-unknown} Type:$device_type Bus:$bus")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        if [[ -z "$bin_file" ]] || [[ "$bin_file" == "null" ]]; then
            log_message "err" "Missing CartridgeBinFile for device $dev_idx"
            failed_flashes=$((failed_flashes + 1))
            failed_devices+=("Index:${index:-unknown} Type:$device_type Bus:$bus Addr:$slave_addr")
            dev_idx=$((dev_idx + 1))
            continue
        fi

        # Process cartridge
        local result_code
        process_cartridge "$index" "$device_type" "$bus" "$slave_addr" "$bin_file"
        result_code=$?

        if [[ $result_code -eq 0 ]]; then
            # Successfully flashed
            successful_flashes=$((successful_flashes + 1))
        elif [[ $result_code -eq 2 ]]; then
            # Skipped (content already matches)
            skipped_flashes=$((skipped_flashes + 1))
        elif [[ $result_code -eq 3 ]]; then
            # Dry-run mismatch detected
            failed_flashes=$((failed_flashes + 1))
            # Format address for reporting (use INVALID if formatting fails)
            local slave_addr_formatted
            slave_addr_formatted=$(format_slave_addr "$slave_addr")
            if [[ $? -ne 0 ]]; then
                slave_addr_formatted="INVALID"
            fi
            failed_devices+=("Index:$index Type:$device_type Bus:$bus Addr:$slave_addr_formatted [MISMATCH]")
        else
            # Failed
            failed_flashes=$((failed_flashes + 1))
            # Format address for reporting (use INVALID if formatting fails)
            local slave_addr_formatted
            slave_addr_formatted=$(format_slave_addr "$slave_addr")
            if [[ $? -ne 0 ]]; then
                slave_addr_formatted="INVALID"
            fi
            failed_devices+=("Index:$index Type:$device_type Bus:$bus Addr:$slave_addr_formatted")
        fi

        dev_idx=$((dev_idx + 1))
    done

    # Summary
    log_message "info" "=========================================="
    if [[ $DRY_RUN -eq 1 ]]; then
        log_message "info" "Dry-Run Comparison Summary:"
    else
        log_message "info" "Cartridge Flash Summary:"
    fi
    log_message "info" "  Total Devices:     $total_devices"
    if [[ $DRY_RUN -eq 1 ]]; then
        log_message "info" "  Matching:          $skipped_flashes"
        log_message "info" "  Mismatched:        $failed_flashes"
        # Calculate errors safely, ensuring non-negative result
        local errors=$(( total_devices - successful_flashes - skipped_flashes - failed_flashes ))
        if [[ $errors -lt 0 ]]; then
            errors=0
        fi
        log_message "info" "  Errors:            $errors"
    else
        log_message "info" "  Successful Flash:  $successful_flashes"
        log_message "info" "  Skipped (Match):   $skipped_flashes"
        log_message "info" "  Failed:            $failed_flashes"
    fi

    if [[ $failed_flashes -gt 0 ]]; then
        log_message "info" ""
        if [[ $DRY_RUN -eq 1 ]]; then
            log_message "info" "Mismatched Devices (would be flashed):"
        else
            log_message "info" "Failed Devices:"
        fi
        local idx=0
        while [[ $idx -lt ${#failed_devices[@]} ]]; do
            log_message "info" "  ${failed_devices[$idx]}"
            idx=$((idx + 1))
        done
    fi

    log_message "info" "=========================================="

    if [[ $failed_flashes -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Main execution
main()
{
    local validate_only=0
    local dump_only=0
    local modify_bin_mode=0
    local json_file=""
    local modify_bin_file=""
    local modify_offset=""
    local modify_data=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --validate-json)
                validate_only=1
                shift
                ;;
            --dump-current-content)
                dump_only=1
                shift
                ;;
            --modify-bin)
                modify_bin_mode=1
                shift
                # Expect 3 more arguments: file, offset, data
                if [[ $# -lt 3 ]]; then
                    echo "Error: --modify-bin requires 3 arguments: <file> <offset> <data>"
                    usage
                    exit 1
                fi
                modify_bin_file="$1"
                modify_offset="$2"
                modify_data="$3"
                shift 3
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

    # Handle --modify-bin mode separately (doesn't require JSON file)
    if [[ $modify_bin_mode -eq 1 ]]; then
        if modify_bin_file "$modify_bin_file" "$modify_offset" "$modify_data"; then
            exit 0
        else
            exit 1
        fi
    fi

    # Check if JSON file is provided for other modes
    if [[ -z "$json_file" ]]; then
        echo "Error: JSON configuration file not specified"
        usage
        exit 1
    fi

    # If validation mode, validate and exit
    if [[ $validate_only -eq 1 ]]; then
        # Check dependencies (skip dd check for validation)
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

    # If dump mode, dump and exit
    if [[ $dump_only -eq 1 ]]; then
        # Check dependencies
        if ! check_dependencies; then
            log_message "err" "Dependency check failed - exiting"
            exit 1
        fi

        # Dump current content
        if dump_current_content "$json_file"; then
            log_message "info" "Dump Completed Successfully"
            exit 0
        else
            log_message "err" "Dump Completed with Errors"
            exit 1
        fi
    fi

    # Normal operation: flash cartridges
    log_message "info" "Cartridge EEPROM Flash Tool Started"

    # Check dependencies
    if ! check_dependencies; then
        log_message "err" "Dependency check failed - exiting"
        exit 1
    fi

    # Process JSON configuration
    if process_json_config "$json_file"; then
        log_message "info" "Cartridge EEPROM Flash Completed Successfully"
        exit 0
    else
        log_message "err" "Cartridge EEPROM Flash Completed with Errors"
        exit 1
    fi
}

# Execute main function
main "$@"

