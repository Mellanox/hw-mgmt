#!/bin/bash

# Copyright (c) 2018 - 2021, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

board_type=`cat /sys/devices/virtual/dmi/id/board_name`

if [ "$board_type" == "VMOD0014" ]; then
	# TODO Verify on system if it's really required
	# Wait for PCA9555 to start.
	while [ ! -e /sys/class/gpio/gpiochip342 ]
	do
		sleep 1
	done

	for gpio_num in $(seq 342 357); do
		if [ ! -e /sys/class/gpio/gpio"$gpio_num"/value ]; then
			echo "$gpio_num" > /sys/class/gpio/export
		fi
	done

	echo "in" > /sys/class/gpio/gpio342/direction
	echo "out" > /sys/class/gpio/gpio343/direction
	echo "out" > /sys/class/gpio/gpio344/direction
	echo "in" > /sys/class/gpio/gpio345/direction
	echo "in" > /sys/class/gpio/gpio346/direction
	echo "in" > /sys/class/gpio/gpio347/direction
	echo "in" > /sys/class/gpio/gpio348/direction
	echo "out" > /sys/class/gpio/gpio349/direction
	echo "out" > /sys/class/gpio/gpio350/direction
	echo "out" > /sys/class/gpio/gpio351/direction
	echo "out" > /sys/class/gpio/gpio352/direction
	echo "out" > /sys/class/gpio/gpio353/direction
	echo "out" > /sys/class/gpio/gpio354/direction
	echo "out" > /sys/class/gpio/gpio355/direction
	echo "out" > /sys/class/gpio/gpio356/direction
	echo "out" > /sys/class/gpio/gpio357/direction

	# Initialize fantray LED value.
	for gpio_num in $(seq 350 357); do
		if [ -e /sys/class/gpio/gpio"$gpio_num"/active_low ]; then
			echo 1 > /sys/class/gpio/gpio"$gpio_num"/active_low
		fi
		echo 0 > /sys/class/gpio/gpio"$gpio_num"/value
	done
fi

exit 0
