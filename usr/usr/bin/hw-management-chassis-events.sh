#!/bin/bash

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

hw_management_path=/var/run/hw-management
environment_path=$hw_management_path/environment
alarm_path=$hw_management_path/alarm
eeprom_path=$hw_management_path/eeprom
led_path=$hw_management_path/led
system_path=$hw_management_path/system
sfp_path=$hw_management_path/sfp
watchdog_path=$hw_management_path/watchdog
config_path=$hw_management_path/config
events_path=$hw_management_path/events
LED_STATE=/usr/bin/hw-management-led-state-conversion.sh
i2c_bus_max=10
i2c_bus_offset=0
i2c_bus_def_off_eeprom_vpd=8
i2c_bus_def_off_eeprom_cpu=$(< $config_path/i2c_bus_def_off_eeprom_cpu)
i2c_bus_def_off_eeprom_psu=4
i2c_bus_alt_off_eeprom_psu=10
i2c_bus_def_off_eeprom_fan1=11
i2c_bus_def_off_eeprom_fan2=12
i2c_bus_def_off_eeprom_fan3=13
i2c_bus_def_off_eeprom_fan4=14
i2c_comex_mon_bus_default=$(< $config_path/i2c_comex_mon_bus_default)
psu1_i2c_addr=0x51
psu2_i2c_addr=0x50
eeprom_name=''
sfp_counter=0
LOCKFILE="/var/run/hw-management-chassis.lock"
udev_ready=$hw_management_path/.udev_ready
linecard_folders=("alarm" "config" "eeprom" "environment" "led" "system" "thermal")
mlxreg_lc_addr=32
lc_max_num=8

log_err()
{
	logger -t hw-management -p daemon.err "$@"
}

log_info()
{
	logger -t hw-management -p daemon.info "$@"
}

find_i2c_bus()
{
	# Find physical bus number of Mellanox I2C controller. The default
	# number is 1, but it could be assigned to others id numbers on
	# systems with different CPU types.
	for ((i=1; i<i2c_bus_max; i++)); do
		folder=/sys/bus/i2c/devices/i2c-$i
		if [ -d $folder ]; then
			name=$(cut $folder/name -d' ' -f 1)
			if [ "$name" == "i2c-mlxcpld" ]; then
				i2c_bus_offset=$((i-1))
				return
			fi
		fi
	done

	log_err "i2c-mlxcpld driver is not loaded"
	exit 0
}

find_linecard_bus()
{
	# Find base i2c bus number of Mellanox line card.
	for ((i=1; i<i2c_bus_max; i++)); do
		folder=/sys/bus/i2c/devices/i2c-$i/$i-00"$mlxreg_lc_addr"
		if [ -d $folder ]; then
			name=$(cut $folder/name -d' ' -f 1)
			if [ "$name" == "mlxreg-lc" ]; then
				linecard_bus_offset=$i
				return
			fi
		fi
	done

	log_err "mlxreg-lc driver is not loaded"
	exit 0
}

find_linecard_num()
{
	input_bus_num="$1"
	find_linecard_bus "$input_bus_num"
	max_lc_bus_num=$((linecard_bus_offset+lc_max_num))
	# Check line card bus range.
	if [ "$input_bus_num" -le "$max_lc_bus_num" ] &&
	   [ "$input_bus_num" -ge "$linecard_bus_offset" ]; then
		linecard_num=$((input_bus_num-linecard_bus_offset+1))
		# Check line card num range.
		if [ "$linecard_num" -le "$lc_max_num" ] &&
		   [ "$linecard_num" -ge 1 ]; then
			return
		else
			log_err "Line card number out of range. $linecard_num Expected range: 1 - $lc_max_num."
			exit 0
		fi
	else
		log_err "Line card bus number out of range. $input_bus_num Expected range: $linecard_bus_offset - $max_lc_bus_num."
		exit 0
	fi
	log_err "mlxreg-lc driver is not loaded"
	exit 0
}

