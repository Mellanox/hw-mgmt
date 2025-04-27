#!/bin/bash

# Copyright (c) 2018 - 2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
sku=$(< $sku_file)
cpu_type=$(<"$config_path"/cpu_type)

LED_STATE=/usr/bin/hw-management-led-state-conversion.sh
i2c_bus_def_off_eeprom_cartridge=7
i2c_bus_def_off_eeprom_cartridge1=3
i2c_bus_def_off_eeprom_cartridge2=11
i2c_bus_def_off_eeprom_vpd=8
i2c_bus_def_off_eeprom_psu=4
i2c_bus_alt_off_eeprom_psu=10
i2c_bus_def_off_eeprom_fan1=11
i2c_bus_def_off_eeprom_fan2=12
i2c_bus_def_off_eeprom_fan3=13
i2c_bus_def_off_eeprom_fan4=14
i2c_bus_def_off_eeprom_mgmt=45
vpd_i2c_addr=0x51
psu1_i2c_addr=0x51
psu2_i2c_addr=0x50
psu3_i2c_addr=0x53
psu4_i2c_addr=0x52
psu5_i2c_addr=0x55
psu6_i2c_addr=0x54
psu7_i2c_addr=0x56
psu8_i2c_addr=0x57
line_card_bus_off=33
lc_iio_dev_name_def="iio:device0"
eeprom_name=''
fan_dir_offset_in_vpd_eeprom_pn=0x48
# 46 - F, 52 - R
fan_direction_exhaust=46
fan_direction_intake=52
linecard_folders=("alarm" "config" "eeprom" "environment" "led" "system" "thermal")
mlxreg_lc_addr=32
lc_max_num=8
dpu_folders=("alarm" "config" "environment" "events" "system" "thermal")
fan_debounce_timeout_ms=2000
cfl_comex_vcore_out_idx=2

case "$board_type" in
VMOD0014)
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
	;;
VMOD0013)
	psu2_i2c_addr=0x5a
	;;
VMOD0021)
	i2c_bus_def_off_eeprom_vpd=2
	;;
default)
	;;
esac

# Voltmon sensors by label mapping:
#                   dummy   sensor1       sensor2        sensor3
VOLTMON_SENS_LABEL=("none" "vin\$|vin1"   "vout\$|vout1" "vout2")
CURR_SENS_LABEL=(   "none" "iin\$|iin1"   "iout\$|iout1\$" "iout2\$")
POWER_SENS_LABEL=(  "none" "pin\$|pin1"   "pout\$|pout1\$" "pout2\$")


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
	FILES=$(find "$path"/"$sens_type"*label)
	sensor_id_regex="$path"/"$sens_type""([0-9]+)_label"
	for label_file in $FILES
	do
		curr_label=$(< "$label_file")
		if [[ $curr_label =~ $label_mask ]]; then
			# Extracting sensor number from label name like "curr7_label"
			[[ $label_file =~ $sensor_id_regex ]]
			if [ "${#BASH_REMATCH[@]}" != 2 ]; then
			    # not matched
			    return 0
			else
			    return "${BASH_REMATCH[1]}"
			fi
		fi
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

