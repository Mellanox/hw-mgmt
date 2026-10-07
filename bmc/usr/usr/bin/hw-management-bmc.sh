#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

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
