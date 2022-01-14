#!/bin/bash
################################################################################
# Copyright (c) 2018-2021, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

source hw-management-helpers.sh
board_type=$(< $board_type_file)
# Local constants and variables

thermal_type=$thermal_type_def

i2c_asic_addr=0x48
i2c_asic_addr_name=0048
psu1_i2c_addr=0x59
psu2_i2c_addr=0x58
psu3_i2c_addr=0x5b
psu4_i2c_addr=0x5a
fan_psu_default=0x3c
fan_command=0x3b
chipup_delay_default=0
hotplug_psus=2
hotplug_fans=6
hotplug_pwrs=2
hotplug_linecards=0
i2c_bus_def_off_eeprom_cpu=16
i2c_comex_mon_bus_default=15
lm_sensors_configs_path="/etc/hw-management-sensors"
tune_thermal_type=0
i2c_freq_400=0xf
i2c_freq_reg=0x2004
pn_sanity_offset=62
fan_dir_pn_offset=11
# 46 - F, 52 - R
fan_direction_exhaust=46
fan_direction_intake=52

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

base_cpu_bus_offset=10

# Ivybridge and Rangeley CPU mostly used on SPC1 systems.
cpu_type0_connection_table=(	max11603 0x6d 15 \
			24c32 0x51 16)

# Broadwell CPU, mostly used on SPC2/SPC3 systems.
cpu_type1_connection_table=(	max11603 0x6d 15 \
			tmp102 0x49 15 \
			tps53679 0x58 15 \
			tps53679 0x61 15 \
			24c32 0x50 16)

# CoffeeLake CPU.
cpu_type2_connection_table=(	max11603 0x6d 15 \
			mp2975 0x6b 15 \
			24c32 0x50 16)

msn2700_base_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			24c32 0x51 8 \
			lm75 0x49 17)

msn2100_base_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			lm75 0x4b 7 \
			24c32 0x51 8)

msn2740_base_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x64 5 \
			tmp102 0x49 6 \
			tmp102 0x48 7 \
			24c32 0x51 8)

msn2010_base_connect_table=(	max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			lm75 0x4a 7 \
			lm75 0x4b 7 \
			24c32 0x51 8)

