#!/bin/bash
################################################################################
# Copyright (c) 2018-2022, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
board_type=$(< $board_type_file)
sku=$(< $sku_file)
source hw-management-devtree.sh
# Local constants and variables

thermal_type=$thermal_type_def
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
hotplug_linecards=0
erot_count=0
health_events_count=0
pwr_events_count=0
dpu_count=0
i2c_bus_def_off_eeprom_cpu=16
i2c_comex_mon_bus_default=15
lm_sensors_configs_path="/etc/hw-management-sensors"
thermal_control_configs_path="/etc/hw-management-thermal"
tune_thermal_type=0
i2c_freq_400=0xf
i2c_freq_reg=0x2004
# ASIC PCIe Ids.
spc3_pci_id=cf70
spc4_pci_id=cf80
quantum2_pci_id=d2f2
quantum3_pci_id=d2f4
nv3_pci_id=1af1
nv4_pci_id=22a3
nv4_rev_a1_pci_id=22a4
dpu_bf3_pci_id=c2d5
leakage_count=0
asic_chipup_retry=2
chipup_log_size=4096
reset_dflt_attr_num=18

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
qm3400_base_connect_table=( \
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
qm3000_base_connect_table=( \
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
	adt75 0x48 7 \
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
	tmp421 0x0 0x1f tmp421 dpu_cx_amb \
	mp2975 0x0 0x68 dpu_voltmon1 \
	mp2975 0x0 0x69 dpu_voltmon2 \
	mp2975 0x0 0x6a dpu_voltmon3)

# I2C busses naming.
cfl_come_named_busses=( come-vr 15 come-amb 15 come-fru 16 )
amd_epyc_named_busses=( come-vr 39 come-amb 39 come-fru 40 )
msn47xx_mqm97xx_named_busses=( asic1 2 pwr 4 vr1 5 amb1 7 vpd 8 )
mqm9510_named_busses=( asic1 2 asic2 3 pwr 4 vr1 5 vr2 6 amb1 7 vpd 8 )
mqm9520_named_busses=( asic1 2 pwr 4 vr1 5 amb1 7 vpd 8 asic2 10 vr2 13 )
sn5600_named_busses=( asic1 2 pwr 4 vr1 5 fan-amb 6 port-amb 7 vpd 8 )
p4262_named_busses=( pdb 4 ts 7 vpd 8 erot1 15 erot2 16 vr1 26 vr2 29 )
p4300_named_busses=( ts 7 vpd 8 erot1 15 vr1 26 vr2 29 )
qm3400_named_busses=( asic1 2 asic2 18 pwr 4 vr1 5 vr2 21 fan-amb 6 port-amb 7 vpd 8 )
qm3000_named_busses=( asic1 2 asic2 18 asic3 34 asic4 50 pwr1 4 pwr2 3 vr1 5 vr2 21 vr3 37 vr4 53 fan-amb 6 port-amb 7 vpd 8 )
smart_switch_named_busses=( asic1 2 pwr 4 vr1 5 amb1 7 vpd 8 dpu1 17 dpu2 18 dpu3 19 dpu4 20)

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
		fi
		;;
	*)
		;;
	esac
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

	if find /sys/bus/i2c/drivers/jc42/[0-9]*/ | grep -q hwmon ; then
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
		ln -sf /sys/class/gpio/gpio$gpio_tck/value $jtag_path/jtag_tck
		ln -sf /sys/class/gpio/gpio$gpio_tms/value $jtag_path/jtag_tms
		ln -sf /sys/class/gpio/gpio$gpio_tdo/value $jtag_path/jtag_tdo
		ln -sf /sys/class/gpio/gpio$gpio_tdi/value $jtag_path/jtag_tdi
		if [ "$board_type" == "VMOD0014" ]; then
			check_n_link /sys/class/gpio/gpio$gpio_mux_rst/value $system_path/mux_reset
			check_n_link /sys/class/gpio/gpio$gpio_jtag_mux_en/value $jtag_path/jtag_mux_en
			check_n_link /sys/class/gpio/gpio$gpio_jtag_enable/value $jtag_path/jtag_enable
		fi
	fi
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
				# MQM9700, P4697, P4262, P4300 removed A2D from CFL
				HI130|HI142|HI152|HI157|HI158|HI159)
					cpu_connection_table=( ${cpu_type2_connection_table[@]} )
					;;
				*)
					cpu_connection_table=( ${cpu_type2_A2D_connection_table[@]} )
					;;
			esac
			cpu_voltmon_connection_table=( ${cpu_type2_mps_voltmon_connection_table[@]} )
			;;
		$BF3_CPU)
			cpu_connection_table=( ${bf3_come_connection_table[@]} )
			cpu_voltmon_connection_table=( ${bf3_come_voltmon_connection_table[@]} )
			;;
		$AMD_EPYC_CPU)
			cpu_connection_table=( ${cpu_type1_connection_table[@]} )
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
	$AMD_EPYC_CPU)
		come_named_busses+=( ${amd_epyc_named_busses[@]} )
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

	thermal_type=$thermal_type_t3
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

	thermal_type=$thermal_type_t2
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
			thermal_type=$thermal_type_t1
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
		*)
			;;
	esac
	add_cpu_board_to_connection_table

	case $sku in
		HI138)
			hotplug_fans=0
			max_tachos=0
		;;
		*)
			thermal_type=$thermal_type_t1
			max_tachos=8
			hotplug_fans=4
			echo 25000 > $config_path/fan_max_speed
			echo 1500 > $config_path/fan_min_speed
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

	thermal_type=$thermal_type_t4
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
			connect_table+=(${msn37xx_secured_connect_table[@]})
			voltmon_connection_table=(${mqm8700_voltmon_connect_table[@]})
			thermal_control_config="$thermal_control_configs_path/tc_config_msn3700C.json"
		;;
		HI112|MSN3700)
			# msn3700
			connect_msn3700
			thermal_control_config="$thermal_control_configs_path/tc_config_msn3700.json"
		;;
		HI116|MSN3700C)
			# mmsn3700C
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

	tune_thermal_type=1
	thermal_type=$thermal_type_t5
	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
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

	tune_thermal_type=1
	thermal_type=$thermal_type_t5
	max_tachos=12
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

	thermal_type=$thermal_type_t9
	max_tachos=10
	hotplug_fans=5
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	echo 24c02 > $config_path/psu_eeprom_type
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
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
	tune_thermal_type=1
	thermal_type=$thermal_type_t5
	echo 3 > $config_path/cpld_num
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	lm_sensors_config="$lm_sensors_configs_path/msn3700_sensors.conf"
	get_i2c_bus_frequency_default
}

