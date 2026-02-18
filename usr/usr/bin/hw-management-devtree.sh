#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2022-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

devtr_verb_display=0
devtree_codes_file=

# Declare common associative arrays for SMBIOS System Version parsing.
declare -A board_arr=( \
	["C"]="cpu_board" \
	["S"]="switch_board" \
	["F"]="fan_board" \
	["P"]="power_board" \
	["L"]="platform_board" \
	["K"]="clock_board" \
	["O"]="port_board" \
	["D"]="dpu_board")

declare -A category_arr=( \
	["T"]="thermal" \
	["R"]="regulator" \
	["A"]="a2d" \
	["P"]="pressure" \
	["E"]="eeprom" \
	["O"]="powerconv" \
	["H"]="hotswap" \
	["G"]="gpio" \
	["N"]="network" \
	["J"]="jitter" \
	["X"]="osc" \
	["F"]="fpga" \
	["S"]="erot" \
	["C"]="rtc")

declare -A thermal_arr=( \
	["0"]="dummy" \
	["a"]="lm75" \
	["b"]="tmp102" \
	["c"]="adt75" \
	["d"]="stts751" \
	["e"]="tmp75" \
	["f"]="tmp421" \
	["g"]="lm90" \
	["h"]="emc1412" \
	["i"]="tmp411" \
	["j"]="tmp1075" \
	["k"]="tmp451" \
	["l"]="jc42")

declare -A regulator_arr=( \
	["0"]="dummy" \
	["a"]="mp2975" \
	["b"]="mp2888" \
	["c"]="tps53679" \
	["d"]="xdpe12284" \
	["e"]="152x4" \
	["f"]="pmbus" \
	["g"]="mp2891" \
	["h"]="xdpe1a2g7" \
	["i"]="mp2855" \
	["j"]="mp29816" \
	["k"]="mp2845")

declare -A a2d_arr=( \
	["0"]="dummy" \
	["a"]="max11603" \
	["b"]="ads1015")

declare -A pwr_conv_arr=( \
	["0"]="dummy" \
	["a"]="pmbus" \
	["b"]="pmbus" \
	["c"]="pmbus" \
	["d"]="raa228000" \
	["e"]="mp29502" \
	["f"]="raa228004")

declare -A hotswap_arr=( \
	["0"]="dummy" \
	["a"]="lm5066" \
	["c"]="lm5066i")

# Just currently used EEPROMs are in this mapping.
declare -A eeprom_arr=( \
	["0"]="dummy" \
	["a"]="24c02" \
	["c"]="24c08" \
	["e"]="24c32" \
	["g"]="24c128" \
	["i"]="24c512")

declare -A pressure_arr=( \
	["0"]="dummy" \
	["a"]="icp201xx" \
	["b"]="bmp390" \
	["c"]="lps22")

# Declare component alternatives associative arrays.
declare -A comex_bdw_alternatives=( \
	["mp2975_0"]="mp2975 0x61 15 comex_voltmon2" \
	["mp2975_1"]="mp2975 0x6a 15 comex_voltmon1" \
	["tps53679_0"]="tps53679 0x58 15 comex_voltmon1" \
	["tps53679_1"]="tps53679 0x61 15 comex_voltmon2" \
	["xdpe15284_0"]="xdpe12284 0x61 15 comex_voltmon1" \
	["xdpe15284_1"]="xdpe12284 0x6a 15 comex_voltmon2" \
	["max11603_0"]="max11603 0x6d 15 comex_a2d" \
	["tmp102_0"]="tmp102 0x49 15 cpu_amb" \
	["adt75_0"]="adt75 0x49 15 cpu_amb" \
	["24c32_0"]="24c32 0x50 16 cpu_info" \
	["24c512_0"]="24c512 0x50 16 cpu_info")

declare -A comex_cfl_alternatives=( \
	["mp2975_0"]="mp2975 0x6b 15 comex_voltmon1" \
	["xdpe15284_0"]="xdpe15284 0x6b 15 comex_voltmon1" \
	["max11603_0"]="max11603 0x6d 15 comex_a2d" \
	["24c32_0"]="24c32 0x50 16 cpu_info" \
	["24c512_0"]="24c512 0x50 16 cpu_info")

declare -A comex_bf3_alternatives=( \
	["mp2975_0"]="mp2975 0x6b 15 comex_voltmon1" \
	["24c512_0"]="24c512 0x50 16 cpu_info")

declare -A comex_amd_snw_alternatives=( \
	["mp2855_0"]="mp2855 0x69 15 comex_voltmon1" \
	["mp2975_1"]="mp2975 0x6a 15 comex_voltmon2" \
	["24c128_0"]="24c128 0x50 16 cpu_info" \
	["24c512_0"]="24c512 0x50 16 cpu_info")

declare -A sn58xxld_comex_amd_snw_alternatives=( \
	["mp2855_0"]="mp2855 0x69 69 comex_voltmon1" \
	["mp2975_1"]="mp2975 0x6a 69 comex_voltmon2" \
	["24c128_0"]="24c128 0x50 70 cpu_info" \
	["24c512_0"]="24c512 0x50 70 cpu_info")

declare -A mqm8700_alternatives=( \
	["max11603_0"]="max11603 0x64 5 swb_a2d" \
	["tps53679_0"]="tps53679 0x70 5 voltmon1" \
	["tps53679_1"]="tps53679 0x71 5 voltmon2" \
	["mp2975_0"]="mp2975 0x62 5 voltmon1" \
	["mp2975_1"]="mp2975 0x66 5 voltmon2" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["24c32_0"]="24c32 0x51 8 vpd_info")

