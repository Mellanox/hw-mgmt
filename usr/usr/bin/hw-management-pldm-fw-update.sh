#!/bin/bash
################################################################################
# Copyright (c) 2024, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

FW_FILE_EXTENSION=".fwpkg"
DEFAULT_PROTO="https"

show_usage()
{
	echo "Script is used for burning PLDM components by BMC through the Redfish interface."
	echo "Usage: $0 [-b [<protocol>] <ip> <file_name>] [-v [<protocol>] <ip> <component_name>]"
	echo "	<protocol> is optional and can be 'https' or 'http'. Default is 'https'."
	echo "Options:"
	echo "  -b [<protocol>] <ip> <file_name>: Flash firmware file and check status"
	echo "  -v [<protocol>] <ip> <FPGA_0 | BMC | CPLD>: Print firmware version for the selected component"
	echo "  -s [<protocol>] <ip>: Show firmware inventory list"
	exit 1
}

validate_proto()
{
	case "$1" in
		"http")
			proto="http"
			;;
		"https")
			proto="https"
			;;
		*)
			echo "Invalid argument for protocol. Use <https> or <http>"
			exit 0
			;;
	esac
}

validate_ip()
{
	if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		return 0
	else
		return 1
	fi
}

validate_file_extension()
{
	if [[ "$1" =~ $FW_FILE_EXTENSION ]]; then
		return 0
	else
		return 1
	fi
}

file_error_handling()
{
	local file="$1"

	if ! validate_file_extension "$file"; then
		echo "Error: File must have .fwpkg extension"
		exit 1
	fi

	if [ -e "$file" ]; then
		return 0
	else
		echo "Error: $file does not exist."
		exit 1
	fi
}

ip_error_handling()
{
	local ip="$1"

	if ! validate_ip "$ip"; then
		echo "Error: Invalid IP address format"
		exit 1
	fi

	if ! ping -c 1 "$ip" > /dev/null; then
		echo "Error: Cannot ping the IP address $ip"
		exit 1
	fi
}

extract_task_state()
{
	local task_state=$(echo "$1" | grep -o '"TaskState": *"[^"]*"')
	if [[ -z "$task_state" ]]; then
		echo "Error: Task state not found in JSON response"
		return 1
	else
		echo "$task_state" | sed 's/.*: *"\([^"]*\)".*/\1/'
	fi
}

get_version()
{
	if [[ "${num_args}" -lt 3 ]]; then
		echo "Error: Wrong number of arguments"
		show_usage
		exit 1
	fi

	local ip="$1"
	local comp="$2"

	if [[ "${num_args}" -eq 4 ]]; then
		validate_proto $optional_proto
	else
		proto=$DEFAULT_PROTO
	fi

	ip_error_handling $1

	# All is good we can query using RF for component version
	local res=$(curl -k -u $USER:$PASS -X GET ${proto}://${ip}/redfish/v1/UpdateService/FirmwareInventory/${comp} 2>/dev/null)
	echo $res | grep -o '"Version": "[^"]*"' | sed 's/"Version": "\([^"]*\)"/\1/'

	if [ -z "$res" ]; then
		echo "Error : No response or error occurred."
		echo "	Verify that you are using the right protocol http/https."
		exit 1
	fi

	#Error handling
	echo $res | grep -q '"error"' && echo "$res"| sed -n 's/.*"message": "\(.*\)".*/\1/p'

}

flash_fw_error_handling()
{
	if [[ "${num_args}" -lt 3 ]]; then
		echo "Error: Wrong number of arguments"
		show_usage
		exit 1
	fi

	ip_error_handling $1
	file_error_handling $2

	if [[ "${num_args}" -eq 4 ]]; then
		validate_proto $optional_proto
	else
		proto=$DEFAULT_PROTO
	fi
}

flash_fw()
{
	local ip="$1"
	local file_name="$2"

	flash_fw_error_handling $1 $2

	# All is good, send payload using RF.
	res=$(curl -k -u $USER:$PASS -H 'Expect:' --location --request POST ${proto}://${ip}/redfish/v1/UpdateService/update-multipart -F 'UpdateParameters={"Targets":["/redfish/v1/Chassis/MGX_Chassis_0"]} ;type=application/json' -F UpdateFile=@${file_name})
	# Get task_id from RF JSON response
	task_id=$res | grep -o '"@odata.id": "[^"]*' | sed 's/.*\///'

	local timeout_seconds=300  # 5 minutes
	local start_time=$(date +%s)

	# Pull for task completion until timeout
	while true; do
		curl_result=$(curl -s -k -u $USER:$PASS -X GET ${proto}://${ip}/redfish/v1/TaskService/Tasks/"${task_id}")
		task_state=$(extract_task_state "$curl_result")
		ret_val=$?
		if [[ $ret_val -eq 0 && "$task_state" = "Completed" ]]; then
			echo "Success: File sent successfully"
			exit 0
		else
			echo "Failure: Task did not complete or state not found"
			echo "TBD Add support for Exception handling"
			exit 1
		fi

		local current_time=$(date +%s)
		local elapsed_time=$((current_time - start_time))
		if [ "$elapsed_time" -ge "$timeout_seconds" ]; then
			echo "Error: Timeout exceeded while waiting for task completion"
			exit 1
		fi

		sleep 5
	done
}

get_fw_ver()
{
	case "$2" in
	"FPGA_0")
		get_version $1 "MGX_FW_FPGA_0"
		exit 0
		;;
	"BMC")
		get_version $1 "MGX_FW_BMC_0"
		exit 0
		;;
	"CPLD")
		get_version $1 "MGX_FW_CPLD_0"
		exit 0
		;;
	*)
		echo "Invalid argument for -v option. Argument must be <FPGA_0 | BMC | CPLD>"
		exit 0
		;;
	esac
}

show_fw_inventory()
{
	local ip="$1"

	if [[ "${num_args}" -eq 3 ]]; then
		validate_proto $optional_proto
	else
		proto=$DEFAULT_PROTO
	fi

	ip_error_handling $ip

	# All is good we can query for the inventory list
	resp=$(curl -s -k -u $USER:$PASS -X GET ${proto}://${ip}/redfish/v1/UpdateService/FirmwareInventory/)

	if [ -z "$resp" ]; then
		echo "Error : No response or error occurred."
		echo "	Verify that you are using the right protocol http/https."
		exit 1
	else
		echo "${resp}"
		exit 0
	fi
}

num_args=$#
optional_proto=$2

while getopts ":b:v:s:h" opt; do
	case $opt in
		b)
			second_to_last_index=$((num_args-1))
			last_index=$((num_args))
			flash_fw ${!second_to_last_index} ${!last_index}
			;;
		v)
			second_to_last_index=$((num_args-1))
			last_index=$((num_args))
			get_fw_ver ${!second_to_last_index} ${!last_index}
			;;
		s)
			last_index=$((num_args))
			show_fw_inventory ${!last_index}
			;;
		h)
			show_usage
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			show_usage
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			show_usage
			;;
	esac
done

show_usage
