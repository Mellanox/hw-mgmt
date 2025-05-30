#!/bin/bash
##################################################################################
# Copyright (c) 2021 - 2024, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
watchdog_path=$hw_management_path/watchdog
config_path=$hw_management_path/config
events_path=$hw_management_path/events
thermal_path=$hw_management_path/thermal
jtag_path=$hw_management_path/jtag
power_path=$hw_management_path/power
fw_path=$hw_management_path/firmware
bin_path=$hw_management_path/bin
dynamic_boards_path=$config_path/dynamic_boards
udev_ready=$hw_management_path/.udev_ready
LOCKFILE="/var/run/hw-management-chassis.lock"
if [ -d /sys/devices/virtual/dmi/id ]; then
	board_type_file=/sys/devices/virtual/dmi/id/board_name
	sku_file=/sys/devices/virtual/dmi/id/product_sku
	system_ver_file=/sys/devices/virtual/dmi/id/product_version
else
	board_type_file=/var/run/hw-management/config/pn
	sku_file=/var/run/hw-management/config/hid
	system_ver_file=/var/run/hw-management/config/bom
fi
pn_file=/sys/devices/virtual/dmi/id/product_name
devtree_file=$config_path/devtree
dpu2host_events_file=$config_path/dpu_to_host_events
dpu_events_file=$config_path/dpu_events
power_events_file=$config_path/power_events
i2c_bus_def_off_eeprom_cpu_file=$config_path/i2c_bus_def_off_eeprom_cpu
i2c_comex_mon_bus_default_file=$config_path/i2c_comex_mon_bus_default
l1_switch_health_events=("intrusion" "pwm_pg" "thermal1_pdb" "thermal2_pdb")
smart_switch_dpu2host_events=("dpu1_ready" "dpu2_ready" "dpu3_ready" "dpu4_ready" \
			      "dpu1_shtdn_ready" "dpu2_shtdn_ready" \
			      "dpu3_shtdn_ready" "dpu4_shtdn_ready")
smart_switch_dpu_events=("pg_1v8" "pg_dvdd" "pg_vdd pg_vddio" "thermal_trip" \
			 "ufm_upgrade_done" "vdd_cpu_hot_alert" "vddq_hot_alert" \
			 "pg_comparator" "pg_hvdd pg_vdd_cpu" "pg_vddq" \
			 "vdd_cpu_alert" "vddq_alert")
l1_power_events=("power_button graceful_pwr_off")
ui_tree_sku=`cat $sku_file`
ui_tree_archive=
udev_event_log="/var/log/udev_events.log"
vm_sku=`cat $sku_file`
vm_vpd_path="/etc/hw-management-virtual/$vm_sku"
cpldreg_log_file=/var/log/hw-mgmt-cpldreg.log

