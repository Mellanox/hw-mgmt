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

source hw-management-helpers.sh
source hw-management-devtree.sh
system_ver_file=/sys/devices/virtual/dmi/id/product_version
board_type=$(<"$board_type_file")
cpu_type=$(<"$config_path"/cpu_type)

usage()                                                                                              
{                                                                                                    
        printf "Usage:\\t %s <-d> | <-s> | <-p> | <-h>\n" `basename $0` 
	printf "%s\\t display device tree\n" "-d"
	printf "%s\\t show system version SMBIOS string\n" "-s"
	printf "%s\\t parse SMBIOS sysver string and create devtree\n" "-p"
	printf "%s\\t this help\n" "-h"
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

# Script can be used as standalone for debug
param_num=$#
rc=0
if [ "$param_num" -ge 1 ]; then 
	OPTIND=1
	optspec="dsph"
	while getopts "$optspec" optchar; do
		case "${optchar}" in
			d)
				devtr_show_devtree_file
				;;
			s)
				smbios_sysver_str=$(<$system_ver_file)
				echo "Devtree SMBios string: ${smbios_sysver_str}"
				;;
			h)
				usage
				;;
			p)
				devtr_check_smbios_device_description
				rc=$?
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

exit "$rc"
