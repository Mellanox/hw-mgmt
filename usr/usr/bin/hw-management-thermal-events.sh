#!/bin/bash

########################################################################
# Copyright (c) 2018 Mellanox Technologies. All rights reserved.
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

# Local variables
hw_management_path=/var/run/hw-management
thermal_path=$hw_management_path/thermal
eeprom_path=$hw_management_path/eeprom
power_path=$hw_management_path/power
alarm_path=$hw_management_path/alarm
config_path=$hw_management_path/config
system_path=$hw_management_path/system
fan_command=$config_path/fan_command
fan_psu_default=$config_path/fan_psu_default
events_path=$hw_management_path/events
max_psus=4
max_tachos=14
max_lcs=8
min_module_gbox_ind=2
max_module_gbox_ind=160
min_lc_thermal_ind=1
max_lc_thermal_ind=20
i2c_bus_max=10
i2c_bus_offset=0
i2c_asic_bus_default=2
i2c_comex_mon_bus_default=$(< $config_path/i2c_comex_mon_bus_default)
fan_full_speed_code=20
LOCKFILE="/var/run/hw-management-thermal.lock"
udev_ready=$hw_management_path/.udev_ready
IVB_CPU=0x63A
RNG_CPU=0x64D
BDW_CPU=0x656
CFL_CPU=0x69E
cpu_type=

log_err()
{
	logger -t hw-management -p daemon.err "$@"
}

