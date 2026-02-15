#!/bin/bash
################################################################################
# Copyright (c) 2024 - 2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# This script is used as standalone for debug. 

source hw-management-helpers.sh
source hw-management-devtree.sh
board_type=$(<"$board_type_file")
cpu_type=$(<"$config_path"/cpu_type)
devtr_verb_display=0
devtree_codes_file="${PWD}/devtree_codes"

usage()                                                                                              
{                                                                                                    
        printf "Usage:\\t %s -d | -s | -p | -c | -h | -S | -v\\n" `basename "$0"`
	printf "%s\\t display device tree\\n" "-d"
	printf "%s\\t show system version SMBIOS string\\n" "-s"
	printf "%s\\t parse provided SMBIOS BOM string and create devtree\\n" "-p <SMBIOS_BOM_STR>"
	printf "%s\\t convert devtree file to csv format for Excel\\n" "-c"
	printf "%s\\t simulate parameters for debug through environment variables:\\n" "-S"
	printf "\\t DT_BOARD_TYPE, DT_SYS_SKU, DT_PATH, DT_CPU_TYPE\\n"
	printf "%s\\t verbose simulation output and display of device tree\\n" "-v"
	printf "\\t Simulation output will be written to journal log\\n"
	printf "\\t To read: journalctl | grep -E 'hw-management | DBG:'\\n"
	printf "\\t Display will include Category and Device code info\\n"
	printf "%s\\t this help\\n" "-h"
}

