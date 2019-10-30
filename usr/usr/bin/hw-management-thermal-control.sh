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
#  t1: MSN27*|MSN24*		Panther, Spider
#  t2: MSN21*			Bulldog
#  t3: MSN274*			Panther SF
#  t4: MSN201*			Boxer
#  t5: MSN27*|MSB*|MSX*		Neptune, Tarantula, Scorpion, Scorpion2
#  t6: QMB7*|SN37*|SN34*	Jaguar, Anaconda

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

. /lib/lsb/init-functions

# Check if this is Redhat based distribution (RH, CentOS, Fedora etc.)
# log_action_msg exist in Debian LSB definitions
# Define log_action_msg function in case of Redhat based distribution
if [ -d /etc/redhat-lsb ]; then
log_action_msg()
{
	echo "$@"
	command -v systemd-cat > /dev/null 2>&1
	rc=$?
	if [ $rc -eq 0 ]; then
		echo "$@" | systemd-cat -p info -t hw-management
        else
		logger -p info -t hw-management "$@"
	fi
}
fi

# Paths to thermal sensors, device present states, thermal zone and cooling device
hw_management_path=/var/run/hw-management
thermal_path=$hw_management_path/thermal
power_path=$hw_management_path/power
config_path=$hw_management_path/config
temp_fan_amb=$thermal_path/fan_amb
temp_port_amb=$thermal_path/port_amb
temp_asic=$thermal_path/asic
pwm=$thermal_path/pwm1
psu1_status=$thermal_path/psu1_status
psu2_status=$thermal_path/psu2_status
psu1_fan1_speed=$thermal_path/psu1_fan1_speed_get
psu2_fan1_speed=$thermal_path/psu2_fan1_speed_get
psu1_pwr_status=$power_path/psu1_pwr_status
psu2_pwr_status=$power_path/psu2_pwr_status
fan_command=$config_path/fan_command
fan_psu_default=$config_path/fan_psu_default
tz_mode=$thermal_path/mlxsw/thermal_zone_mode
tz_policy=$thermal_path/mlxsw/thermal_zone_policy
tz_temp=$thermal_path/mlxsw/thermal_zone_temp
temp_trip_norm=$thermal_path/mlxsw/temp_trip_norm
temp_trip_high=$thermal_path/mlxsw/temp_trip_high
temp_trip_hot=$thermal_path/mlxsw/temp_trip_hot
temp_trip_crit=$thermal_path/mlxsw/temp_trip_crit
cooling_cur_state=$thermal_path/cooling_cur_state
thermal_sys=/sys/class/thermal
highest_tz="none"
wait_for_config=120

# Input parameters for the system thermal class, the number of tachometers, the
# number of replicable power supply units and for sensors polling time (seconds)
system_thermal_type_def=1
polling_time_def=60
max_tachos_def=12
max_psus_def=2
max_ports_def=64
system_thermal_type=${1:-$system_thermal_type_def}
max_tachos=${2:-$max_tachos_def}
max_psus=${3:-$max_psus_def}
max_ports=${4:-$max_ports_def}
polling_time=${5:-$polling_time_def}

# Local constants
pwm_noact=0
pwm_max=1
pwm_max_rpm=255
cooling_set_max_state=20
pwm_def_rpm=153
cooling_set_def_state=16
max_amb=120000
untrusted_sensor=0
hysteresis=5000
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

# Class t1 for MSN27*|MSN24* (Panther, Spider)
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

p2c_dir_trust_t1=(45000 13 $max_amb 13)
p2c_dir_untrust_t1=(25000 13 30000 14 30000 14 35000 15 40000 16 $max_amb 16)
c2p_dir_trust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
c2p_dir_untrust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_trust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_untrust_t1=(20000 13 25000 14 30000 15 35000 16  $max_amb 16)
trust1=16
untrust1=16

# Class t2 for MSN21* (Bulldog)
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

# Class t3 for MSN274* (Panther SF)
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

# Class t4 for MSN201* (Boxer)
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

# Class t5 for MSN370* (Anaconda)
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
pwm_required=$pwm_noact
fan_max_state=10
fan_dynamic_min=12
fan_dynamic_min_last=12
untrusted_sensor=0
p2c_dir=0
c2p_dir=0
unk_dir=0
ambient=0
set_cur_state=0

