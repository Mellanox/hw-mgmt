#!/bin/bash
########################################################################
# Copyright (c) 2018 Mellanox Technologies. All rights reserved.
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
hw_management_path=/var/run/hw-management
thermal_path=$hw_management_path/thermal
config_path=$hw_management_path/config
temp_fan_amb=$thermal_path/fan_amb
temp_port_amb=$thermal_path/port_amb
pwm=$thermal_path/pwm1
asic=$thermal_path/asic
psu1_status=$thermal_path/psu1_status
psu2_status=$thermal_path/psu2_status
fan_command=$config_path/fan_command
tz_mode=$thermal_path/mlxsw/thermal_zone_mode
tz_policy=$thermal_path/mlxsw/thermal_zone_policy
tz_temp=$thermal_path/mlxsw/thermal_zone_temp
temp_trip_norm=$thermal_path/mlxsw/temp_trip_norm
cooling_cur_state=$thermal_path/cooling_cur_state
wait_for_config=120

# Input parameters for the system thermal class, the number of tachometers, the
# number of replicable power supply units and for sensors polling time (seconds)
system_thermal_type_def=1
polling_time_def=60

# Local constants
pwm_noact=0
pwm_max=1
cooling_set_max_state=20
cooling_set_def_state=16
max_amb=120000
untrusted_sensor=0
module_counter=0
gearbox_counter=0

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
trust1=16
untrust1=16

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
trust2=13
untrust2=16

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
trust3=13
untrust3=17

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
p2c_dir_untrust_t4=(10000 12 15000 13 20000 14 30000 15 35000 16 $max_amb 16)
c2p_dir_trust_t4=(45000 12 $max_amb 12)
c2p_dir_untrust_t4=(15000 12 20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_trust_t4=(45000 12  $max_amb 12)
unk_dir_untrust_t4=(10000 12 15000 13 20000 14 30000 15 35000 16 $max_amb 16)
trust4=12
untrust4=16

# Class t5 for MSN370*|MSN35*
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

#p2c_dir_trust_t5=(20000 12 25000 13 40000 14 $max_amb 14)
#p2c_dir_untrust_t5=(10000 12 25000 13 30000 14 35000 15 40000 16 $max_amb 16)
#c2p_dir_trust_t5=(20000 12 30000 13 40000 14 $max_amb 14)
#c2p_dir_untrust_t5=(20000 12 35000 13 40000 14 $max_amb 14)
#unk_dir_trust_t5=(20000 12  $max_amb 14)
#unk_dir_untrust_t5=(10000 12 25000 13 30000 14 35000 15 40000 16 $max_amb 16)
#trust5=12
#untrust5=16
# Temporary comment out the above table and put 60% as common default.
# Uncomment it back after extra testing in chamber and remove the below.
p2c_dir_trust_t5=(45000 16  $max_amb 16)
p2c_dir_untrust_t5=(45000 16  $max_amb 16)
c2p_dir_trust_t5=(45000 16  $max_amb 16)
c2p_dir_untrust_t5=(45000 16  $max_amb 16)
unk_dir_trust_t5=(45000 16  $max_amb 16)
unk_dir_untrust_t5=(45000 16  $max_amb 16)
trust5=16
untrust5=16

# Local variables
report_counter=120
fan_max_state=10
fan_dynamic_min=12
fan_dynamic_min_last=12
untrusted_sensor=0
p2c_dir=0
c2p_dir=0
unk_dir=0
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

validate_thermal_configuration()
{
	# Wait for symbolic links creation.
	sleep 3
	# Validate FAN fault symbolic links.
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ ! -L $thermal_path/fan"$i"_fault ]; then
			log_err "FAN fault attributes are not exist"
			return 1
		fi
		if [ ! -L $thermal_path/fan"$i"_speed_get ]; then
			log_err "FAN input attributes are not exist"
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
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -L $thermal_path/module"$i"_temp ]; then
			if [ ! -L $thermal_path/module"$i"_temp_fault ]; then
				log_err "QSFP module attributes are not exist"
				return 1
			fi
		fi
	done
	if [ ! -L $temp_fan_amb ] || [ ! -L $temp_port_amb ]; then
		log_err "Ambient temperature sensors attributes are not exist"
		return 1
	fi
	if [ $max_psus -gt 0 ]; then
		if [ ! -L $psu1_status ] || [ ! -L $psu2_status ]; then
			log_err "PS units status attributes are not exist"
			return 1
		fi
	fi
}

