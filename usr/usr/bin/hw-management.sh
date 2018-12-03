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

### BEGIN INIT INFO
# Provides:		Thermal control for Mellanox systems
# Supported systems:
#  MSN274*		Panther SF
#  MSN21*		Bulldog
#  MSN24*		Spider
#  MSN27*|MSB*|MSX*	Neptune, Tarantula, Scorpion, Scorpion2, Spider
#  MSN201*		Boxer
#  MQMB7*|MSN37*|MSN34*	Jupiter, Jaguar, Anaconda
#  MSN38*		Tigris
# Available options:
# start	- load the kernel drivers required for the thermal control support,
#	  connect drivers to devices, activate thermal control.
# stop	- disconnect drivers from devices, unload kernel drivers, which has
#	  been loaded, deactivate thermal control.
### END INIT INFO

. /lib/lsb/init-functions

# Local constants and variables
thermal_type=0
thermal_type_t1=1
thermal_type_t2=2
thermal_type_t3=3
thermal_type_t4=4
thermal_type_t4=4
thermal_type_t5=5
max_psus=2
max_tachos=12
i2c_bus_max=10
i2c_bus_offset=0
psu1_i2c_addr=0x59
psu2_i2c_addr=0x58
fan_psu_default=0x3c
fan_command=0x3b
fan_max_speed=24000
fan_min_speed=5000
hw_management_path=/var/run/hw-management
thermal_path=$hw_management_path/thermal
config_path=$hw_management_path/config
thermal_zone_path=$hw_management_path/thermal_zone
environment_path=$hw_management_path/environment
power_path=$hw_management_path/power
eeprom_path=$hw_management_path/eeprom
led_path=$hw_management_path/led
module_path=$hw_management_path/module
system_path=$hw_management_path/system
cpld_path=$hw_management_path/cpld
qsfp_path=$hw_management_path/qsfp
THERMAL_CONTROL=/usr/bin/hw-management-thermal-control.sh
PID=/var/run/hw-management.pid

# Topology description and driver specification for ambient sensors and for
# ASIC I2C driver per system class. Specific system class is obtained from DMI
# tables.
# ASIC I2C driver is supposed to be activated only in case PCI ASIC driver is
# not loaded. Both perform the same thermal algorithm and exposes the same
# sensors to sysfs. In case PCI path is available, access will be performed
# through PCI.
# Hardware monitoring related drivers for ambient temperature sensing will be
# loaded in case they were not loaded before or in case these drivers are not
# configured as modules.
msn2700_connect_table=( pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			24c32 0x51 16 \
			lm75 0x49 17)

msn2700_dis_table=(	0x27 5 \
			0x41 5 \
			0x6d 5 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x51 16 \
			0x49 17)

msn2100_connect_table=( pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			lm75 0x4b 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			24c32 0x51 16)

msn2100_dis_table=(	0x27 5 \
			0x41 5 \
			0x6d 5 \
			0x4a 7 \
			0x4b 7 \
			0x51 8 \
			0x6d 15 \
			0x51 16)

msn2740_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x64 5 \
			tmp102 0x49 6 \
			tmp102 0x48 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			24c32 0x51 16)

msn2740_dis_table=(	0x27 5 \
			0x41 5 \
			0x64 5 \
			0x49 6 \
			0x48 7 \
			0x51 8 \
			0x6d 15 \
			0x51 16)

msn2010_connect_table=(	max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			lm75 0x4a 7 \
			lm75 0x4b 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			24c32 0x51 16)

msn2010_dis_table=(	0x71 5 \
			0x70 5 \
			0x6d 5 \
			0x4b 7 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x51 16)

mqm8700_connect_table=(	max11603 0x64 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			24c32 0x50 16)

mqm8700_dis_table=(	0x64 5 \
			0x70 5 \
			0x71 5 \
			0x49 7 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x50 16)

msn3800_connect_table=( max11603 0x64 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tps53679 0x72 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			24c32 0x50 16)

