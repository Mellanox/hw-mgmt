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
# A2D leakage channel reader: reads ADS1015, ADS7924 (IIO or raw I2C), and placeholder MAX1363
# and writes per-channel voltage files under /var/run/hw-management/leakage/,
# alongside the tree created by hw-management-bmc-a2d-leakage-config.sh.
# Origin: OpenBMC meta-nvidia bmc-post-boot-cfg a2d_leakage_read.sh
################################################################################

LEAKAGE_BASE="/var/run/hw-management/leakage"
LOG_TAG="a2d_read"

# Function to log messages
log_message()
{
    local level="$1"
    local message="$2"
    logger -t "$LOG_TAG" -p "daemon.$level" "$message"
    echo "[$level] $message"
}

# Function to read a single ADS1015 channel (legacy i2c sequence from OpenBMC; verify against TI ADS1015 mux/config).
# Usage: ads1015_read_channel <bus> <address> <channel> <offset>
ads1015_read_channel()
{
    local bus="$1"
    local addr="$2"
    local channel="$3"
    local offset="$4"

    # Write channel selection (register 0x01, offset, 0x90)
    if ! i2ctransfer -f -y "$bus" w3@"$addr" 0x01 "$offset" 0x90 >/dev/null 2>&1; then
        log_message "warning" "Failed to select ADS1015 channel $channel on bus $bus addr $addr"
        return 1
    fi

    # Wait for conversion
    sleep 0.1

    # Read conversion result (2 bytes from register 0x00)
    local raw_hex
    raw_hex=$(i2ctransfer -f -y "$bus" w1@"$addr" 0x00 r2 2>/dev/null)

    if [[ -z "$raw_hex" ]]; then
        log_message "warning" "Failed to read ADS1015 channel $channel on bus $bus addr $addr"
        return 1
    fi

    # Parse high and low bytes
    local hi=${raw_hex%% *}
    local lo=${raw_hex##* }

    # Combine to 16-bit value: (hi << 8) | lo
    local read_val=$(( (hi << 8) | lo ))

    # Convert to voltage: (read_val / 16) * 0.002
    local result
    result=$(echo "scale=6; ($read_val/16)*0.002" | bc 2>/dev/null)

    if [[ -z "$result" ]]; then
        log_message "warning" "Failed to calculate voltage for channel $channel"
        return 1
    fi

    # Ensure leading zero for values < 1 (bc may output .123 instead of 0.123)
    if [[ "$result" == .* ]]; then
        result="0$result"
    fi

    echo "$result"
    return 0
}

# Function to read all ADS1015 channels for a device
# Usage: ads1015_read_channels <bus> <address> <device_dir>
ads1015_read_channels()
{
    local bus="$1"
    local addr="$2"
    local device_dir="$3"

    # Channel offset mapping (legacy; ADS1015 uses CONFIG register MUX — align with board when hardware is available)
    declare -A channel_offsets
    channel_offsets[1]="0xc2"
    channel_offsets[2]="0xd2"
    channel_offsets[3]="0xe2"
    channel_offsets[4]="0xf2"

    log_message "info" "Reading ADS1015 channels on bus $bus addr $addr"

    local channels_read=0
    local channels_skipped=0

    # Iterate through channel directories
    for ch_dir in "$device_dir"/[0-9]*; do
        if [[ ! -d "$ch_dir" ]]; then
            continue
        fi

        local ch_num=$(basename "$ch_dir")

        # Check if this channel number is valid (1-4)
        if [[ ! -v channel_offsets[$ch_num] ]]; then
            log_message "debug" "Skipping channel $ch_num (not supported by ADS1015 mapping)"
            ((channels_skipped++))
            continue
        fi

        # Check if channel has a name link and if it should be skipped
        local skip_channel=0
        for link in "$device_dir"/*; do
            if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "$ch_num" ]]; then
                local link_name=$(basename "$link")
                if [[ "$link_name" == Not_Connected* ]]; then
                    log_message "debug" "Skipping channel $ch_num ($link_name - not connected)"
                    skip_channel=1
                    ((channels_skipped++))
                    break
                fi
            fi
        done

        if [[ $skip_channel -eq 1 ]]; then
            continue
        fi

        # Read the channel
        local offset="${channel_offsets[$ch_num]}"
        local value
        value=$(ads1015_read_channel "$bus" "$addr" "$ch_num" "$offset")

        if [[ $? -eq 0 ]] && [[ -n "$value" ]]; then
            # Write value to channel directory
            echo "$value" > "$ch_dir/value"
            log_message "info" "Channel $ch_num: $value V"
            ((channels_read++))
        else
            log_message "warning" "Failed to read channel $ch_num"
        fi
    done

    log_message "info" "ADS1015 read complete: $channels_read read, $channels_skipped skipped"
    return 0
}

# Parse first two 0xNN bytes from i2ctransfer output (big-endian 16-bit).
# Uses grep -oE (BusyBox and GNU); avoid bash-only [[ =~ ]].
ads7924_parse_be16()
{
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -oE '0x[0-9a-f]{1,2}' | head -2 | tr '\n' ' '
}

# True if string is a signed decimal integer (POSIX / BusyBox friendly).
ads7924_is_decimal_int()
{
    awk -v s="$1" 'BEGIN { if (s ~ /^-?[0-9]+$/) exit 0; exit 1 }'
}

# Read ADS7924 channel (1..4): 12-bit code from DATAx_U/L via pointer INC, then volts = raw12 * scale.
ads7924_read_channel_volts()
{
    local bus="$1"
    local addr="$2"
    local channel="$3"
    local scale="$4"
    local ptr raw_hex hi lo val raw12

    ptr=$((0x80 | (0x02 + (channel - 1) * 2)))
    raw_hex=$(i2ctransfer -f -y "$bus" w1@"$addr" "0x$(printf '%02x' "$ptr")" r2 2>/dev/null) || return 1
    set -- $(ads7924_parse_be16 "$raw_hex")
    hi="$1"
    lo="$2"
    [ -n "$hi" ] && [ -n "$lo" ] || return 1
    hi=$((hi))
    lo=$((lo))
    val=$(( (hi << 8) | lo ))
    raw12=$(( val >> 4 ))
    echo "scale=10; ($raw12 * $scale) / 1" | bc 2>/dev/null
}

# Read all ADS7924 channels under device_dir (uses ch_dir/input + scale when present, else I2C).
ads7924_read_channels()
{
    local bus="$1"
    local addr="$2"
    local device_dir="$3"
    local channels_read=0
    local channels_skipped=0
    local ch_dir ch_num scale_f raw_input result skip_channel link link_name

    log_message "info" "Reading ADS7924 channels on bus $bus addr $addr"

    for ch_dir in "$device_dir"/[0-9]*; do
        if [ ! -d "$ch_dir" ]; then
            continue
        fi

        ch_num=$(basename "$ch_dir")
        case "$ch_num" in
        1|2|3|4) ;;
        *)
            log_message "debug" "Skipping channel dir $ch_num (ADS7924 supports 1–4)"
            channels_skipped=$((channels_skipped + 1))
            continue
            ;;
        esac

        skip_channel=0
        for link in "$device_dir"/*; do
            if [ -L "$link" ] && [ "$(readlink "$link")" = "$ch_num" ]; then
                link_name=$(basename "$link")
                case "$link_name" in
                Not_Connected*)
                    log_message "debug" "Skipping channel $ch_num ($link_name)"
                    skip_channel=1
                    channels_skipped=$((channels_skipped + 1))
                    break
                    ;;
                esac
            fi
        done
        if [ "$skip_channel" -eq 1 ]; then
            continue
        fi

        scale_f="0.000244140625"
        if [ -f "$ch_dir/scale" ]; then
            scale_f=$(tr -d ' \t\r\n' <"$ch_dir/scale")
        fi
        [ -z "$scale_f" ] && scale_f="0.000244140625"

        result=""
        if [ -r "$ch_dir/input" ]; then
            IFS= read -r raw_input <"$ch_dir/input" 2>/dev/null || raw_input=""
            raw_input="${raw_input//$'\r'/}"
            raw_input="${raw_input// /}"
            if [ -n "$raw_input" ] && ads7924_is_decimal_int "$raw_input"; then
                result=$(echo "scale=10; ($raw_input * $scale_f) / 1" | bc 2>/dev/null)
            fi
        fi
        if [ -z "$result" ]; then
            result=$(ads7924_read_channel_volts "$bus" "$addr" "$ch_num" "$scale_f")
        fi

        if [ -n "$result" ]; then
            case "$result" in
            .*) result="0$result" ;;
            esac
            echo "$result" >"$ch_dir/value"
            log_message "info" "Channel $ch_num: $result V"
            channels_read=$((channels_read + 1))
        else
            log_message "warning" "Failed to read ADS7924 channel $ch_num"
        fi
    done

    log_message "info" "ADS7924 read complete: $channels_read read, $channels_skipped skipped"
    return 0
}

# Function to read MAX1363 channels (placeholder - not implemented yet)
# Usage: max1363_read_channels <bus> <address> <device_dir>
max1363_read_channels()
{
    local bus="$1"
    local addr="$2"
    local device_dir="$3"

    log_message "info" "MAX1363 reading not implemented yet (bus $bus addr $addr)"

    # TODO: Implement MAX1363 channel reading
    # For now, just skip

    return 0
}

# Function to process a single device directory
process_device()
{
    local device_dir="$1"

    # Check if device_type file exists
    if [[ ! -f "$device_dir/device_type" ]]; then
        log_message "warning" "No device_type file in $device_dir"
        return 1
    fi

    # Read device type
    local device_type
    device_type=$(cat "$device_dir/device_type" 2>/dev/null)

    if [[ -z "$device_type" ]]; then
        log_message "warning" "Empty device_type in $device_dir"
        return 1
    fi

    # Extract bus and address from directory name (format: 12-0048)
    local dir_name=$(basename "$device_dir")
    local bus=$(echo "$dir_name" | cut -d'-' -f1)
    local addr_hex=$(echo "$dir_name" | cut -d'-' -f2)
    local addr="0x$addr_hex"

    log_message "info" "Processing $device_type device at $device_dir (bus $bus, addr $addr)"

    # Call appropriate reader function based on device type
    case "$device_type" in
        ADS1015)
            ads1015_read_channels "$bus" "$addr" "$device_dir"
            ;;
        ADS7924)
            ads7924_read_channels "$bus" "$addr" "$device_dir"
            ;;
        MAX1363)
            max1363_read_channels "$bus" "$addr" "$device_dir"
            ;;
        *)
            log_message "warning" "Unknown device type: $device_type"
            return 1
            ;;
    esac

    return 0
}

# Function to scan and process all devices
scan_and_read_all()
{
    if [[ ! -d "$LEAKAGE_BASE" ]]; then
        log_message "err" "Leakage base directory not found: $LEAKAGE_BASE"
        return 1
    fi

    log_message "info" "Scanning leakage infrastructure: $LEAKAGE_BASE"

    local devices_processed=0
    local devices_failed=0

    # Iterate through device index directories (1, 2, 3, ...)
    for idx_dir in "$LEAKAGE_BASE"/[0-9]*; do
        if [[ ! -d "$idx_dir" ]]; then
            continue
        fi

        # Iterate through device directories (12-0048, 12-0049, etc.)
        for device_dir in "$idx_dir"/*-*; do
            if [[ ! -d "$device_dir" ]]; then
                continue
            fi

            if process_device "$device_dir"; then
                ((devices_processed++))
            else
                ((devices_failed++))
            fi
        done
    done

    log_message "info" "Scan complete: $devices_processed devices processed, $devices_failed failed"

    return 0
}

# Main execution
main()
{
    log_message "info" "A2D Leakage Channel Reader"

    # Check for bc (needed for floating point calculations)
    if ! command -v bc >/dev/null 2>&1; then
        log_message "err" "bc is not installed. Cannot perform voltage calculations."
        exit 1
    fi

    # Check for i2ctransfer
    if ! command -v i2ctransfer >/dev/null 2>&1; then
        log_message "err" "i2ctransfer is not installed. Cannot read I2C devices."
        exit 1
    fi

    # Scan and read all devices
    scan_and_read_all

    log_message "info" "A2D Channel Reader Completed"
    exit 0
}

# Execute main function
main "$@"
