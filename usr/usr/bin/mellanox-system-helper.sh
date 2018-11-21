#!/bin/bash

# Copyright (c) 2018 Mellanox Technologies. All rights reserved.
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

bsp_path=/var/run/mellanox

if echo "$0" | grep -q "/cpld" ; then
	if [ "$1" == "mgmt" ]; then
		ver=`/usr/sbin/iorw -b 0x2500 -r -l1 | awk '{print $5}'`
	elif [ "$1" == "brd" ]; then
		ver=`/usr/sbin/iorw -b 0x2501 -r -l1 | awk '{print $5}'`
	elif [ "$1" == "port" ]; then
		ver=0
		if [ -f /dev/mst/mt52100_pciconf0 ]; then
			ver=`sudo /usr/bin/mlxreg -d /dev/mst/mt52100_pciconf0 --get --reg_id 0x902A --reg_len 16 | tail -n4 | head -n1 | awk '{print $3}'`
		fi
	fi
	echo $(($ver))
	exit 0
fi

if echo "$0" | grep -q "/pwr_consum" ; then
	/usr/sbin/iorw -b 0x2533 -w -l1 -v0xbf
	regval=`/usr/sbin/iorw -b 0x2532 -r -l1 | awk '{print $5}'`

	if [ "$1" == "psu1" ]; then
		regnew=`echo $(($regval | 0x40))`
	elif [ "$1" == "psu2" ]; then
		regnew=`echo $(($regval & 0xbf))`
	fi

	/usr/sbin/iorw -b 0x2532 -w -l1 -v$regnew
	iioreg=`cat $bsp_path/environment/a2d_iio\:device1_raw_1`
	echo $(($iioreg * 80 * 12))
	exit 0
fi

if echo "$0" | grep -q "/pwr_sys" ; then
	if [ "$1" == "psu1" ]; then
		iioreg_vin=`cat $bsp_path/environment/a2d_iio\:device0_raw_1`
		iioreg_iin=`cat $bsp_path/environment/a2d_iio\:device0_raw_6`
	elif [ "$1" == "psu2" ]; then
		iioreg_vin=`cat $bsp_path/environment/a2d_iio\:device0_raw_2`
		iioreg_iin=`cat $bsp_path/environment/a2d_iio\:device0_raw_7`
	fi

	echo $(($iioreg_vin * $iioreg_iin * 59 * 80))
	exit 0
fi

