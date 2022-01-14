#!/bin/bash
########################################################################
# Copyright (c) 2021, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

hw_management_path=/var/run/hw-management
environment_path=$hw_management_path/environment
alarm_path=$hw_management_path/alarm
eeprom_path=$hw_management_path/eeprom
led_path=$hw_management_path/led
system_path=$hw_management_path/system
sfp_path=$hw_management_path/sfp
watchdog_path=$hw_management_path/watchdog
config_path=$hw_management_path/config
events_path=$hw_management_path/events
thermal_path=$hw_management_path/thermal
jtag_path=$hw_management_path/jtag
power_path=$hw_management_path/power
fw_path=$hw_management_path/firmware
udev_ready=$hw_management_path/.udev_ready
LOCKFILE="/var/run/hw-management-chassis.lock"
board_type_file=/sys/devices/virtual/dmi/id/board_name
i2c_bus_def_off_eeprom_cpu_file=$config_path/i2c_bus_def_off_eeprom_cpu
i2c_comex_mon_bus_default_file=$config_path/i2c_comex_mon_bus_default

# Thermal type constants
thermal_type_t1=1
thermal_type_t2=2
thermal_type_t3=3
thermal_type_t4=4
thermal_type_t4=4
thermal_type_t5=5
thermal_type_t6=6
thermal_type_t7=7
thermal_type_t8=8
thermal_type_t9=9
thermal_type_t10=10
thermal_type_t11=11
thermal_type_t12=12
thermal_type_def=0
thermal_type_full=100

max_tachos=14
i2c_asic_bus_default=2
i2c_bus_max=26
lc_i2c_bus_min=34
lc_i2c_bus_max=43
i2c_bus_offset=0
cpu_type=

# CPU Family + CPU Model should idintify exact CPU architecture
# IVB - Ivy-Bridge; RNG - Atom Rangeley
# BDW - Broadwell-DE; CFL - Coffee Lake
# DNV - Denverton;
IVB_CPU=0x63A
RNG_CPU=0x64D
BDW_CPU=0x656
CFL_CPU=0x69E
DNV_CPU=0x65F

log_err()
{
    logger -t hw-management -p daemon.err "$@"
}

log_info()
{
    logger -t hw-management -p daemon.info "$@"
}

check_cpu_type()
{
    if [ ! -f $config_path/cpu_type ]; then
        family_num=$(grep -m1 "cpu family" /proc/cpuinfo | awk '{print $4}')
        model_num=$(grep -m1 model /proc/cpuinfo | awk '{print $3}')
        cpu_type=$(printf "0x%X%X" "$family_num" "$model_num")
        echo $cpu_type > $config_path/cpu_type
    else
        cpu_type=$(cat $config_path/cpu_type)
    fi  
}

find_i2c_bus()
{
    # Find physical bus number of Mellanox I2C controller. The default
    # number is 1, but it could be assigned to others id numbers on
    # systems with different CPU types.
    for ((i=1; i<i2c_bus_max; i++)); do
        folder=/sys/bus/i2c/devices/i2c-$i
        if [ -d $folder ]; then
            name=$(cut $folder/name -d' ' -f 1)
            if [ "$name" == "i2c-mlxcpld" ]; then
                i2c_bus_offset=$((i-1))
                return
            fi
        fi
    done

    log_err "I2C infrastructure is not created"
    exit 0
}

lock_service_state_change()
{
    exec {LOCKFD}>${LOCKFILE}
    /usr/bin/flock -x ${LOCKFD}
    trap "/usr/bin/flock -u ${LOCKFD}" EXIT SIGINT SIGQUIT SIGTERM
}

unlock_service_state_change()
{
    /usr/bin/flock -u ${LOCKFD}
}

# Check if file exists and create soft link
# $1 - file path
# $2 - link path
# return none
check_n_link()
{
    if [ -f "$1" ];
    then
        ln -sf "$1" "$2"
    fi
}

# Check if link exists and unlink it
# $1 - link path
# return none
check_n_unlink()
{
    if [ -L "$1" ];
    then
        unlink "$1"
    fi
}

# Read int val from file, inc it by val and save back
# value can negative
# $1 - counter file name
# $2 - value to add (can be < 0)
change_file_counter()
{
	file_name=$1
	val=$2
	[ -f "$file_name" ] && counter=$(< $file_name)
	counter=$((counter+val))
	if [ $counter -lt 0 ]; then
		counter=0
	fi
	echo $counter > $file_name
}

connect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-"$3"/new_device ]; then
		addr=$(echo "$2" | tail -c +3)
		bus=$(($3+i2c_bus_offset))
		if [ ! -d /sys/bus/i2c/devices/$bus-00"$addr" ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" "$2" > /sys/bus/i2c/devices/i2c-$bus/new_device
		fi
	fi

	return 0
}

disconnect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-"$2"/delete_device ]; then
		addr=$(echo "$1" | tail -c +3)
		bus=$(($2+i2c_bus_offset))
		if [ -d /sys/bus/i2c/devices/$bus-00"$addr" ] ||
		   [ -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" > /sys/bus/i2c/devices/i2c-$bus/delete_device
		fi
	fi

	return 0
}
