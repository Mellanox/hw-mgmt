#!/bin/bash

###########################################################################
# Copyright (c) 2018, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

source hw-management-helpers.sh
board_type=$(< $board_type_file)

# Local variables
fan_command=$config_path/fan_command
fan_psu_default=$config_path/fan_psu_default
max_psus=4
max_pwm=4
max_lcs=8
max_erots=2
max_leakage=8
min_module_gbox_ind=2
max_module_gbox_ind=160
min_lc_thermal_ind=1
max_lc_thermal_ind=20
pciesw_i2c_bus=0
fan_full_speed_code=20
# Static variable to keep track the number of fan drawers
fan_drwr_num=0
# 46 - F, 52 - R
fan_direction_exhaust=46
fan_direction_intake=52

if [ "$board_type" == "VMOD0014" ]; then
	i2c_bus_max=14
	i2c_asic_bus_default=6
	max_tachos=4
	max_pwm=1
fi

# Get line card number by module 'sysfs' device path
# $1 - sys device path in, example: /sys/devices/platform/mlxplat/i2c_mlxcpld.1/i2c-1/i2c-3/3-0037/hwmon/hwmon<n>/
# return line card number 1..8 or 0 in ASIC case
get_lc_id_hwmon()
{
	sysfs_path=$1
	name=$(< "$sysfs_path"/name)
	regex="linecard#([0-9]+)"
	[[ $name =~ $regex ]]
	if [[ -z "${BASH_REMATCH[1]}" ]]; then
		return 0
	else
		return "${BASH_REMATCH[1]}"
	fi
}

set_lc_id_hwmon()
{
	sysfs_path=$1
	cpath=$2
	hwmon=$(basename "$sysfs_path")
	echo $hwmon > "$cpath/hwmon"
}

get_lc_id_from_hwmon()
{
	sysfs_path=$1
	hwmon=$(basename "$sysfs_path")
	lc_num=$(< $config_path/hotplug_linecards)
	for ((i = 1; i <= $lc_num; i++ )); do
		if [ -d $hw_management_path/lc"$i" ]; then
			hwmon_lc=$(< "$hw_management_path/lc$i/config/hwmon")
			if [ "$hwmon" == "$hwmon_lc" ]; then
				return "$i"
			fi
		fi
	done
	return 0
}

# Get line card number from tz name
# $1 - zone type example: mlxsw-lc2-module8, mlxsw-module8
# return line card number 1..8 or 0 in ASIC case
get_lc_id_tz()
{
	zonetype=$1
	regex="mlxsw-lc([0-9]+)?-\S+[0-9]+"
	[[ $zonetype =~ $regex ]]
	if [[ -z "${BASH_REMATCH[1]}" ]]; then
		return 0
	else
		return "${BASH_REMATCH[1]}"
	fi
}

psu_sensor_attr_list=("min" "max" "crit" "lcrit")

# Connect PSU sensor with attributes (min, max, crit, lcrit)
# $1 - sensor sysfs path
# $2 - sensor name (volt, volt_in, curr, ...)
# return none
psu_connect_power_sensor()
{
	sysfs_sensor_path=$1
	sensor_name=$2

	# First check and connect sensor
	if [ -f "$sysfs_sensor_path"_input ];
	then
		ln -sf "$sysfs_sensor_path"_input "$power_path"/"$sensor_name"
		touch "$power_path"/"$sensor_name"_capability
		for attr_name in ${psu_sensor_attr_list[*]}
		do
			sysfs_sensor_attr_path="$sysfs_sensor_path"_$attr_name
			if [ -f "$sysfs_sensor_attr_path" ];
			then
				ln -sf "$sysfs_sensor_attr_path" "$power_path"/"$sensor_name"_"$attr_name"
				echo -n "$attr_name " >> "$power_path"/"$sensor_name"_capability
			fi
		done
	fi
}

# Disconnect PSU sensor with attributes (min, max,crit, lcrit)
# $1 - sensor name
# return none
psu_disconnect_power_sensor()
{
	sensor_name=$1
	check_n_unlink "$power_path"/"$sensor_name"
	for attr_name in ${psu_sensor_attr_list[*]}
	do
		check_n_unlink "$power_path"/"$sensor_name"_"$attr_name"
	done
	rm -f "$power_path"/"$sensor_name"_capability
}

sn2201_find_cpu_core_temp_ids()
{
	if [ -e $config_path/core0_temp_id ]; then
		core0_temp_id=$(<$config_path/core0_temp_id)
	else
		tmp=$(cat /proc/cpuinfo | grep -m1 "core id" | awk '{print $4}')
		core0_temp_id==$(($tmp+2))
	fi
	if [ -e $config_path/core1_temp_id ]; then
		core1_temp_id=$(<$config_path/core1_temp_id)
	else
		tmp=$(cat /proc/cpuinfo | grep -m2 "core id" | tail -n1 | awk '{print $4}')
		core1_temp_id=$(($tmp+2))
	fi
}

get_fixed_fans_direction()
{
	# Earlier the code was trying to read the offset of the string MLNX from
	# /var/run/hw-management/eeprom/vpd_info and perform the fan direction
	# offset computation like this:
	# fan_dir_offset=$((sanity_offset+pn_sanity_offset+fan_dir_pn_offset))
	# sanity_offset:     Offset of string "MLNX"
	# pn_sanity_offset:  62
	# fan_dir_pn_offset: 11
	# There was a delay of ~10sec to get the 'vpd_info' to be available.
	# This optimization directly read the fan direction from the eeprom
	# address 0x102, using i2ctransfer command and avoids the delay.
	fan_direction=$(i2ctransfer -f -y 8 w2@0x51 0x01 0x02 r1 | cut -d'x' -f 2)	
	case $fan_direction in
	$fan_direction_exhaust)
		echo 1 > $config_path/fixed_fans_dir
		;;
	$fan_direction_intake)
		echo 0 > $config_path/fixed_fans_dir
		;;
	*)
		;;
	esac
}

