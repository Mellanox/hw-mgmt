#!/bin/bash
##################################################################################
# Copyright (c) 2020 - 2021, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Thermal configuration per system type. The next types are supported:
#  t1: MSN27*|MSN24*
#  t2: MSN21*
#  t3: MSN274*
#  t4: MSN201*
#  t5: MSN27*|MSB*|MSX*
#  t6: QMB7*|SN37*|SN34*|SN35*|SN47
#  t7: SN38*
#  t8: SN4600C
#  t12: SN4600
#  t13: SN4800

# The thermal algorithm considers the next rules for FAN speed setting:
# The minimal PWM setting is dynamic and depends on FAN direction and cable
# type. For system with copper cables only or/and with trusted optic cable
# minimum PWM setting could be decreased according to the system definition.
# Power supply units PWM control policy:
# If system`s power supplies are equipped with the controlled cooling device,
# its cooling setting should follow the next rules
# - Power supplies cooling devices should be set to the default value
#  (usually 60% of PWM speed), defined per each system type;
# - In case system`s main cooling device is set above this default value, power
#   supply`s cooling device setting should follow main cooling device (for
#   example if main cooling device is set to 80%, power supplies cooling devices
#   should be set to 80%);
# - In case system`s main cooling device is set down (to x%), power supplys'
#   cooling devices should be set down, in case x% >= power supplies default
#   speed value.
# PWM full speed policy addresses the following features:
# - Setting PWM to full speed if one of PS units is not present (in such case
#   thermal monitoring in kernel is set to disabled state until the problem is
#   not recovered). Such events will be reported to systemd journaling system.
# - Setting PWM to full speed if one of FAN drawers is not present or one of
#   tachometers is broken (in such case thermal monitoring in kernel is set to
#   disabled state until the problem is not recovered). Such events will be
#   reported to systemd journaling system.
# Thermal active monitoring is performed based on the values of the next
# sensors: CPU, ASIC ambient and QSFP modules temperatures.
# The decision for PWM setting is taken based on the worst measure of them.
# All the sensors and statuses are exposed through the sysfs interface for the
# user space application access.

# Paths to thermal sensors, device present states, thermal zone and cooling device
source hw-management-helpers.sh

board_type=$(< $board_type_file)
temp_fan_amb=$thermal_path/fan_amb
temp_port_amb=$thermal_path/port_amb
pwm=$thermal_path/pwm1
asic=$thermal_path/asic
tz_mode=$thermal_path/mlxsw/thermal_zone_mode
tz_policy=$thermal_path/mlxsw/thermal_zone_policy
tz_temp=$thermal_path/mlxsw/thermal_zone_temp
temp_trip_norm=$thermal_path/mlxsw/temp_trip_norm
temp_trip_high=$thermal_path/mlxsw/temp_trip_high
cooling_cur_state=$thermal_path/cooling_cur_state
cooling_max_state=$thermal_path/cooling_max_state
wait_for_config=120

# Input parameters for the system thermal class, the number of tachometers, the
# number of replicable power supply units and for sensors polling time (seconds)
system_thermal_type_def=1
polling_time_def=3
cooling_level_update_state=2

# Local constants
pwm_noact=0
pwm_max=1
cooling_set_max_state=20
max_amb=120000
module_counter=0
gearbox_counter=0
lc_counter=0
temp_grow_hyst=0
temp_fall_hyst=2000
temp_tz_hyst=5000
last_cpu_temp=0
common_loop=20
cooling_level_updated=0

# PSU fan speed vector
psu_fan_speed=(0x3c 0x3c 0x3c 0x3c 0x3c 0x3c 0x3c 0x46 0x50 0x5a 0x64)

# Thermal tables for the minimum FAN setting per system time. It contains
# entries with ambient temperature threshold values and relevant minimum
# speed setting. All Mellanox system are equipped with two ambient sensors:
# port side ambient sensor and FAN side ambient sensor. FAN direction can
# be read from FAN EEPROM data, in case FAN is equipped with EEPROM device,
# it can be read from CPLD FAN direction register in other case. Or for the
# common case it can be calculated according to the next rule:
# if port side ambient sensor value is greater than FAN side ambient sensor
# value - the direction is power to cable (forward); if it less - the direction
# is cable to power (reversed), if these value are equal: the direction is
# unknown. For each system the following six tables are defined:
# p2c_dir_trust_tx	all cables with trusted or with no sensors, FAN
#			direction is power to cable (forward)
# p2c_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
#			power to cable (forward)
# c2p_dir_trust_tx	all cables with trusted or with no sensors, FAN
#			direction is cable to power (reversed)
# c2p_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
#			cable to power (reversed)
# unk_dir_trust_tx	all cables with trusted or with no sensors, FAN
#			direction is unknown
# unk_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
#			unknown
# The below tables are defined per system thermal class and defines the
# relationship between the ambient temperature and minimal FAN speed. Th
# minimal FAN speed is coded as following: 12 for 20%, 13 for 30%, ..., 19 for
# 90%, 20 for 100%.
# In the tables whole ambient temperature range split into sub-ranges
# with the 5-degree step. Each sub-range defined in the format: tl-th
# where (tl) is a low threshold, (th) is a high threshold.
# Checking if sensor temperature (t) is fit to range do by the rule:
# tl <= tamb < th

# Default thermal class. Put 60% as common default.
p2c_dir_trust_def=(45000 16  $max_amb 16)
p2c_dir_untrust_def=(45000 16  $max_amb 16)
c2p_dir_trust_def=(45000 16  $max_amb 16)
c2p_dir_untrust_def=(45000 16  $max_amb 16)
unk_dir_trust_def=(45000 16  $max_amb 16)
unk_dir_untrust_def=(45000 16  $max_amb 16)

# Thermal class with full speed enforcement. Put 100% as enforcement.
p2c_dir_trust_full=(45000 20  $max_amb 20)
p2c_dir_untrust_full=(45000 20  $max_amb 20)
c2p_dir_trust_full=(45000 20  $max_amb 20)
c2p_dir_untrust_full=(45000 20  $max_amb 20)
unk_dir_trust_full=(45000 20  $max_amb 20)
unk_dir_untrust_full=(45000 20  $max_amb 20)


# Class t1 for MSN27*|MSN24*
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		30	30	30	30	30	30
#  0-5		30	30	30	30	30	30
#  5-10		30	30	30	30	30	30
# 10-15		30	30	30	30	30	30
# 15-20		30	30	30	30	30	30
# 20-25		30	30	40	40	40	40
# 25-30		30	40	50	50	50	50
# 30-35		30	50	60	60	60	60
# 35-40		30	60	60	60	60	60
# 40-45		50	60	60	60	60	60

p2c_dir_trust_t1=(40000 13 45000 15 $max_amb 15)
p2c_dir_untrust_t1=(25000 13 30000 14 35000 15 40000 16 $max_amb 16)
c2p_dir_trust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
c2p_dir_untrust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_trust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_untrust_t1=(20000 13 25000 14 30000 15 35000 16  $max_amb 16)

