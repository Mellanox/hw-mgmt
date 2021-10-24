#!/bin/bash
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

# hw-management script that is executed at the end of hw-management start.
source hw-management-helpers.sh

# Local constants and paths.
max_cpld=4
max_fan_drwr=8
CPLD3_VER_DEF="0"
 
handle_cpld_versions()
{
	cpld_num_loc="${1}"
	if [ "$cpld_num_loc" -lt "$max_cpld" ]; then
		if [ -L $system_path/cpld"$max_cpld"_version ]; then
			unlink $system_path/cpld"$max_cpld"_version
		fi
		if [ -L $system_path/cpld"$max_cpld"_pn ]; then
			unlink $system_path/cpld"$max_cpld"_pn
		fi
		if [ -L $system_path/cpld"$max_cpld"_version_min ]; then
			unlink $system_path/cpld"$max_cpld"_version_min
		fi
	fi

	for ((i=1; i<=cpld_num_loc; i+=1)); do
		if [ -L $system_path/cpld"$i"_pn ]; then
			cpld_pn=$(cat $system_path/cpld"$i"_pn)
		fi
		if [ -f $system_path/cpld"$i"_version ]; then
			cpld_ver=$(cat $system_path/cpld"$i"_version)
		fi
		if [ -L $system_path/cpld"$i"_version_min ]; then
			cpld_ver_min=$(cat $system_path/cpld"$i"_version_min)
		fi
		if [ -z "$str" ]; then
			str=$(printf "CPLD%06d_REV%02d%02d" "$cpld_pn" "$cpld_ver" "$cpld_ver_min")
		else
			str=$str$(printf "_CPLD%06d_REV%02d%02d" "$cpld_pn" "$cpld_ver" "$cpld_ver_min")
		fi
	done
	echo "$str" > $system_path/cpld_base
	echo "$str" > $system_path/cpld
}

set_fan_drwr_num()
{
	drwr_num=0
	for ((i=1; i<=max_fan_drwr; i+=1)); do
		if [ -L $thermal_path/fan"$i"_status ]; then
			drwr_num=$((drwr_num+1))
		fi
	done
	echo $drwr_num > $config_path/fan_drwr_num
}

board=$(cat /sys/devices/virtual/dmi/id/board_name)
cpld_num=$(cat $config_path/cpld_num)
case $board in
	VMOD0001|VMOD0003)
		cpld_num=$((cpld_num-1))
		;;
	*)
		;;
esac

timeout 60 bash -c 'until [ -L /var/run/hw-management/system/cpld1_version ]; do sleep 1; done'
sleep 1

# Read cpld3 version with the mlxreg from mft package
if [ -f $config_path/cpld_port ];
then
    cpld=$(< $config_path/cpld_port)
    if [ $cpld == "cpld3" ] && [ ! -f $system_path/cpld3_version ];
    then
        ver_dec=$CPLD3_VER_DEF
        # check if mlxreg exists
        if [ -x "$(command -v mlxreg)" ];
        then
            lsmod | grep mst_pci >/dev/null 2>&1
            if [  $? -ne 0 ];
            then
                mst start  >/dev/null 2>&1
                sleep 2
            fi
            cmd='mlxreg --reg_name MSCI  -d /dev/mst/mt52100_pciconf0 -g -i "index=2" | grep version | cut -d "|" -f2'
            ver_hex=$(eval $cmd)
            if [ ! -z "$ver_hex" ]; then
               ver_dec=$(printf "%d" $ver_hex)
            fi
        fi
        echo "$ver_dec" > $system_path/cpld3_version
    fi
fi

handle_cpld_versions $cpld_num
# Do not set for fixed fans systems. For fixed fans systems fan_drwr_num set in system specific init function.
if [ ! -f $config_path/fixed_fans_system ]; then
	set_fan_drwr_num
fi
