#!/bin/bash

################################################################################
# Copyright (c) 2025-2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

################################################################################
# This script perofrms file system related platform specific changes
# It must run after local filesystems are available and before all normal services
# are started.
# Note: logger serivce may not be available.
################################################################################

PLAT_SPECIFIC_PATH=/etc/plat_specific/

sku=""

get_hwid() {
    sku=`find /proc/device-tree/ -name "nvsw*" | xargs basename |  grep -oE 'hid[0-9]+'`
    echo "bmc platform specific settings, sku: $sku"
}

# Map device-tree SKU (hidNNN) to packaged platform ID directory (HINNN) under /usr/etc/.
# Package installs e.g. usr/etc/HI193/; at boot we mirror JSON and configs to /etc, scripts to /usr/bin.
deploy_hw_management_bmc_platform_files()
{
	[ -n "$sku" ] || return 0
	case "$sku" in
	hid[0-9]*) ;;
	*) return 0 ;;
	esac
	local HID HID_SRC
	HID=$(echo "$sku" | sed 's/^hid/HI/')
	HID_SRC="/usr/etc/${HID}"
	if [ ! -d "$HID_SRC" ]; then
		echo "plat-specific: no packaged platform dir $HID_SRC (sku=$sku), skip deploy"
		return 0
	fi
	echo "plat-specific: deploying from $HID_SRC to /etc, /etc/modprobe.d, /usr/bin, /lib/udev/rules.d"
	shopt -s nullglob
	for f in "$HID_SRC"/*.json; do
		cp -f "$f" /etc/
	done
	shopt -u nullglob
	[ -f "$HID_SRC/hw-management-platform.conf" ] && \
		cp -f "$HID_SRC/hw-management-platform.conf" /etc/
	if [ -f "$HID_SRC/hw-management-bmc.conf" ]; then
		mkdir -p /etc/modprobe.d
		cp -f "$HID_SRC/hw-management-bmc.conf" /etc/modprobe.d/hw-management-bmc.conf
		chmod 0644 /etc/modprobe.d/hw-management-bmc.conf
	fi
	shopt -s nullglob
	for f in "$HID_SRC"/*.sh; do
		base=$(basename "$f")
		cp -f "$f" "/usr/bin/$base"
		chmod +x "/usr/bin/$base"
	done
	shopt -u nullglob
	mkdir -p /lib/udev/rules.d
	shopt -s nullglob
	for f in "$HID_SRC"/*.rules; do
		base=$(basename "$f")
		cp -f "$f" "/lib/udev/rules.d/$base"
		chmod 0644 "/lib/udev/rules.d/$base"
	done
	shopt -u nullglob
}

plat_specific(){

	deploy_hw_management_bmc_platform_files

	case $sku in
	hid180|hid187|hid188|hid189|hid190|hid191|hid192)
		mkdir -p /tmp/plat_specific/

		# Update FRU manager I2C blacklist file
		cp ${PLAT_SPECIFIC_PATH}/blacklist_hi189.json /tmp/plat_specific/blacklist.json

		# Update Entity Manager json files

		# Sysfs can't be accessed since platform driver has not been loaded at this point.
		# Retrieve the value of SWITCH_IC_QTY CPLD register directly via I2C
		# TODO: use entity manager probe to detect ASICs dynamically once i2c/i3c communication is supported.
		asic_num=`i2ctransfer -f -y 5 w2@0x31 0x25 0xC1 r1`
		if [ $asic_num == "0x04" ]; then
			cp ${PLAT_SPECIFIC_PATH}/spc6_eth_spc_chassis_4asic.json /tmp/plat_specific/spc6_eth_spc_chassis.json
			cp ${PLAT_SPECIFIC_PATH}/spc6_mctp_bmc_target_configuration_4asic.json /tmp/plat_specific/spc6_mctp_bmc_target_configuration.json
			cp ${PLAT_SPECIFIC_PATH}/spc6_static_inventory_4asic.json /tmp/plat_specific/spc6_static_inventory.json
			cp ${PLAT_SPECIFIC_PATH}/spc6_eth_chassis_4asic.json /tmp/plat_specific/spc6_eth_chassis.json
			cp ${PLAT_SPECIFIC_PATH}/fw_update_config_4asic.json /tmp/plat_specific/fw_update_config.json
		else
			cp ${PLAT_SPECIFIC_PATH}/spc6_eth_spc_chassis_1asic.json /tmp/plat_specific/spc6_eth_spc_chassis.json
			cp ${PLAT_SPECIFIC_PATH}/spc6_mctp_bmc_target_configuration_1asic.json /tmp/plat_specific/spc6_mctp_bmc_target_configuration.json
			cp ${PLAT_SPECIFIC_PATH}/spc6_static_inventory_1asic.json /tmp/plat_specific/spc6_static_inventory.json
			cp ${PLAT_SPECIFIC_PATH}/spc6_eth_chassis_1asic.json /tmp/plat_specific/spc6_eth_chassis.json
			cp ${PLAT_SPECIFIC_PATH}/fw_update_config_1asic.json /tmp/plat_specific/fw_update_config.json
		fi

		;;
	*)
		echo "No platform specific actions defined for sku $sku"
		;;
	esac

}

get_hwid
plat_specific