# Class t2 for MSN21*
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------	
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	20	20	20	20	20
# 10-15		20	20	20	20	20	20
# 15-20		20	30	20	20	20	30
# 20-25		20	30	20	20	20	30
# 25-30		20	40	20	20	20	40
# 30-35		20	50	20	20	20	50
# 35-40		20	60	20	20	20	60
# 40-45		20	60	30	30	30	60

p2c_dir_trust_t2=(45000 12 $max_amb 12)
p2c_dir_untrust_t2=(15000 12 25000 13 30000 14 35000 15 40000 16 $max_amb 16)
c2p_dir_trust_t2=(40000 12 45000 13 $max_amb 13)
c2p_dir_untrust_t2=(40000 12 45000 13 $max_amb 13)
unk_dir_trust_t2=(40000 12 45000 13 $max_amb 13)
unk_dir_untrust_t2=(15000 12 25000 13 30000 14 35000 15 40000 16 $max_amb 16)

# Class t3 for MSN274*
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		30	30	30	30	30	30
#  0-5		30	30	30	30	30	30
#  5-10		30	30	30	30	30	30
# 10-15		30	30	30	30	30	30
# 15-20		30	30	30	40	30	40
# 20-25		30	30	30	40	30	40
# 25-30		30	30	30	40	30	40
# 30-35		30	30	30	50	30	50
# 35-40		30	40	30	70	30	70
# 40-45		30	50	30	70	30	70

p2c_dir_trust_t3=(45000 13  $max_amb 13)
p2c_dir_untrust_t3=(35000 13 40000 14 45000 15 $max_amb 15)
c2p_dir_trust_t3=(45000 13  $max_amb 13)
c2p_dir_untrust_t3=(15000 13 30000 14 35000 15 40000 17 $max_amb 17)
unk_dir_trust_t3=(45000 13 $max_amb 13)
unk_dir_untrust_t3=(15000 13 30000 14 35000 15 40000 17 $max_amb 17)

# Class t4 for MSN201*
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	20	20	20	20	20
# 10-15		20	20	20	20	20	20
# 15-20		20	30	20	20	20	30
# 20-25		20	40	20	30	20	40
# 25-30		20	40	20	40	20	40
# 30-35		20	50	20	50	20	50
# 35-40		20	60	20	60	20	60
# 40-45		20	60	20	60	20	60

p2c_dir_trust_t4=(45000 12 $max_amb 12)
p2c_dir_untrust_t4=(15000 12 20000 13 30000 14 35000 15 40000 16 $max_amb 16)
c2p_dir_trust_t4=(45000 12 $max_amb 12)
c2p_dir_untrust_t4=(20000 12 25000 13 30000 14 35000 15 40000 16 $max_amb 16)
unk_dir_trust_t4=(45000 12  $max_amb 12)
unk_dir_untrust_t4=(15000 12 20000 13 30000 14 35000 15 40000 16 $max_amb 16)

# Class t5 for MSN3700|MQM8700
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	20	20	20	20	20
# 10-15		20	20	20	20	20	20
# 15-20		20	30	20	20	20	30
# 20-25		20	30	20	20	20	30
# 25-30		30	30	30	30	30	30
# 30-35		30	40	30	30	30	40
# 35-40		30	50	30	30	30	50
# 40-45		40	60	40	40	40	60

p2c_dir_trust_t5=(25000 12 40000 13 45000 14 $max_amb 14)
p2c_dir_untrust_t5=(15000 12 30000 13 35000 14 40000 15 45000 16 $max_amb 16)
c2p_dir_trust_t5=(25000 12 40000 13 45000 14 $max_amb 14)
c2p_dir_untrust_t5=(25000 12 40000 13 45000 14 $max_amb 14)
unk_dir_trust_t5=(25000 12 40000 13 45000 14 $max_amb 14)
unk_dir_untrust_t5=(15000 12 30000 13 35000 14 40000 15 45000 16 $max_amb 16)

# Class t6 for MSN3700C
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	20	20	20	20	20
# 10-15		20	30	20	20	20	30
# 15-20		20	30	20	20	20	30
# 20-25		20	40	20	20	20	40
# 25-30		20	40	20	20	20	40
# 30-35		20	50	20	20	20	50
# 35-40		20	60	20	30	20	60
# 40-45		30	60	20	40	30	60

p2c_dir_trust_t6=(40000 12 45000 13 $max_amb 13)
p2c_dir_untrust_t6=(10000 12 20000 13 30000 14 35000 15 40000 16 $max_amb 16)
c2p_dir_trust_t6=(20000 12 $max_amb 12)
c2p_dir_untrust_t6=(3500 12 40000 13 45000 14 $max_amb 14)
unk_dir_trust_t6=(40000 12 45000 13 $max_amb 13)
unk_dir_untrust_t6=(10000 12 20000 13 30000 14 35000 15 4 0000 16 $max_amb 16)

# Class t7 for MSN3800
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	30	20	20	20	30
#  5-10		20	30	20	20	20	30
# 10-15		20	40	20	20	20	40
# 15-20		20	50	20	20	20	50
# 20-25		20	60	20	30	20	60
# 25-30		20	60	20	30	20	60
# 30-35		20	60	30	40	30	60
# 35-40		30	70	30	50	30	70
# 40-45		30	70	40	60	40	70

p2c_dir_trust_t7=(35000 12 40000 13 $max_amb 13)
p2c_dir_untrust_t7=(0 12 10000 13 15000 14 20000 15 35000 16 40000 17 $max_amb 17)
c2p_dir_trust_t7=(30000 12 40000 13 45000 14 $max_amb 14)
c2p_dir_untrust_t7=(20000 12 30000 13 35000 14 40000 15 45000 16 $max_amb 16)
unk_dir_trust_t7=(30000 12 40000 13 45000 14 $max_amb 14)
unk_dir_untrust_t7=(0 12 10000 13 15000 14 20000 15 35000 16 40000 17 $max_amb 17)

# Class t8 for MSN4600
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	30	20	20	20	30
# 10-15		20	30	20	20	20	30
# 15-20		20	30	20	20	20	30
# 20-25		20	40	20	20	20	40
# 25-30		20	40	20	20	20	40
# 30-35		20	50	20	30	20	50
# 35-40		20	60	20	30	20	60
# 40-45		20	70	30	40	30	70

p2c_dir_trust_t8=(45000 12  $max_amb 12)
p2c_dir_untrust_t8=(5000 12 20000 13 30000 14 35000 15 40000 16 45000 17 $max_amb 17)
c2p_dir_trust_t8=(40000 12 45000 13 $max_amb 13)
c2p_dir_untrust_t8=(30000 12 40000 13 45000 14 $max_amb 14)
unk_dir_trust_t8=(40000 12 45000 13 $max_amb 13)
unk_dir_untrust_t8=(5000 12 20000 13 30000 14 35000 15 40000 16 45000 17 $max_amb 17)