declare -A psu_fandir_vs_pn=(["00KX1W"]=R ["00MP582"]=F ["00MP592"]=R ["00WT061"]=F \
["00WT062"]=R ["00WT199"]=F ["01FT674"]=F ["01FT691"]=F ["01LL976"]=F \
["01PG798"]=F ["01PG800"]=R ["02YF120"]=R ["02YF121"]=F ["03GX980"]=F \
["03GX981"]=R ["03KH192"]=F ["03KH193"]=R ["03KH194"]=F ["03KH195"]=R \
["03LE223"]=F ["03LE224"]=R ["071-000-203-01"]=F ["071-000-588"]=F ["07XY0Y"]=F \
["08WP7W"]=F ["0YX5GR"]=R ["105-575-071-00"]=F ["105-575-072-00"]=F \
["105-575-074-00"]=F ["304643"]=R ["322285"]=R ["326013"]=R ["326146"]=R \
["326329"]=R ["675170-001"]=F ["675171-001"]=R ["841985-001"]=F \
["841986-001"]=R ["90Y3770"]=F ["90Y3780"]=R ["90Y3800"]=F ["90Y3802"]=R \
["930-9SPSU-00RA-00A"]=R ["930-9SPSU-00RA-00B"]=R ["9802A00E"]=R \
["98Y6356"]=F ["98Y6357"]=F ["MGA100-PS"]=F ["MSX60-PF"]=F ["MSX60-PR"]=R \
["MTDF-PS-A"]=F ["MTDF-PS-B"]=F ["MUA90-PF"]=F ["MUA96-PF"]=R ["P10613-001"]=F \
["PSU-AC-150-B"]=F ["PSU-AC-150-F"]=R ["PSU-AC-150W-B"]=F ["PSU-AC-150W-F"]=R \
["PSU-AC-400-B"]=F ["PSU-AC-400-F"]=R ["PSU-AC-650A-B"]=F ["PSU-AC-650A-F"]=R \
["PSU-AC-850A-B"]=F ["PSU-AC-850A-F"]=R ["PSU-AC-920-F"]=R ["PSU-AC-920W-F"]=R \
["YM-1151D-A02R"]=F ["YM-1151D-A03R"]=R ["YM-1921A-A01R"]=R ["SP57B0808724"]=R \
["675172-001"]=F ["675173-001"]=R ["687089-001"]=F ["687090-001"]=F \
["687091-001"]=F ["688790-001"]=F ["688791-001"]=F ["841987-001"]=F \
["841988-001"]=R ["P10612-001"]=F ["P10613-001"]=F \
["00MP581"]=F ["00MP583"]=F ["00MP591"]=R ["00MP593"]=R ["SP57A44110"]=F \
["SF17A44112"]=F ["SP57A44111"]=R ["SF17A44113"]=R ["SP57A80805"]=R \
["SP57A80806"]=F ["SF17B06515"]=F ["SF17B06516"]=R ["SP57B06517"]=F \
["SP57B06518"]=R ["SF17B08721"]=R ["SF17B08722"]=F ["SP57B08723"]=F \
["SP57B08724"]=R ["SP57B08725"]=F ["SP57B08726"]=R ["SF17B27987"]=F \
["SF17B27988"]=R ["SP57B42423"]=F ["SP57B42424"]=R ["90Y3769"]=F ["90Y3771"]=F \
["90Y3779"]=R ["90Y3781"]=R ["90Y3779"]=R ["SA001871"]=F ["00WT021"]=F \
["105-575-014-00"]=F )

declare -A psu_type_vs_eeprom=( ["FSP016-9G0G"]="24c02" ["FSP017-9G0G"]="24c02" )

declare -A sys_fandir_vs_pn=(["00MP584"]=F ["00MP594"]=R ["00MP593"]=R \
["841987-001"]=F ["841988-001"]=R  )

base_cpu_bus_offset=10
max_tachos=20
i2c_asic_bus_default=2
i2c_asic2_bus_default=3
i2c_bus_min=1
i2c_bus_max=26
bmc_i2c_bus_max=9
bmc_i2c_bus_offset=70
cpu_type=
device_connect_delay=0.2

# CPU Family + CPU Model should idintify exact CPU architecture
# IVB - Ivy-Bridge
# RNG - Atom Rangeley
# BDW - Broadwell-DE
# CFL - Coffee Lake
# DNV - Denverton
# BF3 - BlueField-3
# AMD_SNW - AMD Snow Owl - EPYC Embedded 3000
# ARMv7 - Aspeed 2600
IVB_CPU=0x63A
RNG_CPU=0x64D
BDW_CPU=0x656
CFL_CPU=0x69E
DNV_CPU=0x65F
BF3_CPU=0xD42
AMD_SNW_CPU=0x171
ARMv7_CPU=0xC07
amd_snw_i2c_sodimm_dev=/sys/devices/platform/AMDI0010:02
n5110_mctp_bus="0"
n5110_mctp_addr="1040"

# hw-mngmt-sysfs-monitor GLOBALS
SYSFS_MONITOR_TIMEOUT=20 # Total Sysfs T/O.
SYSFS_MONITOR_DELAY=1 # Internal delay for Sysfs monitor loop to free CPU.
SYSFS_MONITOR_RDY_FILE=$hw_management_path/sysfs_labels_rdy
SYSFS_MONITOR_RESET_FILE_A="/tmp/sysfs_monitor_time_a"
SYSFS_MONITOR_RESET_FILE_B="/tmp/sysfs_monitor_time_b"
SYSFS_MONITOR_PID_FILE="/tmp/sysfs_monitor.pid"

# hw-mngmt-fast-sysfs-monitor GLOBALS
FAST_SYSFS_MONITOR_INTERVAL=1  # 1 seconds
FAST_SYSFS_MONITOR_TIMEOUT=300   # 5 minutes
FAST_SYSFS_MONITOR_LABELS_JSON="/etc/hw-management-fast-sysfs-monitor/fast_sysfs_labels.json"
FAST_SYSFS_MONITOR_PID_FILE="/tmp/fast_sysfs_monitor.pid"
FAST_SYSFS_MONITOR_RDY_FILE=$hw_management_path/fast_sysfs_labels_rdy