declare -A msn27002_alternatives=( \
	["pmbus_0"]="pmbus 0x27 5 voltmon1" \
	["pmbus_1"]="pmbus 0x41 5 voltmon2" \
	["max11603_0"]="max11603 0x6d 5 swb_a2d" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["lm75_0"]="lm75 0x4a 7 port_amb" \
	["tmp75_0"]="tmp75 0x4a 7 port_amb" \
	["24c32_0"]="24c32 0x51 8 vpd_info" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

#declare -A msn4700_msn4600_alternatives=( \
#	["max11603_0"]="max11603 0x6d 5 swb_a2d" \
#	["xdpe12284_0"]="xdpe12284 0x62 5 voltmon1" \
#	["xdpe12284_1"]="xdpe12284 0x64 5 voltmon2" \
#	["xdpe12284_2"]="xdpe12284 0x66 5 voltmon3" \
#	["xdpe12284_3"]="xdpe12284 0x68 5 voltmon4" \
#	["xdpe12284_4"]="xdpe12284 0x6a 5 voltmon5" \
#	["xdpe12284_5"]="xdpe12284 0x6c 5 voltmon6" \
#	["xdpe12284_6"]="xdpe12284 0x6e 5 voltmon7" \
#	["mp2975_0"]="mp2975 0x62 5 voltmon1" \
#	["mp2975_1"]="mp2975 0x64 5 voltmon2" \
#	["mp2975_2"]="mp2975 0x66 5 voltmon3" \
#	["mp2975_3"]="mp2975 0x6a 5 voltmon4" \
#	["mp2975_4"]="mp2975 0x6e 5 voltmon5" \
#	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
#	["24c32_0"]="24c32 0x51 8 vpd_info")

declare -A mqm97xx_alternatives=( \
	["mp2975_0"]="mp2975 0x62 5 voltmon1" \
	["mp2888_1"]="mp2888 0x66 5 voltmon3" \
	["mp2975_2"]="mp2975 0x68 5 voltmon4" \
	["mp2975_3"]="mp2975 0x6a 5 voltmon5" \
	["mp2975_4"]="mp2975 0x6c 5 voltmon6" \
	["mp2975_5"]="mp2975 0x6e 5 voltmon7" \
	["152x4_0"]="xpde152854 0x62 5 voltmon1" \
	["152x4_1"]="xpde152854 0x68 5 voltmon4" \
	["152x4_2"]="xpde152854 0x6a 5 voltmon5" \
	["152x4_3"]="xpde152854 0x6c 5 voltmon6" \
	["max11603_0"]="max11603 0x6d 5 swb_a2d" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["adt75_0"]="adt75 0x4a 7 port_amb" \
	["stts751_0"]="stts751 0x4a 7 port_amb" \
	["24c32_0"]="24c32 0x51 8 vpd_info" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

declare -A mqm9510_alternatives=( \
	["mp2975_0"]="mp2975 0x62 5 voltmon1" \
	["mp2888_1"]="mp2888 0x66 5 voltmon2" \
	["mp2975_2"]="mp2975 0x68 5 voltmon3" \
	["mp2975_3"]="mp2975 0x6c 5 voltmon4" \
	["mp2975_4"]="mp2975 0x62 6 voltmon5" \
	["mp2888_5"]="mp2888 0x66 6 voltmon6" \
	["mp2975_6"]="mp2975 0x68 6 voltmon7" \
	["mp2975_7"]="mp2975 0x6c 6 voltmon8" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["adt75_0"]="adt75 0x4a 7 port_amb" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

declare -A mqm9520_alternatives=( \
	["mp2888_0"]="mp2975 0x66 5 voltmon1" \
	["mp2975_1"]="mp2975 0x68 5 voltmon2" \
	["mp2975_2"]="mp2975 0x6c 5 voltmon3" \
	["mp2888_3"]="mp2888 0x66 13 voltmon4" \
	["mp2975_4"]="mp2975 0x68 13 voltmon5" \
	["mp2975_5"]="mp2975 0x6c 13 voltmon6" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb1" \
	["adt75_0"]="adt75 0x4a 7 port_amb1" \
	["tmp102_1"]="tmp102 0x4a 15 port_amb2" \
	["adt75_1"]="adt75 0x4a 15 port_amb2" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

# S*RaRaRaRaRaRaRaRaRaRaRaA0TbEi
declare -A sn5600_alternatives=( \
	["max11603_0"]="max11603 0x6d 5 swb_a2d" \
	["mp2975_0"]="mp2975 0x62 5 voltmon1" \
	["mp2975_1"]="mp2975 0x63 5 voltmon2" \
	["mp2975_2"]="mp2975 0x64 5 voltmon3" \
	["mp2975_3"]="mp2975 0x65 5 voltmon4" \
	["mp2975_4"]="mp2975 0x66 5 voltmon5" \
	["mp2975_5"]="mp2975 0x67 5 voltmon6" \
	["mp2975_6"]="mp2975 0x68 5 voltmon7" \
	["mp2975_7"]="mp2975 0x69 5 voltmon8" \
	["mp2975_8"]="mp2975 0x6a 5 voltmon9" \
	["mp2975_9"]="mp2975 0x6c 5 voltmon10" \
	["mp2975_10"]="mp2975 0x6e 5 voltmon11" \
	["xdpe15284_0"]="xdpe15284 0x62 5 voltmon1" \
	["xdpe15284_1"]="xdpe15284 0x63 5 voltmon2" \
	["xdpe15284_2"]="xdpe15284 0x64 5 voltmon3" \
	["xdpe15284_3"]="xdpe15284 0x65 5 voltmon4" \
	["xdpe15284_4"]="xdpe15284 0x66 5 voltmon5" \
	["xdpe15284_5"]="xdpe15284 0x67 5 voltmon6" \
	["xdpe15284_6"]="xdpe15284 0x68 5 voltmon7" \
	["xdpe15284_7"]="xdpe15284 0x69 5 voltmon8" \
	["xdpe15284_8"]="xdpe15284 0x6a 5 voltmon9" \
	["xdpe15284_9"]="xdpe15284 0x6b 5 voltmon10" \
	["xdpe15284_10"]="xdpe15284 0x6e 5 voltmon11" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["adt75_0"]="adt75 0x4a 7 port_amb" \
	["stts751_0"]="stts751 0x4a 7 port_amb" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

declare -A sn5640_alternatives=( \
	["mp2891_0"]="mp2891 0x62 5 voltmon1" \
	["mp2891_1"]="mp2891 0x63 5 voltmon2" \
	["mp2891_2"]="mp2891 0x64 5 voltmon3" \
	["mp2891_3"]="mp2891 0x65 5 voltmon4" \
	["mp2891_4"]="mp2891 0x66 5 voltmon5" \
	["mp2891_5"]="mp2891 0x67 5 voltmon6" \
	["mp2891_6"]="mp2891 0x68 5 voltmon7" \
	["mp2891_7"]="mp2891 0x69 5 voltmon8" \
	["mp2891_8"]="mp2891 0x6a 5 voltmon9" \
	["mp2891_9"]="mp2891 0x6c 5 voltmon10" \
	["mp2891_10"]="mp2891 0x6e 5 voltmon11" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x62 5 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x63 5 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x64 5 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x65 5 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x66 5 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x67 5 voltmon6" \
	["xdpe1a2g7_6"]="xdpe1a2g7 0x68 5 voltmon7" \
	["xdpe1a2g7_7"]="xdpe1a2g7 0x69 5 voltmon8" \
	["xdpe1a2g7_8"]="xdpe1a2g7 0x6a 5 voltmon9" \
	["xdpe1a2g7_9"]="xdpe1a2g7 0x6c 5 voltmon10" \
	["xdpe1a2g7_10"]="xdpe1a2g7 0x6e 5 voltmon11" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["adt75_0"]="adt75 0x4a 7 port_amb" \
	["stts751_0"]="stts751 0x4a 7 port_amb" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

declare -A sn58xxld_swb_alternatives=( \
	["mp2891_0"]="mp2891 0x62 9 voltmon1" \
	["mp2891_1"]="mp2891 0x63 9 voltmon2" \
	["mp2891_2"]="mp2891 0x64 9 voltmon3" \
	["mp2891_3"]="mp2891 0x65 9 voltmon4" \
	["mp2891_4"]="mp2891 0x66 9 voltmon5" \
	["mp2891_5"]="mp2891 0x67 9 voltmon6" \
	["mp2891_6"]="mp2891 0x68 9 voltmon7" \
	["mp2891_7"]="mp2891 0x69 9 voltmon8" \
	["mp2891_8"]="mp2891 0x6a 9 voltmon9" \
	["mp2891_9"]="mp2891 0x6c 9 voltmon10" \
	["mp2891_10"]="mp2891 0x6e 9 voltmon11" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x62 9 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x63 9 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x64 9 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x65 9 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x66 9 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x67 9 voltmon6" \
	["xdpe1a2g7_6"]="xdpe1a2g7 0x68 9 voltmon7" \
	["xdpe1a2g7_7"]="xdpe1a2g7 0x69 9 voltmon8" \
	["xdpe1a2g7_8"]="xdpe1a2g7 0x6a 9 voltmon9" \
	["xdpe1a2g7_9"]="xdpe1a2g7 0x6c 9 voltmon10" \
	["xdpe1a2g7_10"]="xdpe1a2g7 0x6e 9 voltmon11")

declare -A p4262_alternatives=( \
	["tmp75_0"]="tmp75 0x48 7 port_temp1" \
	["adt75_0"]="adt75 0x48 7 port_temp2" \
	["tmp75_1"]="tmp75 0x49 7 port_temp2" \
	["adt75_1"]="adt75 0x49 7 port_temp2" \
	["tmp75_2"]="tmp75 0x4a 7 port_temp3" \
	["adt75_2"]="adt75 0x4a 7 port_temp3" \
	["tmp75_3"]="tmp75 0x4b 7 port_temp4" \
	["adt75_3"]="adt75 0x4b 7 port_temp4" \
	["tmp75_4"]="tmp75 0x4c 7 fan_temp1" \
	["adt75_4"]="adt75 0x4c 7 fan_temp1" \
	["tmp75_5"]="tmp75 0x4d 7 fan_temp2" \
	["adt75_5"]="adt75 0x4d 7 fan_temp2" \
	["tmp75_6"]="tmp75 0x4e 7 fan_temp3" \
	["adt75_6"]="adt75 0x4e 7 fan_temp3" \
	["tmp75_7"]="tmp75 0x4f 7 fan_temp4" \
	["adt75_7"]="adt75 0x4f 7 fan_temp4" \
	["max11603_0"]="max11603 0x6d 7 swb_a2d" \
	["24c512_0"]="24c512 0x51 8 vpd_info" \
	["24c512_1"]="24c512 0x52 8 ipmi_eeprom")

# TBD version: V0-C*A0RaEi-S*TcTcTcTcTcTcTcA0EiEiEi-P*HaEaEa
declare -A p4300_alternatives=( \
	["adt75_0"]="adt75 0x49 7 bpl_amb" \
	["adt75_1"]="adt75 0x4a 7 fiom_amb" \
	["adt75_2"]="adt75 0x4b 7 bpm_amb" \
	["adt75_3"]="adt75 0x4c 7 fiol_amb" \
	["adt75_4"]="adt75 0x4d 7 bpb_amb" \
	["adt75_5"]="adt75 0x4e 7 fior_amb" \
	["adt75_6"]="adt75 0x4f 7 bpr_amb" \
	["24c512_0"]="24c512 0x51 8 vpd_info"\
	["24c512_1"]="24c512 0x54 8 ipmi_eeprom" \
	["24c512_2"]="24c512 0x56 6 fio_info")

declare -A q3400_alternatives=( \
	["mp2891_0"]="mp2891 0x66 5 voltmon1" \
	["mp2891_1"]="mp2891 0x68 5 voltmon2" \
	["mp2891_2"]="mp2891 0x6c 5 voltmon3" \
	["mp2891_3"]="mp2891 0x66 21 voltmon4" \
	["mp2891_4"]="mp2891 0x68 21 voltmon5" \
	["mp2891_5"]="mp2891 0x6c 21 voltmon6" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x66 5 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x68 5 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x6c 5 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x66 21 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x68 21 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x6c 21 voltmon6")

declare -A q3200_alternatives=( \
	["mp2891_0"]="mp2891 0x66 5 voltmon1" \
	["mp2891_1"]="mp2891 0x68 5 voltmon2" \
	["mp2891_2"]="mp2891 0x6c 5 voltmon3" \
	["mp2891_3"]="mp2891 0x66 21 voltmon4" \
	["mp2891_4"]="mp2891 0x68 21 voltmon5" \
	["mp2891_5"]="mp2891 0x6c 21 voltmon6" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x66 5 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x68 5 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x6c 5 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x66 21 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x68 21 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x6c 21 voltmon6" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

declare -A q3450_alternatives=( \
	["mp2891_0"]="mp2891 0x66 5 voltmon1" \
	["mp2891_1"]="mp2891 0x68 5 voltmon2" \
	["mp2891_2"]="mp2891 0x6c 5 voltmon3" \
	["mp2891_3"]="mp2891 0x66 21 voltmon4" \
	["mp2891_4"]="mp2891 0x68 21 voltmon5" \
	["mp2891_5"]="mp2891 0x6c 21 voltmon6" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x66 5 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x68 5 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x6c 5 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x66 21 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x68 21 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x6c 21 voltmon6" \
	["raa228004_0"]="raa228004 0x60 3 pwr_conv" \
	["lm5066i_0"]="lm5066i 0x16 3 hotswap" )

declare -A sn4280_alternatives=( \
	["max11603_0"]="max11603 0x6d 5 swb_a2d" \
	["mp2975_0"]="mp2975 0x62 5 voltmon1" \
	["mp2975_1"]="mp2975 0x64 5 voltmon2" \
	["mp2975_2"]="mp2975 0x66 5 voltmon3" \
	["mp2975_3"]="mp2975 0x6a 5 voltmon4" \
	["mp2975_4"]="mp2975 0x6e 5 voltmon5" \
	["xdpe15284_0"]="xdpe15284 0x62 5 voltmon1" \
	["xdpe15284_1"]="xdpe15284 0x64 5 voltmon2" \
	["xdpe15284_2"]="xdpe15284 0x66 5 voltmon3" \
	["xdpe15284_3"]="xdpe15284 0x6a 5 voltmon4" \
	["xdpe15284_4"]="xdpe15284 0x6e 5 voltmon5" \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["adt75_0"]="adt75 0x4a 7 port_amb" \
	["24c512_0"]="24c512 0x51 8 vpd_info")

# V0-K*G0EgEgJa-S*RgRgRgTcTcFcEiRgRgRgSaSaGeGb-L*GbFdEiTcFdSaXbXc-P*OaOaOaOaHaEi-C*GeGdFdRiRaEg
# for JSO
declare -A n5110ld_platform_alternatives=( \
	["adt75_0"]="adt75 0x49 6 mng_amb" \
	["tmp102_0"]="tmp102 0x49 6 mng_amb" \
	["stts751_0"]="stts751 0x49 6 mng_amb" \
	["emc1412_1"]="emc1403 0x4c 6 fpga" \
	["lm90_1"]="lm90 0x4c 6 fpga" \
	["24c512_0"]="24c512 0x50 6 mgmt_fruid_info" \
	["24c512_1"]="24c512 0x51 6 mgmt_fru_info")

declare -A n5110ld_swb_alternatives=( \
	["mp2891_0"]="mp2891 0x66 5 voltmon1" \
	["mp2891_1"]="mp2891 0x68 5 voltmon2" \
	["mp2891_2"]="mp2891 0x6c 5 voltmon3" \
	["mp2891_3"]="mp2891 0x66 21 voltmon4" \
	["mp2891_4"]="mp2891 0x68 21 voltmon5" \
	["mp2891_5"]="mp2891 0x6c 21 voltmon6" \
	["mp2891_6"]="mp2891 0x66 37 voltmon7" \
	["mp2891_7"]="mp2891 0x68 37 voltmon8" \
	["mp2891_8"]="mp2891 0x6c 37 voltmon9" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x66 5 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x68 5 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x6c 5 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x66 21 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x68 21 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x6c 21 voltmon6" \
	["adt75_0"]="adt75 0x4a 7 swb_asic1" \
	["adt75_1"]="adt75 0x4b 7 swb_asic2" \
	["tmp102_0"]="tmp102 0x4a 7 swb_asic1" \
	["tmp102_1"]="tmp102 0x4b 7 swb_asic2" \
	["stts751_0"]="stts751 0x4a 7 swb_asic1" \
	["stts751_1"]="stts751 0x4b 7 swb_asic2" \
	["24c512_0"]="24c512 0x51 11 swb_info")

declare -A gb3000_swb_alternatives=( \
	["mp29816_0"]="mp29816 0x66 5 voltmon1" \
	["mp29816_1"]="mp29816 0x68 5 voltmon2" \
	["mp29816_2"]="mp29816 0x6c 5 voltmon3" \
	["mp29816_3"]="mp29816 0x66 21 voltmon4" \
	["mp29816_4"]="mp29816 0x68 21 voltmon5" \
	["mp29816_5"]="mp29816 0x6c 21 voltmon6" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x66 5 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x68 5 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x6c 5 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x66 21 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x68 21 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x6c 21 voltmon6" \
	["24c512_0"]="24c512 0x51 11 swb_info" \
	["lm5066i_0"]="lm5066i 0x12 4 pdb_hotswap1" \
	["lm5066_0"]="lm5066i 0x12 4 pdb_hotswap1" \
	["raa228004_0"]="raa228004 0x60 4 pwr_conv1" \
	["mp29502_0"]="mp29502 0x2e 4 pwr_conv1")

declare -A gb200hd_swb_alternatives=( \
	["mp2891_0"]="mp2891 0x66 5 voltmon1" \
	["mp2891_1"]="mp2891 0x68 5 voltmon2" \
	["mp2891_2"]="mp2891 0x6c 5 voltmon3" \
	["mp2891_3"]="mp2891 0x66 21 voltmon4" \
	["mp2891_4"]="mp2891 0x68 21 voltmon5" \
	["mp2891_5"]="mp2891 0x6c 21 voltmon6" \
	["mp2891_6"]="mp2891 0x66 51 voltmon7" \
	["mp2891_7"]="mp2891 0x68 51 voltmon8" \
	["mp2891_8"]="mp2891 0x6c 51 voltmon9" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x66 5 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x68 5 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x6c 5 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x66 21 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x68 21 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x6c 21 voltmon6" \
	["xdpe1a2g7_6"]="xdpe1a2g7 0x66 51 voltmon7" \
	["xdpe1a2g7_7"]="xdpe1a2g7 0x68 51 voltmon8" \
	["xdpe1a2g7_8"]="xdpe1a2g7 0x6c 51 voltmon9" \
	["adt75_0"]="adt75 0x4a 7 swb_asic1" \
	["adt75_1"]="adt75 0x4b 7 swb_asic2" \
	["tmp102_0"]="tmp102 0x4a 7 swb_asic1" \
	["tmp102_1"]="tmp102 0x4b 7 swb_asic2" \
	["stts751_0"]="stts751 0x4a 7 swb_asic1" \
	["stts751_1"]="stts751 0x4b 7 swb_asic2" \
	["24c512_0"]="24c512 0x51 11 swb_info")

declare -A n61xxld_swb_alternatives=( \
	["mp29816_0"]="mp29816 0x66 8 voltmon1" \
	["mp29816_1"]="mp29816 0x68 8 voltmon2" \
	["mp29816_2"]="mp29816 0x6c 8 voltmon3" \
	["mp29816_3"]="mp29816 0x6e 8 voltmon4" \
	["mp29816_4"]="mp29816 0x66 24 voltmon5" \
	["mp29816_5"]="mp29816 0x68 24 voltmon6" \
	["mp29816_6"]="mp29816 0x6c 24 voltmon7" \
	["mp29816_7"]="mp29816 0x6e 24 voltmon8" \
	["mp29816_8"]="mp29816 0x66 40 voltmon9" \
	["mp29816_9"]="mp29816 0x68 40 voltmon10" \
	["mp29816_10"]="mp29816 0x6c 40 voltmon11" \
	["mp29816_11"]="mp29816 0x6e 40 voltmon12" \
	["mp29816_12"]="mp29816 0x66 56 voltmon13" \
	["mp29816_13"]="mp29816 0x68 56 voltmon14" \
	["mp29816_14"]="mp29816 0x6c 56 voltmon15" \
	["mp29816_15"]="mp29816 0x6e 56 voltmon16" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x66 8 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x68 8 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x6c 8 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x6e 8 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x66 24 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x68 24 voltmon6" \
	["xdpe1a2g7_6"]="xdpe1a2g7 0x6c 24 voltmon7" \
	["xdpe1a2g7_7"]="xdpe1a2g7 0x6e 24 voltmon8" \
	["xdpe1a2g7_8"]="xdpe1a2g7 0x66 40 voltmon9" \
	["xdpe1a2g7_9"]="xdpe1a2g7 0x68 40 voltmon10" \
	["xdpe1a2g7_10"]="xdpe1a2g7 0x6c 40 voltmon11" \
	["xdpe1a2g7_11"]="xdpe1a2g7 0x6e 40 voltmon12" \
	["xdpe1a2g7_12"]="xdpe1a2g7 0x66 56 voltmon13" \
	["xdpe1a2g7_13"]="xdpe1a2g7 0x68 56 voltmon14" \
	["xdpe1a2g7_14"]="xdpe1a2g7 0x6c 56 voltmon15" \
	["xdpe1a2g7_15"]="xdpe1a2g7 0x6e 56 voltmon16" \
	["24c512_0"]="24c512 0x51 14 swb_info" \
	["lm5066i_0"]="lm5066i 0x12 7 pdb_hotswap1" \
	["mp5926_0"]="mp5926 0x12 7 pdb_hotswap1" \
	["raa228004_0"]="raa228004 0x60 7 pwr_conv1" \
	["raa228004_1"]="raa228004 0x61 7 pwr_conv2" \
	["mp29502_0"]="mp29502 0x2e 7 pwr_conv1" \
	["mp29502_1"]="mp29502 0x2c 7 pwr_conv2")

# Devices located on SN66XX_LD switch board
declare -A sn66xxld_swb_alternatives=( \
	["mp29816_0"]="mp29816 0x61 15 voltmon1" \
	["mp29816_1"]="mp29816 0x62 15 voltmon2" \
	["mp29816_2"]="mp29816 0x63 15 voltmon3" \
	["mp29816_3"]="mp29816 0x64 15 voltmon4" \
	["mp29816_4"]="mp29816 0x65 15 voltmon5" \
	["mp29816_5"]="mp29816 0x66 15 voltmon6" \
	["mp29816_6"]="mp29816 0x67 15 voltmon7" \
	["mp29816_7"]="mp29816 0x6a 15 voltmon8" \
	["mp29816_8"]="mp29816 0x60 16 voltmon9" \
	["mp29816_9"]="mp29816 0x61 16 voltmon10" \
	["mp29816_10"]="mp29816 0x62 16 voltmon11" \
	["mp29816_11"]="mp29816 0x63 16 voltmon12" \
	["mp29816_12"]="mp29816 0x64 16 voltmon13" \
	["mp29816_13"]="mp29816 0x65 16 voltmon14" \
	["mp29816_14"]="mp29816 0x66 16 voltmon15" \
	["mp29816_15"]="mp29816 0x67 16 voltmon16" \
	["mp29816_16"]="mp29816 0x68 16 voltmon17" \
	["mp29816_17"]="mp29816 0x69 16 voltmon18" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x61 15 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x62 15 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x63 15 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x64 15 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x65 15 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x66 15 voltmon6" \
	["xdpe1a2g7_6"]="xdpe1a2g7 0x67 15 voltmon7" \
	["xdpe1a2g7_7"]="xdpe1a2g7 0x6a 15 voltmon8" \
	["xdpe1a2g7_8"]="xdpe1a2g7 0x61 16 voltmon9" \
	["xdpe1a2g7_9"]="xdpe1a2g7 0x62 16 voltmon10" \
	["xdpe1a2g7_10"]="xdpe1a2g7 0x63 16 voltmon11" \
	["xdpe1a2g7_11"]="xdpe1a2g7 0x64 16 voltmon12" \
	["xdpe1a2g7_12"]="xdpe1a2g7 0x65 16 voltmon13" \
	["xdpe1a2g7_13"]="xdpe1a2g7 0x66 16 voltmon14" \
	["xdpe1a2g7_14"]="xdpe1a2g7 0x67 16 voltmon15" \
	["xdpe1a2g7_15"]="xdpe1a2g7 0x68 16 voltmon16" \
	["xdpe1a2g7_16"]="xdpe1a2g7 0x69 16 voltmon17" \
	["xdpe1a2g7_17"]="xdpe1a2g7 0x6a 16 voltmon18" \
	["24c512_0"]="24c512 0x51 24 swb_info")

# Devices located on SN66XX_LD port board
declare -A sn66xxld_port_alternatives=( \
	["mp29816_0"]="mp29816 0x68 15 voltmon19" \
	["mp29816_1"]="mp29816 0x69 15 voltmon20" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x68 15 voltmon19" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x69 15 voltmon20")

# Devices located on SN66XX_LD power board
declare -A sn66xxld_pwr_alternatives=( \
	["raa228004_0"]="raa228004 0x60 6 pdb_pwr_conv1" \
	["mp29502_0"]="mp29502 0x2e 6 pdb_pwr_conv1" \
	["lm5066i_0"]="lm5066i 0x12 6 pdb_hotswap1" \
	["mp5926_0"]="mp5926 0x12 6 pdb_hotswap1" \
	["tmp451_0"]="tmp451 0x4c 6 pdb_temp1")

# Devices located on SN66XX_LD platform board
declare -A sn66xxld_platform_alternatives=( \
	["24c512_1"]="24c512 0x51 1 vpd_info" \
	["jc42_0"]="jc42 0x52 10 somdimm_temp1" \
	["jc42_1"]="jc42 0x53 10 somdimm_temp2" \
	["mp2845_0"]="mp2845 0x69 5 comex_voltmon1" \
	["mp2975_1"]="mp2975 0x6a 5 comex_voltmon2")

# Devices located on SN68XX_LD switch board
declare -A sn68xxld_swb_alternatives=( \
	["mp29816_0"]="mp29816 0x60 15 voltmon1" \
	["mp29816_1"]="mp29816 0x61 15 voltmon2" \
	["mp29816_2"]="mp29816 0x62 15 voltmon3" \
	["mp29816_3"]="mp29816 0x63 15 voltmon4" \
	["mp29816_4"]="mp29816 0x64 15 voltmon5" \
	["mp29816_5"]="mp29816 0x65 15 voltmon6" \
	["mp29816_6"]="mp29816 0x66 15 voltmon7" \
	["mp29816_7"]="mp29816 0x67 15 voltmon8" \
	["mp29816_8"]="mp29816 0x68 15 voltmon9" \
	["mp29816_9"]="mp29816 0x69 15 voltmon10" \
	["mp29816_10"]="mp29816 0x6a 15 voltmon11" \
	["mp29816_11"]="mp29816 0x6b 15 voltmon12" \
	["mp29816_12"]="mp29816 0x6c 15 voltmon13" \
	["mp29816_13"]="mp29816 0x6d 15 voltmon14" \
	["mp29816_14"]="mp29816 0x6e 15 voltmon15" \
	["mp29816_15"]="mp29816 0x6f 15 voltmon16" \
	["xdpe1a2g7_0"]="xdpe1a2g7 0x60 15 voltmon1" \
	["xdpe1a2g7_1"]="xdpe1a2g7 0x61 15 voltmon2" \
	["xdpe1a2g7_2"]="xdpe1a2g7 0x62 15 voltmon3" \
	["xdpe1a2g7_3"]="xdpe1a2g7 0x63 15 voltmon4" \
	["xdpe1a2g7_4"]="xdpe1a2g7 0x64 15 voltmon5" \
	["xdpe1a2g7_5"]="xdpe1a2g7 0x65 15 voltmon6" \
	["xdpe1a2g7_6"]="xdpe1a2g7 0x66 15 voltmon7" \
	["xdpe1a2g7_7"]="xdpe1a2g7 0x67 15 voltmon8" \
	["xdpe1a2g7_8"]="xdpe1a2g7 0x68 15 voltmon9" \
	["xdpe1a2g7_9"]="xdpe1a2g7 0x69 15 voltmon10" \
	["xdpe1a2g7_10"]="xdpe1a2g7 0x6a 15 voltmon11" \
	["xdpe1a2g7_11"]="xdpe1a2g7 0x6b 15 voltmon12" \
	["xdpe1a2g7_12"]="xdpe1a2g7 0x6c 15 voltmon13" \
	["xdpe1a2g7_13"]="xdpe1a2g7 0x6d 15 voltmon14" \
	["xdpe1a2g7_14"]="xdpe1a2g7 0x6e 15 voltmon15" \
	["xdpe1a2g7_15"]="xdpe1a2g7 0x6f 15 voltmon16")

# Old connection table assumes that Fan amb temp sensors is located on main/switch board.
# Actually it's located on fan board and in this way it will be passed through SMBIOS
# string generated from Agile settings. Thus, declare also Fan board alternatives.
declare -A fan_type0_alternatives=( \
	["tmp102_0"]="tmp102 0x49 7 fan_amb" \
	["adt75_0"]="adt75 0x49 7 fan_amb" \
	["stts751_0"]="stts751 0x49 7 fan_amb")

declare -A fan_type1_alternatives=( \
	["tmp102_0"]="tmp102 0x49 6 fan_amb" \
	["adt75_0"]="adt75 0x49 6 fan_amb" \
	["stts751_0"]="stts751 0x49 6 fan_amb" \
	["lm5066i_0"]="lm5066i 0x14 6 fan_hotswap1")

# Currently system can have just multiple clock boards.
declare -A clk_type0_alternatives=( \
	["24c128_0"]="24c128 0x54 5 clk_eeprom1" \
	["24c128_1"]="24c128 0x57 5 clk_eeprom2")

# Remove ICP201xx pressure sensors from SMBIOS BOM mechanism
# These pressure sensors don't have upstream kernel driver.
# They will be instantiated manually in OPT-OS only.
declare -A pwr_type0_alternatives=( \
	["pmbus_0"]="pmbus 0x10 4 pwr_conv1" \
	["pmbus_1"]="pmbus 0x11 4 pwr_conv2" \
	["pmbus_2"]="pmbus 0x13 4 pwr_conv3" \
	["pmbus_3"]="pmbus 0x15 4 pwr_conv4" \
#	["icp201xx_0"]="icp201xx 0x63 4 press_sens1" \
#	["icp201xx_1"]="icp201xx 0x64 4 press_sens2" \
	["max11603_0"]="max11603 0x6d 4 pwrb_a2d")

declare -A pwr_type1_alternatives=( \
	["lm5066_0"]="lm5066 0x11 4 pdb_hotswap1" \
	["pmbus_0"]="pmbus 0x12 4 pdb_pwr_conv1" \
	["pmbus_1"]="pmbus 0x13 4 pdb_pwr_conv2" \
	["pmbus_2"]="pmbus 0x16 4 pdb_pwr_conv3" \
	["pmbus_3"]="pmbus 0x17 4 pdb_pwr_conv4" \
	["pmbus_4"]="pmbus 0x1b 4 pdb_pwr_conv5" \
	["tmp75_0"]="tmp75 0x4d 4 pdb_temp1" \
	["adt75_0"]="tmp75 0x4d 4 pdb_temp1" \
	["tmp75_1"]="tmp75 0x4e 4 pdb_temp2" \
	["adt75_1"]="tmp75 0x4e 4 pdb_temp2" \
	["24c02_0"]="24c02 0x50 4 pdb_info" \
	["24c02_1"]="24c02 0x50 7 cable_cartridge_eeprom")

# for p4300
declare -A pwr_type2_alternatives=( \
	["lm5066_0"]="lm5066 0x40 4 pdb_hotswap1" \
	["24c02_0"]="24c02 0x50 3 cable_cartridge_eeprom" \
	["24c02_1"]="24c02 0x50 11 cable_cartridge2_eeprom")

# for JSO
# P*OaOaOaOaH0Ei
declare -A pwr_type3_alternatives=( \
	["pmbus_0"]="pmbus 0x10 4 pwr_conv1" \
	["raa228000_0"]="raa228000 0x60 4 pwr_conv1" \
	["pmbus_1"]="pmbus 0x11 4 pwr_conv2" \
	["raa228000_1"]="raa228000 0x61 4 pwr_conv2" \
	["pmbus_2"]="pmbus 0x13 4 pwr_conv3" \
	["pmbus_3"]="pmbus 0x15 4 pwr_conv4" \
	["lm5066_0"]="lm5066i 0x16 4 pdb_hotswap1" \
	["24c512_0"]="24c512 0x51 4 pdb_eeprom")

# for DGX platform PDB -1 - pwr_conv, 1- HotPlug, 2 - thermal, 1 - eeprom 24c02 	
# P*HaHaTjTkEaOdOd
declare -A pwr_type4_alternatives=( \
	["raa228000_0"]="raa228000 0x61 4 pdb_pwr_conv1" \
	["raa228004_0"]="raa228004 0x61 4 pdb_pwr_conv1" \
	["lm5066_0"]="lm5066i 0x12 4 pdb_hotswap1" \
	["lm5066_1"]="lm5066i 0x14 4 pdb_hotswap2" \
	["tmp451_0"]="tmp451 0x4c 4 pdb_mos_amb" \
	["tmp1075_0"]="tmp1075 0x4e 4 pdb_intel_amb" \
	["24c02_0"]="24c02 0x50 4 pdb_eeprom")

declare -A sn58xxld_pwr_alternatives=( \
	["raa228004_0"]="raa228004 0x60 7 pdb_pwr_conv1" \
	["mp29502_0"]="mp29502 0x60 7 pdb_pwr_conv1" \
	["lm5066i_0"]="lm5066i 0x12 7 pdb_hotswap1" \
	["mp5926_0"]="mp5926 0x12 7 pdb_hotswap1" \
	["tmp451_1"]="tmp451 0x4c 7 pdb_mosfet_amb1")

declare -A q3401_pwr_alternatives=( \
	["raa228004_0"]="raa228004 0x60 4 pdb_pwr_conv1" \
	["raa228004_1"]="raa228004 0x61 4 pdb_pwr_conv2" \
	["lm5066i_0"]="lm5066i 0x12 4 pdb_hotswap1" \
	["lm5066_0"]="lm5066i 0x12 4 pdb_hotswap1" \
	["mp5926_0"]="mp5926 0x12 4 pdb_hotswap1" \
	["lm5066i_1"]="lm5066i 0x14 4 pdb_hotswap2" \
	["lm5066_1"]="lm5066i 0x14 4 pdb_hotswap2" \
	["mp5926_1"]="mp5926 0x14 4 pdb_hotswap2" \
	["tmp1075_0"]="tmp1075 0x4e 4 pdb_brd_amb" \
	["tmp411_0"]="tmp411 0x4e 4 pdb_brd_amb" \
	["tmp451_0"]="tmp451 0x4e 4 pdb_brd_amb" \
	["tmp1075_1"]="tmp1075 0x4c 4 pdb_mos_amb" \
	["tmp411_1"]="tmp411 0x4c 4 pdb_mos_amb" \
	["tmp451_1"]="tmp451 0x4c 4 pdb_mos_amb" \
	["24c02_0"]="24c02 0x50 4 pdb_eeprom")

# P*HaEaOfTk
declare -A gb300_pwr_type1_alternatives=( \
	["raa228004_0"]="raa228004 0x60 4 pwr_conv1" \
	["mp29502_0"]="mp29502 0x2e 4 pwr_conv1" \
	["lm5066i_0"]="lm5066i 0x12 4 pdb_hotswap1" \
	["lm5066_0"]="lm5066i 0x12 4 pdb_hotswap1" \
	["mp5926_0"]="mp5926 0x12 4 pdb_hotswap1" \
	["tmp1075_0"]="tmp1075 0x4c 4 pdb_mos_amb" \
	["tmp411_0"]="tmp411 0x4c 4 pdb_mos_amb" \
	["tmp451_0"]="tmp451 0x4c 4 pdb_mos_amb" \
	["24c02_0"]="24c02 0x50 4 pdb_eeprom")

declare -A platform_type0_alternatives=( \
	["max11603_0"]="max11603 0x6d 15 carrier_a2d" \
	["lm75_0"]="lm75 0x49 17 fan_amb" \
	["tmp75_0"]="tmp75 0x49 7 fan_amb")

# System EEPROM located on platform board
declare -A platform_type1_alternatives=( \
	["24c512_0"]="24c512 0x51 8 vpd_info")

declare -A platform_type2_alternatives=( \
	["24c512_0"]="24c512 0x51 1 vpd_info")

# Devices located on N61XX_LD platform board
declare -A n61xxld_platform_alternatives=( \
	["24c512_1"]="24c512 0x51 1 vpd_info" \
	["mp2855_0"]="mp2855 0x69 6 comex_voltmon1" \
	["mp2975_1"]="mp2975 0x6a 6 comex_voltmon2")

# Port ambient sensor located on a separate module board
declare -A port_type0_alternatives=( \
	["tmp102_0"]="tmp102 0x4a 7 port_amb" \
	["adt75_0"]="adt75 0x4a 7 port_amb" \
	["stts751_0"]="stts751 0x4a 7 port_amb")

declare -A dpu_type0_alternatives=( \
	["tmp421_0"]="tmp421 0x1f 18 cx_amb" \
	["mp2975_0"]="mp2975 0x69 18 voltmon1" \
	["mp2975_1"]="mp2975 0x6a 18 voltmon2" \
	["xdpe15284_0"]="xdpe15284 0x69 18 voltmon1" \
	["xdpe15284_1"]="xdpe15284 0x6a 18 voltmon2")

declare -A comex_alternatives
declare -A swb_alternatives
declare -A fan_alternatives
declare -A clk_alternatives
declare -A pwr_alternatives
declare -A platform_alternatives
declare -A port_alternatives
declare -A dpu_alternatives
declare -A board_alternatives

devtr_validate_system_ver_str()
{
	IFS='-'
	system_ver_arr=($system_ver_str)
	unset IFS
	local i=0

# Don't report error in 2 first checks as theoretically it can be a case
# of not customized/old SMBIOS field. Output is just in debug mode.
	substr_len=${#system_ver_arr[0]}
	if [[ ! ${system_ver_arr[0]} =~ V[0-9] ]] || [ "$substr_len" -ne 2 ]; then
		if [ $devtr_verb_display -eq 1 ]; then
			log_info "DBG SMBIOS BOM: string is not correct. Problem in Version part: ${system_ver_arr[0]}"
		fi
		return 1
	fi
	
	arr_len=${#system_ver_arr[@]}
	if [ "$arr_len" -lt 2 ]; then
		if [ $devtr_verb_display -eq 1 ]; then
			log_info "DBG SMBIOS BOM: string is not correct. Problem in number of string components: ${arr_len}"
		fi
		return 1
	fi

	# Currenly just one encode mechanism version exist.
	encode_ver=${system_ver_arr[0]:1:1}
	if [ "$encode_ver" -ne 0 ]; then
		log_err "SMBIOS BOM: unsupported encode version."
		return 2
	fi

	return 0
}

devtr_clean()
{
	if [ -e "$devtree_file" ]; then
		rm -f "$devtree_file"
	fi
	if [ -e "$devtree_codes_file" ]; then
		rm -f "$devtree_codes_file"
	fi
}

# Check if system has SMBIOS BOM changes mechanism support.
# If yes, init appropriate associative arrays.
# Jaguar, Leopard, Gorilla are added just for debug.
# This mechanism is enabled on new systems starting from Moose.
devtr_check_supported_system_init_alternatives()
{
	case $cpu_type in
		$BDW_CPU)
			if [ -e "$config_path"/cpu_brd_bus_offset ]; then
				cpu_brd_bus_offset=$(< $config_path/cpu_brd_bus_offset)
				for key in "${!comex_bdw_alternatives[@]}"; do
					curr_component=(${comex_bdw_alternatives["$key"]})
					curr_component[2]=$((curr_component[2]-base_cpu_bus_offset+cpu_brd_bus_offset))
					comex_alternatives["$key"]="${curr_component[0]} ${curr_component[1]} ${curr_component[2]} ${curr_component[3]}"
				done
			else
				for key in "${!comex_bdw_alternatives[@]}"; do
					comex_alternatives["$key"]="${comex_bdw_alternatives["$key"]}"
				done
			fi
			;;
		$CFL_CPU)
			if [ -e "$config_path"/cpu_brd_bus_offset ]; then
				cpu_brd_bus_offset=$(< $config_path/cpu_brd_bus_offset)
				for key in "${!comex_cfl_alternatives[@]}"; do
					curr_component=(${comex_cfl_alternatives["$key"]})
					curr_component[2]=$((curr_component[2]-base_cpu_bus_offset+cpu_brd_bus_offset))
					comex_alternatives["$key"]="${curr_component[0]} ${curr_component[1]} ${curr_component[2]} ${curr_component[3]}"
				done
			else
				for key in "${!comex_cfl_alternatives[@]}"; do
					comex_alternatives["$key"]="${comex_cfl_alternatives["$key"]}"
				done
			fi
			;;
		$BF3_CPU)
			if [ -e "$config_path"/cpu_brd_bus_offset ]; then
				cpu_brd_bus_offset=$(< $config_path/cpu_brd_bus_offset)
				for key in "${!comex_bf3_alternatives[@]}"; do
					curr_component=(${comex_bf3_alternatives["$key"]})
					curr_component[2]=$((curr_component[2]-base_cpu_bus_offset+cpu_brd_bus_offset))
					comex_alternatives["$key"]="${curr_component[0]} ${curr_component[1]} ${curr_component[2]} ${curr_component[3]}"
				done
			else
				for key in "${!comex_bf3_alternatives[@]}"; do
					comex_alternatives["$key"]="${comex_bf3_alternatives["$key"]}"
				done
			fi
			;;
		$AMD_SNW_CPU)
			sku=$(< $sku_file)
			case "$sku" in
			HI181|HI182)
				for key in "${!sn58xxld_comex_amd_snw_alternatives[@]}"; do
						comex_alternatives["$key"]="${sn58xxld_comex_amd_snw_alternatives["$key"]}"
				done
			;;
			*)
				if [ -e "$config_path"/cpu_brd_bus_offset ]; then
					cpu_brd_bus_offset=$(< $config_path/cpu_brd_bus_offset)
					for key in "${!comex_amd_snw_alternatives[@]}"; do
						curr_component=(${comex_amd_snw_alternatives["$key"]})
						curr_component[2]=$((curr_component[2]-base_cpu_bus_offset+cpu_brd_bus_offset))
						comex_alternatives["$key"]="${curr_component[0]} ${curr_component[1]} ${curr_component[2]} ${curr_component[3]}"
					done
				else
					for key in "${!comex_amd_snw_alternatives[@]}"; do
						comex_alternatives["$key"]="${comex_amd_snw_alternatives["$key"]}"
					done
				fi
				;;
			esac
			;;
		$AMD_V3000_CPU)
			;;
		$DNV_CPU)
			# Silent exit
			return 1
			;;
		*)
			log_info "SMBIOS BOM info: unsupported cpu_type: ${cpu_type}"
			return 1
			;;
	esac
	case $board_type in
#		VMOD0005)
#			case $sku in
#				HI100)	# MQM8700
#					for key in "${!mqm8700_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm8700_alternatives["$key"]}"
#					done
#					;;
#				*)
#					return 1
#					;;
#			esac
#			for key in "${!fan_type0_alternatives[@]}"; do
#				fan_alternatives["$key"]="${fan_type0_alternatives["$key"]}"
#			done
#			return 0
#			;;
#		VMOD0010)
#			case $sku in
#				HI122|HI123|HI124|HI125)	# Leopard, Liger, Tigon, Leo
#					for key in "${!msn4700_msn4600_alternatives[@]}"; do
#						swb_alternatives["$key"]="${msn4700_msn4600_alternatives["$key"]}"
#					done
#					;;
#				HI130)	# MQM9700
#					for key in "${!mqm97xx_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm97xx_alternatives["$key"]}"
#					done
#					;;
#				HI140) # MQM9520
#					for key in "${!mqm9520_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm9520_alternatives["$key"]}"
#					done
#					;;
#				HI141) # MQM9510
#					for key in "${!mqm9510_alternatives[@]}"; do
#						swb_alternatives["$key"]="${mqm9510_alternatives["$key"]}"
#					done
#					;;
#				*)
#					return 1
#					;;
#			esac
#			for key in "${!fan_type0_alternatives[@]}"; do
#				fan_alternatives["$key"]="${fan_type0_alternatives["$key"]}"
#			done
#			return 0
#			;;
		VMOD0010)
			case $sku in
			HI173)	# MQM9701
				for key in "${!mqm97xx_alternatives[@]}"; do
					swb_alternatives["$key"]="${mqm97xx_alternatives["$key"]}"
				done
				for key in "${!pwr_type3_alternatives[@]}"; do
					pwr_alternatives["$key"]="${pwr_type4_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			for key in "${!fan_type0_alternatives[@]}"; do
				fan_alternatives["$key"]="${fan_type0_alternatives["$key"]}"
			done
			return 0
			;;
		VMOD0009)
			case $sku in
			HI117)
				for key in "${!msn27002_alternatives[@]}"; do
					swb_alternatives["$key"]="${msn27002_alternatives["$key"]}"
				done
				for key in "${!platform_type0_alternatives[@]}"; do
					platform_alternatives["$key"]="${platform_type0_alternatives["$key"]}"
				done
				;;
			*)
				return 1
				;;
			esac
			return 0
			;;
		VMOD0013)
			case $sku in
				HI144|HI147|HI148)	# ToDo Separate index HI148 if it will be required
					for key in "${!sn5600_alternatives[@]}"; do
						swb_alternatives["$key"]="${sn5600_alternatives["$key"]}"
					done
					for key in "${!pwr_type0_alternatives[@]}"; do
						pwr_alternatives["$key"]="${pwr_type0_alternatives["$key"]}"
					done
					;;
				HI174)
					for key in "${!sn5600_alternatives[@]}"; do
						swb_alternatives["$key"]="${sn5600_alternatives["$key"]}"
					done
					for key in "${!pwr_type4_alternatives[@]}"; do
						pwr_alternatives["$key"]="${pwr_type4_alternatives["$key"]}"
					done
					;;
				*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			for key in "${!fan_type1_alternatives[@]}"; do
				fan_alternatives["$key"]="${fan_type1_alternatives["$key"]}"
			done
			for key in "${!clk_type0_alternatives[@]}"; do
				clk_alternatives["$key"]="${clk_type0_alternatives["$key"]}"
			done
			return 0
			;;
		VMOD0017)
			case $sku in
			HI152)
				for key in "${!p4262_alternatives[@]}"; do
					swb_alternatives["$key"]="${p4262_alternatives["$key"]}"
				done
				for key in "${!pwr_type1_alternatives[@]}"; do
					pwr_alternatives["$key"]="${pwr_type1_alternatives["$key"]}"
				done
				;;
			HI159)
				for key in "${!p4300_alternatives[@]}"; do
					swb_alternatives["$key"]="${p4300_alternatives["$key"]}"
				done
				for key in "${!pwr_type2_alternatives[@]}"; do
					pwr_alternatives["$key"]="${pwr_type2_alternatives["$key"]}"
				done
				;;
			esac
			return 0
			;;
		VMOD0018)
			case $sku in
			HI157)
				for key in "${!q3200_alternatives[@]}"; do
					swb_alternatives["$key"]="${q3200_alternatives["$key"]}"
				done
				for key in "${!fan_type1_alternatives[@]}"; do
					fan_alternatives["$key"]="${fan_type1_alternatives["$key"]}"
				done
				for key in "${!port_type0_alternatives[@]}"; do
					port_alternatives["$key"]="${port_type0_alternatives["$key"]}"
				done
				;;
			HI158)
				for key in "${!q3400_alternatives[@]}"; do
					swb_alternatives["$key"]="${q3400_alternatives["$key"]}"
				done
				for key in "${!platform_type1_alternatives[@]}"; do
					platform_alternatives["$key"]="${platform_type1_alternatives["$key"]}"
				done
				for key in "${!fan_type1_alternatives[@]}"; do
					fan_alternatives["$key"]="${fan_type1_alternatives["$key"]}"
				done
				for key in "${!port_type0_alternatives[@]}"; do
					port_alternatives["$key"]="${port_type0_alternatives["$key"]}"
				done
				;;
			HI175|HI178)
				for key in "${!q3450_alternatives[@]}"; do
					swb_alternatives["$key"]="${q3450_alternatives["$key"]}"
				done
				for key in "${!platform_type1_alternatives[@]}"; do
					platform_alternatives["$key"]="${platform_type1_alternatives["$key"]}"
				done
				for key in "${!port_type0_alternatives[@]}"; do
					port_alternatives["$key"]="${port_type0_alternatives["$key"]}"
				done
				;;
			HI179)
				for key in "${!q3400_alternatives[@]}"; do
					swb_alternatives["$key"]="${q3400_alternatives["$key"]}"
				done

				for key in "${!platform_type1_alternatives[@]}"; do
					platform_alternatives["$key"]="${platform_type1_alternatives["$key"]}"
				done

				for key in "${!q3401_pwr_alternatives[@]}"; do
					pwr_alternatives["$key"]="${q3401_pwr_alternatives["$key"]}"
				done

				for key in "${!fan_type1_alternatives[@]}"; do
					fan_alternatives["$key"]="${fan_type1_alternatives["$key"]}"
				done

				for key in "${!port_type0_alternatives[@]}"; do
					port_alternatives["$key"]="${port_type0_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			return 0
			;;
		VMOD0019)
			case $sku in
			HI160)
				for key in "${!sn4280_alternatives[@]}"; do
					swb_alternatives["$key"]="${sn4280_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			for key in "${!fan_type1_alternatives[@]}"; do
				fan_alternatives["$key"]="${fan_type1_alternatives["$key"]}"	# ToDo check exact fan board sensors
			done
			for key in "${!dpu_type0_alternatives[@]}"; do
				dpu_alternatives["$key"]="${dpu_type0_alternatives["$key"]}"
			done
			return 0
			;;
		VMOD0021)
			case $sku in
			HI162|HI166|HI167|HI169|HI170)
				for key in "${!n5110ld_swb_alternatives[@]}"; do
					swb_alternatives["$key"]="${n5110ld_swb_alternatives["$key"]}"
				done

				for key in "${!pwr_type3_alternatives[@]}"; do
					pwr_alternatives["$key"]="${pwr_type3_alternatives["$key"]}"
				done

				for key in "${!n5110ld_platform_alternatives[@]}"; do
					platform_alternatives["$key"]="${n5110ld_platform_alternatives["$key"]}"
				done
				;;
			HI176)
				for key in "${!gb3000_swb_alternatives[@]}"; do
					swb_alternatives["$key"]="${gb3000_swb_alternatives["$key"]}"
				done

				for key in "${!gb300_pwr_type1_alternatives[@]}"; do
					pwr_alternatives["$key"]="${gb300_pwr_type1_alternatives["$key"]}"
				done

				for key in "${!n5110ld_platform_alternatives[@]}"; do
					platform_alternatives["$key"]="${n5110ld_platform_alternatives["$key"]}"
				done
				;;
			HI177)
				for key in "${!gb200hd_swb_alternatives[@]}"; do
					swb_alternatives["$key"]="${gb200hd_swb_alternatives["$key"]}"
				done

				for key in "${!gb300_pwr_type1_alternatives[@]}"; do
					pwr_alternatives["$key"]="${gb300_pwr_type1_alternatives["$key"]}"
				done

				for key in "${!n5110ld_platform_alternatives[@]}"; do
					platform_alternatives["$key"]="${n5110ld_platform_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			;;
		VMOD0022)
			case $sku in
			HI171|HI172)
				for key in "${!sn5640_alternatives[@]}"; do
					swb_alternatives["$key"]="${sn5640_alternatives["$key"]}"
				done

				for key in "${!fan_type1_alternatives[@]}"; do
					fan_alternatives["$key"]="${fan_type1_alternatives["$key"]}"
				done

				for key in "${!clk_type0_alternatives[@]}"; do
					clk_alternatives["$key"]="${clk_type0_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			;;
		VMOD0023)
			case $sku in
			HI180)
				for key in "${!n61xxld_swb_alternatives[@]}"; do
					swb_alternatives["$key"]="${n61xxld_swb_alternatives["$key"]}"
				done

				for key in "${!n61xxld_platform_alternatives[@]}"; do
					platform_alternatives["$key"]="${n61xxld_platform_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			;;
		VMOD0024)
			case $sku in
			HI181|HI182)
				for key in "${!sn58xxld_swb_alternatives[@]}"; do
					swb_alternatives["$key"]="${sn58xxld_swb_alternatives["$key"]}"
				done

				for key in "${!platform_type2_alternatives[@]}"; do
					platform_alternatives["$key"]="${platform_type2_alternatives["$key"]}"
				done

				for key in "${!sn58xxld_pwr_alternatives[@]}"; do
					pwr_alternatives["$key"]="${sn58xxld_pwr_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			;;
		VMOD0025)
			case $sku in
			HI193)
				for key in "${!sn66xxld_swb_alternatives[@]}"; do
					swb_alternatives["$key"]="${sn66xxld_swb_alternatives["$key"]}"
				done

				for key in "${!sn66xxld_platform_alternatives[@]}"; do
					platform_alternatives["$key"]="${sn66xxld_platform_alternatives["$key"]}"
				done

				for key in "${!sn66xxld_pwr_alternatives[@]}"; do
					pwr_alternatives["$key"]="${sn66xxld_pwr_alternatives["$key"]}"
				done

				for key in "${!sn66xxld_port_alternatives[@]}"; do
					port_alternatives["$key"]="${sn66xxld_port_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			;;
		VMOD0027)
			case $sku in
			HI191|H183|HI195)
				for key in "${!sn68xxld_swb_alternatives[@]}"; do
					swb_alternatives["$key"]="${sn68xxld_swb_alternatives["$key"]}"
				done

				for key in "${!sn66xxld_platform_alternatives[@]}"; do
					platform_alternatives["$key"]="${sn66xxld_platform_alternatives["$key"]}"
				done

				for key in "${!sn66xxld_pwr_alternatives[@]}"; do
					pwr_alternatives["$key"]="${sn66xxld_pwr_alternatives["$key"]}"
				done
				;;
			*)
				log_info "SMBIOS BOM info: unsupported board_type: ${board_type}, sku ${sku}"
				return 1
				;;
			esac
			;;
		*)
			log_info "SMBIOS BOM info: unsupported board_type: ${board_type}"
			return 1
			;;
	esac
}