mqm8700_base_connect_table=(	max11603 0x64 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

mqm8700_rev1_base_connect_table=(    max11603 0x64 5 \
			mp2975 0x62 5 \
			mp2975 0x66 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn37xx_secured_connect_table=(    max11603 0x64 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

msn3420_base_connect_table=(	max11603 0x6d 5 \
			xdpe12284 0x62 5 \
			xdpe12284 0x64 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn3800_base_connect_table=( max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tps53679 0x72 5 \
			tps53679 0x73 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn27002_msn24102_msb78002_base_connect_table=( pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			lm75 0x49 17)

msn4700_msn4600_base_connect_table=(	max11603 0x6d 5 \
			xdpe12284 0x62 5 \
			xdpe12284 0x64 5 \
			xdpe12284 0x66 5 \
			xdpe12284 0x68 5 \
			xdpe12284 0x6a 5 \
			xdpe12284 0x6c 5 \
			xdpe12284 0x6e 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn4700_msn4600_A1_base_connect_table=(	max11603 0x6d 5 \
			mp2975 0x62 5 \
			mp2975 0x64 5 \
			mp2975 0x66 5 \
			mp2975 0x6a 5 \
			mp2975 0x6e 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn3510_base_connect_table=(	max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

mqm97xx_base_connect_table=(	max11603 0x6d 5 \
			mp2975 0x62 5 \
			mp2975 0x64 5 \
			mp2888 0x66 5 \
			mp2975 0x68 5 \
			mp2975 0x6C 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x53 7 \
			24c32 0x51 8)

mqm97xx_rev0_base_connect_table=(    max11603 0x6d 5 \
			mp2975 0x62 5 \
			mp2888 0x66 5 \
			mp2975 0x68 5 \
			mp2975 0x6a 5 \
			mp2975 0x6c 5 \
			adt75 0x49 7 \
			adt75 0x4a 7 \
			24c32 0x53 7 \
			24c512 0x51 8)

mqm97xx_rev1_base_connect_table=(    max11603 0x6d 5 \
			mp2975 0x62 5 \
			mp2888 0x66 5 \
			mp2975 0x68 5 \
			mp2975 0x6a 5 \
			mp2975 0x6c 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x53 7 \
			24c512 0x51 8)

mqm97xx_power_base_connect_table=(    max11603 0x6d 5 \
			mp2975 0x62 5 \
			mp2888 0x66 5 \
			mp2975 0x68 5 \
			mp2975 0x6a 5 \
			mp2975 0x6b 5 \
			mp2975 0x6c 5 \
			mp2975 0x6e 5 \
			adt75 0x49 7 \
			adt75 0x4a 7 \
			24c32 0x53 7 \
			24c512 0x51 8)

e3597_base_connect_table=(    max11603 0x6d 5 \
			mp2975 0x22 5 \
			mp2975 0x23 5 \
			mp2975 0x24 5 \
			mp2975 0x25 5 \
			mp2975 0x26 5 \
			mp2975 0x27 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

p4697_base_connect_table=(    max11603 0x6d 7 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

p4697_asic_i2c_bus_connect_table=(  mp2975 0x23 18 voltmon1 \
			mp2975 0x25 18 voltmon2 \
			mp2975 0x27 18 voltmon3 \
			mp2975 0x23 23 voltmon4 \
			mp2975 0x25 23 voltmon5 \
			mp2975 0x27 23 voltmon6)
  
msn4800_base_connect_table=( mp2975 0x62 5 \
	mp2975 0x64 5 \
	mp2975 0x66 5 \
	mp2975 0x68 5 \
	mp2975 0x6a 5 \
	max11603 0x6d 7 \
	max11603 0x64 7 \
	24c32 0x51 8 \
	tmp102 0x49 12 \
	tmp421 0x1f 14 \
	max11603 0x6d 43 \
	tmp102 0x4a 44 \
	24c32 0x51 45)

ACTION=$1

if [ "$board_type" == "VMOD0014" ]; then
	i2c_bus_max=14
	psu1_i2c_addr=0x58
	psu2_i2c_addr=0x58
fi

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
	case $board_type in 
	VMOD0014)
		for path in /sys/devices/pci0000:00/*/NVSN2201:*/mlxreg-io/hwmon/hwmon*; do
			if [ -d "$path" ]; then
				name=$(cut "$path"/name -d' ' -f 1)
				if [ "$name" == "mlxreg_io" ]; then
					echo "$path"
					return 0
				fi
			fi
		done
		;;
	*)
		for path in /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*; do
			if [ -d "$path" ]; then
				name=$(cut "$path"/name -d' ' -f 1)
				if [ "$name" == "mlxreg_io" ]; then
					echo "$path"
					return 0
				fi
			fi
		done
		;;
	esac

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
			jtag_tdi=128
			jtag_tdo=129
			jtag_tms=130
			jtag_tck=131
			;;
		$DNV_CPU)
			jtag_tck=87
			jtag_tms=88
			jtag_tdo=86
			jtag_tdi=89
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

		if [ "$board_type" != "VMOD0014" ]; then
			if find /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/ | grep -q jtag_enable ; then
				ln -sf /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/jtag_enable $jtag_path/jtag_enable
			fi
		fi
	fi

	# Gpiochip358 is used for CPU GPIO and gpiochip342 is used for PCA9555 Extender in SN2201. 
	if [ "$board_type" == "VMOD0014" ]; then
		gpiobase=$(</sys/class/gpio/gpiochip358/base)
	else
		gpiobase=$(</sys/class/gpio/gpiochip*/base)
	fi

	gpio_tck=$((gpiobase+jtag_tck))
	echo $gpio_tck > /sys/class/gpio/"$export_unexport"

	gpio_tms=$((gpiobase+jtag_tms))
	echo $gpio_tms > /sys/class/gpio/"$export_unexport"

	gpio_tdo=$((gpiobase+jtag_tdo))
	echo $gpio_tdo > /sys/class/gpio/"$export_unexport"

	gpio_tdi=$((gpiobase+jtag_tdi))
	echo $gpio_tdi > /sys/class/gpio/"$export_unexport"

	# In SN2201 system. 
	# GPIO0 for CPU request to reset the Main Board I2C Mux.
	# GPIO1 for CPU control the CPU Board MUX when doing the ISP programming. 
	# GPIO13 for CPU request Main Board JTAG control signal. 
	if [ "$board_type" == "VMOD0014" ]; then
		mux_reset=27
		jtag_mux_en=33
		jtag_ena=60
		gpio_mux_rst=$((gpiobase+mux_reset))
		gpio_jtag_mux_en=$((gpiobase+jtag_mux_en))
		gpio_jtag_enable=$((gpiobase+jtag_ena))
		echo $gpio_mux_rst > /sys/class/gpio/"$export_unexport"
		echo $gpio_jtag_mux_en > /sys/class/gpio/"$export_unexport"
		echo $gpio_jtag_enable > /sys/class/gpio/"$export_unexport"
	fi

	if [ "$export_unexport" == "export" ]; then
		ln -sf /sys/class/gpio/gpio$gpio_tck/value $jtag_path/jtag_tck
		ln -sf /sys/class/gpio/gpio$gpio_tms/value $jtag_path/jtag_tms
		ln -sf /sys/class/gpio/gpio$gpio_tdo/value $jtag_path/jtag_tdo
		ln -sf /sys/class/gpio/gpio$gpio_tdi/value $jtag_path/jtag_tdi
		if [ "$board_type" == "VMOD0014" ]; then
			check_n_link /sys/class/gpio/gpio$gpio_mux_rst/value $system_path/mux_reset
			check_n_link /sys/class/gpio/gpio$gpio_jtag_mux_en/value $jtag_path/jtag_mux_en
			check_n_link /sys/class/gpio/gpio$gpio_jtag_enable/value $jtag_path/jtag_enable
		fi
	fi
}

get_fixed_fans_direction()
{
	timeout 5 bash -c 'until [ -L /var/run/hw-management/eeprom/vpd_info ]; do sleep 0.2; done'
	sanity_offset=$(grep MLNX $eeprom_path/vpd_info -b -a -o | cut -f1 -d:)
	fan_dir_offset=$((sanity_offset+pn_sanity_offset+fan_dir_pn_offset))
	fan_direction=$(xxd -u -p -l 1 -s $fan_dir_offset $eeprom_path/vpd_info)
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

add_cpu_board_to_connection_table()
{
	local cpu_connection_table=( )
	case $cpu_type in
		$RNG_CPU|$IVB_CPU)
			cpu_connection_table=( ${cpu_type0_connection_table[@]} )
			;;
		$BDW_CPU)
			cpu_connection_table=( ${cpu_type1_connection_table[@]} )
			;;
		$CFL_CPU)
			cpu_connection_table=( ${cpu_type2_connection_table[@]} )
			;;
		*)
			log_err "$product is not supported"
			exit 0
			;;
	esac

	# $1 - cpu bus offset.
	if [ ! -z "$1" ]; then
		local cpu_bus_offset=$1
		for ((i=0; i<${#cpu_connection_table[@]}; i+=3)); do
			cpu_connection_table[$i+2]=$(( cpu_connection_table[i+2]-base_cpu_bus_offset+cpu_bus_offset ))
		done
	fi

	connect_table+=(${cpu_connection_table[@]})
}

add_i2c_dynamic_bus_dev_connection_table()
{
	connection_table=("$@")
	dynamic_i2cbus_connection_table=""

	echo "${connection_table[@]}" > $config_path/i2c_bus_connect_devs
	for ((i=0; i<${#connection_table[@]}; i+=4)); do
		dynamic_i2cbus_connection_table[$i]="${connection_table[i]}"
		dynamic_i2cbus_connection_table[$i+1]="${connection_table[i+1]}"
		dynamic_i2cbus_connection_table[$i+2]="${connection_table[i+2]}"
	done

	connect_table+=(${dynamic_i2cbus_connection_table[@]})
}

msn274x_specific()
{
	connect_table=(${msn2740_base_connect_table[@]})
	add_cpu_board_to_connection_table

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
	connect_table=(${msn2100_base_connect_table[@]})
	add_cpu_board_to_connection_table

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
	lm_sensors_config="$lm_sensors_configs_path/msn2100_sensors.conf"
	echo 4 > $config_path/fan_drwr_num
	echo 1 > $config_path/fixed_fans_system
}

msn24xx_specific()
{
	connect_table=(${msn2700_base_connect_table[@]})
	add_cpu_board_to_connection_table

	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	case $sku in
		HI138)
			hotplug_fans=0
			max_tachos=0
		;;
		*)
			thermal_type=$thermal_type_t1
			max_tachos=8
			hotplug_fans=4
			echo 21000 > $config_path/fan_max_speed
			echo 5400 > $config_path/fan_min_speed
			echo 18000 > $config_path/psu_fan_max
			echo 2000 > $config_path/psu_fan_min
			echo 9 > $config_path/fan_inversed
			echo 24c02 > $config_path/psu_eeprom_type
			;;
	esac

	echo 3 > $config_path/cpld_num
	echo cpld3 > $config_path/cpld_port

	lm_sensors_config="$lm_sensors_configs_path/msn2700_sensors.conf"
}

msn27xx_msb_msx_specific()
{
	connect_table=(${msn2700_base_connect_table[@]})
	add_cpu_board_to_connection_table

	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	case $sku in
		HI138)
			hotplug_fans=0
			max_tachos=0
		;;
		*)
			thermal_type=$thermal_type_t1
			max_tachos=8
			hotplug_fans=4
			echo 25000 > $config_path/fan_max_speed
			echo 1500 > $config_path/fan_min_speed
			echo 18000 > $config_path/psu_fan_max
			echo 2000 > $config_path/psu_fan_min
			echo 9 > $config_path/fan_inversed
			echo 24c02 > $config_path/psu_eeprom_type
			;;
	esac

	product=$(< /sys/devices/virtual/dmi/id/product_name)
	case $product in
		MSB78*)
			echo 2 > $config_path/cpld_num
		;;
		*)
			echo 3 > $config_path/cpld_num
		;;
	esac

	echo cpld3 > $config_path/cpld_port

	lm_sensors_config="$lm_sensors_configs_path/msn2700_sensors.conf"
	get_i2c_bus_frequency_default
}

msn201x_specific()
{
	connect_table=(${msn2010_base_connect_table[@]})
	add_cpu_board_to_connection_table

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
	echo 4 > $config_path/fan_drwr_num
	echo 1 > $config_path/fixed_fans_system
}

mqmxxx_msn37x_msn34x_specific()
{
	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	case $sku in
		HI136)
			connect_table=(${msn37xx_secured_connect_table[@]})
		;;
		*)
			connect_table=(${mqm8700_base_connect_table[@]})
		;;
	esac

	add_cpu_board_to_connection_table

	tune_thermal_type=1
	thermal_type=$thermal_type_t5
	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 25000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	get_i2c_bus_frequency_default
}

msn3420_specific()
{
	connect_table=(${msn3420_base_connect_table[@]})
	add_cpu_board_to_connection_table

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

msn_xh3000_specific()
{
	connect_table=(${mqm8700_base_connect_table[@]})
	add_cpu_board_to_connection_table
	hotplug_fans=0
	hotplug_psus=0
	hotplug_pwrs=0
	max_tachos=0
	tune_thermal_type=1
	thermal_type=$thermal_type_t5
	echo 3 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	get_i2c_bus_frequency_default
}

msn38xx_specific()
{
	connect_table=(${msn3800_base_connect_table[@]})
	add_cpu_board_to_connection_table

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
	local cpu_bus_offset=18
	# This system do not use auto detected cpu conection table.
	connect_table=(${msn27002_msn24102_msb78002_base_connect_table[@]})
	add_cpu_board_to_connection_table $cpu_bus_offset

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
	local cpu_bus_offset=18
	# This system do not use auto detected cpu conection table.
	connect_table=(${msn27002_msn24102_msb78002_base_connect_table[@]})
	add_cpu_board_to_connection_table $cpu_bus_offset

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
	connect_table=(${msn4700_msn4600_base_connect_table[@]})
	add_cpu_board_to_connection_table
	lm_sensors_config="$lm_sensors_configs_path/msn4700_sensors.conf"
}

connect_msn4700_msn4600_A1()
{
	connect_table=(${msn4700_msn4600_A1_base_connect_table[@]})
	add_cpu_board_to_connection_table
	lm_sensors_config="$lm_sensors_configs_path/msn4700_respin_sensors.conf"
}

msn47xx_specific()
{
	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
		case $sys_ver in
			1)
				connect_msn4700_msn4600_A1
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
	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
		case $sys_ver in
			1|3)
				connect_msn4700_msn4600_A1
			;;
			*)
				connect_msn4700_msn4600
			;;
		esac
	else
		connect_msn4700_msn4600
	fi

	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	# this is MSN4600C
	if [ "$sku" == "HI124" ]; then
		thermal_type=$thermal_type_t8
		echo 11000 > $config_path/fan_max_speed
		echo 2235 > $config_path/fan_min_speed
	# this is MSN4600
	else
		thermal_type=$thermal_type_t12
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
	connect_table=(${msn3510_base_connect_table[@]})
	add_cpu_board_to_connection_table

	thermal_type=$thermal_type_def
	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
}