find_eeprom_name()
{
	bus=$1
	addr=$2
	if [ "$bus" -eq "$i2c_bus_def_off_eeprom_vpd" ]; then
		eeprom_name=vpd_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_cpu" ]; then
		eeprom_name=cpu_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_psu" ] || [ "$bus" -eq "$i2c_bus_alt_off_eeprom_psu" ]; then
		if [ "$addr" = "$psu1_i2c_addr" ]; then
			eeprom_name=psu1_info
		elif [ "$addr" = "$psu2_i2c_addr" ]; then
			eeprom_name=psu2_info
		fi
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan1" ]; then
		eeprom_name=fan1_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan2" ]; then
		eeprom_name=fan2_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan3" ]; then
		eeprom_name=fan3_info
	elif [ "$bus" -eq "$i2c_bus_def_off_eeprom_fan4" ]; then
		eeprom_name=fan4_info
	else
		# Line card VPD at i2c bus {lc_num}07, INI - {lc_num}08.
		case $bus in
		*07)
			eeprom_name=vpd
			;;
		*08)
			eeprom_name=ini
			;;
		esac
	fi
}

lock_service_state_change()
{
	exec {LOCKFD}>${LOCKFILE}
	/usr/bin/flock -x ${LOCKFD}
	trap "/usr/bin/flock -u ${LOCKFD}" EXIT SIGINT SIGQUIT SIGTERM
}

unlock_service_state_change()
{
	/usr/bin/flock -u ${LOCKFD}
}

