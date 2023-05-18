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
set -x
hw_management_path=/var/run/hw-management
ui_path=$hw_management_path/ui 

declare -A label_array=( \
	["comex_voltmon1_in1"]="PMIC-1_PSU_12V_Rail_in1" \
	["comex_voltmon1_in2"]="PMIC-1_PSU_12V_Rail_in2" \
	["comex_voltmon1_in3"]="PMIC-1_ASIC_0.8V_VCORE_Rail_(out)" \
	["comex_voltmon1_in4"]="PMIC-1_ASIC_1.2V_Rail_(out)" \
	["comex_voltmon1_temp1"]="PMIC-1_Temp_1" \
	["comex_voltmon1_temp2"]="PMIC-1_Temp_2" \
	["comex_voltmon1_power1"]="PMIC-1_ASIC_0.8V_VCORE_Rail_Pwr_(out)" \
	["comex_voltmon1_power1"]="PMIC-1_ASIC_1.2V_Rail_Pwr_(out)" \
	["comex_voltmon1_curr1"]="PMIC-1_ASIC_0.8V_VCORE_Rail_Curr_(out)" \
	["comex_voltmon1_curr2"]="PMIC-1_ASIC_1.2V_Rail_Curr_out" \
	["voltmon1_in1"]="PMIC-1_PSU_12V_Rail_(in1)" \
	["voltmon1_in2"]="PMIC-1_PSU_12V_Rail_(in2)" \
	["voltmon1_in3"]="PMIC-1_ASIC_0.8V_VCORE_Rail_(out)" \
	["voltmon1_in4"]="PMIC-1_ASIC_1.2V_Rail_(out)" \
	["voltmon1_temp1"]="PMIC-1_Temp_1" \
	["voltmon1_temp2"]="PMIC-1_Temp_2" \
	["voltmon1_power1"]="PMIC-1_ASIC_0.8V_VCORE_Rail_Pwr_(out)" \
	["voltmon1_power2"]="PMIC-1_ASIC_1.2V_Rail_Pwr_(out)" \
	["voltmon1_curr1"]="PMIC-1_ASIC_0.8V_VCORE_Rail_Curr_(out)" \
	["voltmon1_curr2"]="PMIC-1_ASIC_1.2V_Rail_Curr_(out)" \
)

