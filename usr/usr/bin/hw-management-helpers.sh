#!/bin/bash
##################################################################################
# Copyright (c) 2021 - 2023, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
bin_path=$hw_management_path/bin
udev_ready=$hw_management_path/.udev_ready
LOCKFILE="/var/run/hw-management-chassis.lock"
board_type_file=/sys/devices/virtual/dmi/id/board_name
sku_file=/sys/devices/virtual/dmi/id/product_sku
system_ver_file=/sys/devices/virtual/dmi/id/product_version
devtree_file=$config_path/devtree
i2c_bus_def_off_eeprom_cpu_file=$config_path/i2c_bus_def_off_eeprom_cpu
i2c_comex_mon_bus_default_file=$config_path/i2c_comex_mon_bus_default
l1_switch_health_events=("intrusion" "pwm_pg" "thermal1_pdb" "thermal2_pdb")
ui_tree_sku=`cat $sku_file`
ui_tree_archive="/etc/hw-management-sensors/ui_tree_$ui_tree_sku.tar.gz"
vm_sku=`cat $sku_file`
vm_vpd_path="/etc/hw-management-virtual/$vm_sku"

declare -A psu_fan_pn=(["00KX1W"]=R ["00MP582"]=F ["00MP592"]=R ["00WT061"]=F ["00WT062"]=R ["00WT199"]=F ["01FT674"]=F ["01FT691"]=F ["01LL976"]=F ["01PG798"]=F \
["01PG800"]=F ["02YF120"]=R ["02YF121"]=R ["03GX980"]=F ["03GX981"]=F ["03KH192"]=R ["03KH193"]=F ["03KH194"]=R ["03KH195"]=F ["03LE223"]=R \
["03LE224"]=F ["071-000-203-01"]=R ["071-000-588"]=F ["07XY0Y"]=F ["08WP7W"]=F ["0YX5GR"]=F ["105-575-071-00"]=R ["105-575-072-00"]=F \
["105-575-074-00"]=F ["304643"]=F ["322285"]=R ["326013"]=R ["326146"]=R ["326329"]=R ["675170-001"]=R ["675171-001"]=F ["841985-001"]=R \
["841986-001"]=F ["90Y3770"]=R ["90Y3780"]=F ["90Y3800"]=R ["90Y3802"]=F ["930-9SPSU-00RA-00A"]=R ["930-9SPSU-00RA-00B"]=R ["9802A00E"]=R \
["98Y6356"]=R ["98Y6357"]=F ["MGA100-PS"]=F ["MSX60-PF"]=F ["MSX60-PR"]=F ["MTDF-PS-A"]=R ["MTDF-PS-B"]=F ["MTEF-PSF-AC-A"]=F ["MTEF-PSF-AC-B"]=F \
["MTEF-PSF-AC-C"]=F ["MTEF-PSF-AC-E"]=F ["MTEF-PSF-AC-F"]=F ["MTEF-PSF-AC-G"]=F ["MTEF-PSF-AC-I"]=F ["MTEF-PSF-AC-K"]=F ["MTEF-PSF-AC-L"]=F \
["MTEF-PSF-AC-M"]=F ["MTEF-PSF-DC-A"]=F ["MTEF-PSF-DC-B"]=F ["MTEF-PSF-DC-C"]=F ["MTEF-PSF-DC-L"]=F ["MTEF-PSR-AC-A"]=F ["MTEF-PSR-AC-C"]=R \
["MTEF-PSR-AC-E"]=R ["MTEF-PSR-AC-F"]=R ["MTEF-PSR-AC-G"]=R ["MTEF-PSR-AC-I"]=R ["MTEF-PSR-AC-K"]=R ["MTEF-PSR-AC-L"]=R ["MTEF-PSR-AC-M"]=R \
["MTEF-PSR-DC-B"]=R ["MTEF-PSR-DC-C"]=R ["MTEF-PSR-DC-D"]=R ["MUA90-PF"]=R ["MUA96-PF"]=F ["P10613-001"]=R ["PSU-AC-150-B"]=F ["PSU-AC-150-F"]=F \
["PSU-AC-150W-B"]=R ["PSU-AC-150W-F"]=F ["PSU-AC-400-B"]=R ["PSU-AC-400-F"]=F ["PSU-AC-650A-B"]=R ["PSU-AC-650A-F"]=F ["PSU-AC-850A-B"]=R \
["PSU-AC-850A-F"]=F ["PSU-AC-920-F"]=R ["PSU-AC-920W-F"]=R ["YM-1151D-A02R"]=R ["YM-1151D-A03R"]=F ["YM-1921A-A01R"]=R ["SP57B0808724"]=R)

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
thermal_type_t13=13
thermal_type_t14=14
thermal_type_def=0
thermal_type_full=100

base_cpu_bus_offset=10
max_tachos=14
i2c_asic_bus_default=2
i2c_asic2_bus_default=3
i2c_bus_max=26
lc_i2c_bus_min=34
lc_i2c_bus_max=43
i2c_bus_offset=0
cpu_type=

# CPU Family + CPU Model should idintify exact CPU architecture
# IVB - Ivy-Bridge
# RNG - Atom Rangeley
# BDW - Broadwell-DE
# CFL - Coffee Lake
# DNV - Denverton
# BF3 - BlueField-3
IVB_CPU=0x63A
RNG_CPU=0x64D
BDW_CPU=0x656
CFL_CPU=0x69E
DNV_CPU=0x65F
BF3_CPU=0xD42

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
		# ARM CPU provide "CPU part" field, x86 does not. Check for ARM first.
		cpu_pn=$(grep -m1 "CPU part" /proc/cpuinfo | awk '{print $4}')
		cpu_pn=`echo $cpu_pn | cut -c 3- | tr a-z A-Z`
		cpu_pn=0x$cpu_pn
		if [ "$cpu_pn" == "$BF3_CPU" ]; then
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

