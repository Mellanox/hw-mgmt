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
# Description: performs board specific I2C-GPIO expander initialisation.
#

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