create_main_i2c_links()
{
	local i2c_busdev_path="$1"

	if [ ! -f $config_path/named_busses ]; then
		return
	fi

	i2cbus_regex="i2c-([0-9]+)$"
	[[ $i2c_busdev_path =~ $i2cbus_regex ]]
	if [[ "${#BASH_REMATCH[@]}" != 2 ]]; then
		return
	else
		i2cbus="${BASH_REMATCH[1]}"
	fi

	if [ ! -d /dev/main ]; then
		mkdir /dev/main
	fi

	declare -a named_busses="($(< $config_path/named_busses))"
	for ((i=0; i<${#named_busses[@]}; i+=2)); do
		if [ "$i2cbus" == "${named_busses[i+1]}" ]; then
			sym_name=${named_busses[i]}
			if [ ! -L /dev/main/"$sym_name" ]; then
				ln -s /dev/i2c-"$i2cbus" /dev/main/"$sym_name"
			fi
		fi
	done
}

destroy_main_i2c_links()
{
	if [ -d /dev/main ]; then
		rm -rf /dev/main
	fi
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

	exit 0
}

find_eeprom_name()
{
	bus=$1
	addr=$2
	bus_abs=$((bus+i2c_bus_offset))
	i2c_dev_path="i2c-$bus_abs/$bus_abs-00${busfolder: -2}/" 
	eeprom_name=$(get_i2c_busdev_name "undefined" "$i2c_dev_path")
	if [[ $eeprom_name != "undefined" ]];
	then
		echo $eeprom_name
		return
	fi
	i2c_bus_def_off_eeprom_cpu=$(< $i2c_bus_def_off_eeprom_cpu_file)
	if [ "$bus" -eq "$i2c_bus_def_off_eeprom_vpd" ]; then
		if [ "$board_type" == "VMOD0017" ] && [ "$addr" != "$vpd_i2c_addr" ]; then
			eeprom_name=ipmi_info
		else
			eeprom_name=vpd_info
		fi
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
		VMOD0017)
			eeprom_name=pdb_eeprom
			;;
		*)
			if [ "$addr" = "$psu1_i2c_addr" ]; then
				eeprom_name=psu1_info
			elif [ "$addr" = "$psu2_i2c_addr" ]; then
				eeprom_name=psu2_info
			elif [ "$addr" = "$psu3_i2c_addr" ]; then
				eeprom_name=psu3_info
			elif [ "$addr" = "$psu4_i2c_addr" ]; then
				if [[ $sku == "HI144"  ||  $sku == "HI147" ]]; then
					eeprom_name=psu2_info
				else
					eeprom_name=psu4_info
				fi
			elif [ "$addr" = "$psu5_i2c_addr" ]; then
				eeprom_name=psu5_info
			elif [ "$addr" = "$psu6_i2c_addr" ]; then
				eeprom_name=psu6_info
			elif [ "$addr" = "$psu7_i2c_addr" ]; then
				eeprom_name=psu7_info
			elif [ "$addr" = "$psu8_i2c_addr" ]; then
				eeprom_name=psu8_info
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
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_cartridge" ]; then
		eeprom_name=cable_cartridge_eeprom
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_cartridge1" ]; then
		eeprom_name=cable_cartridge_eeprom
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_cartridge2" ]; then
		eeprom_name=cable_cartridge_eeprom2
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
	echo $eeprom_name
}

find_eeprom_name_on_remove()
{
	bus=$1
	addr=$2
	bus_abs=$((bus+i2c_bus_offset))
	i2c_dev_path="2c-$bus_abs/$bus_abs-00${busfolder: -2}/"
	eeprom_name=$(get_i2c_busdev_name "undefined" "$i2c_dev_path")
	if [[ $eeprom_name != "undefined" ]];
	then
		echo $eeprom_name
		return
	fi
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
				if [[ $sku == "HI144" || $sku == "HI147" ]]; then
					eeprom_name=psu2_info
				else
					eeprom_name=psu4_info
				fi
			elif [ "$addr" = "$psu5_i2c_addr" ]; then
				eeprom_name=psu5_info
			elif [ "$addr" = "$psu6_i2c_addr" ]; then
				eeprom_name=psu6_info
			elif [ "$addr" = "$psu7_i2c_addr" ]; then
				eeprom_name=psu7_info
			elif [ "$addr" = "$psu8_i2c_addr" ]; then
				eeprom_name=psu8_info
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
	echo $eeprom_name
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

function set_fan_direction()
{
	attribute=$1
	event=$2
	case $attribute in
	fan*)
		if [ -f $config_path/fan_dir_eeprom ]; then
			return
		fi
		# Check if CPLD fan direction is exists
		if [ ! -f $system_path/fan_dir ]; then
			return
		fi
		if [[ "$sku" == "HI117" ]]; then
			return
		fi
		fan_debounce_counter=0
		fan_debounce_timer=$fan_debounce_timeout_ms
		# debounce timeout for FAN dir. 2 times in a row read same value or delay > fan_debounce_timer.
		while (("$fan_debounce_timer" > 0)) && (("$fan_debounce_counter" < 2))
		do
			fan_dir=$(< $system_path/fan_dir)
			if [ $fan_dir -eq $fan_dir_old ];
			then
				fan_debounce_counter=$((fan_debounce_counter + 1))
			else
				fan_dir_old=$fan_dir
				fan_debounce_counter=0
			fi
			fan_debounce_timer=$((fan_debounce_timer - 200))
			sleep 0.2
		done
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


# Get FAN direction based on VPD PN field
#
# Input parameters:
# 1 - "$vpd_file"
# Return FAN direction
# 0 - Reverse (C2P)
# 1 - Forward(P2C)
# 2 - unknown (read error or field missing)
get_fan_direction_by_vpd()
{
	vpd_file=$1
	# Default dir "unknown" till it will not be detected later
	dir=2
	pn=$(grep PN: $vpd_file | grep -oE "[^ ]+$")
	if [ -z $pn ]; then
		if [ -f $config_path/fixed_fans_dir ]; then
			dir=$(< $config_path/fixed_fans_dir) 
		fi
	else 
		dir_char=""
		if [ ! ${sys_fandir_vs_pn[$pn]}_ = _ ]; then
			dir_char=${sys_fandir_vs_pn[$pn]}
		else
			PN_REGEXP="MTEF-FAN([R,F])"
		    
		    [[ $pn =~ $PN_REGEXP ]]
		    if [[ ! -z "${BASH_REMATCH[1]}" ]]; then
		        dir_char="${BASH_REMATCH[1]}"
		    fi
		fi
		if [ $dir_char == "R" ]; then
			dir=0
		elif [ $dir_char == "F" ]; then
			dir=1
		fi
	fi
	return $dir
}

function set_fpga_combined_version()
{
	path="$1"
	# Set linecard FPGA combined version.
	if [ -L "$path"/system/fpga1_pn ]; then
		fpga_pn=$(cat "$path"/system/fpga1_pn)
	fi
	if [ -L "$path"/system/fpga1_version ]; then
		fpga_ver=$(cat "$path"/system/fpga1_version)
	fi
	if [ -L "$path"/system/fpga1_version_min ]; then
		fpga_ver_min=$(cat "$path"/system/fpga1_version_min)
	fi
	str=$(printf "FPGA%06d_REV%02d%02d" "$fpga_pn" "$fpga_ver" "$fpga_ver_min")
	echo "$str" > "$path"/system/fpga
}

function handle_hotplug_fan_event()
{
	local attribute=$1
	local event=$2
	local bus=
	local addr=

	case "$board_type" in
	VMOD0014)
		case $attribute in
		fan1)
			bus=$i2c_bus_def_off_eeprom_fan1
			addr=0x50
			;;
		fan2)
			bus=$i2c_bus_def_off_eeprom_fan2
			addr=0x51
			;;
		fan3)
			bus=$i2c_bus_def_off_eeprom_fan3
			addr=0x52
			;;
		fan4)
			bus=$i2c_bus_def_off_eeprom_fan4
			addr=0x53
			;;
		*)
			;;
		esac
		eeprom_type=24c02
		if [ "$event" -eq 1 ]; then
			connect_device "$eeprom_type" "$addr" "$bus"
		else
			disconnect_device "$addr" "$bus"
		fi
		;;
	*)
		;;
	esac

	if [ "$event" -eq 1 ]; then
		set_fan_direction "$attribute" "$event"
	fi
}