# Class t9 for MSN3420
# Direction	P2C		C2P		Unknown

#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	20	20	20	20	20
# 10-15		20	20	20	20	20	20
# 15-20		20	20	20	20	20	20
# 20-25		20	20	20	20	20	20
# 25-30		20	30	20	20	20	30
# 30-35		20	30	20	20	20	30
# 35-40		20	40	20	20	20	40
# 40-45		20	60	20	40	20	60

p2c_dir_trust_t9=(45000 12 $max_amb 12)
p2c_dir_untrust_t9=(25000 12 35000 13 40000 14 45000 16 $max_amb 16)
c2p_dir_trust_t9=(45000 12 $max_amb 12)
c2p_dir_untrust_t9=(40000 12 45000 14 $max_amb 14)
unk_dir_trust_t9=(45000 12 $max_amb 12)
unk_dir_untrust_t9=(25000 12 35000 13 40000 14 45000 16 $max_amb 16)


# Class t10 for MSN4700
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	20	20	20	20	20
# 10-15		20	20	20	20	20	20
# 15-20		20	20	20	20	20	20
# 20-25		20	20	20	20	20	20
# 25-30		20	20	20	20	20	20
# 30-35		20	20	20	20	20	20
# 35-40		50	50	50	50	50	50
# 40-45		50	50	50	50	50	50

p2c_dir_trust_t10=(35000 12 40000 15 $max_amb 15)
p2c_dir_untrust_t10=(35000 12 40000 15 $max_amb 15)
c2p_dir_trust_t10=(35000 12 40000 15 $max_amb 15)
c2p_dir_untrust_t10=(35000 12 40000 15 $max_amb 15)
unk_dir_trust_t10=(35000 12 40000 15 $max_amb 15)
unk_dir_untrust_t10=(35000 12 40000 15 $max_amb 15)

# Class t11 for SN2201. 
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		30	30	30	30	30	30
#  0-5		30	30	30	30	30	30
#  5-10		30	30	30	30	30	30
# 10-15		30	30	30	30	30	30
# 15-20		30	40	30	30	30	40
# 20-25		30	50	30	40	30	50
# 25-30		30	60	30	50	30	60
# 30-35		40	70	30	60	40	70
# 35-40		50	80	40	70	50	80
# 40-45		60	90	50	80	60	90

p2c_dir_trust_t11=(30000 13 35000 14 40000 15 45000 16 $max_amb 16)
p2c_dir_untrust_t11=(15000 13 20000 14 25000 15 30000 16 35000 17 40000 18 45000 19 $max_amb 19)
c2p_dir_trust_t11=(35000 13 40000 14 45000 15 $max_amb 15)
c2p_dir_untrust_t11=(20000 13 25000 14 30000 15 35000 16 40000 17 45000 18 $max_amb 18)
unk_dir_trust_t11=(30000 13 35000 14 40000 15 45000 16 $max_amb 16)
unk_dir_untrust_t11=(15000 13 20000 14 25000 15 30000 16 35000 17 40000 18 45000 19 $max_amb 19)

# Class t12 for MSN4600
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	30	20	20	20	30
# 10-15		20	30	20	20	30	30
# 15-20		20	40	30	30	30	40
# 20-25		20	40	30	30	30	40
# 25-30		20	50	30	40	30	50
# 30-35		20	60	30	40	30	60
# 35-40		20	70	40	60	40	70
# 40-45		20	70	40	60	40	70


p2c_dir_trust_t12=(45000 12 $max_amb 12 )
p2c_dir_untrust_t12=(5000 12 15000 13 25000 14 30000 15 35000 16 45000 17 $max_amb 17 )
c2p_dir_trust_t12=(15000 12 35000 13 45000 14 $max_amb 14 )
c2p_dir_untrust_t12=(15000 12 25000 13 35000 14 45000 16 $max_amb 16 )
unk_dir_trust_t12=(10000 12 35000 13 45000 14 $max_amb 14 )
unk_dir_untrust_t12=(5000 12 15000 13 25000 14 30000 15 35000 16 45000 17 $max_amb 17 )

# Class t13 for MSN4800
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	30	20	20	20	30
# 10-15		20	30	20	20	20	30
# 15-20		20	30	20	20	20	30
# 20-25		20	40	20	20	20	40
# 25-30		30	50	20	20	30	50
# 30-35		30	50	20	20	30	50
# 35-40		40	60	20	20	40	60


p2c_dir_trust_t13=(25000 12 35000 13 40000 14 $max_amb 14 )
p2c_dir_untrust_t13=(5000 12 20000 13 25000 14 35000 15 40000 16 $max_amb 16 )
c2p_dir_trust_t13=(40000 12 $max_amb 12 )
c2p_dir_untrust_t13=(40000 12 $max_amb 12 )
unk_dir_trust_t13=(25000 12 35000 13 40000 14 $max_amb 14 )
unk_dir_untrust_t13=(5000 12 20000 13 25000 14 35000 15 40000 16 $max_amb 16 )

# Class t14 for SN5600.
# ToDo This is preBU setting, just as placeholder
# Actual info should be provided aftyer tests on real system with ASIC.
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		30	30	30	30	30	30
#  0-5		30	30	30	30	30	30
#  5-10		30	30	30	30	30	30
# 10-15		30	30	30	30	30	30
# 15-20		30	40	30	30	30	40
# 20-25		30	50	30	40	30	50
# 25-30		30	60	30	50	30	60
# 30-35		40	70	30	60	40	70
# 35-40		50	80	40	70	50	80
# 40-45		60	90	50	80	60	90

p2c_dir_trust_t14=(30000 13 35000 14 40000 15 45000 16 $max_amb 16)
p2c_dir_untrust_t14=(15000 13 20000 14 25000 15 30000 16 35000 17 40000 18 45000 19 $max_amb 19)
c2p_dir_trust_t14=(35000 13 40000 14 45000 15 $max_amb 15)
c2p_dir_untrust_t14=(20000 13 25000 14 30000 15 35000 16 40000 17 45000 18 $max_amb 18)
unk_dir_trust_t14=(30000 13 35000 14 40000 15 45000 16 $max_amb 16)
unk_dir_untrust_t14=(15000 13 20000 14 25000 15 30000 16 35000 17 40000 18 45000 19 $max_amb 19)

# Local variables
report_counter=120
audit_trigger=10
audit_count=0
fan_max_state=10
fan_dynamic_min=12
fan_dynamic_min_last=12
fan_norm_trip_low_limit=2
fan_high_trip_low_limit=4
temperature_ambient_last=0
untrusted_sensor=0
p2c_dir=0
c2p_dir=0
ambient=0
set_cur_state=0
full_speed=$pwm_noact
handle_dynamic_trend=0

log_err()
{
	logger -t hw-management-tc -p daemon.err "$@"
}

log_warning()
{
	logger -t hw-management-tc -p daemon.warning "$@"
}

log_notice()
{
	logger -t hw-management-tc -p daemon.notice "$@"
}

log_info()
{
	logger -t hw-management-tc -p daemon.info "$@"
}

