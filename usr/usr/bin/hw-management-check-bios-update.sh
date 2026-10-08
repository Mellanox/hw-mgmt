#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

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
