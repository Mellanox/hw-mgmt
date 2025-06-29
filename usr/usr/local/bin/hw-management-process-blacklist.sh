#!/bin/bash
################################################################################
# Copyright (c) 2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

__default_blacklist="
##################################################################################
# Copyright (c) 2018-2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
options at24 io_limit=32
options gpio_ich gpiobase=0
options i2c_i801 disable_features=0x10
blacklist i2c_ismt
blacklist ee1004
blacklist nvidia
blacklist nvidia_modeset
blacklist nvidia_drm
blacklist pcspkr
blacklist i2c_piix4
blacklist cfg80211
blacklist cdc_subset
blacklist delta_i2c_ismt"

# Get system SKU
SKU=$(cat /sys/devices/virtual/dmi/id/product_sku 2>/dev/null)
BLACKLIST_FILE="/etc/modprobe.d/hw-management.conf"

# Function to process blacklist.
process_blacklist()
{
	# Check if running as root
	if [ "$(id -u)" != "0" ]; then
		echo "This script must be run as root" 1>&2
		exit 1
	fi

	# Copy all common records to $BLACKLIST_FILE.
	echo "$__default_blacklist" > $BLACKLIST_FILE

	# Extend with system specific records.
	case $SKU in
	HI180)
		# Neither Designware nor ASF I2C controller drivers should be blackisted.
		# This gurantees that Designware driver is loaded by ACPI before platform driver.
		# Platform driver relies on the existence of i2c-1 bus created by Designware driver.
		# Designware is also guaranteed to be loaded before ASF.
		# ASF bus is used by MCTP, this loading order ensures that MCTP will use i2c bus 4.
		;;
	*)
		# Blacklist Designware and ASF I2C controller drivers
		echo blacklist i2c_designware_platform >> $BLACKLIST_FILE
		echo blacklist i2c_designware_core >> $BLACKLIST_FILE
		echo blacklist i2c_asf >> $BLACKLIST_FILE
		;;
	esac
}

# Process blacklist
process_blacklist

echo "Blacklist file generated at $BLACKLIST_FILE"
