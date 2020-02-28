#!/bin/bash
########################################################################
# Copyright (c) 2020 Mellanox Technologies. All rights reserved.
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

set -e

MLNX_CUSTOM_CHECKER=MLNX
f_length_layout0=(4 24 20 4 1 3)
f_names_layout0=("SANITY" "SN_VPD_FIELD" "PN_VPD_FIELD" "REV_VPD_FIELD" "RSRVD" "MFG_DATE_FIELD")

f_length_layout1=(4 24 1 1 20 4 3 11 5 4)
f_names_layout1=("SANITY" "SN_VPD_FIELD" "RSRVD" "EFT_REV" "PN_VPD_FIELD" "REV_VPD_FIELD" "MFG_DATE_FIELD" "MFR_NAME" "FEED" "CAPACITY")

base_offsets=(137 160)

dependecies=("awk" "xxd")

function cleanup {
	rm  -f "${tmp_psu_eeprom}"
}

trap cleanup EXIT

function find_base_offset ( )
{
	for i in "${!base_offsets[@]}"
	do
		cur_val=$(xxd -u -p -l 4 -s "${base_offsets[i]}" "$psu_eeprom")

		#check sanity
		sanity_ascii=$(echo -ne "${cur_val}" | xxd -r -p)
		if [ "${sanity_ascii}" == "$MLNX_CUSTOM_CHECKER" ]; then
			#echo sanity ok
			base_offset="${base_offsets[i]}"
			l_arr=f_length_layout$i[@]
			n_arr=f_names_layout$i[@]
			f_length=( "${!l_arr}" )
			f_names=( "${!n_arr}" )
			break;
		fi
	done

	if [ ! -v "base_offset" ]; then
		echo No base offset.
		exit 1
	fi

}

function do_conv ( )
{
	if [ ! -v "psu_eeprom" ]; then
		echo Mandatory argument psu_eeprom missed.
		exit 1
	fi

	for i in "${!dependecies[@]}"
	do
		if [ ! -x "$(command -v ${dependecies[$i]})" ]; then
			echo Dependecies check fail. Please install "${dependecies[$i]}".
			exit 1
		fi
	done

	eeprom_fname=$(basename "$psu_eeprom")
	tmp_psu_eeprom=/tmp/"$eeprom_fname".tmp

	cp "$psu_eeprom" "${tmp_psu_eeprom}"
	psu_eeprom="${tmp_psu_eeprom}"

	find_base_offset

	prev_len=0
	cur_offset="${base_offset}"
	#echo "${base_offset}"
	for i in "${!f_names[@]}"
	do
		cur_offset=$((cur_offset+prev_len))
		prev_len="${f_length[i]}"
		cur_val=$(xxd -u -p -l "${f_length[i]}" -s "$cur_offset" "$psu_eeprom")

		#check sanity
		if [ "${f_names[$i]}" == "SANITY" ]; then
				sanity_ascii=$(echo -ne "${cur_val}" | xxd -r -p)
				if [ "${sanity_ascii}" == "$MLNX_CUSTOM_CHECKER" ]; then
					#echo sanity ok
					continue
				else
					echo Mellanox sanity checker fail
					exit 1;
				fi
		fi

		if [ "${f_names[$i]}" == "RSRVD" ]; then
			#echo skip reserved.
			continue
		fi

		echo -ne "${f_names[$i]}: "
		if [ "${f_names[$i]}" == "SN_VPD_FIELD" ] || \
			[ "${f_names[$i]}" == "PN_VPD_FIELD" ] || \
			[ "${f_names[$i]}" == "REV_VPD_FIELD" ] || \
			[ "${f_names[$i]}" == "MFR_NAME" ] || \
			[ "${f_names[$i]}" == "FEED" ] || \
			[ "${f_names[$i]}" == "EFT_REV" ]; then
				#print as ASCII
				echo -ne "${cur_val}" | xxd -r -p
		elif [ "${f_names[$i]}" == "CAPACITY" ]; then
			#print in DEC
			echo -ne "$((0x$cur_val))"
		else
			#print as HEX
			echo -ne "${cur_val}"
		fi
		echo -ne '\n'

	done
}

while [ $# -gt 0 ]; do

	if [[ $1 == *"--"* ]]; then
		param="${1/--/}"
		case $param in
			help)
				command=help
				;;
			conv)
				command=conv
				;;
			*)
				declare "$param=$2"
				#echo $1 $2 #// Optional to see the parameter:value result
				;;
			esac
	fi

	shift
done

case $command in
	help)
		echo "
Tool for MLNX psu eeprom reading." '

Usage:
	hw-management-read-ps-eeprom.sh --conv --psu_eeprom <path to ps eeprom sysfs entry>
Commands:
	--conv: read psu eeprom.

	--psu_eeprom: MANDATORY argument, path to PSU FRU EEPROM.
		example: /var/run/hw-management/eeprom/psu1_info
				 /var/run/hw-management/eeprom/psu2_info

	--help: this help.

Usage example: 
	hw-management-read-ps-eeprom.sh --conv --psu_eeprom /var/run/hw-management/eeprom/psu1_info

'
		exit 0
		;;
	conv)
		do_conv
		exit 0
		;;
	*)
		echo "No command specified, use --help to print usage example."
		;;
esac


