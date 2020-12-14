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
# Provides: hw-management
# Required-Start: $local_fs $network $remote_fs $syslog
# Required-Stop: $local_fs $network $remote_fs $syslog
# Default-Start: 2 3 4 5
# Default-Stop:  0 1 6
# Short-Description: <Chassis Hardware management of Mellanox systems>
# Description: <Chassis Hardware management of Mellanox systems>
### END INIT INFO
# Supported systems:
#  SN274*
#  SN21*
#  SN24*
#  SN27*|SB*|SX*
#  SN201*
#  QMB7*|SN37*|SN34*
#  SN38*|SN37*|SN34*|SN35*
#  SN47*
#  QM97*
# Available options:
# start	- load the kernel drivers required for chassis hardware management,
#	  connect drivers to devices.
# stop	- disconnect drivers from devices, unload kernel drivers, which has
#	  been loaded.
#

# Local constants and variables

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
thermal_type_def=0

thermal_type=$thermal_type_def
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
chipup_delay_default=0
sxcore_down=0
sxcore_deferred=1
sxcore_withdraw=2
sxcore_up=3
hotplug_psus=2
hotplug_fans=6
hotplug_pwrs=2
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
sfp_path=$hw_management_path/sfp
watchdog_path=$hw_management_path/watchdog
events_path=$hw_management_path/events
jtag_path=$hw_management_path/jtag
lm_sensors_configs_path="/etc/hw-management-sensors"
LOCKFILE="/var/run/hw-management.lock"
udev_ready=$hw_management_path/.udev_ready
tune_thermal_type=0
i2c_freq_400=0xf
i2c_freq_reg=0x2004
# CPU Family + CPU Model should idintify exact CPU architecture
# IVB - Ivy-Bridge; RNG - Atom Rangeley
# BDW - Broadwell-DE; CFL - Coffee Lake
IVB_CPU=0x63A
RNG_CPU=0x64D
BDW_CPU=0x656
CFL_CPU=0x69E
cpu_type=

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

msn3420_connect_table=(	max11603 0x6d 5 \
			xdpe12284 0x62 5 \
			xdpe12284 0x64 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			tmp102 0x49 15 \
			tps53679 0x58 15 \
			tps53679 0x61 15 \
			24c32 0x50 16)

msn3420_dis_table=(	0x6d 5 \
			0x62 5 \
			0x64 5 \
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
			max11603 0x6d 15 \
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
			0x6d 15 \
			0x6d 23 \
			0x49 23 \
			0x58 23 \
			0x61 23 \
			0x50 24 \
			0x49 17)

msn4700_msn4600_connect_table=(	max11603 0x6d 5 \
			xdpe12284 0x62 5 \
			xdpe12284 0x64 5 \
			xdpe12284 0x66 5 \
			xdpe12284 0x68 5 \
			xdpe12284 0x6a 5 \
			xdpe12284 0x6c 5 \
			xdpe12284 0x6e 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			tmp102 0x49 15 \
			tps53679 0x58 15 \
			tps53679 0x61 15 \
			24c32 0x50 16)

msn4700_msn4600_dis_table=(	0x6d 5 \
			0x62 5 \
			0x64 5 \
			0x66 5 \
			0x68 5 \
			0x6a 5 \
			0x6c 5 \
			0x6e 5 \
			0x49 7 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x49 15 \
			0x58 15 \
			0x61 15 \
			0x50 16)

msn4700_A1_connect_table=(	max11603 0x6d 5 \
			mp2975 0x62 5 \
			mp2975 0x64 5 \
			mp2975 0x6a 5 \
			mp2975 0x6e 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			tmp102 0x49 15 \
			tps53679 0x58 15 \
			tps53679 0x61 15 \
			24c32 0x50 16)

msn4700_A1_dis_table=(	0x6d 5 \
			0x62 5 \
			0x64 5 \
			0x66 5 \
			0x6a 5 \
			0x6e 5 \
			0x49 7 \
			0x4a 7 \
			0x51 8 \
			0x6d 15 \
			0x49 15 \
			0x58 15 \
			0x61 15 \
			0x50 16)