mqm97xx_specific()
{
	lm_sensors_config="$lm_sensors_configs_path/mqm9700_sensors.conf"

	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
		case $sys_ver in
			0)
				connect_table=(${mqm97xx_rev0_base_connect_table[@]})
				lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
				;;
			1)
				connect_table=(${mqm97xx_rev1_base_connect_table[@]})
				lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
				;;
			7)
				connect_table=(${mqm97xx_power_base_connect_table[@]})
				lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
				;;
			*)
				connect_table=(${mqm97xx_base_connect_table[@]})
				;;
		esac
	else
		connect_table=(${mqm97xx_base_connect_table[@]})
	fi

	add_cpu_board_to_connection_table

	thermal_type=$thermal_type_def
	max_tachos=14
	hotplug_fans=7
	echo 29500 > $config_path/fan_max_speed
	echo 5000 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
}

mqm87xx_rev1_specific()
{
	connect_table=(${mqm8700_rev1_base_connect_table[@]})
	add_cpu_board_to_connection_table

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

e3597_specific()
{
	connect_table=(${e3597_base_connect_table[@]})
	add_cpu_board_to_connection_table

	thermal_type=$thermal_type_def
	max_tachos=14
	hotplug_fans=7
	i2c_asic_addr=0xff
	# TODO set correct PSU/case FAN speed
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 4 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/e3597_sensors.conf"
}

p4697_specific()
{
	connect_table=(${p4697_base_connect_table[@]})

	add_i2c_dynamic_bus_dev_connection_table "${p4697_asic_i2c_bus_connect_table[@]}"
	add_cpu_board_to_connection_table

	thermal_type=$thermal_type_def
	max_tachos=14
	hotplug_fans=7
	i2c_asic_addr=0xff

	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 4 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
}

msn_spc2_common()
{
	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
	else
		sys_ver=0
	fi

	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	case $sku in
		HI120)
			msn3420_specific
			;;
		HI121)
			msn3510_specific
			;;
		HI100)
			case $sys_ver in
				2)
					mqm87xx_rev1_specific
					;;
				*)
					mqmxxx_msn37x_msn34x_specific
					;;
			esac
			;;
		HI139)
			msn_xh3000_specific
			;;
		*)
			mqmxxx_msn37x_msn34x_specific
			;;
	esac
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
		HI132)
			e3597_specific
		;;
		HI142)
			p4697_specific
		;;
		*)
			msn47xx_specific
		;;
	esac
}