get_fan_fault_trusted()
{
	idx=$1
	fault=0
	if [ -L $thermal_path/fan"$idx"_fault ]; then
		fault=$(< $thermal_path/fan"$idx"_fault)
		if [ $fault -eq 1 ]; then
			sleep 1
			fault=$(< $thermal_path/fan"$idx"_fault)
		fi
	fi
	return $((fault))
}

# Validate thermal attributes for the subsystem
# input parameters:
# $1 - 'subsystem' relative path. Example '' for MGMT or 'lc{n}' for line card
# $2 - thermal dev type name. Example: 'module', 'gearbox'
# $3 - thermal dev count in subsystem
validate_thermal_configuration_per_susbsys()
{
	subsys_path=$1
	dev_type=$2
	dev_count=$3

	for ((i=1; i<=dev_count; i+=1)); do
		if [ -L $hw_management_path/"$subsys_path"/thermal/"$dev_type""$i"_temp ]; then
			if [ ! -L $hw_management_path/"$subsys_path"/thermal/"$dev_type""$i"_temp_fault ]; then
				log_err "$subsys_path $dev_type($i)_temp_fault attribute not exist"
				return 1
			fi
		fi
	done
	return 0
}

validate_thermal_configuration()
{
	# Wait for symbolic links creation.
	sleep 3
	# Validate FAN fault symbolic links.
	for ((i=1; i<=max_tachos; i+=1)); do
		if [ ! -L $thermal_path/fan"$i"_fault ]; then
			log_err "FAN $i fault attribute ( fan_fault ) not exist"
			return 1
		fi
		if [ ! -L $thermal_path/fan"$i"_speed_get ]; then
			log_err "FAN $i input attribute ( fan_speed_get ) not exist"
			return 1
		fi
	done
	if [ ! -L $cooling_cur_state ] || [ ! -L $tz_mode  ] ||
	   [ ! -L $temp_trip_norm ] || [ ! -L $tz_temp ]; then
		log_err "Thermal zone attributes are not exist"
		return 1
	fi
	if [ ! -L $pwm ] || [ ! -L $asic ]; then
		log_err "PWM control and ASIC attributes are not exist"
		return 1
	fi
	if [ "$lc_counter" -gt 0 ]; then
		for ((i=1; i<=lc_counter; i+=1)); do
			lc_active=$(< $system_path/lc"$i"_active)
			if [ "$lc_active" -gt 0 ]; then
				lc_module_count=$(< $hw_management_path/lc"$i"/config/module_counter)
				validate_thermal_configuration_per_susbsys "lc$i" "module" "$lc_module_count"
				if [ "$?" -ne 0 ]; then
					return 1
				fi
			fi
		 done
	fi

	validate_thermal_configuration_per_susbsys "" "module" $module_counter
	if [ "$?" -ne 0 ]; then
		return 1
	fi

	if [ ! -L $temp_fan_amb ] || [ ! -L $temp_port_amb ]; then
		log_err "Ambient temperature sensors attributes are not exist"
		return 1
	fi
	if [ "$max_psus" -gt 0 ]; then
		for ((i=1; i<=max_psus; i+=1)); do
			psu_status="$thermal_path"/psu"$i"_status
			if [ ! -L "$psu_status" ]; then
			    log_err "PS$i status attribute not exist"
			    return 1
			fi
		done
	fi
}

# Validate for the untrusted thermal sensor
# input parameters:
# $1 - 'subsystem' relative path. Example '' for MGMT or 'lc{n}' for line card
# $2 - thermal dev type name. Example: 'module', 'gearbox' 
# $3 - thermal dev count in subsystem
check_untrusted_sensor_per_type()
{
	subsys_path=$1
	dev_type=$2
	dev_count=$3	
	for ((i=1; i<=dev_count; i+=1)); do
		if [ -L $hw_management_path/"$subsys_path"/thermal/"$dev_type""$i"_temp_fault ]; then
			temp_fault=$(<$hw_management_path/"$subsys_path"/thermal/"$dev_type""$i"_temp_fault)
			if [ "$temp_fault" -eq 1 ]; then
				untrusted_sensor=1
				return 1
			fi
		fi
	done
}

check_untrusted_sensors()
{
	tz_check_suspend
	if [ "$?" -ne 0 ]; then
		return
	fi
	if [ "$lc_counter" -gt 0 ]; then
		for ((i=1; i<=lc_counter; i+=1)); do
			lc_active=$(< $system_path/lc"$i"_active)
			if [ "$lc_active" -gt 0 ]; then
				lc_module_count=$(< $hw_management_path/lc"$i"/config/module_counter)
				check_untrusted_sensor_per_type "lc$i" "module" "$lc_module_count"
				if [ "$?" -ne 0 ]; then
					return
				fi
			fi
		 done
	fi
	
	check_untrusted_sensor_per_type "" "module" $module_counter
}

# Print to log single tz information
# input parameters:
# $1 - 'tz_path' 
# $2 - 'name' tz name: module, gearbox, asic...
log_tz_info()
{
	tz_path=$1
	name=$2
	if [ -f "$tz_path"/thermal_zone_temp ]; then
		t6=$(< "$tz_path"/thermal_zone_mode)
		if [ "$t6" = "enabled" ]; then
			t1=$(< "$tz_path"/thermal_zone_temp)
			t2=$(< "$tz_path"/temp_trip_norm)
			t3=$(< "$tz_path"/temp_trip_high)
			t4=$(< "$tz_path"/temp_trip_hot)
			t5=$(< "$tz_path"/thermal_zone_policy)
			log_info "tz $name temp $t1 trips $t2 $t3 $t4 $t5 $t6"
		fi
	fi
}

# Print to log tz information for modules in specified 'subsystem'
# input parameters:
# $1 - 'subsystem' relative path. Example '' for MGMT or 'lc{n}' for line card
# $2 - module count in subsystem
log_modules_tz_info()
{
	subsys_path=$1
	module_count=$2

	for ((i=1; i<=module_count; i+=1)); do
		if [ -f $hw_management_path/"$subsys_path"/thermal/module"$i"_temp_input ]; then
			t1=$(< $hw_management_path/"$subsys_path"/thermal/module"$i"_temp_input)
			if [ "$t1" -gt  "0" ]; then
				t2=$(< $hw_management_path/"$subsys_path"/thermal/module"$i"_temp_fault)
				t3=$(< $hw_management_path/"$subsys_path"/thermal/module"$i"_temp_crit)
				t4=$(< $hw_management_path/"$subsys_path"/thermal/module"$i"_temp_emergency)
				log_info "$subsys_path module$i temp $t1 fault $t2 crit $t3 emerg $t4"
			fi
			log_tz_info "$hw_management_path/$subsys_path/thermal/mlxsw-module$i" "module$i"
		fi
	done
}


