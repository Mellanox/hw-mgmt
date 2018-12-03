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

. /lib/lsb/init-functions

# Local variables
hw_management_path=/var/run/hw-management
thermal_path=$hw_management_path/thermal
power_path=$hw_management_path/power
config_path=$hw_management_path/config
fan_command=$config_path/fan_command
fan_psu_default=$config_path/fan_psu_default
max_psus=2
max_tachos=12
max_modules_ind=65
i2c_bus_max=10
i2c_bus_offset=0
i2c_asic_bus_default=2

find_i2c_bus()
{
	# Find physical bus number of Mellanox I2C controller. The default
	# number is 1, but it could be assigned to others id numbers on
	# systems with different CPU types.
	for ((i=1; i<$i2c_bus_max; i++)); do
		folder=/sys/bus/i2c/devices/i2c-$i
		if [ -d $folder ]; then
			name=`cat $folder/name | cut -d' ' -f 1`
			if [ "$name" == "i2c-mlxcpld" ]; then
				i2c_bus_offset=$(($i-1))
				return
			fi
		fi
	done

	log_failure_msg "i2c-mlxcpld driver is not loaded"
	exit 0
}

if [ "$1" == "add" ]; then
	if [ "$2" == "fan_amb" ] || [ "$2" == "port_amb" ]; then
		ln -sf $3$4/temp1_input $thermal_path/$2
	fi
	if [ "$2" == "switch" ]; then
		name=`cat $3$4/name`
		if [ "$name" == "mlxsw" ]; then
			ln -sf $3$4/temp1_input $thermal_path/temp1_input_asic
			ln -sf $3$4/pwm1 $thermal_path/pwm1

			if [ -f $config_path/fan_inversed ]; then
				inv=`cat $config_path/fan_inversed`
			fi
			for ((i=1; i<=$max_tachos; i+=1)); do
				if [ -z "$inv" ] || [ ${inv} -eq 0 ]; then
					j=$i
				else
					j=`echo $(($inv - $i))`
				fi
				if [ -f $3$4/fan"$i"_fault ]; then
					ln -sf $3$4/fan"$i"_fault $thermal_path/fan"$j"_fault
				fi
				if [ -f $3$4/fan"$i"_input ]; then
					ln -sf $3$4/fan"$i"_input $thermal_path/fan"$j"_input
					if [ -f $config_path/fan_min_speed ]; then
						ln -sf $config_path/fan_min_speed $thermal_path/fan"$j"_min
					fi
					if [ -f $config_path/fan_max_speed ]; then
						ln -sf $config_path/fan_max_speed $thermal_path/fan"$j"_max
					fi
				fi
			done
			for ((i=2; i<=$max_modules_ind; i+=1)); do
				if [ -f $3$4/temp"$i"_input ]; then
					j=$(($i-1))
					ln -sf $3$4/temp"$i"_input $thermal_path/temp_input_module"$j"
					ln -sf $3$4/temp"$i"_fault $thermal_path/temp_fault_module"$j"
					ln -sf $3$4/temp"$i"_crit $thermal_path/temp_crit_module"$j"
					ln -sf $3$4/temp"$i"_emergency $thermal_path/temp_emergency_module"$j"
				fi
			done
		fi
	fi
	if [ "$2" == "regfan" ]; then
		ln -sf $3$4/pwm1 $thermal_path/pwm1
		if [ -f $config_path/fan_inversed ]; then
			inv=`cat $config_path/fan_inversed`
		fi
		for ((i=1; i<=$max_tachos; i+=1)); do
			if [ -z "$inv" ] || [ ${inv} -eq 0 ]; then
				j=$i
			else
				j=`echo $(($inv - $i))`
			fi
			if [ -f $3$4/fan"$i"_fault ]; then
				ln -sf $3$4/fan"$i"_fault $thermal_path/fan"$j"_fault
			fi
			if [ -f $3$4/fan"$i"_input ]; then
				ln -sf $3$4/fan"$i"_input $thermal_path/fan"$j"_input
			fi
			if [ -f $config_path/fan_min_speed ]; then
				ln -sf $config_path/fan_min_speed $thermal_path/fan"$j"_min
			fi
			if [ -f $config_path/fan_max_speed ]; then
				ln -sf $config_path/fan_max_speed $thermal_path/fan"$j"_max
			fi
		done
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		zonep0type="${zonetype:0:${#zonetype}-1}"
		zonep1type="${zonetype:0:${#zonetype}-2}"
		zonep2type="${zonetype:0:${#zonetype}-3}"
		if [ "$zonetype" == "mlxsw" ] || [ "$zonep0type" == "mlxsw-module" ] ||
		   [ "$zonep1type" == "mlxsw-module" ] || [ "$zonep2type" == "mlxsw-module" ]; then
			mkdir -p $thermal_path/$zonetype
			ln -sf $3$4/mode $thermal_path/$zonetype/thermal_zone_mode
			ln -sf $3$4/policy $thermal_path/$zonetype/thermal_zone_policy
			ln -sf $3$4/trip_point_0_temp $thermal_path/$zonetype/temp_trip_norm
			ln -sf $3$4/trip_point_1_temp $thermal_path/$zonetype/temp_trip_high
			ln -sf $3$4/trip_point_2_temp $thermal_path/$zonetype/temp_trip_hot
			ln -sf $3$4/trip_point_3_temp $thermal_path/$zonetype/temp_trip_crit
			ln -sf $3$4/temp $thermal_path/$zonetype/thermal_zone_temp
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ]; then
			ln -sf $3$4/cur_state $thermal_path/cooling_cur_state
		fi
	fi
	if [ "$2" == "hotplug" ]; then
		for ((i=1; i<=$max_tachos; i+=1)); do
			if [ -f $3$4/fan$i ]; then
				ln -sf $3$4/fan$i $thermal_path/fan"$i"_status
			fi
		done
		for ((i=1; i<=$max_psus; i+=1)); do
			if [ -f $3$4/psu$i ]; then
				ln -sf $3$4/psu$i $thermal_path/psu"$i"_status
			fi
			if [ -f $3$4/pwr$i ]; then
				ln -sf $3$4/pwr$i $power_path/psu"$i"_pwr_status
			fi
		done
		if [ -d /sys/module/mlxsw_pci ]; then
			return
		fi
		asic_health=`cat $3$4/asic1`
		if [ $asic_health -ne 2 ]; then
			return
		fi
		find_i2c_bus
		bus=$(($i2c_asic_bus_default+$i2c_bus_offset))
		path=/sys/bus/i2c/devices/i2c-$bus
		if [ ! -d /sys/module/mlxsw_minimal ]; then
			modprobe mlxsw_minimal
		fi
		if [ ! -d /sys/bus/i2c/devices/$bus-0048 ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-00048 ]; then
			echo mlxsw_minimal 0x48 > $path/new_device
		fi
  	fi
	if [ "$2" == "cputemp" ]; then
		for i in {1..9}; do
			if [ -f $3$4/temp"$i"_input ]; then
				if [ $i -eq 1 ]; then
					name="pack"
				else
					id=$(($i-2))
					name="core$id"
				fi
				ln -sf $3$4/temp"$i"_input $thermal_path/cpu_$name
				ln -sf $3$4/temp"$i"_crit $thermal_path/cpu_"$name"_crit
				ln -sf $3$4/temp"$i"_crit_alarm $thermal_path/cpu_"$name"_crit_alarm
				ln -sf $3$4/temp"$i"_max $thermal_path/cpu_"$name"_max
			fi
		done
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
		# PSU unit FAN speed set
		busdir=`echo $5$3 |xargs dirname |xargs dirname`
		busfolder=`basename $busdir`
		bus="${busfolder:0:${#busfolder}-5}"
		# Set default fan speed
		addr=`cat $config_path/psu"$i"_i2c_addr`
		command=`cat $fan_command`
		speed=`cat $fan_psu_default`
		i2cset -f -y $bus $addr $command $speed wp
		# Set I2C bus for psu
		echo $bus > $config_path/"$2"_i2c_bus
		# Add thermal attributes
		ln -sf $5$3/temp1_input $thermal_path/$2_temp
		ln -sf $5$3/temp1_max $thermal_path/$2_temp_max
		ln -sf $5$3/temp1_max_alarm $thermal_path/$2_temp_alarm
		ln -sf $5$3/fan1_input $thermal_path/$2_fan1_speed_get
		# Add power attributes
		ln -sf $5$3/in1_input $power_path/$2_volt_in
		ln -sf $5$3/in2_input $power_path/$2_volt
		ln -sf $5$3/power1_input $power_path/$2_power_in
		ln -sf $5$3/power2_input $power_path/$2_power
		ln -sf $5$3/curr1_input $power_path/$2_curr_in
		ln -sf $5$3/curr2_input $power_path/$2_curr
	fi
