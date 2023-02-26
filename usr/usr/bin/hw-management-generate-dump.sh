#!/bin/sh
##################################################################################
# Copyright (c) 2020 - 2021, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

MODE=$1

dump_cmd () {
	cmd=$1
	output_fname=$2
	timeout=$3
	cmd_name=${cmd%% *}

	if [ -x "$(command -v $cmd_name)" ];
	then
		# ignore shellcheck message SC2016. Arguments should be single-quoted (')
		run_cmd="$cmd & > $DUMP_FOLDER/$output_fname"
		timeout "$timeout" bash -c "$run_cmd"
	fi
}

rm -rf $DUMP_FOLDER
mkdir $DUMP_FOLDER

ls -Rla /sys/ > $DUMP_FOLDER/sysfs_tree
if [ -d $HW_MGMT_FOLDER ]; then
    ls -Rla $HW_MGMT_FOLDER > $DUMP_FOLDER/hw-management_tree
    run_cmd="find -L $HW_MGMT_FOLDER -maxdepth 4 -exec ls -la {} \; -exec cat {} \; > $DUMP_FOLDER/hw-management_val 2> /dev/null"
    timeout 60 bash -c "$run_cmd" &> /dev/null
    run_cmd="find $HW_MGMT_FOLDER/eeprom/  -name *info  -exec ls -la {} \; -exec hexdump -C {} \; > $DUMP_FOLDER/hw-management_fru_dump 2> /dev/null"
    timeout 60 bash -c "$run_cmd" &> /dev/null
fi

if [ -z $MODE ] || [ $MODE != "compact" ]; then
	[ -f var/log/syslog ] && cp /var/log/syslog $DUMP_FOLDER
	[ -e /run/log/journal ] && cp -R /run/log/journal $DUMP_FOLDER/journal
	dump_cmd "journalctl" "journalctl" "45"
	dump_cmd "sx_sdk --version" "sx_sdk_ver" "10"
fi

uname -a > $DUMP_FOLDER/sys_version
mkdir $DUMP_FOLDER/bin/
cp /usr/bin/hw-management* $DUMP_FOLDER/bin/
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
	if [ -f "/sys/kernel/debug/regmap/mlxplat/registers" ]; then
		cat /sys/kernel/debug/regmap/mlxplat/registers > $DUMP_FOLDER/registers
	fi

	if [ -f "/sys/kernel/debug/regmap/mlxplat/access" ]; then
		 cat /sys/kernel/debug/regmap/mlxplat/access > $DUMP_FOLDER/access
	fi
	;;
esac

dump_cmd "dmesg" "dmesg" "10"
dump_cmd "dmidecode -t1 -t2 -t11 -t15" "dmidecode" "3"
dump_cmd "lsmod" "lsmod" "3"
dump_cmd "lspci -vvv" "lspci" "5"
dump_cmd "top -SHb -n 1 | tail -n +8 | sort -nrk 11" "top" "5"
dump_cmd "sensors" "sensors" "20"
dump_cmd "iio_info" "iio_info" "5"
dump_cmd "cat $REGMAP_FILE 2>/dev/null" "cpld_dump" "5"

if [ -x "$(command -v i2cdetect)" ];   then
    run_cmd="for i in {0..17} ; do echo i2c bus \$i; i2cdetect -y \$i 2>/dev/null; done > $DUMP_FOLDER/i2c_scan"
    timeout 60 bash -c "$run_cmd"
fi

tar czf /tmp/hw-mgmt-dump.tar.gz -C $DUMP_FOLDER .
rm -rf $DUMP_FOLDER
