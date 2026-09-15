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

# Journal/syslog tag for log_err / log_info (basename of this script without .sh).
_HW_MANAGEMENT_BMC_SH_LOG_TAG=$(basename "${BASH_SOURCE[0]:-hw-management-bmc.sh}" .sh)

# Inherit system configuration.
source hw-management-bmc-helpers.sh
source hw-management-bmc-devtree.sh

device_connect_retry=2
device_connect_delay=0.2

log_err()
{
    logger -t "${_HW_MANAGEMENT_BMC_SH_LOG_TAG}" -p daemon.err "$@"
}

log_info()
{
    logger -t "${_HW_MANAGEMENT_BMC_SH_LOG_TAG}" -p daemon.info "$@"
}

connect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-"$3"/new_device ]; then
		addr=$(echo "$2" | tail -c +3)
		bus=$3
		if [ ! -d /sys/bus/i2c/devices/$bus-00"$addr" ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" "$2" > /sys/bus/i2c/devices/i2c-$bus/new_device
			sleep ${device_connect_delay}
			if [ ! -L /sys/bus/i2c/devices/$bus-00"$addr"/driver ] &&
			   [ ! -L /sys/bus/i2c/devices/$bus-000"$addr"/driver ]; then
				return 1
			fi
		fi
	fi

	return 0
}

disconnect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-"$2"/delete_device ]; then
		addr=$(echo "$1" | tail -c +3)
		bus=$2
		if [ -d /sys/bus/i2c/devices/$bus-00"$addr" ] ||
		   [ -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" > /sys/bus/i2c/devices/i2c-$bus/delete_device
			return $?
		fi
	fi

	return 0
}

connect_platform()
{
	# Check if it's new or old format of connect table
	if [ -e "$devtree_file" ]; then
		unset connect_table
		declare -a connect_table=($(<"$devtree_file"))
		# New connect table contains also device link name, e.g., fan_amb
		dev_step=4
	else
		dev_step=3
	fi

	for ((i=0; i<${#connect_table[@]}; i+=$dev_step)); do
		for ((j=0; j<${device_connect_retry}; j++)); do
			connect_device "${connect_table[i]}" "${connect_table[i+1]}" \
					"${connect_table[i+2]}"
			if [ $? -eq 0 ]; then
				break;
			fi
			disconnect_device "${connect_table[i+1]}" "${connect_table[i+2]}"
		done
	done
}

disconnect_platform()
{
	# Check if it's new or old format of connect table
	if [ -e "$devtree_file" ]; then
		dev_step=4
	else
		dev_step=3
	fi
	for ((i=0; i<${#connect_table[@]}; i+=$dev_step)); do
		disconnect_device "${connect_table[i+1]}" "${connect_table[i+2]}"
	done
}

connect_chassis()
(
	dev_step=3
	for ((i=0; i<${#connect_chassis_table[@]}; i+=$dev_step)); do
		for ((j=0; j<${device_connect_retry}; j++)); do
			connect_device "${connect_chassis_table[i]}" "${connect_chassis_table[i+1]}" \
					"${connect_chassis_table[i+2]}"
			if [ $? -eq 0 ]; then
				break;
			fi
			disconnect_device "${connect_chassis_table[i+1]}" "${connect_chassis_table[i+2]}"
		done
	done
)

disconnect_chassis()
{
	dev_step=3
	for ((i=0; i<${#connect_chassis_table[@]}; i+=$dev_step)); do
		disconnect_device "${connect_chassis_table[i+1]}" "${connect_chassis_table[i+2]}"
	done
}

# Platform-specific I2C connect tables were previously selected by devicetree model + VPD HID.
# Reserved for future ODM/SKU wiring; do_start does not rely on this today.
check_system()
{
	:
}

do_start()
{
	touch /var/run/hw-management/config/pn
	check_cpu_type
	devtr_check_smbios_device_description
	check_system
	udevadm trigger --action=add
	udevadm settle
	# connect_platform
	# connect_chassis

	log_info "Init completed."
}

do_stop()
{
	# disconnect_chassis
	# disconnect_platform
	log_info "do_stop."
}

ACTION=$1
case $ACTION in
	start)
		do_start
	;;
	stop)
		do_stop
	;;
	restart|force-reload)
		do_stop
		sleep 3
		do_start
	;;
	reset-cause)
		for f in $system_path/reset_*;
			do v=`cat $f`; attr=$(basename $f); if [ $v -eq 1 ]; then echo $attr; fi;
		done
	;;
	*)
		echo "$__usage"
		exit 1
	;;
esac
