#!/bin/bash

# Copyright (c) 2018 - 2021, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

LED_STATE=/usr/bin/hw-management-led-state-conversion.sh
i2c_bus_def_off_eeprom_vpd=8
i2c_bus_def_off_eeprom_psu=4
i2c_bus_alt_off_eeprom_psu=10
i2c_bus_def_off_eeprom_fan1=11
i2c_bus_def_off_eeprom_fan2=12
i2c_bus_def_off_eeprom_fan3=13
i2c_bus_def_off_eeprom_fan4=14
i2c_bus_def_off_eeprom_mgmt=45
psu1_i2c_addr=0x51
psu2_i2c_addr=0x50
psu3_i2c_addr=0x53
psu4_i2c_addr=0x52
lc_iio_dev_name_def="iio:device0"
eeprom_name=''
fan_dir_offset_in_vpd_eeprom_pn=0x48
# 46 - F, 52 - R
fan_direction_exhaust=46
fan_direction_intake=52
linecard_folders=("alarm" "config" "eeprom" "environment" "led" "system" "thermal")
mlxreg_lc_addr=32
lc_max_num=8

if [ "$board_type" == "VMOD0014" ]; then
	i2c_bus_max=14
	psu1_i2c_addr=0x50
	psu2_i2c_addr=0x50
	i2c_bus_def_off_eeprom_vpd=2
	i2c_bus_def_off_eeprom_psu=3
	i2c_bus_alt_off_eeprom_psu=4
	i2c_bus_def_off_eeprom_fan1=10
	i2c_bus_def_off_eeprom_fan2=11
	i2c_bus_def_off_eeprom_fan3=12
	i2c_bus_def_off_eeprom_fan4=13
fi

# Voltmon sensors by label mapping:
#                   dummy   sensor1       sensor2        sensor3
VOLTMON_SENS_LABEL=("none" "vin\$|vin1"   "vout\$|vout1" "vout2")
CURR_SENS_LABEL=(   "none" "iout\$|iout1" "iout2"        "none")
POWER_SENS_LABEL=(  "none" "pout\$|pout"  "pout2"        "none")

# Find sensor index which label matching to mask.
# $1 - path to sensor in sysfs
# $2 - sensor type ('in', 'curr', 'power'...)
# $3 - mask to matching  label
# return sensor index if match is found or 0 if match not found
find_sensor_by_label()
{
	path=$1
	sens_type=$2
	label_mask=$3
	local i=1
	FILES=$(find "$path"/"$sens_type"*label)
	for label_file in $FILES
	do
			curr_label=$(< "$label_file")
			if [[ $curr_label =~ $label_mask ]]; then
				return $i
			fi
			i=$((i+1))
	done
	# 0 means label by 'pattern' not found.
    return 0
}

linecard_i2c_parent_bus_offset=( \
	34 1 \
	35 2 \
	36 3 \
	37 4 \
	38 5 \
	39 6 \
	40 7 \
	41 8)

linecard_i2c_busses=( \
	"vr" \
	"a2d" \
	"hotswap" \
	"fru" \
	"ini" \
	"fpga1" \
	"gearbox00" \
	"gearbox01" \
	"gearbox02" \
	"gearbox03" \
	"transceiver01" \
	"transceiver02" \
	"transceiver03" \
	"transceiver04" \
	"transceiver05" \
	"transceiver06" \
	"transceiver07" \
	"transceiver08" \
	"transceiver09" \
	"transceiver10" \
	"transceiver11" \
	"transceiver12" \
	"transceiver13" \
	"transceiver14" \
	"transceiver15" \
	"transceiver16")

create_linecard_i2c_links()
{
	local counter=0

	if [ ! -d /dev/lc"$1" ]; then
		mkdir /dev/lc"$1"
	fi

        list=$(find /sys/class/i2c-adapter/i2c-"$2"/ -maxdepth 1  -name '*i2c-*' ! -name i2c-dev ! -name i2c-"$2" -exec bash -c 'name=$(basename $0); name="${name:4}"; echo "$name" ' {} \;)
        list_sorted=`for name in "$list"; do echo "$name"; done | sort -V`
	for name in $list_sorted; do
		sym_name=${linecard_i2c_busses[counter]}
		ln -s /dev/i2c-"$name" /dev/lc"$1"/"$sym_name"
		counter=$((counter+1))
	done
}

destroy_linecard_i2c_links()
{
	rm -rf /dev/lc"$1"
}