msn3800_dis_table=(	0x64 5 \
			0x70 5 \
			0x71 5 \
			0x72 5 \
			0x49 7 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x50 16)

ACTION=$1

is_module()
{
        /sbin/lsmod | grep -w "$1" > /dev/null
        RC=$?
        return $RC
}

msn274x_specific()
{
	connect_size=${#msn2740_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2740_connect_table[i]}
	done
	disconnect_size=${#msn2740_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2740_dis_table[i]}
	done

	thermal_type=$thermal_type_t3
	max_tachos=4
	echo 5 > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
}

msn21xx_specific()
{
	connect_size=${#msn2100_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2100_connect_table[i]}
	done
	disconnect_size=${#msn2100_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2100_dis_table[i]}
	done

	thermal_type=$thermal_type_t2
	max_tachos=8
	max_psus=0
	echo 5 > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
}

msn24xx_specific()
{
	connect_size=${#msn2700_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
}

msn27xx_msb_msx_specific()
{
	connect_size=${#msn2700_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
}

msn201x_specific()
{
	connect_size=${#msn2010_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2010_connect_table[i]}
	done
	disconnect_size=${#msn2010_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2010_dis_table[i]}
	done

	thermal_type=$thermal_type_t4
	max_tachos=8
	max_psus=0
	echo 5 > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
}

mqmxxx_msn37x_msn34x_specific()
{
	connect_size=${#mqm8700_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${mqm8700_connect_table[i]}
	done
	disconnect_size=${#mqm8700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${mqm8700_dis_table[i]}
	done

	thermal_type=$thermal_type_t5
	max_tachos=12
	max_psus=2
	echo 3 > $config_path/cpld_num
}

msn38xx_specific()
{
	connect_size=${#msn3800_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn3800_connect_table[i]}
	done
	disconnect_size=${#msn3800_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn3800_dis_table[i]}
	done

	thermal_type=$thermal_type_t6
	max_tachos=3
	max_psus=2
	echo 3 > $config_path/cpld_num
}

check_system()
{
	manufacturer=`cat /sys/devices/virtual/dmi/id/sys_vendor | awk '{print $1}'`
	if [ "$manufacturer" = "Mellanox" ]; then
		product=`cat /sys/devices/virtual/dmi/id/product_name`
		case $product in
			MSN274*)
				msn274x_specific
				;;
			MSN21*)
				msn21xx_specific
				;;
			MSN24*)
				msn24xx_specific
				;;
			MSN27*|MSB*|MSX*)
				msn27xx_msb_msx_specific
				;;
			MSN201*)
				msn201x_specific
				;;
			MQM87*|MSN37*|MSN34*)
				mqmxxx_msn37x_msn34x_specific
				;;
			MSN38*)
				msn38xx_specific
				;;
			*)
				log_failure_msg "$product is not supported"
				exit 0
				;;
		esac
	else
		# Check ODM
		board=`cat /sys/devices/virtual/dmi/id/board_name`
		case $board in
			VMOD0001)
				msn27xx_msb_msx_specific
				;;
			VMOD0002)
				msn21xx_specific
				;;
			VMOD0003)
				msn274x_specific
				;;
			VMOD0004)
				msn201x_specific
				;;
			VMOD0005)
				mqmxxx_msn37x_msn34x_specific
				;;
			VMOD0007)
				msn38xx_specific
				;;
			*)
				log_failure_msg "$manufacturer is not Mellanox"
				exit 0
		esac
	fi

	kernel_release=`uname -r`
}

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

connect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-$3/new_device ]; then
		addr=`echo $2 | tail -c +3`
		bus=$(($3+$i2c_bus_offset))
		if [ ! -d /sys/bus/i2c/devices/$bus-00$addr ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000$addr ]; then
			echo $1 $2 > /sys/bus/i2c/devices/i2c-$bus/new_device
		fi
	fi

	return 0
}