# Print to log tz information for gearboxes in specified 'subsystem'
# input parameters:
# $1 - 'subsystem' relative path. Example '' for MGMT or 'lc{n}' for line card 
# $2 - gearbox count in subsystem
log_gearbox_tz_info()
{
	subsys_path=$1
	gbox_count=$2

	for ((i=1; i<=gbox_count; i+=1)); do
		if [ -f $hw_management_path/"$subsys_path"/thermal/module"$i"_temp_input ]; then
			t1=$(< $hw_management_path/"$subsys_path"/thermal/gearbox"$i"_temp_input)
			if [ "$t1" -gt  "0" ]; then
				log_info "$subsys_path gearbox$i temp $t1"
			fi
			log_tz_info "$hw_management_path/$subsys_path/thermal/mlxsw-gearbox$i" "gearbox$i"
		fi
	done
}

thermal_periodic_report()
{
	f1=$(< $thermal_path/mlxsw/thermal_zone_temp)
	f2=$(< $temp_fan_amb)
	f3=$(< $temp_port_amb)
	f4=$(< $pwm)
	f5=$((fan_dynamic_min-fan_max_state))
	dyn=$((f5*10))
	cooling=$(< $cooling_cur_state)
	if [ "$cooling" -gt "$set_cur_state" ]; then
		set_cur_state=$cooling
		if [ "$cooling" -gt "$f5" ]; then
			f5=$cooling
		fi
	else
		if [ "$cooling" -ge "$f5" ]; then
			f5=$cooling
			set_cur_state=$cooling
		fi
	fi
	ps_fan_speed=${psu_fan_speed[$f5]}
	f5=$((f5*10))
	f6=$((set_cur_state*10))
	log_info "Thermal periodic report"
	log_info "======================="
	log_info "Temperature(mC): asic $f1 fan amb $f2 port amb $f3"
	log_info "Cooling(%): pwm $f6 ps_fan_speed $((ps_fan_speed)) dynaimc_min $dyn"
	for ((i=1; i<=max_tachos; i+=1)); do
		if [ -f $thermal_path/fan"$i"_speed_get ]; then
			tacho=$(< $thermal_path/fan"$i"_speed_get)
			get_fan_fault_trusted $i
			fault=$?
			log_info "tacho$i speed is $tacho fault is $fault"
		fi
	done

	log_modules_tz_info "" "$module_counter"
	log_gearbox_tz_info "" "$gearbox_counter"

	if [ "$lc_counter" -gt 0 ]; then
		for ((i=1; i<=lc_counter; i+=1)); do
			lc_active=$(< $system_path/lc"$i"_active)
			if [ "$lc_active" -gt 0 ]; then
				lc_module_count=$(< $hw_management_path/lc"$i"/config/module_counter)
				lc_gearbox_count=$(< $hw_management_path/lc"$i"/config/gearbox_counter)
				log_modules_tz_info "lc$i" "$lc_module_count"
				log_gearbox_tz_info "lc$i" "$lc_gearbox_count"
		 	fi
		done
	fi

	log_tz_info "$thermal_path/mlxsw" "asic"
}

config_p2c_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<size; i++)); do
		p2c_dir_trust[i]=${array[i]}
	done
}

config_p2c_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<size; i++)); do
		p2c_dir_untrust[i]=${array[i]}
	done
}

config_c2p_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<size; i++)); do
		c2p_dir_trust[i]=${array[i]}
	done
}

config_c2p_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<size; i++)); do
		c2p_dir_untrust[i]=${array[i]}
	done
}

config_unk_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<size; i++)); do
		unk_dir_trust[i]=${array[i]}
	done
}

config_unk_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<size; i++)); do
		unk_dir_untrust[i]=${array[i]}
	done
}

set_fan_to_full_speed()
{
	set_cur_state=$((cooling_set_max_state-fan_max_state))
	echo $cooling_set_max_state > $cooling_cur_state
	audit_count=0
}

get_psu_presence()
{
	for ((i=1; i<=max_psus; i+=1)); do
		if [ -f $thermal_path/psu"$i"_status ]; then
			present=$(< $thermal_path/psu"$i"_status)
			if [ "$present" -eq 0 ]; then
				pwm_required_act=$pwm_max
				if [ "$full_speed" -ne $pwm_max ]; then
					set_fan_to_full_speed
					log_info "FAN speed is set to full speed due to PSU fault"
				fi
				return
			fi
		fi
	done

	pwm_required_act=$pwm_noact
}

update_psu_fan_speed()
{
	for ((i=1; i<=max_psus; i+=1)); do
		if [ -L $thermal_path/psu"$i"_pwr_status ]; then
			pwr=$(< $thermal_path/psu"$i"_pwr_status)
			if [ "$pwr" -eq 1 ]; then
				entry=$(< $thermal_path/cooling_cur_state)
				speed=${psu_fan_speed[$entry]}
				psu_set_fan_speed psu"$i" "$speed"
			fi
		fi
	done
}

get_fan_faults()
{
	for ((i=1; i<=max_tachos; i+=1)); do
		get_fan_fault_trusted $i
		fault=$?
		speed=$(< $thermal_path/fan"$i"_speed_get)
		if [ "$fault" -eq 1 ] || [ "$speed" -eq 0 ]; then
			pwm_required_act=$pwm_max
			if [ "$full_speed" -ne $pwm_max ]; then
				set_fan_to_full_speed
				log_info "FAN speed is set to full speed due to FAN$i fault"
			fi
			return
		fi
	done

	pwm_required_act=$pwm_noact
}

get_fan_direction()
{
	p2c_dir=0
	c2p_dir=0
	fan_dir=0
	for ((i=1; i<="$max_drwr"; i+=1)); do
		if [ ! -f $thermal_path/fan"$i"_dir ]; then
			# Some fan is not present.
			return
		fi
		fan_dir=$(($(<$thermal_path/fan"$i"_dir) + fan_dir))
	done

	if [ "$fan_dir" -eq 0 ]; then
		c2p_dir=1
	elif [ "$fan_dir" -eq "$max_drwr" ]; then
		p2c_dir=1
	else
		# There is a mismatch (actually this is a serious fault,
		# but currently we don't handle such fault).
		return
	fi
}