log_err()
{
    logger -t hw-management -p daemon.err "$@"
}

log_info()
{
    logger -t hw-management -p daemon.info "$@"
}

trace_udev_events()
{
	echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] $@" >> $udev_event_log
	return 0
}

show_hw_info()
{
	arch=$(uname -m)
	if [ "$arch" = "aarch64" ]; then
		CPLD_IOREG_RANGE=512
	else
		CPLD_IOREG_RANGE=256
	fi

	io_dump=$(iorw -b 0x2500 -r -l  $CPLD_IOREG_RANGE | expand)
	log_info "== cpld reg dump start =="
    echo "$io_dump" | logger
	log_info "== cpld reg dump end =="
		
	# Append the new cpldreg dump entry
 	timestamp=$(date +"%d_%m_%y %H:%M:%S")
	echo "====== $timestamp cpldreg dump ======" >> "$cpldreg_log_file"
	echo "$io_dump" >> "$cpldreg_log_file"
	echo "================================" >> "$cpldreg_log_file"
	echo "" >> "$cpldreg_log_file"

	N_REC=100
	dump_max_lines=$(($N_REC * ($CPLD_IOREG_RANGE / 16 + 4)))
	tail -n $dump_max_lines "$cpldreg_log_file" > "${cpldreg_log_file}.tmp" && mv "${cpldreg_log_file}.tmp" "$cpldreg_log_file"
}

check_cpu_type()
{
	if [ ! -f $config_path/cpu_type ]; then
		# ARM CPU provide "CPU part" field, x86 does not. Check for ARM first.
		cpu_pn=$(grep -m1 "CPU part" /proc/cpuinfo | awk '{print $4}')
		cpu_pn=`echo $cpu_pn | cut -c 3- | tr a-z A-Z`
		cpu_pn=0x$cpu_pn
		if [ "$cpu_pn" == "$BF3_CPU" ] || [ "$cpu_pn" == "$ARMv7_CPU" ]; then
			cpu_type=$cpu_pn
			echo $cpu_type > $config_path/cpu_type
			return 0
		fi

		family_num=$(grep -m1 "cpu family" /proc/cpuinfo | awk '{print $4}')
		model_num=$(grep -m1 model /proc/cpuinfo | awk '{print $3}')
		cpu_type=$(printf "0x%X%X" "$family_num" "$model_num")
		echo $cpu_type > $config_path/cpu_type
	else
		cpu_type=$(cat $config_path/cpu_type)
	fi
}

find_i2c_bus()
{
    # Find physical bus number of Mellanox I2C controller. The default
    # number is 1, but it could be assigned to others id numbers on
    # systems with different CPU types.
    if [ -f $config_path/i2c_bus_offset ]; then
        i2c_bus_offset=$(< $config_path/i2c_bus_offset)
        return
    fi

	case "$ui_tree_sku" in
	VMOD0021)
		bus_min=$bmc_i2c_bus_min
		bus_max=$bmc_i2c_bus_max
		;;
	*)
		bus_min=$i2c_bus_min
		bus_max=$i2c_bus_max
		;;
	esac

    for ((i="$bus_min"; i<"$bus_max"; i++)); do
        folder=/sys/bus/i2c/devices/i2c-$i
        if [ -d $folder ]; then
            name=$(cut $folder/name -d' ' -f 1)
            if [ "$name" == "i2c-mlxcpld" ]; then
                i2c_bus_offset=$((i-1))
                case $sku in
                    HI151|HI156)
                        i2c_bus_offset=$((i2c_bus_offset-1))
                    ;;
                    default)
                    ;;
                esac

                echo $i2c_bus_offset > $config_path/i2c_bus_offset
                return
            fi
        fi
    done

    log_err "I2C infrastructure is not created"
    exit 0
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

