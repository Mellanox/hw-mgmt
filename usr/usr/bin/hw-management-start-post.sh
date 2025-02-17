#!/bin/bash
##################################################################################
# Copyright (c) 2020 - 2022, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
CPLD3_VER_DEF="0"
 
board=$(< $board_type_file)
sku=$(< $sku_file)
cpld_num=$(cat $config_path/cpld_num)
case $board in
	VMOD0015)
		# Special case to inform external node (BMC) that system ready
		# for telemetry communication.
		if [ ! -L $system_path/comm_chnl_ready ]; then
			log_err "Missed attrubute comm_chnl_ready."
		else
			echo 1 > $system_path/comm_chnl_ready
			log_info "Communication channel is ready"
		fi
		;;
	VMOD0017)
		# Nvidia RM driver can be probed at system init before mlx_platform.
		# NVlink I2C busses will be created and this can affect BSP I2C busses.
		# Nvidia NVLink drivers are in blacklist and instaniated at the end of
		# hw-management init.
		modprobe nvidia_drm
		;;
	VMOD0010)
		# Kong has the same issue as Goldstone (VMOD0017)
		if [ "$sku" == "HI142" ]; then
			modprobe nvidia_drm
		fi
		;;
	*)
		;;
esac

if [ ! -f /var/run/hw-management/system/cpld_base ]; then
	timeout 5 bash -c 'until [ -f /var/run/hw-management/system/cpld_base ]; do sleep 0.2; done'
fi

## Check SKU and run the below only for relevant.
case $sku in
	HI130|HI151|HI157|HI158|HI162|HI166|HI167|HI169|HI170|HI171|HI172|HI173|HI174|HI175)
		ui_tree_archive_file="$(get_ui_tree_archive_file)"
		if [ -e "$ui_tree_archive_file" ]; then
			# Extract the ui_tree archive to /var/run/hw-management
			tar xfz "$ui_tree_archive_file" -C "$hw_management_path"
			echo 1 > "$config_path"/labels_ready
			log_info "Labels data base is ready"
		else
		    hw-management-label-init-complete.sh &
		fi
		;;
	*)
		# Do nothing
esac