if [ "$1" == "add" ]; then
	# Don't process udev events until service is started and directories are created
	if [ ! -f ${udev_ready} ]; then
		exit 0
	fi
	case "$2" in
		fan_amb | port_amb | pcisw_amb | lrl_amb | swb_amb | cpu_amb)
		# Verify if this is COMEX sensor
		find_i2c_bus
		i2c_comex_mon_bus_default=$(< $i2c_comex_mon_bus_default_file)
		comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
		# Verify if this is ASIC sensor
		asic_bus=$((i2c_asic_bus_default+i2c_bus_offset))
		if [ -f $config_path/pcie_default_i2c_bus ]; then
			pciesw_i2c_bus=$(< $config_path/pcie_default_i2c_bus)
			pciesw_i2c_bus=$((pciesw_i2c_bus+i2c_bus_offset))
		fi
		busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		if [ "$bus" == "$comex_bus" ]; then
			ln -sf "$3""$4"/temp1_input $thermal_path/comex_amb
		elif [ "$bus" == "$asic_bus" ]; then
			exit 0
		elif [ "$bus" == "$pciesw_i2c_bus" ]; then
			ln -sf "$3""$4"/temp2_input $thermal_path/pciesw_amb
		else
			ln -sf "$3""$4"/temp1_input $thermal_path/"$2"
		fi
		;;
	esac
	if [ "$2" == "switch" ]; then
		name=$(< "$3""$4"/name)
		if [[ $name != *"nvme"* ]]; then
			get_lc_id_hwmon "$3$4"
			lc_number=$?
			if [ "$lc_number" -ne 0 ]; then
				cpath="$hw_management_path/lc$lc_number/config"
				tpath="$hw_management_path/lc$lc_number/thermal"
				min_module_ind=$min_lc_thermal_ind
				max_module_ind=$max_lc_thermal_ind
				set_lc_id_hwmon "$3$4" "$cpath"
			else
				cpath="$config_path"
				tpath="$thermal_path"
				min_module_ind=$min_module_gbox_ind
				max_module_ind=$max_module_gbox_ind
				echo 0 > "$cpath"/gearbox_counter
				echo 0 > "$cpath"/module_counter
			fi

			if [ ! -f "$cpath/gearbox_counter" ]; then
				echo 0 > "$cpath"/gearbox_counter
			fi
			if [ ! -f "$cpath/module_counter" ]; then
				echo 0 > "$cpath"/module_counter
			fi

			if [ "$name" == "mlxsw" ]; then
				ln -sf "$3$4" $cpath/asic_hwmon
				ln -sf "$3""$4"/temp1_input "$tpath"/asic
				if [ -f "$3""$4"/pwm1 ]; then
					ln -sf "$3""$4"/pwm1 "$tpath"/pwm1
					echo "$name" > "$cpath"/cooling_name
				fi
				if [ -f "$cpath"/fan_inversed ]; then
					inv=$(< "$cpath"/fan_inversed)
				fi
				for ((i=1; i<=max_tachos; i+=1)); do
					if [ -z "$inv" ] || [ "${inv}" -eq 0 ]; then
						j=$i
					else
						j=$((inv - i))
					fi
					if [ -f "$3""$4"/fan"$i"_input ]; then
						ln -sf "$3""$4"/fan"$i"_input "$tpath"/fan"$j"_speed_get
						ln -sf "$3""$4"/pwm1 "$tpath"/fan"$j"_speed_set
						ln -sf "$3""$4"/fan"$i"_fault "$tpath"/fan"$j"_fault
						check_n_link "$cpath"/fan_min_speed "$tpath"/fan"$j"_min
						check_n_link "$cpath"/fan_max_speed "$tpath"/fan"$j"_max
						# Save max_tachos to config
						echo $i > "$cpath"/max_tachos
					fi
				done
			fi

			lcmatch=`echo $name | cut -d"#" -f1`
			if [ "$name" == "mlxsw" ] || [ "$lcmatch" == "linecard" ]; then
				for ((i=min_module_ind; i<=max_module_ind; i+=1)); do
					if [ -f "$3""$4"/temp"$i"_input ]; then
						label=$(< "$3""$4"/temp"$i"_label)
						case $label in
						*front*)
							if [ "$name" == "mlxsw" ]; then
								j=$((i-1))
							else
								j="$i"
							fi
							ln -sf "$3""$4"/temp"$i"_input "$tpath"/module"$j"_temp_input
							ln -sf "$3""$4"/temp"$i"_fault "$tpath"/module"$j"_temp_fault
							ln -sf "$3""$4"/temp"$i"_crit "$tpath"/module"$j"_temp_crit
							ln -sf "$3""$4"/temp"$i"_emergency "$tpath"/module"$j"_temp_emergency
							lock_service_state_change
							change_file_counter "$cpath"/module_counter 1
							if [ "$lcmatch" == "linecard" ]; then
								change_file_counter "$config_path"/module_counter 1
							fi
							unlock_service_state_change
							;;
						*gear*)
							lock_service_state_change
							change_file_counter "$cpath"/gearbox_counter 1
							gearbox_counter=`cat "$cpath"/gearbox_counter`
							if [ "$lcmatch" == "linecard" ]; then
								change_file_counter "$config_path"/gearbox_counter 1
							fi
							ln -sf "$3""$4"/temp"$i"_input "$tpath"/gearbox"$gearbox_counter"_temp_input
							unlock_service_state_change
							;;
						*)
							;;
						esac
					fi
				done
			fi
		fi
	fi

	if [ "$2" == "regfan" ]; then
		name=$(< "$3""$4"/name)
		echo "$name" > $config_path/cooling_name
		ln -sf "$3""$4"/pwm1 $thermal_path/pwm1
		for ((i=1; i<=max_pwm; i+=1)); do
			check_n_link "$3""$4"/pwm"$i" $thermal_path/pwm"$i"
		done
		if [ -f $config_path/fan_inversed ]; then
			inv=$(< $config_path/fan_inversed)
		fi
		for ((i=1; i<=max_tachos; i+=1)); do
			if [ -z "$inv" ] || [ "${inv}" -eq 0 ]; then
				j=$i
			else
				j=$((inv - i))
			fi
			if [ -f "$3""$4"/fan"$i"_input ]; then
				ln -sf "$3""$4"/fan"$i"_input $thermal_path/fan"$j"_speed_get
				ln -sf "$3""$4"/pwm1 $thermal_path/fan"$j"_speed_set
				ln -sf "$3""$4"/fan"$i"_fault $thermal_path/fan"$j"_fault
				check_n_link $config_path/fan_min_speed $thermal_path/fan"$j"_min
				check_n_link $config_path/fan_max_speed $thermal_path/fan"$j"_max
				# Save max_tachos to config.
				echo $i > $config_path/max_tachos
			fi
		done
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=$(< "$3""$4"/type)
		get_lc_id_tz "$zonetype"
		lc_number=$?
		if [ "$lc_number" -ne 0 ]; then
			# Remove "lc{n}" from zonetype substring
			# mlxsw-lc1-module2 => mlxsw-module2
			regex="(\S+)-lc[0-9]+(-\S+[0-9]+)"
			[[ $zonetype =~ $regex ]]
			zonetype="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
			tpath="$hw_management_path/lc$lc_number/thermal"
		else
			tpath="$hw_management_path/thermal"
		fi

		zonename="$zonetype"
		zoneptype=${zonetype//[0-9]/}
		if [ "$zoneptype" == "mlxsw" ] ||
		   [ "$zoneptype" == "mlxsw-module" ] ||
		   [ "$zoneptype" == "mlxsw-gearbox" ]; then
			mkdir $tpath/"$zonetype"
			ln -sf "$3""$4"/mode $tpath/"$zonetype"/thermal_zone_mode
			ln -sf "$3""$4"/policy $tpath/"$zonetype"/thermal_zone_policy
			ln -sf "$3""$4"/trip_point_0_temp $tpath/"$zonetype"/temp_trip_norm
			ln -sf "$3""$4"/trip_point_1_temp $tpath/"$zonetype"/temp_trip_high
			ln -sf "$3""$4"/trip_point_2_temp $tpath/"$zonetype"/temp_trip_hot
			ln -sf "$3""$4"/temp $tpath/"$zonetype"/thermal_zone_temp
			check_n_link $tpath/"$zonetype"/thermal_zone_temp_emul
			# Create entry with hardcoded value for compatibility with user space.
			if [ "$zoneptype" == "mlxsw" ] || [ "$zoneptype" == "mlxsw-gearbox" ]; then
				if [ ! -f $thermal_path/"$zonetype"/temp_trip_crit ]; then
					echo 120000 > $thermal_path/"$zonename"/temp_trip_crit
				fi
			fi
			# Invoke user thermal governor if exist.
			if [ -x /usr/bin/hw-management-user-thermal-governor.sh ]; then
				/usr/bin/hw-management-user-thermal-governor.sh $tpath/"$zonetype"
			fi
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=$(< "$3""$4"/type)
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan0" ] ||
		   [ "$coolingtype" == "emc2305" ]; then
			check_n_link "$3""$4"/cur_state $thermal_path/cooling_cur_state
			check_n_link "$3""$4"/max_state $thermal_path/cooling_max_state
			# Set FAN to full speed until thermal control is started.
			echo $fan_full_speed_code > $thermal_path/cooling_cur_state
			log_info "FAN speed is set to full speed"
		fi
		if [ "$coolingtype" == "mlxreg_fan1" ]; then
			check_n_link "$3""$4"/cur_state $thermal_path/cooling1_cur_state
			check_n_link "$3""$4"/max_state $thermal_path/cooling1_max_state
		fi
		if [ "$coolingtype" == "mlxreg_fan2" ]; then
			check_n_link "$3""$4"/cur_state $thermal_path/cooling2_cur_state
			check_n_link "$3""$4"/max_state $thermal_path/cooling2_max_state
		fi
		if [ "$coolingtype" == "mlxreg_fan3" ]; then
			check_n_link "$3""$4"/cur_state $thermal_path/cooling3_cur_state
			check_n_link "$3""$4"/max_state $thermal_path/cooling3_max_state
		fi
	fi
	if [ "$2" == "hotplug" ]; then
		for ((i=1; i<=max_tachos; i+=1)); do
			if [ -f "$3""$4"/fan$i ]; then
				ln -sf "$3""$4"/fan$i $thermal_path/fan"$i"_status
				event=$(< $thermal_path/fan"$i"_status)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/fan"$i"
				fi
				(( fan_drwr_num++ ))
			fi
		done

		if [ -f $config_path/fixed_fans_system ] && [ "$(< $config_path/fixed_fans_system)" = 1 ]; then
			get_fixed_fans_direction
			if [ -f $config_path/fixed_fans_dir ]; then
				for i in $(seq 1 "$(< $config_path/fan_drwr_num)"); do
					cat $config_path/fixed_fans_dir > $thermal_path/fan"$i"_dir
					echo 1 > $thermal_path/fan"$i"_status
				done
			fi
		else
			echo $fan_drwr_num > $config_path/fan_drwr_num
		fi

		for ((i=1; i<=max_psus; i+=1)); do
			if [ -f "$3""$4"/psu$i ]; then
				ln -sf "$3""$4"/psu$i $thermal_path/psu"$i"_status
				event=$(< $thermal_path/psu"$i"_status)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/psu"$i"
				fi
			fi
			if [ -f "$3""$4"/pwr$i ]; then
				ln -sf "$3""$4"/pwr$i $thermal_path/psu"$i"_pwr_status
				event=$(< "$thermal_path"/psu"$i"_pwr_status)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/pwr"$i"
				fi
			fi
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			if [ -f "$3""$4"/lc"$i"_active ]; then
				ln -sf "$3""$4"/lc"$i"_active $system_path/lc"$i"_active
				event=$(< $system_path/lc"$i"_active)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_active
				fi
			fi
			if [ -f "$3""$4"/lc"$i"_powered ]; then
				ln -sf "$3""$4"/lc"$i"_powered $system_path/lc"$i"_powered
				event=$(< $system_path/lc"$i"_powered)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_powered
				fi
			fi
			if [ -f "$3""$4"/lc"$i"_present ]; then
				ln -sf "$3""$4"/lc"$i"_present $system_path/lc"$i"_present
				event=$(< $system_path/lc"$i"_present)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_present
				fi
			fi
			if [ -f "$3""$4"/lc"$i"_ready ]; then
				ln -sf "$3""$4"/lc"$i"_ready $system_path/lc"$i"_ready
				event=$(< $system_path/lc"$i"_ready)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_ready
				fi
			fi
			if [ -f "$3""$4"/lc"$i"_shutdown ]; then
				ln -sf "$3""$4"/lc"$i"_shutdown $system_path/lc"$i"_shutdown
				event=$(< $system_path/lc"$i"_shutdown)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_shutdown
				fi
			fi
			if [ -f "$3""$4"/lc"$i"_synced ]; then
				ln -sf "$3""$4"/lc"$i"_synced $system_path/lc"$i"_synced
				event=$(< $system_path/lc"$i"_synced)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_synced
				fi
			fi
			if [ -f "$3""$4"/lc"$i"_verified ]; then
				ln -sf "$3""$4"/lc"$i"_verified $system_path/lc"$i"_verified
				event=$(< $system_path/lc"$i"_verified)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_verified
				fi
			fi
		done
		for ((i=1; i<=max_erots; i+=1)); do
			if [ -f "$3""$4"/erot"$i"_ap ]; then
				ln -sf "$3""$4"/erot"$i"_ap $system_path/erot"$i"_ap
				event=$(< $system_path/erot"$i"_ap)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/erot"$i"_ap
				fi
			fi
			if [ -f "$3""$4"/erot"$i"_error ]; then
				ln -sf "$3""$4"/erot"$i"_error $system_path/erot"$i"_error
				event=$(< $system_path/erot"$i"_error)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/erot"$i"_error
				fi
			fi
		done
		for ((i=1; i<=max_leakage; i+=1)); do
			if [ -f "$3""$4"/leakage$i ]; then
				ln -sf "$3""$4"/leakage$i $system_path/leakage"$i"_status
				event=$(< $system_path/leakage"$i"_status)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/leakage"$i"
				fi
			fi
		done
		if [ -f "$3""$4"/leakage_rope ]; then
			ln -sf "$3""$4"/leakage_rope $system_path/leakage_rope_status
			event=$(< $system_path/leakage_rope_status)
			if [ "$event" -eq 1 ]; then
				echo 1 > $events_path/leakage_rope
			fi
		fi
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		check_n_link "$3""$4"/uevent $config_path/port_config_done
		if [ ! -f "$config_path/asic_num" ]; then
			asic_num=1
		else
			asic_num=$(< $config_path/asic_num)
		fi
		for ((i=1; i<=asic_num; i+=1)); do
			asic_health=0
			if [ -f "$3""$4"/asic"$i" ]; then
				asic_health=$(< "$3""$4"/asic"$i")
			fi
			if [ "$asic_health" -ne 2 ]; then
				exit 0
			fi
			if [ ! -d /sys/module/mlxsw_minimal ]; then
				modprobe mlxsw_minimal
			fi
			if [ ! -f /etc/init.d/sxdkernel ] && [ ! -f /usr/lib/cumulus/sxdkernel ]; then
				sleep 3
				/usr/bin/hw-management.sh chipup "$i"
			fi
		done
	fi
	# Max index of SN2201 cputemp is 14.
	if [ "$2" == "cputemp" ]; then
		if [ "$board_type" == "VMOD0014" ]; then
			sn2201_find_cpu_core_temp_ids
		fi
		for i in {1..16}; do
			if [ -f "$3""$4"/temp"$i"_input ]; then
				if [ $i -eq 1 ]; then
					name="pack"
				else
					if [ "$board_type" != "VMOD0014" ]; then
						id=$((i - 2))
					else
					# Denverton CPU on SN2201 has ridicolous CPU Core numbers 6, 12 instead 0, 1
					# These core id numbers also can differ in various CPU batches.
						if [ "$i" == "$core0_temp_id" ]; then
							id=0
						elif [ "$i" == "$core1_temp_id" ]; then
							id=1
						fi
					fi
					name="core$id"
				fi
				ln -sf "$3""$4"/temp"$i"_input $thermal_path/cpu_$name
				ln -sf "$3""$4"/temp"$i"_crit $thermal_path/cpu_"$name"_crit
				ln -sf "$3""$4"/temp"$i"_max $thermal_path/cpu_"$name"_max
				ln -sf "$3""$4"/temp"$i"_crit_alarm $alarm_path/cpu_"$name"_crit_alarm
			fi
		done
	fi
	if [ "$2" == "pch_temp" ]; then
		name=$(<"$3""$4"/name)
		if [ "$name" == "pch_cannonlake" ]; then
			ln -sf "$3""$4"/temp1_input $thermal_path/pch_temp
		fi
	fi
	if [ "$2" == "sodimm_temp" ]; then
		check_cpu_type
		shopt -s extglob
		case $cpu_type in
			$RNG_CPU)
				sodimm1_addr='0-0018'
				sodimm2_addr='0-001a'
			;;
			$IVB_CPU)
				sodimm1_addr='0-001b'
				sodimm2_addr='0-001a'
			;;
			$CFL_CPU)
				sodimm1_addr='0-001c'
				sodimm2_addr='@(0-001a|0-001e)'
			;;
			$DNV_CPU)
				sodimm1_addr='0-0018'
				sodimm2_addr='0-001a'
			;;
			*)
				exit 0
			;;
		esac

		sodimm_i2c_addr=$(echo "$3"|xargs dirname|xargs dirname|xargs basename)
		case $sodimm_i2c_addr in
			$sodimm1_addr)
				sodimm_name=sodimm1_temp
			;;
			$sodimm2_addr)
				sodimm_name=sodimm2_temp
			;;
			*)
				exit 0
			;;
		esac
		find "$5""$3" -iname 'temp1_*' -exec sh -c 'ln -sf $1 $2/$3$(basename $1| cut -d1 -f2)' _ {} "$thermal_path" "$sodimm_name" \;
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ] ||
	   [ "$2" == "psu3" ] || [ "$2" == "psu4" ]; then
		sku=$(< /sys/devices/virtual/dmi/id/product_sku)
		if [[ $sku == "HI138" ]] || [[ $sku == "HI139" ]]; then
			exit 0
		fi
		find_i2c_bus
		i2c_comex_mon_bus_default=$(< $i2c_comex_mon_bus_default_file)
		comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
		# PSU unit FAN speed set
		busdir=$(echo "$5""$3" |xargs dirname |xargs dirname)
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		# Verify if this is COMEX device
		if [ "$bus" == "$comex_bus" ]; then
			exit 0
		fi
		# Set default fan speed
		addr=$(< $config_path/"$2"_i2c_addr)
		command=$(< $fan_command)
		speed=$(< $fan_psu_default)
		# Allow PS controller to stabilize
		sleep 2
		i2cset -f -y "$bus" "$addr" "$command" "$speed" wp
		# Set I2C bus for psu
		echo "$bus" > $config_path/"$2"_i2c_bus
		# Add thermal attributes
		check_n_link "$5""$3"/temp1_input $thermal_path/"$2"_temp
		check_n_link "$5""$3"/temp1_max $thermal_path/"$2"_temp_max
		check_n_link "$5""$3"/temp1_max_alarm $thermal_path/"$2"_temp_max_alarm
		check_n_link "$5""$3"/temp2_input $thermal_path/"$2"_temp2
		check_n_link "$5""$3"/temp2_max $thermal_path/"$2"_temp2_max
		check_n_link "$5""$3"/temp2_max_alarm $thermal_path/"$2"_temp2_max_alarm
		check_n_link "$5""$3"/fan1_alarm $alarm_path/"$2"_fan1_alarm
		check_n_link "$5""$3"/power1_alarm $alarm_path/"$2"_power1_alarm
		check_n_link "$5""$3"/fan1_input $thermal_path/"$2"_fan1_speed_get

		# Add PSU power attributes
		psu_connect_power_sensor "$5""$3"/in1 "$2"_volt_in
		psu_connect_power_sensor "$5""$3"/in2 "$2"_volt

		if [ -f "$5""$3"/in3_input ]; then
			psu_connect_power_sensor "$5""$3"/in3 "$2"_volt_out2
		else
			in2_label=$(< "$5""$3"/in2_label)
			if [ "$in2_label" == "vout1" ]; then
				psu_connect_power_sensor "$5""$3"/in2 "$2"_volt_out
			fi
		fi
		psu_connect_power_sensor "$5""$3"/power1 "$2"_power_in
		psu_connect_power_sensor "$5""$3"/power2 "$2"_power
		psu_connect_power_sensor "$5""$3"/curr1 "$2"_curr_in
		psu_connect_power_sensor "$5""$3"/curr2 "$2"_curr

		# Allow modification for some PSU thresholds through 'sensors'
		# utilities 'sets instruction.
		if [ -f "$5""$3"/in3_lcrit ]; then
			chmod 644 "$5""$3"/in3_lcrit
		fi
		if [ -f "$5""$3"/in3_min ]; then
			chmod 644 "$5""$3"/in3_min
		fi
		if [ -f "$5""$3"/in3_max ]; then
			chmod 644 "$5""$3"/in3_max
		fi

		if [ ! -f $config_path/"$2"_i2c_addr ]; then
			exit 0
		fi

		psu_addr=$(< $config_path/"$2"_i2c_addr)
		psu_eeprom_addr=$(printf '%02x\n' $((psu_addr - 8)))
		eeprom_name=$2_info
		if [ "$board_type" == "VMOD0014" ]; then
			eeprom_file=/sys/devices/pci0000:00/*/NVSN2201:*/i2c_mlxcpld.1/i2c-1/i2c-$bus/$bus-00$psu_eeprom_addr/eeprom
		else
			eeprom_file=/sys/devices/platform/mlxplat/i2c_mlxcpld.1/i2c-1/i2c-$bus/$bus-00$psu_eeprom_addr/eeprom
		fi
		# Verify if PS unit is equipped with EEPROM. If yes – connect driver.
		i2cget -f -y "$bus" 0x$psu_eeprom_addr 0x0 > /dev/null 2>&1
		if [ $? -eq 0 ] && [ ! -L $eeprom_path/"$2"_info ] && [ ! -f "$eeprom_file" ]; then
			if [ "$board_type" == "VMOD0014" ]; then
				psu_eeprom_type="24c02"
			else
				psu_eeprom_type="24c32"
			fi
			if [ -f $config_path/psu_eeprom_type ]; then
				psu_eeprom_type=$(< "$config_path"/psu_eeprom_type)
			fi
			echo "$psu_eeprom_type" 0x"$psu_eeprom_addr" > /sys/class/i2c-dev/i2c-"$bus"/device/new_device
			ln -sf "$eeprom_file" "$eeprom_path"/"$eeprom_name" 2>/dev/null
			chmod 400 "$eeprom_path"/"$eeprom_name" 2>/dev/null
			echo 1 > $config_path/"$2"_eeprom_us
		fi

		# Set default PSU FAN speed from config, it will be overwitten by values from VPD.
		if [ -f $config_path/psu_fan_min ]; then
			cat $config_path/psu_fan_min > "$thermal_path"/"$2"_fan_min
		fi
		if [ -f $config_path/psu_fan_max ]; then
			cat $config_path/psu_fan_max > "$thermal_path"/"$2"_fan_max
		fi
		# PSU VPD
		ps_ctrl_addr="${busfolder:${#busfolder}-2:${#busfolder}}"
		hw-management-ps-vpd.sh --BUS_ID "$bus" --I2C_ADDR 0x"$ps_ctrl_addr" --dump --VPD_OUTPUT_FILE $eeprom_path/"$2"_vpd
		if [ $? -ne 0 ]; then
			# PS EEPROM VPD.
			hw-management-parse-eeprom.sh --conv --eeprom_path $eeprom_path/"$2"_info > $eeprom_path/"$2"_vpd
			if [ $? -ne 0 ]; then
				# EEPROM failed.
				echo "Failed to read PSU VPD" > $eeprom_path/"$2"_vpd
				exit 0
			else
				# Add PSU FAN speed info.
				if [ -f $config_path/psu_fan_max ]; then
					echo -ne "MAX_RPM: " >> $eeprom_path/"$2"_vpd
					cat $config_path/psu_fan_max >> $eeprom_path/"$2"_vpd
				fi
				if [ -f $config_path/psu_fan_min ]; then
					echo -ne "MIN_RPM: " >> $eeprom_path/"$2"_vpd
					cat $config_path/psu_fan_min >> $eeprom_path/"$2"_vpd
				fi
			fi
		fi
		# Expose min/max psu fan speed per psu from vpd to attributes.
		grep MIN_RPM: $eeprom_path/"$2"_vpd | cut -d' ' -f2 > "$thermal_path"/"$2"_fan_min
		grep MAX_RPM: $eeprom_path/"$2"_vpd | cut -d' ' -f2 > "$thermal_path"/"$2"_fan_max
		ps_min_rpm=$(<"$thermal_path"/"$2"_fan_min)
		ps_max_rpm=$(< "$thermal_path"/"$2"_fan_max)
		if [ "$ps_min_rpm" -eq 0 ]; then
			ps_min_rpm=$(((ps_max_rpm*20)/100))
			echo $ps_min_rpm > "$thermal_path"/"$2"_fan_min
		fi

		# PSU FW VER
		mfr=$(grep MFR_NAME $eeprom_path/"$2"_vpd | awk '{print $2}')
		cap=$(grep CAPACITY $eeprom_path/"$2"_vpd | awk '{print $2}')
		if echo $mfr | grep -iq "Murata"; then
			# Support FW update only for specific Murata PSU capacities
			fw_ver="N/A"
			fw_primary_ver="N/A"
			if [ "$cap" == "1500" -o "$cap" == "2000" ]; then
				fw_ver=$(hw_management_psu_fw_update_murata.py -v -b $bus -a $psu_addr)
				fw_primary_ver=$(hw_management_psu_fw_update_murata.py -v -b $bus -a $psu_addr -P)
			fi
			echo $fw_ver > $fw_path/"$2"_fw_ver
			echo $fw_primary_ver > $fw_path/"$2"_fw_primary_ver
		elif echo $mfr | grep -iq "Delta"; then
			# Support FW update only for specific Delta PSU capacities
			fw_ver="N/A"
			if [ "$cap" == "550" -o "$cap" == "2000" ]; then
				fw_ver=$(hw_management_psu_fw_update_delta.py -v -b $bus -a $psu_addr)
			fi
			echo $fw_ver > $fw_path/"$2"_fw_ver
			# Special handling for Delta 2000 fan speed command
			if [ "$cap" == "2000" ]; then
				i2cset -f -y "$bus" "$addr" 0x3a 0x90 bp
				i2cset -f -y "$bus" "$addr" "$command" "$speed" wp
			fi
		fi

	fi
	if [ "$2" == "sxcore" ]; then
		if [ ! -d /sys/module/mlxsw_minimal ]; then
			modprobe mlxsw_minimal
		fi
		/usr/bin/hw-management.sh chipup 0 "$4/$5"
	fi
	if [ "$2" == "nvme_temp" ]; then
		dev_name=$(cat "$3""$4"/name)
		if [ "$dev_name" == "nvme" ]; then
			for i in {1..4}; do
				if [ -f "$3""$4"/temp"$i"_input ]; then
					label=$(cat "$3""$4"/temp"$i"_label | awk '{ gsub (" ", "", $0); print}')
					name=$(echo "$label" | awk '{print tolower($0)}')
					ln -sf "$3""$4"/temp"$i"_input "$thermal_path"/"$dev_name"_"$name"
					# Make links only to 1st sensor - Composite temperature.
					# Normaslized composite temperature values are taken to thermal management.
					if [ "$i" -eq 1 ]; then
						ln -sf "$3""$4"/temp"$i"_alarm "$thermal_path"/"$dev_name"_"$name"_alarm
						ln -sf "$3""$4"/temp"$i"_crit "$thermal_path"/"$dev_name"_"$name"_crit
						ln -sf "$3""$4"/temp"$i"_max "$thermal_path"/"$dev_name"_"$name"_max
						ln -sf "$3""$4"/temp"$i"_min "$thermal_path"/"$dev_name"_"$name"_min
					fi
				fi
			done
		fi
	fi
