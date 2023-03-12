#!/bin/bash
################################################################################
# Copyright (c) 2022, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

devtr_verb_display=0
devtree_codes_file=

# Declare common associative arrays for SMBIOS System Version parsing.
declare -A board_arr=(["C"]="cpu_board" ["S"]="switch_board" ["F"]="fan_board" ["P"]="power_board" ["L"]="platform_board" ["K"]="clock_board")

declare -A category_arr=(["T"]="thermal" ["R"]="regulator" ["A"]="a2d" ["P"]="pressure" ["E"]="eeprom")

declare -A thermal_arr=(["0"]="dummy" ["a"]="lm75" ["b"]="tmp102" ["c"]="adt75" ["d"]="stts375")

declare -A regulator_arr=(["0"]="dummy" ["a"]="mp2975" ["b"]="mp2888" ["c"]="tps53679" ["d"]="xdpe12284" ["e"]="152x4")

declare -A a2d_arr=(["0"]="dummy" ["a"]="max11603")

declare -A pwr_conv_arr=(["0"]="dummy" ["a"]="pmbus")

# Just currently used EEPROMs are in this mapping.
declare -A eeprom_arr=(["0"]="dummy" ["a"]="24c02" ["c"]="24c08" ["e"]="24c32" ["g"]="24c128" ["i"]="24c512")

declare -A pressure_arr=(["0"]="dummy" ["a"]="icp201xx" ["b"]="bmp390" ["c"]="lps22")

# Declare component alternatives associative arrays.
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

declare -A msn4700_msn4600_alternatives=(["max11603_0"]="max11603 0x6d 5 swb_a2d" \
					 ["xdpe12284_0"]="xdpe12284 0x62 5 voltmon1" \
					 ["xdpe12284_1"]="xdpe12284 0x64 5 voltmon2" \
					 ["xdpe12284_2"]="xdpe12284 0x66 5 voltmon3" \
					 ["xdpe12284_3"]="xdpe12284 0x68 5 voltmon4" \
					 ["xdpe12284_4"]="xdpe12284 0x6a 5 voltmon5" \
					 ["xdpe12284_5"]="xdpe12284 0x6c 5 voltmon6" \
					 ["xdpe12284_6"]="xdpe12284 0x6e 5 voltmon7" \
					 ["mp2975_0"]="mp2975 0x62 5 voltmon1" \
					 ["mp2975_1"]="mp2975 0x64 5 voltmon2" \
					 ["mp2975_2"]="mp2975 0x66 5 voltmon3" \
					 ["mp2975_3"]="mp2975 0x6a 5 voltmon4" \
					 ["mp2975_4"]="mp2975 0x6e 5 voltmon5" \
					 ["tmp102_0"]="tmp102 0x4a 7 port_amb" \
					 ["24c32_0"]="24c32 0x51 8 system_eeprom")

declare -A mqm97xx_alternatives=(["mp2975_0"]="mp2975 0x62 5 voltmon1" \
				 ["mp2888_1"]="mp2888 0x66 5 voltmon3" \
				 ["mp2975_2"]="mp2975 0x68 5 voltmon4" \
				 ["mp2975_3"]="mp2975 0x6a 5 voltmon5" \
				 ["mp2975_4"]="mp2975 0x6c 5 voltmon6" \
				 ["mp2975_5"]="mp2975 0x6e 5 voltmon7" \
				 ["152x4_0"]="xpde152854 0x62 5 voltmon1" \
				 ["152x4_1"]="xpde152854 0x68 5 voltmon4" \
				 ["152x4_2"]="xpde152854 0x6a 5 voltmon5" \
				 ["152x4_3"]="xpde152854 0x6c 5 voltmon6" \
				 ["max11603_0"]="max11603 0x6d 5 swb_a2d" \
				 ["tmp102_0"]="tmp102 0x4a 7 port_amb" \
				 ["adt75_0"]="adt75 0x4a 7 port_amb" \
				 ["stts751_0"]="stts751 0x4a 7 port_amb" \
				 ["24c32_0"]="24c32 0x51 8 system_eeprom" \
				 ["24c512_0"]="24c512 0x51 8 system_eeprom")