elif [ "$1" == "change" ]; then
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		zonep0type="${zonetype:0:${#zonetype}-1}"
		zonep1type="${zonetype:0:${#zonetype}-2}"
		zonep2type="${zonetype:0:${#zonetype}-3}"
		if [ "$zonetype" == "mlxsw" ] || [ "$zonep0type" == "mlxsw-module" ] ||
		   [ "$zonep1type" == "mlxsw-module" ] || [ "$zonep2type" == "mlxsw-module" ]; then
			# Notify thermal control about thermal zone change.
			if [ -f /var/run/hw-management.pid ]; then
				pid=`cat /var/run/hw-management.pid`
				if [ "$6" == "down" ]; then
					kill -USR1 $pid
				elif [ "$6" == "highest" ]; then
					if [ -L $thermal_path/highest_thermal_zone ]; then
						unlink $thermal_path/highest_thermal_zone
					fi
					ln -sf $3$4 $thermal_path/highest_thermal_zone
					score=$7
					max_score="${score:1}"
					echo $max_score > $thermal_path/highest_score
					kill -USR2 $pid
				fi
			fi
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ]; then
			pid=`cat /var/run/hw-management.pid`
			kill -USR1 $pid
		fi
	fi
	if [ "$2" == "hotplug_asic" ]; then
		if [ -d /sys/module/mlxsw_pci ]; then
			return
		fi
		find_i2c_bus
		bus=$(($i2c_asic_bus_default+$i2c_bus_offset))
		path=/sys/bus/i2c/devices/i2c-$bus
		if [ "$3" == "up" ]; then
			if [ ! -d /sys/module/mlxsw_minimal ]; then
				modprobe mlxsw_minimal
			fi
			if [ ! -d /sys/bus/i2c/devices/$bus-0048 ] &&
			   [ ! -d /sys/bus/i2c/devices/$bus-00048 ]; then
				echo mlxsw_minimal 0x48 > $path/new_device
			fi
		elif [ "$3" == "down" ]; then
			if [ -d /sys/bus/i2c/devices/$bus-0048 ] ||
			   [ -d /sys/bus/i2c/devices/$bus-00048 ]; then
				echo 0x48 > $path/delete_device
			fi
		fi
	fi
