#!/bin/bash
################################################################################
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

### BEGIN INIT INFO
# Provides: hw-management
# Required-Start: $local_fs $network $remote_fs $syslog
# Required-Stop: $local_fs $network $remote_fs $syslog
# Default-Start: 2 3 4 5
# Default-Stop:  0 1 6
# Short-Description: <Chassis Hardware management of Mellanox systems>
# Description: <Chassis Hardware management of Mellanox systems>
### END INIT INFO
# Supported systems:
#  SN274*
#  SN21*
#  SN24*
#  SN27*|SB*|SX*
#  SN201*
#  QMB7*|SN37*|SN34*
#  SN38*|SN37*|SN34*|SN35*
#  SN47*
#  QM97*
# Available options:
# start	- load the kernel drivers required for chassis hardware management,
#	  connect drivers to devices.
# stop	- disconnect drivers from devices, unload kernel drivers, which has
#	  been loaded.
#

source hw-management-helpers.sh
[ -f "$board_type_file" ] && board_type=$(< $board_type_file) || board_type="Unknown"
[ -f "$sku_file" ] && sku=$(< $sku_file) || sku="Unknown"
source hw-management-devtree.sh
# Local constants and variables

asic_control=1
i2c_asic_addr=0x48
i2c_asic_addr_name=0048
psu1_i2c_addr=0x59
psu2_i2c_addr=0x58
psu3_i2c_addr=0x5b
psu4_i2c_addr=0x5a
psu5_i2c_addr=0x5d
psu6_i2c_addr=0x5c
psu7_i2c_addr=0x5e
psu8_i2c_addr=0x5f
psu_count=2
fan_psu_default=0x3c
fan_command=0x3b
fan_config_command=0x3a
fan_speed_units=0x90
chipup_delay_default=0
hotplug_psus=2
hotplug_fans=6
hotplug_pwrs=2
hotplug_pdbs=0
hotplug_linecards=0
erot_count=0
health_events_count=0
pwr_events_count=0
dpu_count=0
i2c_bus_def_off_eeprom_cpu=16
i2c_comex_mon_bus_default=15
lm_sensors_configs_path="/etc/hw-management-sensors"
thermal_control_configs_path="/etc/hw-management-thermal"
i2c_freq_400=0xf
i2c_freq_reg=0x2004
# ASIC PCIe Ids.
spc3_pci_id=cf70
spc4_pci_id=cf80
spc5_pci_id=cf82
spc6_pci_id=cf84
quantum2_pci_id=d2f2
quantum3_pci_id=d2f4
quantum4_pci_id=d2f8
nv3_pci_id=1af1
nv4_pci_id=22a3
nv4_rev_a1_pci_id=22a4
dpu_bf3_pci_id=a2dc
# Need to get the correct PCI bus numbers for DPUs
dpu_pci_addr_amd=(06:00.0 05:00.0 01:00.0 02:00.0)
dpu_pci_addr_cfl=(01:00.0 02:00.0 06:00.0 08:00.0)
leakage_count=0
leakage_rope_count=0
asic_chipup_retry=2
device_connect_retry=2
chipup_log_size=4096
reset_dflt_attr_num=18
smart_switch_reset_attr_num=17
n51xx_reset_attr_num=22
sn58xx_reset_attr_num=15
n61xx_reset_attr_num=17
q3401_reset_attr_num=17
chipup_retry_count=3

# Set FAN speed tolerance based on spec +-30%
fan_speed_tolerance=30
minimal_unsupported=0
dummy_psus_supported=0
sed_pba_guid=0d1d8ac9-9958-4e34-aae6-5236e3232bb5

mctp_bus=""
mctp_addr=""

# Topology description and driver specification for ambient sensors and for
# ASIC I2C driver per system class. Specific system class is obtained from DMI
# tables.
# ASIC I2C driver is supposed to be activated only in case PCI ASIC driver is
# not loaded. Both perform the same thermal algorithm and exposes the same
# sensors to sysfs. In case PCI path is available, access will be performed
# through PCI.
# Hardware monitoring related drivers for ambient temperature sensing will be
# loaded in case they were not loaded before or in case these drivers are not
# configured as modules.

ndr_cpu_bus_offset=18
ng800_cpu_bus_offset=34
xdr_cpu_bus_offset=66
q3401_cpu_bus_offset=67
smart_switch_cpu_bus_offset=34

connect_table=()
named_busses=()

#
# Ivybridge and Rangeley CPU mostly used on SPC1 systems.
#
cpu_type0_A2D_connection_table=( max11603 0x6d 15 \
			24c32 0x51 16)

cpu_type0_connection_table=(24c32 0x51 16)

#
# Broadwell CPU, mostly used on SPC2/SPC3 systems.
#
cpu_type1_A2D_connection_table=( max11603 0x6d 15 \
			tmp102 0x49 15 \
			24c32 0x50 16)

cpu_type1_connection_table=( max11603 0x6d 15 \
			tmp102 0x49 15 \
			24c32 0x50 16)

cpu_type1_a1_connection_table=(	tmp102 0x49 15 \
			24c32 0x50 16)

cpu_type1_tps_voltmon_connection_table=( tps53679 0x58 15 comex_voltmon1 \
			tps53679 0x61 15 comex_voltmon2)

cpu_type1_mps_voltmon_connection_table=(	mp2975 0x6a 15 comex_voltmon1 \
			mp2975 0x61 15 comex_voltmon2)

cpu_type1_xpde_voltmon_connection_table=(	xdpe12284 0x62 15 comex_voltmon1 \
			xdpe12284 0x64 15 comex_voltmon2)
#
# CoffeeLake CPU.
#
cpu_type2_A2D_connection_table=(    max11603 0x6d 15 \
            24c32 0x50 16)

cpu_type2_connection_table=(24c32 0x50 16)

cpu_type2_mps_voltmon_connection_table=(mp2975 0x6b 15 comex_voltmon1)

#
# Smart switch
#
smart_switch_come_voltmon_connection_table=( mp2975 0x58 15 comex_voltmon1 \
            mp2975 0x61 15 comex_voltmon2)

smart_switch_come_connection_table=( tmp102 0x49 15 \
            24c32 0x50 16)

#
# BF3 CPU.
#
bf3_come_voltmon_connection_table=( \
			mp2975 0x69 15 comex_voltmon1 \
			mp2975 0x6a 15 comex_voltmon2)

bf3_come_connection_table=(	\
			tmp421 0x1f 15 \
			24c32 0x50 16)

msn2700_base_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			lm75 0x4a 7 \
			24c32 0x51 8 \
			lm75 0x49 17)

msn2700_A2D_base_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			24c32 0x51 8 \
			lm75 0x49 17)

msn2100_base_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			lm75 0x4b 7 \
			24c32 0x51 8)

msn2740_base_connect_table=(	pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x64 5 \
			tmp102 0x49 6 \
			tmp102 0x48 7 \
			24c32 0x51 8)

msn2010_base_connect_table=(	max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			lm75 0x4a 7 \
			lm75 0x4b 7 \
			24c32 0x51 8)

