#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2018-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause

hw_management_path=/var/run/hw-management
system_path=$hw_management_path/system
environment_path=hw_management_path/environment

if echo "$0" | grep -q "/pwr_consum" ; then
	if [ ! -L $system_path/select_iio ]; then
		exit 0
	fi
	if [ "$1" == "psu1" ]; then
		echo 1 > $system_path/select_iio
	elif [ "$1" == "psu2" ]; then
		echo 0 > $system_path/select_iio
	fi

	iioreg=$(< $environment_path/a2d_iio\:device1_raw_1)
	echo $((iioreg * 80 * 12))
	exit 0
fi

if echo "$0" | grep -q "/pwr_sys" ; then
	if [ "$1" == "psu1" ]; then
		iioreg_vin=$($environment_path/a2d_iio\:device0_raw_1)
		iioreg_iin=$($environment_path/a2d_iio\:device0_raw_6)
	elif [ "$1" == "psu2" ]; then
		iioreg_vin=$($environment_path/a2d_iio\:device0_raw_2)
		iioreg_iin=$($environment_path/a2d_iio\:device0_raw_7)
	fi

	echo $((iioreg_vin * iioreg_iin * 59 * 80))
	exit 0
fi

