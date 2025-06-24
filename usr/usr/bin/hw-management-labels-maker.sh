#!/bin/bash
########################################################################
# Copyright (c) 2023, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
set -x
sku=$(< $sku_file)
ui_path=$hw_management_path/ui 

# Obtain label file (/var/run/hw-management/config/lm_sensors_labels).
json_file=$hw_management_path/config/lm_sensors_labels

if [ ! -f $json_file ]; then
	exit 1
fi

# Check if the dictionary has already been loaded
if [ ! -f "/tmp/sensor_labels_dictionary.pkl" ]; then
	lock_service_state_change
	# Call the Python program to load the JSON file and store the dictionary
	hw_management_parse_labels.py --json_file "$json_file" --sku "$sku" 
	unlock_service_state_change
fi

# No prefix index, f.e. "drivetemp"
get_label_files0()
{
	local attr_name="$1"
	local folder
	local key
	local attr_file

	folder=`echo $attr_name | cut -d '_' -f 1`
	key=`echo $attr_name | cut -d '_' -f 1`
	attr_file=`echo "$attr_name" | cut -d '_' -f 2,3`
	echo "$folder" "$key" "$attr_file"
}

# One prefix index, f.e. "voltmon1"
get_label_files1()
{
	local attr_name="$1"
	local folder
	local key
	local attr_file

	folder=`echo $attr_name | cut -d '_' -f 1,2`
	key=`echo $attr_name | cut -d '_' -f 1,2,3`
	attr_file=`echo "$attr_name" | cut -d '_' -f 4,5,6`
	echo "$folder" "$key" "$attr_file"
}

# Two prefixes index, f.e. "comex_voltmon1".
get_label_files2()
{
	local attr_name="$1"
	local folder
	local key
	local attr_file

	folder=`echo $attr_name | cut -d '_' -f 1`
	key=`echo $attr_name | cut -d '_' -f 1,2`
	attr_file=`echo "$attr_name" | cut -d '_' -f 3,4,5`
	echo "$folder" "$key" "$attr_file"
}

# Three prefixes index, f.e. "pdb_pwr_conv1".
get_label_files3()
{
	local attr_name="$1"
	local folder
	local key
	local attr_file

	folder=`echo $attr_name | cut -d '_' -f 1,2,3`
	key=`echo $attr_name | cut -d '_' -f 1,2,3,4`
	attr_file=`echo "$attr_name" | cut -d '_' -f 5`
	echo "$folder" "$key" "$attr_file"
}