declare -A labels_mqm9700_rev1_array=( \
	["asic_amb"]="Ambient_ASIC_Temp" \
	["fan_amb"]="Ambient_Fan_Side_Temp_(air_intake)" \
	["port_amb"]="Ambient_Port_Side_Temp_(air_exhaust)" \
	["comex_amb"]="Ambient_COMEX_Temp" \
	["voltmon1_in1"]="PMIC-1_PSU_12V_Rail_(in1)" \
	["voltmon1_in2"]="PMIC-1_OSFP_PORTS_P01_P08_Rail_(out1)" \
	["voltmon1_in3"]="PMIC-1_OSFP_PORTS_P09_P16_Rail_(out2)" \
	["voltmon1_temp1"]="PMIC-1_OSFP_PORTS_P01_P08_Temp_1" \
	["voltmon1_temp2"]="PMIC-1_OSFP_PORTS_P09_P16_Temp_2" \
	["voltmon1_power1"]="PMIC-1_12V_OSFP_PORT_P01_P16_(in)" \
	["voltmon1_power2"]="PMIC-1_OSFP_P01_P08_Rail_Pwr_(out1)" \
	["voltmon1_power3"]="PMIC-1_OSFP_P09_P16_Rail_Pwr_(out2)" \
	["voltmon1_curr1"]="PMIC-1_12V_OSFP_P01_P08_Rail_Curr_(in1)" \
	["voltmon1_curr2"]="PMIC-1_OSFP_P01_P8_Rail_Curr_(out1)" \
	["voltmon1_curr3"]="PMIC-1_OSFP_P09_P16_Rail_Curr_(out2)" \
	["voltmon1_curr4"]="PMIC-1_OSFP_P09_P16_Rail_Curr_(out2)" \
	["voltmon2_in1"]="PMIC-2_PSU_12V_Rail_(in1)" \
	["voltmon2_in2"]="PMIC-2_OSFP_PORTS_P17_P24_Rail_(out1)" \
	["voltmon2_in3"]="PMIC-2_OSFP_PORTS_P25_P32_Rail_(out2)" \
	["voltmon2_temp1"]="PMIC-2_OSFP_PORTS_P17_P24_Temp_1" \
	["voltmon2_temp2"]="PMIC-2_OSFP_PORTS_P25_P32_Temp_2" \
	["voltmon2_power1"]="PMIC-2_12V_OSFP_PORT_P17_P32_(in)" \
	["voltmon2_power2"]="PMIC-2_OSFP_P17_P24_Rail_Pwr_(out1)" \
	["voltmon2_power3"]="PMIC-2_OSFP_P25_P32_Rail_Pwr_(out2)" \
	["voltmon2_curr1"]="PMIC-2_12V_OSFP_P17_P24_Rail_Curr_(in1)" \
	["voltmon2_curr2"]="PMIC-2_OSFP_P17_P24_Rail_Curr_(out1)" \
	["voltmon2_curr3"]="PMIC-2_OSFP_P25_P32_Rail_Curr_(out2)" \
	["voltmon3_in1"]="PMIC-3_PSU_12V_Rail_(in1)" \
	["voltmon3_in2"]="PMIC-3_ASIC_VCORE_MAIN_Rail_(out1)" \
	["voltmon3_temp1"]="PMIC-3_ASIC_VCORE_MAIN_Temp_1" \
	["voltmon3_power1"]="PMIC-3_12V_ASIC_VCORE_MAIN_Rail_Pwr_(in)" \
	["voltmon3_power2"]="PMIC-3_ASIC_VCORE_MAIN_Rail_Pwr_(out1)" \
	["voltmon3_curr1"]="PMIC-3_12V_ASIC_VCORE_MAIN_Rail_Curr_(in1)" \
	["voltmon3_curr2"]="PMIC-3_ASIC_VCORE_MAIN_Rail_Curr_(out1)" \
	["voltmon4_in1"]="PMIC-4_PSU_12V_Rail_(in)" \
	["voltmon4_in2"]="PMIC-4_HVDD_1.2V_EAST_Rail_(out1)" \
	["voltmon4_in3"]="PMIC-4_DVDD_0.9V_EAST_Rail_(out2)" \
	["voltmon4_temp1"]="PMIC-4_HVDD_1.2V_EAST_Rail_Temp" \
	["voltmon4_power1"]="PMIC-4_12V_HVDD_1.2V_DVDD_0.9V_EAST_(in)" \
	["voltmon4_power2"]="PMIC-4_HVDD_1.2V_EAST_Rail_Pwr_(out1)" \
	["voltmon4_power3"]="PMIC-4_DVDD_0.9V_EAST_Rail_Pwr_(out2)" \
	["voltmon4_curr1"]="PMIC-4_12V_HVDD_1.2V_EAST_Rail_Curr_(in)" \
	["voltmon4_curr2"]="PMIC-4_HVDD_1.2V_EAST_Rail_Curr_(out1)" \
	["voltmon4_curr3"]="PMIC-4_DVDD_0.9V_EAST_Rail_Curr_(out2)" \
	["voltmon5_in1"]="PMIC-5_PSU_12V_Rail_(in)" \
	["voltmon5_in2"]="PMIC-5_HVDD_1.2V_WEST_Rail_(out1)" \
	["voltmon5_in3"]="PMIC-5_DVDD_0.9V_WEST_Rail_(out2)" \
	["voltmon5_temp1"]="PMIC-5_HVDD_1.2V_WEST_Rail_Temp" \
	["voltmon5_power1"]="PMIC-5_12V_HVDD_1.2V_DVDD_0.9V_WEST_(in)" \
	["voltmon5_power2"]="PMIC-5_HVDD_1.2V_WEST_Rail_Pwr_(out1)" \
	["voltmon5_power3"]="PMIC-5_DVDD_0.9V_WEST_Rail_Pwr_(out2)" \
	["voltmon5_curr1"]="PMIC-5_12V_HVDD_1.2V_WEST_Rail_Curr_(in)" \
	["voltmon5_curr2"]="PMIC-5_HVDD_1.2V_WEST_Rail_Curr_(out1)" \
	["voltmon5_curr3"]="PMIC-5_DVDD_0.9V_WEST_Rail_Curr_(out2)" \
	["voltmon6_in1"]="PMIC-6_PSU_12V_Rail_(in1)" \
	["voltmon6_in2"]="PMIC-6_PSU_12V_Rail_(in2)" \
	["voltmon6_in3"]="PMIC-6_HVDD_1.2V_WEST_Rail_(out1)" \
	["voltmon6_in4"]="PMIC-6_DVDD_0.9V_WEST_Rail_(out2)" \
	["voltmon6_temp1"]="PMIC-6_HVDD_1.2V_WEST_Rail_Temp1" \
	["voltmon6_temp2"]="PMIC-6_DVDD_0.9V_WEST_Rail_Temp2" \
	["voltmon6_power1"]="PMIC-6_12V_HVDD_1.2V_DVDD_0.9V_WEST_(in1)" \
	["voltmon6_power2"]="PMIC-6_12V_HVDD_1.2V_DVDD_0.9V_WEST_(in2)" \
	["voltmon6_power3"]="PMIC-6_HVDD_1.2V_WEST_Rail_Pwr_(out1)" \
	["voltmon6_power4"]="PMIC-6_DVDD_0.9V_WEST_Rail_Pwr_(out2)" \
	["voltmon6_curr1"]="PMIC-6_12V_HVDD_1.2V_WEST_Rail_Curr_(in1)" \
	["voltmon6_curr2"]="PMIC-6_12V_DVDD_0.9V_WEST_Rail_Curr_(in2)" \
	["voltmon6_curr3"]="PMIC-6_HVDD_1.2V_WEST_Rail_Curr_(out1)" \
	["voltmon6_curr4"]="PMIC-6_DVDD_0.9V_WEST_Rail_Curr_(out2)" \
	["comex_voltmon1_in1"]="PMIC-1_PSU_12V_Rail_(vin)" \
	["comex_voltmon1_in2"]="PMIC-1_COMEX_VCORE_(out1)" \
	["comex_voltmon1_in3"]="PMIC-1_COMEX_VCCSA_(out2)" \
	["comex_voltmon1_temp1"]="PMIC-1_Temp" \
	["comex_voltmon1_power1"]="PMIC-1_COMEX_Pwr_(pin)" \
	["comex_voltmon1_power2"]="PMIC-1_COMEX_VCORE_Pwr_(pout1)" \
	["comex_voltmon1_power3"]="PMIC-1_COMEX_VCCSA_Pwr_(pout2)" \
	["comex_voltmon1_curr1"]="PMIC-1_COMEX_Curr_(iin)" \
	["comex_voltmon1_curr2"]="PMIC-1_COMEX_VCORE_Rail_Curr_(out1)" \
	["comex_voltmon1_curr3"]="PMIC-1_COMEX_VCCSA_Rail_Curr_(out2)" \
	["psu1_volt_in"]="PSU-1(L)_220V_Rail_(in)" \
	["psu1_volt"]="PSU-1(L)_12V_Rail_(out)" \
	["psu1_fan"]="PSU-1(L)_Fan_1" \
	["psu1_temp1"]="PSU-1(L)_Temp_1" \
	["psu1_temp2"]="PSU-1(L)_Temp_2" \
	["psu1_temp3"]="PSU-1(L)_Temp_3" \
	["psu1_power_in"]="PSU-1(L)_220V_Rail_Pwr_(in)" \
	["psu1_power"]="PSU-1(L)_12V_Rail_Pwr_(out)" \
	["psu1_curr_in"]="PSU-1(L)_220V_Rail_Curr_(in)" \
	["psu1_curr"]="PSU-1(L)_12V_Rail_Curr_(out)" \
	["psu2_volt_in"]="PSU-2(R)_220V_Rail_(in)" \
	["psu2_volt"]="PSU-2(R)_12V_Rail_(out)" \
	["psu2_fan"]="PSU-2(R)_Fan_1" \
	["psu2_temp1"]="PSU-2(R)_Temp_1" \
	["psu2_temp2"]="PSU-2(R)_Temp_2" \
	["psu2_temp3"]="PSU-2(R)_Temp_3" \
	["psu2_power_in"]="PSU-2(R)_220V_Rail_Pwr_(in)" \
	["psu2_power"]="PSU-2(R)_12V_Rail_Pwr_(out)" \
	["psu2_curr_in"]="PSU-2(R)_220V_Rail_Curr_(in)" \
	["psu2_curr"]="PSU-2(R)_12V_Rail_Curr_(out)" \
	["fan1"]="Chassis_Fan_Drawer-1_Tach_1" \
	["fan2"]="Chassis_Fan_Drawer-1_Tach_2" \
	["fan3"]="Chassis_Fan_Drawer-2_Tach_1" \
	["fan4"]="Chassis_Fan_Drawer-2_Tach_2" \
	["fan5"]="Chassis_Fan_Drawer-3_Tach_1" \
	["fan6"]="Chassis_Fan_Drawer-3_Tach_2" \
	["fan7"]="Chassis_Fan_Drawer-4_Tach_1" \
	["fan8"]="Chassis_Fan_Drawer-4_Tach_2" \
	["fan9"]="Chassis_Fan_Drawer-5_Tach_1" \
	["fan10"]="Chassis_Fan_Drawer-5_Tach_2" \
	["fan11"]="Chassis_Fan_Drawer-6_Tach_1" \
	["fan12"]="Chassis_Fan_Drawer-6_Tach_2" \
	["fan13"]="Chassis_Fan_Drawer-7_Tach_1" \
	["fan14"]="Chassis_Fan_Drawer-7_Tach_2" \
)

