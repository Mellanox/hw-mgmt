#!/bin/bash
################################################################################
# Copyright (c) 2024-2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Inherit system configuration.
source hw-management-helpers.sh
source hw-management-devtree.sh

device_connect_retry=2
device_connect_delay=0.2

so_base_connect_table=( \
	mp2855 0x66 17 \
	mp2855 0x68 17 \
	mp2855 0x6c 17 \
	lm5066 0x16 18 \
	pmbus 0x10 18 \
	pmbus 0x11 18 \
	pmbus 0x12 18 \
	pmbus 0x13 18 \
	24c512 0x51 18 \
	mp2891 0x66 19 \
	mp2891 0x68 19 \
	mp2891 0x6c 19 \
	adt75 0x49 20 \
	adt75 0x4a 21 \
	adt75 0x4b 21 \
	mp2891 0x66 25 \
	mp2891 0x68 25 \
	mp2891 0x6c 25 )
	
so_chassis_connect_table=( \
	24c02 0x50 29 \
	24c02 0x50 30 \
	24c02 0x50 31 \
	24c02 0x50 32 )

ariel_base_connect_table=( \
	mp2855 0x66 17 \
	mp2855 0x68 17 \
	mp2855 0x6a 17 \
	lm5066 0x16 18 \
	pmbus 0x10 18 \
	pmbus 0x11 18 \
	pmbus 0x12 18 \
	pmbus 0x13 18 \
	24c512 0x51 18 \
	mp2891 0x66 19 \
	mp2891 0x68 19 \
	mp2891 0x6c 19 \
	adt75 0x49 20 \
	adt75 0x4a 21 \
	adt75 0x4b 21 \
	mp2891 0x66 25 \
	mp2891 0x68 25 \
	mp2891 0x6c 25 )
	
ariel_chassis_connect_table=( \
	24c02 0x50 29 \
	24c02 0x50 32 )

nso_base_connect_table=( \
	mp2855 0x66 17 \
	mp2855 0x68 17 \
	mp2855 0x6a 17 \
	lm5066 0x16 18 \
	pmbus 0x10 18 \
	pmbus 0x11 18 \
	pmbus 0x12 18 \
	pmbus 0x13 18 \
	24c512 0x51 18 \
	mp2891 0x66 19 \
	mp2891 0x68 19 \
	mp2891 0x6c 19 \
	adt75 0x49 20 \
	adt75 0x4a 21 \
	adt75 0x4b 21 \
	mp2891 0x66 25 \
	mp2891 0x68 25 \
	mp2891 0x6c 25 )

gb300_nso_base_connect_table=( \
	ads1015 0x49 6 \
	mp29816 0x66 17 \
	mp29816 0x68 17 \
	mp29816 0x6c 17 \
	lm5066i 0x16 18 \
	tmp451 0x4c 18 \
	24c512 0x51 18 \
	raa228004  0x60 18 \
	mp29816 0x66 19 \
	mp29816 0x68 19 \
	mp29816 0x6c 19 \
	mp2891 0x66 25 \
	mp2891 0x68 25 \
	mp2891 0x6c 25 \
	24c512 0x51 36 )

rosalind_surrogate_base_connect_table=( \
	mp29816 0x66 17 \
	mp29816 0x68 17 \
	mp29816 0x6c 17 \
	lm5066i 0x12 18 \
	24c512 0x51 18 \
	raa228004 0x60 18 \
	mp29816 0x66 19 \
	mp29816 0x68 19 \
	mp29816 0x6c 19 \
	24c512 0x51 36 \
	24c512 0x51 37 \
	24c512 0x51 38 \
	24c512 0x51 39 )

rosalind_nso_base_connect_table=( \
	mp29816 0x66 17 \
	mp29816 0x68 17 \
	mp29816 0x6c 17 \
	mp29816 0x6e 17 \
	lm5066i 0x12 18 \
	24c512 0x51 18 \
	raa228004 0x60 18 \
	mp29816 0x66 19 \
	mp29816 0x68 19 \
	mp29816 0x6c 19 \
	mp29816 0x6e 19 \
	mp29816 0x66 25 \
	mp29816 0x66 25 \
	mp29816 0x68 25 \
	mp29816 0x6c 25 \
	mp29816 0x6e 34 \
	mp29816 0x68 34 \
	mp29816 0x6c 34 \
	mp29816 0x6e 34 \
	24c512 0x51 36 \
	24c512 0x51 37 \
	24c512 0x51 38 \
	24c512 0x51 39 )

