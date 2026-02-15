#!/bin/bash
################################################################################
# Copyright (c) 2024 - 2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Source common helper functions
source hw-management-helpers-common.sh

# CPU Family + CPU Model should idintify exact CPU architecture
# IVB - Ivy-Bridge
# RNG - Atom Rangeley
# BDW - Broadwell-DE
# CFL - Coffee Lake
# DNV - Denverton
# BF3 - BlueField-3
# AMD_SNW - AMD Snow Owl - EPYC Embedded 3000
# TODO: Add AMD V3000 and FireRange

# ARMv7 - Aspeed 2600
# ARM v8 - Aspeed AST2700/AST2720/AST2750 is based on Arm v8 Cortex-A35

IVB_CPU=0x63A
RNG_CPU=0x64D
BDW_CPU=0x656
CFL_CPU=0x69E
DNV_CPU=0x65F
BF3_CPU=0xD42
AMD_SNW_CPU=0x171
ARMv7_CPU=0xC07
ARMv8_CPU=0xd04

BMC_TO_CPU_CTRL=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*/bmc_to_cpu_ctrl
BMC_CPU_PWR_ON=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*/pwr_down
BMC_TO_CPU_UART=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*/uart_sel
AUX_PWR_CYCLE=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*/aux_pwr_cycle
BMC_CPU_PWR_ON_BUT=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*/pwr_button_halt
ASIC_CONFIG=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*/config1

hw_management_path=/var/run/hw-management
config_path=$hw_management_path/config
system_path=$hw_management_path/system
reset_bypass_file="/var/reset_bypass"
grace_reset_bypass_file="/var/grace_reset_bypass"
if [ -d /sys/devices/virtual/dmi/id ]; then
	board_type_file=/sys/devices/virtual/dmi/id/board_name
	sku_file=/sys/devices/virtual/dmi/id/product_sku
	system_ver_file=/sys/devices/virtual/dmi/id/product_version
else
	board_type_file=/var/run/hw-management/config/pn
	sku_file=/var/run/hw-management/config/hid
	system_ver_file=/var/run/hw-management/config/bom
fi

devtree_file=$config_path/devtree
if [ -d $sku_file ]; then
	sku=$(< $sku_file)
fi

check_cpu_type()
{
	if [ ! -f $config_path/cpu_type ]; then
		# ARM CPU provide "CPU part" field, x86 does not. Check for ARM first.
		cpu_pn=$(grep -m1 "CPU part" /proc/cpuinfo | awk '{print $4}')
		cpu_pn=`echo $cpu_pn | cut -c 3- | tr a-z A-Z`
		cpu_pn=0x$cpu_pn
		if [ "$cpu_pn" == "$BF3_CPU" ] || [ "$cpu_pn" == "$ARMv7_CPU" ]; then
			cpu_type=$cpu_pn
			echo $cpu_type > $config_path/cpu_type
			return 0
		fi

		family_num=$(grep -m1 "cpu family" /proc/cpuinfo | awk '{print $4}')
		model_num=$(grep -m1 model /proc/cpuinfo | awk '{print $3}')
		cpu_type=$(printf "0x%X%X" "$family_num" "$model_num")
		echo $cpu_type > $config_path/cpu_type
	else
		cpu_type=$(cat $config_path/cpu_type)
	fi
}

# Check if file exists and create soft link
# $1 - file path
# $2 - link path
# return none
check_n_link()
{
	if [ -f "$1" ]; then
		ln -sf "$1" "$2"
	fi
}

# Check if link exists and unlink it
# $1 - link path
# return none
check_n_unlink()
{
	if [ -L "$1" ]; then
		unlink "$1"
	fi
}

set_host_powerstate_off()
{
    /usr/bin/hw-management-dbus-if.sh host_state_off 2>/dev/null || true
}

set_host_powerstate_on()
{
    /usr/bin/hw-management-dbus-if.sh host_state_on 2>/dev/null || true
}

set_requested_host_transition_on()
{
    /usr/bin/hw-management-dbus-if.sh requested_host_transition_on 2>/dev/null || true
}

set_requested_host_transition_off()
{
    /usr/bin/hw-management-dbus-if.sh requested_host_transition_off 2>/dev/null || true
}

get_power_restore_delay()
{
    /usr/bin/hw-management-dbus-if.sh power_restore_delay 2>/dev/null || echo "0"
}

check_power_restore_policy()
{
	local pwr_policy
	local busctl_output
	# Check what is the power restore policy
	#
	# AlwaysOff: CPU should not be started by default
	# AlwaysOn:  CPU should be started by default
	# Restore:   Previous state of the CPU
	busctl_output=$(/usr/bin/hw-management-dbus-if.sh power_restore_policy 2>/dev/null | sed 's/^"//; s/"$//')
	pwr_policy="${busctl_output##*.}"

	power_delay=$(get_power_restore_delay)

	case "$pwr_policy" in
		AlwaysOff)
			# In case we are booted following PowerCycleBypass
			# We should skip the power policy
			if [ -f "$reset_bypass_file" ]; then
				rm -f "$reset_bypass_file"
				touch "$grace_reset_bypass_file"
				echo "Skipping AlwaysOff Power Policy Following PowerCycleBypass" | systemd-cat -p info
				echo "1"
			else
				echo "0"
			fi
			;;
		AlwaysOn)
			if [ "$power_delay" == "0" ]; then
				echo "No power_delay configured. Starting host cpu" | systemd-cat -p info
				echo "1"
			else
				echo "power_delay: $power_delay configured. Not starting host cpu" | systemd-cat -p info
				echo "0"
			fi
			;;
		Restore)
			echo "2"
			;;
		*)
			echo "3"
			;;
	esac
}

check_asic_config()
{
	local asic_cfg
	local ret=0

	# In the config1 cpld register, BIT(7) will be set to 1
	# if it's a single asic configuration. 0 if it's a four
	# asic configuration.
	asic_cfg=$(< $ASIC_CONFIG)
	if (( asic_cfg & 0x80 )); then
		ret=1
	fi

	echo "$ret"
}