validate_thermal_configuration()
{
	# Wait for symbolic links creation.
	sleep 3
	# Validate FAN fault symbolic links.
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ ! -L $thermal_path/fan"$i"_fault ]; then
			log_failure_msg "FAN fault status attributes are not exist"
			return 1
		fi
		if [ ! -L $thermal_path/fan"$i"_speed_get ]; then
			log_failure_msg "FAN input attributes are not exist"
			return 1
		fi
	done
	if [ ! -L $cooling_cur_state ] || [ ! -L $tz_mode  ] ||
	   [ ! -L $temp_trip_norm ] || [ ! -L $tz_temp ]; then
		log_failure_msg "Thermal zone attributes are not exist"
		return 1
	fi
	if [ ! -L $pwm ] || [ ! -L $asic ]; then
		log_failure_msg "PWM control and ASIC attributes are not exist"
		return 1
	fi
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -L $thermal_path/module"$i"_temp ]; then
			if [ ! -L $thermal_path/module"$i"_temp_fault ]; then
				log_failure_msg "QSFP module attributes are not exist"
				return 1
			fi
		fi
	done
	if [ ! -L $fan_amb ] || [ ! -L $port_amb ]; then
		log_failure_msg "Ambient temperature sensors attributes are not exist"
		return 1
	fi
	if [ $max_psus -gt 0 ]; then
		if [ ! -L $psu1_status ] || [ ! -L $psu2_status ]; then
			log_failure_msg "PS units status attributes are not exist"
			return 1
		fi
	fi
}

check_untrested_module_sensor()
{
	for ((i=1; i<=$module_counter; i+=1)); do
		tz_check_suspend
		if [ "$?" -ne 0 ]; then
			exit
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
	log_success_msg "Thermal periodic report"
	log_success_msg "======================="
	log_success_msg "Temperature(mC): asic $f1 fan amb $f2 port amb $f3"
	log_success_msg "Cooling(%): pwm $f6 ps_fan_speed $((ps_fan_speed)) dynaimc_min $dyn"
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ -f $thermal_path/fan"$i"_speed_get ]; then
			tacho=`cat $thermal_path/fan"$i"_speed_get`
			fault=`cat $thermal_path/fan"$i"_fault`
			log_success_msg "tacho$i speed is $tacho fault is $fault"
		fi
	done
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -f $thermal_path/module"$i"_temp_input ]; then
			t1=`cat $thermal_path/module"$i"_temp_input`
			if [ "$t1" -gt  "0" ]; then
				t2=`cat $thermal_path/module"$i"_temp_fault`
				t3=`cat $thermal_path/module"$i"_temp_crit`
				t4=`cat $thermal_path/module"$i"_temp_emergency`
				log_success_msg "module$i temp $t1 fault $t2 crit $t3 emerg $t4"
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
					log_success_msg "tz module$i temp $t1 trips $t2 $t3 $t4 $t5 $t6 $t7"
				fi
			fi
		fi
	done
	for ((i=1; i<=$gearbox_counter; i+=1)); do
		if [ -f $thermal_path/gearbox"$i"_temp_input ]; then
			t1=`cat $thermal_path/gearbox"$i"_temp_input`
			if [ "$t1" -gt  "0" ]; then
				log_success_msg "gearbox$i temp $t1"
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
					log_success_msg "tz gearbox$i temp $t1 trips $t2 $t3 $t4 $t5 $t6 $t7"
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
		log_success_msg "tz asic temp $t1 trips $t2 $t3 $t4 $t5 $t6 $t7"
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