else
	if [ "$2" == "fan_amb" ] || [ "$2" == "port_amb" ]; then
		unlink $thermal_path/$2
	fi
	if [ "$2" == "switch" ]; then
		name=`cat $3$4/name`
		if [ "$name" == "mlxsw" ]; then
			unlink $thermal_path/temp1_input_asic
			unlink $thermal_path/pwm1
			for ((i=1; i<=$max_tachos; i+=1)); do
				if [ -L $thermal_path/fan"$i"_fault ]; then
					unlink $thermal_path/fan"$i"_fault
				fi
				if [ -L $thermal_path/fan"$i"_input ]; then
					unlink $thermal_path/fan"$i"_input
				fi
				if [ -f $thermal_path/fan"$j"_min ]; then
					unlink $thermal_path/fan"$j"_min
				fi
				if [ -f $thermal_path/fan"$j"_max ]; then
					unlink $thermal_path/fan"$j"_max
				fi
			done
			unlink $thermal_path/$pwm1
			for ((i=2; i<=$max_modules_ind; i+=1)); do
				if [ -L $thermal_path/temp_input_module"$j" ]; then
					j=$(($i-1))
					unlink $thermal_path/temp_input_module"$j"
					unlink $thermal_path/temp_fault_module"$j"
					unlink $thermal_path/temp_crit_module"$j"
					unlink $thermal_path/temp_emergency_module"$j"
				fi
			done
		fi
	fi
	if [ "$2" == "regfan" ]; then
		ln -sf $3$4/pwm1 $thermal_path/pwm1
		for ((i=1; i<=$max_tachos; i+=1)); do
			if [ -f $3$4/fan"$i"_fault ]; then
				unlink $thermal_path/fan"$i"_fault
			fi
			if [ -f $3$4/fan"$i"_input ]; then
				unlink $thermal_path/fan"$i"_input
			fi
			if [ -f $thermal_path/fan"$i"_min ]; then
				unlink $thermal_path/fan"$i"_min
			fi
			if [ -f $thermal_path/fan"$i"_max ]; then
				unlink $thermal_path/fan"$i"_max
			fi
		done
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		zonep0type="${zonetype:0:${#zonetype}-1}"
		zonep1type="${zonetype:0:${#zonetype}-2}"
		zonep2type="${zonetype:0:${#zonetype}-3}"
		if [ "$zonetype" == "mlxsw" ] || [ "$zonep0type" == "mlxsw-module" ] ||
		   [ "$zonep1type" == "mlxsw-module" ] || [ "$zonep2type" == "mlxsw-module" ]; then
			mode=`cat $thermal_path/$zonetype/thermal_zone_mode`
			if [ $mode == "enabled" ]; then
				echo disabled > $thermal_path/$zonetype/thermal_zone_mode
			fi
			unlink $thermal_path/$zonetype/thermal_zone_mode
			unlink $thermal_path/$zonetype/thermal_zone_policy
			unlink $thermal_path/$zonetype/temp_trip_norm
			unlink $thermal_path/$zonetype/temp_trip_high
			unlink $thermal_path/$zonetype/temp_trip_hot
			unlink $thermal_path/$zonetype/temp_trip_crit
			unlink $thermal_path/$zonetype/thermal_zone_temp
			rm -rf $thermal_path/$zonetype
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ]; then
			unlink $thermal_path/cooling_cur_state
		fi
	fi
	if [ "$2" == "hotplug" ]; then
		for ((i=1; i<=$max_tachos; i+=1)); do
			if [ -L $thermal_path/fan"$i"_status ]; then
				unlink $thermal_path/fan"$i"_status
			fi
		done
		for ((i=1; i<=$max_psus; i+=1)); do
			if [ -L $thermal_path/psu"$i"_status ]; then
				unlink $thermal_path/psu"$i"_status
			fi
			if [ -L $power_path/psu"$i"_pwr_status ]; then
				unlink $power_path/psu"$i"_pwr_status
			fi
		done
		if [ -d /sys/module/mlxsw_pci ]; then
			return
		fi
		find_i2c_bus
		bus=$(($i2c_asic_bus_default+$i2c_bus_offset))
		path=/sys/bus/i2c/devices/i2c-$bus
		if [ -d /sys/bus/i2c/devices/$bus-0048 ] ||
		   [ -d /sys/bus/i2c/devices/$bus-00048 ]; then
			echo 0x48 > $path/delete_device
		fi
	fi
	if [ "$2" == "cputemp" ]; then
		unlink $thermal_path/cpu_pack
		unlink $thermal_path/cpu_pack_crit
		unlink $thermal_path/cpu_pack_crit_alarm
		unlink $thermal_path/cpu_pack_max
		for i in {1..8}; do
			if [ -L $thermal_path/cpu_core"$i" ]; then
				j=$((i+1))
				unlink $thermal_path/cpu_core"$j"
				unlink $thermal_path/cpu_core"$j"_crit
				unlink $thermal_path/cpu_core"$j"_crit_alarm
				unlink $thermal_path/cpu_core"$j"_max
			fi
		done
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
		# Remove thermal attributes
		if [ -L $thermal_path/$2_temp ]; then
			unlink $thermal_path/$2_temp
		fi
		if [ -L $thermal_path/$2_temp_max ]; then
			unlink $thermal_path/$2_temp_max
		fi
		if [ -L $thermal_path/$2_temp_alarm ]; then
			unlink $thermal_path/$2_temp_alarm
		fi
		if [ -L $thermal_path/$2_fan1_speed_get ]; then
			unlink $thermal_path/$2_fan1_speed_get
		fi
		# Remove power attributes
		if [ -L $power_path/$2_volt_in ]; then
			unlink $power_path/$2_volt_in
		fi
		if [ -L $power_path/$2_volt ]; then
			unlink $power_path/$2_volt
		fi
		if [ -L $power_path/$2_power_in ]; then
			unlink $power_path/$2_power_in
		fi
		if [ -L $power_path/$2_power ]; then
			unlink $power_path/$2_power
		fi
		if [ -L $power_path/$2_curr_in ]; then
			unlink $power_path/$2_curr_in
		fi
		if [ -L $power_path/$2_curr ]; then
			unlink $power_path/$2_curr
		fi
	fi
fi
