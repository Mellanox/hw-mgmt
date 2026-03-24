#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# Deployed per platform to /etc by hw-management-bmc-plat-specific-preps (usr/etc/<HID>/).
devtr_bom_json="${HW_MANAGEMENT_BMC_BOM_JSON:-/etc/hw-management-bmc-bom.json}"

# Declare common associative arrays for SMBIOS System Version parsing.
declare -A board_arr=(["C"]="cpu_board" ["S"]="switch_board" ["F"]="fan_board" ["P"]="power_board" ["L"]="platform_board" ["K"]="clock_board" ["O"]="port_board" ["D"]="dpu_board")

declare -A category_arr=(["T"]="thermal" ["R"]="regulator" ["A"]="a2d" ["P"]="pressure" ["E"]="eeprom" ["O"]="powerconv" ["H"]="hotswap" ["G"]="gpio" ["N"]="network" ["J"]="jitter" ["X"]="osc" ["F"]="fpga", ["S"]="erot", ["C"]="rtc")

declare -A thermal_arr=(["0"]="dummy" ["a"]="lm75" ["b"]="tmp102" ["c"]="adt75" ["d"]="stts751" ["e"]="tmp75" ["f"]="tmp421" ["g"]="lm90" ["h"]="emc1412" ["i"]="tmp411" ["j"]="tmp1075" ["k"]="tmp451")

declare -A regulator_arr=(["0"]="dummy" ["a"]="mp2975" ["b"]="mp2888" ["c"]="tps53679" ["d"]="xdpe12284" ["e"]="152x4" ["f"]="pmbus" ["g"]="mp2891" ["h"]="xdpe1a2g7" ["i"]="mp2855" ["j"]="mp29816")

declare -A a2d_arr=(["0"]="dummy" ["a"]="max11603" ["b"]="ads1015")

declare -A pwr_conv_arr=(["0"]="dummy" ["a"]="pmbus" ["b"]="pmbus" ["c"]="pmbus" ["d"]="raa228000" ["e"]="mp29502" ["f"]="raa228004")

declare -A hotswap_arr=(["0"]="dummy" ["a"]="lm5066" ["c"]="lm5066i")

# Just currently used EEPROMs are in this mapping.
declare -A eeprom_arr=(["0"]="dummy" ["a"]="24c02" ["c"]="24c08" ["e"]="24c32" ["g"]="24c128" ["i"]="24c512")

declare -A pressure_arr=(["0"]="dummy" ["a"]="icp201xx" ["b"]="bmp390" ["c"]="lps22")

