#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# A2D Leakage Channel Reader Script
#
# This script reads A2D channels from configured devices and populates
# the infrastructure created by a2d_leakage_config.sh
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

# Function to read a single ADS7142 channel
# Usage: ads7142_read_channel <bus> <address> <channel> <offset>
ads7142_read_channel()
{
    local bus="$1"
    local addr="$2"
    local channel="$3"
    local offset="$4"
    
    # Write channel selection (register 0x01, offset, 0x90)
    if ! i2ctransfer -f -y "$bus" w3@"$addr" 0x01 "$offset" 0x90 >/dev/null 2>&1; then
        log_message "warning" "Failed to select ADS7142 channel $channel on bus $bus addr $addr"
        return 1
    fi

    # Wait for conversion
    sleep 0.1

    # Read conversion result (2 bytes from register 0x00)
    local raw_hex
    raw_hex=$(i2ctransfer -f -y "$bus" w1@"$addr" 0x00 r2 2>/dev/null)

    if [[ -z "$raw_hex" ]]; then
        log_message "warning" "Failed to read ADS7142 channel $channel on bus $bus addr $addr"
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

# Function to read all ADS7142 channels for a device
# Usage: ads7142_read_channels <bus> <address> <device_dir>
ads7142_read_channels()
{
    local bus="$1"
    local addr="$2"
    local device_dir="$3"

    # Channel offset mapping for ADS7142
    declare -A channel_offsets
    channel_offsets[1]="0xc2"
    channel_offsets[2]="0xd2"
    channel_offsets[3]="0xe2"
    channel_offsets[4]="0xf2"

    log_message "info" "Reading ADS7142 channels on bus $bus addr $addr"

    local channels_read=0
    local channels_skipped=0

    # Iterate through channel directories
    for ch_dir in "$device_dir"/[0-9]*; do
        if [[ ! -d "$ch_dir" ]]; then
            continue
        fi

        local ch_num=$(basename "$ch_dir")
        # Check if this channel number is valid (1-4 for ADS7142)
        if [[ ! -v channel_offsets[$ch_num] ]]; then
            log_message "debug" "Skipping channel $ch_num (not supported by ADS7142)"
            ((channels_skipped++))
            continue
        fi

        # Read the channel
        local offset="${channel_offsets[$ch_num]}"
        local value
        value=$(ads7142_read_channel "$bus" "$addr" "$ch_num" "$offset")

        if [[ $? -eq 0 ]] && [[ -n "$value" ]]; then
            # Write value to channel directory
            echo "$value" > "$ch_dir/value"
            log_message "info" "Channel $ch_num: $value V"
            ((channels_read++))
        else
            log_message "warning" "Failed to read channel $ch_num"
        fi
    done

    log_message "info" "ADS7142 read complete: $channels_read read, $channels_skipped skipped"
    return 0
}

# Function to read all ADS7924 channels for a device
# The ADS7924 runs in Auto-Scan mode (started by a2d_leakage_config.sh), so
# DATA0..DATA3 are continuously updated: one auto-increment burst read from
# DATA0_U (pointer 0x80|0x02) returns all 4 channels. Values are 12-bit
# left-justified: code = (U << 4) | (L >> 4).
# Usage: ads7924_read_channels <bus> <address> <device_dir>
ads7924_read_channels()
{
    local bus="$1"
    local addr="$2"
    local device_dir="$3"

    # Volts per LSB: from the config-provided scale file, else platform default
    local scale="0.002"
    if [[ -f "$device_dir/scale" ]]; then
        scale=$(cat "$device_dir/scale" 2>/dev/null)
    fi

    log_message "info" "Reading ADS7924 channels on bus $bus addr $addr (scale $scale V/LSB)"

    # Prefer the kernel ti-ads7924 IIO driver when bound (in_voltageN_raw is
    # the 12-bit code); otherwise fall back to raw I2C register access.
    local iio_dir=""
    local i2c_dev="/sys/bus/i2c/devices/$(basename "$device_dir")"
    for d in "$i2c_dev"/iio:device*; do
        [[ -d "$d" ]] && iio_dir="$d" && break
    done

    local bytes=()
    if [[ -n "$iio_dir" ]]; then
        log_message "info" "Using IIO driver interface: $iio_dir"
    else
        local raw_hex
        raw_hex=$(i2ctransfer -f -y "$bus" w1@"$addr" 0x82 r8 2>/dev/null)
        if [[ -z "$raw_hex" ]]; then
            log_message "warning" "Failed to read ADS7924 data registers on bus $bus addr $addr"
            return 1
        fi

        bytes=($raw_hex)
        if [[ ${#bytes[@]} -ne 8 ]]; then
            log_message "warning" "Unexpected ADS7924 data length on bus $bus addr $addr: $raw_hex"
            return 1
        fi
    fi

    local channels_read=0
    local channels_skipped=0

    for ch_dir in "$device_dir"/[0-9]*; do
        if [[ ! -d "$ch_dir" ]]; then
            continue
        fi

        local ch_num=$(basename "$ch_dir")
        # ADS7924 has 4 channels (CH0..CH3 -> directories 1..4)
        if [[ "$ch_num" -lt 1 ]] || [[ "$ch_num" -gt 4 ]]; then
            log_message "debug" "Skipping channel $ch_num (not supported by ADS7924)"
            ((channels_skipped++))
            continue
        fi

        # Prefer the per-channel input symlink created by a2d_leakage_config.sh: it
        # targets the correct hardware IIO node for this channel's Id (which may be
        # non-sequential), matching the hw-mgmt runtime contract. Falls through to
        # the existing IIO-dir / raw-I2C paths when no symlink is present.
        if [[ -e "$ch_dir/input" ]]; then
            local in_code
            in_code=$(cat "$ch_dir/input" 2>/dev/null)
            if [[ -n "$in_code" ]] && [[ "$in_code" =~ ^[0-9]+$ ]]; then
                local in_val
                in_val=$(echo "scale=6; $in_code*$scale" | bc 2>/dev/null)
                if [[ -n "$in_val" ]]; then
                    [[ "$in_val" == .* ]] && in_val="0$in_val"
                    echo "$in_val" > "$ch_dir/value"
                    log_message "info" "Channel $ch_num: $in_val V (code $in_code, via input symlink)"
                    ((channels_read++))
                    continue
                fi
            fi
        fi

        local code
        if [[ -n "$iio_dir" ]]; then
            code=$(cat "$iio_dir/in_voltage$((ch_num - 1))_raw" 2>/dev/null)
            if [[ -z "$code" ]]; then
                log_message "warning" "Failed to read IIO raw value for channel $ch_num"
                continue
            fi
        else
            local hi=${bytes[$(( (ch_num - 1) * 2 ))]}
            local lo=${bytes[$(( (ch_num - 1) * 2 + 1 ))]}
            code=$(( (hi << 4) | (lo >> 4) ))
        fi

        local value
        value=$(echo "scale=6; $code*$scale" | bc 2>/dev/null)
        if [[ -z "$value" ]]; then
            log_message "warning" "Failed to calculate voltage for channel $ch_num"
            continue
        fi
        if [[ "$value" == .* ]]; then
            value="0$value"
        fi

        echo "$value" > "$ch_dir/value"
        log_message "info" "Channel $ch_num: $value V (code $code)"
        ((channels_read++))
    done

    log_message "info" "ADS7924 read complete: $channels_read read, $channels_skipped skipped"
    return 0
}

# Read channels through the kernel IIO driver, via the per-channel input symlink
# that a2d_leakage_config.sh created. Device-agnostic: used for MAX1363 and
# ADS1015, both of which are read live by their driver.
# Usage: iio_read_channels <bus> <address> <device_dir>
iio_read_channels()
{
    local bus="$1"
    local addr="$2"
    local device_dir="$3"

    # a2d_leakage_config.sh links <ch>/input to in_voltage<N>_raw, so each read is
    # a fresh conversion. Publish volts as <ch>/value = input * scale, matching the
    # ADS7924/ADS7142 readers so consumers see a uniform value interface.
    local scale=""
    [[ -f "$device_dir/scale" ]] && scale=$(cat "$device_dir/scale" 2>/dev/null)

    local ch_dir code ch_scale value
    for ch_dir in "$device_dir"/[0-9]*; do
        [[ -d "$ch_dir" ]] || continue
        [[ -e "$ch_dir/input" ]] || continue
        code=$(cat "$ch_dir/input" 2>/dev/null) || continue
        [[ "$code" =~ ^[0-9]+$ ]] || continue
        ch_scale="$scale"
        [[ -f "$ch_dir/scale" ]] && ch_scale=$(cat "$ch_dir/scale" 2>/dev/null)
        [[ -n "$ch_scale" ]] || continue
        value=$(echo "scale=6; $code*$ch_scale" | bc 2>/dev/null) || continue
        [[ -z "$value" ]] && continue
        [[ "$value" == .* ]] && value="0$value"
        echo "$value" > "$ch_dir/value"
        log_message "info" "Channel $(basename "$ch_dir"): $value V (code $code)"
    done

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
        ADS7142)
            ads7142_read_channels "$bus" "$addr" "$device_dir"
            ;;
        ADS7924)
            ads7924_read_channels "$bus" "$addr" "$device_dir"
            ;;
        MAX1363|ADS1015)
            iio_read_channels "$bus" "$addr" "$device_dir"
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