copy_treshold_vector()
{
    array=("$@")
    size=${#array[@]}
    for ((i=0; i<size; i++)); do
        treshold_vector[i]=${array[i]}
    done
}

config_treshold_vector()
{
    untrusted_sensor=0
    # Check for untrusted modules
    check_untrusted_sensors

    if [ "$untrusted_sensor" -eq 0 ]; then
        if [ "$p2c_dir" -eq 1 ]; then
            copy_treshold_vector "${p2c_dir_trust[@]}"
        elif [ "$c2p_dir" -eq 1 ]; then
            copy_treshold_vector "${c2p_dir_trust[@]}"
        else
            copy_treshold_vector "${unk_dir_trust[@]}"
        fi
    else
        if [ "$p2c_dir" -eq 1 ]; then
            copy_treshold_vector "${p2c_dir_untrust[@]}"
        elif [ "$c2p_dir" -eq 1 ]; then
            copy_treshold_vector "${c2p_dir_untrust[@]}"
        else
            copy_treshold_vector "${unk_dir_untrust[@]}"
        fi
    fi
}

set_pwm_min_threshold()
{
    if [ "$p2c_dir" -eq 1 ]; then
        ambient=$(< $temp_port_amb)
    elif [ "$c2p_dir" -eq 1 ]; then
        ambient=$(< $temp_fan_amb)
    else
        ambient=$(< $temp_fan_amb)
    fi

    config_treshold_vector
    size=${#treshold_vector[@]}
    for ((i=0; i<size; i+=2)); do
        tresh=${treshold_vector[i]}
        if [ "$ambient" -lt "$tresh" ]; then
            fan_dynamic_min_curr=${treshold_vector[$((i+1))]}
            tresh_next=$tresh
            break
        fi
        tresh_prev=$tresh
    done

    # Temperature diff between current temperature and last dmin_change
    temperature_diff=$((ambient-temperature_ambient_tresh_cross))

    # Check if fan_dynamic_min was changed
    if [ ! "$fan_dynamic_min_curr" -eq "$fan_dynamic_min" ];
    then
        # Check if temperature change is more then hysteresis
        if [ $temperature_diff -ge $temp_grow_hyst ]; then
            fan_dynamic_min=$fan_dynamic_min_curr
            temperature_ambient_tresh_cross=$tresh_prev
        elif [ $temperature_diff -le -$temp_fall_hyst ]; then
            fan_dynamic_min=$fan_dynamic_min_curr
            temperature_ambient_tresh_cross=$tresh_next
        fi
    fi
    temperature_ambient_last=$ambient
}

init_system_dynamic_minimum_db()
{
	case $system_thermal_type in
	$thermal_type_t1)
		# Config FAN minimal speed setting for class t1
		config_p2c_dir_trust "${p2c_dir_trust_t1[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t1[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t1[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t1[@]}"
		config_unk_dir_trust "${unk_dir_trust_t1[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t1[@]}"
		;;
	$thermal_type_t2)
		# Config FAN minimal speed setting for class t2
		config_p2c_dir_trust "${p2c_dir_trust_t2[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t2[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t2[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t2[@]}"
		config_unk_dir_trust "${unk_dir_trust_t2[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t2[@]}"
		;;
	$thermal_type_t3)
		# Config FAN minimal speed setting for class t3
		config_p2c_dir_trust "${p2c_dir_trust_t3[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t3[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t3[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t3[@]}"
		config_unk_dir_trust "${unk_dir_trust_t3[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t3[@]}"
		;;
	$thermal_type_t4)
		# Config FAN minimal speed setting for class t4
		config_p2c_dir_trust "${p2c_dir_trust_t4[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t4[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t4[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t4[@]}"
		config_unk_dir_trust "${unk_dir_trust_t4[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t4[@]}"
		;;
	$thermal_type_t5)
		# Config FAN minimal speed setting for class t5
		config_p2c_dir_trust "${p2c_dir_trust_t5[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t5[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t5[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t5[@]}"
		config_unk_dir_trust "${unk_dir_trust_t5[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t5[@]}"
		;;
	$thermal_type_t6)
		# Config FAN minimal speed setting for class t6
		config_p2c_dir_trust "${p2c_dir_trust_t6[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t6[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t6[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t6[@]}"
		config_unk_dir_trust "${unk_dir_trust_t6[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t6[@]}"
		;;
	$thermal_type_t7)
		# Config FAN minimal speed setting for class t7
		config_p2c_dir_trust "${p2c_dir_trust_t7[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t7[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t7[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t7[@]}"
		config_unk_dir_trust "${unk_dir_trust_t7[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t7[@]}"
		;;
	$thermal_type_t8)
		# Config FAN minimal speed setting for class t8
		config_p2c_dir_trust "${p2c_dir_trust_t8[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t8[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t8[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t8[@]}"
		config_unk_dir_trust "${unk_dir_trust_t8[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t8[@]}"
		;;
	$thermal_type_t9)
		# Config FAN minimal speed setting for class t9
		config_p2c_dir_trust "${p2c_dir_trust_t9[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t9[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t9[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t9[@]}"
		config_unk_dir_trust "${unk_dir_trust_t9[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t9[@]}"
		;;
	$thermal_type_t10)
		# Config FAN minimal speed setting for class t10
		config_p2c_dir_trust "${p2c_dir_trust_t10[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t10[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t10[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t10[@]}"
		config_unk_dir_trust "${unk_dir_trust_t10[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t10[@]}"
		;;
	$thermal_type_t11)
		# Config FAN minimal speed setting for class t11
		config_p2c_dir_trust "${p2c_dir_trust_t11[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t11[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t11[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t11[@]}"
		config_unk_dir_trust "${unk_dir_trust_t11[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t11[@]}"
		;;
	$thermal_type_t12)
		# Config FAN minimal speed setting for class t12
		config_p2c_dir_trust "${p2c_dir_trust_t12[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t12[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t12[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t12[@]}"
		config_unk_dir_trust "${unk_dir_trust_t12[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t12[@]}"
		;;
	$thermal_type_t13)
		# Config FAN minimal speed setting for class t13
		config_p2c_dir_trust "${p2c_dir_trust_t13[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t13[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t13[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t13[@]}"
		config_unk_dir_trust "${unk_dir_trust_t13[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t13[@]}"
		;;
	$thermal_type_t14)
		# Config FAN minimal speed setting for class t14.
		# ToDo. Use default 60% settings until real values will be available.
		config_p2c_dir_trust "${p2c_dir_trust_def[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_def[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_def[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_def[@]}"
		config_unk_dir_trust "${unk_dir_trust_def[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_def[@]}"
		;;
	$thermal_type_full)
		# Config FAN default minimal speed setting
		config_p2c_dir_trust "${p2c_dir_trust_def[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_def[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_def[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_def[@]}"
		config_unk_dir_trust "${unk_dir_trust_def[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_def[@]}"
		;;
	*)
		# Config FAN default minimal speed setting
		config_p2c_dir_trust "${p2c_dir_trust_def[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_def[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_def[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_def[@]}"
		config_unk_dir_trust "${unk_dir_trust_def[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_def[@]}"
		;;
	esac
}

set_default_pwm()
{
	set_cur_state=$((cooling_set_max_state-fan_max_state))
	echo $cooling_set_max_state > $cooling_cur_state
	echo $set_cur_state > $cooling_cur_state
	cur_state=$((set_cur_state*10))
	echo $cur_state > $thermal_path/fan_dynamic_min
	audit_count=0
	# Suspend - set internal state to 1.
	cooling_level_update_state=1
	log_info "FAN speed is set to $cur_state percent up to full speed"
}