check_labels_enabled()
{
    ui_tree_archive_file="$(get_ui_tree_archive_file)"
    if ([ "$ui_tree_sku" = "HI130" ] ||
        [ "$ui_tree_sku" = "HI151" ] ||
        [ "$ui_tree_sku" = "HI157" ] ||
        [ "$ui_tree_sku" = "HI158" ] ||
        [ "$ui_tree_sku" = "HI162" ] ||
        [ "$ui_tree_sku" = "HI166" ] ||
        [ "$ui_tree_sku" = "HI167" ] ||
        [ "$ui_tree_sku" = "HI169" ] ||
        [ "$ui_tree_sku" = "HI170" ] || 
        [ "$ui_tree_sku" = "HI173" ] ||
        [ "$ui_tree_sku" = "HI174" ] ||
        [ "$ui_tree_sku" = "HI175" ] ||
        [ "$ui_tree_sku" = "HI176" ] ||
        [ "$ui_tree_sku" = "HI177" ] ||
        [ "$ui_tree_sku" = "HI178" ]) &&
        ([ ! -e "$ui_tree_archive_file" ]); then
        return 0
    else
        return 1
    fi
}

# This function checks if the platform is having BSP emulation support.
check_if_simx_supported_platform()
{
	case $vm_sku in
		HI130|HI122|HI144|HI147|HI157|HI112|MSN2700-CS2FO|MSN2410-CB2F|MSN2100|HI160|HI158|HI166|HI171|HI172|HI173|HI174|HI176)
			return 0
			;;

		*)
			return 1
			;;
	esac
}

# It also checks if the environment is SimX.
check_simx()
{
	if [ -n "$(lspci -vvv | grep SimX)" ]; then
		return 0
	else
		return 1
	fi
}

# This function checks if ThermalControl supports current platform
# Returns 1 if TC is supported, 0 otherwise.
check_tc_is_supported()
{
	if grep -q '"platform_support" : 0' $config_path/tc_config.json; then
		return 1
	else
		return 0
	fi
}

# This function create or cleans sysfs monitor helper files.
init_sysfs_monitor_timestamp_files()
{
    SYSFS_MONITOR_FILES=(
        "$SYSFS_MONITOR_RESET_FILE_A"
        "$SYSFS_MONITOR_RESET_FILE_B"
    )

    # Remove all sysfs monitor files if they exist from previous runs.
    # They might contain garbage. Then create new ones.
    for FILE in "${SYSFS_MONITOR_FILES[@]}"; do
        [ -f "$FILE" ] && rm "$FILE"
        touch "$FILE"
    done

    # remove the sysfs ready file if it exists.
    if [[ -f "$SYSFS_MONITOR_RDY_FILE" ]]; then
        rm "$SYSFS_MONITOR_RDY_FILE"
    fi

    # remove the fast sysfs ready file if it exists.
    if [[ -f "$FAST_SYSFS_MONITOR_RDY_FILE" ]]; then
        rm "$FAST_SYSFS_MONITOR_RDY_FILE"
    fi

    file_exist=true
    for FILE in "${SYSFS_MONITOR_FILES[@]}"; do
        [ ! -f "$FILE" ]
        file_exist=false
        break
    done
    # In case one of the Sysfs monitor files was not created, 
    # or in case the first run file was not removed,
    # exit with error.
    if [ ! "$file_exist" ] ;then
        log_info "Error init. Sysfs Monitor files."
        exit 1
    fi

    log_info "Successfully init. Sysfs Monitor files."
}

# This function writes the current timestamp to the relevant file.
# Used by both hw-management service and sysfs monitor service.
refresh_sysfs_monitor_timestamps()
{
    # Capture the current time with milliseconds.
    local current_time=$(awk '{print int($1 * 1000)}' /proc/uptime)
    # Read the last update time from both reset files.
    local last_reset_time_A=$(cat "$SYSFS_MONITOR_RESET_FILE_A" 2>/dev/null || echo 0)
    local last_reset_time_B=$(cat "$SYSFS_MONITOR_RESET_FILE_B" 2>/dev/null || echo 0)
    # Ensure both variables are valid integers, defaulting to 0 if empty or invalid.
    last_reset_time_A=${last_reset_time_A:-0}
    last_reset_time_B=${last_reset_time_B:-0}
    # Determine which file was written most recently.
    if [ "$last_reset_time_A" -gt "$last_reset_time_B" ]; then
        # Write the current time to the less recently updated file (B).
        echo "$current_time" > "$SYSFS_MONITOR_RESET_FILE_B"
    else
        # Write the current time to the less recently updated file (A).
        echo "$current_time" > "$SYSFS_MONITOR_RESET_FILE_A"
    fi
}

