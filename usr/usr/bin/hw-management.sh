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
# Required-Start: $local_fs $network $remote_fs $syslog
# Required-Stop: $local_fs $network $remote_fs $syslog
# Default-Start: 2 3 4 5
# Default-Stop:  0 1 6
# Short-Description: <Thermal control for Mellanox systems>
# Description: <Thermal control for Mellanox systems>
### END INIT INFO
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
#

. /lib/lsb/init-functions

# Local constants and variables
thermal_type=0
thermal_type_t1=1
thermal_type_t2=2
thermal_type_t3=3
thermal_type_t4=4
thermal_type_t4=4
thermal_type_t5=5
thermal_type_t6=6
max_psus=2
max_tachos=12
i2c_bus_max=10
i2c_bus_offset=0
i2c_asic_bus_default=2
i2c_asic_addr=0x48
i2c_asic_addr_name=0048
psu1_i2c_addr=0x59
psu2_i2c_addr=0x58
fan_psu_default=0x3c
fan_command=0x3b
fan_max_speed=24000
fan_min_speed=5000
chipup_delay_default=0
sxcore_down=0
sxcore_deferred=1
sxcore_withdraw=2
sxcore_up=3
i2c_bus_def_off_eeprom_cpu=16
i2c_comex_mon_bus_default=15
hw_management_path=/var/run/hw-management
thermal_path=$hw_management_path/thermal
config_path=$hw_management_path/config
environment_path=$hw_management_path/environment
power_path=$hw_management_path/power
alarm_path=$hw_management_path/alarm
eeprom_path=$hw_management_path/eeprom
led_path=$hw_management_path/led
system_path=$hw_management_path/system
module_path=$hw_management_path/module
sfp_path=$hw_management_path/sfp
watchdog_path=$hw_management_path/watchdog
THERMAL_CONTROL=/usr/bin/hw-management-thermal-control.sh
PID=/var/run/hw-management.pid
LOCKFILE="/var/run/hw-management.lock"

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
			tmp102 0x49 15 \
			tps53679 0x58 15 \
			tps53679 0x61 15 \
			24c32 0x50 16)

mqm8700_dis_table=(	0x64 5 \
			0x70 5 \
			0x71 5 \
			0x49 7 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x49 15 \
			0x58 15 \
			0x61 15 \
			0x50 16)

msn3800_connect_table=( max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tps53679 0x72 5 \
			tps53679 0x73 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			tmp102 0x49 15 \
			tps53679 0x58 15 \
			tps53679 0x61 15 \
			24c32 0x50 16)

msn3800_dis_table=(	0x6d 5 \
			0x70 5 \
			0x71 5 \
			0x72 5 \
			0x73 5 \
			0x49 7 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x49 15 \
			0x58 15 \
			0x61 15 \
			0x50 16)

msn27002_msn24102_msb78002_connect_table=( pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 23 \
			tmp102 0x49 23 \
			tps53679 0x58 23 \
			tps53679 0x61 23 \
			24c32 0x50 24 \
			lm75 0x49 17)

msn27002_msn24102_msb78002_dis_table=(	0x27 5 \
			0x41 5 \
			0x6d 5 \
			0x4a 7 \
			0x51 8 \
			0x6d 23 \
			0x49 23 \
			0x58 23 \
			0x61 23 \
			0x50 24 \
			0x49 17)

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
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
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
	max_tachos=4
	max_psus=0
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 5 > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
	echo cpld1 > $config_path/cpld_port
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
	echo 21000 > $config_path/fan_max_speed
	echo 5400 > $config_path/fan_min_speed
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
	echo cpld3 > $config_path/cpld_port
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
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
	echo cpld3 > $config_path/cpld_port
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
	max_tachos=4
	max_psus=0
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
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
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
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
	echo 11000 > $config_path/fan_max_speed
	echo 2235 > $config_path/fan_min_speed
	echo 4 > $config_path/cpld_num
}