devtr_show_devtree_file()
{
	if [ -e "$devtree_file" ]; then
		declare -a devtree_table=($(<"$devtree_file"))

		if [ $devtr_verb_display -eq 1 ]; then
			if [ -e "$devtree_codes_file" ]; then
				declare -a devtree_codes_table=($(<"$devtree_codes_file"))
			else
				devtr_verb_display=0
				echo "No verbose devtree_codes file"
			fi
		fi

		local arr_len=${#devtree_table[@]}
		arr_len=$((arr_len/4))
		echo "Number of components in devtree: ${arr_len}"
		printf "Number\\t\\tBus\\tAddress\\tDevice\\t\\tName\\n"

		for ((i=0, j=0, k=0; i<${#devtree_table[@]}; i+=4, j+=1, k+=3)); do
			strlen=${#devtree_table[i]}
			if [ "$strlen" -lt 8 ]; then
				printf "Device %s:\\t%s\\t%s\\t%s\\t\\t%s\\n" "${j}" "${devtree_table[i+2]}" "${devtree_table[i+1]}" "${devtree_table[i]}" "${devtree_table[i+3]}"
				if [ $devtr_verb_display -eq 1 ]; then
					printf "\\tBoard name: %s\\tCategory code: %s\\tDevice code: %s\\n" "${devtree_codes_table[k]}" "${devtree_codes_table[k+1]}" "${devtree_codes_table[k+2]}"
				fi
			else
				printf "Device %s:\\t%s\\t%s\\t%s\\t%s\\n" "${j}" "${devtree_table[i+2]}" "${devtree_table[i+1]}" "${devtree_table[i]}" "${devtree_table[i+3]}"
				if [ $devtr_verb_display -eq 1 ]; then
					printf "\\tBoard name: %s\\tCategory code: %s\\tDevice code: %s\\n" "${devtree_codes_table[k]}" "${devtree_codes_table[k+1]}" "${devtree_codes_table[k+2]}"
				fi
			fi
		done
	else
		echo "No devicetree file"
	fi
}

devtr_2_csv_convert()
{
	if [ -e "$devtree_file" ]; then
		declare -a devtree_table=($(<"$devtree_file"))

		if [ $devtr_verb_display -eq 1 ]; then
			if [ -e "$devtree_codes_file" ]; then
				declare -a devtree_codes_table=($(<"$devtree_codes_file"))
			else
				devtr_verb_display=0
				echo "No verbose devtree_codes file"
			fi
		fi
		devtree_dir=$(dirname "${devtree_file}")
		devtree_csv_file="$devtree_dir""/"devtree.csv

		if [ $devtr_verb_display -eq 0 ]; then
			echo "Device,Bus,Address,Device name" > "$devtree_csv_file"
			for ((i=0; i<${#devtree_table[@]}; i+=4)); do
				echo  "${devtree_table[i]}""," "${devtree_table[i+1]}""," "${devtree_table[i+2]}""," "${devtree_table[i+3]}" >> "$devtree_csv_file"
			done
		else
			echo "Device,Bus,Address,Device name,Board name,Category code,Device code" > "$devtree_csv_file"
			for ((i=0, j=0; i<${#devtree_table[@]}; i+=4, j+=3)); do
				echo  "${devtree_table[i]}""," "${devtree_table[i+1]}""," "${devtree_table[i+2]}""," "${devtree_table[i+3]}""," "${devtree_codes_table[j]}""," "${devtree_codes_table[j+1]}""," "${devtree_codes_table[j+2]}" >> "$devtree_csv_file"
			done
		fi
	else
		echo "No devicetree file"
	fi
}

# Simulation parameters can be passed to the script through environment.
# DT_BOARD_TYPE - SMBIOS VMOD variable
# DT_SYS_SKU - system SKU
# DT_PATH -full path of devtree file for use. Default is /var/run/hw-management/config
# DT_CPU_TYPE - simulate other CPU. Currently Broadwell, Coffelake and BF3 CPUs are supported
# 	BDW_CPU, CFL_CPU, BF3_CPU, AMD_CPU e.g. export DT_CPU_TYPE=BDW_CPU
devtr_sim_environment_vars()
{
	if [[ -z "${DT_BOARD_TYPE}" ]]; then
		board_type=$(<"$board_type_file")
	else
		board_type="${DT_BOARD_TYPE}"
	fi

	if [[ -z "${DT_SYS_SKU}" ]]; then
		sku=$(< $sku_file)
	else
		sku="${DT_SYS_SKU}"
	fi

	if [[ -z "${DT_PATH}" ]]; then
		devtree_file="$config_path"/devtree
		if [ $devtr_verb_display -eq 1 ]; then
			devtree_codes_file="$config_path"/devtree_codes
		fi
	else
		devtree_file="${DT_PATH}"/devtree
		if [ $devtr_verb_display -eq 1 ]; then
			devtree_codes_file="${DT_PATH}"/devtree_codes
		fi
	fi

	if [[ -z "${DT_CPU_TYPE}" ]]; then
		cpu_type=$(<"$config_path"/cpu_type)		
	else
		case $DT_CPU_TYPE in
			BDW_CPU)
				cpu_type="${BDW_CPU}"
				;;
			CFL_CPU)
				cpu_type="${CFL_CPU}"
				;;
			BF3_CPU)
				cpu_type="${BF3_CPU}"
				;;
			AMD_SNW_CPU)
				cpu_type="${AMD_SNW_CPU}"
				;;
			*)
				cpu_type=$(<"$config_path"/cpu_type)
				;;
		esac
	fi
}

param_num=$#
rc=0
devtr_display=0
devtr_parse=0
devtr_sim=0
devtr_csv_convert=0
if [ "$param_num" -ge 1 ]; then
	OPTIND=1
	optspec="dsShcp:v"
	while getopts "$optspec" optchar; do
		case "${optchar}" in
			d)
				devtr_display=1
				;;
			s)
				smbios_bom_str=$(<"$system_ver_file")
				echo "Devtree SMBios string: ${smbios_bom_str}"
				;;
			h)
				usage
				;;
			p)
				devtr_parse=1
				smbios_bom_str=${OPTARG}
				;;
			S)
				devtr_sim=1
				;;
			v)
				devtr_verb_display=1
				;;
			c)
				devtr_csv_convert=1
				;;
			*)
				usage
				rc=1
				;;
		esac
	done
	shift $((OPTIND-1))
else
	usage
	exit 1
fi

devtr_sim_environment_vars

if [ $devtr_display -eq 1 ]; then
	devtr_show_devtree_file
elif [ $devtr_csv_convert -eq 1 ]; then
	devtr_2_csv_convert
elif [ $devtr_parse -eq 1 ]; then
	if [ $devtr_sim -eq 1 ]; then
		devtr_check_smbios_device_description "$smbios_bom_str" "$devtr_verb_display" "$devtree_codes_file" "$board_type" "$sku" "$devtree_file" "$cpu_type"
	else
		devtr_check_smbios_device_description "$smbios_bom_str" "$devtr_verb_display" "$devtree_codes_file"
	fi
	rc=$?
fi 

exit "$rc"