# Create labels
# $1 - file path
make_labels()
{
	local attr_full_name="$1"
	local oper="$2"
	local folder
	local subfolder
	local key
	local attr_file
	local scale
	local attr_name=$(basename $attr_full_name)

	case $attr_name in
	comex_voltmon1_in*|comex_voltmon2_in*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	comex_voltmon1_curr*|comex_voltmon2_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	comex_voltmon1_power*|comex_voltmon2_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	comex_voltmon1_temp*|comex_voltmon2_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	voltmon1_in*|voltmon2_in*|voltmon3_in*|voltmon4_in*|voltmon5_in*|voltmon6_in*|voltmon7_in*|voltmon8_in*|voltmon9_in*|voltmon10_in*|voltmon11_in*|voltmon12_in*|voltmon13_in*|voltmon14_in*|voltmon15_in*|voltmon16_in*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	sbw1_voltmon1_in*|sbw1_voltmon2_in*|sbw1_voltmon3_in*|sbw1_voltmon4_in*|sbw1_voltmon5_in*|sbw1_voltmon6_in*|sbw2_voltmon1_in*|sbw2_voltmon2_in*|sbw2_voltmon3_in*|sbw2_voltmon4_in*|sbw2_voltmon5_in*|sbw2_voltmon6_in*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	voltmon1_power*|voltmon2_power*|voltmon3_power*|voltmon4_power*|voltmon5_power*|voltmon6_power*|voltmon7_power*|voltmon8_power*|voltmon9_power*|voltmon10_power*|voltmon11_power*|voltmon12_power*|voltmon13_power*|voltmon14_power*| voltmon15_power*|voltmon16_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	sbw1_voltmon1_power*|sbw1_voltmon2_power*|sbw1_voltmon3_power*|sbw1_voltmon4_power*|sbw1_voltmon5_power*|sbw1_voltmon6_power*|sbw2_voltmon1_power*|sbw2_voltmon2_power*|sbw2_voltmon3_power*|sbw2_voltmon4_power*|sbw2_voltmon5_power*|sbw2_voltmon6_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	voltmon1_curr*|voltmon2_curr*|voltmon3_curr*|voltmon4_curr*|voltmon5_curr*|voltmon6_curr*|voltmon7_curr*|voltmon8_curr*|voltmon9_curr*|voltmon10_curr*|voltmon11_curr*|voltmon12_curr*|voltmon13_curr*|voltmon14_curr*|voltmon15_curr*|voltmon16_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	sbw1_voltmon1_curr*|sbw1_voltmon2_curr*|sbw1_voltmon3_curr*|sbw1_voltmon4_curr*|sbw1_voltmon5_curr*|sbw1_voltmon6_curr*|sbw2_voltmon1_curr*|sbw2_voltmon2_curr*|sbw2_voltmon3_curr*|sbw2_voltmon4_curr*|sbw2_voltmon5_curr*|sbw2_voltmon6_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	voltmon1_temp*|voltmon2_temp*|voltmon3_temp*|voltmon4_temp*|voltmon5_temp*|voltmon6_temp*|voltmon7_temp*|voltmon8_temp*|voltmon9_temp*|voltmon10_temp*|voltmon11_temp*|voltmon12_temp*|voltmon13_temp*|voltmon14_temp*|voltmon15_temp*|voltmon16_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	sbw1_voltmon1_temp*|sbw1_voltmon2_temp*|sbw1_voltmon3_temp*|sbw1_voltmon4_temp*|sbw1_voltmon5_temp*|sbw1_voltmon6_temp*|sbw2_voltmon1_temp*|sbw2_voltmon2_temp*|sbw2_voltmon3_temp*|sbw2_voltmon4_temp*|sbw2_voltmon5_temp*|sbw2_voltmon6_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	psu1_volt*|psu2_volt*|psu3_volt*|psu4_volt*|psu5_volt*|psu6_volt*|psu7_volt*|psu8_volt*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_power*|psu2_power*|psu3_power*|psu4_power*|psu5_power*|psu6_power*|psu7_power*|psu8_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_curr*|psu2_curr*|psu3_curr*|psu4_curr*|psu5_curr*|psu6_curr*|psu7_curr*|psu8_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_temp*|psu2_temp*|psu3_temp*|psu4_temp*|psu5_temp*|psu6_temp*|psu7_temp*|psu8_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_fan*|psu2_fan*|psu3_fan*|psu4_fan*|psu5_fan*|psu6_fan*|psu7_fan*|psu8_fan*)
		subfolder="fan"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	pwr_conv1_in*|pwr_conv2_in*|pwr_conv3_in*|pwr_conv4_in*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pwr_conv1_curr*|pwr_conv2_curr*|pwr_conv3_curr*|pwr_conv4_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pwr_conv1_temp*|pwr_conv2_temp*|pwr_conv3_temp*|pwr_conv4_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;	
	pwr_conv1_power*|pwr_conv2_power*|pwr_conv3_power*|pwr_conv4_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;	
	pdb_pwr_conv1_in*|pdb_pwr_conv2_in*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files3 $attr_name)
		;;
	pdb_pwr_conv1_curr*|pdb_pwr_conv2_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files3 $attr_name)
		;;
	pdb_pwr_conv1_temp*|pdb_pwr_conv2_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files3 $attr_name)
		;;
	pdb_pwr_conv1_power*|pdb_pwr_conv2_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files3 $attr_name)
		;;
	pdb_hotswap1_in*|pdb_hotswap2_in*|pdb_hotswap3_in*|pdb_hotswap4_in*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pdb_hotswap1_curr*|pdb_hotswap2_curr*|pdb_hotswap3_curr*|pdb_hotswap4_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pdb_hotswap1_pwr*|pdb_hotswap2_pwr*|pdb_hotswap3_pwr*|pdb_hotswap4_pwr*)
		subfolder="power"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pdb_hotswap1_power*|pdb_hotswap2_power*|pdb_hotswap3_power*|pdb_hotswap4_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pdb_hotswap1_pwr*|pdb_hotswap2_pwr*|pdb_hotswap3_pwr*|pdb_hotswap4_pwr*)
		subfolder="power"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pdb_hotswap1_temp*|pdb_hotswap2_temp*|pdb_hotswap3_temp*|pdb_hotswap4_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	port_amb|fan_amb|swb_asic*|fpga|mng_amb|pdb_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	pdb_*_amb)
		subfolder="temperature"
		folder=$attr_name
		key=$attr_name
		attr_file="input"
		;;	
	drivetemp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files0 $attr_name)
		;;
	fan*)
		subfolder="fan"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	*)
		return 0
		;;
	esac

	label_name=$(hw_management_parse_labels.py --get_value --label "labels_${sku}_rev1_array" --key "$key")
	[ -z "$label_name" ] && return 0
	label_dir="$ui_path"/"$subfolder"/"$folder"/"$label_name"

	if [ "$oper" == "link" ]; then
		if [ ! -d "$label_dir" ]; then
			mkdir -p "$label_dir"
		fi
		ln -sf "$attr_full_name" "$label_dir/$attr_file"
		scale=$(hw_management_parse_labels.py --get_value --label "labels_scale_${sku}_rev1_array" --key "$key")
		[ -z "$scale" ] && return 0
		echo "$scale" > "$label_dir"/scale
	else
		if [ -z "$attr_file" ]; then
			unlink "$label_dir/$key"
		else
			unlink "$label_dir/$attr_file"
		fi

		[ -f "$label_dir"/scale ] && rm -f "$label_dir"/scale
	fi
}

make_labels "$1" "$2"