msn48xx_specific()
{
	local cpu_bus_offset=51
	connect_table=(${msn4800_base_connect_table[@]})
	add_cpu_board_to_connection_table $cpu_bus_offset
	thermal_type=$thermal_type_def
	hotplug_linecards=8
	i2c_comex_mon_bus_default=$((cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((cpu_bus_offset+6))
	echo 4 > $config_path/cpld_num
	hotplug_pwrs=4
	hotplug_psus=4
	i2c_asic_bus_default=3
	echo 22000 > $config_path/fan_max_speed
	echo 3000 > $config_path/fan_min_speed
	echo 27500 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 14 > $config_path/pcie_default_i2c_bus
	lm_sensors_config="$lm_sensors_configs_path/msn4800_sensors.conf"
	# TMP for Buffalo BU
	iorw -b 0x2004 -w -l1 -v0x3f
}

sn2201_specific()
{
	local cpu_bus_offset=51
	echo 2 > $config_path/cpld_num
	thermal_type=$thermal_type_t11
	i2c_asic_bus_default=6
	hotplug_fans=4
	hotplug_pwrs=2
	hotplug_psus=2
	echo 22000 > $config_path/fan_max_speed
	echo 960 > $config_path/fan_min_speed
	echo 16000 > $config_path/psu_fan_max
	echo 2500 > $config_path/psu_fan_min
	cpld2=$(i2cget -f -y 1 0x3d 0x01)
	cpld2=${cpld2:2}
	echo $(( 16#$cpld2 )) > $system_path/cpld2_version
	lm_sensors_config="$lm_sensors_configs_path/sn2201_sensors.conf"
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
		VMOD0011)
			msn48xx_specific
			;;
		VMOD0014)
			sn2201_specific
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
				MQM87*)
					mqm87xx_specific
					;;
				SN2201*)
					sn2201_specific
					;;
				P4697)
					p4697_specific
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
	echo ${i2c_comex_mon_bus_default} > $config_path/i2c_comex_mon_bus_default
	echo ${i2c_bus_def_off_eeprom_cpu} > $config_path/i2c_bus_def_off_eeprom_cpu
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
	if [ $hotplug_linecards -ne 0 ]; then
		for ((i=1; i<=hotplug_linecards; i+=1)); do
			touch $events_path/lc"$i"_prsnt
			touch $events_path/lc"$i"_verified
			touch $events_path/lc"$i"_powered
			touch $events_path/lc"$i"_ready
			touch $events_path/lc"$i"_synced
			touch $events_path/lc"$i"_active
			touch $events_path/lc"$i"_shutdown
		done
	fi
}

