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

source hw-management-helpers.sh

# Default configuration constants.
STORE_OFFSET=0x17
PAGE=0x00
CLEAR_FAULT=0x03
WRITE_PROTECT=0x10
WP_VAL=0x63
DPC_MODEL_ID=0xba
DPC_REVISION_ID=0xbb
DPC_MODEL_ID_PAGE=1
DPC_REVISION_ID_PAGE=1
MFR_CRC_NORMAL_CODE=0xab
MFR_CRC_MULTI_CONFIG=0xad
PAGE2_MAX_REG=0x1e

# Global variables.
CRC_READ[0]=0x0
CRC_READ[1]=0x0
CRC_EXP[0]=""
CRC_EXP[1]=""

# Error handling function.
error_exit()
{
	log_info "ERROR: $1"
	exit 1
}

# Help function.
show_help()
{
	echo "Usage: $0 <i2c_bus> <device_name> <hid> [csv_file] [crc_file] [config_file]"
	echo ""
	echo "Voltage Regulator Device Flashing Utility"
	echo ""
	echo "DESCRIPTION:"
	echo "  This script validates and flashes voltage regulator devices via I2C."
	echo "  It compares register values from CSV input with device registers"
	echo "  and updates mismatched values. Includes CRC validation and"
	echo "  revision checking for safe operation."
	echo ""
	echo "PARAMETERS:"
	echo "  i2c_bus        I2C bus number (e.g., 0, 1, 2) - MANDATORY"
	echo "  device_name    Device name (e.g., mp2888, mp2974, xdpe152, xdpe122) - MANDATORY"
	echo "  hid            Hardware ID (e.g., hid180) or 0 for manual files - MANDATORY"
	echo "  csv_file       CSV file containing register configuration data - OPTIONAL"
	echo "                 Format: device_addr,cmd_code,wr,p0_name,p0_byte,p0_val,..."
	echo "  crc_file       File containing expected CRC checksum values - OPTIONAL"
	echo "                 Format: line with third word as CRC value"
	echo "  config_file    Configuration file with device-specific constants - OPTIONAL"
	echo "                 If not provided, default values are used"
	echo ""
	echo "AUTO-DISCOVERY:"
	echo "  If csv_file, crc_file, or config_file are not provided and HID is not 0,"
	echo "  the script will automatically search for them in /var/run/hw-management/firmware/<hid>/"
	echo "  with the following naming convention:"
	echo "    \${device_name}\${i2c_bus}_csv_file"
	echo "    \${device_name}\${i2c_bus}_crc_file"
	echo "    \${device_name}\${i2c_bus}_config_file"
	echo "  When HID is 0, all files must be provided manually."
	echo ""
	echo "OPTIONS:"
	echo "  -h, --help     Display this help message and exit"
	echo ""
	echo "EXAMPLES:"
	echo "  $0 1 mp2888 hid180"
	echo "  $0 1 mp2888 hid180 config.csv"
	echo "  $0 1 mp2888 hid180 config.csv crc.txt"
	echo "  $0 1 mp2888 hid180 config.csv crc.txt device_config.conf"
	echo "  $0 1 mp2888 0 config.csv crc.txt device_config.conf"
	echo "  $0 -h"
	echo ""
	echo "CSV FILE FORMAT:"
	echo "  Header line followed by data lines with comma-separated values:"
	echo "  device_addr,cmd_code,wr,p0_name,p0_byte,p0_val,p1_name,p1_byte,p1_val,p2_name,p2_byte,p2_val"
	echo ""
	echo "CONFIG FILE FORMAT:"
	echo "  Shell script with variable assignments:"
	echo "  STORE_OFFSET=0x17"
	echo "  WP_VAL=0x63"
	echo "  DPC_MODEL_ID=0xba"
	echo "  # ... other constants"
	echo ""
	echo "EXIT CODES:"
	echo "  0  Success - Device flashed or no changes needed"
	echo "  1  Error - Invalid input, device error, or validation failed"
	echo ""
	echo "AUTHOR:"
	echo "  NVIDIA CORPORATION & AFFILIATES"
}