mqm8700_connect_table=( tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

mqm8700_A2D_connect_table=( 	max11603 0x64 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

mqm8700_voltmon_connect_table=( tps53679 0x70 5 voltmon1 \
			tps53679 0x71 5 voltmon2)

mqm8700_rev1_voltmon_connect_table=( mp2975 0x62 5 voltmon1 \
			mp2975 0x66 5 voltmon2)

msn37xx_secured_connect_table=(  max11603 0x64 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

msn37xx_A1_connect_table=(	tmp102 0x49 7 \
			adt75 0x4a 7 \
			24c512 0x51 8)

msn37xx_A1_voltmon_connect_table=( mp2975 0x62 5 voltmon1 \
			mp2975 0x66 5 voltmon2)

sn3750sx_secured_connect_table=(	mp2975 0x62 5 \
			mp2975 0x66 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8 \
			24c128 0x54 9)

msn3420_base_connect_table=(	max11603 0x6d 5 \
			xdpe12284 0x62 5 \
			xdpe12284 0x64 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn3800_base_connect_table=( max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tps53679 0x72 5 \
			tps53679 0x73 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn27002_msn24102_msb78002_base_connect_table=( pmbus 0x27 5 \
			pmbus 0x41 5 \
			max11603 0x6d 5 \
			lm75 0x4a 7 \
			24c32 0x51 8 \
			max11603 0x6d 15 \
			lm75 0x49 17)

msn4700_msn4600_base_connect_table=( tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn4600C_base_connect_table=( tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn4700_msn4600_xdpe_voltmon_connect_table=( xdpe12284 0x62 5 voltmon1 \
			xdpe12284 0x64 5 voltmon2 \
			xdpe12284 0x66 5 voltmon3 \
			xdpe12284 0x68 5 voltmon4 \
			xdpe12284 0x6a 5 voltmon5 \
			xdpe12284 0x6c 5 voltmon6 \
			xdpe12284 0x6e 5 voltmon7)

msn4700_msn4600_A1_base_connect_table=( tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn4600C_A1_base_connect_table=( tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

msn4700_msn4600_mps_voltmon_connect_table=( mp2975 0x62 5 voltmon1 \
			mp2975 0x64 5 voltmon2 \
			mp2975 0x66 5 voltmon3 \
			mp2975 0x6a 5 voltmon5 \
			mp2975 0x6e 5 voltmon7)

msn3510_base_connect_table=(	max11603 0x6d 5 \
			tps53679 0x70 5 \
			tps53679 0x71 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c32 0x51 8)

# MQM9700 (deprecated)
mqm97xx_base_connect_table=(	max11603 0x6d 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

# MQM9700 adt75 temp sensors
mqm97xx_rev0_base_connect_table=(    max11603 0x6d 5 \
			adt75 0x49 7 \
			adt75 0x4a 7 \
			24c512 0x51 8)

# MQM9700 tmp102 temp sensors
mqm97xx_rev1_base_connect_table=(    max11603 0x6d 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

# MQM9700 STTS751 temp sensors
mqm97xx_rev2_base_connect_table=(    max11603 0x6d 5 \
			stts751 0x49 7 \
			stts751 0x4a 7 \
			24c512 0x51 8)

# MQM9700 power test
mqm97xx_power_base_connect_table=(    max11603 0x6d 5 \
			adt75 0x49 7 \
			adt75 0x4a 7 \
			24c512 0x51 8)

mqm97xx_mps_def_voltmon_connect_table=( mp2975 0x62 5 voltmon1 \
			mp2975 0x64 5 voltmon2 \
			mp2888 0x66 5 voltmon3 \
			mp2975 0x68 5 voltmon4 \
			mp2975 0x6C 5 voltmon5 )

mqm97xx_mps_voltmon_connect_table=( mp2975 0x62 5 voltmon1 \
			mp2888 0x66 5 voltmon3 \
			mp2975 0x68 5 voltmon4 \
			mp2975 0x6a 5 voltmon5 \
			mp2975 0x6c 5 voltmon6 )

mqm97xx_xpde_voltmon_connect_table=( xdpe15284 0x62 5 voltmon1 \
			mp2888 0x66 5 voltmon3 \
			xdpe15284 0x68 5 voltmon4 \
			xdpe15284 0x6a 5 voltmon5 \
			xdpe15284 0x6c 5 voltmon6 )

mqm97xx_power_voltmon_connect_table=( mp2975 0x62 5 voltmon1 \
			mp2888 0x66 5 voltmon2 \
			mp2975 0x68 5 voltmon3 \
			mp2975 0x6a 5 voltmon4 \
			mp2975 0x6b 5 voltmon5 \
			mp2975 0x6c 5 voltmon6 \
			mp2975 0x6e 5 voltmon7 )

mqm97xx_pdb_connect_table=( raa228000 0x61 4 pdb_pwr_conv1 \
			lm5066i	0x12 4 pdb_hotswap1 \
			lm5066i	0x14 4 pdb_hotswap2 \
			tmp451 0x4c 4 pdb_mos_amb \
			tmp1075 0x4e 4 pdb_intel_amb \
			24c02 0x50 4 pdb_eeprpm )

q3401_pdb_connect_table=( raa228004 0x60 5 pdb_pwr_conv1 \
			lm5066i	0x12 5 pdb_hotswap1 \
			tmp451 0x4c 5 pdb_mos_amb \
			24c02 0x50 5 pdb_eeprpm )
	   
e3597_base_connect_table=(    max11603 0x6d 5 \
			tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

e3597_dynamic_i2c_bus_connect_table=(  mp2975 0x22 5 voltmon1 \
			mp2975 0x23 5  voltmon2 \
			mp2975 0x24 5  voltmon3 \
			mp2975 0x25 5  voltmon4 \
			mp2975 0x26 5  voltmon5 \
			mp2975 0x27 5  voltmon6)

p4697_base_connect_table=(	adt75 0x49 7 \
			adt75 0x4a 7 \
			24c512 0x51 8)

p4697_rev1_base_connect_table=(	tmp102 0x49 7 \
			tmp102 0x4a 7 \
			24c512 0x51 8)

p4697_dynamic_i2c_bus_connect_table=(  mp2975 0x62 26 voltmon1 \
			mp2975 0x65 26 voltmon2 \
			mp2975 0x67 26 voltmon3 \
			mp2975 0x62 29 voltmon4 \
			mp2975 0x65 29 voltmon5 \
			mp2975 0x67 29 voltmon6)

msn4800_base_connect_table=( mp2975 0x62 5 \
	mp2975 0x64 5 \
	mp2975 0x66 5 \
	mp2975 0x68 5 \
	mp2975 0x6a 5 \
	max11603 0x6d 7 \
	max11603 0x64 7 \
	24c32 0x51 8 \
	tmp102 0x49 12 \
	tmp421 0x1f 14 \
	max11603 0x6d 43 \
	tmp102 0x4a 44 \
	24c32 0x51 45)

mqm9510_base_connect_table=( \
	adt75  0x4a 7 \
	24c512 0x51 8)

mqm9510_dynamic_i2c_bus_connect_table=( \
	mp2975 0x62 5 voltmon1 \
	mp2888 0x66 5 voltmon2 \
	mp2975 0x68 5 voltmon3 \
	mp2975 0x6c 5 voltmon4 \
	mp2975 0x62 6 voltmon5 \
	mp2888 0x66 6 voltmon6 \
	mp2975 0x68 6 voltmon7 \
	mp2975 0x6c 6 voltmon8 )

mqm9520_base_connect_table=( \
	24c512 0x51 8 )

mqm9520_dynamic_i2c_bus_connect_table=( \
	adt75  0x4a 7  port_amb1 \
	adt75  0x4a 15 port_amb2 \
	mp2888 0x66 5  voltmon1 \
	mp2975 0x68 5  voltmon2 \
	mp2975 0x6c 5  voltmon3 \
	mp2888 0x66 13 voltmon4 \
	mp2975 0x68 13 voltmon5 \
	mp2975 0x6c 13 voltmon6 )

# Just for possible initial step without SMBios alternative BOM string
sn5600_base_connect_table=( \
	pmbus  0x10 4 \
	pmbus  0x11 4 \
	pmbus  0x13 4 \
	pmbus  0x15 4 \
	mp2975 0x62 5 \
	mp2975 0x63 5 \
	mp2975 0x64 5 \
	mp2975 0x65 5 \
	mp2975 0x66 5 \
	mp2975 0x67 5 \
	mp2975 0x68 5 \
	mp2975 0x69 5 \
	mp2975 0x6a 5 \
	mp2975 0x6c 5 \
	mp2975 0x6e 5 \
	tmp102 0x49 6 \
	tmp102 0x4a 7 \
	24c512 0x51 8 )

sn5640_base_connect_table=( \
	mp2891 0x62 5 \
	mp2891 0x63 5 \
	mp2891 0x64 5 \
	mp2891 0x65 5 \
	mp2891 0x66 5 \
	mp2891 0x67 5 \
	mp2891 0x68 5 \
	mp2891 0x69 5 \
	mp2891 0x6a 5 \
	mp2891 0x6c 5 \
	mp2891 0x6e 5 \
	tmp102 0x49 6 \
	tmp102 0x4a 7 \
	24c512 0x51 8 )

p2317_connect_table=(	24c512 0x51 8)

# 6 TS are temporary for BU and will be removed later.
# EEPROM 0x52 and A2D are unused
p4262_base_connect_table=( \
	pmbus 0x10 4 \
	lm5066 0x11 4 \
	pmbus 0x12 4 \
	pmbus 0x13 4 \
	pmbus 0x16 4 \
	pmbus 0x17 4 \
	pmbus 0x1b 4 \
	tmp75 0x4d 4 \
	tmp75 0x4e 4 \
	24c02 0x50 4 \
	adt75 0x48 7 \
	adt75 0x49 7 \
	adt75 0x4a 7 \
	adt75 0x4b 7 \
	adt75 0x4c 7 \
	adt75 0x4d 7 \
	adt75 0x4e 7 \
	adt75 0x4f 7 \
	24c02 0x50 7 \
	24c512 0x51 8 \
	24c512 0x52 8 )

# TBD MS. Check exact components
p4262_dynamic_i2c_bus_connect_table=( \
	mp2975 0x21 26 voltmon1 \
	mp2975 0x23 26 voltmon2 \
	mp2975 0x2a 26 voltmon3 \
	mp2975 0x21 29 voltmon4 \
	mp2975 0x23 29 voltmon5 )

# Just for possible initial step without SMBios alternative BOM string
q3200_base_connect_table=( \
	mp2891 0x66 5  \
	mp2891 0x68 5  \
	mp2891 0x6c 5  \
	mp2891 0x66 21 \
	mp2891 0x68 21 \
	mp2891 0x6c 21 \
	tmp102 0x49 6  \
	tmp102 0x4a 7  \
	24c512 0x51 8 )

# Just for possible initial step without SMBios alternative BOM string
q3400_base_connect_table=( \
	mp2891 0x66 5  \
	mp2891 0x68 5  \
	mp2981 0x6c 5  \
	mp2891 0x66 21 \
	mp2891 0x68 21 \
	mp2891 0x6c 21 \
	mp2891 0x66 37 \
	mp2891 0x68 37 \
	mp2891 0x6c 37 \
	mp2891 0x66 53 \
	mp2891 0x68 53 \
	mp2891 0x6c 53 \
	tmp102 0x49 6  \
	tmp102 0x4a 7  \
	24c512 0x51 8 )

# Just for possible initial step without SMBios alternative BOM string
p4300_base_connect_table=( \
	lm5066 0x40 4 \
	adt75 0x49 7 \
	adt75 0x4a 7 \
	adt75 0x4b 7 \
	adt75 0x4c 7 \
	adt75 0x4d 7 \
	adt75 0x4e 7 \
	adt75 0x4f 7 \
	24c512 0x51 8 \
	24c512 0x54 8 )

p4300_dynamic_i2c_bus_connect_table=( \
	mp2975 0x21 26 voltmon1 \
	mp2975 0x23 26 voltmon2 )

smart_switch_dpu_dynamic_i2c_bus_connect_table=( \
	tmp421 0x0 0x1f dpu_cx_amb \
	mp2975 0x0 0x69 dpu_voltmon1 \
	mp2975 0x0 0x6a dpu_voltmon2)

# Just for possible initial step without SMBios alternative BOM string
n5110ld_base_connect_table=( lm5066 0x16 5 \
	pmbus 0x10 5 \
	pmbus 0x11 5 \
	pmbus 0x12 5 \
	pmbus 0x13 5 \
	24c512 0x51 5 \
	adt75 0x49 7 \
	adt75 0x4a 8 \
	adt75 0x4b 8)

n5110ld_dynamic_i2c_bus_connect_table=( mp2891 0x66 6 voltmon1 \
	mp2891 0x68 6 voltmon2 \
	mp2891 0x6c 6 voltmon3 \
	mp2891 0x66 22 voltmon4 \
	mp2891 0x68 22 voltmon5 \
	mp2891 0x6c 22 voltmon6)
	
so_cartridge_eeprom_connect_table=( 24c02 0x50 47 cable_cartridge1_eeprom \
	24c02 0x50 48 cable_cartridge2_eeprom \
	24c02 0x50 49 cable_cartridge3_eeprom \
	24c02 0x50 50 cable_cartridge4_eeprom)

nso_cartridge_eeprom_connect_table=( 24c02 0x50 47 cable_cartridge1_eeprom \
	24c02 0x50 50 cable_cartridge2_eeprom \
	24c02 0x50 51 cable_cartridge3_eeprom \
	24c02 0x50 52 cable_cartridge4_eeprom)

ariel_cartridge_eeprom_connect_table=( 24c02 0x50 47 cable_cartridge1_eeprom \
	24c02 0x50 50 cable_cartridge2_eeprom)

n61xxld_cartridge_eeprom_connect_table=( \
	24c02 0x50 68 cable_cartridge1_eeprom \
	24c02 0x50 69 cable_cartridge2_eeprom \
	24c02 0x50 70 cable_cartridge3_eeprom \
	24c02 0x50 71 cable_cartridge4_eeprom)

n5110ld_vpd_connect_table=(24c512 0x51 2 vpd_info)
n5110ld_virtual_vpd_connect_table=(24c512 0x51 10 vpd_info)

# I2C busses naming.
cfl_come_named_busses=( come-vr 15 come-amb 15 come-fru 16 )
amd_snw_named_busses=( come-vr 39 come-amb 39 come-fru 40 )
msn47xx_mqm97xx_named_busses=( asic1 2 pwr 4 vr1 5 amb1 7 vpd 8 )
mqm9510_named_busses=( asic1 2 asic2 3 pwr 4 vr1 5 vr2 6 amb1 7 vpd 8 )
mqm9520_named_busses=( asic1 2 pwr 4 vr1 5 amb1 7 vpd 8 asic2 10 vr2 13 )
sn5600_named_busses=( asic1 2 pwr 4 vr1 5 fan-amb 6 port-amb 7 vpd 8 )
p4262_named_busses=( pdb 4 ts 7 vpd 8 erot1 15 erot2 16 vr1 26 vr2 29 )
p4300_named_busses=( ts 7 vpd 8 erot1 15 vr1 26 vr2 29 )
q3200_named_busses=( asic1 2 asic2 18 pwr 4 vr1 5 vr2 21 fan-amb 6 port-amb 7 vpd 8 )
q3400_named_busses=( asic1 2 asic2 18 asic3 34 asic4 50 pwr1 4 pwr2 3 vr1 5 vr2 21 vr3 37 vr4 53 fan-amb 6 port-amb 7 vpd 8 )
q3401_named_busses=( asic1 2 asic2 18 asic3 34 asic4 50 pwr1 4 vr1 5 vr2 21 vr3 37 vr4 53 fan-amb 6 port-amb 7 vpd 8 )
smart_switch_named_busses=( asic1 2 pwr 4 vr1 5 amb1 7 vpd 8 dpu1 17 dpu2 18 dpu3 19 dpu4 20)
n5110ld_named_busses=( asic1 11 vr 13 pwr1 14 pwr2 30 amb 15 pcb_amb 16 vpd 2 cart1 55 cart2 56 cart3 57 cart4 58)
n61xxld_named_busses=( asic1 5 asic2 21 asic3 37 asic4 53 pwr 7 vr1 8 vr2 24 vr3 40 vr4 56 vpd 1 cart1 68 cart2 69 cart3 70 cart4 71 cpu-vr 6)
sn5640_named_busses=( asic1 2 pwr 4 vr1 5 fan-amb 6 port-amb 7 vpd 8 )
sn58xxld_named_busses=(asic1 6 asic2 22 asic3 38 asic4 54 pwr1 7 pwr2 23 pwr3 39 pwr4 55 vr1 9 vr2 25 vr3 41 vr4 57 vpd 1 cpu-vr 69 cpu-vpd 70)
sn66xxld_named_busses=(asic1 5 pwr1 7 pwr2 8 vr1 16 vr2 17 vpd 1 cpu-vr 6)

ACTION=$1

if [ "$board_type" == "VMOD0014" ]; then
	i2c_bus_max=14
	psu1_i2c_addr=0x58
	psu2_i2c_addr=0x58
fi

is_module()
{
    /sbin/lsmod | grep -w "$1" > /dev/null
    RC=$?
    return $RC
}

function get_i2c_bus_frequency_default()
{
	# Get I2C base frequency default value.
	# Relevant only to particular system types.
	i2c_freq=$(/usr/bin/iorw -b "$i2c_freq_reg" -r -l1 | awk '{print $5}')
	echo "$i2c_freq" > $config_path/default_i2c_freq
}

function set_i2c_bus_frequency_400KHz()
{
	# Speed-up ASIC I2C driver probing by setting I2C frequency to 400KHz.
	# Relevant only to particular system types.

	case $board_type in
	VMOD0001|VMOD0002|VMOD003|VMOD0004|VMOD0005|VMOD0009)
		if [ -f $config_path/default_i2c_freq ]; then
			/usr/bin/iorw -b "$i2c_freq_reg" -w -l1 -v"$i2c_freq_400"
		fi
		;;
	*)
		;;
	esac
}

function restore_i2c_bus_frequency_default()
{
	# Restore I2C base frequency to the default value.
	# Relevant only to particular system types.

	case $board_type in
	VMOD0001|VMOD0002|VMOD003|VMOD0004|VMOD0005|VMOD0009)
		if [ -f $config_path/default_i2c_freq ]; then
			i2c_freq=$(< $config_path/default_i2c_freq)
			/usr/bin/iorw -b "$i2c_freq_reg" -w -l1 -v"$i2c_freq"
			chipup_test_time=5
		fi
		;;
	VMOD0014)
			chipup_test_time=5
		;;
	*)
		chipup_test_time=2
		;;
	esac

	return $chipup_test_time
}

function find_regio_sysfs_path_helper()
{
	# Find hwmon{n} sysfs path for regio device
	case $board_type in 
	VMOD0014)
		for path in /sys/devices/pci0000:00/*/NVSN2201:*/mlxreg-io/hwmon/hwmon*; do
			if [ -d "$path" ]; then
				name=$(cut "$path"/name -d' ' -f 1)
				if [ "$name" == "mlxreg_io" ]; then
					echo "$path"
					return 0
				fi
			fi
		done
		;;
	*)
		arch=$(uname -m)
		if [ "$arch" = "aarch64" ]; then
			plat_path=/sys/devices/platform/MLNXBF49:00
		else
			plat_path=/sys/devices/platform/mlxplat
		fi
		for path in ${plat_path}/mlxreg-io/hwmon/hwmon*; do
			if [ -d "$path" ]; then
				name=$(cut "$path"/name -d' ' -f 1)
				if [ "$name" == "mlxreg_io" ]; then
					echo "$path"
					return 0
				fi
			fi
		done
		;;
	esac

	return 1
}

function find_regio_sysfs_path()
{

	retry_helper find_regio_sysfs_path_helper 0.5 10 "mlxreg_io is not loaded"
	if [ $? -eq 0 ]; then
		return 0
	fi
	return 1
}

# SODIMM temperatures (C) for setting in scale 1000
SODIMM_TEMP_CRIT=95000
SODIMM_TEMP_MAX=85000
SODIMM_TEMP_MIN=0
SODIMM_TEMP_HYST=6000

set_sodimm_temp_limits()
{
	local s_list=""
	# SODIMM temp reading is not supported on Broadwell-DE Comex
	# and on BF# Comex.
	# Broadwell-DE Comex can be installed interchangeably with new
	# Coffee Lake Comex on part of systems e.g. on Anaconda.
	# Thus check by CPU type and not by system type.
	case $cpu_type in
		$BDW_CPU|$BF3_CPU)
			return 0
			;;
		*)
			;;
	esac

	if [ ! -d /sys/bus/i2c/drivers/jc42 ]; then
		modprobe jc42 > /dev/null 2>&1
		rc=$?
		if [ $rc -eq 0 ]; then
			while : ; do
				sleep 1
				[[ -d /sys/bus/i2c/drivers/jc42 ]] && break
			done
		else
			return 1
		fi
	fi

	s_list=`find /sys/bus/i2c/drivers/jc42/[0-9]*/`
	if echo $s_list | grep -q hwmon ; then
		for temp_sens in /sys/bus/i2c/drivers/jc42/[0-9]*; do
			echo $SODIMM_TEMP_CRIT > "$temp_sens"/hwmon/hwmon*/temp1_crit
			echo $SODIMM_TEMP_MAX > "$temp_sens"/hwmon/hwmon*/temp1_max
			echo $SODIMM_TEMP_MIN > "$temp_sens"/hwmon/hwmon*/temp1_min
			echo $SODIMM_TEMP_HYST > "$temp_sens"/hwmon/hwmon*/temp1_crit_hyst
		done
	else
		return 1
	fi

	return 0
}

set_jtag_gpio()
{
	local export_unexport=$1
	local cpu_type=$(cat $config_path/cpu_type)
	# Check where supported and assign appropriate GPIO pin numbers
	# for JTAG bit-banging operations.
	# GPIO pin numbers are offset from gpiobase.
	case $cpu_type in
		$BDW_CPU)
			jtag_tck=15
			jtag_tms=24
			jtag_tdo=27
			jtag_tdi=28
			echo 0x2094 > $config_path/jtag_rw_reg
			echo 0x2095 > $config_path/jtag_ro_reg
			;;
		$CFL_CPU)
			jtag_tdi=128
			jtag_tdo=129
			jtag_tms=130
			jtag_tck=131
			echo 0x2094 > $config_path/jtag_rw_reg
			echo 0x2095 > $config_path/jtag_ro_reg
			;;
		$DNV_CPU)
			jtag_tdi=86
			jtag_tck=87
			jtag_tms=88
			jtag_tdo=89
			;;
		$AMD_SNW_CPU)
			case $sku in
			HI180)
				echo 0x20e5 > $config_path/jtag_rw_reg
				echo 0x20e6 > $config_path/jtag_ro_reg
				;;
			*)
				echo 0x2094 > $config_path/jtag_rw_reg
				echo 0x2095 > $config_path/jtag_ro_reg
				;;
			esac
			;;
		$AMD_V3000_CPU)
			jtag_tdi=5
			jtag_tck=132
			jtag_tms=7
			jtag_tdo=8
			echo 0x20e5 > $config_path/jtag_rw_reg
			echo 0x20e6 > $config_path/jtag_ro_reg
			;;
		*)
			return 0
			;;
	esac

	find /sys/class/gpio/gpiochip*/ 2>&1 | grep -q base
	if [ $? -ne 0 ]; then
		echo "gpio controller driver is not loaded"
		return 1
	fi

	if [ "$export_unexport" == "export" ]; then
		if [ ! -d $jtag_path ]; then
			mkdir $jtag_path
		fi

		if [ "$board_type" != "VMOD0014" ]; then
			arch=$(uname -m)
			if [ "$arch" = "aarch64" ]; then
				plat_path=/sys/devices/platform/MLNXBF49:00
			else
				plat_path=/sys/devices/platform/mlxplat
			fi
			if find ${plat_path}/mlxreg-io/hwmon/hwmon*/ | grep -q jtag_enable ; then
				ln -sf ${plat_path}/mlxreg-io/hwmon/hwmon*/jtag_enable $jtag_path/jtag_enable
			fi
		fi
	fi

	if [ "$cpu_type" == "$AMD_SNW_CPU" ]; then
		return 0
	fi

	# SN2201 has 2 gpiochips: CPU/PCH GPIO and PCA9555 Extender.
	# CPU GPIOs are used for JTAG bit-banging.
	if [ "$board_type" == "VMOD0014" ]; then
		for gpiochip in /sys/class/gpio/*; do
			if [ -d "$gpiochip" ] && [ -e "$gpiochip"/label ]; then
				gpiolabel=$(<"$gpiochip"/label)
				if [ "$gpiolabel" == "INTC3000:00" ]; then
					gpiobase=$(<"$gpiochip"/base)
					break
				fi
			fi
		done
		if [ -z "$gpiobase" ]; then
			log_err "CPU GPIO chip was not found"
		fi
	else
		gpiobase=$(</sys/class/gpio/gpiochip*/base)
	fi

	gpio_tck=$((gpiobase+jtag_tck))
	echo $gpio_tck > /sys/class/gpio/"$export_unexport"
	gpio_tms=$((gpiobase+jtag_tms))
	echo $gpio_tms > /sys/class/gpio/"$export_unexport"
	gpio_tdo=$((gpiobase+jtag_tdo))
	echo $gpio_tdo > /sys/class/gpio/"$export_unexport"
	gpio_tdi=$((gpiobase+jtag_tdi))
	echo $gpio_tdi > /sys/class/gpio/"$export_unexport"

	# In SN2201 system. 
	# GPIO0 for CPU request to reset the Main Board I2C Mux.
	# GPIO1 for CPU control the CPU Board MUX when doing the ISP programming. 
	# GPIO13 for CPU request Main Board JTAG control signal. 
	if [ "$board_type" == "VMOD0014" ]; then
		mux_reset=27
		jtag_mux_en=33
		jtag_ena=60
		gpio_mux_rst=$((gpiobase+mux_reset))
		gpio_jtag_mux_en=$((gpiobase+jtag_mux_en))
		gpio_jtag_enable=$((gpiobase+jtag_ena))
		echo $gpio_mux_rst > /sys/class/gpio/"$export_unexport"
		echo $gpio_jtag_mux_en > /sys/class/gpio/"$export_unexport"
		echo $gpio_jtag_enable > /sys/class/gpio/"$export_unexport"
	fi

	if [ "$export_unexport" == "export" ]; then
		check_n_link /sys/class/gpio/gpio$gpio_tck/value $jtag_path/jtag_tck
		check_n_link /sys/class/gpio/gpio$gpio_tms/value $jtag_path/jtag_tms
		check_n_link /sys/class/gpio/gpio$gpio_tdo/value $jtag_path/jtag_tdo
		check_n_link /sys/class/gpio/gpio$gpio_tdi/value $jtag_path/jtag_tdi
		if [ "$board_type" == "VMOD0014" ]; then
			check_n_link /sys/class/gpio/gpio$gpio_mux_rst/value $system_path/mux_reset
			check_n_link /sys/class/gpio/gpio$gpio_jtag_mux_en/value $jtag_path/jtag_mux_en
			check_n_link /sys/class/gpio/gpio$gpio_jtag_enable/value $jtag_path/jtag_enable
		fi
	fi
}

