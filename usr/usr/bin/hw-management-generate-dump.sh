#!/bin/sh
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

# Description: hw-management generate dump script.
#              This script collecting debug information and pack it in /tmp/hw-mgmt-dump.tar.gz 

DUMP_FOLDER="/tmp/hw-mgmt-dump"

dump_cmd () {
cmd=$1
output_fname=$2
cmd_name=${cmd%% *}

if [ -x "$(command -v $cmd_name)" ]; 
then
	eval $cmd > $DUMP_FOLDER/$output_fname
fi
}

rm -rf $DUMP_FOLDER
mkdir $DUMP_FOLDER

ls -Rla /sys/ > $DUMP_FOLDER/sysfs_tree
ls -Rla /var/run/hw-management/ > $DUMP_FOLDER/hw-management_tree
find -L /var/run/hw-management/  -type f,l -exec ls -la {} \; -exec cat {} \; > $DUMP_FOLDER/hw-management_val  2> /dev/null
cp /var/log/syslog $DUMP_FOLDER
cp /var/log/dmesg* $DUMP_FOLDER
uname -a > $DUMP_FOLDER/sys_version
cat /etc/os-release >> $DUMP_FOLDER/sys_version
[ -e /run/log/journal ] && cp -R /run/log/journal $DUMP_FOLDER/journal
cat /proc/interrupts > $DUMP_FOLDER/interrupts

if [ -f "/sys/kernel/debug/regmap/mlxplat/registers" ]; then
    cat /sys/kernel/debug/regmap/mlxplat/registers > $DUMP_FOLDER/registers
fi

if [ -f "/sys/kernel/debug/regmap/mlxplat/access" ]; then
    cat /sys/kernel/debug/regmap/mlxplat/access > $DUMP_FOLDER/access
fi

dump_cmd "dmidecode -t1 -t2 -t 11" "dmidecode"
dump_cmd "lsmod" "lsmod"
dump_cmd "lspci -vvv" "lspci"
dump_cmd "top -SHb -n 1 | tail -n +8 | sort -nrk 11" "top"
dump_cmd "journalctl" "journalctl"
dump_cmd "flint -d mlnxsw-255 -qq q" "flint"
dump_cmd "sx_sdk --version" "sx_sdk_ver"
dump_cmd "lshw" "lshw"
dump_cmd "sensors" "sensors"
dump_cmd "iio_info" "iio_info"

tar czf /tmp/hw-mgmt-dump.tar.gz -C $DUMP_FOLDER .
rm -rf $DUMP_FOLDER

