#!/bin/bash
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
source hw-management-helpers.sh

# SANITY 4D4C4E58 = MLNX.
MLNX_CUSTOM_CHECKER=4D4C4E58
f_length_layout0=(4 24 20 4 1 3)
f_names_layout0=("SANITY" "SN_VPD_FIELD" "PN_VPD_FIELD" "REV_VPD_FIELD" "RSRVD" "MFG_DATE_FIELD")

f_length_layout1=(4 24 1 1 20 4 3 11 5 4)
f_names_layout1=("SANITY" "SN_VPD_FIELD" "RSRVD" "EFT_REV" "PN_VPD_FIELD" "REV_VPD_FIELD" "MFG_DATE_FIELD" "MFR_NAME" "FEED" "CAPACITY")

f_length_layout2=(24 20 4)
f_names_layout2=("SN_VPD_FIELD" "PN_VPD_FIELD" "REV_VPD_FIELD")

f_length_layout3=(2 2 1 3)
f_names_layout3=("MINOR_INI_VERSION" "HW_REVISION" "CARD_TYPE" "RSRVD")

base_offsets=(137 160 0 0)

dependecies=("awk" "xxd")

function cleanup {
	rm  -f "${tmp_eeprom_path}"
}

trap cleanup EXIT

function find_base_offset ( )
{
	for i in "${!base_offsets[@]}"
	do
		cur_val=$(xxd -u -p -l 4 -s "${base_offsets[i]}" "$eeprom_path")

		# Check sanity.
		if [ "${cur_val}" == "$MLNX_CUSTOM_CHECKER" ]; then
			# Sanity ok.
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
	for i in "${!dependecies[@]}"
	do
		if [ ! -x $(command -v "${dependecies[$i]}") ]; then
			echo Dependecies check fail. Please install "${dependecies[$i]}".
			exit 1
		fi
	done

	if [ ! -v "eeprom_path" ]; then
		echo Mandatory argument eeprom missed.
		exit 1
	fi

	tmp_eeprom_path=$(mktemp)
	sync
	cp "$eeprom_path" "${tmp_eeprom_path}"
	eeprom_path="${tmp_eeprom_path}"

	if [ ! -v "layout" ]; then
		find_base_offset
	else
		if [[ "$layout" < "${#base_offsets[@]}" ]]; then
			base_offset="${base_offsets[layout]}"
			l_arr=f_length_layout$layout[@]
			n_arr=f_names_layout$layout[@]
			f_length=( "${!l_arr}" )
			f_names=( "${!n_arr}" )
		else
			echo layout out of range: 0 - $(( ${#base_offsets[@]}-1 ))
			exit 1
		fi
	fi

	prev_len=0
	cur_offset="${base_offset}"

	for i in "${!f_names[@]}"
	do
		cur_offset=$((cur_offset+prev_len))
		prev_len="${f_length[i]}"
		cur_val=$(xxd -u -p -l "${f_length[i]}" -s "$cur_offset" "$eeprom_path")
		# Check sanity.
		if [ "${f_names[$i]}" == "SANITY" ]; then
				if [ "${cur_val}" == "$MLNX_CUSTOM_CHECKER" ]; then
					# Sanity ok.
					continue
				else
					echo Nvidia sanity checker fail
					exit 1;
				fi
		fi

		if [ "${f_names[$i]}" == "RSRVD" ]; then
			# Skip reserved.
			continue
		fi

		echo -ne "${f_names[$i]}: "
		if [ "${f_names[$i]}" == "SN_VPD_FIELD" ] || \
			[ "${f_names[$i]}" == "PN_VPD_FIELD" ] || \
			[ "${f_names[$i]}" == "REV_VPD_FIELD" ] || \
			[ "${f_names[$i]}" == "MFR_NAME" ] || \
			[ "${f_names[$i]}" == "FEED" ] || \
			[ "${f_names[$i]}" == "EFT_REV" ]; then
			# Print as ASCII.
			echo -ne "${cur_val}" | xxd -r -p | tr -d '\0'
		elif [ "${f_names[$i]}" == "CAPACITY" ] || \
			[ "${f_names[$i]}" == "CARD_TYPE" ]; then
			# Print in DEC.
			echo -ne "$((0x$cur_val))"
		elif [ "${f_names[$i]}" == "HW_REVISION" ] || \
			[ "${f_names[$i]}" == "MINOR_INI_VERSION" ]; then
			# Print in DEC with Endian coversion.
			cur_val=`echo ${cur_val:2:2}${cur_val:0:2}`
			echo -ne "$((0x$cur_val))"
		else
			# Print as HEX.
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
MLNX eeprom parsing tool.

Usage:
	hw-management-parse-eeprom.sh --conv --eeprom_path <path to eeprom sysfs entry>
Commands:
	--conv: parse eeprom.

	--eeprom_path: MANDATORY argument, path to FRU EEPROM.
		example: /var/run/hw-management/eeprom/psu1_info
				 /var/run/hw-management/eeprom/psu2_info

	--layout: If not set, tool will try to find base offset and sanity.
		Possible range: 0 - $(( ${#base_offsets[@]}-1 ))

	--help: this help.

Usage example: 
	hw-management-parse-eeprom.sh --conv --eeprom_path /var/run/hw-management/eeprom/psu1_info
	hw-management-parse-eeprom.sh --layout 2 --conv --eeprom_path /var/run/hw-management/lc1/eeprom/vpd

"
		exit 0
		;;
	conv)
		retry_helper do_conv 0.5 10 "vpd parsing failed"
		exit 0
		;;
	*)
		echo "No command specified, use --help to print usage example."
		;;
esac