set_gpios()
{
	local export_unexport=$1
	gpiobase=

	case $cpu_type in
		$BDW_CPU|$CFL_CPU|$DNV_CPU)
			set_jtag_gpio $1
			return 1
			;;
		$AMD_SNW_CPU)
			set_jtag_gpio $1
			gpiolabel="AMDI0030:00"
			gpio_idx=(5 6 4 42)
			gpio_names=("cpu_erot_present" "bmc_present" "boot_completed" "nvme_present")
			;;
		$AMD_V3000_CPU)
			set_jtag_gpio $1
			gpiolabel="AMDI0030:00"
			gpio_idx=(89 10 12 23)
			gpio_names=("conf_flash_rst" "boot_completed" "bmc_present" "cpu_erot_present")
			;;
		*)
			return 1
			;;
	esac

	for gpiochip in /sys/class/gpio/*; do
		if [ -d "$gpiochip" ] && [ -e "$gpiochip"/label ]; then
			gpiochip_label=$(<"$gpiochip"/label)
			if [ "$gpiochip_label" == "$gpiolabel" ]; then
				gpiobase=$(<"$gpiochip"/base)
				break
			fi
		fi
	done
	if [ -z "$gpiobase" ]; then
		return 1
	fi

	for ((i=0; i<${#gpio_idx[@]}; i+=1)); do
		gpionum=$((gpiobase+${gpio_idx[$i]}))
		echo $gpionum > /sys/class/gpio/$export_unexport
		if [ "$export_unexport" == "export" ]; then
			check_n_link /sys/class/gpio/gpio$gpionum/value $system_path/"${gpio_names[$i]}"
		fi
	done
}


# $1 - cpu bus offset.
add_cpu_board_to_connection_table()
{
	local cpu_connection_table=()
	local cpu_voltmon_connection_table=()
	local HW_REV=255
	local cpu_type=$(cat $config_path/cpu_type)

	regio_path=$(find_regio_sysfs_path)
	if [ $? -eq 0 ]; then
		if [ -f "$regio_path"/config3 ]; then
			HW_REV=$(cut "$regio_path"/config3 -d' ' -f 1)
		fi
	fi

	case $cpu_type in
		$RNG_CPU|$IVB_CPU)
			board=$(< /sys/devices/virtual/dmi/id/product_name)
			case $board in
				MSN241*|MSN27*)
					# Spider Panther removed A2D from SFF
					cpu_connection_table=( ${cpu_type0_connection_table[@]} )
					;;
				*)
					cpu_connection_table=( ${cpu_type0_A2D_connection_table[@]} )
					;;
			esac
		;;
		$BDW_CPU)
			# None respin BWD version not support to read HW_REV (255).
			case $HW_REV in
				0|3)
					cpu_connection_table=( ${cpu_type1_a1_connection_table[@]} )
					cpu_voltmon_connection_table=( ${cpu_type1_tps_voltmon_connection_table[@]} )
				;;
				1|5)
					cpu_connection_table=( ${cpu_type1_a1_connection_table[@]} )
					cpu_voltmon_connection_table=( ${cpu_type1_mps_voltmon_connection_table[@]} )
				;;
				2|4)
					cpu_connection_table=( ${cpu_type1_a1_connection_table[@]} )
					cpu_voltmon_connection_table=( ${cpu_type1_xpde_voltmon_connection_table[@]} )
				;;
				*)
					# COMEX BWD regular version not support HW_REV register
					case $sku in
						HI116|HI112|HI124|HI100|HI122|HI123|MSN3700|MSN3700C)
							# An MSN3700/MSN3700C,MQM7800, MSN4600/MSN4600C MSN4700
							cpu_connection_table=( ${cpu_type1_connection_table[@]} )
							;;
						*)
							cpu_connection_table=( ${cpu_type1_A2D_connection_table[@]} )
							;;
					esac
					cpu_voltmon_connection_table=( ${cpu_type1_tps_voltmon_connection_table[@]} )
				;;
			esac
			;;
		$CFL_CPU)
			case $sku in
				# Systems without A2D on COMEx
				HI130|HI142|HI152|HI157|HI158|HI159|HI173|HI174|HI175|HI178|HI179)
					cpu_connection_table=( ${cpu_type2_connection_table[@]} )
					cpu_voltmon_connection_table=( ${cpu_type2_mps_voltmon_connection_table[@]} )
					;;
				HI160)
					cpu_connection_table=( ${smart_switch_come_connection_table[@]} )
					cpu_voltmon_connection_table=( ${smart_switch_come_voltmon_connection_table[@]} )
					;;
				*)
					cpu_connection_table=( ${cpu_type2_A2D_connection_table[@]} )
					cpu_voltmon_connection_table=( ${cpu_type2_mps_voltmon_connection_table[@]} )
					;;
			esac
			;;
		$BF3_CPU)
			cpu_connection_table=( ${bf3_come_connection_table[@]} )
			cpu_voltmon_connection_table=( ${bf3_come_voltmon_connection_table[@]} )
			;;
		$AMD_SNW_CPU)
			cpu_connection_table=( ${cpu_type2_connection_table[@]} )
			;;
		*)
			log_err "$product is not supported"
			exit 0
			;;
	esac

	# $1 - cpu bus offset.
	if [ ! -z "$1" ]; then
		local cpu_bus_offset=$1
		for ((i=0; i<${#cpu_connection_table[@]}; i+=3)); do
			cpu_connection_table[$i+2]=$(( cpu_connection_table[i+2]-base_cpu_bus_offset+cpu_bus_offset ))
		done
		for ((i=0; i<${#cpu_voltmon_connection_table[@]}; i+=4)); do
			cpu_voltmon_connection_table[$i+2]=$(( cpu_voltmon_connection_table[i+2]-base_cpu_bus_offset+cpu_bus_offset ))
		done
	fi

	connect_table+=(${cpu_connection_table[@]})
	add_i2c_dynamic_bus_dev_connection_table "${cpu_voltmon_connection_table[@]}"
}

add_i2c_dynamic_bus_dev_connection_table()
{
	connection_table=("$@")
	dynamic_i2cbus_connection_table=()

	echo -n "${connection_table[@]} " >> $config_path/i2c_bus_connect_devices
	for ((i=0; i<${#connection_table[@]}; i+=4)); do
		dynamic_i2cbus_connection_table[$i]="${connection_table[i]}"
		dynamic_i2cbus_connection_table[$i+1]="${connection_table[i+1]}"
		dynamic_i2cbus_connection_table[$i+2]="${connection_table[i+2]}"
	done

	connect_table+=(${dynamic_i2cbus_connection_table[@]})
}

add_come_named_busses()
{
	local come_named_busses=()

	case $cpu_type in
	$CFL_CPU|$BF3_CPU)
		come_named_busses+=( ${cfl_come_named_busses[@]} )
		;;
	$AMD_SNW_CPU)
		come_named_busses+=( ${amd_snw_named_busses[@]} )
		;;
	*)
		return
		;;
	esac

	# $1 may contain come board bus offset.
	if [ ! -z "$1" ]; then
		local come_board_bus_offset=$1
		for ((i=0; i<${#come_named_busses[@]}; i+=2)); do
			come_named_busses[$i+1]=$(( come_named_busses[i+1]-base_cpu_bus_offset+come_board_bus_offset ))
		done
	fi

	named_busses+=(${come_named_busses[@]})
}

start_mst_for_spc1_port_cpld()
{
	if [ ! -d /dev/mst ]; then
		lsmod | grep mst_pci >/dev/null 2>&1
		if [  $? -ne 0 ]; then
			mst start  >/dev/null 2>&1
		fi
	fi
}

set_spc1_port_cpld()
{
	cpld=$(< $config_path/cpld_port)
	if [ $cpld == "cpld3" ] && [ ! -f $system_path/cpld3_version ]; then
		ver_dec=$CPLD3_VER_DEF
		# check if mlxreg exists
		if [ -x "$(command -v mlxreg)" ]; then
			if [ ! -d /dev/mst ]; then
				lsmod | grep mst_pci >/dev/null 2>&1
				if [  $? -ne 0 ]; then
					mst start  >/dev/null 2>&1
					sleep 2
				fi
			fi
			mt_dev=$(find /dev/mst -name *00_pciconf0)
			cmd='mlxreg --reg_name MSCI  -d $mt_dev -g -i "index=2" | grep version | cut -d "|" -f2'
			ver_hex=$(eval $cmd 2>/dev/null)
			if [ ! -z "$ver_hex" ]; then
				ver_dec=$(printf "%d" $ver_hex)
			fi
		fi
		echo "$ver_dec" > $system_path/cpld3_version
	fi
}

msn274x_specific()
{
	connect_table+=(${msn2740_base_connect_table[@]})
	add_cpu_board_to_connection_table

	max_tachos=4
	hotplug_fans=4
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo "3 4 1 2" > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn2740_sensors.conf"
	echo 8 > $config_path/reset_attr_num
}

msn21xx_specific()
{
	connect_table+=(${msn2100_base_connect_table[@]})
	add_cpu_board_to_connection_table

	max_tachos=4
	hotplug_psus=0
	hotplug_fans=0
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 13000 > $config_path/psu_fan_max
	echo 1040 > $config_path/psu_fan_min
	echo "3 4 1 2" > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn2100_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn2100.json"
	echo 4 > $config_path/fan_drwr_num
	echo 1 > $config_path/fixed_fans_system
	echo 8 > $config_path/reset_attr_num
}

msn24xx_specific()
{
	start_mst_for_spc1_port_cpld
	case $sku in
		HI138)
			# SGN2410_A1
			connect_table+=(${msn2700_A2D_base_connect_table[@]})
			thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
			hotplug_fans=0
			max_tachos=0
		;;
		*)
			connect_table+=(${msn2700_base_connect_table[@]})
			max_tachos=8
			hotplug_fans=4
			echo 21000 > $config_path/fan_max_speed
			echo 5400 > $config_path/fan_min_speed
			echo 18000 > $config_path/psu_fan_max
			echo 2000 > $config_path/psu_fan_min
			echo "7 8 5 6 3 4 1 2" > $config_path/fan_inversed
			echo 24c02 > $config_path/psu_eeprom_type
			thermal_control_config="$thermal_control_configs_path/tc_config_msn2410.json"
			;;
	esac
	add_cpu_board_to_connection_table

	echo 3 > $config_path/cpld_num
	echo cpld3 > $config_path/cpld_port

	lm_sensors_config="$lm_sensors_configs_path/msn2700_sensors.conf"
	set_spc1_port_cpld
	cpld=$(< $config_path/cpld_port)
	echo 8 > $config_path/reset_attr_num
}

msn27xx_msb_msx_specific()
{
	start_mst_for_spc1_port_cpld
	product=$(< /sys/devices/virtual/dmi/id/product_name)
	case $product in
		MSN27*|MSN241*)
			# Panther Spider
			connect_table+=(${msn2700_base_connect_table[@]})
			;;
		*)
			connect_table+=(${msn2700_A2D_base_connect_table[@]})
			;;
	esac
	# Connect TC data table 
	case $product in
		MSN27*)
			# Panther
			thermal_control_config="$thermal_control_configs_path/tc_config_msn2700.json"
			;;
		MSN241*)
			# Spider
			thermal_control_config="$thermal_control_configs_path/tc_config_msn2410.json"
			;;
		MSB78*|MSB77*)
			# Scorp
			thermal_control_config="$thermal_control_configs_path/tc_config_msb7xxx.json"
			;;
		SGN2410)
			# SGN2410_A1
			thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
			;;
		*)
			;;
	esac
	add_cpu_board_to_connection_table

	case $sku in
		HI138)
			# SGN2410_A1
			thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
			hotplug_fans=0
			max_tachos=0
		;;
		*)
			max_tachos=8
			hotplug_fans=4

			# Set according to front (inlet) fan max, 21800
			echo 21000 > $config_path/fan_max_speed
			# Set according to rear (outlet) fan min, 4600
			echo 5400 > $config_path/fan_min_speed

			# Set FAN front (inlet) speed limits
			echo 21000 > $config_path/fan_front_max_speed
			echo 6300 > $config_path/fan_front_min_speed

			# Set FAN rear (outlet) speed limits 
			echo 18000 > $config_path/fan_rear_max_speed
			echo 5400 > $config_path/fan_rear_min_speed

			echo 18000 > $config_path/psu_fan_max
			echo 2000 > $config_path/psu_fan_min
			echo "7 8 5 6 3 4 1 2" > $config_path/fan_inversed
			echo 24c02 > $config_path/psu_eeprom_type
			;;
	esac

	product=$(< /sys/devices/virtual/dmi/id/product_name)
	case $product in
		MSB78*)
			echo 2 > $config_path/cpld_num
		;;
		*)
			echo 3 > $config_path/cpld_num
			echo cpld3 > $config_path/cpld_port
		;;
	esac

	set_spc1_port_cpld

	lm_sensors_config="$lm_sensors_configs_path/msn2700_sensors.conf"
	get_i2c_bus_frequency_default
	echo 8 > $config_path/reset_attr_num
}

msn201x_specific()
{
	connect_table+=(${msn2010_base_connect_table[@]})
	add_cpu_board_to_connection_table

	max_tachos=4
	hotplug_psus=0
	hotplug_fans=0
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 13000 > $config_path/psu_fan_max
	echo 1040 > $config_path/psu_fan_min
	echo "3 4 1 2" > $config_path/fan_inversed
	echo 2 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn2010_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn2010.json"
	echo 4 > $config_path/fan_drwr_num
	echo 1 > $config_path/fixed_fans_system
	echo 8 > $config_path/reset_attr_num
}

connect_msn3700()
{
	local voltmon_connection_table=()
	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
		case $sys_ver in
			6|2)
					# msn3700/msn3700C respin A1
					connect_table+=(${msn37xx_A1_connect_table[@]})
					voltmon_connection_table=(${msn37xx_A1_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/msn3700_A1_sensors.conf"
			;;
			*)
					connect_table+=(${mqm8700_connect_table[@]})
					voltmon_connection_table=(${mqm8700_voltmon_connect_table[@]})
			;;
		esac
	else
		connect_table+=(${mqm8700_connect_table[@]})
		voltmon_connection_table=(${mqm8700_voltmon_connect_table[@]})
	fi
	add_i2c_dynamic_bus_dev_connection_table "${voltmon_connection_table[@]}"
}

mqmxxx_msn37x_msn34x_specific()
{
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	local voltmon_connection_table=()

	case $sku in
		HI136)
			# msn3700C-S
			minimal_unsupported=1
			connect_table+=(${msn37xx_secured_connect_table[@]})
			voltmon_connection_table=(${mqm8700_voltmon_connect_table[@]})
			thermal_control_config="$thermal_control_configs_path/tc_config_msn3700C.json"
		;;
		HI112|MSN3700)
			# msn3700
			minimal_unsupported=1
			connect_msn3700
			thermal_control_config="$thermal_control_configs_path/tc_config_msn3700.json"
		;;
		HI116|MSN3700C)
			# msn3700C
			minimal_unsupported=1
			connect_msn3700
			thermal_control_config="$thermal_control_configs_path/tc_config_msn3700C.json"
		;;
		HI110)
			# Jaguar
			connect_table+=(${mqm8700_connect_table[@]})
			voltmon_connection_table=(${mqm8700_voltmon_connect_table[@]})
			thermal_control_config="$thermal_control_configs_path/tc_config_mqm8700.json"
		;;
		*)
			connect_table+=(${mqm8700_A2D_connect_table[@]})
			voltmon_connection_table=(${mqm8700_voltmon_connect_table[@]})
			thermal_control_config="$thermal_control_configs_path/tc_config_mqm8700.json"
		;;
	esac
	add_i2c_dynamic_bus_dev_connection_table "${voltmon_connection_table[@]}"
	add_cpu_board_to_connection_table

	max_tachos=12

	# Set according to front (inlet) fan max, 21800
	echo 23000 > $config_path/fan_max_speed
	# Set according to rear (outlet) fan min, 4600
	echo 4600 > $config_path/fan_min_speed

	# Set FAN front (inlet) speed limits
	echo 23000 > $config_path/fan_front_max_speed
	echo 5400 > $config_path/fan_front_min_speed

	# Set FAN rear (outlet) speed limits
	echo 20500 > $config_path/fan_rear_max_speed
	echo 4800 > $config_path/fan_rear_min_speed

	echo 25000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	get_i2c_bus_frequency_default
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

sn3750sx_specific()
{
	connect_table+=(${sn3750sx_secured_connect_table[@]})
	add_cpu_board_to_connection_table

	max_tachos=12
	minimal_unsupported=1
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 25000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/sn3750sx_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn3750.json" 
	get_i2c_bus_frequency_default
}

msn3420_specific()
{
	connect_table+=(${msn3420_base_connect_table[@]})
	add_cpu_board_to_connection_table

	max_tachos=10
	hotplug_fans=5
	minimal_unsupported=1
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn3420_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn3420.json"
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

msn_xh3000_specific()
{
	connect_table+=(${mqm8700_A2D_connect_table[@]})
	add_i2c_dynamic_bus_dev_connection_table "${mqm8700_voltmon_connect_table[@]}"

	add_cpu_board_to_connection_table
	hotplug_fans=0
	hotplug_psus=0
	hotplug_pwrs=0
	max_tachos=0
	echo 3 > $config_path/cpld_num
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	get_i2c_bus_frequency_default
}

msn38xx_specific()
{
	connect_table+=(${msn3800_base_connect_table[@]})
	add_cpu_board_to_connection_table

	max_tachos=3
	hotplug_fans=3
	echo 11000 > $config_path/fan_max_speed
	echo 2235 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 4 > $config_path/cpld_num
	thermal_control_config="$thermal_control_configs_path/tc_config_msn3800.json"
	lm_sensors_config="$lm_sensors_configs_path/msn3800_sensors.conf"
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

msn24102_specific()
{
	local cpu_bus_offset=18
	# This system do not use auto detected cpu conection table.
	connect_table+=(${msn27002_msn24102_msb78002_base_connect_table[@]})
	add_cpu_board_to_connection_table $cpu_bus_offset

	max_tachos=8
	hotplug_fans=4
	echo 21000 > $config_path/fan_max_speed
	echo 5400 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo "7 8 5 6 3 4 1 2" > $config_path/fan_inversed
	echo 4 > $config_path/cpld_num
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	echo 24c02 > $config_path/psu_eeprom_type
	get_i2c_bus_frequency_default
	echo 8 > $config_path/reset_attr_num
}

msn27002_msb78002_specific()
{
	local cpu_bus_offset=18
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${msn27002_msn24102_msb78002_base_connect_table[@]})
		add_cpu_board_to_connection_table $cpu_bus_offset
	fi

	max_tachos=8
	hotplug_fans=4
	echo 25000 > $config_path/fan_max_speed
	echo 1500 > $config_path/fan_min_speed
	echo 18000 > $config_path/psu_fan_max
	echo 2000 > $config_path/psu_fan_min
	echo 4 > $config_path/cpld_num
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn27002_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn27002.json"
	get_i2c_bus_frequency_default
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

connect_msn4700_msn4600()
{
	if [ "$sku" == "HI124" ]; then
		# msn4600C with removed A2D
		connect_table+=(${msn4600C_base_connect_table[@]})
	else
        # msn4700/msn4600
		connect_table+=(${msn4700_msn4600_base_connect_table[@]})
	fi
	add_i2c_dynamic_bus_dev_connection_table "${msn4700_msn4600_xdpe_voltmon_connect_table[@]}"
	add_cpu_board_to_connection_table
	lm_sensors_config="$lm_sensors_configs_path/msn4700_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn4700.json"
}

connect_msn4700_msn4600_A1()
{
	case $sku in
		HI124|HI156)
			#  msn4600C with removed A2D or msn4700 BF3
			connect_table+=(${msn4600C_A1_base_connect_table[@]})
			;;
		*)
			# msn4700/msn4600 respin 
			connect_table+=(${msn4700_msn4600_A1_base_connect_table[@]})
	esac
	add_i2c_dynamic_bus_dev_connection_table "${msn4700_msn4600_mps_voltmon_connect_table[@]}"
	add_cpu_board_to_connection_table
	lm_sensors_config="$lm_sensors_configs_path/msn4700_respin_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn4700_mps.json"
	named_busses+=(${msn47xx_mqm97xx_named_busses[@]})
	add_come_named_busses
	echo -n "${named_busses[@]}" > $config_path/named_busses
}

msn47xx_specific()
{
	if [ -e "$devtree_file" ]; then
		lm_sensors_config="$lm_sensors_configs_path/msn4700_respin_sensors.conf"
	else
		regio_path=$(find_regio_sysfs_path)
		res=$?
		if [ $res -eq 0 ]; then
			sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
			case $sys_ver in
				1)
					connect_msn4700_msn4600_A1
				;;
				*)
					connect_msn4700_msn4600
				;;
			esac
		else
			connect_msn4700_msn4600
		fi
	fi

	max_tachos=12
	minimal_unsupported=1
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
}

msn46xx_specific()
{
	if [ -e "$devtree_file" ]; then
		lm_sensors_config="$lm_sensors_configs_path/msn4700_respin_sensors.conf"
	else
		regio_path=$(find_regio_sysfs_path)
		res=$?
		if [ $res -eq 0 ]; then
			sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
			case $sys_ver in
				1|3)
					connect_msn4700_msn4600_A1
				;;
				2)
					connect_msn4700_msn4600
					lm_sensors_config="$lm_sensors_configs_path/msn4600c_2_sensors.conf"
				;;
				*)
					connect_msn4700_msn4600
				;;
			esac
		else
			connect_msn4700_msn4600
		fi
	fi

	# this is MSN4600C
	if [ "$sku" == "HI124" ]; then
		thermal_control_config="$thermal_control_configs_path/tc_config_msn4600C.json"
		echo 11000 > $config_path/fan_max_speed
		echo 2235 > $config_path/fan_min_speed
	# this is MSN4600
	else
		thermal_control_config="$thermal_control_configs_path/tc_config_msn4600.json"
		echo 19500 > $config_path/fan_max_speed
		echo 2800 > $config_path/fan_min_speed
	fi

	max_tachos=3
	hotplug_fans=3
	minimal_unsupported=1
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

msn3510_specific()
{
	connect_table+=(${msn3510_base_connect_table[@]})
	add_cpu_board_to_connection_table

	max_tachos=12
	minimal_unsupported=1
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

mqm97xx_specific()
{
	local voltmon_connection_table=()

	if [ -e "$devtree_file" ]; then
		lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
	else
		regio_path=$(find_regio_sysfs_path)
		res=$?
		if [ $res -eq 0 ]; then
			sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
			case $sys_ver in
				0|8)
					connect_table+=(${mqm97xx_rev0_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_mps_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
					;;
				1|9)
					connect_table+=(${mqm97xx_rev1_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_mps_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
					;;
				7)
					connect_table+=(${mqm97xx_power_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_power_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
					;;
				10)
					connect_table+=(${mqm97xx_rev2_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_mps_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
					;;
				11)
					connect_table+=(${mqm97xx_rev0_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_xpde_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
					;;
				12)
					connect_table+=(${mqm97xx_rev1_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_xpde_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
					;;
				5|13)
					connect_table+=(${mqm97xx_rev2_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_xpde_voltmon_connect_table[@]})
					lm_sensors_config="$lm_sensors_configs_path/mqm9700_rev1_sensors.conf"
					;;
				*)
					connect_table+=(${mqm97xx_base_connect_table[@]})
					voltmon_connection_table=(${mqm97xx_mps_def_voltmon_connect_table[@]})
					named_busses+=(${msn47xx_mqm97xx_named_busses[@]})
					add_come_named_busses
					echo -n "${named_busses[@]}" > $config_path/named_busses
					;;
			esac
		else
			connect_table+=(${mqm97xx_base_connect_table[@]})
			voltmon_connection_table=(${mqm97xx_mps_def_voltmon_connect_table[@]})
		fi

		add_i2c_dynamic_bus_dev_connection_table "${voltmon_connection_table[@]}"
		add_cpu_board_to_connection_table
	fi

	case $sku in
	# MQM9701
	HI173)
		lm_sensors_labels="$lm_sensors_configs_path/mqm9701_sensors_labels.json"
		thermal_control_config="$thermal_control_configs_path/tc_config_mqm9701.json"
		lm_sensors_config="$lm_sensors_configs_path/mqm9701_sensors.conf"
		hotplug_psus=0
		hotplug_pwrs=0
		hotplug_pdbs=1
		psu_count=0
		add_i2c_dynamic_bus_dev_connection_table "${mqm97xx_pdb_connect_table[@]}"
		echo C2P > $config_path/system_flow_capability
		;;
	*)
		lm_sensors_labels="$lm_sensors_configs_path/mqm9700_sensors_labels.json"
		thermal_control_config="$thermal_control_configs_path/tc_config_mqm9700.json"
		echo 23000 > $config_path/psu_fan_max
		echo 4600 > $config_path/psu_fan_min
		;;
	esac

	echo 0 > "$config_path"/labels_ready
	max_tachos=14
	hotplug_fans=7
	echo 29500 > $config_path/fan_max_speed
	echo 5000 > $config_path/fan_min_speed
	echo 7 > $config_path/fan_drwr_num
	echo 3 > $config_path/cpld_num
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

mqm9510_specific()
{
	local cpu_bus_offset=18
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${mqm9510_base_connect_table[@]})
		add_i2c_dynamic_bus_dev_connection_table "${mqm9510_dynamic_i2c_bus_connect_table[@]}"
		add_cpu_board_to_connection_table $cpu_bus_offset
	fi
	i2c_bus_def_off_eeprom_cpu=24
	i2c_comex_mon_bus_default=23
	echo 11000 > $config_path/fan_max_speed
	echo 2235 > $config_path/fan_min_speed
	echo 32000 > $config_path/psu_fan_max
	echo 9000 > $config_path/psu_fan_min
	max_tachos=2
	hotplug_fans=2
	leakage_count=3
	leakage_rope_count=1
	echo 4 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/mqm9510_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	named_busses+=(${mqm9510_named_busses[@]})
	add_come_named_busses $ndr_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
}

mqm9520_specific()
{
	local cpu_bus_offset=18
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${mqm9520_base_connect_table[@]})
		add_i2c_dynamic_bus_dev_connection_table "${mqm9520_dynamic_i2c_bus_connect_table[@]}"
		add_cpu_board_to_connection_table $cpu_bus_offset
	fi
	asic_i2c_buses=(2 10)
	i2c_bus_def_off_eeprom_cpu=24
	i2c_comex_mon_bus_default=23
	echo 11000 > $config_path/fan_max_speed
	echo 2235 > $config_path/fan_min_speed
	echo 32000 > $config_path/psu_fan_max
	echo 9000 > $config_path/psu_fan_min
	max_tachos=2
	hotplug_fans=2
	leakage_count=8
	leakage_rope_count=1
	echo 5 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/mqm9520_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	named_busses+=(${mqm9520_named_busses[@]})
	add_come_named_busses $ndr_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
}

mqm87xx_rev1_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${mqm8700_connect_table[@]})
		add_i2c_dynamic_bus_dev_connection_table "${mqm8700_rev1_voltmon_connect_table[@]}"
		add_cpu_board_to_connection_table
	fi

	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_mqm8700.json"
	get_i2c_bus_frequency_default
}

e3597_specific()
{
	connect_table+=(${e3597_base_connect_table[@]})
	add_i2c_dynamic_bus_dev_connection_table "${e3597_dynamic_i2c_bus_connect_table[@]}"
	add_cpu_board_to_connection_table

	max_tachos=14
	hotplug_fans=7
	asic_control=0
	# TODO set correct PSU/case FAN speed
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 4 > $config_path/cpld_num
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	lm_sensors_config="$lm_sensors_configs_path/e3597_sensors.conf"
}

p4697_specific()
{
	local cpu_bus_offset=18
	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
		case $sys_ver in
			0)
				connect_table+=(${p4697_base_connect_table[@]})
				;;
			1)
				connect_table+=(${p4697_rev1_base_connect_table[@]})
				;;
			*)
				connect_table+=(${p4697_base_connect_table[@]})
				;;
		esac
	else
		connect_table+=(${p4697_base_connect_table[@]})
	fi

	add_cpu_board_to_connection_table $cpu_bus_offset
	add_i2c_dynamic_bus_dev_connection_table "${p4697_dynamic_i2c_bus_connect_table[@]}"

	max_tachos=14
	hotplug_fans=7
	erot_count=2
	asic_control=0
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 4 > $config_path/cpld_num
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	lm_sensors_config="$lm_sensors_configs_path/p4697_sensors.conf"
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

msn_spc2_common()
{
	regio_path=$(find_regio_sysfs_path)
	res=$?
	if [ $res -eq 0 ]; then
		sys_ver=$(cut "$regio_path"/config1 -d' ' -f 1)
	else
		sys_ver=0
	fi

	case $sku in
		HI120)
			msn3420_specific
			;;
		HI121)
			msn3510_specific
			;;
		HI100)
			case $sys_ver in
				2)
					mqm87xx_rev1_specific
					;;
				*)
					mqmxxx_msn37x_msn34x_specific
					;;
			esac
			;;
		HI139)
			msn_xh3000_specific
			;;
		HI146)
			sn3750sx_specific
			;;
		*)
			mqmxxx_msn37x_msn34x_specific
			;;
	esac
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

msn_spc3_common()
{
	case $sku in
		HI123|HI124)
			msn46xx_specific
		;;
		HI122)
			msn47xx_specific
		;;
		HI130|HI173)
			mqm97xx_specific
		;;
		HI132)
			e3597_specific
		;;
		HI140)
			mqm9520_specific
		;;
		HI141)
			mqm9510_specific
		;;
		HI142)
			p4697_specific
		;;
		*)
			msn47xx_specific
		;;
	esac
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

bf3_common()
{
	case $sku in
		HI151)
			mqm97xx_specific
			i2c_asic_bus_default=0
			echo 15 > $config_path/cx_default_i2c_bus
			;;
		HI156)
			msn47xx_specific
			i2c_asic_bus_default=0
			echo 15 > $config_path/cx_default_i2c_bus
			;;
		*)
			echo "Unsupported BF3 platform"
			exit 0
			;;
	esac

	jtag_bridge_offset=`cat /proc/iomem | grep mlxplat_jtag_bridge | awk -F '-' '{print $1}'`
	echo $jtag_bridge_offset > $config_path/jtag_bridge_offset
	jtag_pci=`lspci | grep Lattice | grep 9c30 | awk '{print $1}'`
	check_n_link /sys/bus/pci/devices/0000:"$jtag_pci"/resource0 $config_path/jtag_bridge

	if find /sys/devices/platform/MLNXBF49:00/mlxreg-io/hwmon/hwmon*/ | grep -q jtag_enable ; then
		if [ ! -d $jtag_path ]; then
			mkdir $jtag_path
		fi
		check_n_link /sys/devices/platform/MLNXBF49:00/mlxreg-io/hwmon/hwmon*/jtag_enable $jtag_path/jtag_enable
	fi
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

