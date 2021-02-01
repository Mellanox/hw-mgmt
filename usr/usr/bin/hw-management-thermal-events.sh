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
fan_command=$config_path/fan_command
fan_psu_default=$config_path/fan_psu_default
events_path=$hw_management_path/events
max_psus=2
max_tachos=14
max_module_gbox_ind=160
i2c_bus_max=10
i2c_bus_offset=0
i2c_asic_bus_default=2
i2c_comex_mon_bus_default=$(< $config_path/i2c_comex_mon_bus_default)
fan_full_speed_code=20
LOCKFILE="/var/run/hw-management-thermal.lock"
udev_ready=$hw_management_path/.udev_ready

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
		name=$(< "$3""$4"/name)
		if [ ! -f "$config_path/gearbox_counter" ]; then
			echo 0 > $config_path/gearbox_counter
		fi
		if [ ! -f "$config_path/module_counter" ]; then
			echo 0 > $config_path/module_counter
		fi

		if [ "$name" == "mlxsw" ]; then
			ln -sf "$3""$4"/temp1_input $thermal_path/asic
			if [ -f "$3""$4"/pwm1 ]; then
				ln -sf "$3""$4"/pwm1 $thermal_path/pwm1
				echo "$name" > $config_path/cooling_name
			fi
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
					if [ -f $config_path/fan_min_speed ]; then
						ln -sf $config_path/fan_min_speed $thermal_path/fan"$j"_min
					fi
					if [ -f $config_path/fan_max_speed ]; then
						ln -sf $config_path/fan_max_speed $thermal_path/fan"$j"_max
					fi
					# Save max_tachos to config
					echo $i > $config_path/max_tachos
				fi
			done
			for ((i=2; i<=max_module_gbox_ind; i+=1)); do
				if [ -f "$3""$4"/temp"$i"_input ]; then
					label=$(< "$3""$4"/temp"$i"_label)
					case $label in
					*front*)
						j=$((i-1))
						ln -sf "$3""$4"/temp"$i"_input $thermal_path/module"$j"_temp_input
						ln -sf "$3""$4"/temp"$i"_fault $thermal_path/module"$j"_temp_fault
						ln -sf "$3""$4"/temp"$i"_crit $thermal_path/module"$j"_temp_crit
						ln -sf "$3""$4"/temp"$i"_emergency $thermal_path/module"$j"_temp_emergency
						lock_service_state_change
						[ -f "$config_path/module_counter" ] && module_counter=$(< $config_path/module_counter)
						module_counter=$((module_counter+1))
						echo "$module_counter" > $config_path/module_counter
						unlock_service_state_change
						;;
					*gear*)
						lock_service_state_change
						[ -f "$config_path/gearbox_counter" ] && gearbox_counter=$(< $config_path/gearbox_counter)
						gearbox_counter=$((gearbox_counter+1))
						echo "$gearbox_counter" > $config_path/gearbox_counter
						unlock_service_state_change
						ln -sf "$3""$4"/temp"$i"_input $thermal_path/gearbox"$gearbox_counter"_temp_input
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
				if [ -f $config_path/fan_min_speed ]; then
					ln -sf $config_path/fan_min_speed $thermal_path/fan"$j"_min
				fi
				if [ -f $config_path/fan_max_speed ]; then
					ln -sf $config_path/fan_max_speed $thermal_path/fan"$j"_max
				fi
				#save max_tachos to config
				echo $i > $config_path/max_tachos
			fi
		done
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=$(< "$3""$4"/type)
		zonep0type="${zonetype:0:${#zonetype}-1}"
		zonep1type="${zonetype:0:${#zonetype}-2}"
		zonep2type="${zonetype:0:${#zonetype}-3}"
		if [ "$zonetype" == "mlxsw" ] ||
		   [ "$zonep0type" == "mlxsw-module" ] ||
		   [ "$zonep1type" == "mlxsw-module" ] ||
		   [ "$zonep2type" == "mlxsw-module" ] ||
		   [ "$zonep0type" == "mlxsw-gearbox" ] ||
		   [ "$zonep1type" == "mlxsw-gearbox" ] ||
		   [ "$zonep2type" == "mlxsw-gearbox" ]; then
			mkdir $thermal_path/"$zonetype"
			ln -sf "$3""$4"/mode $thermal_path/"$zonetype"/thermal_zone_mode
			ln -sf "$3""$4"/policy $thermal_path/"$zonetype"/thermal_zone_policy
			ln -sf "$3""$4"/trip_point_0_temp $thermal_path/"$zonetype"/temp_trip_norm
			ln -sf "$3""$4"/trip_point_1_temp $thermal_path/"$zonetype"/temp_trip_high
			ln -sf "$3""$4"/trip_point_2_temp $thermal_path/"$zonetype"/temp_trip_hot
			ln -sf "$3""$4"/trip_point_3_temp $thermal_path/"$zonetype"/temp_trip_crit
			ln -sf "$3""$4"/temp $thermal_path/"$zonetype"/thermal_zone_temp
			if [ -f "$3""$4"/emul_temp ]; then
				ln -sf "$3""$4"/emul_temp $thermal_path/"$zonetype"/thermal_zone_temp_emul
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
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		if [ -f "$3""$4"/uevent ]; then
			ln -sf "$3""$4"/uevent $config_path/port_config_done
		fi
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
		sodimm_i2c_addr=$(echo "$3"|xargs dirname|xargs dirname|xargs basename)
		case $sodimm_i2c_addr in
			0-001c|0-001e)
				sodimm_name=sodimm2_temp
			;;
			*)
				sodimm_name=sodimm1_temp
			;;
		esac
		find "$5""$3" -iname 'temp1_*' -exec sh -c 'ln -sf $1 $2/$3$(basename $1| cut -d1 -f2)' _ {} "$thermal_path" "$sodimm_name" \;
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
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
		if [ -f "$5""$3"/temp2_input ]; then
			ln -sf "$5""$3"/temp2_input $thermal_path/"$2"_temp2
		fi
		if [ -f "$5""$3"/temp2_max ]; then
			ln -sf "$5""$3"/temp2_max $thermal_path/"$2"_temp2_max
		fi
		if [ -f "$5""$3"/temp2_max_alarm ]; then
			ln -sf "$5""$3"/temp2_max_alarm $thermal_path/"$2"_temp2_max_alarm
		fi
		if [ -f "$5""$3"/fan1_alarm ]; then
			ln -sf "$5""$3"/fan1_alarm $alarm_path/"$2"_fan1_alarm
		fi
		if [ -f "$5""$3"/power1_alarm ]; then
			ln -sf "$5""$3"/power1_alarm $alarm_path/"$2"_power1_alarm
		fi
		ln -sf "$5""$3"/fan1_input $thermal_path/"$2"_fan1_speed_get
		# Add power attributes
		ln -sf "$5""$3"/in1_input $power_path/"$2"_volt_in
		ln -sf "$5""$3"/in2_input $power_path/"$2"_volt
		if [ -f "$5""$3"/in3_input ]; then
			ln -sf "$5""$3"/in3_input $power_path/"$2"_volt_out2
		else
			in2_label=$(< "$5""$3"/in2_label)
			if [ "$in2_label" == "vout1" ]; then
				ln -sf "$5""$3"/in2_input $power_path/"$2"_volt_out
			fi
		fi
		ln -sf "$5""$3"/power1_input $power_path/"$2"_power_in
		ln -sf "$5""$3"/power2_input $power_path/"$2"_power
		ln -sf "$5""$3"/curr1_input $power_path/"$2"_curr_in
		ln -sf "$5""$3"/curr2_input $power_path/"$2"_curr

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
			#EEPROM VPD
			hw-management-read-ps-eeprom.sh --conv --psu_eeprom $eeprom_path/"$2"_info > $eeprom_path/"$2"_vpd
			if [ $? -ne 0 ]; then
				#EEPROM failed
				echo "Failed to read PSU VPD" > $eeprom_path/"$2"_vpd
			else
				#Add PSU FAN speed info
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
		if [ -L $thermal_path/asic ]; then
			unlink $thermal_path/asic
		fi
		name=$(< $$config_path/cooling_name)
		if [ "$name" == "mlxsw" ]; then
			if [ -L $thermal_path/pwm1 ]; then
				unlink $thermal_path/pwm1
			fi
			for ((i=1; i<=max_tachos; i+=1)); do
				if [ -L $thermal_path/fan"$i"_fault ]; then
					unlink $thermal_path/fan"$i"_fault
				fi
				if [ -L $thermal_path/fan"$i"_speed_get ]; then
					unlink $thermal_path/fan"$i"_speed_get
				fi
				if [ -L $thermal_path/fan"$j"_min ]; then
					unlink $thermal_path/fan"$j"_min
				fi
				if [ -L $thermal_path/fan"$j"_max ]; then
					unlink $thermal_path/fan"$j"_max
				fi
			done
			if [ -L $thermal_path/pwm1 ]; then
				unlink $thermal_path/pwm1
			fi
		fi
		for ((i=max_module_gbox_ind; i>=2; i-=1)); do
			j=$((i-1))
			if [ -L $thermal_path/module"$j"_temp_input ]; then
				unlink $thermal_path/module"$j"_temp_input
				lock_service_state_change
				[ -f "$config_path/module_counter" ] && module_counter=$(< $config_path/module_counter)
				module_counter=$((module_counter-1))
				echo $module_counter > $config_path/module_counter
				unlock_service_state_change
			fi
			if [ -L $thermal_path/module"$j"_temp_fault ]; then
				unlink $thermal_path/module"$j"_temp_fault
			fi
			if [ -L $thermal_path/module"$j"_temp_crit ]; then
				unlink $thermal_path/module"$j"_temp_crit
			fi
			if [ -L $thermal_path/module"$j"_temp_emergency ]; then
				unlink $thermal_path/module"$j"_temp_emergency
			fi
		done
		find /var/run/hw-management/thermal/ -type l -name '*_temp_input' -exec rm {} +
		find /var/run/hw-management/thermal/ -type l -name '*_temp_fault' -exec rm {} +
		find /var/run/hw-management/thermal/ -type l -name '*_temp_crit' -exec rm {} +
		find /var/run/hw-management/thermal/ -type l -name '*_temp_emergency' -exec rm {} +
		echo 0 > $config_path/module_counter
		echo 0 > $config_path/gearbox_counter
	fi
	if [ "$2" == "regfan" ]; then
		if [ -L $thermal_path/pwm1 ]; then
			unlink $thermal_path/pwm1
		fi
		for ((i=1; i<=max_tachos; i+=1)); do
			if [ -L $thermal_path/fan"$i"_fault ]; then
				unlink $thermal_path/fan"$i"_fault
			fi
			if [ -L $thermal_path/fan"$i"_speed_get ]; then
				unlink $thermal_path/fan"$i"_speed_get
			fi
			if [ -L $thermal_path/fan"$i"_speed_set ]; then
				unlink $thermal_path/fan"$i"_speed_set
			fi
			if [ -L $thermal_path/fan"$i"_min ]; then
				unlink $thermal_path/fan"$i"_min
			fi
			if [ -L $thermal_path/fan"$i"_max ]; then
				unlink $thermal_path/fan"$i"_max
			fi
		done
	fi
	if [ "$2" == "thermal_zone" ]; then
		[ -f "$config_path/stopping" ] && stopping=$(< $config_path/stopping)
		if [ "$stopping" ] &&  [ "$stopping" = "1" ]; then
			exit 0
		fi
		for ((i=1; i<max_module_gbox_ind; i+=1)); do
			if [ -d $thermal_path/mlxsw-module"$i" ]; then
				rm -rf $thermal_path/mlxsw-module"$i"
			elif [ -d $thermal_path/mlxsw-gearbox"$i" ]; then
				rm -rf $thermal_path/mlxsw-gerabox"$i"
			fi
		done
		if [ -d $thermal_path/mlxsw ]; then
			rm -rf $thermal_path/mlxsw
		fi
		if [ -L $thermal_path/highest_thermal_zone ]; then
			unlink $thermal_path/highest_thermal_zone
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		if [ -L $thermal_path/cooling_cur_state ]; then
			unlink $thermal_path/cooling_cur_state
		fi
	fi
	if [ "$2" == "hotplug" ]; then
		for ((i=1; i<=max_tachos; i+=1)); do
			if [ -L $thermal_path/fan"$i"_status ]; then
				unlink $thermal_path/fan"$i"_status
			fi
		done
		for ((i=1; i<=max_psus; i+=1)); do
			if [ -L $thermal_path/psu"$i"_status ]; then
				unlink $thermal_path/psu"$i"_status
			fi
			if [ -L $thermal_path/psu"$i"_pwr_status ]; then
				unlink $thermal_path/psu"$i"_pwr_status
			fi
		done
		if [ -d /sys/module/mlxsw_pci ]; then
			exit 0
		fi
		if [ -L $config_path/port_config_done ]; then
			unlink $config_path/port_config_done
		fi
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
		sodimm_i2c_addr=$(echo "$3"|xargs dirname|xargs dirname|xargs basename)
		case $sodimm_i2c_addr in
			0-001c|0-001e)
				sodimm_name=sodimm2_temp
			;;
			*)
				sodimm_name=sodimm1_temp
			;;
		esac
		find "$thermal_path" -iname "$sodimm_name*" -exec unlink {} \;
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
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
		if [ -L $thermal_path/"$2"_temp ]; then
			unlink $thermal_path/"$2"_temp
		fi
		if [ -L $thermal_path/"$2"_temp_max ]; then
			unlink $thermal_path/"$2"_temp_max
		fi
		if [ -L $thermal_path/"$2"_temp_alarm ]; then
			unlink $thermal_path/"$2"_temp_alarm
		fi
		if [ -L $thermal_path/"$2"_temp_max_alarm ]; then
			unlink $thermal_path/"$2"_temp_max_alarm
		fi
		if [ -L $thermal_path/"$2"_temp2 ]; then
			unlink $thermal_path/"$2"_temp2
		fi
		if [ -L $thermal_path/"$2"_temp2_max ]; then
			unlink $thermal_path/"$2"_temp2_max
		fi
		if [ -L $thermal_path/"$2"_temp2_max_alarm ]; then
			unlink $thermal_path/"$2"_temp2_max_alarm
		fi
		if [ -L $alarm_path/"$2"_fan1_alarm ]; then
			unlink $alarm_path/"$2"_fan1_alarm
		fi
		if [ -L $alarm_path/"$2"_power1_alarm ]; then
			unlink $alarm_path/"$2"_power1_alarm
		fi
		if [ -L $thermal_path/"$2"_fan1_speed_get ]; then
			unlink $thermal_path/"$2"_fan1_speed_get
		fi
		# Remove power attributes
		if [ -L $power_path/"$2"_volt_in ]; then
			unlink $power_path/"$2"_volt_in
		fi
		if [ -L $power_path/"$2"_volt ]; then
			unlink $power_path/"$2"_volt
		fi
		if [ -L $power_path/"$2"_volt_out2 ]; then
			unlink $power_path/"$2"_volt_out2
		fi
		if [ -L $power_path/"$2"_power_in ]; then
			unlink $power_path/"$2"_power_in
		fi
		if [ -L $power_path/"$2"_power ]; then
			unlink $power_path/"$2"_power
		fi
		if [ -L $power_path/"$2"_curr_in ]; then
			unlink $power_path/"$2"_curr_in
		fi
		if [ -L $power_path/"$2"_curr ]; then
			unlink $power_path/"$2"_curr
		fi
		rm -f $eeprom_path/"$2"_vpd
	fi
	if [ "$2" == "sxcore" ]; then
		/usr/bin/hw-management.sh chipdown
	fi
fi
