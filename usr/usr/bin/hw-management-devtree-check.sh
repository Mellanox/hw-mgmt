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

# This script is used as standalone for debug. 

source hw-management-helpers.sh
source hw-management-devtree.sh
system_ver_file=/sys/devices/virtual/dmi/id/product_version
board_type=$(<"$board_type_file")
cpu_type=$(<"$config_path"/cpu_type)

usage()                                                                                              
{                                                                                                    
        printf "Usage:\\t %s <-d> | <-s> | <-p> | | -S | <-h>\\n" `basename "$0"` 
	printf "%s\\t display device tree\\n" "-d"
	printf "%s\\t show system version SMBIOS string\\n" "-s"
	printf "%s\\t parse provided SMBIOS sysver string and create devtree\\n" "-p <SMBIOS_SYS_VER>"
	printf "%s\\t simulate parameters for debug through environment variables:\\n" "-S"
	printf "\\t DT_BOARD_TYPE, DT_SYS_SKU, DT_PATH, DT_CPU_TYPE\\n"
	printf "%s\\t this help\\n" "-h"
}

devtr_show_devtree_file()
{
	if [ -e "$devtree_file" ]; then
		declare -a devtree_table=($(<"$devtree_file"))

		local arr_len=${#devtree_table[@]}
		arr_len=$((arr_len/4))
		echo "Number of components in devtree: ${arr_len}"
		printf "Number\\t\\tBus\\tAddress\\tDevice\\t\\tName\\n"

		for ((i=0, j=0; i<${#devtree_table[@]}; i+=4, j+=1)); do
			strlen=${#devtree_table[i]}
			if [ "$strlen" -lt 8 ]; then
				printf "Device %s:\\t%s\\t%s\\t%s\\t\\t%s\\n" "${j}" "${devtree_table[i+2]}" "${devtree_table[i+1]}" "${devtree_table[i]}" "${devtree_table[i+3]}"
			else
				printf "Device %s:\\t%s\\t%s\\t%s\\t%s\\n" "${j}" "${devtree_table[i+2]}" "${devtree_table[i+1]}" "${devtree_table[i]}" "${devtree_table[i+3]}"
			fi
		done
	else
		echo "No devicetree file"
	fi
}

# Simulation parameters can be passed to the script through environment
# DT_BOARD_TYPE - SMBIOS VMOD variable
# DT_SYS_SKU - system SKU
# DT_PATH -full path of devtree file for use. Default is /var/run/hw-management/config
# DT_CPU_TYPE - simulate other CPU. Currently Broadwell and Coffelake CPUs are supported
# 	BDW_CPU, CFL_CPU e.g. export DT_CPU_TYPE=BDW_CPU
devtr_sim_environment_vars()
{
	if [[ -z "${DT_BOARD_TYPE}" ]]; then
		board_type=$(<"$board_type_file")
	else
		board_type="${DT_BOARD_TYPE}"
	fi

	if [[ -z "${DT_SYS_SKU}" ]]; then
		sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	else
		sku="${DT_SYS_SKU}"
	fi

	if [[ -z "${DT_PATH}" ]]; then
		devtree_file="$config_path"/devtree
	else
		devtree_file="${DT_PATH}"/devtree
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
if [ "$param_num" -ge 1 ]; then 
	OPTIND=1
	optspec="dsShp:"
	while getopts "$optspec" optchar; do
		case "${optchar}" in
			d)
				devtr_display=1
				;;
			s)
				smbios_sysver_str=$(<$system_ver_file)
				echo "Devtree SMBios string: ${smbios_sysver_str}"
				;;
			h)
				usage
				;;
			p)
				devtr_parse=1
				smbios_sysver_str=${OPTARG}
				;;
			S)	
				devtr_sim_environment_vars
				devtr_sim=1
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

if [ $devtr_display -eq 1 ]; then
	devtr_show_devtree_file
elif [ $devtr_parse -eq 1 ]; then
	if [ $devtr_sim -eq 1 ]; then
		devtr_check_smbios_device_description "$smbios_sysver_str" "$board_type" "$sku" "$devtree_file" "$cpu_type"
	else
		devtr_check_smbios_device_description "$smbios_sysver_str"
	fi
	rc=$?
fi 

exit "$rc"