# Auto-discover files in firmware directory.
discover_files()
{
	local i2c_bus="$1"
	local device_name="$2"
	local hid="$3"
	local firmware_dir="/var/run/hw-management/firmware/$hid"

	# Auto-discover CSV file if not provided.
	if [[ -z "$CSV_FILE" ]]; then
		local csv_pattern="${device_name}${i2c_bus}_csv_file"
		if [[ -f "$firmware_dir/$csv_pattern" ]]; then
			CSV_FILE="$firmware_dir/$csv_pattern"
			log_info "Auto-discovered CSV file: $CSV_FILE"
		else
			error_exit "CSV file not provided and auto-discovery failed: $firmware_dir/$csv_pattern"
		fi
	fi

	# Auto-discover CRC file if not provided.
	if [[ -z "$CRC_FILE" ]]; then
		local crc_pattern="${device_name}${i2c_bus}_crc_file"
		if [[ -f "$firmware_dir/$crc_pattern" ]]; then
			CRC_FILE="$firmware_dir/$crc_pattern"
			log_info "Auto-discovered CRC file: $CRC_FILE"
		else
			error_exit "CRC file not provided and auto-discovery failed: $firmware_dir/$crc_pattern"
		fi
	fi

	# Auto-discover config file if not provided.
	if [[ -z "$CONFIG_FILE" ]]; then
		local config_pattern="${device_name}${i2c_bus}_config_file"
		if [[ -f "$firmware_dir/$config_pattern" ]]; then
			CONFIG_FILE="$firmware_dir/$config_pattern"
			log_info "Auto-discovered config file: $CONFIG_FILE"
		else
			log_info "Config file not provided and auto-discovery failed: $firmware_dir/$config_pattern"
			log_info "Using default configuration values"
		fi
	fi
}

# Load configuration file if provided.
load_config()
{
	local config_file="$1"
	if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
		log_info "Loading configuration from: $config_file"
		source "$config_file"
	else
		log_info "Using default configuration values"
	fi
}

