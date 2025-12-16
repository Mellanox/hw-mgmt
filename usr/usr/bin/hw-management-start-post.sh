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

# Create the links for the sensors which doesn't have emulation drivers
if check_simx; then
        if check_if_simx_supported_platform; then
                case $sku in
                        HI166|HI176|HI171|HI193)
                                process_simx_links
                                ;;
                        *)
                                ;;
                esac

        fi
fi

## Check SKU and run the below only for relevant.
case $sku in
	HI130|HI151|HI157|HI158|HI162|HI166|HI167|HI169|HI170|HI171|HI172|HI173|HI174|HI175|HI176|HI177|HI178)
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

# update Thermal Control service to use correct executable revision
service_file_path=$(systemctl status hw-management-tc.service | grep hw-management-tc.service | sed -n '2p' | awk -F'[();]' '{print $2}')
if [ -f $service_file_path ]; then
	md5sum_orig=$(md5sum $service_file_path | awk '{print $1}')
	case $sku in
		HI172|HI171)	# Systems allowed to use new hw-management-tc
			tc_version="2.5"
			tc_executable="hw_management_thermal_control_2_5.py"
			;;
		*)
			tc_version="2.0"
			tc_executable="hw_management_thermal_control.py"
			;;
	esac
	sed -i "s/hw_management_thermal_control.py/$tc_executable/g" $service_file_path
	sed -i "s/ver 2.0/ver $tc_version/g" $service_file_path
	md5sum_new=$(md5sum $service_file_path | awk '{print $1}')
	if [ "$md5sum_orig" != "$md5sum_new" ]; then
		log_info "Thermal Control service updated. reload it in 10 seconds"
		bash -c 'sleep 10 && systemctl daemon-reload && systemctl restart hw-management-tc.service' &
	fi
fi

# If the BSP emulation is not available for the platforms that run in the SimX
# environment, TC need to be stopped. Otherwise enabling TC.
if check_simx; then
    if ! check_if_simx_supported_platform; then
	    if systemctl is-enabled --quiet hw-management-tc; then
		    echo "Stopping and disabling hw-management-tc on SimX"
		    systemctl stop hw-management-tc
		    systemctl disable hw-management-tc
	    fi
	    echo "Start Chassis HW management service."
	    logger -t hw-management -p daemon.notice "Start Chassis HW management service."
	    exit 0
    else
	    if ! systemctl is-enabled --quiet hw-management-tc; then
		    echo "Enabling and starting hw-management-tc"
		    if check_tc_support; then
			    systemctl enable hw-management-tc
			    nohup systemctl start hw-management-tc &
			fi
	    fi
    fi
fi

## Checking if system doesn't require TC
check_tc_is_supported
if [ $? -eq 0 ]; then
	log_info "Disabe Thermal Control for current platform: $sku"
	systemctl stop hw-management-tc.service
	systemctl disable hw-management-tc.service  
fi

