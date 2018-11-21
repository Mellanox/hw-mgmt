#!/bin/bash

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

bsp_path=/var/run/mellanox
fan_command=0x3b
fan_psu_default=0x3c
i2c_bus_max=10
i2c_bus_offset=0
i2c_asic_bus_default=2
i2c_bus_def_off_eeprom_vpd=7
i2c_bus_def_off_eeprom_cpu=15
i2c_bus_def_offeeprom_psu1=3
i2c_bus_def_off_eeprom_psu2=3
i2c_bus_alt_off_eeprom_psu1=9
i2c_bus_alt_off_eeprom_psu2=9
i2c_bus_def_off_eeprom_fan1=10
i2c_bus_def_off_eeprom_fan1=11
i2c_bus_def_off_eeprom_fan1=12
i2c_bus_def_off_eeprom_fan4=13
eeprom_name=''

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

find_eeprom_name()
{
	bus=$1
	if [ $bus -eq $i2c_bus_def_off_eeprom_vpd ]; then
		eeprom_name=eeprom_vpd
	elif [ $bus -eq $i2c_bus_def_off_eeprom_cpu ]; then
		eeprom_name=eeprom_cpu
	elif [ $bus -eq $i2c_bus_def_offeeprom_psu1 ] ||
	     [ $bus -eq $bus -eq $i2c_bus_alt_off_eeprom_psu1 ]; then
		eeprom_name=eeprom_psu1
	elif [ $bus -eq bus -eq $i2c_bus_def_off_eeprom_psu2 ] ||
	     [ $bus -eq $i2c_bus_alt_off_eeprom_psu2]; then
		eeprom_name=eeprom_psu2
	elif [ $bus -eq $i2c_bus_def_off_eeprom_fan1 ]; then
		eeprom_name=eeprom_fan1
	elif [ $bus -eq $i2c_bus_def_off_eeprom_fan2 ]; then
		eeprom_name=eeprom_fan2
	elif [ $bus -eq $i2c_bus_def_off_eeprom_fan3 ]; then
		eeprom_name=eeprom_fan3
	elif [ $bus -eq $i2c_bus_def_off_eeprom_fan4 ]; then
		eeprom_name=eeprom_fan4
	fi
}