elif [ "$1" == "change" ]; then
	if [ "$2" == "hotplug_asic" ]; then
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		asic_index="$6"
		asic_num=$(< $config_path/asic_num)
		if [ "$asic_num" -lt "$asic_index" ]; then
			exit 0
		fi
		if [ "$3" == "up" ]; then
			if [ ! -d /sys/module/mlxsw_minimal ]; then
				modprobe mlxsw_minimal
			fi
			if [ ! -f /etc/init.d/sxdkernel ] && [ ! -f /usr/lib/cumulus/sxdkernel ]; then
				sleep 3
				/usr/bin/hw-management.sh chipup "$asic_index"
			fi
		elif [ "$3" == "down" ]; then
			/usr/bin/hw-management.sh chipdown "$asic_index"
		else
			asic_health=0
			if [ -f "$3""$4"/asic1 ]; then
				asic_health=$(< "$4""$5"/asic1)
			fi
			if [ "$asic_health" -eq 2 ]; then
				if [ ! -f /etc/init.d/sxdkernel ] && [ ! -f /usr/lib/cumulus/sxdkernel ]; then
					sleep 3
					/usr/bin/hw-management.sh chipup "$asic_index"
				fi
			else
				/usr/bin/hw-management.sh chipdown "$asic_index"
			fi
		fi
	fi