devtr_check_board_components()
{
	local board_str=$1
	local board_num=1
	local board_bus_offset=0
	local board_vr_num=
	local board_pwr_conv_num=
	local board_hotswap_num=
	local board_temp_sens_num=
	local board_name_pfx=
	local board_type=static
#	local board_addr_offset=0
	local comp_arr

	case $cpu_type in
	$ARMv7_CPU)
		# Shell command "fold" is not available on this platform.
		# Iterate over the string with a step size of 2
		for ((i=0; i<${#board_str}; i+=2)); do
			local pair="${board_str:i:2}"
			comp_arr+=("$pair")
		done
		;;
	*)
		local comp_arr=($(echo "$board_str" | fold -w2))
		;;
	esac

	local board_key=${comp_arr[0]:0:1}
	local board_name=${board_arr[$board_key]}

	if [ $devtr_verb_display -eq 1 ]; then
		log_info "DBG SMBIOS BOM: Board: ${board_name}"
	fi

	board_alternatives=()

	case $board_key in
		C)	# CPU/Comex board
			for key in "${!comex_alternatives[@]}"; do
				board_alternatives["$key"]="${comex_alternatives["$key"]}"
			done
			;;
		S)	# Switch board
			# There can be several switch boards (e.g on q3400)
			if [ -e "$config_path"/swb_brd_num ]; then
				board_num=$(< $config_path/swb_brd_num)
				board_name_pfx=swb
			fi
			if [ -e "$config_path"/swb_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/swb_brd_bus_offset)
			fi
			if [ -e "$config_path"/swb_brd_vr_num ]; then
				board_vr_num=$(< $config_path/swb_brd_vr_num)
			fi
			for key in "${!swb_alternatives[@]}"; do
				board_alternatives["$key"]="${swb_alternatives["$key"]}"
			done
			;;
		F)	# Fan board
			for key in "${!fan_alternatives[@]}"; do
				board_alternatives["$key"]="${fan_alternatives["$key"]}"
			done
			;;
		P)	# Power board
			# There can be several power boards (e.g on sn58xxld)
			if [ -e "$config_path"/pwr_brd_num ]; then
				board_num=$(< $config_path/pwr_brd_num)
				board_name_pfx=pdb
			fi
			if [ -e "$config_path"/pwr_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/pwr_brd_bus_offset)
			fi
			if [ -e "$config_path"/pwr_brd_pwr_conv_num ]; then
				board_pwr_conv_num=$(< $config_path/pwr_brd_pwr_conv_num)
			fi
			if [ -e "$config_path"/pwr_brd_hotswap_num ]; then
				board_hotswap_num=$(< $config_path/pwr_brd_hotswap_num)
			fi
			if [ -e "$config_path"/pwr_brd_temp_sens_num ]; then
				board_temp_sens_num=$(< $config_path/pwr_brd_temp_sens_num)
			fi
			for key in "${!pwr_alternatives[@]}"; do
				board_alternatives["$key"]="${pwr_alternatives["$key"]}"
			done
			;;
		L)	# Platform or Carrier board
			for key in "${!platform_alternatives[@]}"; do
				board_alternatives["$key"]="${platform_alternatives["$key"]}"
			done
			;;
		K)	# Clock board
			# There can be several clock boards (e.g on SN5600)
			if [ -e "$config_path"/clk_brd_num ]; then
				board_num=$(< $config_path/clk_brd_num)
				board_name_pfx=clk
			fi
			if [ -e "$config_path"/clk_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/clk_brd_bus_offset)
			fi