msn48xx_specific()
{
	local cpu_bus_offset=51
	connect_table+=(${msn4800_base_connect_table[@]})
	add_cpu_board_to_connection_table $cpu_bus_offset

	hotplug_linecards=8
	i2c_comex_mon_bus_default=$((cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((cpu_bus_offset+6))
	echo 4 > $config_path/cpld_num
	hotplug_pwrs=4
	hotplug_psus=4
	psu_count=4
	i2c_asic_bus_default=3
	echo 18000 > $config_path/fan_max_speed
	echo 3000 > $config_path/fan_min_speed
	echo 27500 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 14 > $config_path/cx_default_i2c_bus
	lm_sensors_config="$lm_sensors_configs_path/msn4800_sensors.conf"
	lm_sensors_config_lc="$lm_sensors_configs_path/msn4800_sensors_lc.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

sn2201_specific()
{
	local cpu_bus_offset=51
	echo 2 > $config_path/cpld_num
	i2c_asic_bus_default=6
	hotplug_fans=4
	echo 1 > $config_path/fan_dir_eeprom
	echo 22000 > $config_path/fan_max_speed
	echo 2200 > $config_path/fan_min_speed
	echo 16000 > $config_path/psu_fan_max
	echo 2500 > $config_path/psu_fan_min
	cpld2_ver=$(i2cget -f -y 1 0x3d 0x01)
	cpld2_ver=${cpld2_ver:2}
	echo $(( 16#$cpld2_ver )) > $system_path/cpld2_version
	cpld2_mver=$(i2cget -f -y 1 0x3d 0x02)
	cpld2_mver=${cpld2_mver:2}
	echo $(( 16#$cpld2_mver )) > $system_path/cpld2_version_min
	cpld2_pn=$(i2cget -f -y 1 0x3d 0x21 w)
	cpld2_pn=${cpld2_pn:3}
	cpld2_pn=$(( 16#$cpld2_pn ))
	echo $cpld2_pn > $system_path/cpld2_pn
	id0=$(cat /proc/cpuinfo | grep -m1 "core id" | awk '{print $4}')
	id0=$(($id0+2))
	echo $id0> $config_path/core0_temp_id
	id1=$(cat /proc/cpuinfo | grep -m2 "core id" | tail -n1 | awk '{print $4}')
	id1=$(($id1+2))
	echo $id1 > $config_path/core1_temp_id
	sed -i "s/label temp8/label temp$id0/g" $lm_sensors_configs_path/sn2201_sensors.conf
	sed -i "s/label temp14/label temp$id1/g" $lm_sensors_configs_path/sn2201_sensors.conf
	lm_sensors_config="$lm_sensors_configs_path/sn2201_sensors.conf"
	echo 13 > $config_path/reset_attr_num
	# WA for mux idle state issue.
	echo -2 > /sys/devices/pci0000\:00/0000\:00\:1f.0/NVSN2201\:00/i2c_mlxcpld.1/i2c-1/1-0070/idle_state
	if [ "$sku" == "HI168" ]; then
		hotplug_pwrs=0
		hotplug_psus=0
		psu_count=0
		thermal_control_config="$thermal_control_configs_path/tc_config_msn2201_busbar.json"
	else
		hotplug_pwrs=2
		hotplug_psus=2
		thermal_control_config="$thermal_control_configs_path/tc_config_msn2201.json"
	fi
}

p2317_specific()
{
	connect_table+=(${p2317_connect_table[@]})
	add_cpu_board_to_connection_table
	echo 1 > $config_path/cpld_num
	hotplug_fans=0
	hotplug_pwrs=0
	hotplug_psus=0
	echo 1 > $config_path/global_wp_wait_step
	echo 20 > $config_path/global_wp_timeout
	lm_sensors_config="$lm_sensors_configs_path/p2317_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

sn5x00_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${sn5600_base_connect_table[@]})
		add_cpu_board_to_connection_table $ng800_cpu_bus_offset
	fi
	# Set according to front fan max. Rear fan max is 13200
	echo 13800 > $config_path/fan_max_speed
	echo 2800 > $config_path/fan_min_speed
	echo 32500 > $config_path/psu_fan_max
	echo 9500 > $config_path/psu_fan_min
	i2c_comex_mon_bus_default=$((ng800_cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((ng800_cpu_bus_offset+6))
	max_tachos=8
	hotplug_fans=4
	hotplug_pwrs=2
	hotplug_psus=2
	psu2_i2c_addr=0x5a
	if [ "$sku" == "HI147" ]; then
		echo 5 > $config_path/cpld_num
	else
		echo 4 > $config_path/cpld_num
	fi
	lm_sensors_config="$lm_sensors_configs_path/sn5600_sensors.conf"
	named_busses+=(${sn5600_named_busses[@]})
	add_come_named_busses $ng800_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
}

sn5600d_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${sn5600_base_connect_table[@]})
		add_cpu_board_to_connection_table $ng800_cpu_bus_offset
		add_i2c_dynamic_bus_dev_connection_table "${mqm97xx_pdb_connect_table[@]}"
	fi
	# Set according to front fan max. Rear fan max is 13200
	echo 13800 > $config_path/fan_max_speed
	echo 2800 > $config_path/fan_min_speed
	echo C2P > $config_path/system_flow_capability
	i2c_comex_mon_bus_default=$((ng800_cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((ng800_cpu_bus_offset+6))
	max_tachos=8
	hotplug_fans=4
	hotplug_pwrs=0
	hotplug_psus=0
	hotplug_pdbs=1
	psu_count=0
	echo 7 > $config_path/fan_drwr_num
	echo 4 > $config_path/cpld_num
	echo 0 > "$config_path"/labels_ready
	lm_sensors_config="$lm_sensors_configs_path/sn5600d_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_msn5600d.json"
	named_busses+=(${sn5600_named_busses[@]})
	add_come_named_busses $ng800_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
}

sn_spc4_common()
{
	minimal_unsupported=1

	case $sku in
		HI144)	# SN5600
			sn5x00_specific
			thermal_control_config="$thermal_control_configs_path/tc_config_msn5600.json"
		;;
		HI147)	# SN5400
			sn5x00_specific
			thermal_control_config="$thermal_control_configs_path/tc_config_msn5400.json"
		;;
		HI148)	# SN5700
			sn5x00_specific
		;;
		HI174)	# SN5600d
			sn5600d_specific
		;;
		*)
			sn5x00_specific
		;;
	esac
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

p4262_specific()
{
	local cpu_bus_offset=18
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${p4262_base_connect_table[@]})
		add_cpu_board_to_connection_table $cpu_bus_offset
		add_i2c_dynamic_bus_dev_connection_table "${p4262_dynamic_i2c_bus_connect_table[@]}"
	fi
	echo 1 > $config_path/global_wp_wait_step
	echo 20 > $config_path/global_wp_timeout
	echo 3 > $config_path/cpld_num
	hotplug_fans=6
	max_tachos=12
	hotplug_pwrs=0
	hotplug_psus=0
	erot_count=2
	asic_control=0
	health_events_count=4
	pwr_events_count=1
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	lm_sensors_config="$lm_sensors_configs_path/p4262_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	named_busses+=(${p4262_named_busses[@]})
	add_come_named_busses $ndr_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

p4300_specific()
{
	local cpu_bus_offset=18
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${p4300_base_connect_table[@]})
		add_cpu_board_to_connection_table $cpu_bus_offset
		add_i2c_dynamic_bus_dev_connection_table "${p43002_dynamic_i2c_bus_connect_table[@]}"
	fi
	echo 1 > $config_path/global_wp_wait_step
	echo 20 > $config_path/global_wp_timeout
	echo 2 > $config_path/cpld_num
	hotplug_fans=4
	max_tachos=4
	hotplug_pwrs=0
	hotplug_psus=0
	erot_count=1
	asic_control=0
	health_events_count=4
	pwr_events_count=1
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	lm_sensors_config="$lm_sensors_configs_path/p4300_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	named_busses+=(${p4300_named_busses[@]})
	add_come_named_busses $ndr_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

vmod0017_common()
{
	case $sku in
		HI152)	# p4262
			p4262_specific
		;;
		HI159)	# p4300
			p4300_specific
		;;
		*)
			p4262_specific
		;;
	esac
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
}

qm3xxx_specific()
{
	if [ ! -e "$devtree_file" ]; then
		if [ "$sku" == "HI157" ]; then
			connect_table+=(${q3200_base_connect_table[@]})
		elif [ "$sku" == "HI158" ]; then
			connect_table+=(${q3400_base_connect_table[@]})
		fi
		add_cpu_board_to_connection_table $xdr_cpu_bus_offset
	fi
	i2c_comex_mon_bus_default=$((xdr_cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((xdr_cpu_bus_offset+6))
	minimal_unsupported=1

	if [ "$sku" == "HI157" ]; then
		# Set according to front fan max.
		echo 21800 > $config_path/fan_max_speed
		# Set as 20% of max speed
		echo 4360 > $config_path/fan_min_speed
		# Only reverse fans are supported
		echo C2P > $config_path/system_flow_capability
		echo 27500 > $config_path/psu_fan_max
		# Set as 20% of max speed
		echo 5500 > $config_path/psu_fan_min
		max_tachos=10
		hotplug_fans=5
		hotplug_pwrs=4
		hotplug_psus=4
		psu_count=4
		echo 4 > $config_path/cpld_num
		lm_sensors_config="$lm_sensors_configs_path/q3200_sensors.conf"
		lm_sensors_labels="$lm_sensors_configs_path/q3200_sensors_labels.json"
		thermal_control_config="$thermal_control_configs_path/tc_config_q3200.json"
		named_busses+=(${q3200_named_busses[@]})
		asic_i2c_buses=(2 18)
		psu_i2c_map=(4 59 4 58 4 5b 4 5a)
		dummy_psus_supported=1
	elif [ "$sku" == "HI158" ]; then
		# Set according to front fan max.
		echo 21800 > $config_path/fan_max_speed
		# Set as 20% of max speed
		echo 4360 > $config_path/fan_min_speed
		# Only reverse fans are supported
		echo C2P > $config_path/system_flow_capability
		echo 27500 > $config_path/psu_fan_max
		# Set as 20% of max speed
		echo 5500 > $config_path/psu_fan_min
		max_tachos=20
		hotplug_fans=10
		hotplug_pwrs=8
		hotplug_psus=8
		psu_count=8
		echo 6 > $config_path/cpld_num
		lm_sensors_config="$lm_sensors_configs_path/q3400_sensors.conf"
		lm_sensors_labels="$lm_sensors_configs_path/q3400_sensors_labels.json"
		thermal_control_config="$thermal_control_configs_path/tc_config_q3400.json"
		named_busses+=(${q3400_named_busses[@]})
		asic_i2c_buses=(2 18 34 50)
		psu_i2c_map=(4 59 4 58 3 5b 3 5a 4 5d 4 5c 3 5e 3 5f)
		dummy_psus_supported=1
	elif [ "$sku" == "HI175" ] || [ "$sku" == "HI178" ]; then
		# Set according to front fan max.
		echo 13800 > $config_path/fan_max_speed
		# Set as 30% of max speed
		echo 4140 > $config_path/fan_min_speed
		# Only reverse fans are supported
		echo C2P > $config_path/system_flow_capability
		max_tachos=4
		leakage_count=3
		hotplug_fans=2
		hotplug_pwrs=0
		hotplug_psus=0
		psu_count=0
		echo 7 > $config_path/cpld_num
		lm_sensors_config="$lm_sensors_configs_path/q3450_sensors.conf"
		lm_sensors_labels="$lm_sensors_configs_path/q3450_sensors_labels.json"
		thermal_control_config="$thermal_control_configs_path/tc_config_q3450.json"
		named_busses+=(${q3400_named_busses[@]})
		asic_i2c_buses=(2 18 34 50)
	fi

	add_come_named_busses $xdr_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo 0 > "$config_path"/labels_ready
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

qm3xx1_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${q3400_base_connect_table[@]})
		add_cpu_board_to_connection_table $q3401_cpu_bus_offset
		add_i2c_dynamic_bus_dev_connection_table "${mqm97xx_pdb_connect_table[@]}"
	fi
	i2c_comex_mon_bus_default=$((q3401_cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((q3401_cpu_bus_offset+6))
	minimal_unsupported=1

	# Set according to front fan max.
	echo 13500 > $config_path/fan_max_speed
	# Set at rear (outlet) fan min, according to fan vendor table
	echo 2741 > $config_path/fan_min_speed
	# Only reverse fans are supported

	# Set FAN front (inlet) speed limits
	echo 13500 > $config_path/fan_front_max_speed
	echo 2842 > $config_path/fan_front_min_speed

	# Set FAN rear (outlet) speed limits 
	echo 12603 > $config_path/fan_rear_max_speed
	echo 2741 > $config_path/fan_rear_min_speed

	echo C2P > $config_path/system_flow_capability

	max_tachos=16
	hotplug_fans=8
	hotplug_pwrs=0
	hotplug_psus=0
	psu_count=0
	hotplug_pdbs=1
	echo 6 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/q3401_sensors.conf"
	lm_sensors_labels="$lm_sensors_configs_path/q3401_sensors_labels.json"
	thermal_control_config="$thermal_control_configs_path/tc_config_q3401.json"
	named_busses+=(${q3401_named_busses[@]})
	asic_i2c_buses=(2 18 34 50)
	add_come_named_busses $xdr_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo 0 > "$config_path"/labels_ready
	echo $q3401_reset_attr_num > $config_path/reset_attr_num
}

qm_qm3_common()
{
	case $sku in
		HI157)	# Q3200
			qm3xxx_specific
		;;
		HI158)	# Q3400
			qm3xxx_specific
		;;
		HI175|HI178)	# Q3450/Q3451
			qm3xxx_specific
		;;
		HI179)	# Q3401
			qm3xx1_specific
		;;
		*)
			qm3xxx_specific
		;;
	esac
}

smart_switch_common()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${msn4700_msn4600_A1_base_connect_table[@]})
		add_cpu_board_to_connection_table $smart_switch_cpu_bus_offset
		add_i2c_dynamic_bus_dev_connection_table "${msn4700_msn4600_mps_voltmon_connect_table[@]}"
		echo -n "${smart_switch_dpu_dynamic_i2c_bus_connect_table[@]} " > $config_path/i2c_underlying_devices
	fi
	lm_sensors_config="$lm_sensors_configs_path/sn4280_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_sn4280.json"
	named_busses+=(${smart_switch_named_busses[@]})
	echo -n "${named_busses[@]}" > $config_path/named_busses
	max_tachos=4
	minimal_unsupported=1
	echo 11000 > $config_path/fan_max_speed
	echo 3100 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	echo 18 > $config_path/dpu_bus_off
	dpu_count=4
	echo -n "${smart_switch_dpu2host_events[@]}" > "$dpu2host_events_file"
	echo -n "${smart_switch_dpu_events[@]}" > "$dpu_events_file"
	i2c_comex_mon_bus_default=$((smart_switch_cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((smart_switch_cpu_bus_offset+6))
	echo "$smart_switch_reset_attr_num" > $config_path/reset_attr_num
}

n51xxld_specific()
{
	# Report I2C bus ownership for VMOD0021 systems at early initialization
	bmc_to_cpu_ctrl_path=$(ls /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/bmc_to_cpu_ctrl 2>/dev/null | head -n1)
	if [ -f "$bmc_to_cpu_ctrl_path" ]; then
		bus_ownership=$(< "$bmc_to_cpu_ctrl_path")
		if [ "$bus_ownership" = "0" ]; then
			log_info "I2C bus ownership: CPU (bmc_to_cpu_ctrl=0)"
		elif [ "$bus_ownership" = "1" ]; then
			log_info "I2C bus ownership: BMC (bmc_to_cpu_ctrl=1)"
			# Try to enforce ownership to CPU
			echo 0 > /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/bmc_to_cpu_ctrl
		else
			# Should never happen as driver represents CPLD bit
			log_err "I2C bus ownership: Unknown value (bmc_to_cpu_ctrl=$bus_ownership)"
		fi
	else
		log_err "I2C bus ownership: bmc_to_cpu_ctrl file not found"
	fi

	local cpu_bus_offset=55
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${n5110ld_base_connect_table[@]})
		add_cpu_board_to_connection_table $cpu_bus_offset
		add_i2c_dynamic_bus_dev_connection_table "${n5110ld_dynamic_i2c_bus_connect_table[@]}"
		add_i2c_dynamic_bus_dev_connection_table "${so_cartridge_eeprom_connect_table[@]}"
	else
		# Adding Cable Cartridge support which is not included to BOM string.
		case $sku in
		HI166)	# Juliet SO.
			add_i2c_dynamic_bus_dev_connection_table "${so_cartridge_eeprom_connect_table[@]}"
			echo -n "${so_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
			echo 4 > $config_path/cartridge_counter
			;;
		HI169)	# Juliet Ariel.
			add_i2c_dynamic_bus_dev_connection_table "${ariel_cartridge_eeprom_connect_table[@]}"
			echo -n "${ariel_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
			echo 2 > $config_path/cartridge_counter
			;;
		HI167|HI170)	# Juliet NSO
			add_i2c_dynamic_bus_dev_connection_table "${nso_cartridge_eeprom_connect_table[@]}"
			echo -n "${nso_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
			echo 4 > $config_path/cartridge_counter
			;;
		HI176)	# gb300
			add_i2c_dynamic_bus_dev_connection_table "${so_cartridge_eeprom_connect_table[@]}"
			echo -n "${so_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
			echo 4 > $config_path/cartridge_counter
			echo 2 > $config_path/cpld_num
			;;
		HI177)	# Kyber
			echo 0 > $config_path/cartridge_counter
			;;
		*)	# According Juliet SO.
			add_i2c_dynamic_bus_dev_connection_table "${so_cartridge_eeprom_connect_table[@]}"
			echo -n "${so_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
			echo 4 > $config_path/cartridge_counter
			;;
		esac
		# Add VPD explicitly.
		echo ${n5110ld_vpd_connect_table[0]} ${n5110ld_vpd_connect_table[1]} > /sys/bus/i2c/devices/i2c-${n5110ld_vpd_connect_table[2]}/new_device
		if check_simx; then
			echo ${n5110ld_virtual_vpd_connect_table[0]} ${n5110ld_virtual_vpd_connect_table[1]} > /sys/bus/i2c/devices/i2c-${n5110ld_virtual_vpd_connect_table[2]}/new_device
		fi
	fi
	
	asic_i2c_buses=(11 21)
	echo 1 > $config_path/global_wp_wait_step
	echo 20 > $config_path/global_wp_timeout
	lm_sensors_config="$lm_sensors_configs_path/n51xxld_sensors.conf"

	cpld_num=4
	max_tachos=8
	leakage_count=6
	erot_count=3

	case $sku in
		HI162)	# power-on
			max_tachos=8
			echo 6 > $config_path/fan_drwr_num
			thermal_control_config="$thermal_control_configs_path/tc_config_n5110ld.json"
		;;
		HI166|HI169)	# TTM, ARIEL
			echo 4 > $config_path/fan_drwr_num
			thermal_control_config="$thermal_control_configs_path/tc_config_n5110ld_ttm.json"
		;;
		HI167|HI170)	# NSO, NSO no NCI, DGX, MSFT
			echo 4 > $config_path/fan_drwr_num
			thermal_control_config="$thermal_control_configs_path/tc_config_n5100ld.json"
		;;
		HI176)	# gb300
			max_tachos=0
			echo 0 > $config_path/fan_drwr_num
			thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
			lm_sensors_config="$lm_sensors_configs_path/n5500ld_sensors.conf"
			leakage_count=2
			cpld_num=3
		;;
		HI177)	# Kyber
			max_tachos=0
			echo 0 > $config_path/fan_drwr_num
			thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
			lm_sensors_config="$lm_sensors_configs_path/n5240ld_sensors.conf"
			leakage_count=2
			erot_count=4
			cpld_num=3
		;;
		*)
			echo 6 > $config_path/fan_drwr_num
			thermal_control_config="$thermal_control_configs_path/tc_config_n5110ld.json"
		;;
	esac

	echo 2 > $config_path/clk_brd_num
	echo $cpld_num > $config_path/cpld_num
	psu_count=0
	hotplug_fans=0
	hotplug_pwrs=0
	hotplug_psus=0
	asic_control=0
	health_events_count=0
	pwr_events_count=1
	minimal_unsupported=1
	i2c_comex_mon_bus_default=$((cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((cpu_bus_offset+6))
	lm_sensors_labels="$lm_sensors_configs_path/n51xxld_sensors_labels.json"
	echo C2P > $config_path/system_flow_capability
	named_busses+=(${n5110ld_named_busses[@]})
	add_come_named_busses $cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo -n "${l1_power_events[@]}" > "$power_events_file"
	echo "$n51xx_reset_attr_num" > $config_path/reset_attr_num
	if [ $max_tachos -ne 0 ]; then
		echo 33000 > $config_path/fan_max_speed
		echo 6000 > $config_path/fan_min_speed
	fi
	mctp_bus="$n5110_mctp_bus"
	mctp_addr="$n5110_mctp_addr"
	ln -sf /dev/i2c-2 /dev/i2c-8
}

n51xxld_specific_cleanup()
{
	unlink /dev/i2c-8
	# Remove VPD explicitly.
	echo ${n5110ld_vpd_connect_table[1]} > /sys/bus/i2c/devices/i2c-${n5110ld_vpd_connect_table[2]}/delete_device
	if check_simx; then
		echo ${n5110ld_virtual_vpd_connect_table[1]} > /sys/bus/i2c/devices/i2c-${n5110ld_virtual_vpd_connect_table[2]}/delete_device
	fi
}

n61xxld_specific()
{
	case $sku in
	# N6100_LD
	HI180)
		add_i2c_dynamic_bus_dev_connection_table "${n61xxld_cartridge_eeprom_connect_table[@]}"
		echo -n "${n61xxld_cartridge_eeprom_connect_table[@]}" >> "$devtree_file"
		echo 4 > $config_path/cartridge_counter

		asic_i2c_buses=(5 21 37 53)
		echo 1 > $config_path/global_wp_wait_step
		echo 20 > $config_path/global_wp_timeout
		echo 0 > $config_path/i2c_bus_offset
		lm_sensors_config="$lm_sensors_configs_path/n61xxld_sensors.conf"
		thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"

		cpld_num=2
		leakage_count=2
		erot_count=1
		;;
	esac

	echo $cpld_num > $config_path/cpld_num
	echo 0 > $config_path/fan_drwr_num
	psu_count=0
	hotplug_fans=0
	hotplug_pwrs=0
	hotplug_psus=0
	asic_control=0
	max_tachos=0
	health_events_count=0
	pwr_events_count=1
	minimal_unsupported=1
	i2c_bus_def_off_eeprom_vpd=1
	i2c_comex_mon_bus_default=6
	lm_sensors_labels="$lm_sensors_configs_path/n61xxld_sensors_labels.json"
	named_busses+=(${n61xxld_named_busses[@]})
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo -n "${l1_power_events[@]}" > "$power_events_file"
	echo "$n61xx_reset_attr_num" > $config_path/reset_attr_num
	echo 0 > /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/bmc_to_cpu_ctrl
}