# Input validation function.
validate_inputs()
{
	# Check for help option.
	if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
		show_help
		exit 0
	fi

	# Check minimum required parameters.
	if [[ $# -lt 3 ]]; then
		echo "Error: Missing required parameters"
		echo ""
		show_help
		exit 1
	fi

	# Check maximum parameters.
	if [[ $# -gt 6 ]]; then
		echo "Error: Too many parameters"
		echo ""
		show_help
		exit 1
	fi

	I2C_BUS="$1"
	DEVICE_NAME="$2"
	HID="$3"
	CSV_FILE="$4"
	CRC_FILE="$5"
	CONFIG_FILE="$6"

	# Validate I2C bus exists.
	if [[ ! -d "/sys/class/i2c-dev/i2c-$I2C_BUS" ]]; then
		error_exit "I2C bus not found: $I2C_BUS"
	fi

	# Validate device name format.
	if [[ ! "$DEVICE_NAME" =~ ^[a-zA-Z0-9]+$ ]]; then
		error_exit "Invalid device name format: $DEVICE_NAME"
	fi

	# Validate HID format (allow "0" for manual file specification).
	if [[ "$HID" != "0" ]] && [[ ! "$HID" =~ ^hid[0-9]{3}$ ]]; then
		error_exit "Invalid HID format: $HID (expected hidXXX where XXX are 3 digits, or 0 for manual files)"
	fi

	# Auto-discover missing files (skip if HID is "0").
	if [[ "$HID" != "0" ]]; then
		discover_files "$I2C_BUS" "$DEVICE_NAME" "$HID"
	fi

	# Validate input files exist.
	if [[ ! -f "$CSV_FILE" ]]; then
		error_exit "CSV file not found: $CSV_FILE"
	fi

	if [[ ! -f "$CRC_FILE" ]]; then
		error_exit "CRC file not found: $CRC_FILE"
	fi

	# Validate CSV file format (check if it has at least 2 lines).
	if [[ $(wc -l < "$CSV_FILE") -lt 2 ]]; then
		error_exit "CSV file appears to be empty or malformed"
	fi

	log_info "Input validation passed"
}

# Safe i2c command execution with error checking.
i2c_cmd()
{
	local cmd="$1"
	local expected_exit="$2"

	if [[ -z "$expected_exit" ]]; then
		expected_exit=0
	fi

	eval "$cmd"
	local exit_code=$?

	if [[ $exit_code -ne $expected_exit ]]; then
		log_info "Warning: i2c command failed: $cmd (exit code: $exit_code)"
		return $exit_code
	fi

	return 0
}

get_device_address()
{
	local dev_addr
	dev_addr=$(head -2 "$CSV_FILE" | tail -1 | cut -d ',' -f1)

	# Validate device address format.
	if [[ ! "$dev_addr" =~ ^0x[0-9a-fA-F]{2}$ ]]; then
		error_exit "Invalid device address format: $dev_addr"
	fi

	echo "$dev_addr"
}

store_user()
{
	log_info "Storing user settings..."

	# Remove write protect from page 0.
	i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$PAGE' 0x00" || return 1
	sleep 0.1
	i2c_cmd "i2cset -f -y '$I2C_BUS' '$dev_addr' '$WRITE_PROTECT' '$WP_VAL' bp" || return 1

	# Clear fault and store user from page 1.
	i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$PAGE' 0x01" || return 1
	sleep 1
	i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$CLEAR_FAULT' 0x00" || return 1
	i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$STORE_OFFSET'" || return 1
	sleep 0.1

	log_info "User settings stored successfully"
}

read_crc_from_device()
{
	log_info "Reading CRC from device..."

	# Read CRC from 0xAB (MFR_CRC_NORMAL_CODE) and 0xAD (MFR_CRC_MULTI_CONFIG) from page 1.
	i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$PAGE' 0x01" || return 1

	CRC_READ[0]=$(i2cget -y -f "$I2C_BUS" "$dev_addr" "$MFR_CRC_NORMAL_CODE" w 2>/dev/null)
	CRC_READ[1]=$(i2cget -y -f "$I2C_BUS" "$dev_addr" "$MFR_CRC_MULTI_CONFIG" w 2>/dev/null)

	log_info "CRC read - Normal: ${CRC_READ[0]}, Multi: ${CRC_READ[1]}"
}

get_model()
{
	i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$PAGE' '$DPC_MODEL_ID_PAGE'" || return 1
	i2cget -y -f "$I2C_BUS" "$dev_addr" "$DPC_MODEL_ID" w
}

get_revision()
{
	i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$PAGE' '$DPC_REVISION_ID_PAGE'" || return 1
	i2cget -y -f "$I2C_BUS" "$dev_addr" "$DPC_REVISION_ID" w
}

parse_crc_file()
{
	local file="$1"
	local i=0

	log_info "Parsing CRC file: $file"

	while read -r line; do
		# Skip empty lines.
		[[ -z "$line" ]] && continue

		# Extract the third word (CRC value).
		crc_val=$(echo "$line" | awk '{print $3}')

		if [[ -z "$crc_val" ]]; then
			log_info "Warning: Empty CRC value in line: $line"
			continue
		fi

		CRC_EXP[$i]="$crc_val"
		((i++))
	done < "$file"

	log_info "Parsed CRC values - Normal: ${CRC_EXP[0]}, Multi: ${CRC_EXP[1]}"
}

validate_revisions()
{
	log_info "Validating device revisions..."

	local model
	local revision

	model=$(get_model) || error_exit "Failed to get model"
	revision=$(get_revision) || error_exit "Failed to get revision"

	log_info "Device model: $model, revision: $revision"

	# Parse input file: skip header, process each line until revision field.
	tail -n +2 "$CSV_FILE" | while IFS=, read -r dev_addr cmd_code wr \
		p0_name p0_byte p0_val \
		p1_name p1_byte p1_val \
		p2_name p2_byte p2_val
	do
		for page in 0 1 2; do
			eval name=\$p${page}_name
			eval byte=\$p${page}_byte
			eval val=\$p${page}_val

			# Skip if no command name (empty page).
			if [[ -z "$name" ]]; then
				continue
			fi

			# Remove trailing symbols and convert to lowercase.
			val=$(echo "$val" | cut -c1-6 | tr '[:upper:]' '[:lower:]')
			cmd_code=$(echo "$cmd_code" | tr '[:upper:]' '[:lower:]')

			if [[ "$page" == "$DPC_REVISION_ID_PAGE" ]] && [[ "$cmd_code" == "$DPC_REVISION_ID" ]]; then
				# Compare expected and real values.
				if [[ "$revision" < "$val" ]]; then
					log_info "Input revision $revision is less than actual revision $val"
					return 1
				else
					log_info "Input revision $revision, actual revision $val - OK"
					return 0
				fi
			fi
		done
	done

	log_info "Revision validation completed"
}

validate_crc()
{
	log_info "Validating CRC values..."

	# Get CRC from input file.
	parse_crc_file "$CRC_FILE"

	# Normalize CRC values.
	CRC_EXP[0]=$(echo "0x${CRC_EXP[0]}" | tr '[:upper:]' '[:lower:]')
	CRC_EXP[1]=$(echo "0x${CRC_EXP[1]}" | tr '[:upper:]' '[:lower:]')

	# Remove carriage return.
	CRC_EXP[0]=${CRC_EXP[0]//$'\r'/}
	CRC_EXP[1]=${CRC_EXP[1]//$'\r'/}

	# Get CRC from device.
	store_user || error_exit "Failed to store user settings"
	read_crc_from_device || error_exit "Failed to read CRC from device"

	sleep 0.1

	local crc_names=("normal" "multi")
	local mismatch_found=false

	for i in 0 1; do
		if [[ "${CRC_EXP[$i]}" != "${CRC_READ[$i]}" ]]; then
			log_info "CRC mismatch - ${crc_names[$i]}: actual ${CRC_READ[$i]}, expected ${CRC_EXP[$i]}"
			mismatch_found=true
		else
			log_info "CRC match - ${crc_names[$i]}: ${CRC_READ[$i]}"
		fi
	done

	if [[ "$mismatch_found" == "true" ]]; then
		log_info "CRC validation failed"
		return 1
	else
		log_info "CRC validation passed"
		return 0
	fi
}

compare_and_flash_device()
{
	log_info "Starting device comparison and flashing..."

	local fix_count=0
	local temp_file=$(mktemp)

	# Skip header, process each line.
	tail -n +2 "$CSV_FILE" | while IFS=, read -r dev_addr cmd_code wr \
		p0_name p0_byte p0_val \
		p1_name p1_byte p1_val \
		p2_name p2_byte p2_val
	do
		for page in 0 1 2; do
			eval name=\$p${page}_name
			eval byte=\$p${page}_byte
			eval val=\$p${page}_val

			# Skip if no command name (empty page).
			if [[ -z "$name" ]]; then
				continue
			fi

			# Remove trailing symbols and convert to lowercase.
			val=$(echo "$val" | cut -c1-6 | tr '[:upper:]' '[:lower:]')

			# Set page.
			i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$PAGE' $page" || continue

			# Read value.
			local read_val
			if [[ "$byte" == 2 ]]; then
				read_val=$(i2cget -y -f "$I2C_BUS" "$dev_addr" "$cmd_code" w 2>/dev/null)
			else
				read_val=$(i2cget -y -f "$I2C_BUS" "$dev_addr" "$cmd_code" 2>/dev/null)
			fi

			# Compare values.
			if [[ "$read_val" != "$val" ]]; then
				# Skip certain registers.
				if [[ ("$cmd_code" > "$PAGE2_MAX_REG" && "$page" == 2) || ("$cmd_code" = 0x10) ]]; then
					continue
				fi

				log_info "Mismatch at bus $I2C_BUS $dev_addr $cmd_code page $page name $name: read $read_val, expected $val"

				# Set page and fix mismatch.
				i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$PAGE' $page" || continue

				local new_val
				if [[ "$byte" == 2 ]]; then
					i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$cmd_code' '$val' w" || continue
					new_val=$(i2cget -y -f "$I2C_BUS" "$dev_addr" "$cmd_code" w 2>/dev/null)
				else
					i2c_cmd "i2cset -y -f '$I2C_BUS' '$dev_addr' '$cmd_code' '$val'" || continue
					new_val=$(i2cget -y -f "$I2C_BUS" "$dev_addr" "$cmd_code" 2>/dev/null)
				fi

				if [[ "$new_val" != "$val" ]]; then
					log_info "Failed to fix at bus $I2C_BUS $dev_addr $cmd_code page $page name $name: read $new_val, expected $val"
				else
					echo "1" >> "$temp_file"
					log_info "Successfully fixed register $cmd_code on page $page"
				fi
			fi
		done
	done

	# Count fixes.
	fix_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
	rm -f "$temp_file"

	log_info "Device flashing completed. Fixed $fix_count registers"
	echo "$fix_count"
}

# Main execution.
main()
{
	log_info "Starting voltage regulator flash script for device: $DEVICE_NAME"

	# Validate inputs.
	validate_inputs "$@"

	# Load configuration.
	load_config "$CONFIG_FILE"

	# Get device address.
	dev_addr=$(get_device_address)
	log_info "Device address: $dev_addr"

	# Validate revisions.
	validate_revisions
	if [[ $? -eq 0 ]]; then
		log_info "Revision validation passed - update allowed"
	else
		log_info "Revision validation failed - exiting"
		exit 1
	fi

	# Validate CRC.
	validate_crc
	if [[ $? -eq 0 ]]; then
		log_info "CRC validation passed - no update needed"
		exit 0
	else
		log_info "CRC validation failed - proceeding with update"
	fi

	# Compare and flash device.
	fix_count=$(compare_and_flash_device)

	# Store to RAM if fixes were made.
	if [[ "$fix_count" -gt 0 ]]; then
		log_info "Storing changes to device..."
		store_user || error_exit "Failed to store changes"
		log_info "Successfully updated $fix_count registers"

		# Update counter of flashed voltage regulators.
		if [ ! -f "$config_path/vr_updated_counter" ]; then
			echo 1 > "$config_path/vr_updated_counter"
		else
			vr_counter=$(< $config_path/vr_updated_counter)
			vr_counter=$((vr_counter+1))
			echo "$vr_counter" > "$config_path/vr_updated_counter"
		fi
	else
		log_info "No changes needed"
	fi

	log_info "Script completed successfully"
}

# Execute main function with all arguments.
main "$@"
