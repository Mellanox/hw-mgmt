#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
	VMOD0019)
		# Trying to re-instatiate mlxreg-dpu driver for smart switch if there
		# was a problem during initialization
		if [ "$sku" == "HI160" ]; then
			check_and_recreate_dpu_devices
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
                        HI166|HI176|HI171|HI183|HI187)
                                process_simx_links
                                ;;
                        *)
                                ;;
                esac

        fi
fi

## Check SKU and run the below only for relevant.
case $sku in
	HI130|HI151|HI157|HI158|HI162|HI166|HI167|HI169|HI170|HI171|HI172|HI173|HI174|HI175|HI176|HI177|HI178|HI179|HI180|HI185)
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

# Check if TC service is enabled (unit enabled at boot).
tc_is_enabled=0
if systemctl is-enabled --quiet hw-management-tc.service 2>/dev/null; then
	tc_is_enabled=1
fi

# Initialize TC service control variables.
tc_should_enable=0
tc_should_disable=0
tc_should_start=0

## Checking if system doesn't support TC and disable it if it doesn't.
if check_tc_is_supported; then
	# If TC is not supported, disable it.
	log_info "Disable Thermal Control for current platform: $sku"
	tc_should_disable=1
else
	# If we are running in SimX environment and the BSP emulation is not available for the platforms that run in the SimX
	# environment, TC need to be stopped. Otherwise, enable and start TC.
	if check_simx; then
		# Check if SimX is supported for the current platform.
		if ! check_if_simx_supported_platform; then
			if [ $tc_is_enabled -eq 1 ]; then
				echo "Stopping and disabling hw-management-tc on SimX"
				logger -t hw-management -p daemon.notice "Stopping and disabling hw-management-tc on SimX"
				# TC service should be stopped and disabled.
				tc_should_disable=1
			fi
		else
			# If TC is supported in SimX.
			if [ $tc_is_enabled -eq 0 ]; then
				echo "Enable and start Thermal Control service."
				logger -t hw-management -p daemon.notice "Thermal Control service scheduled to start."
				# TC service should be enabled and started.
				tc_should_enable=1
				tc_should_start=1
			fi
		fi
	fi

	# PartOf=hw-management.service only propagates stop/restart of hw-management-tc.service,
	# not start. If hw-management.service was stopped and later started separately (rather
	# than restarted), an already-enabled TC service is left inactive. Schedule a restore
	# below, but only when hw-management-tc-stop-post.sh recorded that the prior stop was
	# this PartOf= cascade rather than an operator directly stopping TC - see
	# tc_pending_restart_file in hw-management-helpers.sh. The marker is re-checked (and
	# consumed) at actual start time, not here, since the start itself runs after a 10s
	# deferral below: consuming it this early would let an operator's stop issued during
	# that window be silently overridden by our own stale decision.
	if [ $tc_is_enabled -eq 1 ] && [ $tc_should_disable -eq 0 ] && [ $tc_should_start -eq 0 ]; then
		if [ -f "$tc_pending_restart_file" ]; then
			log_info "Thermal Control restore scheduled after hw-management restart."
			tc_should_start=1
		fi
	fi
fi

# Build and execute the command line for TC service control only when there is something to do.
if [ $tc_should_disable -eq 1 ] || [ $tc_should_enable -eq 1 ] || [ $tc_should_start -eq 1 ]; then
	cmd_line="sleep 10 &&"

	# Disable TC service if needed.
	if [ $tc_should_disable -eq 1 ]; then
		cmd_line="$cmd_line systemctl stop hw-management-tc && systemctl disable hw-management-tc &&"
	elif [ $tc_should_enable -eq 1 ]; then
		# TC service should be enabled.
		cmd_line="$cmd_line systemctl enable hw-management-tc &&"
		if [ $tc_should_start -eq 1 ]; then
			# TC service should be started.
			cmd_line="$cmd_line systemctl start hw-management-tc &&"
		fi
	elif [ $tc_should_start -eq 1 ]; then
		# TC service is already enabled and was inactive with a pending-restart marker
		# at decision time. Re-check (and consume) the marker here, once the 10s
		# deferral below has elapsed, so a stop issued by an operator during that
		# window - which would remove the marker via hw-management-tc-stop-post.sh -
		# is not silently overridden by this stale scheduling decision.
		cmd_line="$cmd_line if [ -f $tc_pending_restart_file ]; then rm -f $tc_pending_restart_file; if ! systemctl is-active --quiet hw-management-tc.service; then systemctl start hw-management-tc; fi; fi &&"
	fi

	# Run the command line in the background and log the output to /dev/null.
	# it is necessary because on SIMX, hw-mgmt tries to start the TC service during initialization.
	# However, the TC service has a strong dependency:
	# Requires=hw-management.service. This means the TC service cannot start
	# before hw-mgmt starts. But hw-mgmt attempts to start TC earlier. In this
	# case, neither hw-mgmt nor TC will complete initialization.
	# to run it in the background to avoid blocking the startup process.
	nohup bash -c "$cmd_line echo thermal control service configured" &>/dev/null &
fi


# double check fan_dir present and initialize it
set_fan_direction_for_all_fans 0