set_dynamic_min_pwm()
{
	trip_low_limit=$1

	if [ "$cooling_level_update_state" -eq 1 ]; then
		# Fan was set to full speed because of suspend.
		# Move to internal state 2 and handle like after full speed.
		cooling_level_update_state=2
	fi

	set_cur_state=$((fan_dynamic_min-fan_max_state))
	cur_cooling=$(< $cooling_cur_state)
	limit=$((trip_low_limit+10))
	if [ "$fan_dynamic_min" -ne "$cur_cooling" ]; then
		if [ "$fan_dynamic_min" -ge "$limit" ]; then
			echo "$fan_dynamic_min" > $cooling_cur_state
		else
			echo "$limit" > $cooling_cur_state
		fi
	fi
	if [ "$set_cur_state" -ge "$trip_low_limit" ]; then
		set_cooling=$set_cur_state
	else
		set_cooling=$trip_low_limit
	fi
	if [ "$set_cooling" -lt "$cur_cooling" ]; then
		echo "$set_cooling" > $cooling_cur_state
		cur_cooling=$((cur_cooling*10))
		cur_state=$((set_cur_state*10))
		cooling=$(< $cooling_cur_state)
		cooling=$((cooling*10))
		echo $cur_state > $thermal_path/fan_dynamic_min
		log_info "FAN speed changed from $cur_cooling% to $cooling% (dynamic minimum $cur_state%)"
	fi
}

update_dynamic_min_pwm()
{
	if [ "$cooling_level_update_state" -eq 2 ]; then
		# Fan in state 2 after init, resume or after some missed unit
		# was inserted back. Move to normal internal state 0.
		check_trip_min_vs_current_temp "high" $fan_high_trip_low_limit
		if [ $? -eq 0 ]; then
			cooling_level_update_state=0
		fi
	fi
}

# input parameters:
# $1 - 'subsystem' relative path. Example '' for MGMT or 'lc{n}' for line card
# $2 - thermal device type name. Example: 'module', 'gearbox' 
# $3 - thermal device count in subsystem 
check_trip_min_vs_current_temp_per_type()
{
	subsys_path=$1
	dev_type=$2
	dev_count=$3
	zone=$4
	
	for ((i=1; i<=dev_count; i+=1)); do
		if [ -f $hw_management_path/"$subsys_path"/thermal/mlxsw-"$dev_type""$i"/thermal_zone_temp ]; then
			temp_now=$(< $hw_management_path/"$subsys_path"/thermal/mlxsw-"$dev_type""$i"/thermal_zone_temp)
			trip_orig=$(< $hw_management_path/"$subsys_path"/thermal/mlxsw-"$dev_type""$i"/temp_trip_"$zone")
			trip=$((trip_orig-temp_tz_hyst))
			if [ "$trip_orig" -le 10 ] && [ "$temp_now" -ne 0 ]; then
				log_warning "Module mlxsw-$dev_type$i unexpected attribute values: temperature $temp_now, temp_trip_$zone $trip_orig"
			fi 
			if [ "$temp_now" -gt 0 ] && [ "$trip" -le  "$temp_now" ]; then
				return 1
			fi
		fi
	done
	return 0
}

check_trip_min_vs_current_temp()
{
	zone=$1
	trip_low_limit=$2

	check_trip_min_vs_current_temp_per_type "" "module" $module_counter $zone
	if [ "$?" -ne 0 ]; then
		return 1
	fi

	check_trip_min_vs_current_temp_per_type "" "gearbox" $gearbox_counter $zone
	if [ "$?" -ne 0 ]; then
		return 1
	fi

	if [ "$lc_counter" -gt 0 ]; then
		for ((i=1; i<=lc_counter; i+=1)); do
			lc_active=$(< $system_path/lc"$i"_active)
			if [ "$lc_active" -gt 0 ]; then
				lc_module_count=$(< $hw_management_path/lc"$i"/config/module_counter)
				check_trip_min_vs_current_temp_per_type "lc$i" "module" "$lc_module_count"
				if [ "$?" -ne 0 ]; then
					return 1
				fi
				lc_gbox_count=$(< $hw_management_path/lc"$i"/config/gearbox_counter)
				check_trip_min_vs_current_temp_per_type "lc$i" "gearbox" "$lc_gbox_count"
				if [ "$?" -ne 0 ]; then
					return 1
				fi
			fi
		done
	fi
	trip=$(< /var/run/hw-management/thermal/mlxsw/temp_trip_"$zone")
	trip=$((trip-temp_tz_hyst))
	temp_now=$(< $tz_temp)
	if [ "$trip" -gt "$temp_now" ]; then
		set_dynamic_min_pwm $trip_low_limit
		cooling_level_updated=1
	fi
	return 0
}

# Ckeck existing and set thermal attributes
# input parameters:
# $1 - 'subsystem' relative path. Example '' for MGMT or 'lc{n}' for line card
# $2 - dev type name. Example: 'module', 'gearbox'
# $3 - dev count in subsystem
# $4 - attribute name. Example: 'thermal_zone_policy', 'thermal_zone_mode', ...
# $5 - attribute value
set_thermal_zone_attr()
{
	subsys_path=$1
	dev_type=$2
	dev_count=$3
	attr_name=$4
	attr_val=$5
	for ((i=1; i<=dev_count; i+=1)); do
		if [ -f $hw_management_path/"$subsys_path"/thermal/mlxsw-"$dev_type""$i"/"$attr_name" ]; then
			echo "$attr_val" > $hw_management_path/"$subsys_path"/thermal/mlxsw-"$dev_type""$i"/"$attr_name"
		fi
	done
}

enable_disable_zones_set_pwm()
{
	case $1 in
	1)
		set_pwm_min_threshold
		fan_dynamic_min_last=$fan_dynamic_min
		check_trip_min_vs_current_temp "high" $fan_high_trip_low_limit
		;;
	*)
		set_default_pwm
		;;
	esac
}

tz_check_suspend()
{
	[ -f "$config_path/suspend" ] && suspend=$(< $config_path/suspend)
	if [ "$suspend" ] &&  [ "$suspend" = "1" ]; then
		return 1
	fi
	return 0
}

[ -f $config_path/thermal_delay ] && thermal_delay=$(< $config_path/thermal_delay);
if [ -z "$thermal_delay" ]; then
	sleep "$thermal_delay" &
	wait $!
fi

asic_hot_vs_cooling_sanity()
{
	trip=$(< /var/run/hw-management/thermal/mlxsw/temp_trip_hot)
	trip=$((trip+temp_tz_hyst))
	temp_now=$(< $tz_temp)
	cooling=$(< $cooling_cur_state)
	cooling_max=$(< $cooling_max_state)
	if [ "$temp_now" -gt "$trip" ] && [ "$cooling" -lt "$cooling_max" ]; then
		log_info "FAN speed level is changed from $cooling to $cooling_max, because ASIC temparture $temp_now"
		echo "$cooling_max" > $cooling_cur_state
	fi
}

