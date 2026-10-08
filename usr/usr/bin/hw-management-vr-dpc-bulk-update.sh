#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

# Script directory for finding the individual update script.
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
UPDATE_SCRIPT="$SCRIPT_DIR/hw-management-vr-dpc-update.sh"

# Provide fallback log_info if not available (bulk-update runs as its own process).
if ! type log_info >/dev/null 2>&1; then
	log_info()
	{
		logger -t hw-management -p user.info "$1"
	}
fi

# Error handling function.
error_exit()
{
	log_info "ERROR: $1"
	exit 1
}

# Help function.
show_help()
{
	echo "Usage: $0 <hid>"
	echo ""
	echo "Voltage Regulator Bulk Device Flashing Utility"
	echo ""
	echo "DESCRIPTION:"
	echo "  This script scans the system device tree and automatically flashes"
	echo "  all voltage regulator devices that have corresponding firmware files."
	echo "  It reads device information from /var/run/hw-management/config/devtree"
	echo "  and runs individual device updates for matching devices."
	echo ""
	echo "PARAMETERS:"
	echo "  hid            Hardware ID (e.g., hid180) - MANDATORY"
	echo "                 Must be in format hidXXX where XXX are 3 digits"
	echo ""
	echo "OPTIONS:"
	echo "  -h, --help     Display this help message and exit"
	echo ""
	echo "DEVICE TREE FORMAT:"
	echo "  The script reads from /var/run/hw-management/config/devtree"
	echo "  Expected format: <device_name> <slave_address> <bus> <label_name>"
	echo "  Example: mp29816 0x66 5 voltmon1"
	echo ""
	echo "FIRMWARE FILES:"
	echo "  Script looks for firmware files in:"
	echo "  /var/run/hw-management/firmware/<hid>/"
	echo "  Naming convention: \${device_name}\${bus}_csv_file"
	echo ""
	echo "EXAMPLES:"
	echo "  $0 hid180"
	echo "  $0 -h"
	echo ""
	echo "EXIT CODES:"
	echo "  0  Success - All devices processed successfully"
	echo "  1  Error - Invalid input, device error, or validation failed"
	echo ""
	echo "AUTHOR:"
	echo "  NVIDIA CORPORATION & AFFILIATES"
}

# Validate HID format.
validate_hid()
{
	local hid="$1"
	if [[ ! "$hid" =~ ^hid[0-9]{3}$ ]]; then
		error_exit "Invalid HID format: $hid (expected hidXXX where XXX are 3 digits)"
	fi
}

# Check if firmware files exist for a device.
check_firmware_files()
{
	local device_name="$1"
	local bus="$2"
	local hid="$3"
	local firmware_dir="/var/run/hw-management/firmware/$hid"

	# Check if at least CSV file exists (required).
	local csv_file="${device_name}${bus}_csv_file"
	if [[ -f "$firmware_dir/$csv_file" ]]; then
		return 0
	fi

	return 1
}

# Parse device tree and find voltage regulator devices.
parse_devtree()
{
	local hid="$1"
	local devtree_file="/var/run/hw-management/config/devtree"
	local found_devices=()

	# Check if devtree file exists.
	if [[ ! -f "$devtree_file" ]]; then
		error_exit "Device tree file not found: $devtree_file"
	fi

	log_info "Parsing device tree file: $devtree_file"

	# Read devtree file line by line.
	while read -r line; do
		# Skip empty lines and comments.
		[[ -z "$line" ]] && continue
		[[ "$line" =~ ^[[:space:]]*# ]] && continue

		# Parse the line: <device_name> <slave_address> <bus> <label_name>
		read -r device_name slave_addr bus label_name <<< "$line"

		# Skip if we don't have all required fields.
		if [[ -z "$device_name" ]] || [[ -z "$slave_addr" ]] || [[ -z "$bus" ]]; then
			continue
		fi

		# Check if this device has firmware files.
		if check_firmware_files "$device_name" "$bus" "$hid"; then
			found_devices+=("${device_name}"$'\t'"${bus}")
			log_info "Found device with firmware: $device_name on bus $bus"
		fi
	done < "$devtree_file"

	printf '%s\n' "${found_devices[@]}"
}

# Run individual device update.
update_device()
{
	local device_name="$1"
	local bus="$2"
	local hid="$3"

	log_info "Updating device: $device_name on bus $bus"

	# Run the individual update script.
	if "$UPDATE_SCRIPT" "$bus" "$device_name" "$hid"; then
		log_info "Successfully updated device: $device_name on bus $bus"
		return 0
	else
		log_info "Failed to update device: $device_name on bus $bus"
		return 1
	fi
}

# Main execution.
main()
{
	# Check for help option.
	if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
		show_help
		exit 0
	fi

	# Check if individual update script exists.
	if [[ ! -f "$UPDATE_SCRIPT" ]]; then
		error_exit "Individual update script not found: $UPDATE_SCRIPT"
	fi

	# Check if we have the required parameter.
	if [[ $# -ne 1 ]]; then
		echo "Error: Invalid number of arguments"
		echo ""
		show_help
		exit 1
	fi

	local hid="$1"

	# Validate HID format.
	validate_hid "$hid"

	log_info "Starting bulk voltage regulator update for HID: $hid"

	# Parse device tree and find devices with firmware (one device<TAB>bus per line).
	local devices=()
	local device_info
	while IFS= read -r device_info; do
		[[ -n "$device_info" ]] && devices+=("$device_info")
	done < <(parse_devtree "$hid")

	if [[ ${#devices[@]} -eq 0 ]]; then
		log_info "No devices with firmware files found for HID: $hid"
		exit 0
	fi

	log_info "Found ${#devices[@]} device(s) with firmware files"

	# Process each device.
	local success_count=0
	local failure_count=0

	for device_info in "${devices[@]}"; do
		local device_name bus
		IFS=$'\t' read -r device_name bus <<< "$device_info"

		if update_device "$device_name" "$bus" "$hid"; then
			((success_count++))
		else
			((failure_count++))
		fi
	done

	# Report results.
	log_info "Bulk update completed:"
	log_info "  Successful updates: $success_count"
	log_info "  Failed updates: $failure_count"

	if [[ $failure_count -gt 0 ]]; then
		log_info "Some devices failed to update"
		exit 1
	else
		log_info "All devices updated successfully"
		exit 0
	fi
}

# Execute main function with all arguments.
main "$@"