# Runtime SMBIOS BOM alternate maps (filled from ${devtr_bom_json} where deployed).
declare -A comex_alternatives
declare -A swb_alternatives
declare -A fan_alternatives
declare -A clk_alternatives
declare -A pwr_alternatives
declare -A platform_alternatives
declare -A port_alternatives
declare -A dpu_alternatives
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
			log_info "DBG SMBIOS BOM: string is not correct. Problem in Version part: ${system_ver_arr[0]}"
		fi
		return 1
	fi
	
	arr_len=${#system_ver_arr[@]}
	if [ "$arr_len" -lt 2 ]; then
		if [ $devtr_verb_display -eq 1 ]; then
			log_info "DBG SMBIOS BOM: string is not correct. Problem in number of string components: ${arr_len}"
		fi
		return 1
	fi

	# Currenly just one encode mechanism version exist.
	encode_ver=${system_ver_arr[0]:1:1}
	if [ "$encode_ver" -ne 0 ]; then
		log_err "SMBIOS BOM: unsupported encode version."
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

# Fill one associative array from a named array in ${devtr_bom_json}. Requires
# hw-management-bmc-json-parser.sh (nameref needs bash 4.3+).
devtr_bom_fill_alternatives_from_json()
{
	local json_file="$1"
	local section="$2"
	local -n _dest="$3"
	local n i block k v

	n=$(cat "$json_file" | json_count_nested_array "$section")
	for ((i = 0; i < n; i++)); do
		block=$(cat "$json_file" | json_get_nested_array_element "$section" "$i")
		k=$(echo "$block" | json_get_string "key")
		v=$(echo "$block" | json_get_string "spec")
		if [ -n "$k" ] && [ -n "$v" ]; then
			_dest["$k"]="$v"
		fi
	done
}

# Load optional SMBIOS BOM alternate component maps from ${devtr_bom_json}.
devtr_check_supported_system_init_alternatives()
{
	# Optional swb / platform / pwr tables: ${devtr_bom_json} (deployed from usr/etc/<HID>/).
	if [ -f "$devtr_bom_json" ] && [ -f /usr/bin/hw-management-bmc-json-parser.sh ]; then
		# shellcheck source=/dev/null
		source /usr/bin/hw-management-bmc-json-parser.sh
		if json_validate "$devtr_bom_json"; then
			devtr_bom_fill_alternatives_from_json "$devtr_bom_json" "swb" swb_alternatives
			devtr_bom_fill_alternatives_from_json "$devtr_bom_json" "platform" platform_alternatives
			devtr_bom_fill_alternatives_from_json "$devtr_bom_json" "pwr" pwr_alternatives
		elif [ "$devtr_verb_display" -eq 1 ]; then
			log_info "DBG SMBIOS BOM: skip, invalid JSON: ${devtr_bom_json}"
		fi
	fi
	return 0
}


devtr_check_board_components()
{
	local board_str=$1
	local board_num=1
	local board_bus_offset=0
	local board_name_pfx=
	local board_type=static
#	local board_addr_offset=0
	local comp_arr

	case $cpu_type in
	$ARMv7_CPU|$ARMv8_CPU)
		# Shell command "fold" is not available on this platform.
		# Iterate over the string with a step size of 2
		for ((i=0; i<${#board_str}; i+=2)); do
			local pair="${board_str:i:2}"
			comp_arr+=("$pair")
		done
		;;
	*)
		local comp_arr=($(echo "$board_str" | fold -w2))
		;;
	esac

	local board_key=${comp_arr[0]:0:1}
	local board_name=${board_arr[$board_key]}

	if [ $devtr_verb_display -eq 1 ]; then
		log_info "DBG SMBIOS BOM: Board: ${board_name}"
	fi

	board_alternatives=()

	case $board_key in
		C)	# CPU/Comex board
			for key in "${!comex_alternatives[@]}"; do
				board_alternatives["$key"]="${comex_alternatives["$key"]}"
			done
			;;
		S)	# Switch board
			# There can be several switch boards (e.g on q3400)
			if [ -e "$config_path"/swb_brd_num ]; then
				board_num=$(< $config_path/swb_brd_num)
				board_name_pfx=swb
			fi
			if [ -e "$config_path"/swb_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/swb_brd_bus_offset)
			fi
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
			# There can be several power boards (e.g on sn58xxld)
			if [ -e "$config_path"/pwr_brd_num ]; then
				board_num=$(< $config_path/pwr_brd_num)
				board_name_pfx=pdb
			fi
			if [ -e "$config_path"/pwr_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/pwr_brd_bus_offset)
			fi

			for key in "${!pwr_alternatives[@]}"; do
				board_alternatives["$key"]="${pwr_alternatives["$key"]}"
			done
			;;
		L)	# Platform or Carrier board
			for key in "${!platform_alternatives[@]}"; do
				board_alternatives["$key"]="${platform_alternatives["$key"]}"
			done
			;;
		K)	# Clock board
			# There can be several clock boards (e.g on SN5600)
			if [ -e "$config_path"/clk_brd_num ]; then
				board_num=$(< $config_path/clk_brd_num)
				board_name_pfx=clk
			fi
			if [ -e "$config_path"/clk_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/clk_brd_bus_offset)
			fi