check_untrested_module_sensor()
{
	for ((i=1; i<=$module_counter; i+=1)); do
		tz_check_suspend
		if [ "$?" -ne 0 ]; then
			return
		fi
		if [ -L $thermal_path/module"$i"_temp_fault ]; then
			temp_fault=`cat $thermal_path/module"$i"_temp_fault`
			if [ $temp_fault -eq 1 ]; then
				untrusted_sensor=1
			fi
		fi
	done
}

thermal_periodic_report()
{
	f1=`cat $thermal_path/mlxsw/thermal_zone_temp`
	f2=`cat $temp_fan_amb`
	f3=`cat $temp_port_amb`
	f4=`cat $pwm`
	f5=$(($fan_dynamic_min-$fan_max_state))
	dyn=$(($f5*10))
	cooling=`cat $cooling_cur_state` # entry=`cat $thermal_path/cooling_cur_state`
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
	f5=$(($f5*10))
	f6=$(($set_cur_state*10))
	log_info "Thermal periodic report"
	log_info "======================="
	log_info "Temperature(mC): asic $f1 fan amb $f2 port amb $f3"
	log_info "Cooling(%): pwm $f6 ps_fan_speed $((ps_fan_speed)) dynaimc_min $dyn"
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ -f $thermal_path/fan"$i"_speed_get ]; then
			tacho=`cat $thermal_path/fan"$i"_speed_get`
			fault=`cat $thermal_path/fan"$i"_fault`
			log_info "tacho$i speed is $tacho fault is $fault"
		fi
	done
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -f $thermal_path/module"$i"_temp_input ]; then
			t1=`cat $thermal_path/module"$i"_temp_input`
			if [ "$t1" -gt  "0" ]; then
				t2=`cat $thermal_path/module"$i"_temp_fault`
				t3=`cat $thermal_path/module"$i"_temp_crit`
				t4=`cat $thermal_path/module"$i"_temp_emergency`
				log_info "module$i temp $t1 fault $t2 crit $t3 emerg $t4"
			fi
			if [ -f $thermal_path/mlxsw-module"$i"/thermal_zone_temp ]; then
				t7=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_mode`
				if [ $t7 = "enabled" ]; then
					t1=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_temp`
					t2=`cat $thermal_path/mlxsw-module"$i"/temp_trip_norm`
					t3=`cat $thermal_path/mlxsw-module"$i"/temp_trip_high`
					t4=`cat $thermal_path/mlxsw-module"$i"/temp_trip_hot`
					t5=`cat $thermal_path/mlxsw-module"$i"/temp_trip_crit`
					t6=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_policy`
					log_info "tz module$i temp $t1 trips $t2 $t3 $t4 $t5 $t6 $t7"
				fi
			fi
		fi
	done
	for ((i=1; i<=$gearbox_counter; i+=1)); do
		if [ -f $thermal_path/gearbox"$i"_temp_input ]; then
			t1=`cat $thermal_path/gearbox"$i"_temp_input`
			if [ "$t1" -gt  "0" ]; then
				log_info "gearbox$i temp $t1"
			fi
			if [ -f $thermal_path/mlxsw-gearbox"$i"/thermal_zone_temp ]; then
				t7=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode`
				if [ $t7 = "enabled" ]; then
					t1=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_temp`
					t2=`cat $thermal_path/mlxsw-gearbox"$i"/temp_trip_norm`
					t3=`cat $thermal_path/mlxsw-gearbox"$i"/temp_trip_high`
					t4=`cat $thermal_path/mlxsw-gearbox"$i"/temp_trip_hot`
					t5=`cat $thermal_path/mlxsw-gearbox"$i"/temp_trip_crit`
					t6=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy`
					log_info "tz gearbox$i temp $t1 trips $t2 $t3 $t4 $t5 $t6 $t7"
				fi
			fi
		fi
	done
	t1=`cat $thermal_path/mlxsw/thermal_zone_temp`
	t2=`cat $thermal_path/mlxsw/temp_trip_norm`
	t3=`cat $thermal_path/mlxsw/temp_trip_high`
	t4=`cat $thermal_path/mlxsw/temp_trip_hot`
	t5=`cat $thermal_path/mlxsw/temp_trip_crit`
	t6=`cat $thermal_path/mlxsw/thermal_zone_policy`
	t7=`cat $thermal_path/mlxsw/thermal_zone_mode`
	if [ $t7 = "enabled" ]; then
		log_info "tz asic temp $t1 trips $t2 $t3 $t4 $t5 $t6 $t7"
	fi
}