msn3510_connect_table=(	max11603 0x6d 5 \
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

msn3510_dis_table=(	0x6d 5 \
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

mqm97xx_connect_table=(	max11603 0x6d 5 \
			mp2975 0x62 5 \
			mp2975 0x64 5 \
			mp2888 0x66 5 \
			mp2975 0x68 5 \
			mp2975 0x6C 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x53 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			tmp102 0x49 15 \
			tps53679 0x58 15 \
			tps53679 0x61 15 \
			24c32 0x50 16)

mqm97xx_dis_table=(	0x6d 5 \
			0x62 5 \
			0x64 5 \
			0x66 5 \
			0x68 5 \
			0x6c 5 \
			0x49 7 \
			0x4a 7 \
			0x53 7 \
			0x51 8 \
			0x6d 15 \
			0x49 15 \
			0x58 15 \
			0x61 15 \
			0x50 16)

ACTION=$1

log_err()
{
	logger -t hw-management -p daemon.err "$@"
}

log_info()
{
	logger -t hw-management -p daemon.info "$@"
}

is_module()
{
        /sbin/lsmod | grep -w "$1" > /dev/null
        RC=$?
        return $RC
}

function get_i2c_bus_frequency_default()
{
	# Get I2C base frequency default value.
	# Relevant only to particular system types.
	i2c_freq=$(/usr/bin/iorw -b "$i2c_freq_reg" -r -l1 | awk '{print $5}')
	echo "$i2c_freq" > $config_path/default_i2c_freq
}

function set_i2c_bus_frequency_400KHz()
{
	# Speed-up ASIC I2C driver probing by setting I2C frequency to 400KHz.
	# Relevant only to particular system types.
	if [ -f $config_path/default_i2c_freq ]; then
		/usr/bin/iorw -b "$i2c_freq_reg" -w -l1 -v"$i2c_freq_400"
	fi
}

function restore_i2c_bus_frequency_default()
{
	# Restore I2C base frequency to the default value.
	# Relevant only to particular system types.
	if [ -f $config_path/default_i2c_freq ]; then
		i2c_freq=$(< $config_path/default_i2c_freq)
		/usr/bin/iorw -b "$i2c_freq_reg" -w -l1 -v"$i2c_freq"
	fi
}

function find_regio_sysfs_path()
{
	# Find hwmon{n} sysfs path for regio device
	for path in /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*; do
		if [ -d "$path" ]; then
			name=$(cut "$path"/name -d' ' -f 1)
			if [ "$name" == "mlxreg_io" ]; then
				echo "$path"
				return 0
			fi
		fi
	done

	log_err "mlxreg_io is not loaded"
	return 1
}

# SODIMM temperatures (C) for setting in scale 1000
SODIMM_TEMP_CRIT=95000
SODIMM_TEMP_MAX=85000
SODIMM_TEMP_MIN=0
SODIMM_TEMP_HYST=6000

set_sodimm_temp_limits()
{
	# SODIMM temp reading is not supported on Broadwell-DE Comex.
	# Broadwell-DE Comex can be installed interchangeably with new
	# Coffee Lake Comex on part of systems e.g. on Anaconda.
	# Thus check by CPU type and not by system type.
	case $cpu_type in
		$BDW_CPU)
			return 0
			;;
		*)
			;;
	esac

	if [ ! -d /sys/bus/i2c/drivers/jc42 ]; then
		modprobe jc42 > /dev/null 2>&1
		rc=$?
		if [ $rc -eq 0 ]; then
			while : ; do
				sleep 1
				[[ -d /sys/bus/i2c/drivers/jc42 ]] && break
			done
		else
			return 1
		fi
	fi

	if find /sys/bus/i2c/drivers/jc42/[0-9]*/ | grep -q hwmon ; then
		for temp_sens in /sys/bus/i2c/drivers/jc42/[0-9]*; do
			echo $SODIMM_TEMP_CRIT > "$temp_sens"/hwmon/hwmon*/temp1_crit
			echo $SODIMM_TEMP_MAX > "$temp_sens"/hwmon/hwmon*/temp1_max
			echo $SODIMM_TEMP_MIN > "$temp_sens"/hwmon/hwmon*/temp1_min
			echo $SODIMM_TEMP_HYST > "$temp_sens"/hwmon/hwmon*/temp1_crit_hyst
		done
	else
		return 1
	fi

	return 0
}

