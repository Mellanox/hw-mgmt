#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2018-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Description: performs board specific I2C-GPIO expander initialisation.

source hw-management-helpers.sh

board_type=`cat /sys/devices/virtual/dmi/id/board_name`

if [ "$board_type" == "VMOD0014" ]; then
	gpiobase=
	for gpiochip in /sys/class/gpio/*; do
		if [ -d "$gpiochip" ] && [ -e "$gpiochip"/label ]; then
			gpiolabel=$(<"$gpiochip"/label)
			if [ "$gpiolabel" == "7-0027" ] || [ "$gpiolabel" == "pca9555" ]; then
				gpiobase=$(<"$gpiochip"/base)
				break
			fi
		fi
	done
	if [ -z "$gpiobase" ]; then
		log_err "I2C PCA9555 GPIO was not found"
		exit 1
	fi

	echo "$gpiobase" > $config_path/i2c_gpiobase
	gpioend=$((gpiobase+15))
	gpiodirs=("in" "out" "out" "in" "in" "in" "in" "out" "out" "out" "out" "out" "out" "out" "out" "out")
	for gpio_num in $(seq "$gpiobase" "$gpioend"); do
		if [ ! -e /sys/class/gpio/gpio"$gpio_num"/value ]; then
			echo "$gpio_num" > /sys/class/gpio/export
			i=$((gpio_num-gpiobase))
			echo ${gpiodirs[$i]} > /sys/class/gpio/gpio"$gpio_num"/direction
		fi
	done

	# Initialize fantray LED value.
	gpioled_start=$((gpiobase+8))
	for gpio_num in $(seq "$gpioled_start" "$gpioend"); do
		if [ -e /sys/class/gpio/gpio"$gpio_num"/active_low ]; then
			echo 1 > /sys/class/gpio/gpio"$gpio_num"/active_low
		fi
		echo 0 > /sys/class/gpio/gpio"$gpio_num"/value
	done
fi

exit 0