else
	case "$2" in
		fan_amb | port_amb | pcisw_amb | lrl_amb | swb_amb | cpu_amb)
		# Verify if this is COMEX sensor
		find_i2c_bus
		i2c_comex_mon_bus_default=$(< $i2c_comex_mon_bus_default_file)
		comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
		# Verify if this is ASIC sensor
		asic_bus=$((i2c_asic_bus_default+i2c_bus_offset))
		if [ -f $config_path/pcie_default_i2c_bus ]; then
			pciesw_i2c_bus=$(< $config_path/pcie_default_i2c_bus)
			pciesw_i2c_bus=$((pciesw_i2c_bus+i2c_bus_offset))
		fi
		busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		if [ "$bus" == "$comex_bus" ]; then
			unlink $thermal_path/comex_amb
		elif [ "$bus" == "$asic_bus" ]; then
			exit 0
		elif [ "$bus" == "$pciesw_i2c_bus" ]; then
			unlink $thermal_path/pciesw_amb
		else
			unlink $thermal_path/$
		fi
		;;
	esac
	if [ "$2" == "switch" ]; then
		name=$(< "$3""$4"/name)
		if [[ $name != *"nvme"* ]]; then
			[ -f "$config_path/stopping" ] && stopping=$(< $config_path/stopping)
			if [ "$stopping" ] &&  [ "$stopping" = "1" ]; then
				exit 0
			fi
			get_lc_id_from_hwmon "$3$4"
			lc_id=$?
			if [ "$lc_id" -ne 0 ]; then
				cpath="$hw_management_path/lc$lc_id/config"
				tpath="$hw_management_path/lc$lc_id/thermal"
				max_module_ind=$(< $cpath/module_counter)
				max_ind="$max_lc_thermal_ind"
				min_ind=1
			else
				cpath="$config_path"
				tpath="$thermal_path"
				max_ind="$max_module_gbox_ind"
				min_ind=2
			fi

			for ((i=$max_ind; i>=$min_ind; i-=1)); do
				if [ "$lc_id" -ne 0 ]; then
					j="$i"
					k=$((i-max_module_ind))
				else
					j=$((i-1))
				fi
				if [ -L $tpath/module"$j"_temp_input ]; then
					unlink $tpath/module"$j"_temp_input
					lock_service_state_change
					change_file_counter "$cpath"/module_counter -1
					if [ "$lc_id" -ne 0 ]; then
						change_file_counter "$config_path"/module_counter -1
					fi
					unlock_service_state_change
				elif [ -L $tpath/gearbox"$k"_temp_input ]; then
					unlink $tpath/gearbox"$j"_temp_input
					lock_service_state_change
					change_file_counter "$cpath"/gearbox_counter -1
					if [ "$lc_id" -ne 0 ]; then
						change_file_counter "$config_path"/gearbox_counter -1
					fi
					unlock_service_state_change
				fi
				check_n_unlink $tpath/module"$j"_temp_fault
				check_n_unlink $tpath/module"$j"_temp_crit
				check_n_unlink $tpath/module"$j"_temp_emergency
			done
			rm -f "$tpath/gearbox*_temp_input"
			rm -f "$tpath/module*_temp_input"
			rm -f "$tpath/module*_temp_fault"
			rm -f "$tpath/module*_temp_crit"
			rm -f "$tpath/module*_temp_emergency"

			echo 0 > $cpath/module_counter
			echo 0 > $cpath/gearbox_counter

			check_n_unlink $cpath/asic_hwmon

			if [ "$lc_id" -ne 0 ]; then
				exit 0
			fi
			check_n_unlink $thermal_path/asic
			name=$(< $$config_path/cooling_name)
			if [ "$name" == "mlxsw" ]; then
				check_n_unlink $thermal_path/pwm1
				for ((i=1; i<=max_tachos; i+=1)); do
					check_n_unlink $thermal_path/fan"$i"_fault
					check_n_unlink $thermal_path/fan"$i"_speed_get
					check_n_unlink $thermal_path/fan"$j"_min
					check_n_unlink $thermal_path/fan"$j"_max
				done
				check_n_unlink $thermal_path/pwm1
			fi
		fi
	fi
	if [ "$2" == "regfan" ]; then
		for ((i=1; i<=max_pwm; i+=1)); do
			if [ -L $thermal_path/pwm"$i" ]; then
				unlink $thermal_path/pwm"$i"
			fi
		done
		for ((i=1; i<=max_tachos; i+=1)); do
			check_n_unlink $thermal_path/fan"$i"_fault
			check_n_unlink $thermal_path/fan"$i"_speed_get
			check_n_unlink $thermal_path/fan"$i"_speed_set
			check_n_unlink $thermal_path/fan"$i"_min
			check_n_unlink $thermal_path/fan"$i"_max
		done
	fi
	if [ "$2" == "thermal_zone" ]; then
		[ -f "$config_path/stopping" ] && stopping=$(< $config_path/stopping)
		if [ "$stopping" ] &&  [ "$stopping" = "1" ]; then
			exit 0
		fi

		zonetype=$(< "$3""$4"/type)
		get_lc_id_tz "$zonetype"
		lc_id=$?
		if [ "$lc_id" -ne 0 ]; then
			tpath="$hw_management_path/lc$lc_id/thermal"
			max_module_ind=$max_lc_thermal_ind
		else
			tpath="$thermal_path"
			max_module_ind=$max_module_gbox_ind
		fi
		for ((i=1; i<max_module_ind; i+=1)); do
			if [ -d $tpath/mlxsw-module"$i" ]; then
				rm -rf $tpath/mlxsw-module"$i"
			fi
			if [ -d $tpath/mlxsw-gearbox"$i" ]; then
				rm -rf $tpath/mlxsw-gearbox"$i"
			fi
		done
		if [ "$lc_id" -ne 0 ]; then
			exit 0
		fi
		if [ -d $thermal_path/mlxsw ]; then
			rm -rf $thermal_path/mlxsw
		fi
		check_n_unlink $thermal_path/highest_thermal_zone
	fi
	if [ "$2" == "cooling_device" ]; then
		check_n_unlink $thermal_path/cooling_cur_state
		check_n_unlink $thermal_path/cooling_max_state
		check_n_unlink $thermal_path/cooling1_cur_state
		check_n_unlink $thermal_path/cooling1_max_state
		check_n_unlink $thermal_path/cooling2_cur_state
		check_n_unlink $thermal_path/cooling2_max_state
		check_n_unlink $thermal_path/cooling3_cur_state
		check_n_unlink $thermal_path/cooling3_max_state
	fi
	if [ "$2" == "hotplug" ]; then
		for ((i=1; i<=max_tachos; i+=1)); do
			check_n_unlink $thermal_path/fan"$i"_status
		done
		for ((i=1; i<=max_psus; i+=1)); do
			check_n_unlink $thermal_path/psu"$i"_status
			check_n_unlink $thermal_path/psu"$i"_pwr_status
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			check_n_unlink $system_path/lc"$i"_active
			check_n_unlink $system_path/lc"$i"_powered
			check_n_unlink $system_path/lc"$i"_present
			check_n_unlink $system_path/lc"$i"_ready
			check_n_unlink $system_path/lc"$i"_shutdown
			check_n_unlink $system_path/lc"$i"_synced
			check_n_unlink $system_path/lc"$i"_verified
		done
		for ((i=1; i<=max_erots; i+=1)); do
			check_n_unlink $system_path/erot"$i"_ap
			check_n_unlink $system_path/erot"$i"_error
		done
		for ((i=1; i<=max_leakage; i+=1)); do
			check_n_unlink $system_path/leakage"$i"_status
		done
		check_n_unlink $system_path/leakage_rope_status
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		check_n_unlink $config_path/port_config_done
		if [ ! -f "$config_path/asic_num" ]; then
			asic_num=1
		else
			asic_num=$(< $config_path/asic_num)
		fi
		for ((i=1; i<=asic_num; i+=1)); do
			/usr/bin/hw-management.sh chipdown "$i"
		done
	fi
	if [ "$2" == "cputemp" ]; then
		unlink $thermal_path/cpu_pack
		unlink $thermal_path/cpu_pack_crit
		unlink $thermal_path/cpu_pack_max
		unlink $alarm_path/cpu_pack_crit_alarm
		# Max index of SN2201 cputemp is 14.
		for i in {1..14}; do
			if [ -L $thermal_path/cpu_core"$i" ]; then
				j=$((i+1))
				unlink $thermal_path/cpu_core"$j"
				unlink $thermal_path/cpu_core"$j"_crit
				unlink $thermal_path/cpu_core"$j"_max
				unlink $alarm_path/cpu_core"$j"_crit_alarm
			fi
		done
	fi
	if [ "$2" == "pch_temp" ]; then
		unlink $thermal_path/pch_temp
	fi
	if [ "$2" == "sodimm_temp" ]; then
		find "$thermal_path" -iname "sodimm*_temp*" -exec unlink {} \;
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ] ||
	   [ "$2" == "psu3" ] || [ "$2" == "psu4" ]; then
		find_i2c_bus
		i2c_comex_mon_bus_default=$(< $i2c_comex_mon_bus_default_file)
		comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
		# PSU unit FAN speed set
		busdir=$(echo "$5""$3" |xargs dirname |xargs dirname)
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		# Verify if this is COMEX device
		if [ "$bus" == "$comex_bus" ]; then
			exit 0
		fi

		if [ -L $eeprom_path/"$2"_info ] && [ -f $config_path/"$2"_eeprom_us ]; then
			psu_addr=$(< $config_path/"$2"_i2c_addr)
			psu_eeprom_addr=$(printf '%02x\n' $((psu_addr - 8)))
			echo 0x$psu_eeprom_addr > /sys/class/i2c-dev/i2c-"$bus"/device/delete_device
			unlink $eeprom_path/"$2"_info
			rm -rf $config_path/"$2"_eeprom_us
		fi
		# Remove thermal attributes
		check_n_unlink $thermal_path/"$2"_temp
		check_n_unlink $thermal_path/"$2"_temp_max
		check_n_unlink $thermal_path/"$2"_temp_alarm
		check_n_unlink $thermal_path/"$2"_temp_max_alarm
		check_n_unlink $thermal_path/"$2"_temp2
		check_n_unlink $thermal_path/"$2"_temp2_max
		check_n_unlink $thermal_path/"$2"_temp2_max_alarm
		check_n_unlink $thermal_path/"$2"_fan1_speed_get
		check_n_unlink $alarm_path/"$2"_fan1_alarm
		check_n_unlink $alarm_path/"$2"_power1_alarm

		# Remove power attributes
		psu_disconnect_power_sensor "$2"_volt_in
		psu_disconnect_power_sensor "$2"_volt
		psu_disconnect_power_sensor "$2"_volt_out2
		psu_disconnect_power_sensor "$2"_power_in
		psu_disconnect_power_sensor "$2"_power
		psu_disconnect_power_sensor "$2"_curr_in
		psu_disconnect_power_sensor "$2"_curr

		rm -f $eeprom_path/"$2"_vpd
	fi
	if [ "$2" == "sxcore" ]; then
		/usr/bin/hw-management.sh chipdown 0 "$4/$5"
	fi
fi
