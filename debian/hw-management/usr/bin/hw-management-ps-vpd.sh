#!/bin/bash

##################################################################################
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

#set -x

VERSION="1.1"
VPD_POINTER_ADDR=0xe8
VPD_POINTER_LEN=16
MFR_NAME_ADDR=0x99

VPD_FORMAT_VER=0x01

VPD_OUTPUT_FILE=${VPD_OUTPUT_FILE:-"/dev/stdout"}

#VPD_POINTER=(0x10 0xe9 0xea 0xeb 0xec 0xed 0xee 0xef 0xf0 0xf1 0xf2 0xff 0xff 0xff 0xff 0xff 0x01)
PMBUS_PS_FNAMES=("LEN" "CHSUM_FIELD" "PN_VPD_FIELD" "SN_VPD_FIELD" "REV_VPD_FIELD" "MFG_DATE_FIELD" "CAP_VPD_FIELD" "RSRVD" "RSRVD0" "RSRVD1" "WP_FIELD" "RSRVD2" "RSRVD2" "RSRVD2" "RSRVD2" "RSRVD2" "VPD_FORMAT_VER")
PMBUS_PS_FLEN=(0 2 30 24 8 8 8 8 8 8 2 8 8 8 8 8 0)

crc_arr=("PN_VPD_FIELD" "SN_VPD_FIELD" "REV_VPD_FIELD" "MFG_DATE_FIELD" "CAP_VPD_FIELD" "RSRVD" "RSRVD0" "RSRVD1")

FEED_T=("NA" "AC" "DC")

declare -A FEED_ARR
FEED_ARR=(["NA"]=0 ["AC"]=1 ["DC"]=2)

BUS_ID=${BUS_ID:-10}
I2C_ADDR=${I2C_ADDR:-0x59}

pmbus_bin=pmbus