spc6_ast2600_base_connect_table=( \
	lm5066i 0x12 22 \
	lm5066i 0x12 23 \
	raa228004 0x60 22 \
	raa228004 0x60 23 \
	mp29816 0x66 25 \
	mp29816 0x66 25 \
	mp29816 0x68 25 \
	mp29816 0x6c 25 \
	mp29816 0x6e 26 \
	mp29816 0x68 26 \
	mp29816 0x6c 26 \
	mp29816 0x6e 26 \
	24c512 0x51 8 \
	24c512 0x51 4 \
	24c512 0x51 27 )

spc6_ast2700_base_connect_table=( \
	lm5066i 0x12 22 \
	lm5066i 0x12 23 \
	raa228004 0x60 22 \
	raa228004 0x60 23 \
	mp29816 0x66 25 \
	mp29816 0x66 25 \
	mp29816 0x68 25 \
	mp29816 0x6c 25 \
	mp29816 0x6e 26 \
	mp29816 0x68 26 \
	mp29816 0x6c 26 \
	mp29816 0x6e 26 \
	24c512 0x51 13 \
	24c512 0x51 5 \
	24c512 0x51 27 )

gb200hd_nso_base_connect_table=( \
	mp2855 0x66 17 \
	mp2855 0x68 17 \
	mp2855 0x6a 17 \
	lm5066i 0x16 18 \
	tmp451 0x4c 18 \
	24c512 0x51 18 \
	raa228004  0x60 18 \
	mp2891 0x66 19 \
	mp2891 0x68 19 \
	mp2891 0x6c 19 \
	adt75 0x49 20 \
	adt75 0x4a 21 \
	adt75 0x4b 21 \
	mp2891 0x66 25 \
	mp2891 0x68 25 \
	mp2891 0x6c 25 \
	mp2891 0x66 34 \
	mp2891 0x68 34 \
	mp2891 0x6c 34 \
	24c512 0x51 36 )

nso_chassis_connect_table=( \
	24c02 0x50 29 \
	24c02 0x50 32 \
	24c02 0x50 33 \
	24c02 0x50 34 )

gb300_nso_cartridge_eeprom_connect_table=( 24c02 0x50 29 cable_cartridge1_eeprom \
	24c02 0x50 30 cable_cartridge2_eeprom \
	24c02 0x50 31 cable_cartridge3_eeprom \
	24c02 0x50 32 cable_cartridge4_eeprom)

rosalind_nso_cartridge_eeprom_connect_table=( 24c02 0x50 29 cable_cartridge1_eeprom \
	24c02 0x50 30 cable_cartridge2_eeprom \
	24c02 0x50 31 cable_cartridge3_eeprom \
	24c02 0x50 32 cable_cartridge4_eeprom)

log_err()
{
    logger -t bmc-boot-complete -p daemon.err "$@"
}

log_info()
{
    logger -t bmc-boot-complete -p daemon.info "$@"
}

connect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-"$3"/new_device ]; then
		addr=$(echo "$2" | tail -c +3)
		bus=$3
		if [ ! -d /sys/bus/i2c/devices/$bus-00"$addr" ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" "$2" > /sys/bus/i2c/devices/i2c-$bus/new_device
			sleep ${device_connect_delay}
			if [ ! -L /sys/bus/i2c/devices/$bus-00"$addr"/driver ] &&
			   [ ! -L /sys/bus/i2c/devices/$bus-000"$addr"/driver ]; then
				return 1
			fi
		fi
	fi

	return 0
}

disconnect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-"$2"/delete_device ]; then
		addr=$(echo "$1" | tail -c +3)
		bus=$2
		if [ -d /sys/bus/i2c/devices/$bus-00"$addr" ] ||
		   [ -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" > /sys/bus/i2c/devices/i2c-$bus/delete_device
			return $?
		fi
	fi

	return 0
}