function handle_hotplug_dpu_event()
{
    local dpu_i2c_path
    local slot_num
    local event
    local attribute
    local dpu_event_path

    attribute=$(echo "$1" | awk '{print tolower($0)}')
    event=$2
    dpu_i2c_path=$(echo "$3""$4" | rev | cut -d'/' -f4- | rev)
    slot_num=$(find_dpu_slot "$dpu_i2c_path")
    dpu_event_path="$hw_management_path"/dpu"$slot_num"/events/"$attribute"

    if [ -f "${dpu_event_path}" ]; then
        echo "$event" > "${dpu_event_path}"
        log_info "Event ${event} is received for DPU: ${slot_num} attribute ${attribute}"
    fi
}

function handle_hotplug_psu_event()
{
	local psu_name=$1
	local event=$2
	local psu_num
	local psu_i2c_bus
	local psu_i2c_addr
	local psu_is_dummy
	local dummy_psus_supported=$(< ${config_path}/dummy_psus_supported)

	if [ ${dummy_psus_supported} -eq 1 ]; then
		case ${sku} in
		HI157)
			psu_i2c_bus=(4 4 4 4)
			psu_i2c_addr=(59 58 5b 5a)
			;;
		HI158)
			psu_i2c_bus=(4 4 3 3 3 3 4 4)
			psu_i2c_addr=(59 58 5b 5a 5d 5c 5e 5f)
			;;
		*)
			;;
		esac

		psu_name=$(echo ${psu_name} | awk '{print tolower($0)}')
		psu_num=${psu_name#psu}

		if [ $event -eq 1 ]; then
			psu_bus=${psu_i2c_bus[$((psu_num-1))]}
			psu_addr=${psu_i2c_addr[$((psu_num-1))]}
			psu_is_dummy=1
			for ((i=0; i<5; i++)); do
				if [ -d "/sys/bus/i2c/devices/${psu_bus}-00${psu_addr}" ]; then
					psu_is_dummy=0
					break
				fi
				sleep 1
			done
			if [ ${psu_is_dummy} -eq 1 ]; then
				touch ${config_path}/${psu_name}_is_dummy
			fi
		else
			rm -f ${config_path}/${psu_name}_is_dummy
		fi
	fi
}

function handle_hotplug_event()
{
	local attribute
	local event
	local lc_path
	local board_num
	local board_name_str
	local board_type=dynamic
	attribute=$(echo "$1" | awk '{print tolower($0)}')
	event=$2

	if [ -f "$events_path"/"$attribute" ]; then
		echo "$event" > "$events_path"/"$attribute"
		log_info "Event ${event} is received for attribute ${attribute}"
	fi

	case "$attribute" in
	lc*_active)
		linecard=$(echo ${attribute:0:3})
		lc_path="$hw_management_path"/"$linecard"
		set_fpga_combined_version "$lc_path"
		;;
	fan*)
		handle_hotplug_fan_event "$attribute" "$event"
		;;
	dpu[1-8]_ready)
		if [ "$event" -eq 1 ]; then
			# Connect dynamic devices.
			if [ -e "$devtree_file" ]; then
				if [ -e "$config_path"/dpu_board_type ]; then
					board_type=$(< $config_path/dpu_board_type)
				fi
				if [ "$board_type" == "dynamic" ]; then
					board_num=$(echo "$attribute" | grep -o -E '[0-9]+')
					board_name_str=dpu_board${board_num}
					connect_dynamic_board_devices "$board_name_str"
				fi
			else
				bus=$(echo $attribute | cut  -d"_" -f1 | cut -c 4-)
				bus_offset=$(< $config_path/dpu_bus_off)
				bus=$((bus+bus_offset-1))
				connect_underlying_devices "$bus"
			fi
		fi
		;;
	dpu[1-8]_shtdn_ready)
		if [ "$event" -eq 1 ]; then
			# Disconnect dynamic devices.
			if [ -e "$devtree_file" ]; then
				if [ -e "$config_path"/dpu_board_type ]; then
					board_type=$(< $config_path/dpu_board_type)
				fi
				if [ "$board_type" == "dynamic" ]; then
					board_num=$(echo "$attribute" | grep -o -E '[0-9]+')
					board_name_str=dpu_board${board_num}
					disconnect_dynamic_board_devices "$board_name_str"
				fi
			else
				bus=$(echo $attribute | cut  -d"_" -f1 | cut -c 4-)
				bus_offset=$(< $config_path/dpu_bus_off)
				bus=$((bus+bus_offset-1))
				disconnect_underlying_devices "$bus"
			fi
		fi
		;;
	psu*)
		handle_hotplug_psu_event "$attribute" "$event"
		;;
	*)
		;;
	esac
}