find_linecard_match()
{
	local input_bus_num
	local lc_bus_offset
	local lc_bus_num
	local lc_num
	local size

	input_bus_num="$1"
	i2c_bus_offset=$(< $config_path/i2c_bus_offset)
	size=${#linecard_i2c_parent_bus_offset[@]}
	for ((i=0; i<size; i+=2)); do
		lc_bus_offset="${linecard_i2c_parent_bus_offset[i]}"
		lc_num="${linecard_i2c_parent_bus_offset[$((i+1))]}"
		lc_bus_num=$((lc_bus_offset+i2c_bus_offset))
		if [ "$lc_bus_num" -eq "$input_bus_num" ]; then
			create_linecard_i2c_links "$lc_num" "$input_bus_num"
			return
		fi
	done
}

find_linecard_num()
{
	local input_bus_num="$1"
	local lc_bus_offset
	local lc_bus_num
	local lc_num
	local size

	# Find base i2c bus number of line card.
	folder=/sys/bus/i2c/devices/i2c-"$input_bus_num"/"$input_bus_num"-00"$mlxreg_lc_addr"
	if [ -d $folder ]; then
		name=$(cut $folder/name -d' ' -f 1)
		if [ "$name" == "mlxreg-lc" ]; then
			i2c_bus_offset=$(< $config_path/i2c_bus_offset)
			size=${#linecard_i2c_parent_bus_offset[@]}
			for ((i=0; i<size; i+=2)); do
				lc_bus_offset="${linecard_i2c_parent_bus_offset[i]}"
				linecard_num="${linecard_i2c_parent_bus_offset[$((i+1))]}"
				lc_bus_num=$((lc_bus_offset+i2c_bus_offset))
				if [ "$lc_bus_num" -eq "$input_bus_num" ]; then
					if [ "$linecard_num" -le "$lc_max_num" ] &&
					   [ "$linecard_num" -ge 1 ]; then
						return
					else
						log_err "Line card number out of range. $linecard_num Expected range: 1 - $lc_max_num."
						exit 0
					fi
				fi
			done
		fi
	fi

	log_err "mlxreg-lc driver is not loaded"
	exit 0
}

find_eeprom_name()
{
	bus=$1
	addr=$2
	i2c_bus_def_off_eeprom_cpu=$(< $i2c_bus_def_off_eeprom_cpu_file)
	if [ "$bus" -eq "$i2c_bus_def_off_eeprom_vpd" ]; then
		eeprom_name=vpd_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_cpu" ]; then
		eeprom_name=cpu_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_psu" ] ||
		[ "$bus" -eq "$i2c_bus_alt_off_eeprom_psu" ]; then
		case $board_type in
		VMOD0014)
			if [ "$bus" -eq "$i2c_bus_def_off_eeprom_psu" ]; then
				eeprom_name=psu1_info
			elif [ "$bus" -eq "$i2c_bus_alt_off_eeprom_psu" ]; then
				eeprom_name=psu2_info
			fi
			;;
		*)
			if [ "$addr" = "$psu1_i2c_addr" ]; then
				eeprom_name=psu1_info
			elif [ "$addr" = "$psu2_i2c_addr" ]; then
				eeprom_name=psu2_info
			elif [ "$addr" = "$psu3_i2c_addr" ]; then
				eeprom_name=psu3_info
			elif [ "$addr" = "$psu4_i2c_addr" ]; then
				eeprom_name=psu4_info
			fi
			;;
		esac
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan1" ]; then
		eeprom_name=fan1_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan2" ]; then
		eeprom_name=fan2_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan3" ]; then
		eeprom_name=fan3_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan4" ]; then
		eeprom_name=fan4_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_mgmt" ]; then
		eeprom_name=mgmt_info
	elif [ "$bus" -eq 0 ]; then
		:
	else
		# Wait to allow line card symbolic links creation.
		local find_retry=0
		find_linecard_num "$4"
		find_linecard_match "$4"
		lc_dev=$3
		while [ ! $(find -L /dev/lc* -samefile /dev/"$lc_dev") ] && [ $find_retry -lt 3 ]; do sleep 1; done;
		symlink=$(find -L /dev/lc* -samefile /dev/"$lc_dev")
		eeprom_name=$(basename "$symlink")
	fi
}

find_eeprom_name_on_remove()
{
	bus=$1
	addr=$2
	i2c_bus_def_off_eeprom_cpu=$(< $i2c_bus_def_off_eeprom_cpu_file)
	if [ "$bus" -eq "$i2c_bus_def_off_eeprom_vpd" ]; then
		eeprom_name=vpd_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_cpu" ]; then
		eeprom_name=cpu_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_psu" ] ||
		[ "$bus" -eq "$i2c_bus_alt_off_eeprom_psu" ]; then
		case $board_type in
		VMOD0014)
			if [ "$bus" -eq "$i2c_bus_def_off_eeprom_psu" ]; then
				eeprom_name=psu1_info
			elif [ "$bus" -eq "$i2c_bus_alt_off_eeprom_psu" ]; then
				eeprom_name=psu2_info
			fi
			;;
		*)
			if [ "$addr" = "$psu1_i2c_addr" ]; then
				eeprom_name=psu1_info
			elif [ "$addr" = "$psu2_i2c_addr" ]; then
				eeprom_name=psu2_info
			elif [ "$addr" = "$psu3_i2c_addr" ]; then
				eeprom_name=psu3_info
			elif [ "$addr" = "$psu4_i2c_addr" ]; then
				eeprom_name=psu4_info
			fi
			;;
		esac
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan1" ]; then
		eeprom_name=fan1_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan2" ]; then
		eeprom_name=fan2_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan3" ]; then
		eeprom_name=fan3_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan4" ]; then
		eeprom_name=fan4_info
	fi
}