msn38xx_specific()
{
	connect_table+=(${msn3800_base_connect_table[@]})
	add_cpu_board_to_connection_table

	thermal_type=$thermal_type_t7
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

	thermal_type=$thermal_type_t1
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

	thermal_type=$thermal_type_t1
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

	thermal_type=$thermal_type_t10
	max_tachos=12
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
		thermal_type=$thermal_type_t8
		thermal_control_config="$thermal_control_configs_path/tc_config_msn4600C.json"
		echo 11000 > $config_path/fan_max_speed
		echo 2235 > $config_path/fan_min_speed
	# this is MSN4600
	else
		thermal_type=$thermal_type_t12
		thermal_control_config="$thermal_control_configs_path/tc_config_msn4600.json"
		echo 19500 > $config_path/fan_max_speed
		echo 2800 > $config_path/fan_min_speed
	fi

	max_tachos=3
	hotplug_fans=3
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

msn3510_specific()
{
	connect_table+=(${msn3510_base_connect_table[@]})
	add_cpu_board_to_connection_table

	thermal_type=$thermal_type_def
	max_tachos=12
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
	lm_sensors_config="$lm_sensors_configs_path/mqm9700_sensors.conf"
	lm_sensors_labels="$lm_sensors_configs_path/mqm9700_sensors_labels.json"
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

	thermal_control_config="$thermal_control_configs_path/tc_config_mqm9700.json"
	echo 0 > "$config_path"/labels_ready
	thermal_type=$thermal_type_def
	max_tachos=14
	hotplug_fans=7
	echo 29500 > $config_path/fan_max_speed
	echo 5000 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
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
	thermal_type=$thermal_type_def
	i2c_bus_def_off_eeprom_cpu=24
	i2c_comex_mon_bus_default=23
	echo 11000 > $config_path/fan_max_speed
	echo 2235 > $config_path/fan_min_speed
	echo 32000 > $config_path/psu_fan_max
	echo 9000 > $config_path/psu_fan_min
	max_tachos=2
	hotplug_fans=2
	leakage_count=3
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
	thermal_type=$thermal_type_def
	echo 11000 > $config_path/fan_max_speed
	echo 2235 > $config_path/fan_min_speed
	echo 32000 > $config_path/psu_fan_max
	echo 9000 > $config_path/psu_fan_min
	max_tachos=2
	hotplug_fans=2
	leakage_count=8
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

	thermal_type=$thermal_type_t5
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

	thermal_type=$thermal_type_def
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

	thermal_type=$thermal_type_def
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
		HI130)
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
	thermal_type=$thermal_type_t13
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
	thermal_type=$thermal_type_t11
	i2c_asic_bus_default=6
	hotplug_fans=4
	hotplug_pwrs=2
	hotplug_psus=2
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
	thermal_control_config="$thermal_control_configs_path/tc_config_msn2201.json"
	echo 13 > $config_path/reset_attr_num
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

sn56xx_specific()
{
	if [ ! -e "$devtree_file" ]; then
		connect_table+=(${sn5600_base_connect_table[@]})
		add_cpu_board_to_connection_table $ng800_cpu_bus_offset
	fi
	# ToDo Uncomment when will be defined	thermal_type=$thermal_type_t14
	thermal_type=$thermal_type_def	# ToDo Temporary default 60%
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

sn_spc4_common()
{
	# ToDo Meantime same for all SPC4 systems.
	case $sku in
		HI144)	# SN5600
			sn56xx_specific
			thermal_control_config="$thermal_control_configs_path/tc_config_msn5600.json"
		;;
		HI147)	# SN5400
			sn56xx_specific
			thermal_control_config="$thermal_control_configs_path/tc_config_msn5400.json"
		;;
		HI148)	# SN5700
			sn56xx_specific
		;;
		*)
			sn56xx_specific
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
	thermal_type=$thermal_type_def
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	lm_sensors_config="$lm_sensors_configs_path/p4262_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	add_i2c_dynamic_bus_dev_connection_table "${p4262_dynamic_i2c_bus_connect_table[@]}"
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
	thermal_type=$thermal_type_def
	i2c_comex_mon_bus_default=23
	i2c_bus_def_off_eeprom_cpu=24
	lm_sensors_config="$lm_sensors_configs_path/p4300_sensors.conf"
	thermal_control_config="$thermal_control_configs_path/tc_config_not_supported.json"
	add_i2c_dynamic_bus_dev_connection_table "${p43002_dynamic_i2c_bus_connect_table[@]}"
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
			connect_table+=(${qm3400_base_connect_table[@]})
		else
			connect_table+=(${qm3000_base_connect_table[@]})
		fi
		add_cpu_board_to_connection_table $xdr_cpu_bus_offset
	fi
	# Set according to front fan max.
	echo 21800 > $config_path/fan_max_speed
	# Set as 20% of max speed
	echo 4360 > $config_path/fan_min_speed
	# Only reverse fans are supported
	echo C2P > $config_path/system_flow_capability
	echo 27500 > $config_path/psu_fan_max
	# Set as 20% of max speed
	echo 5500 > $config_path/psu_fan_min
	i2c_comex_mon_bus_default=$((xdr_cpu_bus_offset+5))
	i2c_bus_def_off_eeprom_cpu=$((xdr_cpu_bus_offset+6))

	if [ "$sku" == "HI157" ]; then
		max_tachos=10
		hotplug_fans=5
		hotplug_pwrs=4
		hotplug_psus=4
		psu_count=4
		echo 4 > $config_path/cpld_num
		lm_sensors_config="$lm_sensors_configs_path/qm3400_sensors.conf"
		lm_sensors_labels="$lm_sensors_configs_path/qm3400_sensors_labels.json"
		thermal_control_config="$thermal_control_configs_path/tc_config_qm3400.json"
		named_busses+=(${qm3400_named_busses[@]})
		asic_i2c_buses=(2 18)
	else
		max_tachos=20
		hotplug_fans=10
		hotplug_pwrs=8
		hotplug_psus=8
		psu_count=8
		echo 6 > $config_path/cpld_num
		lm_sensors_config="$lm_sensors_configs_path/qm3000_sensors.conf"
		lm_sensors_labels="$lm_sensors_configs_path/qm3000_sensors_labels.json"
		thermal_control_config="$thermal_control_configs_path/tc_config_qm3000.json"
		named_busses+=(${qm3000_named_busses[@]})
		asic_i2c_buses=(2 18 34 50)
	fi

	add_come_named_busses $xdr_cpu_bus_offset
	echo -n "${named_busses[@]}" > $config_path/named_busses
	echo 0 > "$config_path"/labels_ready
}