set_jtag_gpio()
{
	export_unexport=$1
	# Check where supported and assign appropriate GPIO pin numbers
	# for JTAG bit-banging operations.
	# GPIO pin numbers are offset from gpiobase.
	case $cpu_type in
		$BDW_CPU)
			jtag_tck=15
			jtag_tms=24
			jtag_tdo=27
			jtag_tdi=28
			;;
		$CFL_CPU)
			jtag_tdi=99
			jtag_tdo=100
			jtag_tms=101
			jtag_tck=102
			;;
		*)
			return 0
			;;
	esac

	if find /sys/class/gpio/gpiochip* | grep -q base; then
		echo "gpio controller driver is not loaded"
		return 1
	fi

	if [ "$export_unexport" == "export" ]; then
		if [ ! -d $jtag_path ]; then
			mkdir $jtag_path
		fi

		if find /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/ | grep -q jtag_enable ; then
			ln -sf /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/jtag_enable $jtag_path/jtag_enable
		fi
	fi

	gpiobase=$(</sys/class/gpio/gpiochip*/base)

	gpio_tck=$((gpiobase+jtag_tck))
	echo $gpio_tck > /sys/class/gpio/"$export_unexport"

	gpio_tms=$((gpiobase+jtag_tms))
	echo $gpio_tms > /sys/class/gpio/"$export_unexport"

	gpio_tdo=$((gpiobase+jtag_tdo))
	echo $gpio_tdo > /sys/class/gpio/"$export_unexport"

	gpio_tdi=$((gpiobase+jtag_tdi))
	echo $gpio_tdi > /sys/class/gpio/"$export_unexport"

	if [ "$export_unexport" == "export" ]; then
		ln -sf /sys/class/gpio/gpio$gpio_tck $jtag_path/jtag_tck
		ln -sf /sys/class/gpio/gpio$gpio_tms $jtag_path/jtag_tms
		ln -sf /sys/class/gpio/gpio$gpio_tdo $jtag_path/jtag_tdo
		ln -sf /sys/class/gpio/gpio$gpio_tdi $jtag_path/jtag_tdi
	fi
}

