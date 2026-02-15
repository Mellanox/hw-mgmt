#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

cpu_type=0
check_cpu_type

case $cpu_type in
	$CFL_CPU)
		;;
	*)
		echo "$0 is not supported on this CPU type."
		exit 1
		;;
esac

ret=0
last_caps=$(hexdump -ve '1/1 "%c"' /sys/firmware/efi/efivars/CapsuleLast* | sed 's/[^a-zA-Z0-9]//g')
rc=$(hexdump -ve '1/1 "%.2x"' /sys/firmware/efi/efivars/"$last_caps"* | awk '{ print substr( $0, length($0) - 15, length($0) ) }')
active_image=$(cat /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/bios_active_image)
ts=$(lspci -xxx -s 00:1f.5 | grep "d0:" | awk '{print $14}')
ts=$((16#$ts & 0x16))
ts=$((ts >>= 4))
echo "Last performed BIOS update: ${last_caps}"
echo "Active image: ${active_image}"
echo "Top-Swap status: ${ts}"
echo "Bios update result: ${rc}"
if [ "$active_image" != "$ts" ]; then
	echo "Error: CPLD indication of active image doesn't correspond to CPU report!"
	ret=1
fi
if [[ $rc =~ [1-9a-fA-F] ]]; then
	echo "Last BIOS update Failed."
	ret=1
else
	echo "Last BIOS update Success."
fi
exit $ret