#			if [ -e "$config_path"/clk_brd_addr_offset ]; then
#				board_addr_offset=$(< $config_path/clk_brd_addr_offset)
#			fi
			for key in "${!clk_alternatives[@]}"; do
				board_alternatives["$key"]="${clk_alternatives["$key"]}"
			done
			;;
		O)	# Port board
			for key in "${!port_alternatives[@]}"; do
				board_alternatives["$key"]="${port_alternatives["$key"]}"
			done
			;;
		D)	# DPU board
			# There are several DPU boards (SN4280)
			if [ -e "$config_path"/dpu_num ]; then
				board_num=$(< $config_path/dpu_num)
				board_name_pfx=dpu
			fi
			# Check if board and his components are "static", always available
			# or they are "dynamic". I.e., board can powered-off / powered-on.
			if [ -e "$config_path"/dpu_board_type ]; then
				board_type=$(< $config_path/dpu_board_type)
			fi
			if [ -e "$config_path"/dpu_brd_bus_offset ]; then
				board_bus_offset=$(< $config_path/dpu_brd_bus_offset)
			fi
			for key in "${!dpu_alternatives[@]}"; do
				board_alternatives["$key"]="${dpu_alternatives["$key"]}"
			done
			;;
		*)
			log_err "SMBIOS BOM: incorrect encoded board, board key ${board_key}"
			return 1
			;;
	esac

	local i=0; t_cnt=0; r_cnt=0; e_cnt=0; a_cnt=0; p_cnt=0; o_cnt=0; h_cnt=0; brd=0
	curr_component=()
	for comp in "${comp_arr[@]}"; do
		# Skip 1st tuple in board string. It desctibes board name and number.
		# All other tuples describe components.
		if [ $i -eq 0 ]; then
		        i=$((i + 1))
		        continue
		fi
		category_key=${comp:0:1}
		component_key=${comp:1:2}

		category=${category_arr[$category_key]}  # Optional, just for print.
		case $category_key in
			T)	# Thermal Sensors
				# Don't process removed component.
				if [ "$component_key" == "0" ]; then
					t_cnt=$((t_cnt+1))
					continue
				fi
				component_name=${thermal_arr[$component_key]}
				alternative_key="${component_name}_${t_cnt}"
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
					fi
					if [ ! -z "${board_name_pfx}" ]; then
						if [ -z "${board_temp_sens_num}" ]; then
							curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
						else
							sens_name=$(echo ${curr_component[3]} | grep -o '[^0-9]\+')
							sens_num=$(echo ${curr_component[3]} | grep -o '[0-9]\+')
							curr_component[3]=${sens_name}$((sens_num+brd*board_temp_sens_num))
						fi
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${t_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							echo -n "${curr_component[@]} " >> "$dynamic_boards_path"/"$board_name_str"
						else
							echo -n "${curr_component[@]} " >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[@]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				t_cnt=$((t_cnt+1))
				;;
			R)	# Voltage Regulators
				if [ "$component_key" == "0" ]; then
					r_cnt=$((r_cnt+1))
					continue
				fi
				component_name=${regulator_arr[$component_key]}
				alternative_key="${component_name}_${r_cnt}"
				# Q3400 and Q3450 systems have 2 switch boards, each with multiple VRs
				# SN5800 systems have 4 switch boards, each with multiple VRs
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
					fi
					if [ ! -z "${board_name_pfx}" ]; then
						if [ -z "${board_vr_num}" ]; then
							curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
						else
							vr_name=$(echo ${curr_component[3]} | grep -o '[^0-9]\+')
							vr_num=$(echo ${curr_component[3]} | grep -o '[0-9]\+')
							curr_component[3]=${vr_name}$((vr_num+brd*board_vr_num))
						fi
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${r_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							echo -n "${curr_component[@]} " >> "$dynamic_boards_path"/"$board_name_str"
						else
							echo -n "${curr_component[@]} " >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[@]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				r_cnt=$((r_cnt+1))
				;;
			E)	# Eeproms
				if [ "$component_key" == "0" ]; then
					e_cnt=$((e_cnt+1))
					continue
				fi
				component_name=${eeprom_arr[$component_key]}
				alternative_key="${component_name}_${e_cnt}"
				# SN5600 system has 2 Clock boards. Just EEPROM is accessed on these boards.
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
# There is no currently address offset. Leave commented just for possible future use
#					if [ $board_addr_offset -ne 0 ]; then
#						curr_component[1]=$((curr_component[1]+board_addr_offset*brd))
#						curr_component[1]=0x$(echo "obase=16; ${curr_component[1]}"|bc)
#					fi
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
						curr_component[2]=0x$(echo "obase=16; ${curr_component[2]}"|bc)
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${e_cnt}"
					else
						echo -n "${curr_component[@]} " >> "$devtree_file"
						if [ $devtr_verb_display -eq 1 ]; then
							if [ $board_num -gt 1 ]; then
								board_name_str="${board_name}${n}"
							else
								board_name_str="$board_name"
							fi
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[@]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				e_cnt=$((e_cnt+1))
				;;
			A)	# A2D
				if [ "$component_key" == "0" ]; then
					a_cnt=$((a_cnt+1))
					continue
				fi
				component_name=${a2d_arr[$component_key]}
				alternative_key="${component_name}_${a_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				if [ -z "${alternative_comp[0]}" ]; then
					log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${a_cnt}"
				else
					echo -n "${alternative_comp} " >> "$devtree_file"
					if [ $devtr_verb_display -eq 1 ]; then
						log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
						echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
					fi
				fi
				a_cnt=$((a_cnt+1))
				;;
			P)	# Pressure Sensors
				if [ "$component_key" == "0" ]; then
					p_cnt=$((p_cnt+1))
					continue
				fi
				component_name=${pressure_arr[$component_key]}
				alternative_key="${component_name}_${p_cnt}"
				alternative_comp=${board_alternatives[$alternative_key]}
				if [ -z "${alternative_comp[0]}" ]; then
					log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${p_cnt}"
				else
					echo -n "${alternative_comp} " >> "$devtree_file"
					if [ $devtr_verb_display -eq 1 ]; then
						log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${alternative_comp}, category key: ${category_key}, device code: ${component_key}"
						echo -n " ${board_name} ${category_key} ${component_key} " >> "$devtree_codes_file"
					fi
				fi
				p_cnt=$((p_cnt+1))
				;;
			O)	# Power Convertors
				if [ "$component_key" == "0" ]; then
					o_cnt=$((o_cnt+1))
					continue
				fi
				component_name=${pwr_conv_arr[$component_key]}
				alternative_key="${component_name}_${o_cnt}"
				# Q3450 system has 2 switch boards, each with 1 power converter
				# SN5800 system has 4 power boards, each with 1 power converter
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
					fi
					if [ ! -z "${board_name_pfx}" ]; then
						if [ -z "${board_pwr_conv_num}" ]; then
							curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
						else
							pwr_conv_name=$(echo ${curr_component[3]} | grep -o '[^0-9]\+')
							pwr_conv_num=$(echo ${curr_component[3]} | grep -o '[0-9]\+')
							curr_component[3]=${pwr_conv_name}$((pwr_conv_num+brd*board_pwr_conv_num))
						fi
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${o_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							echo -n "${curr_component[@]} " >> "$dynamic_boards_path"/"$board_name_str"
						else
							echo -n "${curr_component[@]} " >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[@]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				o_cnt=$((o_cnt+1))
				;;
			H)	# Hot-swap
				if [ "$component_key" == "0" ]; then
					h_cnt=$((h_cnt+1))
					continue
				fi
				component_name=${hotswap_arr[$component_key]}
				alternative_key="${component_name}_${h_cnt}"
				# Q3450 system has 2 switch boards, each with 1 hot-swap controller
				# SN5800 system has 4 power boards, each with 1 hot-swap controller
				for ((brd=0, n=1; brd<board_num; brd++, n++)) do
					curr_component=(${board_alternatives[$alternative_key]})
					if [ $board_bus_offset -ne 0 ]; then
						curr_component[2]=$((curr_component[2]+board_bus_offset*brd))
					fi
					if [ ! -z "${board_name_pfx}" ]; then
						if [ -z "${board_hotswap_num}" ]; then
							curr_component[3]=${board_name_pfx}${n}_${curr_component[3]}
						else
							hotswap_name=$(echo ${curr_component[3]} | grep -o '[^0-9]\+')
							hotswap_num=$(echo ${curr_component[3]} | grep -o '[0-9]\+')
							curr_component[3]=${hotswap_name}$((hotswap_num+brd*board_hotswap_num))
						fi
					fi
					# Check if component from SMBIOS BOM string is defined in layout
					if [ -z "${curr_component[0]}" ]; then
						log_info "SMBIOS BOM info: component not defined in layout/ignored: ${board_name} ${category}, category key: ${category_key}, device code: ${component_key}, num: ${o_cnt}"
					else
						if [ $board_num -gt 1 ]; then
							board_name_str="${board_name}${n}"
						else
							board_name_str="$board_name"
						fi
						# Components of dynamic boards write to separate per board devtree file
						if [ "${board_type}" == "dynamic" ]; then
							echo -n "${curr_component[@]} " >> "$dynamic_boards_path"/"$board_name_str"
						else
							echo -n "${curr_component[@]} " >> "$devtree_file"
						fi
						if [ $devtr_verb_display -eq 1 ]; then
							log_info "DBG SMBIOS BOM: ${board_name} ${category} component - ${curr_component[@]}, category key: ${category_key}, device code: ${component_key}"
							echo -n " ${board_name_str} ${category_key} ${component_key} " >> "$devtree_codes_file"
						fi
					fi
				done
				h_cnt=$((h_cnt+1))
				;;
			G)	# GPIO Expander
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			N)	# Network Adapter
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			J)	# Jitter Attenuator
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			X)	# Oscillator
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			F)	# FPGA
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			S)	# EROT
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			C)	# RTC
				log_info "SMBIOS BOM info: ${board_name} ${category} component is ignored"
				;;
			*)
				log_err "SMBIOS BOM: incorrect encoded category, category key ${category_key}"
				return 1
				;;
		esac
	done
	return 0
}