# Create the missed out links due to lack of emulation
process_simx_links()
{
	local dir_list

	# Create the attributes in thermal and environment directories of hw-management.
        dir_list="thermal environment"
        for i in $dir_list; do
                while IFS=' ' read -r filename value; do
                        [ -z "$filename" ] && continue
                        [ -L "$hw_management_path"/"$i"/"$filename" ] && check_n_unlink "$hw_management_path"/"$i"/"$filename"
                        echo "$value" > "$hw_management_path"/"$i"/"$filename"
                done < "$vm_vpd_path"/"$i"
        done
}

# Check if file exists and create soft link
# $1 - file path
# $2 - link path
# return none
check_n_link()
{
    refresh_sysfs_monitor_timestamps
    if [ -f "$1" ];
    then
        ln -sf "$1" "$2"
        if  check_labels_enabled; then
            hw-management-labels-maker.sh "$2" "link" > /dev/null 2>&1 &
        fi
    fi
}

# Check if link exists and unlink it
# $1 - link path
# return none
check_n_unlink()
{
    if [ -L "$1" ];
    then
        unlink "$1"
        if check_labels_enabled; then
	    hw-management-labels-maker.sh "$1" "unlink" > /dev/null 2>&1 &
        fi
    fi
}

# Check if file not exists and create it
# $1 - file path
# $2 - default value
# return none
check_n_init()
{
	if [ ! -f $1 ]; then
		echo $2 > $1
	fi
}

# Read int val from file, inc it by val and save back
# value can negative
# $1 - counter file name
# $2 - value to add (can be < 0)
change_file_counter()
{
	file_name=$1
	val=$2
	[ -f "$file_name" ] && counter=$(< $file_name)
	counter=$((counter+val))
	if [ $counter -lt 0 ]; then
		counter=0
	fi
	echo $counter > $file_name
}

# Update counter, match attribute, unlock.
# $1 - file with counter
# $2 - value to update counter ( 1 increase, -1 decrease)
# $3 - file to match with the counter
# $4 - file to set according to the match ( 0 not matched, 1 matched)
unlock_service_state_change_update_and_match()
{
	update_file_name=$1
	val=$2
	match_file_name=$3
	set_file_name=$4
	local counter
	local match

	change_file_counter "$update_file_name" "$val"
	if [ ! -z "$3" ] && [ ! -z "$4" ]; then
		counter=$(< $update_file_name)
		match=$(< $match_file_name)
		if [ $counter -eq $match ]; then
			echo 1 > $set_file_name
		else
			echo 0 > $set_file_name
		fi
	fi
	/usr/bin/flock -u ${LOCKFD}
}