connect_platform()
{
	# Check if it's new or old format of connect table
	if [ -e "$devtree_file" ]; then
		unset connect_table
		declare -a connect_table=($(<"$devtree_file"))
		# New connect table contains also device link name, e.g., fan_amb
		dev_step=4
	else
		dev_step=3
	fi

	for ((i=0; i<${#connect_table[@]}; i+=$dev_step)); do
		for ((j=0; j<${device_connect_retry}; j++)); do
			connect_device "${connect_table[i]}" "${connect_table[i+1]}" \
					"${connect_table[i+2]}"
			if [ $? -eq 0 ]; then
				break;
			fi
			disconnect_device "${connect_table[i+1]}" "${connect_table[i+2]}"
		done
	done
}

disconnect_platform()
{
	# Check if it's new or old format of connect table
	if [ -e "$devtree_file" ]; then
		dev_step=4
	else
		dev_step=3
	fi
	for ((i=0; i<${#connect_table[@]}; i+=$dev_step)); do
		disconnect_device "${connect_table[i+1]}" "${connect_table[i+2]}"
	done
}

connect_chassis()
(
	dev_step=3
	for ((i=0; i<${#connect_chassis_table[@]}; i+=$dev_step)); do
		for ((j=0; j<${device_connect_retry}; j++)); do
			connect_device "${connect_chassis_table[i]}" "${connect_chassis_table[i+1]}" \
					"${connect_chassis_table[i+2]}"
			if [ $? -eq 0 ]; then
				break;
			fi
			disconnect_device "${connect_chassis_table[i+1]}" "${connect_chassis_table[i+2]}"
		done
	done
)

disconnect_chassis()
{
	dev_step=3
	for ((i=0; i<${#connect_chassis_table[@]}; i+=$dev_step)); do
		disconnect_device "${connect_chassis_table[i+1]}" "${connect_chassis_table[i+2]}"
	done
}

so_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${so_base_connect_table[@]})
	fi
	connect_chassis_table+=(${so_chassis_connect_table[@]})
}

ariel_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${ariel_base_connect_table[@]})
	fi
	connect_chassis_table+=(${ariel_chassis_connect_table[@]})
}

nso_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${nso_base_connect_table[@]})
	fi
	connect_chassis_table+=(${nso_chassis_connect_table[@]})
}

gb300_nso_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${gb300_nso_base_connect_table[@]})
	fi
	echo -n "${gb300_nso_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
}

rosalind_nso_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${rosalind_surrogate_base_connect_table[@]})
	fi
	echo -n "${rosalind_nso_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
}

rosalind_surrogate_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${rosalind_nso_base_connect_table[@]})
	fi
	echo -n "${rosalind_nso_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
}

spc6_ast2600_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${spc6_ast2600_base_connect_table[@]})
	fi
}

spc6_ast2700_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${spc6_ast2700_base_connect_table[@]})
	fi
}

gb200hd_nso_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${gb200hd_nso_base_connect_table[@]})
	fi
}

check_system()
{
	# Check ODM
	board_type=`cat /sys/firmware/devicetree/base/model | awk '{print $2}'`
	hid=$(cat $config_path/hid)

	# Apply relevant configuration.
	case $board_type in
	Juliet)
		case "$hid" in
		HI166)	# Juliet SO.
			so_specific
			;;
		HI169)	# Juliet Ariel.
			ariel_specific
			;;
		HI167|HI170)	# Juliet NSO.
			nso_specific
			;;
		HI176)	# GB300 NSO.
			gb300_nso_specific
			;;
		HI177)	# GB200 HD
			gb200hd_nso_specific
			# No cartridges.
			;;
		*)	# According Juliet SO.
			so_specific
			;;
		esac
		;;
	Rosalind)
		case "$hid" in
		HI180)	# Rosalind NSO.
			if [ "$cpu_type" == "$ARMv8_CPU" ]; then
				# rosalind (Aspeed 2700)
				rosalind_nso_specific
			else
				#rosalind surrogate (Aspeed 2600)
				rosalind_surrogate_specific
			fi
			;;
		*)	# According Juliet SO.
			so_specific
			;;
		esac
		;;
	Spc6)
		case "$hid" in
		HI181|HI182)
			rosalind_surrogate_specific
			# No cartridges.
			;;
		HI191|HI192|HI193)
			#Salamanrda / Chameleon V3000 based management board:
			spc6_ast2600_specific
			# No cartridges.
			;;
		HI189|HI190)
			#Salamanrda / Chameleon V3000 based management board:
			spc6_ast2700_specific
			# No cartridges.
			;;
		*)      # According Juliet SO.
			so_specific
			;;
		esac
		;;
	*)
		;;
	esac
}

do_start()
{
	touch /var/run/hw-management/config/pn
	check_cpu_type
	devtr_check_smbios_device_description
	check_system
	udevadm trigger --action=add
	udevadm settle
	# connect_platform
	# connect_chassis

	log_info "Init completed."
}

do_stop()
{
	# disconnect_chassis
	# disconnect_platform
	log_info "do_stop."
}

ACTION=$1
case $ACTION in
	start)
		do_start
	;;
	stop)
		do_stop
	;;
	restart|force-reload)
		do_stop
		sleep 3
		do_start
	;;
	reset-cause)
		for f in $system_path/reset_*;
			do v=`cat $f`; attr=$(basename $f); if [ $v -eq 1 ]; then echo $attr; fi;
		done
	;;
	*)
		echo "$__usage"
		exit 1
	;;
esac