# This is a main function for SMBIOS alternative BOM mechanism.
# It's called at early step hw-management init and can be also called
# from standalone debug script hw-management-devtree-check.sh.
# It's called without parameters in normal flow.
# It's called with 3 or 7 parameters in debug/simulation mode.
# $1 - SMBIOS system version string
# $2 - verbose simulation output and display of device tree
# $3 - create and use additional files with device codes
# $4 - board type (VMOD)
# $5 - system SKU
# $6 - location of devtree file
# $7 - CPU type: BDW_CPU, CFL_CPU, BF3_CPU
devtr_check_smbios_device_description()
{
	system_ver_str=$(<$system_ver_file)
	# Check if system supports this mechanism.
	if ! devtr_check_supported_system_init_alternatives ; then
		return 1
	fi

	# Check if the call was done from standalone debug script with simualtion variables.
	if [ $# -eq 3 ]; then
		system_ver_str="$1"
		devtr_verb_display=$2
		devtree_codes_file="$3"
	elif [ $# -eq 7 ]; then
		system_ver_str="$1"
		devtr_verb_display=$2
		devtree_codes_file="$3"
		board_type="$4"
		sku="$5"
		devtree_file="$6"
		cpu_type="$7"
	fi

	devtr_clean

	if [ $devtr_verb_display -eq 1 ]; then
		log_info "DBG SMBIOS BOM: system version string: ${system_ver_str}"
	fi
	devtr_validate_system_ver_str
	rc=$?
	if [ $rc -ne 0 ]; then
		devtr_clean
		return $rc
	fi

	local i=0
	for substr in "${system_ver_arr[@]}"; do
		# Skip 1st substring in system version string.
		# It's used as valid id and describes encoding version
		# that can be changed in the future.
		if [ $devtr_verb_display -eq 1 ]; then
			log_info "DBG SMBIOS BOM: Substring ${substr}"
		fi
		if [ $i -eq 0 ]; then
			i=$((i + 1))
			continue
		fi
		if ! devtr_check_board_components "$substr" ; then
			devtr_clean
			return 1
		fi
	done
	return 0
}