sn5640_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${sn5640_base_connect_table[@]})
		add_cpu_board_to_connection_table $ng800_cpu_bus_offset
	fi

	# Set according to front (inlet) fan max, 21800
	echo 21800 > $config_path/fan_max_speed
	# Set at 30% of rear (outlet) fan max, 20500 (according to fan vendor table)
	echo 6468 > $config_path/fan_min_speed

	# Set FAN front (inlet) speed limits
	echo 21800 > $config_path/fan_front_max_speed
	echo 6879 > $config_path/fan_front_min_speed

	# Set FAN rear (outlet) speed limits 
	echo 20500 > $config_path/fan_rear_max_speed
	echo 6468 > $config_path/fan_rear_min_speed
	
	echo C2P > $config_path/system_flow_capability
	echo 27500 > $config_path/psu_fan_max
	# Set as 20% of max speed
	echo 5500 > $config_path/psu_fan_min
	i2c_comex_mon_bus_default=$((ng800_cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((ng800_cpu_bus_offset+6))
	max_tachos=10
	hotplug_fans=5
	hotplug_pwrs=4
	hotplug_psus=4
	psu_count=4
	minimal_unsupported=1
	echo 4 > $config_path/cpld_num
	lm_sensors_config="$lm_sensors_configs_path/sn5640_sensors.conf"

	case $sku in
		HI172)	# Gaur
			thermal_control_config="$thermal_control_configs_path/tc_config_sn5610.json"
		;;
		HI171)	# Bison
			thermal_control_config="$thermal_control_configs_path/tc_config_sn5640.json"
		;;
		*)
			thermal_control_config="$thermal_control_configs_path/tc_config_sn5640.json"
		;;
	esac

	lm_sensors_labels="$lm_sensors_configs_path/sn5640_sensors_labels.json"
	named_busses+=(${sn5640_named_busses[@]})
	add_come_named_busses $ng800_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
	echo 0 > "$config_path"/labels_ready
}