function create_sfp_symbolic_links()
{
	local event_path="${1}"
	local sfp_name=${event_path##*/net/}

	ln -sf /usr/bin/hw-management-sfp-helper.sh ${sfp_path}/"${sfp_name}"_status
}

# ASIC CPLD event
function asic_cpld_add_handler()
{
	local -r ASIC_I2C_PATH="${1}"

	# Verify if CPLD attributes are exist
	if [ -f "$config_path/cpld_port" ]; then
		local  cpld=$(< $config_path/cpld_port)
		if [ "$cpld" == "cpld1" ]; then
			ln -sf "${ASIC_I2C_PATH}"/cpld1_version $system_path/cpld3_version
		fi
		if [ "$cpld" == "cpld3" ] && [ -f "${ASIC_I2C_PATH}"/cpld3_version ]; then
			ln -sf "${ASIC_I2C_PATH}"/cpld3_version $system_path/cpld3_version
		fi
	fi
}

function asic_cpld_remove_handler()
{
	if [ -f "$config_path/cpld_port" ]; then
		if [ -L $system_path/cpld3_version ]; then
			unlink $system_path/cpld3_version
		else
			rm -rf $system_path/cpld3_version
		fi
	fi
}

function set_fan_direction()
{
	attribute=$1
	event=$2
	case $attribute in
	fan*)
		fan_dir=$(< $system_path/fan_dir)
		fandirhex=$(printf "%x\n" "$fan_dir")
		fan_bit_index=$(( ${attribute:3} - 1 ))
		fan_direction_bit=$(( 0x$fandirhex & (1 << fan_bit_index) ))
		fan_direction=($fan_direction_bit ? 1 : 0)
		if [ "$fan_direction_bit" == 0 ]; then
			fan_direction=0;
		else
			fan_direction=1;
		fi
		if [ "$event" == 1 ]; then
			echo "$fan_direction" > $thermal_path/"${attribute}"_dir
		else
			rm -f $thermal_path/"${attribute}"_dir
		fi
		;;
	*)
		;;
	esac
}

function set_lc_fpga_combined_version()
{
	lc_path="$1"
	# Set linecard FPGA combined version.
	if [ -L "$lc_path"/system/fpga1_pn ]; then
		fpga_pn=$(cat "$lc_path"/system/fpga1_pn)
	fi
	if [ -L "$lc_path"/system/fpga1_version ]; then
		fpga_ver=$(cat "$lc_path"/system/fpga1_version)
	fi
	if [ -L "$lc_path"/system/fpga1_version_min ]; then
		fpga_ver_min=$(cat "$lc_path"/system/fpga1_version_min)
	fi
	str=$(printf "FPGA%06d_REV%02d%02d" "$fpga_pn" "$fpga_ver" "$fpga_ver_min")
	echo "$str" > "$lc_path"/system/fpga
}

function handle_hotplug_event()
{
	local attribute
	local event
	local lc_path
	attribute=$(echo "$1" | awk '{print tolower($0)}')
	event=$2
	
	if [ -f $events_path/"$attribute" ]; then
		echo "$event" > $events_path/"$attribute"
		log_info "Event ${event} is received for attribute ${attribute}"

		case "$attribute" in
		lc*_active)
			linecard=`echo ${attribute:0:3}`
			lc_path="$hw_management_path"/"$linecard"
			set_lc_fpga_combined_version "$lc_path"
			;;
		*)
			;;
		esac
	fi
	set_fan_direction "$attribute" "$event"
}

