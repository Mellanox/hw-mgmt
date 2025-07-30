#!/bin/sh
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

# Description: hw-management generate dump script.
#              This script collecting debug information and pack it in /tmp/hw-mgmt-dump.tar.gz

DUMP_FOLDER="/tmp/hw-mgmt-dump"
HW_MGMT_FOLDER="/var/run/hw-management/"
board_type=`cat /sys/devices/virtual/dmi/id/board_name`
REGMAP_FILE="/sys/kernel/debug/regmap/mlxplat/registers"
REGMAP_FILE_ARM64="/sys/kernel/debug/regmap/MLNXBF49:00/registers"
CPLD_IOREG_RANGE=256
dump_process_pid=$$

MODE=$1

dump_cmd () {
	cmd=$1
	output_fname=$2
	timeout=$3
	cmd_name=${cmd%% *}

	if [ -x "$(command -v $cmd_name)" ];
	then
		# ignore shellcheck message SC2016. Arguments should be single-quoted (')
		run_cmd="$cmd 1> $DUMP_FOLDER/$output_fname 2> $DUMP_FOLDER/$output_fname"
		timeout "$timeout" bash -c "$run_cmd"
	fi
}

rm -rf $DUMP_FOLDER
mkdir $DUMP_FOLDER

arch=$(uname -m)
if [ "$arch" = "aarch64" ]; then
	regmap_plat_path=/sys/kernel/debug/regmap/MLNXBF49:00
	REGMAP_FILE=${REGMAP_FILE_ARM64}
	CPLD_IOREG_RANGE=512
else
	regmap_plat_path=/sys/kernel/debug/regmap/mlxplat
	CPLD_IOREG_RANGE=256
fi

dump_cmd "sensors" "sensors" "20"

ls -Rla /sys/ > $DUMP_FOLDER/sysfs_tree
if [ -d $HW_MGMT_FOLDER ]; then
    ls -Rla $HW_MGMT_FOLDER > $DUMP_FOLDER/hw-management_tree
    timeout 140 find -L $HW_MGMT_FOLDER -maxdepth 4 ! -name '*_info' ! -name '*_eeprom' -exec ls -la {} \; -exec cat {} \; > $DUMP_FOLDER/hw-management_val 2> /dev/null
    timeout 80 find $HW_MGMT_FOLDER/eeprom/ -type l -exec ls -la {} \; -exec hexdump -C {} \; > $DUMP_FOLDER/hw-management_fru_dump 2> /dev/null
fi

if [ -z $MODE ] || [ $MODE != "compact" ]; then
	[ -f var/log/syslog ] && cp /var/log/syslog $DUMP_FOLDER
	[ -e /run/log/journal ] && cp -R /run/log/journal $DUMP_FOLDER/journal
	dump_cmd "journalctl" "journalctl" "45"
	dump_cmd "sx_sdk --version" "sx_sdk_ver" "10"
fi

[ -f /var/log/tc_log ] && cp /var/log/tc_* $DUMP_FOLDER/
[ -f /var/log/chipup_i2c_trace_log ] && cp /var/log/chipup_i2c_trace_* $DUMP_FOLDER/
[ -f /var/log/udev_events.log ] && cp -a /var/log/udev* $DUMP_FOLDER/
[ -f /var/log/hw_mgmt_cpldreg.log ] && cp /var/log/hw_mgmt_cpldreg.log $DUMP_FOLDER/
uname -a > $DUMP_FOLDER/sys_version
mkdir $DUMP_FOLDER/bin/
cp /usr/bin/hw?management* $DUMP_FOLDER/bin/
cat /etc/os-release >> $DUMP_FOLDER/sys_version
cat /proc/interrupts > $DUMP_FOLDER/interrupts
case $board_type in
VMOD0014)
	if [ -f "/sys/kernel/debug/regmap/2-0041/registers" ]; then
		cat /sys/kernel/debug/regmap/2-0041/registers > $DUMP_FOLDER/registers
	fi
	if [ -f "/sys/kernel/debug/regmap/2-0041/access" ]; then
		cat /sys/kernel/debug/regmap/2-0041/access > $DUMP_FOLDER/access
	fi
	;;
*)
	if [ -f "${regmap_plat_path}/registers" ]; then
		cat ${regmap_plat_path}/registers > $DUMP_FOLDER/registers
	fi

	if [ -f "${regmap_plat_path}/access" ]; then
		 cat ${regmap_plat_path}/access > $DUMP_FOLDER/access
	fi
	;;
esac

dump_cmd "iorw -b 0x2500 -r -l$CPLD_IOREG_RANGE" "cpld_reg_direct_dump" "5"
dump_cmd "dmesg" "dmesg" "10"
dump_cmd "dmidecode -t1 -t2 -t11 -t15" "dmidecode" "3"
dump_cmd "lsmod" "lsmod" "3"
dump_cmd "lspci -vvv" "lspci" "5"
dump_cmd "top -SHb -n 1 | tail -n +8 | sort -nrk 11" "top" "5"
dump_cmd "iio_info" "iio_info" "5"
dump_cmd "cat $REGMAP_FILE 2>/dev/null" "cpld_dump" "5"
dump_cmd "dpkg -l | grep hw-management" "hw-management_version" "5"

# Kill all the leftout child processes before creating the dump archive
pkill -P $dump_process_pid

tar czf /tmp/hw-mgmt-dump.tar.gz -C $DUMP_FOLDER .
rm -rf $DUMP_FOLDER