sn58xxld_specific()
{
	case $sku in
	# SN5810_LD
	HI181)
		cpld_num=4
		leakage_count=2
		i2c_asic_bus_default=6
		hotplug_pdbs=1
		;;
	# SN5800_LD
	HI182)
		cpld_num=10
		leakage_count=5
		asic_i2c_buses=(6 22 38 54)
		hotplug_pdbs=4
		;;
	esac

	echo 0 > $config_path/i2c_bus_offset
	lm_sensors_config="$lm_sensors_configs_path/sn58xxld_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"

	echo $cpld_num > $config_path/cpld_num
	echo 0 > $config_path/fan_drwr_num
	psu_count=0
	hotplug_fans=0
	hotplug_pwrs=0
	hotplug_psus=0
	asic_control=0
	max_tachos=0
	health_events_count=0
	minimal_unsupported=1
	i2c_bus_def_off_eeprom_cpu=0
	i2c_bus_def_off_eeprom_vpd=1
	i2c_comex_mon_bus_default=69
	named_busses+=(${sn58xxld_named_busses[@]})
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo "$sn58xx_reset_attr_num" > $config_path/reset_attr_num
	echo 0 > /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/bmc_to_cpu_ctrl
}

sn66xxld_specific()
{
	case $sku in
	# SN6600_LD
	HI193)
		cpld_num=4
		leakage_count=2
		i2c_asic_bus_default=5
		hotplug_pdbs=2
		;;
	esac

	echo 0 > $config_path/i2c_bus_offset
	lm_sensors_config="$lm_sensors_configs_path/sn66xxld_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"

	echo $cpld_num > $config_path/cpld_num
	echo 0 > $config_path/fan_drwr_num
	psu_count=0
	hotplug_fans=0
	hotplug_pwrs=0
	hotplug_psus=0
	asic_control=0
	max_tachos=0
	health_events_count=0
	minimal_unsupported=1
	i2c_bus_def_off_eeprom_cpu=0
	i2c_bus_def_off_eeprom_vpd=1
	i2c_comex_mon_bus_default=5
	named_busses+=(${sn66xxld_named_busses[@]})
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo "$sn66xx_reset_attr_num" > $config_path/reset_attr_num
	echo 0 > /sys/devices/platform/mlxplat/mlxreg-io/hwmon/hwmon*/bmc_to_cpu_ctrl
}

system_cleanup_specific()
{
	case $board_type in
	VMOD0021)
		n51xxld_specific_cleanup
		;;
	*)
		;;
	esac
}

check_system()
{
	# Check ODM
	case $board_type in
		VMOD0001)
			msn27xx_msb_msx_specific
			;;
		VMOD0002)
			msn21xx_specific
			;;
		VMOD0003)
			msn274x_specific
			;;
		VMOD0004)
			msn201x_specific
			;;
		VMOD0005)
			msn_spc2_common
			;;
		VMOD0007)
			msn38xx_specific
			;;
		VMOD0009)
			msn27002_msb78002_specific
			;;
		VMOD0010)
			msn_spc3_common
			;;
		VMOD0011)
			msn48xx_specific
			;;
		VMOD0013)
			sn_spc4_common
			;;
		VMOD0014)
			sn2201_specific
			;;
		VMOD0015)
			p2317_specific
			;;
		VMOD0017)
			vmod0017_common
			;;
		VMOD0016)
			bf3_common
			;;
		VMOD0018)
			qm_qm3_common
			;;
		VMOD0019)
			smart_switch_common
			;;
		VMOD0021)
			n51xxld_specific
			;;
		VMOD0022)
			sn5640_specific
			;;
		VMOD0023)
			n61xxld_specific
			;;
		VMOD0024)
			sn58xxld_specific
			;;
		VMOD0025)
			sn66xxld_specific
			;;
		*)
			product=$(< /sys/devices/virtual/dmi/id/product_name)
			case $product in
				MSN27002|MSB78002)
					msn27002_msb78002_specific
					;;
				MSN24102)
					msn24102_specific
					;;
				MSN274*)
					msn274x_specific
					;;
				MSN21*)
					msn21xx_specific
					;;
				MSN24*)
					msn24xx_specific
					;;
				MSN27*|MSB*|MSX*)
					msn27xx_msb_msx_specific
					;;
				MSN201*)
					msn201x_specific
					;;
				MQM87*|MSN37*)
					mqmxxx_msn37x_msn34x_specific
					;;
				MSN34*)
					msn3420_specific
					;;
				MSN35*)
					msn3510_specific
					;;
				MSN38*)
					msn38xx_specific
					;;
				MSN46*)
					msn46xx_specific
					;;
				MQM97*)
					mqm97xx_specific
					;;
				MQM87*)
					mqm87xx_specific
					;;
				SN2201*)
					sn2201_specific
					;;
				P4697)
					p4697_specific
					;;
				*)
					# Check marginal system, system without SMBIOS customization,
					# only on old types of Mellanox switches.
					cpu_type=$(cat $config_path/cpu_type)
					if grep -q "Mellanox Technologies" /sys/devices/virtual/dmi/id/chassis_vendor ; then
						case $cpu_type in
							$RNG_CPU)
								msn21xx_specific
								;;
							$IVB_CPU)
								msn27xx_msb_msx_specific
								;;
							$BDW_CPU)
								mqmxxx_msn37x_msn34x_specific
								;;
							$BF3_CPU)
								bf3_common
								;;
							*)
								log_err "$product is not supported"
								exit 0
								;;
						esac
					else
						case $cpu_type in
							# First BF3 BU systems will have only SKU configured in SMBIOS
							$BF3_CPU)
								bf3_common
								;;
							*)
								log_err "$product is not supported"
								exit 0
								;;
						esac
					fi
					;;
			esac
			;;
	esac
	echo ${i2c_comex_mon_bus_default} > $config_path/i2c_comex_mon_bus_default
	echo ${i2c_bus_def_off_eeprom_cpu} > $config_path/i2c_bus_def_off_eeprom_cpu
	if check_bmc_is_supported; then
		pushd /usr/bin
		python -c "from hw_management_redfish_client import BMCAccessor; print(BMCAccessor().login())" || true
		popd
	fi
}

create_event_files()
{
	if [ $hotplug_psus -ne 0 ]; then
		for ((i=1; i<=hotplug_psus; i+=1)); do
			check_n_init $events_path/psu$i 0
		done
	fi
	if [ $hotplug_pwrs -ne 0 ]; then
		for ((i=1; i<=hotplug_pwrs; i+=1)); do
			check_n_init $events_path/pwr$i 0
		done
	fi
	if [ $hotplug_pdbs -ne 0 ]; then
		for ((i=1; i<=hotplug_pdbs; i+=1)); do
			check_n_init $events_path/pdb$i 0
		done
	fi
	if [ $hotplug_fans -ne 0 ]; then
		for ((i=1; i<=hotplug_fans; i+=1)); do
			check_n_init $events_path/fan$i 0
		done
	fi
	if [ $hotplug_linecards -ne 0 ]; then
		for ((i=1; i<=hotplug_linecards; i+=1)); do
			check_n_init $events_path/lc"$i"_present 0
			check_n_init $events_path/lc"$i"_verified 0
			check_n_init $events_path/lc"$i"_powered 0
			check_n_init $events_path/lc"$i"_ready 0
			check_n_init $events_path/lc"$i"_synced 0
			check_n_init $events_path/lc"$i"_active 0
			check_n_init $events_path/lc"$i"_shutdown 0
		done
	fi
	if [ $erot_count -ne 0 ]; then
		for ((i=1; i<=erot_count; i+=1)); do
			check_n_init  $events_path/erot"$i"_error 0
			check_n_init $events_path/erot"$i"_ap 0
		done
	fi
	if [ $leakage_count -ne 0 ]; then
		for ((i=1; i<=leakage_count; i+=1)); do
			check_n_init $events_path/leakage"$i" 0
		done
	fi
	if [ $leakage_rope_count -ne 0 ]; then
		for ((i=1; i<=leakage_rope_count; i+=1)); do
			check_n_init $events_path/leakage_rope"$i" 0
		done
	fi
	for ((i=0; i<health_events_count; i+=1)); do
		check_n_init  $events_path/${l1_switch_health_events[$i]}
	done
	if [ $pwr_events_count -ne 0 ]; then
		if [ -f "$power_events_file" ]; then
			declare -a power_events="($(< $power_events_file))"
			for ((i=0; i<=pwr_events_count; i+=1)); do
				check_n_init $events_path/${power_events[$i]} 0
			done
		else
			check_n_init $events_path/power_button 0
		fi
	fi
	if [ $dpu_count -ne 0 ]; then
		create_hotplug_smart_switch_event_files "$dpu2host_events_file" "$dpu_events_file"
	fi
}

enable_vpd_wp()
{
	if [ -e "$system_path"/vpd_wp ]; then
		echo 1 > $system_path/vpd_wp
		log_info "Enabled VPD WP"
	fi
}

load_modules()
{
	# Some modules are not present in all the kernel
	# versions. Use this function to load those modules
	# which need to be loaded based on their availability
	if ! lsmod | grep -q "drivetemp"; then
		if [ -f /lib/modules/`uname -r`/kernel/drivers/hwmon/drivetemp.ko ]; then
			modprobe drivetemp
		fi
	fi
	case $cpu_type in
		$AMD_SNW_CPU|$AMD_V3000_CPU|$BF3_CPU)
			# coretemp driver supported only on Intel chips
			;;
		*)
			if ! check_simx; then
				modprobe coretemp
			fi
			;;
	esac

	case $sku in
		HI162|HI166|HI167|HI169|HI170|HI176|HI177)	# Juliet
			modprobe i2c_asf
			modprobe i2c_designware_platform
		;;
		*)
		;;
	esac
}

set_config_data()
{
	for ((idx=1; idx<=psu_count; idx+=1)); do
		psu_i2c_addr=psu"$idx"_i2c_addr
		echo ${!psu_i2c_addr} > $config_path/psu"$idx"_i2c_addr
	done
	if [ "$psu_count" -gt 0 ]; then
		echo $fan_psu_default > $config_path/fan_psu_default
		echo $fan_command > $config_path/fan_command
		echo $fan_config_command > $config_path/fan_config_command
	fi
	if [ $max_tachos -ne 0 ]; then
		echo $fan_speed_units > $config_path/fan_speed_units
		echo $fan_speed_tolerance > $config_path/fan_speed_tolerance
	fi
	echo 35 > $config_path/thermal_delay
	echo $chipup_delay_default > $config_path/chipup_delay
	echo 0 > $config_path/chipdown_delay
	echo $hotplug_psus > $config_path/hotplug_psus
	echo $hotplug_pwrs > $config_path/hotplug_pwrs
	echo $hotplug_pdbs > $config_path/hotplug_pdbs
	echo $hotplug_fans > $config_path/hotplug_fans
	echo $hotplug_linecards > $config_path/hotplug_linecards
	echo $fan_speed_tolerance > $config_path/fan_speed_tolerance
	echo $leakage_count > $config_path/leakage_counter
	if [ -v "thermal_control_config" ] && [ -f $thermal_control_config ]; then
		cp $thermal_control_config $config_path/tc_config.json
	else
		cp $thermal_control_configs_path/tc_config_not_supported.json $config_path/tc_config.json
	fi
	if [ -v $thermal_control_configs_path/tc_config_user.json ]; then
		cp $thermal_control_configs_path/tc_config_user.json $config_path/tc_config_user.json
	fi
}