# Handle i2c bus add/remove.
# If we have some devices which should be connected to this bus - do it.
# $1 - i2c bus full address.
# $2 - i2c bus action type add/remove.
function handle_i2cbus_dev_action()
{
	i2c_busdev_path=$1
	i2c_busdev_action=$2

	# Check if we have devices list which should be connected to dynamic i2c buses.
	if [ ! -f $config_path/i2c_bus_connect_devs ];
	then
		return
	fi

	# Extract i2c bus index.
	i2cbus_regex="i2c-([0-9]+)$"
	[[ $i2c_busdev_path =~ $i2cbus_regex ]]
	if [[ -z "${BASH_REMATCH[1]}" ]]; then
		return
	else
		i2cbus="${BASH_REMATCH[1]}"
	fi

	# Load i2c devices list which should be connected on demand..
	declare -a asic_i2c_bus_connect_table="($(< $config_path/i2c_bus_connect_devs))"

	# Go over all devices and check if they should be connected to the current i2c bus.
	for ((i=0; i<${#asic_i2c_bus_connect_table[@]}; i+=4)); do
		if [ $i2cbus == "${asic_i2c_bus_connect_table[i+2]}" ];
		then
			if [ "$i2c_busdev_action" == "add" ]; then
				connect_device "${asic_i2c_bus_connect_table[i]}" "${asic_i2c_bus_connect_table[i+1]}" \
					"${asic_i2c_bus_connect_table[i+2]}"
			elif [ "$i2c_busdev_action" == "remove" ]; then
				diconnect_device "${asic_i2c_bus_connect_table[i]}" "${asic_i2c_bus_connect_table[i+1]}" \
					"${asic_i2c_bus_connect_table[i+2]}"
			fi
		fi
	done
}

# Get voltmon sensor name prefix, like voltmon{id}.
# For name voltmonX returning name based on $config_path/i2c_bus_connect_devs file.
# For other names - just return voltmon{id} string.
# $1 - voltmon name (voltmon1,voltmon2, voltmon10, voltmonX)
# $2 - path to sensor in sysfs
# return sensor index if match is found or 0 if match not found.
function get_i2c_voltmon_prefix()
{
	voltmon_name=$1
	path=$2

	# Check if we need to create voltmon name based on names in i2c_bus_connect_devs.
	if [ "$voltmon_name" != "voltmon_nameX" ];
	then
		echo "$voltmon_name"
		return
	fi

	# Check if we have devices list which can be connected to dynamic i2c buses.
	if [ ! -f $config_path/i2c_bus_connect_devs ];
	then
		log_info "Can't find" "$config_path"/i2c_bus_connect_devs " database required for name assign for sensor" "$path"
		echo "$voltmon_name"
		return
	fi

	# Load i2c devices list which should be connected on demand.
	declare -a asic_i2c_bus_connect_table="($(< $config_path/i2c_bus_connect_devs))"

	i2caddr_regex="i2c-[0-9]+/([0-9]+)-00([a-zA-Z0-9]+)/"
	[[ $i2c_busdev_path =~ $i2cbus_regex ]]
	if [ "${#BASH_REMATCH[1]}" == 3 ]; then
		echo "$voltmon_name"
		return
	else
		i2cbus="${BASH_REMATCH[1]}"
		i2caddr="${BASH_REMATCH[2]}"
	fi

	for ((i=0; i<${#asic_i2c_bus_connect_table[@]}; i+=4)); do
		if [ $i2cbus == "${asic_i2c_bus_connect_table[i+2]}" ] && [ $i2addr == "${asic_i2c_bus_connect_table[i+1]}" ] ;
		then
			voltmon_name="${asic_i2c_bus_connect_table[i+3]}"
			break
		fi
	done

	echo "$voltmon_name"
}

if [ "$1" == "add" ]; then
	# Don't process udev events until service is started and directories are created
	if [ ! -f ${udev_ready} ]; then
		exit 0
	fi
	if [ "$2" == "a2d" ]; then
		# Detect if it belongs to line card or to main board.
		iio_name=$5
		input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Line card event, replace output folder.
				find_linecard_num "$input_bus_num"
				environment_path="$hw_management_path"/lc"$linecard_num"/environment
				iio_name=$lc_iio_dev_name_def
			fi
		fi
		ln -sf "$3""$4"/in_voltage-voltage_scale $environment_path/"$2"_"$iio_name"_voltage_scale
		for i in {0..7}; do
			if [ -f "$3""$4"/in_voltage"$i"_raw ]; then
				ln -sf "$3""$4"/in_voltage"$i"_raw $environment_path/"$2"_"$iio_name"_raw_"$i"
			fi
		done
	fi
	if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ] ||
	   [ "$2" == "voltmon3" ] || [ "$2" == "voltmon4" ] ||
	   [ "$2" == "voltmon5" ] || [ "$2" == "voltmon6" ] ||
	   [ "$2" == "voltmon7" ] || [ "$2" == "voltmon12" ] ||
	   [ "$2" == "voltmon13" ] || [ "$2" == "voltmonX" ] || 
	   [ "$2" == "comex_voltmon1" ] || [ "$2" == "comex_voltmon2" ] ||
	   [ "$2" == "hotswap" ]; then
		if [ "$2" == "comex_voltmon1" ]; then
			find_i2c_bus
			i2c_comex_mon_bus_default=$(< $i2c_comex_mon_bus_default_file)
			comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
			busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
			busfolder=$(basename "$busdir")
			bus="${busfolder:0:${#busfolder}-5}"
			# Verify if this is not COMEX device
			if [ "$bus" != "$comex_bus" ]; then
				exit 0
			fi
		else
			# Detect if it belongs to line card or to main board.
			input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
			driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
			if [ -d "$driver_dir" ]; then
				driver_name=$(< "$driver_dir"/name)
				if [ "$driver_name" == "mlxreg-lc" ]; then
					# Linecard event, replace output folder.
					find_linecard_num "$input_bus_num"
					environment_path="$hw_management_path"/lc"$linecard_num"/environment
					alarm_path="$hw_management_path"/lc"$linecard_num"/alarm
				fi
			fi
		fi
		case $board_type in
		VMOD0014)
			# For SN2201 indexes are from 0 to 9.
			for i in {0..9}; do 
				check_n_link "$3""$4"/in"$i"_input $environment_path/"$2"_in"$i"_input

				check_n_link "$3""$4"/in"$i"_alarm $alarm_path/"$2"_in"$i"_alarm

				check_n_link "$3""$4"/curr"$i"_input $environment_path/"$2"_curr"$i"_input

				check_n_link "$3""$4"/power"$i"_input $environment_path/"$2"_power"$i"_input

				check_n_link "$3""$4"/curr"$i"_alarm $alarm_path/"$2"_curr"$i"_alarm

				check_n_link "$3""$4"/power"$i"_alarm $alarm_path/"$2"_power"$i"_alarm
			done
			;;
		*)
			# Get voltmon prefix. 
			# For voltmon[0..100] name will not change - just return it.
			# For voltmonX we will try to get name based on dev id/bus and system connect table.
			prefix=$(get_i2c_voltmon_prefix "$2" "$4")

			# TMP workaround until dictionary is implemented.
			dev_addr=$(echo "$4" | xargs dirname | xargs dirname | xargs basename )
			sku=$(< /sys/devices/virtual/dmi/id/product_sku)
			if [[ $sku == "HI132" && "$dev_addr" == "5-0027" ]]; then
				prefix="voltmon6"
			fi

			for i in {1..3}; do
				find_sensor_by_label "$3""$4" "in" "${VOLTMON_SENS_LABEL[$i]}"
				sensor_id=$?
				if [ ! $sensor_id -eq 0 ]; then
					if [ -f "$3""$4"/in"$sensor_id"_input ]; then
						ln -sf "$3""$4"/in"$sensor_id"_input $environment_path/"$prefix"_in"$i"_input
					fi
					if [ -f "$3""$4"/in"$sensor_id"_alarm ]; then
						ln -sf "$3""$4"/in"$sensor_id"_alarm $alarm_path/"$prefix"_in"$i"_alarm
					elif [ -f "$3""$4"/in"$sensor_id"_crit_alarm ]; then
						ln -sf "$3""$4"/in"$sensor_id"_crit_alarm $alarm_path/"$prefix"_in"$i"_alarm
					fi
				fi
				if [ -f "$3""$4"/curr"$i"_input ]; then
					ln -sf "$3""$4"/curr"$i"_input $environment_path/"$prefix"_curr"$i"_input
				fi
				if [ -f "$3""$4"/power"$i"_input ]; then
					ln -sf "$3""$4"/power"$i"_input $environment_path/"$prefix"_power"$i"_input
				fi
				if [ -f "$3""$4"/curr"$i"_alarm ]; then
					ln -sf "$3""$4"/curr"$i"_alarm $alarm_path/"$prefix"_curr"$i"_alarm
				fi
				if [ -f "$3""$4"/power"$i"_alarm ]; then
					ln -sf "$3""$4"/power"$i"_alarm $alarm_path/"$prefix"_power"$i"_alarm
				fi
			done
			;;
		esac
	fi
	if [ "$2" == "led" ]; then
		# Detect if it belongs to line card or to main board.
		# For main board dirname leds-mlxreg, for line card - leds-mlxreg.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		leds-mlxreg)
			# Default case, nothing to do.
			;;
		leds-mlxreg.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			led_path="$hw_management_path"/lc"$linecard_num"/led
			;;
		esac
		name=$(echo "$5" | cut -d':' -f2)
		color=$(echo "$5" | cut -d':' -f3)
		ln -sf "$3""$4"/brightness $led_path/led_"$name"_"$color"
		ln -sf "$3""$4"/trigger  $led_path/led_"$name"_"$color"_trigger
		ln -sf "$3""$4"/delay_on  $led_path/led_"$name"_"$color"_delay_on
		ln -sf "$3""$4"/delay_off $led_path/led_"$name"_"$color"_delay_off
		ln -sf $LED_STATE $led_path/led_"$name"_state
		lock_service_state_change
		if [ ! -f $led_path/led_"$name"_capability ]; then
			echo none "${color}" "${color}"_blink > $led_path/led_"$name"_capability
		else
			capability=$(< $led_path/led_"$name"_capability)
			capability="${capability} ${color} ${color}_blink"
			echo "$capability" > $led_path/led_"$name"_capability
		fi
		unlock_service_state_change
		$led_path/led_"$name"_state
	fi
	if [ "$2" == "regio" ]; then
		linecard=0
		# Detect if it belongs to line card or to main board.
		# For main board dirname mlxreg-io, for linecard - mlxreg-io.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		mlxreg-io)
			# Default case, nothing to do.
			;;
		mlxreg-io.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			system_path="$hw_management_path"/lc"$linecard_num"/system
			linecard="$linecard_num"
			;;
		esac
		# Allow to driver insertion off all the attributes.
		sleep 1
		if [ -d "$3""$4" ]; then
			for attrpath in "$3""$4"/*; do
				attrname=$(basename "${attrpath}")
				if [ ! -d "$attrpath" ] && [ ! -L "$attrpath" ] &&
				   [ "$attrname" != "uevent" ] &&
				   [ "$attrname" != "name" ]; then
					ln -sf "$3""$4"/"$attrname" $system_path/"$attrname"
				fi
			done
		fi
		for ((i=1; i<=$(<$config_path/max_tachos); i+=1)); do
			if [ -L $thermal_path/fan"$i"_status ]; then
				status=$(< $thermal_path/fan"$i"_status)
				if [ "$status" -eq 1 ]; then
					set_fan_direction fan"${i}" 1
				fi
			fi
		done

		# Handle linecard.
		if [ "$linecard" -ne 0 ]; then
			lc_path="$hw_management_path"/lc"$linecard"

			if [ ! -d "$lc_path"/config ]; then
				mkdir "$lc_path"/config
			fi
			config=$(< "$lc_path"/system/config)
			case "$config" in
			0)
				echo 16 > "$lc_path"/config/port_num
				echo 1 > "$lc_path"/config/cpld_num
				echo 1 > "$lc_path"/config/fpga_num
				echo 4 > "$lc_path"/config/gearbox_num
				echo 1 > "$lc_path"/config/gearbox_mgr_num
				;;
			1)
				echo 8 > "$lc_path"/config/port_num
				echo 1 > "$lc_path"/config/cpld_num
				echo 1 > "$lc_path"/config/fpga_num
				;;
			*)
				;;
			esac

			# Set linecard CPLD combined version.
			if [ -L "$lc_path"/system/cpld1_pn ]; then
				cpld_pn=$(cat "$lc_path"/system/cpld1_pn)
			fi
			if [ -L "$lc_path"/system/cpld1_version ]; then
				cpld_ver=$(cat "$lc_path"/system/cpld1_version)
			fi
			if [ -L "$lc_path"/system/cpld1_version_min ]; then
				cpld_ver_min=$(cat "$lc_path"/system/cpld1_version_min)
			fi
			str=$(printf "CPLD%06d_REV%02d%02d" "$cpld_pn" "$cpld_ver" "$cpld_ver_min")
			echo "$str" > "$lc_path"/system/cpld

			# Set linecard FPGA combined version.
			set_lc_fpga_combined_version "$lc_path"
		fi
	fi
	if [ "$2" == "eeprom" ]; then
		busdir="$3""$4"
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		find_i2c_bus
		bus=$((bus-i2c_bus_offset))
		addr="0x${busfolder: -2}"
		# Get parent bus for line card EEPROM - skip two folders.
		parentdir=$(dirname "$busdir")
		parentbus=$(basename "$parentdir")
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		find_eeprom_name "$bus" "$addr" "$parentbus" "$input_bus_num"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Linecard event, replace output folder.
				find_linecard_num "$input_bus_num"
				eeprom_path="$hw_management_path"/lc"$linecard_num"/eeprom
				# Parse VPD.
				if [ "$eeprom_name" == "fru" ]; then
					hw-management-lc-fru-parser.py -i "$3""$4"/eeprom -o "$eeprom_path"/vpd_parsed
					if [ $? -ne 0 ]; then
						echo "Failed to parse linecard VPD" > "$eeprom_path"/vpd_parsed
					fi
				fi
				if [ "$eeprom_name" == "ini" ]; then
					hw-management-parse-eeprom.sh --layout 3 --conv --eeprom_path "$3""$4"/eeprom > "$eeprom_path"/ini_parsed
					if [ $? -ne 0 ]; then
						echo "Failed to parse linecard INI" > "$eeprom_path"/ini_parsed
					fi
				fi
			fi
		fi
		drv_name=$(< "$busdir"/name)
		if [[ $drv_name == *"24c"* ]]; then
			ln -sf "$3""$4"/eeprom $eeprom_path/$eeprom_name 2>/dev/null
			chmod 400 $eeprom_path/$eeprom_name 2>/dev/null
		fi
		case $eeprom_name in
		fan*_info)
			sku=$(< /sys/devices/virtual/dmi/id/product_sku)
			if [[ $sku == "HI138" ]] || [[ $sku == "HI139" ]]; then
				exit 0
			fi
			fan_direction=$(xxd -u -p -l 1 -s $fan_dir_offset_in_vpd_eeprom_pn $eeprom_path/$eeprom_name)
			fan_prefix=$(echo $eeprom_name | cut -d_ -f1)
			case $fan_direction in
			$fan_direction_exhaust)
				echo 1 > $thermal_path/"${fan_prefix}"_dir
				;;
			$fan_direction_intake)
				echo 0 > $thermal_path/"${fan_prefix}"_dir
				;;
			*)
				;;
			esac
			;;
		*)
			;;
		esac
	fi
	if [ "$2" == "cpld" ]; then
		asic_cpld_add_handler "${3}${4}"
	fi
	if [ "$2" == "watchdog" ]; then
		wd_type=$(< "$3""$4"/identity)
		case $wd_type in
			mlx-wdt-*)
				wd_sub="$(echo "$wd_type" | cut -c 9-)"
				if [ ! -d ${watchdog_path}/"${wd_sub}" ]; then
					mkdir ${watchdog_path}/"${wd_sub}"
				fi
				ln -sf "$3""$4"/bootstatus ${watchdog_path}/"${wd_sub}"/bootstatus
				ln -sf "$3""$4"/nowayout ${watchdog_path}/"${wd_sub}"/nowayout
				ln -sf "$3""$4"/status ${watchdog_path}/"${wd_sub}"/status
				ln -sf "$3""$4"/timeout ${watchdog_path}/"${wd_sub}"/timeout
				ln -sf "$3""$4"/identity ${watchdog_path}/"${wd_sub}"/identity
				ln -sf "$3""$4"/state ${watchdog_path}/"${wd_sub}"/state
				if [ -f "$3""$4"/timeleft ]; then
					ln -sf "$3""$4"/timeleft ${watchdog_path}/"${wd_sub}"/timeleft
				fi
				;;
			*)
				;;
		esac
	fi
	# Creating lc folders hierarchy upon line card udev add event.
	if [ "$2" == "linecard" ]; then
		input_bus_num=$(echo "$3""$4" | xargs basename | cut -d"-" -f1)
		find_linecard_num "$input_bus_num"
		if [ ! -d "$hw_management_path"/lc"$linecard_num" ]; then
			mkdir "$hw_management_path"/lc"$linecard_num"
		fi
		for i in "${!linecard_folders[@]}"
		do
			if [ ! -d "$hw_management_path"/lc"$linecard_num"/"${linecard_folders[$i]}" ]; then
				mkdir "$hw_management_path"/lc"$linecard_num"/"${linecard_folders[$i]}"
			fi 
		done
	fi
	# Create line card i2c mux symbolic link infrastructure
	if [ "$2" == "lc_topo" ]; then
		log_info "I2C infrastucture for line card $3 is created."
	fi

	# Create i2c bus.
	if [ "$2" == "i2c_bus" ]; then
		log_info "I2C bus $4 connected."
		handle_i2cbus_dev_action $4 "add"
	fi
elif [ "$1" == "mv" ]; then
	if [ "$2" == "sfp" ]; then
		lock_service_state_change
		change_file_counter $config_path/sfp_counter 1
		unlock_service_state_change
		create_sfp_symbolic_links "${3}${4}"
	fi
elif [ "$1" == "hotplug-event" ]; then
	# Don't process udev events until service is started and directories are created
	if [ ! -f ${udev_ready} ]; then
		exit 0
	fi
	handle_hotplug_event "${2}" "${3}"
else
	if [ "$2" == "a2d" ]; then
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Line card event, replace output folder.
				find_linecard_num "$input_bus_num"
				environment_path="$hw_management_path"/lc"$linecard_num"/environment
			fi
		fi
		unlink $environment_path/"$2"_"$5"_voltage_scale
		for i in {0..7}; do
			if [ -L $environment_path/"$2"_"$5"_raw_"$i" ]; then
				unlink $environment_path/"$2"_"$5"_raw_"$i"
			fi
		done
	fi
	if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ] ||
	   [ "$2" == "voltmon3" ] || [ "$2" == "voltmon4" ] ||
	   [ "$2" == "voltmon5" ] || [ "$2" == "voltmon6" ] ||
	   [ "$2" == "voltmon7" ] || [ "$2" == "voltmon12" ] ||
	   [ "$2" == "voltmon13" ] ||
	   [ "$2" == "comex_voltmon1" ] || [ "$2" == "comex_voltmon2" ] ||
	   [ "$2" == "hotswap" ]; then
		if [ "$2" == "comex_voltmon1" ]; then
			find_i2c_bus
			i2c_comex_mon_bus_default=$(< $i2c_comex_mon_bus_default_file)
			comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
			busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
			busfolder=$(basename "$busdir")
			bus="${busfolder:0:${#busfolder}-5}"
			# Verify if this is not COMEX device
			if [ "$bus" != "$comex_bus" ]; then
				exit 0
			fi
		else
			# Detect if it belongs to line card or to main board.
			input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
			driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
			if [ -d "$driver_dir" ]; then
				driver_name=$(< "$driver_dir"/name)
				if [ "$driver_name" == "mlxreg-lc" ]; then
					# Linecard event, replace output folder.
					find_linecard_num "$input_bus_num"
					environment_path="$hw_management_path"/lc"$linecard_num"/environment
					alarm_path="$hw_management_path"/lc"$linecard_num"/alarm
				fi
			fi
		fi
		# For SN2201 indexes are from 0 to 9.
		for i in {0..9}; do
			if [ -L $environment_path/"$2"_in"$i"_input ]; then
				unlink $environment_path/"$2"_in"$i"_input
			fi
			if [ -L $environment_path/"$2"_curr"$i"_input ]; then
				unlink $environment_path/"$2"_curr"$i"_input
			fi
			if [ -L $environment_path/"$2"_power"$i"_input ]; then
				unlink $environment_path/"$2"_power"$i"_input
			fi
			if [ -L $alarm_path/"$2"_in"$i"_alarm ]; then
				unlink $alarm_path/"$2"_in"$i"_alarm
			fi
			if [ -L $alarm_path/"$2"_curr"$i"_alarm ]; then
				unlink $alarm_path/"$2"_curr"$i"_alarm
			fi
			if [ -L $alarm_path/"$2"_power"$i"_alarm ]; then
				unlink $alarm_path/"$2"_power"$i"_alarm
			fi
		done
	fi
	if [ "$2" == "led" ]; then
		# Detect if it belongs to line card or to main board.
		# For main board dirname leds-mlxreg, for line card - leds-mlxreg.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		leds-mlxreg)
			# Default case, nothing to do.
			;;
		leds-mlxreg.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			led_path="$hw_management_path"/lc"$linecard_num"/led
			;;
		esac
		name=$(echo "$5" | cut -d':' -f2)
		color=$(echo "$5" | cut -d':' -f3)
		unlink $led_path/led_"$name"_"$color"
		unlink $led_path/led_"$name"_"$color"_delay_on
		unlink $led_path/led_"$name"_"$color"_delay_off
		unlink $led_path/led_"$name"_state
	fi
	if [ -f $led_path/led_"$name" ]; then
		rm -f $led_path/led_"$name"
	fi
	if [ -f $led_path/led_"$name"_capability ]; then
		rm -f $led_path/led_"$name"_capability
	fi
	if [ "$2" == "regio" ]; then
		# Detect if it belongs to line card or to main board.
		# For main board dirname mlxreg-io, for line card - mlxreg-io.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		mlxreg-io)
			# Default case, nothing to do.
			;;
		mlxreg-io.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			system_path="$hw_management_path"/lc"$linecard_num"/system
			;;
		esac
		if [ -d $system_path ]; then
			for attrname in $system_path/*; do
				attrname=$(basename "${attrname}")
				if [ -L $system_path/"$attrname" ]; then
					unlink $system_path/"$attrname"
				fi
			done
		fi
	fi
	if [ "$2" == "eeprom" ]; then
		busdir="$3""$4"
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$busdir" | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$busdir" | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Linecard event, replace output folder.
				find_linecard_num "$input_bus_num"
				eeprom_path="$hw_management_path"/lc"$linecard_num"/eeprom
				if [ -d "$eeprom_path" ]; then
					rm -rf "$eeprom_path"
					return
				fi
			fi
		fi
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		find_i2c_bus
		bus=$((bus-i2c_bus_offset))
		addr="0x${busfolder: -2}"
		find_eeprom_name_on_remove "$bus" "$addr"
		drv_name=$(< "$busdir"/name)
		if [[ $drv_name != *"24c"* ]]; then
			unlink $eeprom_path/$eeprom_name
		fi
		case "$eeprom_name" in
			fan*)
				fan_prefix=$(echo $eeprom_name | cut -d_ -f1)
				rm -f $thermal_path/"${fan_prefix}"_dir
				;;
			vpd*)
				rm -f $eeprom_path/vpd_parsed
				;;
			*)
				;;
		esac
	fi
	if [ "$2" == "cpld" ]; then
		asic_cpld_remove_handler
	fi
	if [ "$2" == "watchdog" ]; then
	wd_type=$(< "$3""$4"/identity)
		case $wd_type in
			mlx-wdt-*)
				find $watchdog_path/ -name "$wd_type""*" -type l -exec unlink {} \;
				;;
			*)
				;;
		esac
	fi
	if [ "$2" == "sfp" ]; then
		lock_service_state_change
		change_file_counter $config_path/sfp_counter -1
		unlock_service_state_change
		rm -rf ${sfp_path}/*_status
	fi
	# Clear lc folders upon line card udev rm event.
	if [ "$2" == "linecard" ]; then
		input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
		find_linecard_num "$input_bus_num"
		# Clean line card folders.
		if [ -d "$hw_management_path"/lc"$linecard_num" ]; then
			find "$hw_management_path"/lc"$linecard_num" -type l -exec unlink {} \;
			rm -rf "$hw_management_path"/lc"$linecard_num"
		fi
	fi
	# Destroy line card i2c mux symbolic link infrastructure
	if [ "$2" == "lc_topo" ]; then
		destroy_linecard_i2c_links "$3"
	fi

	# Removed i2c bus.
	if [ "$2" == "i2c_bus" ]; then
		log_info "I2C bus $4 connected."
		handle_i2cbus_dev_action $4 "remove"
	fi
fi