config_p2c_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		p2c_dir_trust[i]=${array[i]}
	done
}

config_p2c_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		p2c_dir_untrust[i]=${array[i]}
	done
}

config_c2p_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		c2p_dir_trust[i]=${array[i]}
	done
}

config_c2p_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		c2p_dir_untrust[i]=${array[i]}
	done
}

config_unk_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		unk_dir_trust[i]=${array[i]}
	done
}

config_unk_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		unk_dir_untrust[i]=${array[i]}
	done
}

set_fan_to_full_speed()
{
	set_cur_state=$(($cooling_set_max_state-$fan_max_state))
	echo $cooling_set_max_state > $cooling_cur_state
}

get_psu_presence()
{
	for ((i=1; i<=$max_psus; i+=1)); do
		if [ -f $thermal_path/psu"$i"_status ]; then
			present=`cat $thermal_path/psu"$i"_status`
			if [ $present -eq 0 ]; then
				pwm_required_act=$pwm_max
				if [ $full_speed -ne $pwm_max ]; then
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
	for ((i=1; i<=$max_psus; i+=1)); do
		if [ -L $thermal_path/psu"$i"_pwr_status ]; then
			pwr=`cat $thermal_path/psu"$i"_pwr_status`
			if [ $pwr -eq 1 ]; then
				bus=`cat $config_path/psu"$i"_i2c_bus`
				addr=`cat $config_path/psu"$i"_i2c_addr`
				command=`cat $fan_command`
				entry=`cat $thermal_path/cooling_cur_state`
				speed=${psu_fan_speed[$entry]}
				i2cset -f -y $bus $addr $command $speed wp
			fi
		fi
	done
}

get_fan_faults()
{
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ -L $thermal_path/fan"$i"_fault ]; then
			fault=`cat $thermal_path/fan"$i"_fault`
		fi
		speed=`cat $thermal_path/fan"$i"_speed_get`
		if [ $fault -eq 1 ] || [ $speed -eq 0 ] ; then
			pwm_required_act=$pwm_max
			if [ $full_speed -ne $pwm_max ]; then
				set_fan_to_full_speed
				log_info "FAN speed is set to full speed due to FAN fault"
			fi
			return
		fi
	done

	pwm_required_act=$pwm_noact
}

set_pwm_min_threshold()
{
	untrusted_sensor=0
	ambient=0
	p2c_dir=0
	c2p_dir=0
	unk_dir=0

	# Check for untrusted modules
	check_untrested_module_sensor

	# Define FAN direction
	temp_fan_ambient=`cat $temp_fan_amb`
	temp_port_ambient=`cat $temp_port_amb`
	if [ $temp_fan_ambient -gt  $temp_port_ambient ]; then
		ambient=$temp_port_ambient
		p2c_dir=1
	elif [ $temp_fan_ambient -lt  $temp_port_ambient ]; then
		ambient=$temp_fan_ambient
		c2p_dir=1
	else
		ambient=$temp_fan_ambient
		unk_dir=1
	fi

	# Set FAN minimum speed according to FAN direction, cable type and
	# presence of untrusted cabels.
	if [ $untrusted_sensor -eq 0 ]; then
		if [ $p2c_dir -eq 1 ]; then
			size=${#p2c_dir_trust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${p2c_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${p2c_dir_trust[$(($i+1))]}
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_trust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${c2p_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${c2p_dir_trust[$(($i+1))]}
					break
				fi
			done
		else
			size=${#unk_dir_trust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${unk_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${unk_dir_trust[$(($i+1))]}
					break
				fi
			done
		fi
	else
		if [ $p2c_dir -eq 1 ]; then
			size=${#p2c_dir_untrust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${unk_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${unk_dir_untrust[$(($i+1))]}
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_untrust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${c2p_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${c2p_dir_untrust[$(($i+1))]}
					break
				fi
			done
		else
			size=${#unk_dir_untrust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${unk_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${unk_dir_untrust[$(($i+1))]}
					break
				fi
			done
		fi
	fi
}

init_system_dynamic_minimum_db()
{
	case $system_thermal_type in
	1)
		# Config FAN minimal speed setting for class t1
		config_p2c_dir_trust "${p2c_dir_trust_t1[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t1[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t1[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t1[@]}"
		config_unk_dir_trust "${unk_dir_trust_t1[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t1[@]}"
		;;
	2)
		# Config FAN minimal speed setting for class t2
		config_p2c_dir_trust "${p2c_dir_trust_t2[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t2[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t2[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t2[@]}"
		config_unk_dir_trust "${unk_dir_trust_t2[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t2[@]}"
		;;
	3)
		# Config FAN minimal speed setting for class t3
		config_p2c_dir_trust "${p2c_dir_trust_t3[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t3[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t3[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t3[@]}"
		config_unk_dir_trust "${unk_dir_trust_t3[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t3[@]}"
		;;
	4)
		# Config FAN minimal speed setting for class t4
		config_p2c_dir_trust "${p2c_dir_trust_t4[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t4[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t4[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t4[@]}"
		config_unk_dir_trust "${unk_dir_trust_t4[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t4[@]}"
		;;
	5)
		# Config FAN minimal speed setting for class t5
		config_p2c_dir_trust "${p2c_dir_trust_t5[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t5[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t5[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t5[@]}"
		config_unk_dir_trust "${unk_dir_trust_t5[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t5[@]}"
		;;
	6)
		# Config FAN minimal speed setting for class t6
		config_p2c_dir_trust "${p2c_dir_trust_t5[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t5[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t5[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t5[@]}"
		config_unk_dir_trust "${unk_dir_trust_t5[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t5[@]}"
		;;
	*)
		echo thermal type $system_thermal_type is not supported
		exit 0
		;;
	esac
}