#			if [ -e "$config_path"/clk_brd_addr_offset ]; then
#				board_addr_offset=$(< $config_path/clk_brd_addr_offset)
#			fi
			for key in "${!clk_alternatives[@]}"; do
				board_alternatives["$key"]="${clk_alternatives["$key"]}"
			done
			;;
		O)	# Port board
			for key in "${!port_alternatives[@]}"; do
				board_alternatives["$key"]="${port_alternatives["$key"]}"
			done
			;;
		D)	# DPU board
			# There are several DPU boards (SN4280)
			if [ -e "$config_path"/dpu_num ]; then
				board_num=$(< $config_path/dpu_num)
				board_name_pfx=dpu
			fi
			# Check if board and his components are "static", always available
			# or they are "dynamic". I.e., board can powered-off / powered-on.
			if [ -e "$config_path"/dpu_board_type ]; then
				board_type=$(< $config_path/dpu_board_type)
			fi
			if [ -e "$config_path"/dpu_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/dpu_brd_bus_offset)
			fi
			for key in "${!dpu_alternatives[@]}"; do
				board_alternatives["$key"]="${dpu_alternatives["$key"]}"
			done
			;;
		*)
			log_err "SMBIOS BOM: incorrect encoded board, board key ${board_key}"
			return 1
			;;
	esac

	local i=0; t_cnt=0; r_cnt=0; e_cnt=0; a_cnt=0; p_cnt=0; o_cnt=0; h_cnt=0; brd=0
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
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
					fi
					if [ ! -z "${board_name_pfx}" ]; then
						curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${t_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							printf '%s ' "${curr_component[@]}" >> "$dynamic_boards_path"/"$board_name_str"
						else
							printf '%s ' "${curr_component[@]}" >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[*]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				t_cnt=$((t_cnt+1))
				;;
			R)	# Voltage Regulators
				if [ "$component_key" == "0" ]; then
					r_cnt=$((r_cnt+1))
					continue
				fi
				component_name=${regulator_arr[$component_key]}
				alternative_key="${component_name}_${r_cnt}"
				# q3400 system has 2 switch boards. Just VRs are accessed on these boards.
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
					fi
					if [ ! -z "${board_name_pfx}" ]; then
						curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${r_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							printf '%s ' "${curr_component[@]}" >> "$dynamic_boards_path"/"$board_name_str"
						else
							printf '%s ' "${curr_component[@]}" >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[*]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				r_cnt=$((r_cnt+1))
				;;
			E)	# Eeproms
				if [ "$component_key" == "0" ]; then
					e_cnt=$((e_cnt+1))
					continue
				fi
				component_name=${eeprom_arr[$component_key]}
				alternative_key="${component_name}_${e_cnt}"
				# SN5600 system has 2 Clock boards. Just EEPROM is accessed on these boards.
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
# There is no currently address offset. Leave commented just for possible future use
#					if [ $board_addr_offset -ne 0 ]; then
#						curr_component[1]=$((curr_component[1]+board_addr_offset*brd))
#						curr_component[1]=0x$(echo "obase=16; ${curr_component[1]}"|bc)
#					fi
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
						curr_component[2]=0x$(echo "obase=16; ${curr_component[2]}"|bc)
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${e_cnt}"
					else
						printf '%s ' "${curr_component[@]}" >> "$devtree_file"
						if [ $devtr_verb_display -eq 1 ]; then
							if [ $board_num -gt 1 ]; then
								board_name_str="${board_name}${n}"
							else
								board_name_str="$board_name"
							fi
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[*]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
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
				if [ -z "${alternative_comp[0]}" ]; then
					log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${a_cnt}"
				else
					echo -n "${alternative_comp} " >> "$devtree_file"
					if [ $devtr_verb_display -eq 1 ]; then
						log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
						echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
					fi
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
				if [ -z "${alternative_comp[0]}" ]; then
					log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${p_cnt}"
				else
					echo -n "${alternative_comp} " >> "$devtree_file"
					if [ $devtr_verb_display -eq 1 ]; then
						log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
						echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
					fi
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
				# q3450 have 2 switch boards, each with 1 power converter
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					curr_component[2]=$((curr_component[2]+brd))
					if [ ! -z "${board_name_pfx}" ]; then
						curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${o_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							printf '%s ' "${curr_component[@]}" >> "$dynamic_boards_path"/"$board_name_str"
						else
							printf '%s ' "${curr_component[@]}" >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[*]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				o_cnt=$((o_cnt+1))
				;;
			H)	# Hot-swap
				if [ "$component_key" == "0" ]; then
					h_cnt=$((h_cnt+1))
					continue
				fi
				component_name=${hotswap_arr[$component_key]}
				alternative_key="${component_name}_${h_cnt}"
				# q3450 have 2 switch boards, each with 1 hot-swap controller
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					curr_component[2]=$((curr_component[2]+brd))
					if [ ! -z "${board_name_pfx}" ]; then
						curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${o_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							printf '%s ' "${curr_component[@]}" >> "$dynamic_boards_path"/"$board_name_str"
						else
							printf '%s ' "${curr_component[@]}" >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[*]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				h_cnt=$((h_cnt+1))
				;;
			G)	# GPIO Expander
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			N)	# Network Adapter
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			J)	# Jitter Attenuator
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			X)	# Oscillator
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			F)	# FPGA
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			S)	# EROT
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			C)	# RTC
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			*)
				log_err "SMBIOS BOM: incorrect encoded category, category key ${category_key}"
				return 1
				;;
		esac
	done
	return 0
}

# This is a main function for SMBIOS alternative BOM mechanism.
# It's called at early step hw-management init and can be also called
# from standalone debug script hw-management-bmc-devtree-check.sh.
# It's called without parameters in normal flow.
# It's called with 3 or 7 parameters in debug/simulation mode.
# $1 - SMBIOS system version string
# $2 - verbose simulation output and display of device tree
# $3 - create and use additional files with device codes
# $4 - board type (VMOD)
# $5 - system SKU
# $6 - location of devtree file
# $7 - CPU type: BDW_CPU, CFL_CPU, BF3_CPU
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
		log_info "DBG SMBIOS BOM: system version string: ${system_ver_str}"
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
			log_info "DBG SMBIOS BOM: Substring ${substr}"
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