declare -A mqm9510_alternatives=(["mp2975_0"]="mp2975 0x62 5 voltmon1" \
				 ["mp2888_1"]="mp2888 0x66 5 voltmon2" \
				 ["mp2975_2"]="mp2975 0x68 5 voltmon3" \
				 ["mp2975_3"]="mp2975 0x6c 5 voltmon4" \
				 ["mp2975_4"]="mp2975 0x62 6 voltmon5" \
				 ["mp2888_5"]="mp2888 0x66 6 voltmon6" \
				 ["mp2975_6"]="mp2975 0x68 6 voltmon7" \
				 ["mp2975_7"]="mp2975 0x6c 6 voltmon8" \
				 ["tmp102_0"]="tmp102 0x4a 7 port_amb" \
				 ["adt75_0"]="adt75 0x4a 7 port_amb" \
				 ["24c512_0"]="24c512 0x51 8 system_eeprom")

declare -A mqm9520_alternatives=(["mp2888_0"]="mp2975 0x66 5 voltmon1" \
				 ["mp2975_1"]="mp2975 0x68 5 voltmon2" \
				 ["mp2975_2"]="mp2975 0x6c 5 voltmon3" \
				 ["mp2888_3"]="mp2888 0x66 13 voltmon4" \
				 ["mp2975_4"]="mp2975 0x68 13 voltmon5" \
				 ["mp2975_5"]="mp2975 0x6c 13 voltmon6" \
				 ["tmp102_0"]="tmp102 0x4a 7 port_amb1" \
				 ["adt75_0"]="adt75 0x4a 7 port_amb1" \
				 ["tmp102_1"]="tmp102 0x4a 15 port_amb2" \
				 ["adt75_1"]="adt75 0x4a 15 port_amb2" \
				 ["24c512_0"]="24c512 0x51 8 system_eeprom")

declare -A sn5600_alternatives=(["max11603_0"]="max11603 0x6d 5 swb_a2d" \
				["mp2975_0"]="mp2975 0x62 5 voltmon1" \
				["mp2975_1"]="mp2975 0x63 5 voltmon2" \
				["mp2975_2"]="mp2975 0x64 5 voltmon3" \
				["mp2975_3"]="mp2975 0x65 5 voltmon4" \
				["mp2975_4"]="mp2975 0x66 5 voltmon5" \
				["mp2975_5"]="mp2975 0x67 5 voltmon6" \
				["mp2975_6"]="mp2975 0x68 5 voltmon7" \
				["mp2975_7"]="mp2975 0x69 5 voltmon8" \
				["mp2975_8"]="mp2975 0x6a 5 voltmon9" \
				["mp2975_9"]="mp2975 0x6c 5 voltmon10" \
				["mp2975_10"]="mp2975 0x6e 5 voltmon11" \
				["xdpe15284_0"]="xdpe15284 0x62 5 voltmon1" \
				["xdpe15284_1"]="xdpe15284 0x63 5 voltmon2" \
				["xdpe15284_2"]="xdpe15284 0x64 5 voltmon3" \
				["xdpe15284_3"]="xdpe15284 0x65 5 voltmon4" \
				["xdpe15284_4"]="xdpe15284 0x66 5 voltmon5" \
				["xdpe15284_5"]="xdpe15284 0x67 5 voltmon6" \
				["xdpe15284_6"]="xdpe15284 0x68 5 voltmon7" \
				["xdpe15284_7"]="xdpe15284 0x69 5 voltmon8" \
				["xdpe15284_8"]="xdpe15284 0x6a 5 voltmon9" \
				["xdpe15284_9"]="xdpe15284 0x6b 5 voltmon10" \
				["xdpe15284_10"]="xdpe15284 0x6e 5 voltmon11" \
				["tmp102_0"]="tmp102 0x4a 7 port_amb" \
				["adt75_0"]="tmp102 0x4a 7 port_amb" \
				["24c512_0"]="24c512 0x51 8 system_eeprom")

# Old connection table assumes that Fan amb temp sensors is located on main/switch board.
# Actually it's located on fan board and in this way it will be passed through SMBios
# string generated from Agile settings. Thus, declare also Fan board alternatives.
declare -A fan_type0_alternatives=(["tmp102_0"]="tmp102 0x49 7 fan_amb" \
				   ["adt75_0"]="adt75 0x49 7 fan_amb" \
				   ["stts751_0"]="stts751 0x49 7 fan_amb")

declare -A fan_type1_alternatives=(["tmp102_0"]="tmp102 0x49 6 fan_amb" \
				   ["adt75_0"]="adt75 0x49 6 fan_amb")

# Currently system can have just multiple clock boards.
declare -A clk_type0_alternatives=(["24c128_0"]="24c128 0x54 5 clk_eeprom1" \
				   ["24c128_1"]="24c128 0x57 5 clk_eeprom2")

