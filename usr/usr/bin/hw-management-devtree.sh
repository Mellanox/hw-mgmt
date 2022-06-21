#!/bin/bash
################################################################################
# Copyright (c) 2018-2022, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# ToDo: Move default conenction tables here. They will be used in case of SMBios error.

system_ver_file=/sys/devices/virtual/dmi/id/product_version
sku=$(< /sys/devices/virtual/dmi/id/product_sku)

# Declare common associative arrays for SMBIOS System Version parsing
declare -A board_arr=(["C"]="comex" ["S"]="switch_board" ["F"]="fan_board" ["P"]="power_board" ["L"]="platform_board")

declare -A category_arr=(["T"]="thermal" ["R"]="regulator" ["A"]="a2d" ["P"]="pressure" ["E"]="eeprom")

declare -A thermal_arr=(["0"]="dummy" ["a"]="lm75" ["b"]="tmp102" ["c"]="adt75" ["d"]="stts375")

declare -A regulator_arr=(["0"]="dummy" ["a"]="mp2975" ["b"]="mp2888" ["c"]="tps53679" ["d"]="xdpe12284" ["e"]="152x4")

declare -A a2d_arr=(["0"]="dummy" ["a"]="max11603")

declare -A eeprom_arr=(["0"]="dummy" ["a"]="24c02" ["c"]="24c08" ["e"]="24c32" ["i"]="24c512")	# Just currently used EEPROMs are in this mapping

declare -A pressure_arr=(["0"]="dummy" ["a"]="icp20100" ["b"]="bmp390" ["c"]="lps22")

# Declare component alternatives associative arrays
declare -A comex_bdw_alternatives=(["mp2975_0"]="mp2975 0x61 15 comex_voltmon2" \
				   ["mp2975_1"]="mp2975 0x6a 15 comex_voltmon1" \
				   ["tps53679_0"]="tps53679 0x58 15 comex_voltmon1" \
				   ["tps53679_1"]="tps53679 0x61 15 comex_voltmon2" \
				   ["xdpe12284_0"]="xdpe12284 0x62 15 comex_voltmon1" \
				   ["xdpe12284_1"]="xdpe12284 0x64 15 comex_voltmon2" \
				   ["max11603_0"]="max11603 0x6d 15 comex_a2d" \
				   ["tmp102_0"]="tmp102 0x49 15 cpu_amb" \
				   ["adt75_0"]="adt75 0x49 15 cpu_amb" \
				   ["24c32_0"]="24c32 0x50 16 comex_eeprom")

declare -A comex_cfl_alternatives=(["mp2975_0"]="mp2975 0x6b 15 comex_voltmon1" \
				   ["max11603_0"]="max11603 0x6d 15 comex_a2d" \
				   ["24c32_0"]="24c32 0x50 16 comex_eeprom" \
				   ["24c512_0"]="24c512 0x50 16 comex_eeprom")

declare -A mqm8700_alternatives=(["max11603_0"]="max11603 0x64 5 swb_a2d" \
				 ["tps53679_0"]="tps53679 0x70 5 voltmon1" \
				 ["tps53679_1"]="tps53679 0x71 5 voltmon2" \
				 ["mp2975_0"]="mp2975 0x62 5 voltmon1" \
				 ["mp2975_1"]="mp2975 0x66 5 voltmon2" \
				 ["tmp102_0"]="tmp102 0x4a 7 port_amb" \
				 ["24c32_0"]="24c32 0x51 8 system_eeprom")

declare -A msn3700_alternatives=(["mp2975_0"]="mp2975 0x62 5 voltmon1" \
				 ["mp2975_1"]="mp2975 0x66 5 voltmon2" \
				 ["tps53679_0"]="tps53679 0x70 5 voltmon1" \
				 ["tps53679_1"]="tps53679 0x71 5 voltmon2" \
				 ["max11603_0"]="max11603 0x64 5 swb_a2d" \
				 ["tmp102_0"]="tmp102 0x4a 7 port_amb" \
				 ["adt75_0"]="adt75 0x4a 7 port_amb" \
				 ["24c32_0"]="24c32 0x51 8 system_eeprom" \
				 ["24c512_0"]="24c512 0x51 8 system_eeprom")