init_service_params()
{
	if [ -f $config_path/thermal_type ]; then
		system_thermal_type=$(< $config_path/thermal_type)
	else
		system_thermal_type=$system_thermal_type_def
	fi
	if [ -f $config_path/max_tachos ]; then
		max_tachos=$(< $config_path/max_tachos)
	else
		log_err "Mellanox thermal control start fail. Missing max tachos config."
		exit 1
	fi
	if [ -f $config_path/fan_drwr_num ]; then
		max_drwr=$(< $config_path/fan_drwr_num)
	else
		log_err "Mellanox thermal control start fail. Missing max fan drawers config."
		exit 1
	fi
	if [ -f $config_path/hotplug_psus ]; then
		max_psus=$(< $config_path/hotplug_psus)
	else
		log_err "Mellanox thermal control start fail. Missing hotplug_psus config."
		exit 1
	fi
	if [ -f $config_path/polling_time ]; then
		polling_time=$(< $config_path/polling_time)
	else
		polling_time=$polling_time_def
	fi
	if [ -f $config_path/module_counter ]; then
		module_counter=$(< $config_path/module_counter)
	fi
	if [ -f $config_path/gearbox_counter ]; then
		gearbox_counter=$(< $config_path/gearbox_counter)
	fi
	if [ -f $config_path/lc_counter ]; then
		lc_counter=$(< $config_path/hotplug_linecards)
	fi
}

thermal_control_preinit()
{
	init_service_params
	# Initialize system dynamic minimum speed data base.
	init_system_dynamic_minimum_db
	get_fan_direction

	# Periodic report counter
	periodic_report=$((polling_time*report_counter))
	echo $periodic_report > $config_path/periodic_report
	fan_dynamic_min_init=$((fan_dynamic_min -fan_max_state))
	fan_dynamic_min_init=$((fan_dynamic_min_init*10))
	echo $fan_dynamic_min_init > $thermal_path/fan_dynamic_min
	count=0
	audit_count=0
	suspend_thermal=0
}

sku=$(< /sys/devices/virtual/dmi/id/product_sku)
case $sku in
	HI138|HI132)
	log_notice "Mellanox thermal control not supported by this platform:" $sku
	exit 0
	;;
esac

rm -rf $config_path/periodic_report
log_notice "Mellanox thermal control is started"
# Wait for thermal configuration.
log_notice "Mellanox thermal control is waiting for configuration."
/bin/sleep $wait_for_config &
wait $!

thermal_control_preinit

# Start thermal monitoring.
while true
do
	/bin/sleep $polling_time &
	wait $!

	# Control cooling devices according to CPU temperature trends.
	hw_management_cpu_thermal.py -t $last_cpu_temp
	last_cpu_temp=$?
	
	cpu_loop=$((cpu_loop+1))
	if [ "$cpu_loop" -le "$common_loop" ]; then
		continue
	else
		cpu_loop=1
	fi

	# Check if thermal algorithm is suspended.
	[ -f "$config_path/suspend" ] && suspend=$(< $config_path/suspend)
	if [ "$suspend" ] && [ "$suspend" != "$suspend_thermal" ]; then
		# Attribute 'suspend' has been changed since last cycle.
		if [ "$suspend" = "1" ]; then
			log_info "Thermal algorithm is manually suspended"
			enable_disable_zones_set_pwm 0
		else
			log_info "Thermal algorithm is manually resumed"
			enable_disable_zones_set_pwm 1
		fi
		suspend_thermal=$suspend
		continue
	else
		if [ "$suspend_thermal" = "1" ]; then
			# Thermal algorithm is keeping suspended.
			continue
		fi
	fi

	# Validate thermal configuration.
	validate_thermal_configuration
	if [ $? -ne 0 ]; then
		continue
	fi
	# Perform sanity check for ASI temparture versus fan speed.
	asic_hot_vs_cooling_sanity
	# Set PWM minimal limit.
	# Set dynamic FAN speed minimum, depending on ambient temperature,
	# presence of untrusted optical cables or presence of any cables
	# with untrusted temperature sensing.
	set_pwm_min_threshold
	# Verify if cooling state required update.
	update_dynamic_min_pwm
	# Update PS unit fan speed
	update_psu_fan_speed
	# If one of PS units is out disable thermal zone and set PWM to the
	# maximum speed.
	get_psu_presence
	if [ "$pwm_required_act" -eq $pwm_max ]; then
		full_speed=$pwm_max
		continue
	fi
	# If one of tachometers is faulty set PWM to the maximum speed.
	get_fan_faults
	if [ "$pwm_required_act" -eq $pwm_max ]; then
		full_speed=$pwm_max
		continue
	fi
	# Update cooling levels of FAN if dynamic minimum has been changed
	# since the last time.
	if [ "$fan_dynamic_min" -ne "$fan_dynamic_min_last" ]; then
		log_info "fan_dynamic_min changed $fan_dynamic_min_last => $fan_dynamic_min"
		log_info "due to temp change to $temperature_ambient_last"
		echo "$fan_dynamic_min" > $cooling_cur_state
		cooling=$(< $cooling_cur_state)
		if [ "$set_cur_state" -ge "$cooling" ]; then
			echo $set_cur_state > $cooling_cur_state
			log_info "Cooling current state is set to $set_cur_state"
		fi
		fan_from=$((fan_dynamic_min_last-fan_max_state))
		fan_from=$((fan_from*10))
		fan_to=$((fan_dynamic_min-fan_max_state))
		fan_to=$((fan_to*10))
		log_info "FAN minimum speed is changed from $fan_from to $fan_to percent"
		if [ "$fan_dynamic_min" -lt "$fan_dynamic_min_last" ]; then
			handle_dynamic_trend=1
		fi
		fan_dynamic_min_last=$fan_dynamic_min
		echo $fan_to > $thermal_path/fan_dynamic_min
	fi
	# Arrange FAN and update if necessary (f.e. in case when some unit was
	# inserted back or dynamic minimim has been changed down.
	if [ "$full_speed" -eq "$pwm_max" ] || [ "$handle_dynamic_trend" -eq 1 ]; then
		check_trip_min_vs_current_temp "high" $fan_high_trip_low_limit
		full_speed=$pwm_noact
		handle_dynamic_trend=0
	fi

	# Periodic audit for fan speed reducing.
	# TMP: Temporary disable audit. Uncomment line below in next release.
	# audit_count=$((audit_count+1))
	if [ "$audit_count" -ge "$audit_trigger" ]; then
		cooling_min=$((fan_dynamic_min-fan_max_state))
		cooling=$(< $cooling_cur_state)
		if [ "$cooling_min" -le  "$cooling" ]; then
			cooling_level_updated=0
			# Test for normal thermal zones.
			check_trip_min_vs_current_temp "norm" $fan_norm_trip_low_limit
			if [ "$cooling_level_updated" -eq 0 ]; then
				# Test for high thermal zones.
				check_trip_min_vs_current_temp "high" $fan_high_trip_low_limit
			fi
		fi
		audit_count=0
	fi

	# Periodic log report.
	count=$((count+1))
	[ -f "$config_path/periodic_report" ] && periodic_report=$(< $config_path/periodic_report)
	if [ "$count" -ge "$periodic_report" ]; then
		count=0
		thermal_periodic_report
	fi
done