crc=0
crc16_str=""
function calc_crc16 ( )
{
	#poly=0x8005
	declare -a crc_16_table=(     
	  0x0000 0xC0C1 0xC181 0x0140 0xC301 0x03C0 0x0280 0xC241
	  0xC601 0x06C0 0x0780 0xC741 0x0500 0xC5C1 0xC481 0x0440
	  0xCC01 0x0CC0 0x0D80 0xCD41 0x0F00 0xCFC1 0xCE81 0x0E40
	  0x0A00 0xCAC1 0xCB81 0x0B40 0xC901 0x09C0 0x0880 0xC841
	  0xD801 0x18C0 0x1980 0xD941 0x1B00 0xDBC1 0xDA81 0x1A40
	  0x1E00 0xDEC1 0xDF81 0x1F40 0xDD01 0x1DC0 0x1C80 0xDC41
	  0x1400 0xD4C1 0xD581 0x1540 0xD701 0x17C0 0x1680 0xD641
	  0xD201 0x12C0 0x1380 0xD341 0x1100 0xD1C1 0xD081 0x1040
	  0xF001 0x30C0 0x3180 0xF141 0x3300 0xF3C1 0xF281 0x3240
	  0x3600 0xF6C1 0xF781 0x3740 0xF501 0x35C0 0x3480 0xF441
	  0x3C00 0xFCC1 0xFD81 0x3D40 0xFF01 0x3FC0 0x3E80 0xFE41
	  0xFA01 0x3AC0 0x3B80 0xFB41 0x3900 0xF9C1 0xF881 0x3840
	  0x2800 0xE8C1 0xE981 0x2940 0xEB01 0x2BC0 0x2A80 0xEA41
	  0xEE01 0x2EC0 0x2F80 0xEF41 0x2D00 0xEDC1 0xEC81 0x2C40
	  0xE401 0x24C0 0x2580 0xE541 0x2700 0xE7C1 0xE681 0x2640
	  0x2200 0xE2C1 0xE381 0x2340 0xE101 0x21C0 0x2080 0xE041
	  0xA001 0x60C0 0x6180 0xA141 0x6300 0xA3C1 0xA281 0x6240
	  0x6600 0xA6C1 0xA781 0x6740 0xA501 0x65C0 0x6480 0xA441
	  0x6C00 0xACC1 0xAD81 0x6D40 0xAF01 0x6FC0 0x6E80 0xAE41
	  0xAA01 0x6AC0 0x6B80 0xAB41 0x6900 0xA9C1 0xA881 0x6840
	  0x7800 0xB8C1 0xB981 0x7940 0xBB01 0x7BC0 0x7A80 0xBA41
	  0xBE01 0x7EC0 0x7F80 0xBF41 0x7D00 0xBDC1 0xBC81 0x7C40
	  0xB401 0x74C0 0x7580 0xB541 0x7700 0xB7C1 0xB681 0x7640
	  0x7200 0xB2C1 0xB381 0x7340 0xB101 0x71C0 0x7080 0xB041
	  0x5000 0x90C1 0x9181 0x5140 0x9301 0x53C0 0x5280 0x9241
	  0x9601 0x56C0 0x5780 0x9741 0x5500 0x95C1 0x9481 0x5440
	  0x9C01 0x5CC0 0x5D80 0x9D41 0x5F00 0x9FC1 0x9E81 0x5E40
	  0x5A00 0x9AC1 0x9B81 0x5B40 0x9901 0x59C0 0x5880 0x9841
	  0x8801 0x48C0 0x4980 0x8941 0x4B00 0x8BC1 0x8A81 0x4A40
	  0x4E00 0x8EC1 0x8F81 0x4F40 0x8D01 0x4DC0 0x4C80 0x8C41
	  0x4400 0x84C1 0x8581 0x4540 0x8701 0x47C0 0x4680 0x8641
	  0x8201 0x42C0 0x4380 0x8341 0x4100 0x81C1 0x8081 0x4040
	)

	input=("$@")

	len=${#input[@]}
	for (( j = 0; j<len; j++ ))
	do
		buf=${input[j]}
		crc=$(( crc_16_table[ ( crc ^ buf ) & 0xff ] ^ ( crc >> 8 ) ))
	done

	crc16_str=$(printf "0x%02x 0x%02x\n" $((crc & 0xff)) $((crc >> 8)))
	read -r -a crc16_arr <<< "$crc16_str"
}

function calc_crc8 ( )
{
# CRC8  = x^8 + x^2 + x^1 + x^0 

	declare -a crc8_table=(
		0x00 0x07 0x0E 0x09 0x1C 0x1B 0x12 0x15
		0x38 0x3F 0x36 0x31 0x24 0x23 0x2A 0x2D
		0x70 0x77 0x7E 0x79 0x6C 0x6B 0x62 0x65
		0x48 0x4F 0x46 0x41 0x54 0x53 0x5A 0x5D
		0xE0 0xE7 0xEE 0xE9 0xFC 0xFB 0xF2 0xF5
		0xD8 0xDF 0xD6 0xD1 0xC4 0xC3 0xCA 0xCD
		0x90 0x97 0x9E 0x99 0x8C 0x8B 0x82 0x85
		0xA8 0xAF 0xA6 0xA1 0xB4 0xB3 0xBA 0xBD
		0xC7 0xC0 0xC9 0xCE 0xDB 0xDC 0xD5 0xD2
		0xFF 0xF8 0xF1 0xF6 0xE3 0xE4 0xED 0xEA
		0xB7 0xB0 0xB9 0xBE 0xAB 0xAC 0xA5 0xA2
		0x8F 0x88 0x81 0x86 0x93 0x94 0x9D 0x9A
		0x27 0x20 0x29 0x2E 0x3B 0x3C 0x35 0x32
		0x1F 0x18 0x11 0x16 0x03 0x04 0x0D 0x0A
		0x57 0x50 0x59 0x5E 0x4B 0x4C 0x45 0x42
		0x6F 0x68 0x61 0x66 0x73 0x74 0x7D 0x7A
		0x89 0x8E 0x87 0x80 0x95 0x92 0x9B 0x9C
		0xB1 0xB6 0xBF 0xB8 0xAD 0xAA 0xA3 0xA4
		0xF9 0xFE 0xF7 0xF0 0xE5 0xE2 0xEB 0xEC
		0xC1 0xC6 0xCF 0xC8 0xDD 0xDA 0xD3 0xD4
		0x69 0x6E 0x67 0x60 0x75 0x72 0x7B 0x7C
		0x51 0x56 0x5F 0x58 0x4D 0x4A 0x43 0x44
		0x19 0x1E 0x17 0x10 0x05 0x02 0x0B 0x0C
		0x21 0x26 0x2F 0x28 0x3D 0x3A 0x33 0x34
		0x4E 0x49 0x40 0x47 0x52 0x55 0x5C 0x5B
		0x76 0x71 0x78 0x7F 0x6A 0x6D 0x64 0x63
		0x3E 0x39 0x30 0x37 0x22 0x25 0x2C 0x2B
		0x06 0x01 0x08 0x0F 0x1A 0x1D 0x14 0x13
		0xAE 0xA9 0xA0 0xA7 0xB2 0xB5 0xBC 0xBB
		0x96 0x91 0x98 0x9F 0x8A 0x8D 0x84 0x83
		0xDE 0xD9 0xD0 0xD7 0xC2 0xC5 0xCC 0xCB
		0xE6 0xE1 0xE8 0xEF 0xFA 0xFD 0xF4 0xF3
	)
	input=("$@")

	for (( j = 0; j<${#input[@]}; j++ ))
	do
		buf=${input[j]}
		crc8=$(( crc8_table[ ( crc8 ^ buf ) & 0xff ] ))
	done

	crc8=$(printf "0x%01x\n" "$crc8")
}

function hex_2_ascii ( )
{
	input=("$@")
	for c in "${!input[@]}"
	do
		if [ "${input[$c]}" == 0x00 ] || [ "${input[$c]}" == 0xFF ]; then
			continue
		fi
		echo -ne "\x${input[$c]//0x/}"
	done
}

function ascii_2_hex ( )
{
	input=("$1")
	echo -ne "$1"|od -An -tx1|sed 's/ / 0x/g;s/^ //;s/$//'
}

function pmbus_read ( )
{
	# $1 - command ADDR
	# $2 - read len

	if [ -v mst_dev ]; then
		#switch i2c mux for tests.
		#iorw -b 0x25db -w -l1 -v $((BUS_ID - 1))
		case "${2}" in
			1)
				#echo $2 "pmbus -d ${mst_dev} -s ${I2C_ADDR} -c ${1} -readByte --no_pec" >&2
				ret_val=$("${pmbus_bin}" -d "${mst_dev}" -s "${I2C_ADDR}" -c "${1}" -readByte --no_pec)
				;;
			2)
				#echo $2 "pmbus -d ${mst_dev} -s ${I2C_ADDR} -c ${1} -readWord --no_pec" >&2
				ret_val=$("${pmbus_bin}" -d "${mst_dev}" -s "${I2C_ADDR}" -c "${1}" -readWord_LL --no_pec)
				;;
			*)
				#echo $2 "pmbus -d ${mst_dev} -s ${I2C_ADDR} -c ${1} -readBlock_LL --no_pec" >&2
				ret_val=$("${pmbus_bin}" -d "${mst_dev}" -s "${I2C_ADDR}" -c "${1}" -readBlock_LL --no_pec)
				;;
		esac
	else
		#echo "i2ctransfer -f -y ${BUS_ID} w1@${I2C_ADDR} ${1} r${2}" >&2
		ret_val=$(i2ctransfer -f -y "${BUS_ID}" w1@"${I2C_ADDR}" "${1}" r"${2}")
	fi

	if [ -v "pmbus_delay" ]; then
		sleep "${pmbus_delay}"
	fi
	#echo ${ret_val} >&2
	echo "${ret_val}"
}

function pmbus_write ( )
{
	# $1 - command ADDR
	# $@ - data
	cmd_addr="${1}"
	shift

	if [ -v "mst_dev" ]; then
		#switch i2c mux for tests.
		#iorw -b 0x25db -w -l1 -v $((BUS_ID - 1))
		case "$#" in
			1)
				#echo "pmbus -d ${mst_dev} -s ${I2C_ADDR} -c ${cmd_addr} -writeByte $(echo $@)"  >&2
				ret_val=$("${pmbus_bin}" -d "${mst_dev}" -s "${I2C_ADDR}" -c "${cmd_addr}" -writeByte $(echo "$@"))
				;;
			2)
				#echo "pmbus -d ${mst_dev} -s ${I2C_ADDR} -c ${cmd_addr} -writeWord_LL $(echo $@)" >&2
				ret_val=$("${pmbus_bin}" -d "${mst_dev}" -s "${I2C_ADDR}" -c "${cmd_addr}" -writeWord_LL "$(echo $@)")
				;;
			*)
				wlen=$(printf "%#04x" "$1")
				shift
				#echo "pmbus -d ${mst_dev} -s ${I2C_ADDR} -c ${cmd_addr} -writeBlock_LL ${wdata[@]}" >&2
				ret_val=$("${pmbus_bin}" -d "${mst_dev}" -s "${I2C_ADDR}" -c "${cmd_addr}" -writeBlock_LL "$(echo $@)")
				;;
		esac
	else
		wlen=$(($# + 2))
		#echo "i2ctransfer -f -y ${BUS_ID} w${wlen}@${I2C_ADDR} ${cmd_addr} $@ ${crc8}"
		i2ctransfer -f -y "${BUS_ID}" w"${wlen}"@"${I2C_ADDR}" "${cmd_addr}" "$@" "${crc8}"
	fi

	if [ -v "pmbus_delay" ]; then
		sleep "${pmbus_delay}"
	fi
	#echo ${ret_val} >&2
	#echo ${ret_val}
}

function read_pmbus_ps_vpd_pointer ( )
{
	#VPD POINTER
	len=$(pmbus_read "${VPD_POINTER_ADDR}" 1)
	expected_len=$((${#PMBUS_PS_FNAMES[@]}-1))
	if [  $expected_len -ne $((len)) ]; then
		echo "Bus: ""${BUS_ID}"", Addr: ""${I2C_ADDR}"
		echo "Invalid PMBUS PS VPD Pointer length,  len: " "$len" "len expected: " "$expected_len"; exit 1;
	fi

	len=$((len+1))

	VPD_POINTER_STR=$(pmbus_read "${VPD_POINTER_ADDR}" "${len}")

	read -r -a VPD_POINTER <<< "$VPD_POINTER_STR"

	if [ $((${#VPD_POINTER[@]})) -ne $((len)) ]; then
		echo "Invalid PMBUS PS VPD Pointer  Data: " "$VPD_POINTER_STR" "Data count: " "${#VPD_POINTER[@]}"; exit 1;
fi
}

function read_pmbus_ps_vpd ( )
{
	read_pmbus_ps_vpd_pointer

	#MFR NAME
	#read block len
	len=$(pmbus_read "${MFR_NAME_ADDR}" 1)
	len=$((len+1))
	MFR_NAME_STR=$(pmbus_read "${MFR_NAME_ADDR}" "${len}")

	read -r -a MFR_NAME <<< "$MFR_NAME_STR"

	echo -ne "MFR_NAME: " > "$VPD_OUTPUT_FILE"

	hex_2_ascii "${MFR_NAME[@]:1}" >> "$VPD_OUTPUT_FILE"

	echo -ne '\n' >> "$VPD_OUTPUT_FILE"

	calc_crc16 "${VPD_POINTER[@]:1}"

	i=0
	for i in "${!VPD_POINTER[@]}"
	do
	#skip
		if [ "${PMBUS_PS_FNAMES[$i]}" == "RSRVD2" ] || \
		[ "${PMBUS_PS_FNAMES[$i]}" == "LEN" ] || \
		[ "${PMBUS_PS_FNAMES[$i]}" == "VPD_FORMAT_VER" ] || \
		[ "${PMBUS_PS_FNAMES[$i]}" == "WP_FIELD" ]; then
			continue
		fi

		#check address for allowed range
		if [ $((${VPD_POINTER[$i]})) -lt $((0xd0)) ] || 
		   [ $((${VPD_POINTER[$i]})) -gt $((0xff)) ]; then
			echo "Error. command addr: ${VPD_POINTER[$i]} out of allowed range 0xd0 - 0xff. Check VPD Pointer set correctly."
			echo "VPD_PONTER:" "${VPD_POINTER[*]}"
			exit 1
		fi

		if [ "${PMBUS_PS_FNAMES[$i]}" == "CHSUM_FIELD" ] || \
			[ "${PMBUS_PS_FNAMES[$i]}" == "WP_FIELD" ]; then
			len=2
		else
	#read block len
			len=$(pmbus_read "${VPD_POINTER[$i]}" 1)
			len=$((len+1))
		fi

	#read in hex
		 CUR_FIELD=$(pmbus_read "${VPD_POINTER[$i]}" "${len}")

	#calc crc16
		if [[ " ${crc_arr[*]} " == *"${PMBUS_PS_FNAMES[$i]}"* ]]; then
			read -r -a arr_for_crc <<< "${CUR_FIELD}"
			calc_crc16 "${arr_for_crc[@]:1}"
		fi

	#START PRINT
	#skip
		if [ "${PMBUS_PS_FNAMES[$i]}" == "RSRVD2" ] || \
		[ "${PMBUS_PS_FNAMES[$i]}" == "LEN" ] || \
		[ "${PMBUS_PS_FNAMES[$i]}" == "VPD_FORMAT_VER" ]; then
			continue
		fi
	#skip print in human kind representation
		if [ "${PMBUS_PS_FNAMES[$i]}" == "RSRVD0" ] || \
		[ "${PMBUS_PS_FNAMES[$i]}" == "RSRVD1" ] || \
		[ "${PMBUS_PS_FNAMES[$i]}" == "RSRVD" ]; then
			continue
		fi

	#print in hex
		if [ "${PMBUS_PS_FNAMES[$i]}" == "CHSUM_FIELD" ]; then
			{
				echo -ne "${PMBUS_PS_FNAMES[$i]}: "
				echo "${CUR_FIELD}"
				read_crc16_str="${CUR_FIELD}"
			} >> "$VPD_OUTPUT_FILE"
			continue
		fi

	#special parcing print
		if [ "${PMBUS_PS_FNAMES[$i]}" == "CAP_VPD_FIELD" ]; then
			read -a cap_field_arr <<< "${CUR_FIELD}"
			CAP=$((cap_field_arr[2]*256+cap_field_arr[1]))
			MIN_RPM=$((cap_field_arr[4]*256+cap_field_arr[3]))
			MAX_RPM=$((cap_field_arr[6]*256+cap_field_arr[5]))
			FEED=${cap_field_arr[7]}
			{
				echo -ne "CAPACITY: "
				echo $CAP

				echo -ne "MIN_RPM: "
				echo $MIN_RPM

				echo -ne "MAX_RPM: "
				echo $MAX_RPM

				echo -ne "FEED: "
				echo "${FEED_T[$FEED]}"
			} >> "$VPD_OUTPUT_FILE"
			continue
		fi
	#print as string
		read -a ascii_arr <<< "${CUR_FIELD}"
		{
			echo -ne "${PMBUS_PS_FNAMES[$i]}: "
			hex_2_ascii "${ascii_arr[@]:1}"
			echo -ne '\n'
		}  >> "$VPD_OUTPUT_FILE"

	done
}

while [ $# -gt 0 ]; do
	if [[ $1 == *"--"* ]]; then
		param="${1/--/}"
		case $param in
			help)
				command=help
				;;
			version)
				command=version
				;;
			dump)
				command=dump
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
This is PMBUS PS VPD tool. Version ${VERSION}" '

Usage:
	hw-management-ps-vpd.sh --BUS_ID <bus_num> --I2C_ADDR <addr value> <command> <field> <value> .. <field> <value>
Commands:
	--dump: dump vpd info to screen.

	--pmbus_delay: there can be added delay between transactions.
		example: hw-management-ps-vpd.sh --pmbus_delay 0.1

	--BUS_ID: PSU i2c bus number. allowed value decimal. default value 10.
	--I2C_ADDR: PSU i2c address. allowed value hex. default value 0x59.

	--mst_dev: If this option set VPD tool working over mst device using MFT.
			   By default(if this option NOT set) and VPD tool working over
				i2c-tools(ver 4.1-1+) using i2ctransfer.

		example: hw-management-ps-vpd.sh --mst_dev /dev/mst/dev-i2c-1

	--pmbus_bin: path to pmbus binary. Used only with --mst_dev.

	--help: this help.
	--version: show version.

Usage example: hw-management-ps-vpd.sh --BUS_ID 4 --I2C_ADDR 0x59 --dump

Author: Mykola Kostenok <c_mykolak@mellanox.com>'
		exit 0
		;;
	version)
		echo "This is PMBUS PS VPD tool. Version ${VERSION}"
		exit 0
		;;
	dump)
		read_pmbus_ps_vpd
		echo CALC_CRC: "${crc16_arr[*]}" >> "$VPD_OUTPUT_FILE"
		if [ "${crc16_str}" != "${read_crc16_str}" ];
		then
			exit 1
		fi
		exit 0
		;;
	*)
		echo "No command specified, use hw-management-ps-vpd.sh --help to print usage example."
		;;
esac