function handle_fantray_led_event()
{
	local fan_idx
	local color
	local event
	local gpio_path
	local gpio_pin_green
	local gpio_pin_orange
	fan_idx=$(echo "$1" | cut -d':' -f2 | cut -d'n' -f2)
	color=$(echo "$1" | cut -d':' -f3)
	event=$2
	gpio_path=/sys/class/gpio

	if [ -e "$config_path"/i2c_gpiobase ]; then
		gpiobase=$(<"$config_path"/i2c_gpiobase)
	else
		return
	fi
	gpio_pin_green=$((gpiobase + 8 + 2*(fan_idx - 1)))
	gpio_pin_orange=$((gpiobase + 9 + 2*(fan_idx - 1)))
	case "$color" in
	green)
		if [ "$event" -eq "0" ]; then
			echo 0 > $gpio_path/gpio"$gpio_pin_orange"/value
			echo 0 > $gpio_path/gpio"$gpio_pin_green"/value
		else
			echo 0 > $gpio_path/gpio"$gpio_pin_orange"/value
			echo 1 > $gpio_path/gpio"$gpio_pin_green"/value
		fi
		;;
	orange)
		if [ "$event" -eq "0" ]; then
			echo 0 > $gpio_path/gpio"$gpio_pin_green"/value
			echo 0 > $gpio_path/gpio"$gpio_pin_orange"/value
		else
			echo 0 > $gpio_path/gpio"$gpio_pin_green"/value
			echo 1 > $gpio_path/gpio"$gpio_pin_orange"/value
		fi
		;;
	*)
		;;
	esac
}

function check_cpld_attrs_num()
{
   board=$(cat /sys/devices/virtual/dmi/id/board_name)
   cpld_num=$(cat $config_path/cpld_num)
   case "$board" in
   VMOD0001|VMOD0003)
       cpld_num=$((cpld_num-1))
       ;;
   *)
       ;;
   esac

   return $cpld_num
}

function check_cpld_attrs()
{
    attrname="$1"
    cpld_num="$2"
    take=1

    # Extracting the cpld number if the attribute starts with cpld<num>
    num=`echo $attrname | grep -Po '^(cpld)\K\d+'`
    # Seeing if the cpld index is valid for the platform
    [[ ! -z "$num" ]] && [ $num -gt $cpld_num ] && take=0

    return $take
}

handle_cpld_versions()
{
	CPLD3_VER_DEF="0"
	cpld_num_loc="${1}"

	for ((i=1; i<=cpld_num_loc; i+=1)); do
		if [ -f $system_path/cpld"$i"_pn ]; then
			cpld_pn=$(cat $system_path/cpld"$i"_pn)
		fi
		if [ -f $system_path/cpld"$i"_version ]; then
			cpld_ver=$(cat $system_path/cpld"$i"_version)
		fi
		if [ -f $system_path/cpld"$i"_version_min ]; then
			cpld_ver_min=$(cat $system_path/cpld"$i"_version_min)
		fi
		if [ -z "$str" ]; then
			str=$(printf "CPLD%06d_REV%02d%02d" "$cpld_pn" "$cpld_ver" "$cpld_ver_min")
		else
			str=$str$(printf "_CPLD%06d_REV%02d%02d" "$cpld_pn" "$cpld_ver" "$cpld_ver_min")
		fi
	done
	echo "$str" > $system_path/cpld_base
	echo "$str" > $system_path/cpld
}

check_reset_attrs()
{
	attrname="$1"
	if [[ "$attrname" == "reset_"* ]]; then
		reset_attr_count=$((reset_attr_count+1))
		if [ $reset_attr_count -eq $reset_attr_num ]; then
			check_n_init $config_path/reset_attr_ready 1
		fi
	fi
}

# Don't process udev events until service is started and directories are created
if [ ! -f ${udev_ready} ]; then
	exit 0
fi

trace_udev_events "$0: ACTION=$1 $2 $3 $4 $5"