disconnect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-$2/delete_device ]; then
		addr=`echo $1 | tail -c +3`
		bus=$(($2+$i2c_bus_offset))
		if [ -d /sys/bus/i2c/devices/$bus-00$addr ] ||
		   [ -d /sys/bus/i2c/devices/$bus-000$addr ]; then
			echo $1 > /sys/bus/i2c/devices/i2c-$bus/delete_device
		fi
	fi

	return 0
}

connect_platform()
{
	for ((i=0; i<$connect_size; i+=3)); do
		connect_device 	${connect_table[i]} ${connect_table[i+1]} \
				${connect_table[i+2]}
        done
}

disconnect_platform()
{
	for ((i=0; i<$disconnect_size; i+=2)); do
		disconnect_device ${dis_table[i]} ${dis_table[i+1]}
	done
}

create_symbolic_links()
{
	if [ ! -d $hw_management_path ]; then
		mkdir $hw_management_path
	fi
	if [ ! -d $thermal_path ]; then
		mkdir $thermal_path
	fi	
	if [ ! -d $thermal_path ]; then
		mkdir $thermal_path
	fi
	if [ ! -d $config_path ]; then
		mkdir $config_path
	fi
	if [ ! -d $thermal_zone_path  ]; then
		mkdir -p $thermal_zone_path
	fi
	if [ ! -d $environment_path ]; then
		mkdir $environment_path
	fi
	if [ ! -d $power_path ]; then
		mkdir $power_path
	fi
	if [ ! -d $eeprom_path ]; then
		mkdir $eeprom_path
	fi
	if [ ! -d $led_path ]; then
		mkdir $led_path
	fi
	if [ ! -d $module_path ]; then
		mkdir $module_path
	fi
	if [ ! -d $system_path ]; then
		mkdir $system_path
	fi
	if [ ! -d $cpld_path ]; then
		mkdir $cpld_path
	fi
	if [ ! -d $qsfp_path ]; then
		mkdir $qsfp_path
	fi
	if [ ! -h $power_path/pwr_consum ]; then
		ln -sf /usr/bin/hw-management-power-helper.sh $power_path/pwr_consum
	fi
	if [ ! -h $power_path/pwr_sys ]; then
		ln -sf /usr/bin/hw-management-power-helper.sh $power_path/pwr_sys
	fi
}

remove_symbolic_links()
{
	# Clean hw-management directory - remove folder if it's empty
	if [ -d $hw_management_path ]; then
		sleep 3
		for filename in $hw_management_path/*; do
			if [ -d $filename ]; then
				if [ -z "$(ls -A $filename)" ]; then
					rm -rf $filename
				fi
			elif [ -L $filename ]; then
				unlink $filename
			fi
		done
		rm -rf $config_path
		if [ -z "$(ls -A $hw_management_pat)" ]; then
			rm -rf $hw_management_path
		fi
	fi
}

case $ACTION in
	start)
		create_symbolic_links
		check_system
		depmod -a 2>/dev/null
		echo $fan_max_speed > $config_path/fan_max_speed
		echo $fan_min_speed > $config_path/fan_min_speed
		echo $psu1_i2c_addr > $config_path/psu1_i2c_addr
		echo $psu2_i2c_addr > $config_path/psu2_i2c_addr
		echo $fan_psu_default > $config_path/fan_psu_default
		echo $fan_command > $config_path/fan_command
		# Sleep to allow kernel modules initialization completion
		sleep 3
		find_i2c_bus
		connect_platform
		$THERMAL_CONTROL $thermal_type $max_tachos $max_psus &
	;;
	stop)
		# Kill thermal control if running.
		if [ -f $PID ]; then
			pid=`cat $PID`
			if [ -d /proc/$pid ]; then
				kill $pid
			fi
		fi

		check_system
		disconnect_platform
		remove_symbolic_links
	;;
	*)
		echo "Usage: `basename $0` {start|stop}"
		exit 1
	;;
esac