connect_platform()
{
	find_i2c_bus
	# Check if it's new or old format of connect table
	if [ -e "$devtree_file" ]; then
		unset connect_table
		declare -a connect_table=($(<"$devtree_file"))
		# New connect table contains also device link name, e.g., fan_amb
		dev_step=4
	else
		dev_step=3
	fi

	for ((i=0; i<${#connect_table[@]}; i+=$dev_step)); do
		for ((j=0; j<${device_connect_retry}; j++)); do
			connect_device "${connect_table[i]}" "${connect_table[i+1]}" \
					"${connect_table[i+2]}"
			if [ $? -eq 0 ]; then
				break;
			fi
			disconnect_device "${connect_table[i+1]}" "${connect_table[i+2]}"
		done
	done
	if [ ! -z $mctp_addr ]; then
		echo $mctp_addr > $config_path/mctp_addr
		echo $mctp_bus > $config_path/mctp_bus
		echo mctp-i2c-interface "0x${mctp_addr}" > /sys/bus/i2c/devices/i2c-"$mctp_bus"/new_device
	fi
}

disconnect_platform()
{
	if [ -f $config_path/i2c_bus_offset ]; then
		i2c_bus_offset=$(<$config_path/i2c_bus_offset)
	fi
	# Check if it's new or old format of connect table
	if [ -e "$devtree_file" ]; then
		dev_step=4
	else
		dev_step=3
	fi
	for ((i=0; i<${#connect_table[@]}; i+=$dev_step)); do
		disconnect_device "${connect_table[i+1]}" "${connect_table[i+2]}"

	# Remove  MCTP interface
	if [ -f $config_path/mctp_addr ]; then
		mctp_addr=$(<$config_path/mctp_addr)
		mctp_bus=$(<$config_path/mctp_bus)
		if [ -f /sys/bus/i2c/devices/i2c-"$mctp_bus"/"$mctp_bus"-"$mctp_addr"/name ]; then
	 		name=$(</sys/bus/i2c/devices/i2c-"$mctp_bus"/"$mctp_bus"-"$mctp_addr"/name )
		 	if [ "$name" = "mctp-i2c-interface" ]; then
				echo  0x"$mctp_addr" > /sys/bus/i2c/devices/i2c-"$mctp_bus"/delete_device
			fi
		fi
	fi
	done
}

create_symbolic_links()
{
	if [ ! -d $hw_management_path ]; then
		mkdir $hw_management_path
	fi
	if [ ! -d $thermal_path ]; then
		mkdir $thermal_path
	fi	
	if [ ! -d $config_path ]; then
		mkdir $config_path
	fi
	if [ ! -d $environment_path ]; then
		mkdir $environment_path
	fi
	if [ ! -d $power_path ]; then
		mkdir $power_path
	fi
	if [ ! -d $alarm_path ]; then
		mkdir $alarm_path
	fi
	if [ ! -d $eeprom_path ]; then
		mkdir $eeprom_path
	fi
	if [ ! -d $led_path ]; then
		mkdir $led_path
	fi
	if [ ! -d $system_path ]; then
		mkdir $system_path
	fi
	if [ ! -d $watchdog_path ]; then
		mkdir $watchdog_path
	fi
	if [ ! -d $events_path ]; then
		mkdir $events_path
	fi
	if [ ! -d $fw_path ]; then
		mkdir $fw_path
	fi
	if [ ! -d $bin_path ]; then
		mkdir $bin_path
		# Copy binaries to make them available for the access from containers.
		cp /usr/bin/hw_management_independent_mode_update.py "$bin_path"
		cp /usr/bin/hw_management_dpu_thermal_update.py "$bin_path"
	fi
	if [ ! -d $dynamic_boards_path ]; then
		mkdir $dynamic_boards_path
	fi
	if [ ! -h $power_path/pwr_consum ]; then
		ln -sf /usr/bin/hw-management-power-helper.sh $power_path/pwr_consum
	fi
	if [ ! -h $power_path/pwr_sys ]; then
		ln -sf /usr/bin/hw-management-power-helper.sh $power_path/pwr_sys
	fi

	if [ ! -f "$config_path/gearbox_counter" ]; then
		echo 0 > "$config_path"/gearbox_counter
	fi
	if [ ! -f "$config_path/module_counter" ]; then
		echo 0 > "$config_path"/module_counter
	fi
	if [ ! -f "$config_path/asic_chipup_counter" ]; then
		echo "$asic_chipup_retry" > "$config_path"/asic_chipup_counter
	fi
}

remove_symbolic_links()
{
	# Clean hw-management directory - remove folder if it's empty
	if [ -d $hw_management_path ]; then
		find $hw_management_path -type l -exec unlink {} \;
		rm -rf $hw_management_path
	fi
}

set_asic_i2c_bus()
{
	local asic_num=1
	local asic_i2c_bus

	if [ -f "$config_path/asic_num" ]; then
		asic_num=$(< $config_path/asic_num)
	fi

	find_i2c_bus

	if [ ${asic_num} -eq 1 ]; then
		if [ ! -f $config_path/asic_bus ]; then
			asic_i2c_bus=$((i2c_asic_bus_default+i2c_bus_offset))
			echo $asic_i2c_bus > $config_path/asic_bus
			echo $asic_i2c_bus > $config_path/asic1_i2c_bus_id
		fi
		return
	fi

	for ((i=1; i<=${asic_num}; i++)); do
		if [ ! -f $config_path/asic${i}_i2c_bus_id ]; then
			asic_i2c_bus=${asic_i2c_buses[$((i-1))]}
			asic_i2c_bus=$((asic_i2c_bus+i2c_bus_offset))
			echo $asic_i2c_bus > $config_path/asic${i}_i2c_bus_id
		fi
	done

	if [ ! -f $config_path/asic_bus ]; then
		asic_i2c_bus=${asic_i2c_buses[0]}
		asic_i2c_bus=$((asic_i2c_bus+i2c_bus_offset))
		echo $asic_i2c_bus > $config_path/asic_bus
	fi
}

set_asic_pci_id()
{
	if [ ! -f "$config_path"/asic_control ]; then
		echo $asic_control > "$config_path"/asic_control
	fi

	if [ ! -f "$config_path"/minimal_unsupported ]; then
		echo $minimal_unsupported > "$config_path"/minimal_unsupported
	fi

	# Get ASIC PCI Ids.
	case $sku in
	HI122|HI123|HI124|HI126|HI156|HI160)
		asic_pci_id=$spc3_pci_id
		;;
	HI130|HI140|HI141|HI151|HI173)
		asic_pci_id=$quantum2_pci_id
		;;
	HI144|HI147|HI148|HI174)
		asic_pci_id=$spc4_pci_id
		;;
	HI131)
		asic_pci_id=$nv3_pci_id
		;;
	HI142|HI143|HI152|HI159)
		asic_pci_id=$nv4_pci_id
		check_asics=`lspci -nn | grep $asic_pci_id | awk '{print $1}'`
		if [ -z "$check_asics" ]; then
			asic_pci_id=$nv4_rev_a1_pci_id
		fi
		;;
	HI157|HI162|HI166|HI167|HI169|HI170|HI175|HI176|HI177|HI178|HI179)
		asic_pci_id=${quantum3_pci_id}
		;;
	HI158)
		asic_pci_id="${quantum3_pci_id}|${quantum2_pci_id}"
		;;
	HI171|HI181|HI182)
		asic_pci_id=$spc5_pci_id
		;;
	HI172)
		asic_pci_id=$spc4_pci_id
		;;
	HI180)
		asic_pci_id="${quantum3_pci_id}|${quantum4_pci_id}"
		;;
	HI193)
		asic_pci_id="${spc5_pci_id}|${spc6_pci_id}"
		;;
	*)
		echo 1 > "$config_path"/asic_num
		return
		;;
	esac

	asics=`lspci -nn | grep -E $asic_pci_id | awk '{print $1}'`
	case $sku in
	HI140)
		asic1_pci_bus_id=`echo $asics | awk '{print $2}'`   # 2-nd for ASIC1 because it appears first
		asic2_pci_bus_id=`echo $asics | awk '{print $1}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo 2 > "$config_path"/asic_num
		;;
	HI131|HI141|HI142|HI152|HI162|HI166|HI167|HI169|HI170|HI176)
		asic1_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $2}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo 2 > "$config_path"/asic_num
		;;
	HI177)
		asic1_pci_bus_id=`echo $asics | awk '{print $2}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $3}'`
		asic3_pci_bus_id=`echo $asics | awk '{print $1}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo "$asic3_pci_bus_id" > "$config_path"/asic3_pci_bus_id
		echo 3 > "$config_path"/asic_num
		;;
	HI143)
		asic1_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $2}'`
		asic3_pci_bus_id=`echo $asics | awk '{print $3}'`
		asic4_pci_bus_id=`echo $asics | awk '{print $4}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo "$asic3_pci_bus_id" > "$config_path"/asic3_pci_bus_id
		echo "$asic4_pci_bus_id" > "$config_path"/asic4_pci_bus_id
		echo 4 > "$config_path"/asic_num
		;;
	HI144|HI147|HI148|HI174)
		asic1_pci_bus_id=`echo $asics | awk '{print $1}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo 1 > "$config_path"/asic_num
		;;
	HI157)
		echo -n "$asics" | grep -c '^' > "$config_path"/asic_num
		[ -z "$asics" ] && return
		asic1_pci_bus_id=`echo $asics | awk '{print $2}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $1}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo 2 > "$config_path"/asic_num
		;;
	HI158|HI179)
		echo -n "$asics" | grep -c '^' > "$config_path"/asic_num
		[ -z "$asics" ] && return
		asic1_pci_bus_id=`echo $asics | awk '{print $3}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $2}'`
		asic3_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic4_pci_bus_id=`echo $asics | awk '{print $4}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo "$asic3_pci_bus_id" > "$config_path"/asic3_pci_bus_id
		echo "$asic4_pci_bus_id" > "$config_path"/asic4_pci_bus_id
		echo 4 > "$config_path"/asic_num
		;;
	HI175|HI178)
		echo -n "$asics" | grep -c '^' > "$config_path"/asic_num
		[ -z "$asics" ] && return
		asic1_pci_bus_id=`echo $asics | awk '{print $2}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $3}'`
		asic3_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic4_pci_bus_id=`echo $asics | awk '{print $4}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo "$asic3_pci_bus_id" > "$config_path"/asic3_pci_bus_id
		echo "$asic4_pci_bus_id" > "$config_path"/asic4_pci_bus_id
		echo 4 > "$config_path"/asic_num
		;;
	HI180)
		echo -n "$asics" | grep -c '^' > "$config_path"/asic_num
		[ -z "$asics" ] && return
		asic1_pci_bus_id=`echo $asics | awk '{print $2}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic3_pci_bus_id=`echo $asics | awk '{print $3}'`
		asic4_pci_bus_id=`echo $asics | awk '{print $4}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo "$asic3_pci_bus_id" > "$config_path"/asic3_pci_bus_id
		echo "$asic4_pci_bus_id" > "$config_path"/asic4_pci_bus_id
		echo 4 > "$config_path"/asic_num
		;;
	HI182)
		echo -n "$asics" | grep -c '^' > "$config_path"/asic_num
		[ -z "$asics" ] && return
		asic1_pci_bus_id=`echo $asics | awk '{print $2}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic3_pci_bus_id=`echo $asics | awk '{print $4}'`
		asic4_pci_bus_id=`echo $asics | awk '{print $3}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo "$asic3_pci_bus_id" > "$config_path"/asic3_pci_bus_id
		echo "$asic4_pci_bus_id" > "$config_path"/asic4_pci_bus_id
		echo 4 > "$config_path"/asic_num
		;;
	*)
		asic1_pci_bus_id=`echo $asics | awk '{print $1}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo 1 > "$config_path"/asic_num
		;;
	esac

	return
}

set_dpu_pci_id()
{
	local dpu_pci_addr=()
	local cpu_type=$(cat $config_path/cpu_type)
	local total_dpu_num
	local idx=0
	local element
	local dpu_detected_num=0

	# Get DPU PCI Ids.
	case $sku in
	HI160)
		dpu_pci_id=$dpu_bf3_pci_id
		;;

	*)
		return
		;;
	esac

	dpus=`lspci -nn | grep -E $dpu_pci_id | awk '{print $1}'`

	case $sku in
	HI160)
		case $cpu_type in
		$CFL_CPU)
			dpu_pci_addr+=( ${dpu_pci_addr_cfl[@]} )
			;;
		$AMD_SNW_CPU)
			dpu_pci_addr+=( ${dpu_pci_addr_amd[@]} )
			;;
		*)
			return
			;;
		esac

		total_dpu_num=${#dpu_pci_addr[@]}

		while [ $idx -lt $total_dpu_num ]; do
			element="${dpu_pci_addr[$idx]}"
			if echo "$dpus" | grep -q -w "$element"; then
				echo "$element" > "$config_path"/dpu$((idx+1))_pci_bus_id
				dpu_detected_num=$((dpu_detected_num + 1))
			else
				echo "" > "$config_path"/dpu$((idx+1))_pci_bus_id
			fi
			idx=$((idx + 1))
		done
		echo "$dpu_detected_num" > "$config_path"/dpu_detected_num
		;;
	*)
		;;
	esac

	return
}

# DIMM Temp sensor driver jc42 doesn't probe/find sodimm_ts on AMD platform
# Check and add availab
set_sodimms()
{
	local i2c_dir
	local i2c_bus
	local amd_snw_sodimm_ts_addr=(0x1a 0x1b 0x1e 0x1f)

	if [ "$cpu_type" != "$AMD_SNW_CPU" ]; then
		return 0
	fi

	if ! lsmod | grep -q i2c_designware_platform; then
		modprobe i2c_designware_platform
		sleep 0.5
	fi

	i2c_dir=$(ls -1d "$sodimm_dev"/i2c-*)
	i2c_bus="${i2c_dir##*-}"
	if check_simx; then
		# i2c-designware emulattion is not available. For the virtual
		# platforms that used AMD comex, sodimm sensor is defined at i2c-10
		i2c_bus=10
	fi
	if [ -z "$i2c_bus" ]; then
		log_err "Error: I2C bus of SODIMMs TS isn't found."
		return 1
	fi

	for ((i=0; i<${#amd_snw_sodimm_ts_addr[@]}; i+=1)); do
		j=$(echo ${amd_snw_sodimm_ts_addr[$i]} | cut -b 3-)
		i2cdetect -y -a -r $i2c_bus ${amd_snw_sodimm_ts_addr[$i]} ${amd_snw_sodimm_ts_addr[$i]} | grep -qi $j
		if [ $? -eq 0 ]; then
			echo "jc42" "${amd_snw_sodimm_ts_addr[$i]}" > /sys/bus/i2c/devices/i2c-$i2c_bus/new_device
		fi
	done
}

pre_devtr_init()
{
	case $board_type in
	VMOD0009)
		case $sku in
		HI117)
			echo $ndr_cpu_bus_offset > $config_path/cpu_brd_bus_offset
			;;
		*)
			;;
		esac
		;;
	VMOD0013)
		case $sku in
		HI144|HI147|HI148|HI174)	# ToDo Possible change for Ibex
			echo $ng800_cpu_bus_offset > $config_path/cpu_brd_bus_offset
			echo 2 > "$config_path"/clk_brd_num
#			echo 3 > "$config_path"/clk_brd_addr_offset
			;;
		*)
			;;
		esac
		;;
	VMOD0017)
		echo $ndr_cpu_bus_offset > $config_path/cpu_brd_bus_offset
		;;
	VMOD0018)
		cpu_bus_offset=$xdr_cpu_bus_offset
		case $sku in
		HI158|HI175|HI178)
			echo 2 > "$config_path"/swb_brd_num
			echo 32 > "$config_path"/swb_brd_bus_offset
			;;
		HI179)
			echo 2 > "$config_path"/swb_brd_num
			echo 32 > "$config_path"/swb_brd_bus_offset
			cpu_bus_offset=$q3401_cpu_bus_offset
			;;	
		*)
			;;
		esac
		echo $cpu_bus_offset > $config_path/cpu_brd_bus_offset
		;;
	VMOD0019)
		case $sku in
		HI160)
			echo 4 > "$config_path"/dpu_num
			echo 1 > "$config_path"/dpu_brd_bus_offset
			echo "dynamic" > "$config_path"/dpu_board_type
			echo $smart_switch_cpu_bus_offset > $config_path/cpu_brd_bus_offset
			;;
		*)
			;;
		esac
		;;
	VMOD0021)
		case $sku in
		HI162|HI166|HI167|HI169|HI170|HI176|HI177)
			echo 55 > $config_path/cpu_brd_bus_offset
			;;
		*)
			;;
		esac
		;;
	VMOD0022)
		case $sku in
		HI171|HI172)
			echo $ng800_cpu_bus_offset > $config_path/cpu_brd_bus_offset
			;;
		esac
		;;
	VMOD0024)
		case $sku in
		HI181)
			echo 1 >  "$config_path"/swb_brd_num
			echo 1 >  "$config_path"/pwr_brd_num
			echo 11 > "$config_path"/swb_brd_vr_num
			echo 1 >  "$config_path"/pwr_brd_pwr_conv_num
			echo 1 >  "$config_path"/pwr_brd_hotswap_num
			echo 1 >  "$config_path"/pwr_brd_temp_sens_num
			;;
		HI182)
			echo 4  > "$config_path"/swb_brd_num
			echo 4  > "$config_path"/pwr_brd_num
			echo 16 > "$config_path"/swb_brd_bus_offset
			echo 16 > "$config_path"/pwr_brd_bus_offset
			echo 11 > "$config_path"/swb_brd_vr_num
			echo 1 >  "$config_path"/pwr_brd_pwr_conv_num
			echo 1 >  "$config_path"/pwr_brd_hotswap_num
			echo 1 >  "$config_path"/pwr_brd_temp_sens_num
			;;
		esac
		;;
	VMOD0025)
		case $sku in
		HI193)
			echo 2 >  "$config_path"/pwr_brd_num
			echo 1 >  "$config_path"/pwr_brd_bus_offset
			echo 1 >  "$config_path"/pwr_brd_pwr_conv_num
			echo 1 >  "$config_path"/pwr_brd_hotswap_num
			echo 1 >  "$config_path"/pwr_brd_temp_sens_num
			;;
		esac
		;;
	*)
		;;
	esac
}