msn24102_specific()
{
	connect_size=${#msn27002_msn24102_msb78002_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn27002_msn24102_msb78002_connect_table[i]}
	done
	disconnect_size=${#msn27002_msn24102_msb78002_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn27002_msn24102_msb78002_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
	echo 21000 > $config_path/fan_max_speed
	echo 5400 > $config_path/fan_min_speed
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
}

msn27002_msb78002_specific()
{
	connect_size=${#msn27002_msn24102_msb78002_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn27002_msn24102_msb78002_connect_table[i]}
	done
	disconnect_size=${#msn27002_msn24102_msb78002_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn27002_msn24102_msb78002_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
}

check_system()
{
	manufacturer=`cat /sys/devices/virtual/dmi/id/sys_vendor | awk '{print $1}'`
	if [ "$manufacturer" == "Mellanox" ]; then
		product=`cat /sys/devices/virtual/dmi/id/product_name`
		case $product in
			MSN27002|MSB78002)
				msn27002_msb78002_specific
				;;
			MSN24102)
				msn24102_specific
				;;
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
				proc_type=`cat /proc/cpuinfo | grep 'model name' | uniq  | awk '{print $5}'`
				case $proc_type in
					Atom*)
						msn21xx_specific
					;;
					Celeron*)
						msn27xx_msb_msx_specific
					;;
					Xeon*)
						mqmxxx_msn37x_msn34x_specific
					;;
					*)
						log_failure_msg "$product is not supported"
						exit 0
						;;
				esac
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
	if [ ! -d $config_path ]; then
		mkdir $config_path
	fi
	if [ ! -d $environment_path ]; then
		mkdir $environment_path
	fi
	if [ ! -d $power_path ]; then
		mkdir $power_path
	fi
	if [ ! -d $alarm_path ]; then
		mkdir $alarm_path
	fi
	if [ ! -d $eeprom_path ]; then
		mkdir $eeprom_path
	fi
	if [ ! -d $led_path ]; then
		mkdir $led_path
	fi
	if [ ! -d $system_path ]; then
		mkdir $system_path
	fi
	if [ ! -d $sfp_path ]; then
		mkdir $sfp_path
	fi
	if [ ! -d $watchdog_path ]; then
		mkdir $watchdog_path
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
		find $hw_management_path -type l -exec unlink {} \;
		rm -rf $hw_management_path
	fi
}

do_start()
{
	create_symbolic_links
	check_system
	echo ${i2c_comex_mon_bus_default} > $config_path/i2c_comex_mon_bus_default
	echo ${i2c_bus_def_off_eeprom_cpu} > $config_path/i2c_bus_def_off_eeprom_cpu
	depmod -a 2>/dev/null
	udevadm trigger --action=add
	echo $psu1_i2c_addr > $config_path/psu1_i2c_addr
	echo $psu2_i2c_addr > $config_path/psu2_i2c_addr
	echo $fan_psu_default > $config_path/fan_psu_default
	echo $fan_command > $config_path/fan_command
	echo 35 > $config_path/thermal_delay
	echo $chipup_delay_default > $config_path/chipup_delay
	echo 0 > $config_path/chipdown_delay
	if [ -f /etc/init.d/sxdkernel ]; then
		echo $sxcore_down > $config_path/sxcore
	fi
	find_i2c_bus
	asic_bus=$(($i2c_asic_bus_default+$i2c_bus_offset))
	echo $asic_bus > $config_path/asic_bus
	connect_platform

	$THERMAL_CONTROL $thermal_type $max_tachos $max_psus&
}

do_stop()
{
	# Kill thermal control if running.
	if [ -f $PID ]; then
		pid=`cat $PID`
		if [ -d /proc/$pid ]; then
			kill -9 $pid
		fi
		rm -rf $PID
	fi

	check_system
	disconnect_platform
	rm -fR /var/run/hw-management
}

function lock_service_state_change()
{
	exec {LOCKFD}>${LOCKFILE}
	/usr/bin/flock -x ${LOCKFD}
	trap "/usr/bin/flock -u ${LOCKFD}" EXIT SIGINT SIGQUIT SIGTERM
}

function unlock_service_state_change()
{
	/usr/bin/flock -u ${LOCKFD}
}