connect_device()
{
	find_i2c_bus
	addr=$(echo "$2" | tail -c +3)
	bus=$(($3+i2c_bus_offset))
	if [ -f /sys/bus/i2c/devices/i2c-"$bus"/new_device ]; then
		if [ ! -d /sys/bus/i2c/devices/$bus-00"$addr" ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" "$2" > /sys/bus/i2c/devices/i2c-$bus/new_device
			sleep ${device_connect_delay}
			if [ ! -L /sys/bus/i2c/devices/$bus-00"$addr"/driver ] &&
			   [ ! -L /sys/bus/i2c/devices/$bus-000"$addr"/driver ]; then
				return 1
			fi
		fi
	fi

	return 0
}

disconnect_device()
{
	find_i2c_bus
	addr=$(echo "$1" | tail -c +3)
	bus=$(($2+i2c_bus_offset))
	if [ -f /sys/bus/i2c/devices/i2c-"$bus"/delete_device ]; then
		
		if [ -d /sys/bus/i2c/devices/$bus-00"$addr" ] ||
		   [ -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$1" > /sys/bus/i2c/devices/i2c-$bus/delete_device
			return $?
		fi
	fi

	return 0
}

# Common retry helper function.
# Input:
# - $1 - user function to execute.
# - $2 - retry timeout delay window.
# - $3 - retry counter.
# - $4 - user log to be produced if user function failed (optional).
# - $5 - user parameter to execute.
# Output:
# - return code (0 - success; 1 - failure).
# Example:
# retry_helper find_regio_sysfs_path_helper 0.5 10 "mlxreg_io is not loaded"
function retry_helper()
{
	local user_func="$1"
	local retry_to="$2"
	local retry_cnt="$3"
	local user_log="$4"
	local user_param="$5"

	for ((i=0; i<${retry_cnt}; i+=1)); do
		$user_func $user_param
		if [ $? -eq 0 ]; then
			return 0
		fi
		sleep "$retry_to"
	done

	if [ ! -z "$$user_log" ]; then
		log_err "$user_log"
	fi

	return 1
}

# Set PSU fan speed
# Input:
# - $1 - psu name
# - $2 - psu speed
# Output:
# - none
psu_set_fan_speed()
{
	local addr=$(< $config_path/"$1"_i2c_addr)
	local bus=$(< $config_path/"$1"_i2c_bus)
	local fan_config_command=$(< $config_path/fan_config_command)
	local fan_speed_units=$(< $config_path/fan_speed_units)
	local fan_command=$(< $config_path/fan_command)
	local speed=$2

	# Set fan speed units (percentage or RPM)
	i2cset -f -y "$bus" "$addr" "$fan_config_command" "$fan_speed_units" bp

	# Set fan speed
	i2cset -f -y "$bus" "$addr" "$fan_command" "${speed}" wp
}

is_virtual_machine()
{
    if [ -n "$(lspci -vvv | grep SimX)" ]; then
        return 0
    else
        return 1
    fi
}

# Handle i2c bus add/remove.
# If we have some devices which should be connected to this bus - do it.
# $1 - i2c bus full address.
# $2 - i2c bus action type add/remove.
function handle_i2cbus_dev_action()
{
	i2c_busdev_path=$1
	i2c_busdev_action=$2

	# Check if we have devices list which should be connected to dynamic i2c buses.
	if [ ! -f $config_path/i2c_bus_connect_devices ];
	then
		return
	fi

	# Extract i2c bus index.
	i2cbus_regex="i2c-([0-9]+)$"
	[[ $i2c_busdev_path =~ $i2cbus_regex ]]
	if [[ "${#BASH_REMATCH[@]}" != 2 ]]; then
		return
	else
		i2cbus="${BASH_REMATCH[1]}"
	fi

	# Load i2c devices list which should be connected on demand..
	declare -a dynamic_i2c_bus_connect_table="($(< $config_path/i2c_bus_connect_devices))"

	# wait till i2c driver fully init
	sleep 20
	# Go over all devices and check if they should be connected to the current i2c bus.
	for ((i=0; i<${#dynamic_i2c_bus_connect_table[@]}; i+=4)); do
		if [ $i2cbus == "${dynamic_i2c_bus_connect_table[i+2]}" ];
		then
			if [ "$i2c_busdev_action" == "add" ]; then
				connect_device "${dynamic_i2c_bus_connect_table[i]}" "${dynamic_i2c_bus_connect_table[i+1]}" \
					"${dynamic_i2c_bus_connect_table[i+2]}"
			elif [ "$i2c_busdev_action" == "remove" ]; then
				diconnect_device "${dynamic_i2c_bus_connect_table[i]}" "${dynamic_i2c_bus_connect_table[i+1]}" \
					"${dynamic_i2c_bus_connect_table[i+2]}"
			fi
		fi
	done
}

# Get device sensor name prefix, like voltmon{id}, by its i2c_busdev_path
# For name {devname}X returning name based on $config_path/i2c_bus_connect_devices file.
# For other names - just return voltmon{id} string.
# $1 - device name
# $2 - path to sensor in sysfs
# return sensor name if match is found or undefined in other case.
function get_i2c_busdev_name()
{
	dev_name=$1
	i2c_busdev_path=$2

	# Check if we have devices list which can be connected with name translation.
	if [  -f $config_path/i2c_bus_connect_devices ] || [ -f "$devtree_file" ];
	then
		# Load i2c devices list which should be connected on demand.
		if [ -f "$devtree_file" ]; then
			declare -a dynamic_i2c_bus_connect_table=($(<"$devtree_file"))
		else
			declare -a dynamic_i2c_bus_connect_table="($(< $config_path/i2c_bus_connect_devices))"
		fi

		# extract i2c bud/dev addr from device sysfs path ( match for i2c-bus/{bus}-{addr} )
		i2caddr_regex="i2c-[0-9]+/([0-9]+)-00([a-zA-Z0-9]+)/"
		[[ $i2c_busdev_path =~ $i2caddr_regex ]]
		if [ "${#BASH_REMATCH[@]}" != 3 ]; then
			# not matched
			echo "$dev_name"
			return
		else
			i2cbus="${BASH_REMATCH[1]}"
			i2caddr="0x${BASH_REMATCH[2]}"
			find_i2c_bus
			i2cbus=$(($i2cbus-$i2c_bus_offset))
		fi

		for ((i=0; i<${#dynamic_i2c_bus_connect_table[@]}; i+=4)); do
			# match devi ce by i2c bus/addr
			if [ $i2cbus == "${dynamic_i2c_bus_connect_table[i+2]}" ] && [ $i2caddr == "${dynamic_i2c_bus_connect_table[i+1]}" ];
			then
				dev_name="${dynamic_i2c_bus_connect_table[i+3]}"
				if [ $dev_name == "NA" ]; then 
					echo "undefined"
				else
					echo "$dev_name"
				fi
				return
			fi
		done
	fi

	# we not matched i2c device with dev_list file or file not exist
	# returning passed "devname" name or "undefined" in case if passed '{devtype}X"
	if [ ${dev_name:0-1} == "X" ];
	then
		dev_name="undefined"
	fi

	echo "$dev_name"
}

find_dpu_slot_from_i2c_bus()
{
    local input_bus_num=$1
    local slot_num=""
    local dpu_bus_off=$(<$config_path/dpu_bus_off)
    local dpu_num=$(<$config_path/dpu_num)
    local i2c_bus_offset=$(<$config_path/i2c_bus_offset)

    if [ $input_bus_num -lt $dpu_bus_off ] ||
       [ $input_bus_num -gt $((dpu_bus_off+dpu_num+1)) ]; then
        slot_num=""
    else
        slot_num=$((input_bus_num-dpu_bus_off+i2c_bus_offset+1))
    fi

    echo "$slot_num"
}

find_dpu_slot()
{
	local path="$1"
	i2c_bus_offset=$(<$config_path/i2c_bus_offset)
	dpu_bus_off=$(<$config_path/dpu_bus_off)
	input_bus_num=$(echo "$path" | xargs dirname | xargs basename | cut -d"-" -f2)
	slot_num=$((input_bus_num-dpu_bus_off+i2c_bus_offset+1))
	echo "$slot_num"
}

find_dpu_hotplug_slot()
{
	local path="$1"

	slot_num=$(echo "$path" | xargs dirname | xargs dirname | xargs basename | cut -d"." -f2)
	echo "$slot_num"
}

create_hotplug_smart_switch_event_files()
{
	local dpu2host_event_file="$1"
	local dpu_event_file="$2"

	declare -a dpu2host_event_table="($(< $dpu2host_event_file))"
	declare -a dpu_event_table="($(< $dpu_event_file))"

	dpu_num=($(< $config_path/dpu_num))

	for i in ${!dpu2host_event_table[@]}; do
		check_n_init "$events_path/${dpu2host_event_table[$i]}" 0
	done

	dpu_num=$(<"$config_path"/dpu_num)
	for ((i=1; i<=dpu_num; i+=1)); do
		if [ ! -d "$hw_management_path/dpu"$i"/events" ]; then
			mkdir "$hw_management_path/dpu"$i"/events"
		fi
		for j in ${!dpu_event_table[@]}; do
			if [ ! -f $hw_management_path/dpu"$i"/events/${dpu_event_table[$j]} ]; then
				check_n_init $hw_management_path/dpu"$i"/events/${dpu_event_table[$j]} 0
			fi
		done
	done
}

init_hotplug_events()
{
	local event_file="$1"
	local path="$2"
	local slot_num="$3"
	local e_path
	local s_path
	local i2c_bus
	local plat_drv_path="/sys/devices/platform/mlxplat/i2c_mlxcpld.1/i2c-1"
	local hwmon_path="mlxreg-hotplug.$slot_num/hwmon/hwmon*"

	declare -a event_table="($(< $event_file))"

	if [ $slot_num -ne 0 ]; then
		# The events are for dpu hotplug attributes
		e_path="$hw_management_path/dpu$slot_num/events"
		s_path="$hw_management_path/dpu$slot_num/system"
		i2c_bus=$(($(< $config_path/dpu_bus_off)+$slot_num-1))
		path="$plat_drv_path/i2c-$i2c_bus/$i2c_bus-0068/$hwmon_path"
	else
		# The events are for dpu ready/shutdown attributes
		e_path="$events_path"
		s_path="$system_path"
	fi

	for i in ${!event_table[@]}; do
		if [ -f $path/${event_table[$i]} ]; then
			if [ $slot_num -eq 0 ]; then
				check_n_link "$path"/${event_table[$i]} "$s_path"/${event_table[$i]}
			fi
			event=$(< $path/${event_table[$i]})
			echo $event > $e_path/${event_table[$i]}
		fi
	done
}

deinit_hotplug_events()
{
	local event_file="$1"
	local slot_num="$2"
	local s_path

	declare -a event_table="($(< $event_file))"

	if [ $slot_num -ne 0 ]; then
		s_path=$system_path
	else
		s_path="$hw_management_path/dpu$slot_num/system_path"
	fi

	for i in ${!event_table[@]}; do
		check_n_unlink "$s_path"/${event_table[$i]}
	done
}

connect_underlying_devices()
{
	local bus="$1"

	if [ ! -f $config_path/i2c_underlying_devices ]; then
		return
	fi

	declare -a card_connect_table="($(< $config_path/i2c_underlying_devices))"

	for ((i=0; i<${#card_connect_table[@]}; i+=4)); do
		addr="${card_connect_table[i+2]}"
		if [ ! -d /sys/bus/i2c/devices/$bus-00"$addr" ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "${card_connect_table[i]}" "$addr" > /sys/bus/i2c/devices/i2c-$bus/new_device
		fi
	done
}

disconnect_underlying_devices()
{
	local bus="$1"

	if [ ! -f $config_path/i2c_underlying_devices ]; then
		return
	fi

	declare -a card_connect_table="($(< $config_path/i2c_underlying_devices))"

	for ((i=0; i<${#card_connect_table[@]}; i+=4)); do
		addr="${card_connect_table[i+2]}"
		if [ -d /sys/bus/i2c/devices/$bus-00"$addr" ] &&
		   [ -d /sys/bus/i2c/devices/$bus-000"$addr" ]; then
			echo "$addr" > /sys/bus/i2c/devices/i2c-$bus/delete_device
		fi
	done
}

connect_dynamic_board_devices()
{
	local board_name="$1"
	local device_connect_retry=2

	if [ ! -f "$dynamic_boards_path"/"$board_name" ]; then
		return
	fi

	declare -a board_connect_table=($(<"$dynamic_boards_path"/"$board_name"))

	for ((i=0; i<${#board_connect_table[@]}; i+=4)); do
		for ((j=0; j<${device_connect_retry}; j++)); do
			connect_device "${board_connect_table[i]}" "${board_connect_table[i+1]}" \
					"${board_connect_table[i+2]}"
			if [ $? -eq 0 ]; then
				break;
			fi
			disconnect_device "${board_connect_table[i+1]}" "${board_connect_table[i+2]}"
		done
	done
}

disconnect_dynamic_board_devices()
{
	local board_name="$1"

	if [ ! -f "$dynamic_boards_path"/"$board_name" ]; then
		return
	fi

	declare -a board_connect_table=($(<"$dynamic_boards_path"/"$board_name"))

	for ((i=0; i<${#board_connect_table[@]}; i+=4)); do
		disconnect_device "${board_connect_table[i+1]}" "${board_connect_table[i+2]}"
	done
}

load_dpu_sensors()
{
	local dpu_num=$1
	local dpu_ready

	if [ -f $hw_management_path/system/dpu${dpu_num}_ready ]; then
		dpu_ready=$(< $hw_management_path/system/dpu${dpu_num}_ready)
		if [ ${dpu_ready} -eq 1 ]; then
			if [ -e "$devtree_file" ]; then
				connect_dynamic_board_devices "dpu_board""$dpu_num"
			fi
		fi
	fi
}

get_ui_tree_archive_file()
{
	if [ ! -z $ui_tree_archive ]; then
		echo $ui_tree_archive
	fi

	ui_tree_archive="/etc/hw-management-sensors/ui_tree_"$ui_tree_sku".tar.gz"

	[ -f "$board_type_file" ] && board_type=$(< $board_type_file) || board_type="Unknown"

	# Validate label archive file.
	case $ui_tree_sku in
	HI162|HI166|HI167|HI169|HI170|HI175)
		# Check if raa228000 converter present on expected i2c addr 12-0060
		# if 'yes' - we should use special ui file
		i2cdetect -y -a -r 12 0x60 0x60 | grep -q -- "--"
		if [ $? -eq 1 ]; then
			ui_tree_archive="/etc/hw-management-sensors/ui_tree_"$ui_tree_sku"_1.tar.gz"
		fi
		;;
	*)
		;;
	esac
	echo $ui_tree_archive
}