function create_sfp_symbolic_links()
{
	local event_path="${1}"
	local sfp_name=${event_path##*/net/}

	ln -sf /usr/bin/hw-management-sfp-helper.sh ${sfp_path}/"${sfp_name}"_status
}

# ASIC CPLD event
function asic_cpld_add_handler()
{
        local -r ASIC_I2C_PATH="${1}"

        if [ -f "$config_path/cpld_port" ]; then
                local -r cpld=$(< $config_path/cpld_port)
                if [ "$cpld" == "cpld1" ]; then
			ln -sf "${ASIC_I2C_PATH}"/cpld1_version $system_path/cpld3_version
                fi
                if [ "$cpld" == "cpld3" ]; then
			ln -sf "${ASIC_I2C_PATH}"/cpld3_version $system_path/cpld3_version
                fi
        fi

        # Verify if CPLD attributes are exist
        [ -f "$config_path/cpld_port" ] && cpld=$(< $config_path/cpld_port)
        if [ "$cpld" == "cpld1" ]; then
                if [ -f "${QSFP_I2C_PATH}"/cpld1_version ]; then
                        ln -sf "${QSFP_I2C_PATH}"/cpld1_version $system_path/cpld3_version
                fi
        fi
        if [ "$cpld" == "cpld3" ]; then
                if [ -f "${QSFP_I2C_PATH}"/cpld3_version ]; then
                        ln -sf "${QSFP_I2C_PATH}"/cpld3_version $system_path/cpld3_version
                fi
        fi
}

function asic_cpld_remove_handler()
{
	if [ -f "$config_path/cpld_port" ]; then
		if [ -L $system_path/cpld3_version ]; then
			unlink $system_path/cpld3_version
		else
			rm -rf $system_path/cpld3_version
		fi
	fi
}

function handle_hotplug_event()
{
	local unit=$(echo "$1" | awk '{print tolower($0)}')
	local event=$2
	
	if [ -f $events_path/"$unit" ]; then
		echo "$event" > $events_path/"$unit"
	else
		# ToDo check if leave this error maessage
		log_err "Path ${events_path}/${unit} doesn't exist"
	fi
}

if [ "$1" == "add" ]; then
	# Don't process udev events until service is started and directories are created
	if [ ! -f ${udev_ready} ]; then
		exit 0
	fi
	if [ "$2" == "a2d" ]; then
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Line card event, replace output folder.
				find_linecard_num "$input_bus_num"
				environment_path="$hw_management_path"/lc"$linecard_num"/environment
			fi
		fi
		ln -sf "$3""$4"/in_voltage-voltage_scale $environment_path/"$2"_"$5"_voltage_scale
		for i in {0..7}; do
			if [ -f "$3""$4"/in_voltage"$i"_raw ]; then
				ln -sf "$3""$4"/in_voltage"$i"_raw $environment_path/"$2"_"$5"_raw_"$i"
			fi
		done
	fi
	if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ] ||
	   [ "$2" == "voltmon3" ] || [ "$2" == "voltmon4" ] ||
	   [ "$2" == "voltmon5" ] || [ "$2" == "voltmon6" ] ||
	   [ "$2" == "voltmon7" ] ||
	   [ "$2" == "comex_voltmon1" ] || [ "$2" == "comex_voltmon2" ] ||
	   [ "$2" == "hotswap" ]; then
		if [ "$2" == "comex_voltmon1" ]; then
			find_i2c_bus
			comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
			busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
			busfolder=$(basename "$busdir")
			bus="${busfolder:0:${#busfolder}-5}"
			# Verify if this is not COMEX device
			if [ "$bus" != "$comex_bus" ]; then
				exit 0
			fi
		else
			# Detect if it belongs to line card or to main board.
			input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
			driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
			if [ -d "$driver_dir" ]; then
				driver_name=$(< "$driver_dir"/name)
				if [ "$driver_name" == "mlxreg-lc" ]; then
					# Linecard event, replace output folder.
					find_linecard_num "$input_bus_num"
					environment_path="$hw_management_path"/lc"$linecard_num"/environment
					alarm_path="$hw_management_path"/lc"$linecard_num"/alarm
				fi
			fi
		fi
		for i in {1..3}; do
			if [ -f "$3""$4"/in"$i"_input ]; then
				ln -sf "$3""$4"/in"$i"_input $environment_path/"$2"_in"$i"_input
			fi
			if [ -f "$3""$4"/curr"$i"_input ]; then
				ln -sf "$3""$4"/curr"$i"_input $environment_path/"$2"_curr"$i"_input
			fi
			if [ -f "$3""$4"/power"$i"_input ]; then
				ln -sf "$3""$4"/power"$i"_input $environment_path/"$2"_power"$i"_input
			fi
			if [ -f "$3""$4"/in"$i"_alarm ]; then
				ln -sf "$3""$4"/in"$i"_alarm $alarm_path/"$2"_in"$i"_alarm
			fi
			if [ -f "$3""$4"/curr"$i"_alarm ]; then
				ln -sf "$3""$4"/curr"$i"_alarm $alarm_path/"$2"_curr"$i"_alarm
			fi
			if [ -f "$3""$4"/power"$i"_alarm ]; then
				ln -sf "$3""$4"/power"$i"_alarm $alarm_path/"$2"_power"$i"_alarm
			fi
		done
	fi
	if [ "$2" == "led" ]; then
		# Detect if it belongs to line card or to main board.
		# For main board dirname leds-mlxreg, for line card - leds-mlxreg.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		leds-mlxreg)
			# Default case, nothing to do.
			;;
		leds-mlxreg.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			led_path="$hw_management_path"/lc"$linecard_num"/led
			;;
		esac
		name=$(echo "$5" | cut -d':' -f2)
		color=$(echo "$5" | cut -d':' -f3)
		ln -sf "$3""$4"/brightness $led_path/led_"$name"_"$color"
		echo timer > "$3""$4"/trigger
		ln -sf "$3""$4"/delay_on  $led_path/led_"$name"_"$color"_delay_on
		ln -sf "$3""$4"/delay_off $led_path/led_"$name"_"$color"_delay_off
		ln -sf $LED_STATE $led_path/led_"$name"_state
		lock_service_state_change
		if [ ! -f $led_path/led_"$name"_capability ]; then
			echo none "${color}" "${color}"_blink > $led_path/led_"$name"_capability
		else
			capability=$(< $led_path/led_"$name"_capability)
			capability="${capability} ${color} ${color}_blink"
			echo "$capability" > $led_path/led_"$name"_capability
		fi
		unlock_service_state_change
		$led_path/led_"$name"_state
	fi
	if [ "$2" == "regio" ]; then
		# Detect if it belongs to line card or to main board.
		# For main board dirname mlxreg-io, for linecard - mlxreg-io.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		mlxreg-io)
			# Default case, nothing to do.
			;;
		mlxreg-io.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			system_path="$hw_management_path"/lc"$linecard_num"/system
			;;
		esac
		# Allow to driver insertion off all the attributes.
		sleep 1
		if [ -d "$3""$4" ]; then
			for attrpath in "$3""$4"/*; do
				attrname=$(basename "${attrpath}")
				if [ ! -d "$attrpath" ] && [ ! -L "$attrpath" ] &&
				   [ "$attrname" != "uevent" ] &&
				   [ "$attrname" != "name" ]; then
					ln -sf "$3""$4"/"$attrname" $system_path/"$attrname"
				fi
			done
		fi
	fi
	if [ "$2" == "eeprom" ]; then
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Linecard event, replace output folder.
				find_linecard_num "$input_bus_num"
				eeprom_path="$hw_management_path"/lc"$linecard_num"/eeprom
			fi
		fi
		busdir="$3""$4"
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		find_i2c_bus
		bus=$((bus-i2c_bus_offset))
		addr="0x${busfolder: -2}"
		find_eeprom_name "$bus" "$addr"
		ln -sf "$3""$4"/eeprom $eeprom_path/$eeprom_name 2>/dev/null
		chmod 400 $eeprom_path/$eeprom_name 2>/dev/null
	fi
	if [ "$2" == "cpld" ]; then
		asic_cpld_add_handler "${3}${4}"
	fi
	if [ "$2" == "watchdog" ]; then
		wd_type=$(< "$3""$4"/identity)
		case $wd_type in
			mlx-wdt-*)
				wd_sub="$(echo "$wd_type" | cut -c 9-)"
				if [ ! -d ${watchdog_path}/"${wd_sub}" ]; then
					mkdir ${watchdog_path}/"${wd_sub}"
				fi
				ln -sf "$3""$4"/bootstatus ${watchdog_path}/"${wd_sub}"/bootstatus
				ln -sf "$3""$4"/nowayout ${watchdog_path}/"${wd_sub}"/nowayout
				ln -sf "$3""$4"/status ${watchdog_path}/"${wd_sub}"/status
				ln -sf "$3""$4"/timeout ${watchdog_path}/"${wd_sub}"/timeout
				ln -sf "$3""$4"/identity ${watchdog_path}/"${wd_sub}"/identity
				ln -sf "$3""$4"/state ${watchdog_path}/"${wd_sub}"/state
				if [ -f "$3""$4"/timeleft ]; then
					ln -sf "$3""$4"/timeleft ${watchdog_path}/"${wd_sub}"/timeleft
				fi
				;;
			*)
				;;
		esac
	fi
	# Creating lc folders hierarchy upon line card udev add event.
	if [ "$2" == "linecard" ]; then
		input_bus_num=$(echo "$3""$4" | xargs basename | cut -d"-" -f1)
		find_linecard_num "$input_bus_num"
		if [ ! -d "$hw_management_path"/lc"$linecard_num" ]; then
			mkdir "$hw_management_path"/lc"$linecard_num"
		fi
		for i in "${!linecard_folders[@]}"
		do
			if [ ! -d "$hw_management_path"/lc"$linecard_num"/"${linecard_folders[$i]}" ]; then
				mkdir "$hw_management_path"/lc"$linecard_num"/"${linecard_folders[$i]}"
			fi 
		done
	fi
elif [ "$1" == "mv" ]; then
	if [ "$2" == "sfp" ]; then
		lock_service_state_change
		[ -f "$config_path/sfp_counter" ] && sfp_counter=$(< $config_path/sfp_counter)
		sfp_counter=$((sfp_counter+1))
		echo $sfp_counter > $config_path/sfp_counter
		unlock_service_state_change
		create_sfp_symbolic_links "${3}${4}"
	fi
elif [ "$1" == "hotplug-event" ]; then
	handle_hotplug_event "${2}" "${3}"
else
	if [ "$2" == "a2d" ]; then
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Line card event, replace output folder.
				find_linecard_num "$input_bus_num"
				environment_path="$hw_management_path"/lc"$linecard_num"/environment
			fi
		fi
		unlink $environment_path/"$2"_"$5"_voltage_scale
		for i in {0..7}; do
			if [ -L $environment_path/"$2"_"$5"_raw_"$i" ]; then
				unlink $environment_path/"$2"_"$5"_raw_"$i"
			fi
		done
	fi
	if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ] ||
	   [ "$2" == "voltmon3" ] || [ "$2" == "voltmon4" ] ||
	   [ "$2" == "voltmon5" ] || [ "$2" == "voltmon6" ] ||
	   [ "$2" == "voltmon7" ] ||
	   [ "$2" == "comex_voltmon1" ] || [ "$2" == "comex_voltmon2" ] ||
	   [ "$2" == "hotswap" ]; then
		if [ "$2" == "comex_voltmon1" ]; then
			find_i2c_bus
			comex_bus=$((i2c_comex_mon_bus_default+i2c_bus_offset))
			busdir=$(echo "$3""$4" |xargs dirname |xargs dirname)
			busfolder=$(basename "$busdir")
			bus="${busfolder:0:${#busfolder}-5}"
			# Verify if this is not COMEX device
			if [ "$bus" != "$comex_bus" ]; then
				exit 0
			fi
		else
			# Detect if it belongs to line card or to main board.
			input_bus_num=$(echo "$3""$4"| xargs dirname | xargs dirname | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
			driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
			if [ -d "$driver_dir" ]; then
				driver_name=$(< "$driver_dir"/name)
				if [ "$driver_name" == "mlxreg-lc" ]; then
					# Linecard event, replace output folder.
					find_linecard_num "$input_bus_num"
					environment_path="$hw_management_path"/lc"$linecard_num"/environment
					alarm_path="$hw_management_path"/lc"$linecard_num"/alarm
				fi
			fi
		fi
		for i in {1..3}; do
			if [ -L $environment_path/"$2"_in"$i"_input ]; then
				unlink $environment_path/"$2"_in"$i"_input
			fi
			if [ -L $environment_path/"$2"_curr"$i"_input ]; then
				unlink $environment_path/"$2"_curr"$i"_input
			fi
			if [ -L $environment_path/"$2"_power"$i"_input ]; then
				unlink $environment_path/"$2"_power"$i"_input
			fi
			if [ -L $alarm_path/"$2"_in"$i"_alarm ]; then
				unlink $alarm_path/"$2"_in"$i"_alarm
			fi
			if [ -L $alarm_path/"$2"_curr"$i"_alarm ]; then
				unlink $alarm_path/"$2"_curr"$i"_alarm
			fi
			if [ -L $alarm_path/"$2"_power"$i"_alarm ]; then
				unlink $alarm_path/"$2"_power"$i"_alarm
			fi
		done
	fi
	if [ "$2" == "led" ]; then
		# Detect if it belongs to line card or to main board.
		# For main board dirname leds-mlxreg, for line card - leds-mlxreg.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		leds-mlxreg)
			# Default case, nothing to do.
			;;
		leds-mlxreg.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			led_path="$hw_management_path"/lc"$linecard_num"/led
			;;
		esac
		name=$(echo "$5" | cut -d':' -f2)
		color=$(echo "$5" | cut -d':' -f3)
		unlink $led_path/led_"$name"_"$color"
		unlink $led_path/led_"$name"_"$color"_delay_on
		unlink $led_path/led_"$name"_"$color"_delay_off
		unlink $led_path/led_"$name"_state
	fi
	if [ -f $led_path/led_"$name" ]; then
		rm -f $led_path/led_"$name"
	fi
	if [ -f $led_path/led_"$name"_capability ]; then
		rm -f $led_path/led_"$name"_capability
	fi
	if [ "$2" == "regio" ]; then
		# Detect if it belongs to line card or to main board.
		# For main board dirname mlxreg-io, for line card - mlxreg-io.{bus_num}.
		driver_dir=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs basename)
		case "$driver_dir" in
		mlxreg-io)
			# Default case, nothing to do.
			;;
		mlxreg-io.*)
			# Line card event, replace output folder.
			input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
			find_linecard_num "$input_bus_num"
			system_path="$hw_management_path"/lc"$linecard_num"/system
			;;
		esac
		if [ -d $system_path ]; then
			for attrname in $system_path/*; do
				attrname=$(basename "${attrname}")
				if [ -L $system_path/"$attrname" ]; then
					unlink $system_path/"$attrname"
				fi
			done
		fi
	fi
	if [ "$2" == "eeprom" ]; then
		# Detect if it belongs to line card or to main board.
		input_bus_num=$(echo "$3""$4" | xargs dirname | xargs dirname | xargs basename | cut -d"-" -f2)
		driver_dir=$(echo "$3""$4" | xargs dirname | xargs dirname)/"$input_bus_num"-00"$mlxreg_lc_addr"
		if [ -d "$driver_dir" ]; then
			driver_name=$(< "$driver_dir"/name)
			if [ "$driver_name" == "mlxreg-lc" ]; then
				# Linecard event, replace output folder.
				find_linecard_num "$input_bus_num"
				eeprom_path="$hw_management_path"/lc"$linecard_num"/eeprom
			fi
		fi
		busdir="$3""$4"
		busfolder=$(basename "$busdir")
		bus="${busfolder:0:${#busfolder}-5}"
		find_i2c_bus
		bus=$((bus-i2c_bus_offset))
		addr="0x${busfolder: -2}"
		find_eeprom_name "$bus" "$addr"
		unlink $eeprom_path/$eeprom_name
	fi
	if [ "$2" == "cpld" ]; then
		asic_cpld_remove_handler
	fi
	if [ "$2" == "watchdog" ]; then
	wd_type=$(< "$3""$4"/identity)
		case $wd_type in
			mlx-wdt-*)
				find $watchdog_path/ -name "$wd_type""*" -type l -exec unlink {} \;
				;;
			*)
				;;
		esac
	fi
	if [ "$2" == "sfp" ]; then
		lock_service_state_change
		[ -f "$config_path/sfp_counter" ] && sfp_counter=$(< $config_path/sfp_counter)
		if [ "$sfp_counter" -gt 0 ]; then
			sfp_counter=$((sfp_counter-1))
			echo $sfp_counter > $config_path/sfp_counter
		fi
		unlock_service_state_change
		rm -rf ${sfp_path}/*_status
	fi
	# Clear lc folders upon line card udev rm event.
	if [ "$2" == "linecard" ]; then
		input_bus_num=$(echo "$3""$4" | xargs dirname| xargs dirname| xargs dirname| xargs basename | cut -d"-" -f1)
		find_linecard_num "$input_bus_num"
		# Clean line card folders.
		if [ -d "$hw_management_path"/lc"$linecard_num" ]; then
			find "$hw_management_path"/lc"$linecard_num" -type l -exec unlink {} \;
			rm -rf "$hw_management_path"/lc"$linecard_num"
		fi
	fi
fi
