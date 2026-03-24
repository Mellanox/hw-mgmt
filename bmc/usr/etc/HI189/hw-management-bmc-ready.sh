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

# Syslog tag for log_message() from hw-management-bmc-helpers-common.sh
LOG_TAG="hw-management-bmc-ready"

# Inherit common BMC routines
source /usr/bin/hw-management-bmc-ready-common.sh

# Inherit functions for setting extra boot args and params
source /usr/bin/hw-management-bmc-set-extra-params.sh

# OpenBMC hw-management-helpers-common: log_event, log_cpld_dump, bmc_init_eth, get_mgmt_board_revision, …
source /usr/bin/hw-management-bmc-helpers-common.sh

# Inherit system configuration (also sources helpers-common; idempotent).
source /usr/bin/hw-management-bmc-helpers.sh


# Inhert gpio functions
source /usr/bin/hw-management-bmc-gpio-set.sh

# BMC_STBY_READY is set dynamically in bmc_init_sysfs_gpio()
# BMC VPD EEPROM: defaults in hw-management-bmc-ready-common.sh; optional override via
# /etc/hw-management-bmc-eeprom.conf (from usr/etc/<HID>/hw-management-bmc-eeprom.conf).

# wait_platform_drv, get_cpu_type, get_system_hw_id, get_system_hw_bom — hw-management-bmc-ready-common.sh
# set_chassis_powerstate_on, bmc_to_cpu_tmp, bmc_to_cpu, run_hook — hw-management-bmc-ready-common.sh
# bmc_init_sysfs_gpio() is defined in hw-management-bmc-gpio-set.sh (JSON: /etc/hw-management-bmc-gpio-pins.json).

#######################################
# Execute required steps before asserting BMC_READY signal
#
# ARGUMENTS:
#   None
# RETURN:
#   None
# EXIT:
#   0 BMC_READY has been asserted
#   1 BMC_READY not asserted, due to failure in ready sequence
bmc_ready_sequence()
{
	wait_bmc_standby_ready 10 1

	# Obtain CPU type.
	get_cpu_type
	# Obtain system hardware Id from system EEPROM.
	# NOTE: 24c512 0x51 is now created by hw-management-bmc-early-i2c-init.service
	get_system_hw_id
	# Obtain system hardware BOM record.
	get_system_hw_bom

	# NOTE: I2C devices are now created by hw-management-bmc-early-i2c-init.service

	# Configure A2D devices.
	hw-management-bmc-a2d-leakage-config.sh

	check_rw_filesystems
	rc=$?
	if [[ $rc -ne 0 ]]; then
		if [ "$cpu_start_policy" == "1" ]; then
			bmc_to_cpu_tmp
		fi
		echo "[ERROR] Filesystem mount check failure"
		run_hook post
		exit 1
	fi

	check_rofs
	rc=$?
	if [[ $rc -ne 0 ]]; then
		if [ "$cpu_start_policy" == "1" ]; then
			bmc_to_cpu_tmp
		fi
		echo "[ERROR] BMC booted in ROFS, Read-Only mode"
		run_hook post
		exit 1
	fi

	# Assert BMC READY - review the below function.
	#set_bmc_ready $HIGH
	logger -t bmc_ready -p daemon.notice "bmc_ready.sh completed"
	return 0
}

bmc_init_main()
(
	# Note: in case run_hook pre contains code for u-boot command line or boot arguments
	#       modification - it should call the following sequence:
	#         source /usr/bin/hw-management-bmc-set-extra-params.sh
	#         if set_extrabootargs_and_bootcmdline()
	#             reboot_bmc()
	#         fi
	# Example 1: Set both command line and boot arguments
	# if set_extrabootargs_and_bootcmdline \
	#     "i2c dev 4; i2c probe 0x51; i2c md 0x51 0x00.2 0x100" \
	#     "blacklist=mp2995"; then
	#     echo "Boot parameters changed, rebooting..."
	#     reboot_bmc
	# else
	#     echo "No reboot needed, boot parameters already correct"
	# fi
	# Example 2: Set only command line
	# set_extrabootargs_and_bootcmdline \
	#    "i2c dev 4; i2c probe 0x51" \
	#    ""
	# Example 3: Set only boot arguments
	# set_extrabootargs_and_bootcmdline \
	#    "" \
	#    "blacklist=mp2995 debug"
	# Example 4: Clear everything
	# clear_extrabootargs_and_bootcmdline
	# Example 5: Show current configuration
	# show_boot_config

	run_hook pre

	bmc_init_sysfs_gpio
	bmc_init_eth

	bmc_init_bootargs

	# Save CPU power state.
	CPU_OFF_CMD=$(< $BMC_CPU_PWR_ON)
	CPU_OFF_BUT=$(< $BMC_CPU_PWR_ON_BUT)
	CPU_OFF=$((CPU_OFF_CMD|CPU_OFF_BUT))

	if [ "${CPU_OFF}" = "1" ]; then
		echo 1 > $BMC_TO_CPU_CTRL
	fi

	cpu_start_policy=$(check_power_restore_policy)

	bmc_ready_sequence
	rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "[ERROR] BMC init flow failure"
	fi
	
	create_nosbmc_user
	if [ "$cpu_start_policy" == "1" ]; then
		bmc_to_cpu

		# Temporary: connect mux devices only if CPU initially was powered off.
		# Otherwise - assumption this is BMC only reboot flow and mux devices
		# initialization is skipped to avoid conflicts with CPU telemetry.
		if [ "${CPU_OFF}" = "1" ]; then
			hw-management-bmc.sh start
		fi

		# Temporary: Set CPU as a master of I2C tree and signal control.
		sleep 5
		echo 0 > $BMC_TO_CPU_CTRL
	else
		hw-management-bmc.sh start
	fi

	# Enable write protect.
	# echo "Enabling write protect."

	echo "Disabling write protect for bringup."
	sleep 1
	echo 1 > /run/hw-management/system/GP_BMC_WP_CTRL_GPIO_L

	run_hook post

)

## Main
if [ ! -d "$config_path" ]; then
	mkdir -p "$config_path"
	bmc_init_main
else
	echo "BMC is up and running - skip init sequence."
fi