init_fan_dynamic_minimum_speed()
{
	case $system_thermal_type in
	1)
		# Config FAN minimal speed setting for class t1
		config_trust=$trust1
		config_untrust=$untrust1
		;;
	2)
		# Config FAN minimal speed setting for class t2
		config_trust=$trust2
		config_untrust=$untrust2
		;;
	3)
		# Config FAN minimal speed setting for class t3
		config_trust=$trust3
		config_untrust=$untrust3
		;;
	4)
		# Config FAN minimal speed setting for class t4
		config_trust=$trust4
		config_untrust=$untrust4
		;;
	5)
		# Config FAN minimal speed setting for class t5
		config_trust=$trust5
		config_untrust=$untrust5
		;;
	6)
		# Config FAN minimal speed setting for class t6
		config_trust=$trust5
		config_untrust=$untrust5
		;;
	*)
		echo thermal type $system_thermal_type is not supported
		exit 0
		;;
	esac
}

set_default_pwm()
{
	set_cur_state=$(($cooling_set_def_state-$fan_max_state))
	echo $cooling_set_def_state > $cooling_cur_state
	echo $set_cur_state > $cooling_cur_state
	cur_state=$(($set_cur_state*10))
	echo $cur_state > $thermal_path/fan_dynamic_min
	log_info "FAN speed is set to $cur_state percent up to default speed"
}

set_dynamic_min_pwm()
{
	set_cur_state=$(($fan_dynamic_min-$fan_max_state))
	echo $fan_dynamic_min > $cooling_cur_state
	echo $set_cur_state > $cooling_cur_state
	cur_state=$(($set_cur_state*10))
	echo $cur_state > $thermal_path/fan_dynamic_min
	log_info "FAN speed is set to $cur_state percent up to dynamic minimum"
}

check_trip_min_vs_current_temp()
{
	for ((i=1; i<=$gearbox_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-gearbox"$i"/thermal_zone_temp ]; then
			trip_norm=`cat $thermal_path/mlxsw-gearbox"$i"/temp_trip_norm`
			temp_now=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_temp`
			if [ $temp_now -gt 0 ] && [ $trip_norm -le  $temp_now ]; then
				return
			fi
		fi
	done
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-module"$i"/thermal_zone_temp ]; then
			trip_norm=`cat $thermal_path/mlxsw-module"$i"/temp_trip_norm`
			temp_now=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_temp`
			if [ $temp_now -gt 0 ] && [ $trip_norm -le  $temp_now ]; then
				return
			fi
		fi
	done
	trip_norm=`cat $temp_trip_norm`
	temp_now=`cat $tz_temp`
	if [ $trip_norm -gt  $temp_now ]; then
		set_dynamic_min_pwm
	fi
}

enable_disable_zones_set_pwm()
{
	case $1 in
	1)
		mode="enabled"
		policy="step_wise"
		;;
	*)
		mode="disabled"
		policy="user_space"
		;;
	esac

	if [ -L $tz_mode ]; then
		echo $policy > $tz_policy
	fi
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-module"$i"/thermal_zone_mode ]; then
			echo $policy > $thermal_path/mlxsw-module"$i"/thermal_zone_policy
		fi
	done
	for ((i=1; i<=$gearbox_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode ]; then
			echo $policy > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy
		fi
	done
	if [ -L $tz_mode ]; then
		echo $mode > $tz_mode
	fi
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-module"$i"/thermal_zone_mode ]; then
			echo $mode > $thermal_path/mlxsw-module"$i"/thermal_zone_mode
		fi
	done
	for ((i=1; i<=$gearbox_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode ]; then
			echo $mode > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode
		fi
	done

	case $1 in
	1)
		set_pwm_min_threshold
		fan_dynamic_min_last=$fan_dynamic_min
		set_dynamic_min_pwm
		;;
	*)
		set_default_pwm
		;;
	esac
}