get_asic_bus()
{
	if [[ $i2c_asic_addr -eq 0xff ]]; then
		log_err "This operation not supporting with current ASIC type"
		return 0
	fi
	if [ ! -f $config_path/asic_bus ]; then
		find_i2c_bus
		asic_bus=$((i2c_asic_bus_default+i2c_bus_offset))
		echo $asic_bus > $config_path/asic_bus
	else
		asic_bus=$(cat $config_path/asic_bus)
	fi
	return $((asic_bus))
}

set_config_data()
{
	echo $psu1_i2c_addr > $config_path/psu1_i2c_addr
	echo $psu2_i2c_addr > $config_path/psu2_i2c_addr
	echo $psu3_i2c_addr > $config_path/psu3_i2c_addr
	echo $psu4_i2c_addr > $config_path/psu4_i2c_addr
	# TMP for Buffalo BU
	case $board_type in
	VMOD0011)
		echo 0x64 > $config_path/fan_psu_default
		;;
	*)
		echo $fan_psu_default > $config_path/fan_psu_default
		;;
	esac
	echo $fan_command > $config_path/fan_command
	echo 35 > $config_path/thermal_delay
	echo $chipup_delay_default > $config_path/chipup_delay
	echo 0 > $config_path/chipdown_delay
	echo $hotplug_psus > $config_path/hotplug_psus
	echo $hotplug_pwrs > $config_path/hotplug_pwrs
	echo $hotplug_fans > $config_path/hotplug_fans
	echo $hotplug_linecards > $config_path/hotplug_linecards
}