map_asic_pci_to_i2c_bus()
{
	local bus
	local pci_bus
	local i2c_bus
	local asic_num=1

	if [ -z "$1" ]; then
		return 255
	fi
	[ -f "$config_path/asic_num" ] && asic_num=$(< $config_path/asic_num)
	if [ $asic_num -eq 1 ]; then
		return 255
	fi

	if [ $asic_num -gt 1 ]; then
		pci_bus=`basename $1`
		pci_bus="${pci_bus:5}"
		for ((i=1; i<=asic_num; i+=1)); do
			bus=$(< $config_path/asic"$i"_pci_bus_id)
			if [ "$bus" == "$pci_bus" ]; then
				i2c_bus=$(< $config_path/asic"$i"_i2c_bus_id)
				return "$i2c_bus"
			fi
		done
	fi
	return 255
}

map_dummy_psus()
{
	local psu_bus
	local psu_addr
	local psu_num
	local psu_present
	local psu_dev_path

	if [ ! -f "${config_path}/dummy_psus_supported" ]; then
		echo ${dummy_psus_supported} > "${config_path}/dummy_psus_supported"
	fi

	if [ ${dummy_psus_supported} -eq 0 ]; then
		return
	fi

	for ((i=0; i < "${#psu_i2c_map[@]}"; i+=2)); do
		psu_bus=${psu_i2c_map[$i]}
		psu_addr=${psu_i2c_map[$i+1]}
		psu_num=$(((i/2)+1))
		psu_present=$(< $thermal_path/psu${psu_num}_status)
		psu_dev_path="/sys/bus/i2c/devices/${psu_bus}-00${psu_addr}"
		if [ ${psu_present} -eq 1 ] && [ ! -d ${psu_dev_path} ]; then
			touch ${config_path}/psu${psu_num}_is_dummy
		fi
	done
}

report_sed_pba_ver()
{
    if command -v sedutil-cli &> /dev/null; then
		# Scan for OPAL2 compliant drives
		opal_drive=$(sedutil-cli --scan 2>/dev/null | \
		awk '/^\/dev\/(sda|nvme[0-9]+)/ && $2 == "2" {print $1; exit}')

		if [ -n "$opal_drive" ]; then
			# Check if MBREnabled is Y for the detected OPAL2 drive
			if sedutil-cli --query "$opal_drive" 2>/dev/null | grep -q "MBREnabled = Y"; then
				if [ -f "/sys/firmware/efi/efivars/SedPbaVer-$sed_pba_guid" ]; then
					# Use dd to directly read variable data, skipping first 4 bytes (attributes)
					raw_data=$(dd if="/sys/firmware/efi/efivars/SedPbaVer-$sed_pba_guid" bs=1 skip=4 2>/dev/null | tr -d '\0')
					# Extract just version without build date
					sed_pba_ver=$(echo "$raw_data" | awk '{print $1}')
				else
					sed_pba_ver="N/A"
				fi
            else
                sed_pba_ver="N/A"
            fi
        else
            sed_pba_ver="N/A"
        fi
    else
        sed_pba_ver="N/A"
    fi
    echo "$sed_pba_ver" > "$system_path"/sed_pba_ver
}

do_start()
{
	show_hw_info
	init_sysfs_monitor_timestamp_files
	create_symbolic_links
	run_fixup_script pre
	check_cpu_type
	pre_devtr_init
	load_modules
	devtr_check_smbios_device_description
	check_system
	set_asic_pci_id
	set_sodimms
	set_config_data

	if [ -v "lm_sensors_labels" ] && [ -f $lm_sensors_labels ]; then
		ln -sf $lm_sensors_labels $config_path/lm_sensors_labels
	fi
	asic_control=$(< $config_path/asic_control) 
	if [[ $asic_control -ne 0 ]]; then
		set_asic_i2c_bus
	fi
	touch $udev_ready
	depmod -a 2>/dev/null
	
	udevadm trigger --action=add
	udevadm settle
	set_sodimm_temp_limits
	set_gpios "export"
	create_event_files
	hw-management-i2c-gpio-expander.sh
	connect_platform
	sleep 1
	enable_vpd_wp
	echo 0 > $config_path/events_ready
	/usr/bin/hw-management-start-post.sh
	map_dummy_psus

	if [ -f $config_path/max_tachos ]; then
		max_tachos=$(<$config_path/max_tachos)
	fi
	report_sed_pba_ver

	if [ -v "lm_sensors_config_lc" ] && [ -f $lm_sensors_config_lc ]; then
		ln -sf $lm_sensors_config_lc $config_path/lm_sensors_config_lc
	fi
	if [ -v "lm_sensors_config" ] && [ -f $lm_sensors_config ]; then
		ln -sf $lm_sensors_config $config_path/lm_sensors_config
	else
		ln -sf /etc/sensors3.conf $config_path/lm_sensors_config
	fi
	if [ -v "thermal_control_config" ] && [ -f $thermal_control_config ]; then
		cp $thermal_control_config $config_path/tc_config.json
	else
		cp $thermal_control_configs_path/tc_config_not_supported.json $config_path/tc_config.json
	fi
	log_info "Init completed."
}

do_stop()
{
	check_cpu_type
	# There is no need to perform extra work of check_system during
	# hw-management stop in case of devtree exist. Directly init connect_table.
	if [ -e "$devtree_file" ]; then
		unset connect_table
		declare -a connect_table=($(<"$devtree_file"))
	else
		check_system
	fi
	disconnect_platform
	system_cleanup_specific
	set_gpios "unexport"
	rm -fR /var/run/hw-management
	# Re-try removing after 1 second in case of failure.
	# It can happens if some app locked file for reading/writing
	if [ "$?" -ne 0 ]; then
		sleep 1
		rm -fR /var/run/hw-management
	fi
}

function find_asic_hwmon_path()
{
	local path=$1
	if [ ! -d "$path" ]; then
		return 1
	fi
	return 0
}

do_chip_up_down()
{
	local action=$1
	local asic_index=$2
	local asic_pci_bus=$3
	local asic_i2c_bus

	if [ -f "$config_path"/asic_control ]; then
		asic_control=$(< $config_path/asic_control)
	fi
	# Add ASIC device.
	if [[ $asic_control -eq 0 ]]; then
		log_info "Current ASIC type does not support this operation type"
		return 0
	fi

	if [ -f "$config_path"/minimal_unsupported ]; then
		minimal_unsupported=$(< $config_path/minimal_unsupported)
	fi

	board=$(cat /sys/devices/virtual/dmi/id/board_name)
	case $board in
		VMOD0005)
			case $sku in
				HI146)
					# Chip up / down operations are to be performed for ASIC virtual address 0x37.
					# Disabling it for the timebeing. Will have to enable once h/w resolves the issue
					# i2c_asic_addr_name=0037
					# i2c_asic_addr=0x37
					;;
				*)
					;;
			esac
			;;
		VMOD0010)
			case $sku in
				HI140|HI141)
					# Chip up / down operations are to be performed for ASIC virtual address 0x37.
					i2c_asic_addr_name=0037
					i2c_asic_addr=0x37
					;;
				*)
					;;
			esac
			;;
		VMOD0011)
			# Chip up / down operations are to be performed for ASIC virtual address 0x37.
			i2c_asic_addr_name=0037
			i2c_asic_addr=0x37
			i2c_asic_bus_default=3
			;;
		*)
			;;
	esac

	map_asic_pci_to_i2c_bus $asic_pci_bus
	asic_i2c_bus=$?
	if [ $asic_i2c_bus -eq 255 ]; then
		set_asic_i2c_bus
		if [ -n "$asic_index" ] && [ $asic_index -gt 0 ]; then
			asic_i2c_bus=$(< $config_path/asic${asic_index}_i2c_bus_id)
		else
			asic_i2c_bus=$(< $config_path/asic_bus)
		fi
	fi

	case $action in
	0)
		lock_service_state_change

		# If FAN PWM is controllded by ASIC - set it to 100%
		pwm_link=$thermal_path/pwm1
		if [ -L ${pwm_link} ] && [ -e ${pwm_link} ];
		then
			pwm_src=$(readlink -f ${pwm_link})
			asic_i2c_add=/sys/devices/platform/mlxplat/i2c_mlxcpld.1/i2c-1/i2c-"$asic_i2c_bus"/"$asic_i2c_bus"-"$i2c_asic_addr_name"
			if [[ "$pwm_src" == *"$asic_i2c_add"* ]]; then
				echo  255 > $pwm_link
				log_info "Set PWM to maximum speed prior fan driver removing."
			fi
		fi

		chipup_delay=$(< $config_path/chipup_delay)
		if [ -d /sys/bus/i2c/devices/"$asic_i2c_bus"-"$i2c_asic_addr_name" ] && [[ ${minimal_unsupported:-0} -eq 0 ]]; then
			chipdown_delay=$(< $config_path/chipdown_delay)
			sleep "$chipdown_delay"
			set_i2c_bus_frequency_400KHz
			echo $i2c_asic_addr > /sys/bus/i2c/devices/i2c-"$asic_i2c_bus"/delete_device
			restore_i2c_bus_frequency_default
		else
			unlock_service_state_change
			return 0
		fi
		unlock_service_state_change_update_and_match $config_path/asic_chipup_completed -1 $config_path/asic_num $config_path/asics_init_done
		asic_chipup_completed=$(< $config_path/asic_chipup_completed)
		;;
	1)
		lock_service_state_change
		[ -f "$config_path/chipup_dis" ] && disable=$(< $config_path/chipup_dis)
		if [ "$disable" ] && [ "$disable" -gt 0 ]; then
			disable=$((disable-1))
			echo $disable > $config_path/chipup_dis
			unlock_service_state_change
			exit 0
		fi
		chipup_delay=$(< $config_path/chipup_delay)
		if [ ! -d /sys/bus/i2c/devices/"$asic_i2c_bus"-"$i2c_asic_addr_name" ] && [[ ${minimal_unsupported:-0} -eq 0 ]]; then
			sleep "$chipup_delay"
			set_i2c_bus_frequency_400KHz
			echo mlxsw_minimal $i2c_asic_addr > /sys/bus/i2c/devices/i2c-"$asic_i2c_bus"/new_device
			restore_i2c_bus_frequency_default
			chipup_test_time=$?
			chipup_test_time=`awk -v var1=$chipup_test_time -v var2=10 'BEGIN { print  ( var1 / var2 ) }'`
			retry_helper find_asic_hwmon_path "$chipup_test_time" "$chipup_retry_count" "chip hwmon object" /sys/bus/i2c/devices/"$asic_i2c_bus"-"$i2c_asic_addr_name"/hwmon
			if [ $? -ne 0 ]; then
				# chipup command failed.
				unlock_service_state_change
				return 1
			fi

			if [ -f "$config_path/cpld_port" ] && [ -f $system_path/cpld3_version ]; then
				# Append port CPLD version.
				str=$(< $system_path/cpld_base)
				cpld_port=$(< $system_path/cpld3_version)
				str=$str$(printf "_CPLD000000_REV%02d00" "$cpld_port")
				echo "$str" > $system_path/cpld
			fi
		else
			unlock_service_state_change
			return 0
		fi
		if [ ! -f "$config_path/asic_chipup_completed" ]; then
			echo 0 > "$config_path/asic_chipup_completed"
		fi
		if [ ! -f "$config_path/asics_init_done" ]; then
			echo 0 > "$config_path/asics_init_done"
		fi
		unlock_service_state_change_update_and_match "$config_path/asic_chipup_completed" 1 "$config_path/asic_num" "$config_path/asics_init_done"
		return 0
		;;
	*)
		exit 1
		;;
	esac
}


do_chip_down()
{
	# Delete ASIC device
	/usr/bin/hw-management-thermal-events.sh change hotplug_asic down %S %p
}

__usage="
Usage: $(basename "$0") [Options]

Options:
	start		Start hw-management service, supposed to be
			activated at initialization by system service
			control.
	stop		Stop hw-management service, supposed to be
			activated at system shutdown by system service
			control.
	chipup		Manual activation of ASIC I2C driver.
	chipdown	Manual de-activation of ASIC I2C driver.
	chipupen	Set 'chipup_dis' attribute to zero.
	chipupdis <n>	Set 'chipup_dis' attribute to <n>, when <n>
	thermsuspend	Suspend thermal control (if thermal control is
			activated by hw-management package.
			Not relevant for users who disable hw-management
			thermal control.
	thermresume	Resume thermal control.
			Not relevant for users who disable hw-management
			thermal control.
	restart
	force-reload	Performs hw-management 'stop' and the 'start.
	reset-cause	Output system reset cause.
"

# Check if BSP supports platform in SimX. If the platform is supported continue with
# normal initialization. Otherwise exit from the initialization
if check_simx; then
	if ! check_if_simx_supported_platform; then
		exit 0
	fi
fi

case $ACTION in
	start)
		if [ -d /var/run/hw-management ]; then
			log_err "hw-management is already started"
			exit 1
		fi
		# TEMPORARY hw-management mockup values for HI180 in simx
		if check_simx && [ "$sku" == "HI180" -o "$sku" == "HI181" -o "$sku" == "HI193" ]; then
			tar -xzf /etc/hw-management-virtual/hwmgmt_$sku.tgz -C /var/run/
			log_info "Created mock hw management tree, exiting."
			exit 0
		fi
		do_start
	;;
	stop)
		if [ -d /var/run/hw-management ]; then
			echo 1 > $config_path/stopping
			if [ ! -f "$config_path/asic_num" ]; then
				asic_num=1
			else
				asic_num=$(< $config_path/asic_num)
			fi
			for ((i=1; i<=asic_num; i+=1)); do
				do_chip_up_down 0 "$i"
			done
			do_stop
		fi
	;;
	chipup)
		if [ -d /var/run/hw-management ]; then
			asic_retry="$asic_chipup_retry"
			asic_chipup_rc=1

			while [ "$asic_chipup_rc" -ne 0 ] && [ "$asic_retry" -gt 0 ]; do
				do_chip_up_down 1 "$2" "$3"
				asic_chipup_rc=$?
				asic_index="$2"
				if [ "$asic_chipup_rc" -ne 0 ];then
					do_chip_up_down 0 "$2" "$3"
				else
					echo "$asic_chipup_retry" > "$config_path"/asic_chipup_counter
					exit 0
				fi

				asic_retry=$(< $config_path/asic_chipup_counter)
				if [ "$asic_retry" -eq "$asic_chipup_retry" ]; then
					# Start I2C tracer.
					echo 1 >/sys/kernel/debug/tracing/events/i2c/enable
					echo adapter_nr=="$2" >/sys/kernel/debug/tracing/events/i2c/filter
				else
					cat /sys/kernel/debug/tracing/trace >> /var/log/chipup_i2c_trace_log
					echo 0>/sys/kernel/debug/tracing/trace
				fi

				change_file_counter $config_path/asic_chipup_counter -1
			done
			echo 0 >/sys/kernel/debug/tracing/events/i2c/enable
			log_info "chipup failed for ASIC $asic_index"

			# Check log size in (bytes) and rotate if necessary.
			file_size=`du -b /var/log/chipup_i2c_trace_log | tr -s '\t' ' ' | cut -d' ' -f1`
			if [ $file_size -gt $chipup_log_size ]; then
				timestamp=`date +%s`
				mv /var/log/chipup_i2c_trace_log /var/log/chipup_i2c_trace_log.$timestamp
				touch /var/log/chipup_i2c_trace_log
			fi
		fi
	;;
	chipdown)
		if [ -d /var/run/hw-management ]; then
			do_chip_up_down 0 "$2" "$3"
		fi
	;;
	chipupen)
		echo 0 > $config_path/chipup_dis
	;;
	chipupdis)
		if [ -z "$2" ]; then
			echo 1 > $config_path/chipup_dis
		else
			echo "$2" > $config_path/chipup_dis
		fi
	;;
	thermsuspend)
		if [ -d /var/run/hw-management ]; then
			echo 1 > $config_path/suspend
		fi
	;;
	thermresume)
		if [ -d /var/run/hw-management ]; then
			echo 0 > $config_path/suspend
		fi
	;;
	restart|force-reload)
		do_stop
		sleep 3
		# TEMPORARY hw-management mockup values for HI180 in simx
		if check_simx && [ "$sku" == "HI180" -o "$sku" == "HI181" -o "$sku" == "HI193" ]; then
			tar -xzf /etc/hw-management-virtual/hwmgmt_$sku.tgz -C /var/run/
			log_info "Created mock hw management tree, exiting."
			exit 0
		fi
		do_start
	;;
	reset-cause)
		for f in $system_path/reset_*;
			do v=`cat $f`; attr=$(basename $f); if [ $v -eq 1 ]; then echo $attr; fi;
		done
	;;
	*)
		echo "$__usage"
		exit 1
	;;
esac
exit 0