declare -A pwr_type0_alternatives=(["pmbus_0"]="pmbus 0x10 4 pwr_conv1" \
				   ["pmbus_1"]="pmbus 0x11 4 pwr_conv2" \
				   ["pmbus_2"]="pmbus 0x13 4 pwr_conv3" \
				   ["pmbus_3"]="pmbus 0x15 4 pwr_conv4" \
				   ["icp201xx_0"]="icp201xx 0x63 4 press_sens1" \
				   ["icp201xx_1"]="icp201xx 0x64 4 press_sens2" \
				   ["max11603_0"]="max11603 0x6d 4 pwrb_a2d")

declare -A comex_alternatives
declare -A swb_alternatives
declare -A fan_alternatives
declare -A clk_alternatives
declare -A pwr_alternatives
declare -A board_alternatives

devtr_validate_system_ver_str()
{
	IFS='-'
	system_ver_arr=($system_ver_str)
	unset IFS
	local i=0

# Don't report error in 2 first checks as theoretically it can be a case
# of not customized/old SMBIOS field. Output is just in debug mode.
	substr_len=${#system_ver_arr[0]}
	if [[ ! ${system_ver_arr[0]} =~ V[0-9] ]] || [ "$substr_len" -ne 2 ]; then
		if [ $devtr_verb_display -eq 1 ]; then
			log_info "DBG: SMBIOS BOM string is not correct. Problem in Version part: ${system_ver_arr[0]}"
		fi
		return 1
	fi
	
	arr_len=${#system_ver_arr[@]}
	if [ "$arr_len" -lt 2 ]; then
		if [ $devtr_verb_display -eq 1 ]; then
			log_info "DBG: SMBIOS BOM string is not correct. Problem in number of string components: ${arr_len}"
		fi
		return 1
	fi

	# Currenly just one encode mechanism version exist.
	encode_ver=${system_ver_arr[0]:1:1}
	if [ "$encode_ver" -ne 0 ]; then
		log_err "Unsupported SMBios BOM encode version."
		return 2
	fi

	return 0
}

devtr_clean()
{
	if [ -e "$devtree_file" ]; then
		rm -f "$devtree_file"
	fi
	if [ -e "$devtree_codes_file" ]; then
		rm -f "$devtree_codes_file"
	fi
}

# Check if system has SMBios BOM changes mechanism support.
# If yes, init appropriate associative arrays.
# Jaguar, Leopard, Gorilla are added just for debug.
# This mechanism is enabled on new systems starting from Marlin.
devtr_check_supported_system_init_alternatives()
{
	case $cpu_type in
#		$BDW_CPU)
#			for key in "${!comex_bdw_alternatives[@]}"; do
#				comex_alternatives["$key"]="${comex_bdw_alternatives["$key"]}"
#			done
#			;;
		$CFL_CPU)
			if [ -e "$config_path"/cpu_brd_bus_offset ]; then
				cpu_brd_bus_offset=$(< $config_path/cpu_brd_bus_offset)
				for key in "${!comex_cfl_alternatives[@]}"; do
					curr_component=(${comex_cfl_alternatives["$key"]})
					curr_component[2]=$((curr_component[2]-base_cpu_bus_offset+cpu_brd_bus_offset))
					comex_alternatives["$key"]="${curr_component[0]} ${curr_component[1]} ${curr_component[2]} ${curr_component[3]}"
				done
			else
				for key in "${!comex_bdw_alternatives[@]}"; do
					comex_alternatives["$key"]="${comex_cfl_alternatives["$key"]}"
				done
			fi
			;;
		*)
			return 1
			;;
	esac
	case $board_type in
#		VMOD0005)
#			case $sku in
#				HI100)	# MQM8700
#					for key in "${!mqm8700_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm8700_alternatives["$key"]}"
#					done
#					;;
#				*)
#					return 1
#					;;
#			esac
#			for key in "${!fan_type0_alternatives[@]}"; do
#				fan_alternatives["$key"]="${fan_type0_alternatives["$key"]}"
#			done
#			return 0
#			;;
#		VMOD0010)
#			case $sku in
#				HI122|HI123|HI124|HI125)	# Leopard, Liger, Tigon, Leo
#					for key in "${!msn4700_msn4600_alternatives[@]}"; do
#						swb_alternatives["$key"]="${msn4700_msn4600_alternatives["$key"]}"
#					done
#					;;
#				HI130)	# MQM9700
#					for key in "${!mqm97xx_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm97xx_alternatives["$key"]}"
#					done
#					;;
#				HI140) # MQM9520
#					for key in "${!mqm9520_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm9520_alternatives["$key"]}"
#					done
#					;;
#				HI141) # MQM9510
#					for key in "${!mqm9510_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm9510_alternatives["$key"]}"
#					done
#					;;
#				*)
#					return 1
#					;;
#			esac
#			for key in "${!fan_type0_alternatives[@]}"; do
#				fan_alternatives["$key"]="${fan_type0_alternatives["$key"]}"
#			done
#			return 0
#			;;
		VMOD0013)
			case $sku in
				HI144|HI147|HI148)	# ToDo Separate later on.
					for key in "${!sn5600_alternatives[@]}"; do
						swb_alternatives["$key"]="${sn5600_alternatives["$key"]}"
					done
				;;
			*)
				return 1
				;;
			esac
			for key in "${!fan_type0_alternatives[@]}"; do
				fan_alternatives["$key"]="${fan_type1_alternatives["$key"]}"
			done
			for key in "${!pwr_type0_alternatives[@]}"; do
				pwr_alternatives["$key"]="${pwr_type0_alternatives["$key"]}"
			done
			for key in "${!clk_type0_alternatives[@]}"; do
				clk_alternatives["$key"]="${clk_type0_alternatives["$key"]}"
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
	local board_num=1
	local bus_offset=0
	local addr_offset=0

	local comp_arr=($(echo "$board_str" | fold -w2))

	local board_key=${comp_arr[0]:0:1}

	if [ $devtr_verb_display -eq 1 ]; then
		local board_name=${board_arr[$board_key]}
		log_info "DBG: Board: ${board_name}"
	fi

	case $board_key in
		C)	# CPU/Comex board
			for key in "${!comex_alternatives[@]}"; do
				board_alternatives["$key"]="${comex_alternatives["$key"]}"
			done
			;;
		S)	# Switch board
			for key in "${!swb_alternatives[@]}"; do
				board_alternatives["$key"]="${swb_alternatives["$key"]}"
			done
			;;
		F)	# Fan board
			for key in "${!fan_alternatives[@]}"; do
				board_alternatives["$key"]="${fan_alternatives["$key"]}"
			done
			;;
		P)	# Power board
			for key in "${!pwr_alternatives[@]}"; do
				board_alternatives["$key"]="${pwr_alternatives["$key"]}"
			done
			;;
		K)	# Clock board
			# Currently only clock boards number can be bigger than 1.
			if [ -e "$config_path"/clk_brd_num ]; then
				board_num=$(< $config_path/clk_brd_num)
			fi
			if [ -e "$config_path"/clk_brd_bus_offset ]; then
				bus_offset=$(< $config_path/clk_brd_bus_offset)
			fi
			if [ -e "$config_path"/clk_brd_addr_offset ]; then
				addr_offset=$(< $config_path/clk_brd_addr_offset)
			fi
			for key in "${!clk_alternatives[@]}"; do
				board_alternatives["$key"]="${clk_alternatives["$key"]}"
			done
			;;
		*)
			log_err "Incorrect SMBios BOM encoded board. Board key ${board_key}"
			return 1
			;;
	esac

	local i=0; t_cnt=0; r_cnt=0; e_cnt=0; a_cnt=0; p_cnt=0; o_cnt=0; brd=0
	curr_component=()
	for comp in "${comp_arr[@]}"; do
		# Skip 1st tuple in board string. It desctibes board name and number.
		# All other tuples describe components.
		if [ $i -eq 0 ]; then
		        i=$((i + 1))
		        continue
		fi
		category_key=${comp:0:1}
		component_key=${comp:1:2}

		category=${category_arr[$category_key]}  # Optional, just for print.
		case $category_key in
			T)	# Thermal Sensors
				# Don't process removed component.
				if [ "$component_key" == "0" ]; then
					t_cnt=$((t_cnt+1))
					continue
				fi
				component_name=${thermal_arr[$component_key]}
				alternative_key="${component_name}_${t_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				echo -n "${alternative_comp} " >> "$devtree_file"
				if [ $devtr_verb_display -eq 1 ]; then
					log_info "DBG: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
					echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
				fi
				t_cnt=$((t_cnt+1))
				;;
			R)	# Voltage Regulators
				if [ "$component_key" == "0" ]; then
					r_cnt=$((r_cnt+1))
					continue
				fi
				component_name=${regulator_arr[$component_key]}
				alternative_key="${component_name}_${r_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				echo -n "${alternative_comp} " >> "$devtree_file"
				if [ $devtr_verb_display -eq 1 ]; then
					log_info "DBG: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
					echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
				fi
				r_cnt=$((r_cnt+1))
				;;
			E)	# Eeproms
				if [ "$component_key" == "0" ]; then
					e_cnt=$((e_cnt+1))
					continue
				fi
				component_name=${eeprom_arr[$component_key]}
				alternative_key="${component_name}_${e_cnt}"
				# Currently it's done just for EEPROM as other components can't be in multiple cards of the same type
				# Moose system has 2 Clock boards. Just EEPROM is accessed on these boards.
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					if [ $addr_offset -ne 0 ]; then
						curr_component[1]=$((curr_component[1]+addr_offset*brd))
						curr_component[1]=0x$(echo "obase=16; ${curr_component[1]}"|bc)
					fi
					if [ $bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+bus_offset*brd))
						curr_component[2]=0x$(echo "obase=16; ${curr_component[2]}"|bc)
					fi
					echo -n "${curr_component[@]} " >> "$devtree_file"
					if [ $devtr_verb_display -eq 1 ]; then
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						log_info "DBG:  ${board_name} ${category} component - ${curr_component[@]}, category key: ${category_key}, device code: ${component_key}"
						echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
					fi
				done
				e_cnt=$((e_cnt+1))
				;;
			A)	# A2D
				if [ "$component_key" == "0" ]; then
					a_cnt=$((a_cnt+1))
					continue
				fi
				component_name=${a2d_arr[$component_key]}
				alternative_key="${component_name}_${a_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				echo -n "${alternative_comp} " >> "$devtree_file"
				if [ $devtr_verb_display -eq 1 ]; then
					log_info "DBG: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
					echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
				fi
				a_cnt=$((a_cnt+1))
				;;
			P)	# Pressure Sensors
				if [ "$component_key" == "0" ]; then
					p_cnt=$((p_cnt+1))
					continue
				fi
				component_name=${pressure_arr[$component_key]}
				alternative_key="${component_name}_${p_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				echo -n "${alternative_comp} " >> "$devtree_file"
				if [ $devtr_verb_display -eq 1 ]; then
					log_info "DBG: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
					echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
				fi
				p_cnt=$((p_cnt+1))
				;;
			O)	# Power Convertors
				if [ "$component_key" == "0" ]; then
					o_cnt=$((o_cnt+1))
					continue
				fi
				component_name=${pwr_conv_arr[$component_key]}
				alternative_key="${component_name}_${o_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				echo -n "${alternative_comp} " >> "$devtree_file"
				if [ $devtr_verb_display -eq 1 ]; then
					log_info "DBG: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
					echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
				fi
				o_cnt=$((o_cnt+1))
				;;
			*)
				log_err "Incorrect SMBios BOM encoded category. Category key ${category_key}"
				return 1
				;;
		esac
	done
	return 0
}