connect_platform()
{
	find_i2c_bus
	for ((i=0; i<${#connect_table[@]}; i+=3)); do
		connect_device "${connect_table[i]}" "${connect_table[i+1]}" \
				"${connect_table[i+2]}"
	done
}

disconnect_platform()
{
	if [ -f $config_path/i2c_bus_offset ]; then
		i2c_bus_offset=$(<$config_path/i2c_bus_offset)
	fi
	for ((i=0; i<${#connect_table[@]}; i+=3)); do
		disconnect_device "${connect_table[i+1]}" "${connect_table[i+2]}"
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
	if [ ! -d $fw_path ]; then
		mkdir $fw_path
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
	if [[ $i2c_asic_addr -ne 0xff ]]; then
		get_asic_bus
	fi
	touch $udev_ready
	depmod -a 2>/dev/null
	udevadm trigger --action=add
	set_sodimm_temp_limits
	set_jtag_gpio "export"
	set_config_data
	create_event_files
	hw-management-i2c-gpio-expander.sh
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
	if [ -f $config_path/fixed_fans_system ] && [ "$(< $config_path/fixed_fans_system)" = 1 ]; then
		get_fixed_fans_direction
		if [ -f $config_path/fixed_fans_dir ]; then
			for i in $(seq 1 "$(< $config_path/fan_drwr_num)"); do
				cat $config_path/fixed_fans_dir > $thermal_path/fan"$i"_dir
			done
		fi
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

do_chip_up_down()
{
	action=$1
	# Add ASIC device.
	if [[ $i2c_asic_addr -eq 0xff ]]; then
		log_info "Current ASIC type does not support this operation type"
		return 0
	fi
	board=$(cat /sys/devices/virtual/dmi/id/board_name)
	case $board in
	VMOD0011)
		# Chip up / down operations are to be performed for ASIC virtual address 0x37.
		i2c_asic_addr_name=0037
		i2c_asic_addr=0x37
		i2c_asic_bus_default=3
		;;
	*)
		;;
	esac

	# Add ASIC device.
	get_asic_bus
	bus=$?

	case $action in
	0)
		lock_service_state_change
		chipup_delay=$(< $config_path/chipup_delay)
		echo 1 > $config_path/suspend
		if [ -d /sys/bus/i2c/devices/"$bus"-"$i2c_asic_addr_name" ]; then
			chipdown_delay=$(< $config_path/chipdown_delay)
			sleep "$chipdown_delay"
			echo $i2c_asic_addr > /sys/bus/i2c/devices/i2c-"$bus"/delete_device
		fi
		echo 0 > $config_path/sfp_counter
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
		if [ ! -d /sys/bus/i2c/devices/"$bus"-"$i2c_asic_addr_name" ]; then
			sleep "$chipup_delay"
			echo 0 > $config_path/sfp_counter
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
		else
			unlock_service_state_change
			return
		fi
		echo 0 > $config_path/suspend
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