declare -A msn4700_msn4600_alternatives=(["max11603_0"]="max11603 0x6d 5 swb_a2d" \
					 ["xdpe12284_0"]="xdpe12284 0x62 5 voltmon1" \
					 ["xdpe12284_0"]="xdpe12284 0x64 5 voltmon2" \
					 ["xdpe12284_0"]="xdpe12284 0x66 5 voltmon3" \
					 ["xdpe12284_0"]="xdpe12284 0x68 5 voltmon4" \
					 ["xdpe12284_0"]="xdpe12284 0x6a 5 voltmon5" \
					 ["xdpe12284_0"]="xdpe12284 0x6c 5 voltmon6" \
					 ["xdpe12284_0"]="xdpe12284 0x6e 5 voltmon7" \
					 ["mp2975_0"]="mp2975 0x62 5 voltmon1" \
					 ["mp2975_0"]="mp2975 0x64 5 voltmon2" \
					 ["mp2975_0"]="mp2975 0x66 5 voltmon3" \
					 ["mp2975_0"]="mp2975 0x6a 5 voltmon4" \
					 ["mp2975_0"]="mp2975 0x6e 5 voltmon5" \
					 ["tmp102_0"]="tmp102 0x4a 7 port_amb" \
					 ["24c32_0"]="24c32 0x51 8 system_eeprom")

declare -A mqm97xx_alternatives=(["mp2975_0"]="mp2975 0x62 5 voltmon1" \
				 ["mp2888_1"]="mp2888 0x66 5 voltmon2" \
				 ["mp2975_2"]="mp2975 0x68 5 voltmon3" \
				 ["mp2975_3"]="mp2975 0x6a 5 voltmon4" \
				 ["mp2975_4"]="mp2975 0x6c 5 voltmon5" \
				 ["mp2975_5"]="mp2975 0x6e 5 voltmon6" \
				 ["max11603_0"]="max11603 0x6d 5 swb_a2d" \
				 ["tmp102_0"]="tmp102 0x4a 7 port_amb" \
				 ["adt75_0"]="adt75 0x4a 7 port_amb" \
				 ["24c32_0"]="24c32 0x51 8 system_eeprom" \
				 ["24c512_0"]="24c512 0x51 8 system_eeprom")

# Old connection table assumes that Fan amb temp sensors is located on main/switch board
# Actually it's located on fan board and in this way it will be passed through SMBios
# string generated from Agile settings. Thus, declare also Fan board alternatives.
declare -A fan_type0_alternatives=(["tmp102_0"]="tmp102 0x49 7 fan_amb" \
				   ["adt75_0"]="adt75 0x49 7 fan_amb")

# Todo init according to cputype & VMOD
declare -A comex_alternatives
declare -A swb_alternatives
declare -A fan_alternatives
declare -A board_alternatives

devtr_validate_system_ver_str()
{
	IFS='-'
	system_ver_arr=($system_ver_str)
	unset IFS
	local i=0

	substr_len=${#system_ver_arr[0]}
	if [[ ! ${system_ver_arr[0]} =~ V[0-9] ]] || [ "$substr_len" -ne 2 ]; then
		log_info "DBG: SMBIOS BOM string is not correct"		# TMP Dbg. return without error print, old systems
		return 1
	fi

	arr_len=${#system_ver_arr[@]}
	if [ "$arr_len" -lt 2 ]; then
		log_info "DBG: SMBIOS BOM string is not correct"		# TMP Dbg. return without error print, old systems
		return 1
	fi

	# Currenly just one encode mechanism version exist
	encode_ver=${system_ver_arr[0]:1:1}
	if [ "$encode_ver" -ne 0 ]; then
		log_err "Unsupported encode version."
		return 2
	fi

	return 0
}

devtr_clean()
{
	if [ -e "$devtree_file" ]; then
		rm -f "$devtree_file"
	fi
}

# Check if system has SMBios BOM changes mechanism support.
# If yes, init appropriate associative arrays.
devtr_check_supported_system_init_alternatives()
{
	case $cpu_type in
		$BDW_CPU)
			for key in "${!comex_bdw_alternatives[@]}"; do
				comex_alternatives["$key"]="${comex_bdw_alternatives["$key"]}"
			done
			;;
		$CFL_CPU)
			for key in "${!comex_cfl_alternatives[@]}"; do
				comex_alternatives["$key"]="${comex_cfl_alternatives["$key"]}"
			done
			;;
		*)
			return 1
			;;
	esac
	case $board_type in
		VMOD0005)
			case $sku in
				HI100)	# Jaguar
					for key in "${!mqm8700_alternatives[@]}"; do
						swb_alternatives["$key"]="${mqm8700_alternatives["$key"]}"
					done
					;;
				HI112|HI116|HI136)	# Anaconda
					for key in "${!msn3700_alternatives[@]}"; do
						swb_alternatives["$key"]="${msn3700_alternatives["$key"]}"
					done
					;;
				*)
					return 1
					;;
			esac
			for key in "${!fan_type0_alternatives[@]}"; do
				fan_alternatives["$key"]="${fan_type0_alternatives["$key"]}"
			done
			return 0
			;;
		VMOD0010)
			case $sku in
				HI122|HI123|HI124|HI125)	# Leopard, Liger, Tigon, Leo
					for key in "${!msn4700_msn4600_alternatives[@]}"; do
						swb_alternatives["$key"]="${msn4700_msn4600_alternatives["$key"]}"
					done
					;;
				HI130)	# Gorilla
					for key in "${!mqm97xx_alternatives[@]}"; do
						swb_alternatives["$key"]="${mqm97xx_alternatives["$key"]}"
					done
					;;
				*)
					return 1
					;;
			esac
			for key in "${!fan_type0_alternatives[@]}"; do
				fan_alternatives["$key"]="${fan_type0_alternatives["$key"]}"
			done
			return 0
			;;
		*)
			return 1
			;;
	esac
}