if [ "$1" == "add" ]; then
	if [ "$2" == "board_amb" ] || [ "$2" == "port_amb" ]; then
		ln -sf $3$4/temp1_input $bsp_path/thermal/$2
		ln -sf $3$4/temp1_max $bsp_path/thermal/$2_max
		ln -sf $3$4/temp1_max_hyst $bsp_path/thermal/$2_hyst
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
		ln -sf $5$3/temp1_input $bsp_path/thermal/$2
		ln -sf $5$3/temp1_max $bsp_path/thermal/$2_max
		ln -sf $5$3/temp1_max_alarm $bsp_path/thermal/$2_alarm
		ln -sf $5$3/in1_input $bsp_path/power/$2_volt_in
		ln -sf $5$3/in2_input $bsp_path/power/$2_volt
		ln -sf $5$3/power1_input $bsp_path/power/$2_power_in
		ln -sf $5$3/power2_input $bsp_path/power/$2_power
		ln -sf $5$3/curr1_input $bsp_path/power/$2_curr_in
		ln -sf $5$3/curr2_input $bsp_path/power/$2_curr
		ln -sf $5$3/fan1_input $bsp_path/fan/$2_fan1_speed_get

		#FAN speed set
		busdir=`echo $5$3 |xargs dirname |xargs dirname`
		busfolder=`basename $busdir`
		bus="${busfolder:0:${#busfolder}-5}"
		if [ "$2" == "psu1" ]; then
			i2cset -f -y $bus 0x59 $fan_command $fan_psu_default wp
		else
			i2cset -f -y $bus 0x58 $fan_command $fan_psu_default wp
		fi
	fi
	if [ "$2" == "a2d" ]; then
		ln -sf $3$4/in_voltage-voltage_scale $bsp_path/environment/$2_$5_voltage_scale
		for i in {1..12}; do
			if [ -f $3$4/in_voltage"$i"_raw ]; then
				ln -sf $3$4/in_voltage"$i"_raw $bsp_path/environment/$2_$5_raw_"$i"
			fi
		done
	fi
	if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ]; then
		ln -sf $3$4/in1_input $bsp_path/environment/$2_in1_input
		ln -sf $3$4/in2_input $bsp_path/environment/$2_in2_input
		ln -sf $3$4/curr2_input $bsp_path/environment/$2_curr2_input
		ln -sf $3$4/power2_input $bsp_path/environment/$2_power2_input
		ln -sf $3$4/in3_input $bsp_path/environment/$2_in3_input
		ln -sf $3$4/curr3_input $bsp_path/environment/$2_curr3_input
		ln -sf $3$4/power3_input $bsp_path/environment/$2_power3_input
	fi
	if [ "$2" == "asic" ]; then
		ln -sf $3$4/temp1_input $bsp_path/thermal/$2
		ln -sf $3$4/temp1_highest $bsp_path/thermal/$2_highest
	fi
	if [ "$2" == "fan" ]; then
		# Take time for adding infrastructure
		sleep 3
		if [ -f $bsp_path/config/fan_inversed ]; then
			inv=`cat $bsp_path/config/fan_inversed`
		fi
		for i in {1..12}; do
			if [ -f $3$4/fan"$i"_input ]; then
				if [ -z "$inv" ] || [ ${inv} -eq 0 ]; then
					j=$i
				else
					j=`echo $(($inv - $i))`
				fi
				ln -sf $3$4/fan"$i"_input $bsp_path/fan/fan"$j"_speed_get
				ln -sf $3$4/pwm1 $bsp_path/fan/fan"$j"_speed_set
				ln -sf $bsp_path/config/fan_min_speed $bsp_path/fan/fan"$j"_min
				ln -sf $bsp_path/config/fan_max_speed $bsp_path/fan/fan"$j"_max
			fi
		done
	fi
	if [ "$2" == "qsfp" ]; then
		# Take time for adding infrastructure
		sleep 5
		for i in {1..64}; do
			if [ -f $3$4/qsfp$i ]; then
				ln -sf $3$4/qsfp$i $bsp_path/qsfp/qsfp"$i"
				ln -sf $3$4/qsfp"$i"_status $bsp_path/qsfp/qsfp"$i"_status
			fi
		done
		if [ -f $3$4/cpld3_version ]; then
			ln -sf $3$4/cpld3_version $bsp_path/cpld/cpld_port_version
		fi
	fi
	if [ "$2" == "led" ]; then
		name=`echo $5 | cut -d':' -f2`
		color=`echo $5 | cut -d':' -f3`
		ln -sf $3$4/brightness $bsp_path/led/led_"$name"_"$color"
		echo timer > $3$4/trigger
		ln -sf $3$4/delay_on	$bsp_path/led/led_"$name"_"$color"_delay_on
		ln -sf $3$4/delay_off $bsp_path/led/led_"$name"_"$color"_delay_off
		ln -sf /usr/bin/led_state.sh $bsp_path/led/led_"$name"_state

		if [ ! -f $bsp_path/led/led_"$name"_capability ]; then
			echo none ${color} ${color}_blink > $bsp_path/led/led_"$name"_capability
		else
			capability=`cat $bsp_path/led/led_"$name"_capability`
			capability="${capability} ${color} ${color}_blink"
			echo $capability > $bsp_path/led/led_"$name"_capability
		fi
		$bsp_path/led/led_"$name"_state
	fi
	if [ "$2" == "thermal_zone" ]; then
		busfolder=`basename $3$4`
		zonename=`echo $5`
		zonetype=`cat $3$4/type`
		if [ "$zonetype" == "mlxsw" ]; then
			# Disable thermal algorithm
			echo disabled > $3$4/mode
			# Set default fan speed
			echo 6 > $3$4/cdev0/cur_state
			zone=$zonetype
		else
			 zone=$zonename-$zonetype
		fi
		mkdir -p $bsp_path/thermal_zone/$zone
		ln -sf $3$4/mode $bsp_path/thermal_zone/$zone/mode
		for i in {0..11}; do
			if [ -f $3$4/trip_point_"$i"_temp ]; then
				ln -sf $3$4/trip_point_"$i"_temp $bsp_path/thermal_zone/$zone/trip_point_$i
			fi
			if [ -d $3$4/cdev"$i" ]; then
				ln -sf $3$4/cdev"$i"/cur_state $bsp_path/thermal_zone/$zone/cooling"$i"_current_state
			fi
		done
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
				ln -sf $3$4/temp"$i"_input $bsp_path/thermal/cpu_$name
				ln -sf $3$4/temp"$i"_crit $bsp_path/thermal/cpu_"$name"_crit
				ln -sf $3$4/temp"$i"_crit_alarm $bsp_path/thermal/cpu_"$name"_crit_alarm
				ln -sf $3$4/temp"$i"_max $bsp_path/thermal/cpu_"$name"_max
			fi
		done
	fi
	if [ "$2" == "hotplug" ]; then
		for i in {1..12}; do
			if [ -f $3$4/fan$i ]; then
				ln -sf $3$4/fan$i $bsp_path/module/fan"$i"_status
			fi
		done
		for i in {1..2}; do
			if [ -f $3$4/psu$i ]; then
				ln -sf $3$4/psu$i $bsp_path/module/psu"$i"_status
			fi
			if [ -f $3$4/pwr$i ]; then
				ln -sf $3$4/pwr$i $bsp_path/module/psu"$i"_pwr_status
			fi
		done
	fi
	if [ "$2" == "regio" ]; then
		if [ -d $3$4 ]; then
			ln -sf $3$4 $bsp_path/system
		fi
	fi
	if [ "$2" == "eeprom" ]; then
		busdir=`echo $5$3 |xargs dirname |xargs dirname`
		busfolder=`basename $busdir`
		bus="${busfolder:0:${#busfolder}-5}"
		find_i2c_bus
		bus=$(($bus-+$i2c_bus_offset))
		find_eeprom_name $bus
		ln -sf $3$4/eeprom $bsp_path/eeprom/$eeprom_name 2>/dev/null
	fi
	fi