log_info()
{
	logger -t hw-management -p daemon.info "$@"
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

	log_err "i2c-mlxcpld driver is not loaded"
	exit 0
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

# Get line card number by module 'sysfs' device path
# $1 - sys device path in, example: /sys/devices/platform/mlxplat/i2c_mlxcpld.1/i2c-1/i2c-3/3-0037/hwmon/hwmon<n>/
# return line card number 1..8 or 0 in ASIC case
get_lc_id_hwmon()
{
	sysfs_path=$1
	name=$(< "$sysfs_path"/name)
	regex="mlxsw-lc([0-9]+)"
	[[ $name =~ $regex ]]
	if [[ -z "${BASH_REMATCH[1]}" ]]; then
		return 0
	else
		return "${BASH_REMATCH[1]}"
	fi
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

if [ "$1" == "add" ]; then
	# Don't process udev events until service is started and directories are created
	if [ ! -f ${udev_ready} ]; then
		exit 0
	fi
	if [ "$2" == "fan_amb" ] || [ "$2" == "port_amb" ]; then
		# Verify if this is COMEX sensor
		find_i2c_bus
		comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
		# Verify if this is ASIC sensor
		asic_bus=$((i2c_asic_bus_default+i2c_bus_offset))
		busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		if [ "$bus" == "$comex_bus" ]; then
			ln -sf "$3""$4"/temp1_input $thermal_path/comex_amb
		elif [ "$bus" == "$asic_bus" ]; then
			exit 0
		else
			ln -sf "$3""$4"/temp1_input $thermal_path/"$2"
		fi
	fi
	if [ "$2" == "switch" ]; then
		get_lc_id_hwmon "$3$4"
		lc_number=$?
		if [ "$lc_number" -ne 0 ]; then
			cpath="$hw_management_path/lc$lc_id/config"
			tpath="$hw_management_path/lc$lc_id/thermal"
			min_module_ind=$min_lc_thermal_ind
			max_module_ind=$max_lc_thermal_ind
		else
			cpath="$config_path"
			tpath="$thermal_path"
			min_module_ind=$min_module_gbox_ind
			max_module_ind=$max_module_gbox_ind
		fi

		name=$(< "$3""$4"/name)
		if [ ! -f "$cpath/gearbox_counter" ]; then
			echo 0 > "$cpath"/gearbox_counter
		fi
		if [ ! -f "$cpath/module_counter" ]; then
			echo 0 > "$cpath"/module_counter
		fi

		if [ "$name" == "mlxsw" ]; then
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
		if [ "$name" == "mlxsw" ] ||  [ "$name" == "mlxsw-lc" ] ; then
			for ((i=min_module_ind; i<=max_module_ind; i+=1)); do
				if [ -f "$3""$4"/temp"$i"_input ]; then
					label=$(< "$3""$4"/temp"$i"_label)
					case $label in
					*front*)
						j=$((i-1))
						ln -sf "$3""$4"/temp"$i"_input "$tpath"/module"$j"_temp_input
						ln -sf "$3""$4"/temp"$i"_fault "$tpath"/module"$j"_temp_fault
						ln -sf "$3""$4"/temp"$i"_crit "$tpath"/module"$j"_temp_crit
						ln -sf "$3""$4"/temp"$i"_emergency "$tpath"/module"$j"_temp_emergency
						lock_service_state_change
						[ -f "$cpath/module_counter" ] && module_counter=$(< "$cpath"/module_counter)
						module_counter=$((module_counter+1))
						echo "$module_counter" > "$cpath"/module_counter
						unlock_service_state_change
						;;
					*gear*)
						lock_service_state_change
						[ -f "$cpath/gearbox_counter" ] && gearbox_counter=$(< "$cpath"/gearbox_counter)
						gearbox_counter=$((gearbox_counter+1))
						echo "$gearbox_counter" > "$cpath"/gearbox_counter
						unlock_service_state_change
						ln -sf "$3""$4"/temp"$i"_input "$tpath"/gearbox"$gearbox_counter"_temp_input
						;;
					*)
						;;
					esac
				fi
			done
		fi
	fi
	if [ "$2" == "regfan" ]; then
		name=$(< "$3""$4"/name)
		echo "$name" > $config_path/cooling_name
		ln -sf "$3""$4"/pwm1 $thermal_path/pwm1
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
				#save max_tachos to config
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
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=$(< "$3""$4"/type)
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ]; then
			ln -sf "$3""$4"/cur_state $thermal_path/cooling_cur_state
			# Set FAN to full speed until thermal control is started.
			echo $fan_full_speed_code > $thermal_path/cooling_cur_state
			log_info "FAN speed is set to full speed"
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
			fi
		done
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
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			if [ -f "$3""$4"/lc"$i"_powered ]; then
				ln -sf "$3""$4"/lc"$i"_powered $system_path/lc"$i"_powered
				event=$(< $system_path/lc"$i"_powered)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_powered
				fi
			fi
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			if [ -f "$3""$4"/lc"$i"_present ]; then
				ln -sf "$3""$4"/lc"$i"_present $system_path/lc"$i"_present
				event=$(< $system_path/lc"$i"_present)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_present
				fi
			fi
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			if [ -f "$3""$4"/lc"$i"_ready ]; then
				ln -sf "$3""$4"/lc"$i"_ready $system_path/lc"$i"_ready
				event=$(< $system_path/lc"$i"_ready)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_ready
				fi
			fi
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			if [ -f "$3""$4"/lc"$i"_shutdown ]; then
				ln -sf "$3""$4"/lc"$i"_shutdown $system_path/lc"$i"_shutdown
				event=$(< $system_path/lc"$i"_shutdown)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_shutdown
				fi
			fi
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			if [ -f "$3""$4"/lc"$i"_synced ]; then
				ln -sf "$3""$4"/lc"$i"_synced $system_path/lc"$i"_synced
				event=$(< $system_path/lc"$i"_synced)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_synced
				fi
			fi
		done
		for ((i=1; i<=max_lcs; i+=1)); do
			if [ -f "$3""$4"/lc"$i"_verified ]; then
				ln -sf "$3""$4"/lc"$i"_verified $system_path/lc"$i"_verified
				event=$(< $system_path/lc"$i"_verified)
				if [ "$event" -eq 1 ]; then
					echo 1 > $events_path/lc"$i"_verified
				fi
			fi
		done
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		check_n_link "$3""$4"/uevent $config_path/port_config_done
		asic_health=$(< "$3""$4"/asic1)
		if [ "$asic_health" -ne 2 ]; then
			exit 0
		fi
		find_i2c_bus
		bus=$((i2c_asic_bus_default+i2c_bus_offset))
		if [ ! -d /sys/module/mlxsw_minimal ]; then
			modprobe mlxsw_minimal
		fi
		if [ ! -f /etc/init.d/sxdkernel ]; then
			/usr/bin/hw-management.sh chipup
		fi
	fi
	if [ "$2" == "cputemp" ]; then
		for i in {1..9}; do
			if [ -f "$3""$4"/temp"$i"_input ]; then
				if [ $i -eq 1 ]; then
					name="pack"
				else
					id=$((i-2))
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
		find_i2c_bus
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
		ln -sf "$5""$3"/temp1_input $thermal_path/"$2"_temp
		ln -sf "$5""$3"/temp1_max $thermal_path/"$2"_temp_max
		ln -sf "$5""$3"/temp1_max_alarm $thermal_path/"$2"_temp_max_alarm
		check_n_link "$5""$3"/temp2_input $thermal_path/"$2"_temp2
		check_n_link "$5""$3"/temp2_max $thermal_path/"$2"_temp2_max
		check_n_link "$5""$3"/temp2_max_alarm $thermal_path/"$2"_temp2_max_alarm
		check_n_link "$5""$3"/fan1_alarm $alarm_path/"$2"_fan1_alarm
		check_n_link "$5""$3"/power1_alarm $alarm_path/"$2"_power1_alarm
		ln -sf "$5""$3"/fan1_input $thermal_path/"$2"_fan1_speed_get

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

		if [ ! -f $config_path/"$2"_i2c_addr ]; then
			exit 0
		fi

		psu_addr=$(< $config_path/"$2"_i2c_addr)
		psu_eeprom_addr=$((${psu_addr:2:2}-8))
		eeprom_name=$2_info
		eeprom_file=/sys/devices/platform/mlxplat/i2c_mlxcpld.1/i2c-1/i2c-$bus/$bus-00$psu_eeprom_addr/eeprom
		# Verify if PS unit is equipped with EEPROM. If yes – connect driver.
		i2cget -f -y "$bus" 0x$psu_eeprom_addr 0x0 > /dev/null 2>&1
		if [ $? -eq 0 ] && [ ! -L $eeprom_path/"$2"_info ] && [ ! -f "$eeprom_file" ]; then
			psu_eeprom_type="24c32"
			if [ -f $config_path/psu_eeprom_type ]; then
				psu_eeprom_type=$(< "$config_path"/psu_eeprom_type)
			fi
			echo "$psu_eeprom_type" 0x"$psu_eeprom_addr" > /sys/class/i2c-dev/i2c-"$bus"/device/new_device
			ln -sf "$eeprom_file" "$eeprom_path"/"$eeprom_name" 2>/dev/null
			chmod 400 "$eeprom_path"/"$eeprom_name" 2>/dev/null
			echo 1 > $config_path/"$2"_eeprom_us
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
			else
				# Add PSU FAN speed info.
				if [ -f $config_path/psu_fan_max ]; then
					echo -ne MAX_RPM: >> $eeprom_path/"$2"_vpd
					cat $config_path/psu_fan_max >> $eeprom_path/"$2"_vpd
				fi
				if [ -f $config_path/psu_fan_min ]; then
					echo -ne MIN_RPM: >> $eeprom_path/"$2"_vpd
					cat $config_path/psu_fan_min >> $eeprom_path/"$2"_vpd
				fi
			fi
		fi

	fi
	if [ "$2" == "sxcore" ]; then
		if [ ! -d /sys/module/mlxsw_minimal ]; then
			modprobe mlxsw_minimal
		fi
		/usr/bin/hw-management.sh chipup
	fi