msn274x_specific()
{
	connect_size=${#msn2740_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn2740_connect_table[i]}
	done
	disconnect_size=${#msn2740_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn2740_dis_table[i]}
	done

	thermal_type=$thermal_type_t3
	max_tachos=4
	hotplug_fans=4
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo 5 > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn2740_sensors.conf"
}

msn21xx_specific()
{
	connect_size=${#msn2100_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn2100_connect_table[i]}
	done
	disconnect_size=${#msn2100_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn2100_dis_table[i]}
	done

	thermal_type=$thermal_type_t2
	max_tachos=4
	hotplug_psus=0
	hotplug_fans=0
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 13000 > $config_path/psu_fan_max
	echo 1040 > $config_path/psu_fan_min
	echo 5 > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
	echo cpld1 > $config_path/cpld_port
	lm_sensors_config="$lm_sensors_configs_path/msn2100_sensors.conf"
}

msn24xx_specific()
{
	connect_size=${#msn2700_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
	hotplug_fans=4
	echo 21000 > $config_path/fan_max_speed
	echo 5400 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
	echo cpld3 > $config_path/cpld_port
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn2700_sensors.conf"
}

msn27xx_msb_msx_specific()
{
	connect_size=${#msn2700_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
	hotplug_fans=4
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo 9 > $config_path/fan_inversed
	echo 3 > $config_path/cpld_num
	echo cpld3 > $config_path/cpld_port
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn2700_sensors.conf"
	get_i2c_bus_frequency_default
}

msn201x_specific()
{
	connect_size=${#msn2010_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn2010_connect_table[i]}
	done
	disconnect_size=${#msn2010_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn2010_dis_table[i]}
	done

	thermal_type=$thermal_type_t4
	max_tachos=4
	hotplug_psus=0
	hotplug_fans=0
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 13000 > $config_path/psu_fan_max
	echo 1040 > $config_path/psu_fan_min
	echo 5 > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn2010_sensors.conf"
}

mqmxxx_msn37x_msn34x_specific()
{
	connect_size=${#mqm8700_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${mqm8700_connect_table[i]}
	done
	disconnect_size=${#mqm8700_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${mqm8700_dis_table[i]}
	done

	tune_thermal_type=1
	thermal_type=$thermal_type_t5
	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	get_i2c_bus_frequency_default
}

msn3420_specific()
{
	connect_size=${#msn3420_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn3420_connect_table[i]}
	done
	disconnect_size=${#msn3420_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn3420_dis_table[i]}
	done

	thermal_type=$thermal_type_t9
	max_tachos=10
	hotplug_fans=5
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
}

msn38xx_specific()
{
	connect_size=${#msn3800_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn3800_connect_table[i]}
	done
	disconnect_size=${#msn3800_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn3800_dis_table[i]}
	done

	thermal_type=$thermal_type_t7
	max_tachos=3
	hotplug_fans=3
	echo 11000 > $config_path/fan_max_speed
	echo 2235 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 4 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3800_sensors.conf"
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
	hotplug_fans=4
	echo 21000 > $config_path/fan_max_speed
	echo 5400 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo 9 > $config_path/fan_inversed
	echo 4 > $config_path/cpld_num
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	echo 24c02 > $config_path/psu_eeprom_type
	get_i2c_bus_frequency_default
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
	hotplug_fans=4
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo 9 > $config_path/fan_inversed
	echo 4 > $config_path/cpld_num
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	echo 24c02 > $config_path/psu_eeprom_type
}

connect_msn4700_msn4600()
{
	connect_size=${#msn4700_msn4600_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn4700_msn4600_connect_table[i]}
	done
	disconnect_size=${#msn4700_msn4600_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn4700_msn4600_dis_table[i]}
	done
}

connect_msn4700_A1()
{
	connect_size=${#msn4700_A1_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn4700_A1_connect_table[i]}
	done
	disconnect_size=${#msn4700_A1_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn4700_A1_dis_table[i]}
	done
	lm_sensors_config="$lm_sensors_configs_path/msn4700_sensors.conf"
}

msn47xx_specific()
{
	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
		case $sys_ver in
			1)
				connect_msn4700_A1
			;;
			*)
				connect_msn4700_msn4600
			;;
		esac
	else
		connect_msn4700_msn4600
	fi

	thermal_type=$thermal_type_t10
	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
}

msn46xx_specific()
{
	connect_size=${#msn4700_msn4600_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn4700_msn4600_connect_table[i]}
	done
	disconnect_size=${#msn4700_msn4600_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn4700_msn4600_dis_table[i]}
	done

	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	# this is MSN4600C
	if [ "$sku" == "HI124" ]; then
		thermal_type=$thermal_type_t8
		echo 11000 > $config_path/fan_max_speed
		echo 2235 > $config_path/fan_min_speed
	# this is MSN4600
	else
		thermal_type=$thermal_type_def
		echo 19500 > $config_path/fan_max_speed
		echo 2800 > $config_path/fan_min_speed
	fi

	max_tachos=3
	hotplug_fans=3
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
}

msn3510_specific()
{
	connect_size=${#msn3510_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${msn3510_connect_table[i]}
	done
	disconnect_size=${#msn3510_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${msn3510_dis_table[i]}
	done

	thermal_type=$thermal_type_def
	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
}

mqm97xx_specific()
{
	connect_size=${#mqm97xx_connect_table[@]}
	for ((i=0; i<connect_size; i++)); do
		connect_table[i]=${mqm97xx_connect_table[i]}
	done
	disconnect_size=${#mqm97xx_dis_table[@]}
	for ((i=0; i<disconnect_size; i++)); do
		dis_table[i]=${mqm97xx_dis_table[i]}
	done

	thermal_type=$thermal_type_def
	max_tachos=14
	echo 29500 > $config_path/fan_max_speed
	echo 5000 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	#lm_sensors_config="$lm_sensors_configs_path/msn4700_sensors.conf"
}

msn_spc2_common()
{
	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	case $sku in
		HI120)
			msn3420_specific
			;;
		HI121)
			msn3510_specific
			;;
		*)
			mqmxxx_msn37x_msn34x_specific
			;;
	esac
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
}

msn_spc3_common()
{
	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	case $sku in
		HI123|HI124)
			msn46xx_specific
		;;
		HI122)
			msn47xx_specific
		;;
		HI130)
			mqm97xx_specific
		;;
		*)
			msn47xx_specific
		;;
	esac
	lm_sensors_config="$lm_sensors_configs_path/msn4700_sensors.conf"
}

check_cpu_type()
{
	family_num=$(grep -m1 "cpu family" /proc/cpuinfo | awk '{print $4}')
	model_num=$(grep -m1 model /proc/cpuinfo | awk '{print $3}')
	cpu_type=$(printf "0x%X%X" "$family_num" "$model_num")
}

check_system()
{
	check_cpu_type
	# Check ODM
	board=$(< /sys/devices/virtual/dmi/id/board_name)
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
			msn_spc2_common
			;;
		VMOD0007)
			msn38xx_specific
			;;
		VMOD0009)
			msn27002_msb78002_specific
			;;
		VMOD0010)
			msn_spc3_common
			;;
		*)
			product=$(< /sys/devices/virtual/dmi/id/product_name)
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
				MSN35*)
					msn3510_specific
					;;
				MSN38*)
					msn38xx_specific
					;;
				MSN46*)
					msn46xx_specific
					;;
				MQM97*)
					mqm97xx_specific
					;;
				*)
					# Check marginal system, system without SMBIOS customization,
					# only on old types of Mellanox switches.
					if grep -q "Mellanox Technologies" /sys/devices/virtual/dmi/id/chassis_vendor ; then
						case $cpu_type in
							$RNG_CPU)
								msn21xx_specific
								;;
							$IVB_CPU)
								msn27xx_msb_msx_specific
								;;
							$BDW_CPU)
								mqmxxx_msn37x_msn34x_specific
								;;
							*)
								log_err "$product is not supported"
								exit 0
								;;
						esac
					else
						log_err "$product is not supported"
						exit 0
					fi
					;;
			esac
			;;
	esac
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

create_event_files()
{
	if [ $hotplug_psus -ne 0 ]; then
		for ((i=1; i<=hotplug_psus; i+=1)); do
			touch $events_path/psu$i
		done
	fi
	if [ $hotplug_pwrs -ne 0 ]; then
		for ((i=1; i<=hotplug_pwrs; i+=1)); do
			touch $events_path/pwr$i
		done
	fi
	if [ $hotplug_fans -ne 0 ]; then
		for ((i=1; i<=hotplug_fans; i+=1)); do
			touch $events_path/fan$i
		done
	fi
}

set_config_data()
{
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
	echo $hotplug_psus > $config_path/hotplug_psus
	echo $hotplug_pwrs > $config_path/hotplug_pwrs
	echo $hotplug_fans > $config_path/hotplug_fans
}

connect_platform()
{
	for ((i=0; i<connect_size; i+=3)); do
		connect_device "${connect_table[i]}" "${connect_table[i+1]}" \
				"${connect_table[i+2]}"
	done
}

disconnect_platform()
{
	for ((i=0; i<disconnect_size; i+=2)); do
		disconnect_device "${dis_table[i]}" "${dis_table[i+1]}"
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
	if [ ! -d $events_path ]; then
		mkdir $events_path
	fi
	if [ ! -h $power_path/pwr_consum ]; then
		ln -sf /usr/bin/hw-management-power-helper.sh $power_path/pwr_consum
	fi
	if [ ! -h $power_path/pwr_sys ]; then
		ln -sf /usr/bin/hw-management-power-helper.sh $power_path/pwr_sys
	fi
	touch $udev_ready
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
	set_sodimm_temp_limits
	set_jtag_gpio "export"
	set_config_data
	find_i2c_bus
	asic_bus=$((i2c_asic_bus_default+i2c_bus_offset))
	echo $asic_bus > $config_path/asic_bus
	create_event_files
	connect_platform
	sleep 1
	/usr/bin/hw-management-start-post.sh

	if [ -f $config_path/max_tachos ]; then
		max_tachos=$(<$config_path/max_tachos)
	fi

	# check for MSN3700C exeption
	if [ "$max_tachos" == 8 ] && [ "$tune_thermal_type" == 1 ]; then
		thermal_type=$thermal_type_t6
	fi
	# Information for thermal control service
	echo $thermal_type > $config_path/thermal_type

	if [ -v "lm_sensors_config" ] && [ -f $lm_sensors_config ]; then
		ln -sf $lm_sensors_config $config_path/lm_sensors_config
	else
		ln -sf /etc/sensors3.conf $config_path/lm_sensors_config
	fi
}

do_stop()
{
	check_system
	disconnect_platform
	set_jtag_gpio "unexport"
	rm -fR /var/run/hw-management
	# Re-try removing after 1 second in case of failure.
	# It can happens if some app locked file for reading/writing
	if [ "$?" -ne 0 ]; then
		sleep 1
		rm -fR /var/run/hw-management
	fi
}

function lock_service_state_change()
{
	exec {LOCKFD}>${LOCKFILE}
	/usr/bin/flock -x ${LOCKFD}
	trap '/usr/bin/flock -u ${LOCKFD}' EXIT SIGINT SIGQUIT SIGTERM
}

function unlock_service_state_change()
{
	/usr/bin/flock -u ${LOCKFD}
}

do_chip_up_down()
{
	# Add ASIC device.
	bus=$(< $config_path/asic_bus)

	case $1 in
	0)
		if [ -f /etc/init.d/sxdkernel ]; then
			chipup_delay=$(< $config_path/chipup_delay)
			if [ "$chipup_delay" != "0" ]; then
				# Decline chipup if in wait state.
				[ -f "$config_path/sxcore" ] && sxcore=$(< $config_path/sxcore)
				if [ "$sxcore" ] && [ "$sxcore" -eq "$sxcore_deferred" ]; then
					echo $sxcore_withdraw > $config_path/sxcore
					return
				fi
			fi
		fi
		lock_service_state_change
		chipup_delay=$(< $config_path/chipup_delay)
		echo 1 > $config_path/suspend
		if [ -d /sys/bus/i2c/devices/"$bus"-"$i2c_asic_addr_name" ]; then
			if [ -f /etc/init.d/sxdkernel ]; then
				if [ "$chipup_delay" != "0" ]; then
					[ -f "$config_path/sxcore" ] && sxcore=$(< $config_path/sxcore)
					if [ "$sxcore" ] && [ "$sxcore" -eq "$sxcore_up" ]; then
						echo $sxcore_down > $config_path/sxcore
					else
						unlock_service_state_change
						return
					fi
				fi
			fi
			chipdown_delay=$(< $config_path/chipdown_delay)
			sleep "$chipdown_delay"
			echo $i2c_asic_addr > /sys/bus/i2c/devices/i2c-"$bus"/delete_device
		fi
		unlock_service_state_change
		;;
	1)
		lock_service_state_change
		[ -f "$config_path/chipup_dis" ] && disable=$(< $config_path/chipup_dis)
		if [ "$disable" ] && [ "$disable" -gt 0 ]; then
			disable=$((disable-1))
			echo $disable > $config_path/chipup_dis
			unlock_service_state_change
			exit 0
		fi
		chipup_delay=$(< $config_path/chipup_delay)
		if [ -f /etc/init.d/sxdkernel ]; then
			if [ "$chipup_delay" != "0" ]; then
				# Have delay in order to avoid impact of chip reset,
				# performed by sxcore driver.
				# In case sxcore driver does not reset chip, for example
				# for reboot through kexec - just sleep 'chipup_delay'
				# seconds.
				[ -f "$config_path/sxcore" ] && sxcore=$(< $config_path/sxcore)
				if [ "$sxcore" ] && [ "$sxcore" -eq "$sxcore_down" ]; then
					echo $sxcore_deferred > $config_path/sxcore
				elif [ "$sxcore" ] && [ "$sxcore" -eq "$sxcore_deferred" ]; then
					echo $sxcore_up > $config_path/sxcore
				else
					unlock_service_state_change
					return
				fi
			fi
		fi
		if [ ! -d /sys/bus/i2c/devices/"$bus"-"$i2c_asic_addr_name" ]; then
			sleep "$chipup_delay"
			echo 0 > $config_path/sfp_counter
			if [ -f /etc/init.d/sxdkernel ]; then
				if [ "$chipup_delay" != "0" ]; then
					# Skip if chipup has been dropped.
					[ -f "$config_path/sxcore" ] && sxcore=$(< $config_path/sxcore)
					if [ "$sxcore" ] && [ "$sxcore" -eq "$sxcore_withdraw" ]; then
						echo $sxcore_down > $config_path/sxcore
						unlock_service_state_change
						return
					fi
				fi
			fi
			set_i2c_bus_frequency_400KHz
			echo mlxsw_minimal $i2c_asic_addr > /sys/bus/i2c/devices/i2c-"$bus"/new_device
			restore_i2c_bus_frequency_default
			if [ -f "$config_path/cpld_port" ] && [ -f $system_path/cpld3_version ]; then
				# Append port CPLD version.
				str=$(< $system_path/cpld_base)
				cpld_port=$(< $system_path/cpld3_version)
				str=$str$(printf "_CPLD000000_REV%02d00" "$cpld_port")
				echo "$str" > $system_path/cpld
			fi
			if [ "$chipup_delay" != "0" ]; then
				if [ "$sxcore" ] && [ "$sxcore" -eq "$sxcore_deferred" ]; then
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

__usage="
Usage: $(basename "$0") [Options]

Options:
	start		Start hw-management service, supposed to be
			activated at initialization by system service
			control.
	stop		Stop hw-management service, supposed to be
			activated at system shutdown by system service
			control.
	chipup		Manual activation of ASIC I2C driver.
	chipdown	Manual de-activation of ASIC I2C driver.
	chipupen	Set 'chipup_dis' attribute to zero.
	chipupdis <n>	Set 'chipup_dis' attribute to <n>, when <n>
	thermsuspend	Suspend thermal control (if thermal control is
			activated by hw-management package.
			Not relevant for users who disable hw-management
			thermal control.
	thermresume	Resume thermal control.
			Not relevant for users who disable hw-management
			thermal control.
	restart
	force-reload	Performs hw-management 'stop' and the 'start.
"

case $ACTION in
	start)
		if [ -d /var/run/hw-management ]; then
			log_err "hw-management is already started"
			exit 1
		fi
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
			do_chip_up_down 1 "$2"
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
			echo "$2" > $config_path/chipup_dis
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
		echo "$__usage"
		exit 1
	;;
esac
exit 0