tz_check_suspend()
{
	[ -f "$config_path/suspend" ] && suspend=`cat $config_path/suspend`
	if [ $suspend ] &&  [ "$suspend" = "1" ]; then
		return 1
	fi
	return 0
}

[ -f $config_path/thermal_delay ] && thermal_delay=`cat $config_path/thermal_delay`; [ $thermal_delay ] && sleep $thermal_delay;

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
}

log_notice "Mellanox thermal control is started"
# Wait for thermal configuration.
log_notice "Mellanox thermal control is waiting for configuration."
/bin/sleep $wait_for_config &
wait $!

init_service_params
# Initialize system dynamic minimum speed data base.
init_system_dynamic_minimum_db
init_fan_dynamic_minimum_speed

# Periodic report counter
periodic_report=$(($polling_time*$report_counter))
echo $periodic_report > $config_path/periodic_report
count=0
suspend_thermal=0
# Start thermal monitoring.
while true
do
	/bin/sleep $polling_time &
	wait $!

	# Check if thermal algorithm is suspended.
	[ -f "$config_path/suspend" ] && suspend=`cat $config_path/suspend`
	if [ $suspend ] && [ "$suspend" != "$suspend_thermal" ]; then
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
	# Set PWM minimal limit.
	# Set dynamic FAN speed minimum, depending on ambient temperature,
	# presence of untrusted optical cables or presence of any cables
	# with untrusted temperature sensing.
	set_pwm_min_threshold
	# Update PS unit fan speed
	update_psu_fan_speed
	# If one of PS units is out disable thermal zone and set PWM to the
	# maximum speed.
	get_psu_presence
	if [ $pwm_required_act -eq $pwm_max ]; then
		full_speed=$pwm_max
		continue
	fi
	# If one of tachometers is faulty set PWM to the maximum speed.
	get_fan_faults
	if [ $pwm_required_act -eq $pwm_max ]; then
		full_speed=$pwm_max
		continue
	fi
	# Update cooling levels of FAN If dynamic minimum has been changed
	# since the last time.
	if [ $fan_dynamic_min -ne $fan_dynamic_min_last ]; then
		echo $fan_dynamic_min > $cooling_cur_state
		echo $set_cur_state > $cooling_cur_state
		fan_from=$(($fan_dynamic_min_last-$fan_max_state))
		fan_from=$(($fan_from*10))
		fan_to=$(($fan_dynamic_min-$fan_max_state))
		fan_to=$(($fan_to*10))
		log_info "FAN minimum speed is changed from $fan_from to $fan_to percent"
		if [ $fan_dynamic_min -lt $fan_dynamic_min_last ]; then
			handle_dynamic_trend=1
		fi
		fan_dynamic_min_last=$fan_dynamic_min
		echo $fan_to > $thermal_path/fan_dynamic_min
	fi
	# Arrange FAN and update if necessary (f.e. in case when some unit is inserted back).
	if [ $full_speed -eq $pwm_max ] || [ $handle_dynamic_trend -eq 1 ]; then
		check_trip_min_vs_current_temp
		full_speed=$pwm_noact
		handle_dynamic_trend=0
	fi

	count=$(($count+1))
	[ -f "$config_path/periodic_report" ] && periodic_report=`cat $config_path/periodic_report`
	if [ $count -ge $periodic_report ]; then
		count=0
		thermal_periodic_report
	fi
done