if [ "$1" == "add" ]; then
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
		# ADS1015 used on SN2201 has scale for every input
		if [ "$board_type" == "VMOD0014" ]; then
			for i in {0..7}; do
				if [ -f "$3""$4"/in_voltage"$i"_scale ]; then
					check_n_link "$3""$4"/in_voltage"$i"_scale $environment_path/"$2"_"$iio_name"_voltage_scale_"$i"
				fi
			done
		else
			check_n_link "$3""$4"/in_voltage-voltage_scale $environment_path/"$2"_"$iio_name"_voltage_scale
		fi
		for i in {0..7}; do
			if [ -f "$3""$4"/in_voltage"$i"_raw ]; then
				check_n_link "$3""$4"/in_voltage"$i"_raw $environment_path/"$2"_"$iio_name"_raw_"$i"
			fi
		done
	fi
	if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ] ||
	   [ "$2" == "voltmon3" ] || [ "$2" == "voltmon4" ] ||
	   [ "$2" == "voltmon5" ] || [ "$2" == "voltmon6" ] ||
	   [ "$2" == "voltmon7" ] || [ "$2" == "voltmon12" ] ||
	   [ "$2" == "voltmon13" ] || [ "$2" == "voltmonX" ] ||
	   [ "$2" == "comex_voltmon1" ] || [ "$2" == "comex_voltmon2" ] ||
	   [ "$2" == "hotswap" ] || [ "$2" == "pmbus" ]; then
		# Get i2c voltmon prefix.
		prefix=$(get_i2c_busdev_name "$2" "$4")
		if [[ $prefix == "undefined" ]] && [[ $5 != "dpu" ]];
		then
			exit
		fi
		# Voltmon MUST have at least one input.
		# Filtering device that doesn't have it.
		if [ ! -f "$3""$4"/in1_input ]; 
		then
			exit
		fi

		if [ "$prefix" == "comex_voltmon1" ] || [ "$prefix" == "comex_voltmon2" ] ; then
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
			# Detect if it belongs to line card or to main board or to dpu.
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
			else
				sku=$(< /sys/devices/virtual/dmi/id/product_sku)
				case $sku in
				HI160)
					# DPU event, replace output folder.
					input_bus_num=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f1)
					slot_num=$(find_dpu_slot_from_i2c_bus $input_bus_num)
					if [ "$prefix" == "voltmon1" ] || [ "$prefix" == "voltmon2" ]; then
                        			if [ ! -z "$slot_num" ]; then
						    environment_path="$hw_management_path"/dpu"$slot_num"/environment
						    alarm_path="$hw_management_path"/dpu"$slot_num"/alarm
						    thermal_path="$hw_management_path"/dpu"$slot_num"/thermal
                        			fi
					fi
					;;
				*)
					;;
				esac
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
				check_n_link "$3""$4"/temp1_input $thermal_path/"$prefix"_temp1_input
				check_n_link "$3""$4"/temp1_max $thermal_path/"$prefix"_temp1_max
				check_n_link "$3""$4"/temp1_crit $thermal_path/"$prefix"_temp1_crit
				check_n_link "$3""$4"/temp1_lcrit $thermal_path/"$prefix"_temp1_lcrit
				check_n_link "$3""$4"/temp1_max_alarm $alarm_path/"$prefix"_temp1_max_alarm
				check_n_link "$3""$4"/temp1_crit_alarm $alarm_path/"$prefix"_temp1_crit_alarm
			done
			;;
		*)
			# TMP workaround until dictionary is implemented.
			dev_addr=$(echo "$4" | xargs dirname | xargs dirname | xargs basename )
			sku=$(< /sys/devices/virtual/dmi/id/product_sku)
			if [[ $sku == "HI132" && "$dev_addr" == "5-0027" ]]; then
				prefix="voltmon6"
			fi

			# Creating links for only temp1 attribute. Skipping temp2 and others
			check_n_link "$3""$4"/temp1_input $thermal_path/"$prefix"_temp1_input
			check_n_link "$3""$4"/temp1_max $thermal_path/"$prefix"_temp1_max
			check_n_link "$3""$4"/temp1_crit $thermal_path/"$prefix"_temp1_crit
			check_n_link "$3""$4"/temp1_lcrit $thermal_path/"$prefix"_temp1_lcrit
			check_n_link "$3""$4"/temp1_max_alarm $alarm_path/"$prefix"_temp1_max_alarm
			check_n_link "$3""$4"/temp1_crit_alarm $alarm_path/"$prefix"_temp1_crit_alarm

			for i in {1..3}; do
				find_sensor_by_label "$3""$4" "in" "${VOLTMON_SENS_LABEL[$i]}"
				sensor_id=$?
				if [ ! $sensor_id -eq 0 ]; then
					check_n_link "$3""$4"/in"$sensor_id"_input $environment_path/"$prefix"_in"$i"_input
					if [ -f "$3""$4"/in"$sensor_id"_crit ]; then
						check_n_link "$3""$4"/in"$sensor_id"_crit $environment_path/"$prefix"_in"$i"_crit
					else
						check_n_link "$3""$4"/in"$sensor_id"_max $environment_path/"$prefix"_in"$i"_crit
					fi
					if [ -f "$3""$4"/in"$sensor_id"_lcrit ]; then
						# There is a problem in VCORE output of VR on Comex board. This output depends
						# on CPU frequency and according to MPS vendor theoretically can be 0.
						# Thus reported lcrit should be 0 too.
						# Currently problem is reported just for CFL CPU comex VR.
						if [ "$prefix" == "comex_voltmon1" ] || [ "$prefix" == "comex_voltmon2" ]; then
							if [ "$cpu_type" == "$CFL_CPU" ]; then
								if [ $sensor_id -eq $cfl_comex_vcore_out_idx ]; then
									chmod 644 "$3""$4"/in"$sensor_id"_lcrit
									echo 0 > "$3""$4"/in"$sensor_id"_lcrit
								fi
							fi
						fi
						check_n_link "$3""$4"/in"$sensor_id"_lcrit $environment_path/"$prefix"_in"$i"_lcrit
					else
						check_n_link "$3""$4"/in"$sensor_id"_min $environment_path/"$prefix"_in"$i"_lcrit
					fi
					if [ -f "$3""$4"/in"$sensor_id"_alarm ]; then
						check_n_link "$3""$4"/in"$sensor_id"_alarm $alarm_path/"$prefix"_in"$i"_alarm
					elif [ -f "$3""$4"/in"$sensor_id"_crit_alarm ]; then
						check_n_link "$3""$4"/in"$sensor_id"_crit_alarm $alarm_path/"$prefix"_in"$i"_alarm
					elif [ -f "$3""$4"/in"$sensor_id"_max_alarm ]; then
						check_n_link "$3""$4"/in"$sensor_id"_max_alarm $alarm_path/"$prefix"_in"$i"_alarm
					elif [ -f "$3""$4"/in"$sensor_id"_min_alarm ]; then
						check_n_link "$3""$4"/in"$sensor_id"_min_alarm $alarm_path/"$prefix"_in"$i"_alarm
					fi
					check_n_link "$3""$4"/in"$sensor_id"_min $environment_path/"$prefix"_in"$i"_min
					check_n_link "$3""$4"/in"$sensor_id"_max $environment_path/"$prefix"_in"$i"_max
				fi

				find_sensor_by_label "$3""$4" "curr" "${CURR_SENS_LABEL[$i]}"
				sensor_id=$?
				if [ ! $sensor_id -eq 0 ]; then
					check_n_link "$3""$4"/curr"$sensor_id"_input $environment_path/"$prefix"_curr"$i"_input
					if [ -f "$3""$4"/curr"$sensor_id"_alarm ]; then
						check_n_link "$3""$4"/curr"$sensor_id"_alarm $alarm_path/"$prefix"_curr"$i"_alarm
					elif [ -f "$3""$4"/curr"$sensor_id"_crit_alarm ]; then
						check_n_link "$3""$4"/curr"$sensor_id"_crit_alarm $alarm_path/"$prefix"_curr"$i"_alarm
					elif [ -f "$3""$4"/curr"$sensor_id"_max_alarm ]; then
						check_n_link "$3""$4"/curr"$sensor_id"_max_alarm $alarm_path/"$prefix"_curr"$i"_alarm
					fi
					check_n_link "$3""$4"/curr"$sensor_id"_lcrit $environment_path/"$prefix"_curr"$i"_lcrit
					check_n_link "$3""$4"/curr"$sensor_id"_min $environment_path/"$prefix"_curr"$i"_min
					check_n_link "$3""$4"/curr"$sensor_id"_max $environment_path/"$prefix"_curr"$i"_max
					check_n_link "$3""$4"/curr"$sensor_id"_crit $environment_path/"$prefix"_curr"$i"_crit
				fi

				find_sensor_by_label "$3""$4" "power" "${POWER_SENS_LABEL[$i]}"
				sensor_id=$?
				if [ ! $sensor_id -eq 0 ]; then
					check_n_link "$3""$4"/power"$sensor_id"_input $environment_path/"$prefix"_power"$i"_input
					check_n_link "$3""$4"/power"$sensor_id"_alarm $alarm_path/"$prefix"_power"$i"_alarm
					check_n_link "$3""$4"/power"$sensor_id"_lcrit $environment_path/"$prefix"_power"$i"_lcrit
					check_n_link "$3""$4"/power"$sensor_id"_min $environment_path/"$prefix"_power"$i"_min
					check_n_link "$3""$4"/power"$sensor_id"_max $environment_path/"$prefix"_power"$i"_max
					check_n_link "$3""$4"/power"$sensor_id"_crit $environment_path/"$prefix"_power"$i"_crit
				fi
			done
			;;
		esac
		# WA for fix negative vout_min value in lm5066i sensor
		dev_name=$(cat "$3""$4"/name)
		if  [ "$dev_name" == "lm5066i" ]; then
			if [ -f $environment_path/"$prefix"_in2_min ]; then
				val=$(cat $environment_path/"$prefix"_in2_min)
				# check if Vout min is negative and fix it
				if  [[ $val == -* ]]; then
					echo 0 > $environment_path/"$prefix"_in2_min
				fi
			fi
		fi
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
		# In newer switches the LED color is amber. This is a workaround
		# to avoid driver changes.
		color=$(echo "$5" | cut -d':' -f3)
		if [ "$color" == "orange" ]; then
			color="amber"
		fi
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
		reset_attr_num=$(< $config_path/reset_attr_num)
		reset_attrr_count=0
		linecard=0
		# Detect if it belongs to line card or to main board or to dpu.
		# For main board dirname mlxreg-io, for linecard - mlxreg-io.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		mlxreg-io)
			# Default case, nothing to do.
			;;
		mlxreg-io.*)
			sku=$(< /sys/devices/virtual/dmi/id/product_sku)
			if [[ $sku == "HI126" ]]; then
				# Line card event, replace output folder.
				input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
				find_linecard_num "$input_bus_num"
				system_path="$hw_management_path"/lc"$linecard_num"/system
				linecard="$linecard_num"
			else
				# DPU event, replace output folder.
				slot_num=$(echo "$driver_dir" | cut -d"." -f2)
				system_path="$hw_management_path"/dpu"$slot_num"/system
			fi
			;;
		esac
		# Allow insertion of all the attributes, but skip redundant cpld entries.
		if [ -d "$3""$4" ]; then
			local cpld_num
			for attrpath in "$3""$4"/*; do
				take=10
				attrname=$(basename "${attrpath}")
				check_cpld_attrs_num
				cpld_num=$?
				check_cpld_attrs "$attrname" "$cpld_num"
				take=$?
				if [ ! -d "$attrpath" ] && [ ! -L "$attrpath" ] &&
				   [ "$attrname" != "uevent" ] &&
				   [ "$attrname" != "name" ] && [ "$take" -ne 0 ] ; then
					ln -sf "$3""$4"/"$attrname" $system_path/"$attrname"
					check_reset_attrs "$attrname"
				fi
			done
			handle_cpld_versions "$cpld_num"
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
			set_fpga_combined_version "$lc_path"
		fi
	fi
	if [ "$2" == "eeprom" ]; then
		# During connecting non-existent eeprom dev, for a short time, 24C* driver
		# creates ./eeprom sysfs entry, To prevent mistaken eeprom connect, 
		# we should wait a short time to give a chance for the driver to 
		# remove ./eeprom entry (if the device is not present).
		sleep 0.1
		# Event came from none-eeprom device or eeprom not initialized.
		if [ ! -f "$3""$4"/eeprom ]; then
			exit
		fi
		busdir="$3""$4"
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		find_i2c_bus
		# Do not consider offset for native CPU bus.
		if [ "$bus" -gt "$i2c_bus_offset" ]; then
			bus=$((bus-i2c_bus_offset))
		fi
		addr="0x${busfolder: -2}"
		# Get parent bus for line card EEPROM - skip two folders.
		parentdir=$(dirname "$busdir")
		parentbus=$(basename "$parentdir")
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		eeprom_name=$(find_eeprom_name "$bus" "$addr" "$parentbus" "$input_bus_num")
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Linecard event, replace output folder.
				find_linecard_num "$input_bus_num"
				eeprom_path="$hw_management_path"/lc"$linecard_num"/eeprom
				# Parse VPD.
				if [ "$eeprom_name" == "fru" ]; then
					hw-management-vpd-parser.py -t LC_VPD -i "$3""$4"/eeprom -o "$eeprom_path"/vpd_parsed
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
			if [ ! -L "$eeprom_path/$eeprom_name" ]; then
				check_n_link "$3""$4"/eeprom $eeprom_path/$eeprom_name 2>/dev/null
				chmod 400 $eeprom_path/$eeprom_name 2>/dev/null
			fi
		else
			return
		fi
		case $eeprom_name in
		fan*_info)
			sku=$(< /sys/devices/virtual/dmi/id/product_sku)
			if [[ $sku == "HI138" ]] || [[ $sku == "HI139" ]]; then
				exit 0
			fi
			fan_prefix=$(echo $eeprom_name | cut -d_ -f1)
			if [ "$board_type" == "VMOD0014" ]; then
				hw-management-vpd-parser.py -t FIXED_FIELD_FAN_VPD -i $eeprom_path/$eeprom_name -o $eeprom_path/"$fan_prefix"_data
			else
				hw-management-vpd-parser.py -t MLNX_FAN_VPD -i $eeprom_path/$eeprom_name -o $eeprom_path/"$fan_prefix"_data
			fi
			# Get PSU FAN direction
			get_fan_direction_by_vpd $eeprom_path/"$fan_prefix"_data
			echo $? > $thermal_path/"${fan_prefix}"_dir
			;;
		vpd_info)
			hw-management-vpd-parser.py -t SYSTEM_VPD -i "$eeprom_path/$eeprom_name" -o "$eeprom_path"/vpd_data
			echo 1 > $config_path/events_ready
			;;
		cpu_info)
			hw-management-vpd-parser.py -t MLNX_CPU_VPD -i "$eeprom_path/$eeprom_name" -o "$eeprom_path"/cpu_data
			;;
		pdb_eeprom)
			hw-management-vpd-parser.py -i "$eeprom_path/$eeprom_name" -o "$eeprom_path"/pdb_data
			;;
		cable_cartridge*_eeprom*)
			if [ "$board_type" == "VMOD0021" ]; then
				if command -v ipmi-fru 2>&1 >/dev/null; then
					ipmi-fru --fru-file="$eeprom_path"/"$eeprom_name" > "$eeprom_path"/"$eeprom_name"_data
				fi
			else
				eeprom_vpd_filename=${eeprom_name/"_eeprom"/"_data"}
				hw-management-vpd-parser.py -i "$eeprom_path/$eeprom_name" -o "$eeprom_path"/$eeprom_vpd_filename
			fi
			;;
		fio_info)
			hw-management-vpd-parser.py -i "$eeprom_path/$eeprom_name" -o "$eeprom_path"/fio_data
			;;
		mgmt_fru*_info)
			eeprom_vpd_filename=${eeprom_name/"_info"/"_data"}
			if command -v ipmi-fru 2>&1 >/dev/null; then
				ipmi-fru --fru-file="$eeprom_path"/"$eeprom_name" > "$eeprom_path"/"$eeprom_vpd_filename"
			fi
			;;
		swb_info)
			if [ "$board_type" == "VMOD0021" ]; then
				if command -v ipmi-fru 2>&1 >/dev/null; then
					ipmi-fru --fru-file="$eeprom_path"/"$eeprom_name" > "$eeprom_path"/swb_data
				fi
			fi
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
	# Creating dpu folders hierarchy upon dpu udev add event.
	if [ "$2" == "dpu" ]; then
		case $sku in
		HI160)
			slot_num=$(find_dpu_slot "$3$4")
			if [ ! -d "$hw_management_path"/dpu"$slot_num" ]; then
				mkdir "$hw_management_path"/dpu"$slot_num"
			fi
			for i in "${!dpu_folders[@]}"
			do
				if [ ! -d "$hw_management_path"/dpu"$slot_num"/"${dpu_folders[$i]}" ]; then
					mkdir "$hw_management_path/"dpu"$slot_num"/"${dpu_folders[$i]}"
				fi
			done
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
	# Create i2c links.
	if [ "$2" == "i2c_link" ]; then
		create_main_i2c_links "$4"
	fi
elif [ "$1" == "hotplug-event" ]; then
	# Don't process udev events until service is started and directories are created
	if [ ! -f ${udev_ready} ]; then
		exit 0
	fi
	handle_hotplug_event "${2}" "${3}"
elif [ "$1" == "hotplug-dpu-event" ]; then
	# Don't process udev events until service is started and directories are created
	if [ ! -f ${udev_ready} ]; then
		exit 0
	fi
	handle_hotplug_dpu_event "${2}" "${3}" "${4}" "${5}"
elif [ "$1" == "fantray-led-event" ]; then
	# Don't process udev events until service is started and directories are created.
	if [ ! -f "${udev_ready}" ]; then
		exit 0
	fi
	case "$board_type" in
	VMOD0014)
		handle_fantray_led_event "${2}" "${3}"
		;;
	*)
		;;
	esac
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
		if [ "$board_type" == "VMOD0014" ]; then
			for i in {0..7}; do
				if [ -L $environment_path/"$2"_"$5"_voltage_scale_"$i" ]; then
					unlink $environment_path/"$2"_"$5"_voltage_scale_"$i"
				fi
			done
		else
			unlink $environment_path/"$2"_"$5"_voltage_scale
		fi
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
	   [ "$2" == "voltmon13" ] || [ "$2" == "voltmonX" ] ||
	   [ "$2" == "comex_voltmon1" ] || [ "$2" == "comex_voltmon2" ] ||
	   [ "$2" == "hotswap" ] || [ "$2" == "pmbus" ]; then
		prefix=$(get_i2c_busdev_name "$2" "$4")
		if [[ $prefix == "undefined" ]];
		then
			exit
		fi
		if [ "$prefix" == "comex_voltmon1" ] || [ "$prefix" == "comex_voltmon2" ]; then
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
			# Detect if it belongs to line card or to main board or to dpu.
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
			else
				sku=$(< /sys/devices/virtual/dmi/id/product_sku)
				case $sku in
				HI160)
					# DPU event, replace output folder.
					input_bus_num=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f1)
					slot_num=$(find_dpu_slot_from_i2c_bus $input_bus_num)
					if [ "$prefix" == "voltmon1" ] || [ "$prefix" == "voltmon2" ]; then
					    if [ ! -z "$slot_num" ]; then
						    environment_path="$hw_management_path"/dpu"$slot_num"/environment
						    alarm_path="$hw_management_path"/dpu"$slot_num"/alarm
						    thermal_path="$hw_management_path"/dpu"$slot_num"/thermal
					    fi
                    	fi
					;;
				*)
					;;
				esac
			fi
		fi
		# For SN2201 indexes are from 0 to 9.
		for i in {0..9}; do
			if [ -L $environment_path/"$prefix"_in"$i"_input ]; then
				unlink $environment_path/"$prefix"_in"$i"_input
			fi
			if [ -L $environment_path/"$prefix"_in"$i"_crit ]; then
				unlink $environment_path/"$prefix"_in"$i"_crit
			fi
			if [ -L $environment_path/"$prefix"_in"$i"_lcrit ]; then
				unlink $environment_path/"$prefix"_in"$i"_lcrit
			fi
			if [ -L $environment_path/"$prefix"_curr"$i"_input ]; then
				unlink $environment_path/"$prefix"_curr"$i"_input
			fi
			if [ -L $environment_path/"$prefix"_power"$i"_input ]; then
				unlink $environment_path/"$prefix"_power"$i"_input
			fi
			if [ -L $thermal_path/"$prefix"_temp"$i"_input ]; then
				unlink $thermal_path/"$prefix"_temp"$i"_input
			fi
			if [ -L $thermal_path/"$prefix"_temp"$i"_max ]; then
				unlink $thermal_path/"$prefix"_temp"$i"_max
			fi
			if [ -L $thermal_path/"$prefix"_temp"$i"_crit ]; then
				unlink $thermal_path/"$prefix"_temp"$i"_crit
			fi
			if [ -L $alarm_path/"$prefix"_in"$i"_alarm ]; then
				unlink $alarm_path/"$prefix"_in"$i"_alarm
			fi
			if [ -L $alarm_path/"$prefix"_curr"$i"_alarm ]; then
				unlink $alarm_path/"$prefix"_curr"$i"_alarm
			fi
			if [ -L $alarm_path/"$prefix"_power"$i"_alarm ]; then
				unlink $alarm_path/"$prefix"_power"$i"_alarm
			fi
			if [ -L $alarm_path/"$prefix"_temp"$i"_max_alarm ]; then
				unlink $alarm_path/"$prefix"_temp"$i"_max_alarm
			fi
			if [ -L $alarm_path/"$prefix"_temp"$i"_crit_alarm ]; then
				unlink $alarm_path/"$prefix"_temp"$i"_crit_alarm
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
		# In newer switches the LED color is amber. This is a workaround
		# to avoid driver changes.
		if [ "$color" == "orange" ]; then
			color="amber"
		fi
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
		# Detect if it belongs to line card or to main board or to dpu.
		# For main board dirname mlxreg-io, for line card - mlxreg-io.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		mlxreg-io)
			# Default case, nothing to do.
			;;
		mlxreg-io.*)
			if [[ $sku == "HI126" ]]; then
				# Line card event, replace output folder.
				input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
				find_linecard_num "$input_bus_num"
				system_path="$hw_management_path"/lc"$linecard_num"/system
			else
				# DPU event, replace output folder.
				slot_num=$(echo "$driver_dir" | cut -d"." -f2)
				system_path="$hw_management_path"/dpu"$slot_num"/system
			fi
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
		# Do not consider offset for native CPU bus.
		if [ "$bus" -gt "$i2c_bus_offset" ]; then
			bus=$((bus-i2c_bus_offset))
		fi
		addr="0x${busfolder: -2}"
		eeprom_name=$(find_eeprom_name_on_remove "$bus" "$addr")
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
	# Clear dpu folders upon line card udev rm event.
	if [ "$2" == "dpu" ]; then
		case $sku in
		HI160)
			slot_num=$(find_dpu_slot "$3$4")
			if [ -e "$devtree_file" ]; then
				disconnect_dynamic_board_devices "dpu_board""$slot_num"
			fi
			if [ ! -d "$hw_management_path"/dpu"$slot_num" ]; then
				rm -rf "$hw_management_path"/dpu"$slot_num"
			fi
			;;
		*)
			;;
		esac
	fi
	# Clear lc folders upon line card udev rm event.
	if [ "$2" == "linecard" ]; then
		input_bus_num=$(echo "$3""$4" | xargs dirname | cut -d"-" -f3)
		linecard_num=$((input_bus_num-line_card_bus_off))
		# Clean line card folders.
		if [ -d "$hw_management_path"/lc"$linecard_num" ]; then
			find "$hw_management_path"/lc"$linecard_num" -type l -exec unlink {} \;
			rm -rf "$hw_management_path"/lc"$linecard_num"
		fi
	fi
	# Destroy line card i2c mux symbolic link infrastructure.
	if [ "$2" == "lc_topo" ]; then
		destroy_linecard_i2c_links "$3"
	fi
	# Remove i2c bus.
	if [ "$2" == "i2c_bus" ]; then
		log_info "I2C bus $4 removed."
		handle_i2cbus_dev_action $4 "remove"
	fi
	# Removed i2c links.
	if [ "$2" == "i2c_link" ]; then
		destroy_main_i2c_links
	fi
fi
