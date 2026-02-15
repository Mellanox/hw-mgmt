#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

do_global_wp_release_restore()
{
	action="$1"
	file="$2"
	command="$3"
	param1="$4"
	param2="$5"
	param3="$6"
	param4="$7"

	if [ ! -L "$system_path"/global_wp_request ] || [ ! -L "$system_path"/global_wp_response ]; then
		return 1
	fi
	[ -f "$config_path"/global_wp_timeout ] && global_wp_timeout=$(< "$config_path"/global_wp_timeout);
	[ -f "$config_path"/global_wp_wait_step ] && global_wp_wait_step=$(< "$config_path"/global_wp_wait_step);
	if [ "$global_wp_wait_step" -gt 0 ] && [ "$global_wp_timeout" -gt 0 ]; then
		case "$action" in
		release)
			while [ "$global_wp_timeout" -gt 0 ]
			do
				# Request to disable Global Write Protection.
				# Write Global Write Protection request.
				echo 0 > "$system_path"/global_wp_request

				# Validate if request to disable Global Write Protection was accepted.
				sleep 0.1 &
				wait $!

				# Validate if request to disable Global Write Protection was accepted.
				# Read Global Write Protection response.
				global_wp_response=$(< "$system_path"/global_wp_response)
				if [ "$global_wp_response" != 0 ]; then
					global_wp_timeout=$((global_wp_timeout-global_wp_wait_step))
					continue
				fi

				if [ "$command" != "" ]; then
					# Execute user command for flashing device.
					"$command" "$param1" $param2 $param3 $param4 "$file"
					rc=$?
					if [ $rc -eq 0 ]; then
						log_info "$command completed."
					else
						global_wp_response=$(< "$system_path"/global_wp_response)
						if [ "$global_wp_response" != 0 ]; then
							log_info "$command failed - Global WP grant has been removed by remote end."
						fi
					fi
				fi

				# Clear Global Write Protection request.
				echo 1 > "$system_path"/global_wp_request
				return "$rc"
			done
			log_info "Failed to request Global WP grant."
			return 1
		;;

		restore)
			# Clear Global Write Protection request.
			echo 1 > "$system_path"/global_wp_request
			return 0
		;;
		*)
			return 1
		;;
		esac
	fi
}


do_asic_wp_release_restore()
{
	action="$1"
	file="$2"
	command="$3"
	param1="$4"
	param2="$5"
	param3="$6"
	param4="$7"
	
	if [ ! -L "$system_path"/erot1_wp ] || [ ! -L "$system_path"/erot2_wp ]; then
		return 1
	fi
	
	case "$action" in
		release)
			echo 0 > "$system_path"/erot1_wp
			echo 0 > "$system_path"/erot2_wp
			
			if [ "$command" != "" ]; then
				# Execute user command for flashing device.
				"$command" "$param1" $param2 $param3 $param4 "$file"
				rc=$?
				if [ $rc -eq 0 ]; then
					log_info "$command completed."
				else
					log_info "$command failed."
				fi
			fi
			echo 1 > "$system_path"/erot1_wp
			echo 1 > "$system_path"/erot2_wp
			return "$rc"
			;;

		restore)
			# Clear Global Write Protection request.
			echo 1 > "$system_path"/erot1_wp
			echo 1 > "$system_path"/erot2_wp
			return 0
		;;
		*)
			return 1
		;;
	esac
}

__usage="
Usage: $(basename "$0") [Options]

Options:
	release		Request to remove Global Write Protect to
			to get grant for flashing of burnable component.
			Perform flashing.
			Restore Global Write Protect.
			Parameters:
			- 2 - file to be flashed.
			- 3 - command to be executed.
			- 4 - 7 - optional parameters for command to be
				executed.
			If no parameters are specified - command is used
			only for getting grant.
	restore		Request to restore Global Write Protect after
			device flashing is completed.
"
global_wp_pid=$$
action="$1"
case $action in
release|restore)
	if [ "$3" == "" ] || [ "$2" == "" ]; then
		log_info "Wrong command format."
		echo "$__usage"
		exit 1
	fi

	lock_service_state_change
	# Only one Global WP process can be activated.
	if [ -f /var/run/hw-management-global-wp.pid ]; then
		log_info "Global WP process is already running."
		exit 1
	fi
	echo "$global_wp_pid" > /var/run/hw-management-global-wp.pid
	# systems without global WP but with ASIC WP
	sku=$(< /sys/devices/virtual/dmi/id/product_sku)
	if [ "$sku" == "HI142" ] || [ "$sku" == "HI152" ]; then
		do_asic_wp_release_restore "$action" "$2" "$3" "$4" "$5" "$6" "$7"
	else
		do_global_wp_release_restore "$action" "$2" "$3" "$4" "$5" "$6" "$7"
	fi
	ret=$?
	rm /var/run/hw-management-global-wp.pid
	unlock_service_state_change
	exit $ret
	;;
*)
	echo "$__usage"
	exit 1
	;;
esac
exit 0