do_chip_up_down()
{
	# Add ASIC device.
	bus=`cat $config_path/asic_bus`

	case $1 in
	0)
		if [ -f /etc/init.d/sxdkernel ]; then
			chipup_delay=`cat $config_path/chipup_delay`
			if [ "$chipup_delay" != "0" ]; then
				# Decline chipup if in wait state.
				[ -f "$config_path/sxcore" ] && sxcore=`cat $config_path/sxcore`
				if [ $sxcore ] && [ "$sxcore" -eq "$sxcore_deferred" ]; then
					echo $sxcore_withdraw > $config_path/sxcore
					return
				fi
			fi
		fi
		lock_service_state_change
		chipup_delay=`cat $config_path/chipup_delay`
		echo 1 > $config_path/suspend
		if [ -d /sys/bus/i2c/devices/$bus-$i2c_asic_addr_name ]; then
			if [ -f /etc/init.d/sxdkernel ]; then
				if [ "$chipup_delay" != "0" ]; then
					[ -f "$config_path/sxcore" ] && sxcore=`cat $config_path/sxcore`
					if [ $sxcore ] && [ "$sxcore" -eq "$sxcore_up" ]; then
						echo $sxcore_down > $config_path/sxcore
					else
						unlock_service_state_change
						return
					fi
				fi
			fi
			chipdown_delay=`cat $config_path/chipdown_delay`
			sleep $chipdown_delay
			echo $i2c_asic_addr > /sys/bus/i2c/devices/i2c-$bus/delete_device
		fi
		unlock_service_state_change
		;;
	1)
		lock_service_state_change
                [ -f "$config_path/chipup_dis" ] && disable=`cat $config_path/chipup_dis`
                if [ $disable ] && [ "$disable" -gt 0 ]; then
			disable=$(($disable-1))
			echo $disable > $config_path/chipup_dis
			unlock_service_state_change
			exit 0
		fi
		chipup_delay=`cat $config_path/chipup_delay`
		if [ -f /etc/init.d/sxdkernel ]; then
			if [ "$chipup_delay" != "0" ]; then
				# Have delay in order to avoid impact of chip reset,
				# performed by sxcore driver.
				# In case sxcore driver does not reset chip, for example
				# for reboot through kexec - just sleep 'chipup_delay'
				# seconds.
				[ -f "$config_path/sxcore" ] && sxcore=`cat $config_path/sxcore`
				if [ $sxcore ] && [ "$sxcore" -eq "$sxcore_down" ]; then
					echo $sxcore_deferred > $config_path/sxcore
				elif [ $sxcore ] && [ "$sxcore" -eq "$sxcore_deferred" ]; then
					echo $sxcore_up > $config_path/sxcore
				else
					unlock_service_state_change
					return
				fi
			fi
		fi
		if [ ! -d /sys/bus/i2c/devices/$bus-$i2c_asic_addr_name ]; then
			sleep $chipup_delay
			echo 0 > $config_path/sfp_counter
			if [ -f /etc/init.d/sxdkernel ]; then
				if [ "$chipup_delay" != "0" ]; then
					# Skip if chipup has been dropped.
					[ -f "$config_path/sxcore" ] && sxcore=`cat $config_path/sxcore`
					if [ $sxcore ] && [ "$sxcore" -eq "$sxcore_withdraw" ]; then
						echo $sxcore_down > $config_path/sxcore
						unlock_service_state_change
						return
					fi
				fi
			fi
			echo mlxsw_minimal $i2c_asic_addr > /sys/bus/i2c/devices/i2c-$bus/new_device
			if [ "$chipup_delay" != "0" ]; then
				if [ $sxcore ] && [ "$sxcore" -eq "$sxcore_deferred" ]; then
					echo $sxcore_up > $config_path/sxcore
				fi
			fi
		else
			unlock_service_state_change
			return
		fi
		case $2 in
		1)
			echo 0 > $config_path/suspend
			;;
		*)
			echo 1 > $config_path/suspend
			;;
		esac
		unlock_service_state_change
		;;
	*)
		exit 1
		;;
	esac
}

do_chip_down()
{
	# Delete ASIC device
	/usr/bin/hw-management-thermal-events.sh change hotplug_asic down %S %p
}

case $ACTION in
	start)
		do_start
	;;
	stop)
		if [ -d /var/run/hw-management ]; then
			echo 1 > $config_path/stopping
			do_chip_up_down 0
			do_stop
		fi
	;;
	chipup)
		if [ -d /var/run/hw-management ]; then
			do_chip_up_down 1 $2
		fi
	;;
	chipdown)
		if [ -d /var/run/hw-management ]; then
			do_chip_up_down 0
		fi
	;;
	chipupen)
		echo 0 > $config_path/chipup_dis
	;;
	chipupdis)
		if [ -z "$2" ]; then
			echo 1 > $config_path/chipup_dis
		else
			echo $2 > $config_path/chipup_dis
		fi
	;;
	thermsuspend)
		if [ -d /var/run/hw-management ]; then
			echo 1 > $config_path/suspend
		fi
	;;
	thermresume)
		if [ -d /var/run/hw-management ]; then
			echo 0 > $config_path/suspend
		fi
	;;
	restart|force-reload)
		do_stop
		sleep 3
		do_start
	;;
	*)
		echo "Usage: `basename $0` {start|stop}"
		exit 1
	;;
esac