qm_qm3_common()
{
	case $sku in
		HI157)	# QM3400
			qm3xxx_specific
		;;
		HI158)	# QM3000
			qm3xxx_specific
		;;
		*)
			qm3xxx_specific
		;;
	esac
	echo "$reset_dflt_attr_num" > $config_path/reset_attr_num
}

smart_switch_common()
{
	if [ -e "$devtree_file" ]; then
		lm_sensors_config="$lm_sensors_configs_path/msn4700_respin_sensors.conf"
	else
		connect_msn4700_msn4600_A1

		connect_table+=(${msn4700_msn4600_A1_base_connect_table[@]})
		add_i2c_dynamic_bus_dev_connection_table "${msn4700_msn4600_mps_voltmon_connect_table[@]}"
		add_cpu_board_to_connection_table
		lm_sensors_config="$lm_sensors_configs_path/msn4700_respin_sensors.conf"
		thermal_control_config="$thermal_control_configs_path/tc_config_msn4700_mps.json"
		named_busses+=(${smart_switch_named_busses[@]})
		add_come_named_busses
		echo -n "${named_busses[@]}" > $config_path/named_busses
	fi
	echo -n "${smart_switch_dpu_dynamic_i2c_bus_connect_table[@]} " > $config_path/i2c_underlying_devices

	thermal_type=$thermal_type_t10
	max_tachos=12
	echo 25000 > $config_path/fan_max_speed
	echo 4500 > $config_path/fan_min_speed
	echo 23000 > $config_path/psu_fan_max
	echo 4600 > $config_path/psu_fan_min
	echo 3 > $config_path/cpld_num
	echo 17 > $config_path/dpu_bus_off
	dpu_count=4
	echo -n "${smart_switch_dpu2host_events[@]}" > "$dpu2host_events_file"
	echo -n "${smart_switch_dpu_events[@]}" > "$dpu_events_file"
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
			check_n_init $events_path/leakage$i 0
		done
		check_n_init $events_path/leakage_rope 0
	fi
	for ((i=0; i<health_events_count; i+=1)); do
		check_n_init  $events_path/${l1_switch_health_events[$i]}
	done
	if [ $pwr_events_count -ne 0 ]; then
		check_n_init $events_path/power_button 0
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
}

