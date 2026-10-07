#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2018-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

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
