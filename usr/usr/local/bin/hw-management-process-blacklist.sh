#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

# Get system SKU
SKU=$(cat /sys/devices/virtual/dmi/id/product_sku 2>/dev/null)
BLACKLIST_FILE="/etc/modprobe.d/hw-management.conf"
MODULE_LOAD_FILE="/etc/modules-load.d/05-hw-management-modules.conf"

# Function to ensure a line exists in the file
ensure_line_exists()
{
	local line="$1"
	local file="$2"

	# Add line if it doesn't exist
	if ! grep -Fxq "$line" "$file" 2>/dev/null; then
		echo "$line" >> "$file"
	fi
}

# Function to ensure a line does not exist in the file
ensure_line_removed()
{
	local line="$1"
	local file="$2"

	# Remove line if it exists
	if grep -Fxq "$line" "$file" 2>/dev/null; then
		sed -i "\|^${line}$|d" "$file"
	fi
}

# Function to add module at the beginning of modules file (after header lines)
add_module_at_beginning()
{
	local module="$1"
	local file="$2"

	# Add after header lines only if not already listed
	if ! grep -q "$module" "$file" 2>/dev/null; then
		if [ -f "$file" ] && grep -q "^#" "$file"; then
			# Find the last header line (starting with #) and insert after it
			last_header_line=$(grep -n "^#" "$file" | tail -1 | cut -d: -f1)
			sed -i "${last_header_line}a $module" "$file"
		elif [ -f "$file" ]; then
			# No header exists, insert at the beginning
			sed -i "1i $module" "$file"
		else
			# File doesn't exist, create it
			echo "$module" > "$file"
		fi
	fi
}

# Function to process blacklist.
process_blacklist()
{
	# Process system specific records.
	case $SKU in
	HI180|HI181|HI182|HI183|HI185|HI187|HI188|HI193)
		# Prevent various i2c bus drivers from loading before Designware driver
		# to guarantee the correct i2c bus numbering order
		ensure_line_exists "blacklist i2c_asf" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist i2c-diolan-u2c" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist i2c_piix4" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist i2c_i801" "$BLACKLIST_FILE"

		# Ensure Designware is NOT blacklisted for these SKUs
		ensure_line_removed "blacklist i2c_designware_platform" "$BLACKLIST_FILE"
		ensure_line_removed "blacklist i2c_designware_core" "$BLACKLIST_FILE"

		# Ensure Designware I2C driver is loaded early
		add_module_at_beginning "i2c_designware_platform" "$MODULE_LOAD_FILE"
		;;
	HI176)
		# Blacklist Designware, ASF I2C controller drivers and ipmi
		ensure_line_exists "blacklist i2c_designware_platform" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist i2c_designware_core" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist i2c_asf" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist ipmi_si" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist ipmi_ssif" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist ipmi_devintf" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist ipmi_msghandler" "$BLACKLIST_FILE"
		;;
	*)
		# Blacklist Designware and ASF I2C controller drivers
		ensure_line_exists "blacklist i2c_designware_platform" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist i2c_designware_core" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist i2c_asf" "$BLACKLIST_FILE"
		ensure_line_exists "blacklist mlxreg_dpu" "$BLACKLIST_FILE"
		;;
	esac
}

# Process blacklist
process_blacklist

echo "Blacklist file updated at $BLACKLIST_FILE"
