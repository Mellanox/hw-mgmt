#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2018-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

source hw-management-helpers.sh

port_name=$1
board=$(< $board_type_file)

case $board in
VMOD0010)
	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	case $sku in
	HI140|HI141)
		# Determine ASIC index according to ASIC I2C bus
		busdir=$(echo ${2}${3} | xargs dirname | xargs dirname)
		busfolder=$(basename $busdir)
		bus="${busfolder:0:${#busfolder}-5}"
		case $bus in
		2)
			# ASIC1 on leaf or spine
			echo sw1${port_name}
			;;
		*)
			# ASIC2 on leaf or spine
			echo sw2${port_name}
			;;
		esac
		;;
	*)
		echo ${port_name}
		;;
	esac
	;;
VMOD0011)
	# Remove line card index from port name.
	remove_pattern=`echo ${port_name} | cut -c3-4`
	echo ${port_name} | sed s/"$remove_pattern"//
	;;
*)
	echo ${port_name}
	;;
esac

exit 0