elif [ "$1" == "change" ]; then
	if [ "$2" == "hotplug_asic" ]; then
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		if [ "$3" == "up" ]; then
			if [ ! -d /sys/module/mlxsw_minimal ]; then
				modprobe mlxsw_minimal
			fi
			if [ ! -f /etc/init.d/sxdkernel ]; then
				/usr/bin/hw-management.sh chipup
			fi
		elif [ "$3" == "down" ]; then
			/usr/bin/hw-management.sh chipdown
		else
			asic_health=$(< "$4""$5"/asic1)
			if [ "$asic_health" -eq 2 ]; then
				if [ ! -f /etc/init.d/sxdkernel ]; then
					/usr/bin/hw-management.sh chipup
				fi
			else
				/usr/bin/hw-management.sh chipdown
			fi
		fi
	fi
else
	if [ "$2" == "fan_amb" ] || [ "$2" == "port_amb" ]; then
		# Verify if this is COMEX sensor
		find_i2c_bus
		comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
		# Verify if this is ASIC sensor
		asic_bus=$((i2c_asic_bus_default+i2c_bus_offset))
		busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		if [ "$bus" == "$comex_bus" ]; then
			unlink $thermal_path/comex_amb
		elif [ "$bus" == "$asic_bus" ]; then
			exit 0
		else
			unlink $thermal_path/$
		fi
	fi
	if [ "$2" == "switch" ]; then
		[ -f "$config_path/stopping" ] && stopping=$(< $config_path/stopping)
		if [ "$stopping" ] &&  [ "$stopping" = "1" ]; then
			exit 0
		fi
		
		get_lc_id_hwmon "$3$4"
		lc_id$?		
		if [ "$lc_id" -ne 0 ]; then
			cpath="$hw_management_path/lc$lc_id/config"
			tpath="$hw_management_path/lc$lc_id/thermal"
		else
			cpath="$config_path"
			tpath="$thermal_path"
		fi
		
		for ((i=max_module_gbox_ind; i>=2; i-=1)); do
			j=$((i-1))
			if [ -L $tpath/module"$j"_temp_input ]; then
				unlink $tpath/module"$j"_temp_input
				lock_service_state_change
				[ -f "$cpath/module_counter" ] && module_counter=$(< "$cpath"/module_counter)
				module_counter=$((module_counter-1))
				echo $module_counter > "$cpath"/module_counter
				unlock_service_state_change
			fi
			check_n_unlink $tpath/module"$j"_temp_fault
			check_n_unlink $tpath/module"$j"_temp_crit
			check_n_unlink $tpath/module"$j"_temp_emergency
		done
		find "$tpath" -type l -name '*_temp_input' -exec rm {} +
		find "$tpath" -type l -name '*_temp_fault' -exec rm {} +
		find "$tpath" -type l -name '*_temp_crit' -exec rm {} +
		find "$tpath" -type l -name '*_temp_emergency' -exec rm {} +
		echo 0 > $cpath/module_counter
		echo 0 > $cpath/gearbox_counter

		if [ "$lc_id" -ne 0 ]; then
			exit 0
		fi
		check_n_unlink $thermal_path/asic
		name=$(< $$config_path/cooling_name)
		if [ "$name" == "mlxsw" ]; then
			if [ -L $thermal_path/pwm1 ]; then
				unlink $thermal_path/pwm1
			fi
			for ((i=1; i<=max_tachos; i+=1)); do
				check_n_unlink $thermal_path/fan"$i"_fault
				check_n_unlink $thermal_path/fan"$i"_speed_get
				check_n_unlink $thermal_path/fan"$j"_min
				check_n_unlink $thermal_path/fan"$j"_max
			done
			check_n_unlink $thermal_path/pwm1
		fi
	fi
	if [ "$2" == "regfan" ]; then
		if [ -L $thermal_path/pwm1 ]; then
			unlink $thermal_path/pwm1
		fi
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
				rm -rf $tpath/mlxsw-gerabox"$i"
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
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		check_n_unlink $config_path/port_config_done
		/usr/bin/hw-management.sh chipdown
	fi
	if [ "$2" == "cputemp" ]; then
		unlink $thermal_path/cpu_pack
		unlink $thermal_path/cpu_pack_crit
		unlink $thermal_path/cpu_pack_max
		unlink $alarm_path/cpu_pack_crit_alarm
		for i in {1..8}; do
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
			psu_eeprom_addr=$((${psu_addr:2:2}-8))
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
		/usr/bin/hw-management.sh chipdown
	fi
fi