get_psu_presence()
{
	for ((i=1; i<=$max_psus; i+=1)); do
		if [ -f $thermal_path/psu"$i"_status ]; then
			present=`cat $thermal_path/psu"$i"_status`
			if [ $present -eq 0 ]; then
				pwm_required_act=$pwm_max
				if [ -L $tz_mode ]; then
					mode=`cat $tz_mode`
					# Disable asic thermal zone if were enabled.
					if [ $mode = "enabled" ]; then
						echo disabled > $tz_mode
						log_action_msg "ASIC thermal zone is disabled due to PS absence"
					fi
					policy=`cat $tz_policy`
					if [ $policy = "step_wise" ]; then
						echo user_space > $tz_policy
						log_action_msg "ASIC thermal zone policy is set to user_space due to PS absence"
					fi
				fi
				for ((i=1; i<=$module_counter; i+=1)); do
					if [ -L $thermal_path/mlxsw-module"$i"/thermal_zone_mode ]; then
						mode=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_mode`
						if [ $mode = "enabled" ]; then
							echo disabled > $thermal_path/mlxsw-module"$i"/thermal_zone_mode
							log_action_msg "QSFP module $i thermal zone is disabled due to PS absence"
						fi
						policy=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_policy`
						if [ $policy = "step_wise" ]; then
							echo user_space > $thermal_path/mlxsw-module"$i"/thermal_zone_policy
							log_action_msg "QSFP module $i thermal zone policy is set to user_space due to PS absence"
						fi
					fi
				done
				for ((i=1; i<=$gearbox_counter; i+=1)); do
					if [ -f $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode ]; then
						mode=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode`
						if [ $mode = "enabled" ]; then
							echo disabled > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode
							log_action_msg "Gearbox $i thermal zone is disabled due to PS absence"
						fi
						policy=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy`
						if [ $policy = "step_wise" ]; then
							echo user_space > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy
							log_action_msg "Gearbox $i thermal zone policy is set to user_space due to PS absence"
						fi
					fi
				done
				set_cur_state=$(($cooling_set_max_state-$fan_max_state))
				echo $cooling_set_max_state > $cooling_cur_state

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
			mode=`cat $tz_mode`
			# Disable asic and modules thermal zones if were enabled.
			if [ $mode = "enabled" ]; then
				echo disabled > $tz_mode
				log_action_msg "ASIC thermal zone is disabled due to FAN fault"
			fi
			policy=`cat $tz_policy`
			if [ $policy = "step_wise" ]; then
				echo user_space > $tz_policy
				log_action_msg "ASIC thermal zone policy is set to user_space due to FAN fault"
			fi
			for ((i=1; i<=$module_counter; i+=1)); do
				if [ -f $thermal_path/mlxsw-module"$i"/thermal_zone_mode ]; then
					mode=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_mode`
					if [ $mode = "enabled" ]; then
						echo disabled > $thermal_path/mlxsw-module"$i"/thermal_zone_mode
						log_action_msg "QSFP module $i thermal zone is disabled due to FAN fault"
					fi
					policy=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_policy`
					if [ $policy = "step_wise" ]; then
						echo user_space > $thermal_path/mlxsw-module"$i"/thermal_zone_policy
						log_action_msg "QSFP module $i thermal zone policy is set to user_space due to FAN fault"
					fi
				fi
			done
			for ((i=1; i<=$gearbox_counter; i+=1)); do
				if [ -f $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode ]; then
					mode=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode`
					if [ $mode = "enabled" ]; then
						echo disabled > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode
						log_action_msg "Gearbox $i thermal zone is disabled due to FAN fault"
					fi
					policy=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy`
					if [ $policy = "step_wise" ]; then
						echo user_space > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy
						log_action_msg "Gearbox $i thermal zone policy is set to user_space due to FAN fault"
					fi
				fi
			done
			set_cur_state=$(($cooling_set_max_state-$fan_max_state))
			echo $cooling_set_max_state > $cooling_cur_state

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

set_pwm_min_speed()
{
	untrusted_sensor=0

	# Check for untrusted modules
	check_untrested_module_sensor

	# Set FAN minimum speed according to  presence of untrusted cabels.
	if [ $untrusted_sensor -eq 0 ]; then
		fan_dynamic_min=$config_trust
	else
		fan_dynamic_min=$config_untrust
	fi
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

thermal_control_exit()
{
	log_action_msg "Mellanox thermal control is terminated (PID=${thermal_control_pid})"

	if [ -f /var/run/hw-management.pid ]; then
		rm -rf /var/run/hw-management.pid
	fi
	log_end_msg 0
	exit 1
}

check_trip_min_vs_current_temp()
{

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
		set_cur_state=$(($fan_dynamic_min-$fan_max_state))
		echo $fan_dynamic_min > $cooling_cur_state
		echo $set_cur_state > $cooling_cur_state
		cur_state=$(($set_cur_state*10))
		case $1 in
		1)
			log_action_msg "FAN speed is set to $cur_state percent due to thermal zone event"
		;;
		2)
			log_action_msg "FAN speed is set to $cur_state percent due to system health recovery"
		;;
		*)
			return
		;;
		esac
	fi
}

# Handle events sent by command kill -USR1 to /var/run/hw-management.pid.
thermal_down_event()
{
	# The received event notifies about fast temperature decreasing. It
	# could happen in case one or few very hot QSFP module cables have been
	# removed. In this situation temperature trend, handled by the kernel
	# thermal algorithm could go down once, and then could stay in stable
	# state, while PWM state will be decreased only once. As a side effect
	# PWM will be in not optimal. Set PWM speed to dynamic speed minimum
	# value and give to kernel thermal algorithm can stabilize PWM speed
	# if necessary.
	check_trip_min_vs_current_temp 1
	# The received event notifies about PWM change as well.
}