set_config_data()
{
	for ((idx=1; idx<=psu_count; idx+=1)); do
		psu_i2c_addr=psu"$idx"_i2c_addr
		echo ${!psu_i2c_addr} > $config_path/psu"$idx"_i2c_addr
	done
	echo $fan_psu_default > $config_path/fan_psu_default
	echo $fan_command > $config_path/fan_command
	echo $fan_config_command > $config_path/fan_config_command
	echo $fan_speed_units > $config_path/fan_speed_units
	echo 35 > $config_path/thermal_delay
	echo $chipup_delay_default > $config_path/chipup_delay
	echo 0 > $config_path/chipdown_delay
	echo $hotplug_psus > $config_path/hotplug_psus
	echo $hotplug_pwrs > $config_path/hotplug_pwrs
	echo $hotplug_fans > $config_path/hotplug_fans
	echo $hotplug_linecards > $config_path/hotplug_linecards
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
		connect_device "${connect_table[i]}" "${connect_table[i+1]}" \
				"${connect_table[i+2]}"
	done
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
	if [ ! -d $sfp_path ]; then
		mkdir $sfp_path
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
	if [ ! -f "$config_path/sfp_counter" ]; then
		echo 0 > "$config_path"/sfp_counter
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
}

set_asic_pci_id()
{
	if [ ! -f "$config_path"/asic_control ]; then
		echo $asic_control > "$config_path"/asic_control
	fi

	# Get ASIC PCI Ids.
	case $sku in
	HI122|HI123|HI124|HI126|HI156|HI160)
		asic_pci_id=$spc3_pci_id
		;;
	HI130|HI140|HI141|HI151)
		asic_pci_id=$quantum2_pci_id
		;;
	HI144|HI147|HI148)
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
	HI157)
		asic_pci_id=${quantum3_pci_id}
		;;
	HI158)
		asic_pci_id="${quantum3_pci_id}|${quantum2_pci_id}"
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
	HI131|HI141|HI142|HI152)
		asic1_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $2}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo 2 > "$config_path"/asic_num
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
	HI144|HI147|HI148)
		asic1_pci_bus_id=`echo $asics | awk '{print $1}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo 1 > "$config_path"/asic_num
		;;
	HI157)
		echo -n "$asics" | grep -c '^' > "$config_path"/asic_num
		[ -z "$asics" ] && return
		asic1_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $2}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		;;
	HI158)
		echo -n "$asics" | grep -c '^' > "$config_path"/asic_num
		[ -z "$asics" ] && return
		asic1_pci_bus_id=`echo $asics | awk '{print $3}'`
		asic2_pci_bus_id=`echo $asics | awk '{print $1}'`
		asic3_pci_bus_id=`echo $asics | awk '{print $4}'`
		asic4_pci_bus_id=`echo $asics | awk '{print $2}'`
		echo "$asic1_pci_bus_id" > "$config_path"/asic1_pci_bus_id
		echo "$asic2_pci_bus_id" > "$config_path"/asic2_pci_bus_id
		echo "$asic3_pci_bus_id" > "$config_path"/asic3_pci_bus_id
		echo "$asic4_pci_bus_id" > "$config_path"/asic4_pci_bus_id
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
		dpu1_pci_bus_id=`echo $dpus | awk '{print $1}'`
		dpu2_pci_bus_id=`echo $dpus | awk '{print $2}'`
		dpu3_pci_bus_id=`echo $dpus | awk '{print $3}'`
		dpu4_pci_bus_id=`echo $dpus | awk '{print $4}'`
		echo "$dpu1_pci_bus_id" > "$config_path"/dpu1_pci_bus_id
		echo "$dpu2_pci_bus_id" > "$config_path"/dpu2_pci_bus_id
		echo "$dpu3_pci_bus_id" > "$config_path"/dpu3_pci_bus_id
		echo "$dpu4_pci_bus_id" > "$config_path"/dpu4_pci_bus_id
		echo 4 > "$config_path"/dpu_num
		;;
	*)
		;;
	esac

	return
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
		HI144|HI147|HI148)	# ToDo Possible change for Ibex
			echo $ng800_cpu_bus_offset > $config_path/cpu_brd_bus_offset
			echo 2 > "$config_path"/clk_brd_num
			echo 3 > "$config_path"/clk_brd_addr_offset
			;;
		*)
			;;
		esac
		;;
	VMOD0017)
		echo $ndr_cpu_bus_offset > $config_path/cpu_brd_bus_offset
		;;
	VMOD0018)
		case $sku in
		HI158)
			echo 2 > "$config_path"/swb_brd_num
			echo 32 > "$config_path"/swb_brd_bus_offset
			;;
		*)
			;;
		esac
		echo $xdr_cpu_bus_offset > $config_path/cpu_brd_bus_offset
		;;
	VMOD0019)
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

do_start()
{
	create_symbolic_links
	check_cpu_type
	pre_devtr_init
	load_modules
	devtr_check_smbios_device_description
	check_system
	set_asic_pci_id
	set_dpu_pci_id

	asic_control=$(< $config_path/asic_control) 
	if [[ $asic_control -ne 0 ]]; then
		set_asic_i2c_bus
	fi
	touch $udev_ready
	depmod -a 2>/dev/null
	set_config_data
	udevadm trigger --action=add
	set_sodimm_temp_limits
	set_jtag_gpio "export"
	create_event_files
	hw-management-i2c-gpio-expander.sh
	connect_platform
	sleep 1
	enable_vpd_wp
	echo 0 > $config_path/events_ready
	/usr/bin/hw-management-start-post.sh

	if [ -f $config_path/max_tachos ]; then
		max_tachos=$(<$config_path/max_tachos)
	fi

	# check for MSN3700C exeption
	if [ "$max_tachos" == 8 ] && [ "$tune_thermal_type" == 1 ]; then
		thermal_type=$thermal_type_t6
	fi
	# Information for thermal control service
	echo $thermal_type > $config_path/thermal_type

	if [ -v "lm_sensors_config_lc" ] && [ -f $lm_sensors_config_lc ]; then
		ln -sf $lm_sensors_config_lc $config_path/lm_sensors_config_lc
	fi
	if [ -v "lm_sensors_config" ] && [ -f $lm_sensors_config ]; then
		ln -sf $lm_sensors_config $config_path/lm_sensors_config
	else
		ln -sf /etc/sensors3.conf $config_path/lm_sensors_config
	fi
	if [ -v "lm_sensors_labels" ] && [ -f $lm_sensors_labels ]; then 
		ln -sf $lm_sensors_labels $config_path/lm_sensors_labels
	fi 
	if [ -v "thermal_control_config" ] && [ -f $thermal_control_config ]; then
		cp $thermal_control_config $config_path/tc_config.json
	else
		cp $thermal_control_configs_path/tc_config_default.json $config_path/tc_config.json
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
	set_jtag_gpio "unexport"
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
		if [ -d /sys/bus/i2c/devices/"$asic_i2c_bus"-"$i2c_asic_addr_name" ]; then
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
		if [ ${asic_chipup_completed} -eq 0 ]; then
			echo 0 > $config_path/sfp_counter
		fi
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
		if [ ! -d /sys/bus/i2c/devices/"$asic_i2c_bus"-"$i2c_asic_addr_name" ]; then
			sleep "$chipup_delay"
			set_i2c_bus_frequency_400KHz
			echo mlxsw_minimal $i2c_asic_addr > /sys/bus/i2c/devices/i2c-"$asic_i2c_bus"/new_device
			restore_i2c_bus_frequency_default
			retry_helper find_asic_hwmon_path 0.2 3 "chip hwmon object" /sys/bus/i2c/devices/"$asic_i2c_bus"-"$i2c_asic_addr_name"/hwmon
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