# This is a main function for SMBIOS alternative BOM mechanism.
# It's called at early step hw-management init and can be also called
# from standalone debug script hw-management-devtree-check.sh.
# It's called without parameters in normal flow.
# It's called with 3 or 7 parameters in debug/simulation mode.
# $1 - SMBios system version string
# $2 - verbose simulation output and display of device tree
# $3 - create and use additional files with device codes
# $4 - board type (VMOD)
# $5 - system SKU
# $6 - location of devtree file
# $7 - CPU type: BDW_CPU, CFL_CPU
devtr_check_smbios_device_description()
{
	system_ver_str=$(<$system_ver_file)
	# Check if system supports this mechanism.
	if ! devtr_check_supported_system_init_alternatives ; then
		return 1
	fi

	# Check if the call was done from standalone debug script with simualtion variables.
	if [ $# -eq 3 ]; then
		system_ver_str="$1"
		devtr_verb_display=$2
		devtree_codes_file="$3"
	elif [ $# -eq 7 ]; then
		system_ver_str="$1"
		devtr_verb_display=$2
		devtree_codes_file="$3"
		board_type="$4"
		sku="$5"
		devtree_file="$6"
		cpu_type="$7"
	fi

	devtr_clean

	if [ $devtr_verb_display -eq 1 ]; then
		log_info "DBG: SMBios system version string: ${system_ver_str}"
	fi
	devtr_validate_system_ver_str
	rc=$?
	if [ $rc -ne 0 ]; then
		devtr_clean
		return $rc
	fi

	local i=0
	for substr in "${system_ver_arr[@]}"; do
		# Skip 1st substring in system version string.
		# It's used as valid id and describes encoding version
		# that can be changed in the future.
		if [ $devtr_verb_display -eq 1 ]; then
			log_info "DBG: Substring ${substr}"
		fi
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