elif [ "$1" == "change" ]; then
	if [ "$2" == "hotplug_asic" ]; then
		if [ -d /sys/module/mlxsw_pci ] ||
			 [ -d /sys/module/mlxsw_spectrum ]; then
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
	if [ "$2" == "board_amb" ] || [ "$2" == "port_amb" ]; then
		unlink $bsp_path/thermal/$2
		unlink $bsp_path/thermal/$2_max
		unlink $bsp_path/thermal/$2_hyst
	fi
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
		unlink $bsp_path/thermal/$2
		unlink $bsp_path/thermal/$2_max
		unlink $bsp_path/thermal/$2_alarm
		unlink $bsp_path/power/$2_volt_in
		unlink $bsp_path/power/$2_volt
		unlink $bsp_path/power/$2_power_in
		unlink $bsp_path/power/$2_power
		unlink $bsp_path/power/$2_curr_in
		unlink $bsp_path/power/$2_curr
		unlink $bsp_path/fan/$2_fan1_speed_get
	fi
	if [ "$2" == "a2d" ]; then
		unlink $bsp_path/environment/$2_$5_voltage_scale
		for i in {1..12}; do
			if [ -L $bsp_path/environment/$2_$5_raw_"$i" ]; then
				unlink $bsp_path/environment/$2_$5_raw_"$i"
			fi
		done
	fi
	if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ]; then
		unlink $bsp_path/environment/$2_in1_input
		unlink $bsp_path/environment/$2_in2_input
		unlink $bsp_path/environment/$2_curr2_input
		unlink $bsp_path/environment/$2_power2_input
		unlink $bsp_path/environment/$2_in3_input
		unlink $bsp_path/environment/$2_curr3_input
		unlink $bsp_path/environment/$2_power3_input
	fi
	if [ "$2" == "asic" ]; then
		unlink $bsp_path/thermal/$2
		unlink $bsp_path/thermal/$2_highest
	fi
	if [ "$2" == "fan" ]; then
		for i in {1..12}; do
			if [ -L $bsp_path/fan/fan"$i"_speed_get ]; then
				unlink $bsp_path/fan/fan"$i"_speed_get
			fi
			if [ -L $bsp_path/fan/fan"$i"_speed_set ]; then
				unlink $bsp_path/fan/fan"$i"_speed_set
			fi
			if [ -L $bsp_path/fan/fan"$i"_min ]; then
				unlink $bsp_path/fan/fan"$i"_min
			fi
			if [ -L $bsp_path/fan/fan"$i"_max ]; then
				unlink $bsp_path/fan/fan"$i"_max
			fi
 		done
	fi
	if [ "$2" == "qsfp" ]; then
		for i in {1..64}; do
			if [ -L $bsp_path/qsfp/qsfp$i ]; then
				unlink $bsp_path/qsfp/qsfp"$i"
			fi
			if [ -L $bsp_path/qsfp/qsfp"$i"_status ]; then
				unlink $bsp_path/qsfp/qsfp"$i"_status
			fi
		done
		if [ -L $bsp_path/cpld/cpld_port_version ]; then
			unlink $bsp_path/cpld/cpld_port_version
		fi
	fi
	if [ "$2" == "led" ]; then
		name=`echo $5 | cut -d':' -f2`
		color=`echo $5 | cut -d':' -f3`
		unlink $bsp_path/led/led_"$name"_"$color"
		unlink $bsp_path/led/led_"$name"_"$color"_delay_on
		unlink $bsp_path/led/led_"$name"_"$color"_delay_off
		unlink $bsp_path/led/led_"$name"_state
		if [ -f $bsp_path/led/led_"$name" ]; then
			rm -f $bsp_path/led/led_"$name"
		fi
		if [ -f $bsp_path/led/led_"$name"_capability ]; then
			rm -f $bsp_path/led/led_"$name"_capability
		fi
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonefolder=`basename $bsp_path/thermal_zone/$5*`
		if [ ! -d $bsp_path/thermal_zone/$zonefolder ]; then
				zonefolder=mlxsw
		fi
		if [ -d $bsp_path/thermal_zone/$zonefolder ]; then
			unlink $bsp_path/thermal_zone/$zonefolder/mode
			for i in {0..11}; do
				if [ -L $bsp_path/thermal_zone/$zonefolder/trip_point_$i ]; then
					unlink $bsp_path/thermal_zone/$zonfoldere/trip_point_$i
				fi
				if [ -L $bsp_path/thermal_zone/$zonefolder/cooling"$i"_current_state ]; then
					unlink $bsp_path/thermal_zone/$zonefolder/cooling"$i"_current_state
				fi
			done
			unlink $bsp_path/thermal_zone/$zonefolder/*
			rm -rf $bsp_path/thermal_zone/$zonefolder
		fi
	fi
	if [ "$2" == "cputemp" ]; then
		unlink $bsp_path/thermal/cpu_pack
		unlink $bsp_path/thermal/cpu_pack_crit
		unlink $bsp_path/thermal/cpu_pack_crit_alarm
		unlink $bsp_path/thermal/cpu_pack_max
		for i in {1..8}; do
			if [ -L $bsp_path/thermal/cpu_core"$i" ]; then
				j=$((i+1))
				unlink $bsp_path/thermal/cpu_core"$j"
				unlink $bsp_path/thermal/cpu_core"$j"_crit
				unlink $bsp_path/thermal/cpu_core"$j"_crit_alarm
				unlink $bsp_path/thermal/cpu_core"$j"_max
			fi
		done
	fi
	if [ "$2" == "hotplug" ]; then
		for i in {1..12}; do
			if [ -L $bsp_path/module/fan"$i"_status ]; then
				unlink $bsp_path/module/fan"$i"_status
			fi
		done
		for i in {1..2}; do
			if [ -L $bsp_path/module/psu"$i"_status ]; then
				unlink $bsp_path/module/psu"$i"_status
			fi
			if [ -L $bsp_path/module/psu"$i"_pwr_status ]; then
				unlink $bsp_path/module/psu"$i"_pwr_status
			fi
		done
	fi
	if [ "$2" == "regio" ]; then
		if [ -L $bsp_path/system ]; then
			unlink $bsp_path/system
		fi
	fi
	if [ "$2" == "eeprom" ]; then
		unlink $bsp_path/eeprom/psu1_info
		busdir=`echo $5$3 |xargs dirname |xargs dirname`
		busfolder=`basename $busdir`
		bus="${busfolder:0:${#busfolder}-5}"
		find_i2c_bus
		bus=$(($bus-+$i2c_bus_offset))
		find_eeprom_name $bus
		unlink $bsp_path/eeprom/$eeprom_name
	fi
fi