find_i2c_bus()
{
    # Find physical bus number of Mellanox I2C controller. The default
    # number is 1, but it could be assigned to others id numbers on
    # systems with different CPU types.
    if [ -f $config_path/i2c_bus_offset ]; then
        i2c_bus_offset=$(< $config_path/i2c_bus_offset)
        return
    fi
    for ((i=1; i<i2c_bus_max; i++)); do
        folder=/sys/bus/i2c/devices/i2c-$i
        if [ -d $folder ]; then
            name=$(cut $folder/name -d' ' -f 1)
            if [ "$name" == "i2c-mlxcpld" ]; then
                i2c_bus_offset=$((i-1))
		case $sku in
		HI151|HI156)
			i2c_bus_offset=$((i2c_bus_offset-1))
			;;
		default)
			;;
		esac

                echo $i2c_bus_offset > $config_path/i2c_bus_offset
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

check_labels_enabled()
{
    if ([ "$ui_tree_sku" = "HI130" ] ||
        [ "$ui_tree_sku" = "HI151" ] ||
        [ "$ui_tree_sku" = "HI157" ] ||
        [ "$ui_tree_sku" = "HI158" ]) &&
        ([ ! -e "$ui_tree_archive" ]); then
        return 0
    else
        return 1
    fi
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
        if  check_labels_enabled; then
            hw-management-labels-maker.sh "$2" "link" > /dev/null 2>&1 &
        fi
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
        if check_labels_enabled; then
	    hw-management-labels-maker.sh "$1" "unlink" > /dev/null 2>&1 &
        fi
    fi
}

# Check if file not exists and create it
# $1 - file path
# $2 - default value
# return none
check_n_init()
{
	if [ ! -f $1 ]; then
		echo $2 > $1
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

# Update counter, match attribute, unlock.
# $1 - file with counter
# $2 - value to update counter ( 1 increase, -1 decrease)
# $3 - file to match with the counter
# $4 - file to set according to the match ( 0 not matched, 1 matched)
unlock_service_state_change_update_and_match()
{
	update_file_name=$1
	val=$2
	match_file_name=$3
	set_file_name=$4
	local counter
	local match

	change_file_counter "$update_file_name" "$val"
	if [ ! -z "$3" ] && [ ! -z "$4" ]; then
		counter=$(< $update_file_name)
		match=$(< $match_file_name)
		if [ $counter -eq $match ]; then
			echo 1 > $set_file_name
		else
			echo 0 > $set_file_name
		fi
	fi
	/usr/bin/flock -u ${LOCKFD}
}

connect_device()
{
	find_i2c_bus
	if [ -f /sys/bus/i2c/devices/i2c-"$3"/new_device ]; then
		addr=$(echo "$2" | tail -c +3)
		bus=$(($3+i2c_bus_offset))
		if [ ! -d /sys/bus/i2c/devices/$bus-00"$addr" ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" "$2" > /sys/bus/i2c/devices/i2c-$bus/new_device
			return $?
		fi
	fi

	return 0
}

disconnect_device()
{
	find_i2c_bus
	if [ -f /sys/bus/i2c/devices/i2c-"$2"/delete_device ]; then
		addr=$(echo "$1" | tail -c +3)
		bus=$(($2+i2c_bus_offset))
		if [ -d /sys/bus/i2c/devices/$bus-00"$addr" ] ||
		   [ -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" > /sys/bus/i2c/devices/i2c-$bus/delete_device
			return $?
		fi
	fi

	return 0
}

# Common retry helper function.
# Input:
# - $1 - user function to execute.
# - $2 - retry timeout delay window.
# - $3 - retry counter.
# - $4 - user log to be produced if user function failed (optional).
# - $5 - user parameter to execute.
# Output:
# - return code (0 - success; 1 - failure).
# Example:
# retry_helper find_regio_sysfs_path_helper 0.5 10 "mlxreg_io is not loaded"
function retry_helper()
{
	local user_func="$1"
	local retry_to="$2"
	local retry_cnt="$3"
	local user_log="$4"
	local user_param="$5"

	for ((i=0; i<${retry_cnt}; i+=1)); do
		$user_func $user_param
		if [ $? -eq 0 ]; then
			return 0
		fi
		sleep "$retry_to"
	done

	if [ ! -z "$$user_log" ]; then
		log_err "$user_log"
	fi

	return 1
}

# Set PSU fan speed
# Input:
# - $1 - psu name
# - $2 - psu speed
# Output:
# - none
psu_set_fan_speed()
{
	local addr=$(< $config_path/"$1"_i2c_addr)
	local bus=$(< $config_path/"$1"_i2c_bus)
	local fan_config_command=$(< $config_path/fan_config_command)
	local fan_speed_units=$(< $config_path/fan_speed_units)
	local fan_command=$(< $config_path/fan_command)
	local speed=$2

	# Set fan speed units (percentage or RPM)
	i2cset -f -y "$bus" "$addr" "$fan_config_command" "$fan_speed_units" bp

	# Set fan speed
	i2cset -f -y "$bus" "$addr" "$fan_command" "${speed}" wp
}

is_virtual_machine()
{
    if [ -n "$(lspci -vvv | grep SimX)" ]; then
        return 0
    else
        return 1
    fi
}
