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


# ww-management command that is executed after hw-management start.
# Activated by systemd.

# Local constants and paths.
wait_pid_cntr=3
max_cpld=4
max_fan_drwr=8
hw_management_path=/var/run/hw-management
config_path=$hw_management_path/config
system_path=$hw_management_path/system
thermal_path=/var/run/hw-management/thermal
PID=/var/run/hw-management.pid
 
handle_cpld_versions()
{
	local -r cpld_num="${1}"
	if [ $cpld_num -lt $max_cpld ]; then
		if [ -L $system_path/cpld"$max_cpld"_ver ]; then
			unlink $system_path/cpld"$max_cpld"_version
		fi
		if [ -L $system_path/cpld"$max_cpld"_pn ]; then
			unlink $system_path/cpld"$max_cpld"_pn
		fi
		if [ -L $system_path/cpld"$i"_version_min ]; then
			unlink $system_path/cpld"$max_cpld"_version_min
		fi
	fi
}

set_fan_drwr_num()
{
	drwr_num=0
	for ((i=1; i<=$max_fan_drwr; i+=1)); do
		if [ -L $thermal_path/fan"$i"_status ]; then
			drwr_num=$(($drwr_num+1))
		fi
	done
	echo $drwr_num > $config_path/fan_drwr_num
}

# Wait for PID.
while [ ! -f $PID ] && [ "$wait_pid_cntr" -gt  "0" ]; do
	sleep 1
	wait_pid_cntr=$(($wait_pid_cntr-11))
done

board=`cat /sys/devices/virtual/dmi/id/board_name`
cpld_num=`cat $config_path/cpld_num`
case $board in
	VMOD0001|VMOD0002|VMOD0003|VMOD004)
		handle_cpld_versions $(($cpld_num-1))
		set_fan_drwr_num
		;;
	VMOD0005|VMOD0007|VMOD0009|VMOD0010)
		handle_cpld_versions $cpld_num
		set_fan_drwr_num
		;;
	*)
		;;
esac