# Handle the next POSIX signals by thermal_control_exit:
# SIGINT	2	Terminal interrupt signal.
# SIGKILL	9	Kill (cannot be caught or ignored).
# SIGTERM	15	Termination signal.
trap 'thermal_control_exit' INT KILL TERM

# Handle the next POSIX signal by thermal_down_event and
# SIGUSR1	10	User-defined signal 1.
# SIGUSR2	12	User-defined signal 2.
trap 'thermal_down_event' USR1

# Initialization during start up.
thermal_control_pid=$$
if [ -f /var/run/hw-management.pid ]; then
	pid=`cat /var/run/hw-management.pid`
	# Only one instance of thermal control could be activated
	if [ -d /proc/$pid ]; then
		log_warning_msg "Mellanox thermal control is already running (PID=${thermal_control_pid})"
		exit 0
	fi
fi

log_action_msg "Mellanox thermal control is started"
echo $thermal_control_pid > /var/run/hw-management.pid

[ -f $config_path/thermal_delay ] && thermal_delay=`cat $config_path/thermal_delay`; [ $thermal_delay ] && sleep $thermal_delay;

disable_zones_def_pwm()
{
	if [ -L $tz_mode ]; then
		mode=`cat $tz_mode`
		# Disable asic and modules thermal zones if were enabled.
		if [ $mode = "enabled" ]; then
			echo disabled > $tz_mode
			log_action_msg "ASIC thermal zone is disabled due to thermal algorithm is suspended"
		fi
		policy=`cat $tz_policy`
		if [ $policy = "step_wise" ]; then
			echo user_space > $tz_policy
			log_action_msg "ASIC thermal zone policy is set to user_space due to thermal algorithm is suspended"
		fi
	fi
	for ((i=1; i<=$module_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-module"$i"/thermal_zone_mode ]; then
			mode=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_mode`
			if [ $mode = "enabled" ]; then
				echo disabled > $thermal_path/mlxsw-module"$i"/thermal_zone_mode
				log_action_msg "QSFP module $i thermal zone is disabled due to thermal algorithm is suspended"
			fi
			policy=`cat $thermal_path/mlxsw-module"$i"/thermal_zone_policy`
			if [ $policy = "step_wise" ]; then
				echo user_space > $thermal_path/mlxsw-module"$i"/thermal_zone_policy
				log_action_msg "QSFP module $i thermal zone policy is set to user_space due to thermal algorithm is suspended"
			fi
		fi
	done
	for ((i=1; i<=$gearbox_counter; i+=1)); do
		if [ -f $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode ]; then
			mode=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode`
			if [ $mode = "enabled" ]; then
				echo disabled > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_mode
				log_action_msg "Gearbox $i thermal zone is disabled due to thermal algorithm is suspended"
			fi
			policy=`cat $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy`
			if [ $policy = "step_wise" ]; then
				echo user_space > $thermal_path/mlxsw-gearbox"$i"/thermal_zone_policy
				log_action_msg "Gearbox $i thermal zone policy is set to user_space due to thermal algorithm is suspended"
			fi
		fi
	done
	echo $pwm_def_rpm > $pwm
	set_cur_state=$(($cooling_set_def_state-$fan_max_state))
	echo $cooling_set_def_state > $cooling_cur_state

	log_action_msg "Set fan speed to default"
}

trip_points_num=4
tz_asic_trips=(75 85 105 110)
tz_module_trips=(60 70 80 90)
tz_gearbox_trips=(75 85 105 110)

init_tz_highest()
{
	if [ ! -L $thermal_path/highest_thermal_zone ]; then
		ln -sf $thermal_path/mlxsw $thermal_path/highest_thermal_zone
		tzname=`basename "$(readlink -f $thermal_path/highest_thermal_zone)"`
		highest_tz=$tzname
		echo 0 > $thermal_path/highest_tz_num
		echo 0 > $thermal_path/highest_score
	fi
}

tz_check_suspend()
(
	[ -f "$config_path/suspend" ] && suspend=`cat $config_path/suspend`
	if [ $suspend ] &&  [ "$suspend" = "1" ]; then
		return 1
	fi
	exit 0
)

tz_score_calculate()
{
	delta=`expr '(' '(' $2 - $1 ')' / 2 ')' / $2 + $1`
	score=`expr $delta + $shift`
}

get_tz_asic_score()
{
	delta=0
	shift=1

	tz_check_suspend
	if [ "$?" -ne 0 ]; then
		exit
	fi

	temp_curr=`cat $tz_temp`
	v1=`echo $temp_curr`
	v1=$(($v1/1000))
	for ((t=0; t<$trip_points_num; t++)); do
		v2=`echo ${tz_asic_trips[t]}`
		if [ "$v1" -lt "$v2" ]; then
			tz_score_calculate $v1 $v2
			max_score=$score
			break
		fi
		shift=$(($shift*256))
	done
}

get_tz_module_score()
{
	delta=0
	shift=1

	tz_check_suspend
	if [ "$?" -ne 0 ]; then
		exit
	fi

	temp_curr=`cat $thermal_path/mlxsw-module"$1"/thermal_zone_temp`
	v1=`echo $temp_curr`
	v1=$(($v1/1000))
	for ((t=0; t<$trip_points_num; t++)); do
		v2=`echo ${tz_module_trips[t]}`
		if [ "$v1" -lt "$v2" ]; then
			tz_score_calculate $v1 $v2
			break
		fi
		shift=$(($shift*256))
	done
}

get_tz_gearbox_score()
{
	delta=0
	shift=1

	tz_check_suspend
	if [ "$?" -ne 0 ]; then
		exit
	fi

	temp_curr=`cat $thermal_path/mlxsw-gearbox"$1"/thermal_zone_temp`
	v1=`echo $temp_curr`
	v1=$(($v1/1000))
	for ((t=0; t<$trip_points_num; t++)); do
		v2=`echo ${tz_gearbox_trips[t]}`
		if [ "$v1" -lt "$v2" ]; then
			tz_score_calculate $v1 $v2
			break
		fi
		shift=$(($shift*256))
	done
}

get_tz_highest()
{
	score=0
	max_tz=0
	max_score=`cat $thermal_path/highest_score`
	get_tz_asic_score
	for ((p=1; p<=$module_counter; p+=1)); do
		if [ -L $thermal_path/mlxsw-module"$p"/thermal_zone_temp ]; then

			tz_check_suspend
			if [ "$?" -ne 0 ]; then
				exit
			fi

			get_tz_module_score $p
			if [ "$score" -gt "$max_score" ]; then
				max_score=$score
				max_tz=$p
				echo $max_score > $thermal_path/highest_score
			fi
		fi
	done
	for ((p=1; p<=$gearbox_counter; p+=1)); do
		if [ -L $thermal_path/mlxsw-gearbox"$p"/thermal_zone_temp ]; then

			tz_check_suspend
			if [ "$?" -ne 0 ]; then
				exit
			fi

			get_tz_gearbox_score $p
			if [ "$score" -gt "$max_score" ]; then
				max_score=$score
				max_tz=$(($p+$module_counter))
				echo $max_score > $thermal_path/highest_score
			fi
		fi
	done

	highest_tz_num=`cat $thermal_path/highest_tz_num`
	if [ "$max_tz" != "$highest_tz_num" ]; then
		if [ -L $thermal_path/highest_thermal_zone ]; then
			tzname=`basename "$(readlink -f $thermal_path/highest_thermal_zone)"`
			echo user_space > $thermal_path/highest_thermal_zone/thermal_zone_policy
			echo disabled > $thermal_path/highest_thermal_zone/thermal_zone_mode
			log_action_msg "Thermal zone $tzname: mode disabled, policy user_space"
			unlink $thermal_path/highest_thermal_zone
		fi
		if [ "$max_tz" != "0" ]; then
			if [ "$max_tz" -gt "$module_counter" ]; then
				gearbox_tz=$(($max_tz-$module_counter))
				ln -sf $thermal_path/mlxsw-gearbox"$gearbox_tz" $thermal_path/highest_thermal_zone
			else
				ln -sf $thermal_path/mlxsw-module"$max_tz" $thermal_path/highest_thermal_zone
			fi
		else
			ln -sf $thermal_path/mlxsw $thermal_path/highest_thermal_zone
		fi
		echo $max_tz > $thermal_path/highest_tz_num
		echo $max_score > $thermal_path/highest_score

		tz_check_suspend
		if [ "$?" -ne 0 ]; then
			exit
		fi

		echo step_wise > $thermal_path/highest_thermal_zone/thermal_zone_policy
		echo enabled > $thermal_path/highest_thermal_zone/thermal_zone_mode
		tzname=`basename "$(readlink -f $thermal_path/highest_thermal_zone)"`
		highest_tz=$tzname
		log_action_msg "Thermal zone $highest_tz: mode enabled, policy step_wise"
	fi

	# Set PWM to dynamic minimum if highest zone temperature is below the
	# high trip temperature minus hysteresis.
	if [ ! -L $thermal_path/highest_thermal_zone ]; then
		init_tz_highest
	fi
	temp_now=`cat $thermal_path/highest_thermal_zone/thermal_zone_temp`
	trip_high=`cat $thermal_path/highest_thermal_zone/temp_trip_high`
	trip_high=$(($trip_high-$hysteresis))
	if [ $trip_high -gt  $temp_now ]; then
		cooling=`cat $thermal_path/cooling_cur_state`
		set_cur_state=$(($fan_dynamic_min-$fan_max_state))
		if [ $cooling -gt $set_cur_state ]; then
			echo disabled > $thermal_path/highest_thermal_zone/thermal_zone_mode
			echo $fan_dynamic_min > $cooling_cur_state
			echo $set_cur_state > $cooling_cur_state
			echo enabled > $thermal_path/highest_thermal_zone/thermal_zone_mode
			cur_state=$(($set_cur_state*10))
			log_action_msg "FAN speed is set to $cur_state percent"
		fi
	fi
}

# Wait for thermal configuration.
log_action_msg "Mellanox thermal control is waiting for configuration (PID=${thermal_control_pid})"
/bin/sleep $wait_for_config
# Initialize system dynamic minimum speed data base.
init_system_dynamic_minimum_db
init_fan_dynamic_minimum_speed

if [ -f $config_path/module_counter ]; then
	module_counter=`cat $config_path/module_counter`
fi
if [ -f $config_path/gearbox_counter ]; then
	gearbox_counter=`cat $config_path/gearbox_counter`
fi

# Periodic report counter
periodic_report=$(($polling_time*$report_counter))
periodic_report=12	# For debug - remove after tsting
count=0
suspend_thermal=0;
init_tz_highest
# Start thermal monitoring.
while true
do
	/bin/sleep $polling_time

	# Check if thermal is suspended
	[ -f "$config_path/suspend" ] && suspend=`cat $config_path/suspend`
	if [ $suspend ] && [ "$suspend" != "$suspend_thermal" ]; then
		if [ "$suspend" = "1" ]; then
			disable_zones_def_pwm
			init_tz_highest
			log_action_msg "Thermal algorithm is manually suspend"
		else
			log_action_msg "Thermal algorithm is manually resumed"
			sleep 1
		fi
		suspend_thermal=$suspend
		sleep 1
		continue
	else
		if [ "$suspend_thermal" = "1" ]; then
			# Validate there is no enabled thermal zones.
			if [ -L $pwm ]; then
				cur_pwm=`cat $pwm`
				if [ "$cur_pwm" != "$pwm_def_rpm" ]; then
					disable_zones_def_pwm
				fi
			fi
			sleep 1
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
		init_tz_highest
		continue
	fi
	# If one of tachometers is faulty disable thermal zone and set PWM
	# to the maximum speed.
	get_fan_faults
	if [ $pwm_required_act -eq $pwm_max ]; then
		init_tz_highest
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
		log_action_msg "FAN minimum speed is changed from $fan_from to $fan_to percent"
		fan_dynamic_min_last=$fan_dynamic_min
		echo $fan_to > $thermal_path/fan_dynamic_min
	fi
	# Enable ASIC thermal zone if it has been disabled before.
	mode=`cat $tz_mode`
	highest_tz_num=`cat $thermal_path/highest_tz_num`
	if [ $mode = "disabled" ] && [ $highest_tz_num = "0" ]; then
		echo enabled > $tz_mode
		echo step_wise > $tz_policy
		log_action_msg "ASIC thermal zone is re-enabled"
		# System health (PS units or FANs) has been recovered. Set PWM
		# speed to dynamic speed minimum value and give to kernel
		# thermal algorithm can stabilize PWM speed if necessary.
		check_trip_min_vs_current_temp 2
	fi

	get_tz_highest

	count=$(($count+1))
	if [ $count -eq $periodic_report ]; then
		count=0
		thermal_periodic_report
	fi
done
