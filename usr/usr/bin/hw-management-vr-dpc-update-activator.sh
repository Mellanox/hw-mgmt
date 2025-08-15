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

# Script directory for finding the bulk update script.
BULK_UPDATE_SCRIPT="/usr/bin/hw-management-vr-dpc-bulk-update.sh"

# Source hw-management helpers to get system information.
HW_MANAGEMENT_HELPERS="/usr/bin/hw-management-helpers.sh"
if [[ ! -f "$HW_MANAGEMENT_HELPERS" ]]; then
	echo "ERROR: hw-management-helpers.sh not found: $HW_MANAGEMENT_HELPERS"
	exit 1
fi

# Source the helpers script to get $sku_file variable.
source "$HW_MANAGEMENT_HELPERS"

# Error handling function.
error_exit()
{
	log_info "ERROR: $1"
	exit 1
}

# Help function.
show_help()
{
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Voltage Regulator Update Activator"
	echo ""
	echo "DESCRIPTION:"
	echo "  This script activates voltage regulator updates for all devices"
	echo "  discovered on the system. It sources hw-management-helpers.sh to"
	echo "  get the system SKU information and automatically runs bulk updates"
	echo "  for all voltage regulator devices with available firmware files."
	echo ""
	echo "OPTIONS:"
	echo "  -h, --help     Display this help message and exit"
	echo "  --dry-run      Show what would be updated without actually updating"
	echo ""
	echo "INTEGRATION:"
	echo "  This script is designed to be called from hw-management service"
	echo "  and automatically discovers the system hardware ID from helpers."
	echo ""
	echo "EXAMPLES:"
	echo "  $0"
	echo "  $0 --dry-run"
	echo "  $0 -h"
	echo ""
	echo "EXIT CODES:"
	echo "  0  Success - All devices processed successfully or no updates needed"
	echo "  1  Error - Invalid input, device error, or validation failed"
	echo ""
	echo "AUTHOR:"
	echo "  NVIDIA CORPORATION & AFFILIATES"
}

# Check if bulk update script exists.
check_scripts()
{
	if [[ ! -f "$BULK_UPDATE_SCRIPT" ]]; then
		error_exit "Bulk update script not found: $BULK_UPDATE_SCRIPT"
	fi
}

# Validate SKU file variable.
validate_sku()
{
	if [[ -z "$sku_file" ]]; then
		error_exit "SKU file variable not set from hw-management-helpers.sh"
	fi

	# Extract HID from SKU file (assuming format like "hid180").
	if [[ ! "$sku_file" =~ ^hid[0-9]{3}$ ]]; then
		error_exit "Invalid SKU file format: $sku_file (expected hidXXX where XXX are 3 digits)"
	fi

	log_info "Detected system HID: $sku_file"
}

# Run bulk update.
run_bulk_update()
{
	local hid="$1"
	local dry_run="$2"

	if [[ "$dry_run" == "true" ]]; then
		log_info "DRY RUN: Would run bulk update for HID: $hid"
		log_info "DRY RUN: Command: $BULK_UPDATE_SCRIPT $hid"
		return 0
	else
		log_info "Running bulk update for HID: $hid"
		"$BULK_UPDATE_SCRIPT" "$hid"
		return $?
	fi
}

# Main execution.
main()
{
	local dry_run=false

	# Parse command line options.
	while [[ $# -gt 0 ]]; do
		case $1 in
			-h|--help)
				show_help
				exit 0
				;;
			--dry-run)
				dry_run=true
				shift
				;;
			*)
				echo "Error: Unknown option: $1"
				echo ""
				show_help
				exit 1
				;;
		esac
	done

	log_info "Starting voltage regulator update activator"

	# Check if required scripts exist.
	check_scripts

	# Validate SKU file variable from helpers.
	validate_sku

	# Run bulk update with detected HID.
	if run_bulk_update "$sku_file" "$dry_run"; then
		log_info "Voltage regulator update activator completed successfully"
		exit 0
	else
		log_info "Voltage regulator update activator completed with errors"
		exit 1
	fi
}

# Execute main function with all arguments.
main "$@"