declare -A labels_scale_mqm9700_rev1_array=( \
	["voltmon1_in2"]="2" \
	["voltmon1_in3"]="2" \
	["voltmon2_in2"]="2" \
	["voltmon2_in3"]="2" \
)

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

# Create labels
# $1 - file path
make_labels()
{
	local attr_full_name="$1"
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
		echo 4 subfolder $subfolder key $key folder  $folder attr_name $attr_name attr_file $attr_file >> /tmp/test
		;;
	voltmon1_in*|voltmon2_in*|voltmon3_in*|voltmon4_in*|voltmon5_in*|voltmon6_in*|voltmon7_in*|voltmon8_in*|voltmon9_in*|voltmon10_in*|voltmon11_in*|voltmon12_in*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	voltmon1_power*|voltmon2_power*|voltmon3_power*|voltmon4_power*|voltmon5_power*|voltmon6_power*|voltmon7_power*|voltmon8_power*|voltmon9_power*|voltmon10_power*|voltmon11_power*|voltmon12_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	voltmon1_curr*|voltmon2_curr*|voltmon3_curr*|voltmon4_curr*|voltmon5_curr*|voltmon6_curr*|voltmon7_curr*|voltmon8_curr*|voltmon9_curr*|voltmon10_curr*|voltmon11_curr*|voltmon12_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	voltmon1_temp*|voltmon2_temp*|voltmon3_temp*|voltmon4_temp*|voltmon5_temp*|voltmon6_temp*|voltmon7_temp*|voltmon8_temp*|voltmon9_temp*|voltmon10_temp*|voltmon11_temp*|voltmon12_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_volt*|psu2_volt*|psu3_volt*|psu4_volt*)
		subfolder="voltage"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_power*|psu2_power*|psu3_power*|psu4_power*)
		subfolder="power"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_curr*|psu2_curr*|psu1_curr*|psu2_curr*)
		subfolder="current"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_temp*|psu2_temp*|psu3_temp*|psu4_temp*)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	psu1_fan*|psu2_fan*|psu3_fan*|psu4_fan*)
		subfolder="fan"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	port_amb|fan_amb)
		subfolder="temperature"
		read folder key attr_file < <(get_label_files1 $attr_name)
		;;
	fan*)
		subfolder="fan"
		read folder key attr_file < <(get_label_files2 $attr_name)
		;;
	*)
		return 0
		;;
	esac

	label_name=${labels_mqm9700_rev1_array[$key]}
	[ -z "$label_name" ] && return 0
	label_dir="$ui_path"/"$folder"/"$subfolder"/"$label_name"
	if [ ! -d "$label_dir" ]; then
		mkdir -p "$label_dir"
	fi
	ln -sf "$attr_full_name" "$label_dir/$attr_file"
	scale=${labels_scale_mqm9700_rev1_array[$key]}
	[ -z "$scale" ] && return 0
	echo "$scale" > "$label_dir"/scale
}

# Check SKU and run the below only for relevant.
# Obtain label file (/var/run/hw-management/config/lm-sensors-labels).
make_labels "$1"