devtr_check_board_components()
{
	local board_str=$1

	local comp_arr=($(echo "$board_str" | fold -w2))

	local board_key=${comp_arr[0]:0:1}
	local board_name=${board_arr[$board_key]}	# Optional, just for print
	log_info "DBG: board: ${board_name}"

	case $board_key in
		C)
			for key in "${!comex_alternatives[@]}"; do
				board_alternatives["$key"]="${comex_alternatives["$key"]}"
			done
			;;
		S)
			for key in "${!swb_alternatives[@]}"; do
				board_alternatives["$key"]="${swb_alternatives["$key"]}"
			done
			;;
		F)
			for key in "${!fan_alternatives[@]}"; do
				board_alternatives["$key"]="${fan_alternatives["$key"]}"
			done
			;;
		*)
			log_err "Incorrect encoded board. Board key ${board_key}"
			return 1
			;;
	esac

	local i=0; t_cnt=0; r_cnt=0; e_cnt=0; a_cnt=0; p_cnt=0
	for comp in "${comp_arr[@]}"; do
		# Skip 1st tuple in board string. It desctibes board naem and number
		# All other tuples describe components
		if [ $i -eq 0 ]; then
		        i=$((i + 1))
		        continue
		fi
		category_key=${comp:0:1}
		component_key=${comp:1:2}
		# Don't process removed component
		if [ "$component_key" == "0" ]; then
			continue
		fi
		category=${category_arr[$category_key]}  # Optional, just for print
		case $category_key in
			T)
				component_name=${thermal_arr[$component_key]}
				alternative_key="${component_name}_${t_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				log_info "DBG: ${category} component - ${alternative_comp}"
				echo -n "${alternative_comp} " >> "$devtree_file"
				t_cnt=$((t_cnt+1))
				;;
			R)
				component_name=${regulator_arr[$component_key]}
				alternative_key="${component_name}_${r_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				log_info "DBG: ${category} component - ${alternative_comp}"
				echo -n "${alternative_comp} " >> "$devtree_file"
				r_cnt=$((r_cnt+1))
				;;
			E)
				component_name=${eeprom_arr[$component_key]}
				alternative_key="${component_name}_${e_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				log_info "DBG: ${category} component - ${alternative_comp}"
				echo -n "${alternative_comp} " >> "$devtree_file"
				e_cnt=$((e_cnt+1))
				;;
			A)
				component_name=${a2d_arr[$component_key]}
				alternative_key="${component_name}_${a_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				log_info "DBG: ${category} component - ${alternative_comp}"
				echo -n "${alternative_comp} " >> "$devtree_file"
				a_cnt=$((a_cnt+1))
				;;
			P)
				component_name=${pressure_arr[$component_key]}
				alternative_key="${component_name}_${p_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				log_info "DBG: ${category} component - ${alternative_comp}"
				echo -n "${alternative_comp} " >> "$devtree_file"
				p_cnt=$((p_cnt+1))
				;;
			*)
				log_err "Incorrect encoded category. Category key ${category_key}"
				return 1
				;;
		esac
	done
	return 0
}

devtr_check_smbios_device_description()
{
	# 1st of all check if system supports this mechanism
	if ! devtr_check_supported_system_init_alternatives ; then
		return 1
	fi

	devtr_clean

	system_ver_str=$(<$system_ver_file)
#	log_info "DBG: SMBios system version string: ${system_ver_str}"
	devtr_validate_system_ver_str
	rc=$?
	if [ $rc -ne 0 ]; then
		devtr_clean
		return $rc
	fi

	local i=0
	for substr in "${system_ver_arr[@]}"; do
		# Skip 1st substring in system version string
		# It's used as valid id and describes encoding version
		# that can be changed in the future.
#		log_info "DBG: Substring ${substr}"
		if [ $i -eq 0 ]; then
			i=$((i + 1))
			continue
		fi
		if ! devtr_check_board_components "$substr" ; then
			devtr_clean
			return 1
		fi
	done
	return 0
}

