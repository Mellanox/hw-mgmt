#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Inherit system configuration.
source /usr/bin/hw-management-bmc-helpers.sh

RETRIES=20
PWR_ATTR_DIR=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*/

EEPROM_RUN_DIR=/var/run/hw-management/eeprom
THERMAL_RUN_DIR=/var/run/hw-management/thermal

udev_event_log="/var/log/udev_events.log"

trace_udev_events()
{
	printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S.%3N')" "$*" >> "$udev_event_log"
	return 0
}

wait_for_cpu_shutdown()
{
    echo 1 > ${PWR_ATTR_DIR}/graceful_power_off
    count=0
    while true; do
        sleep 1
        count=$((count+1))
        cpu_power_off_ready=$(< ${PWR_ATTR_DIR}/cpu_power_off_ready)
        if [ ${cpu_power_off_ready} -eq 1 ] || [ ${count} -eq ${RETRIES} ]; then
            break
        fi
    done
}

power_on()
{
    echo 0 > ${PWR_ATTR_DIR}/pwr_down
}

grace_off()
{
    wait_for_cpu_shutdown
    echo 1 > ${PWR_ATTR_DIR}/pwr_down
}

power_on_by_pwr_button()
{
    local power_delay
    local power_policy

    power_delay=$(get_power_restore_delay)

    if [ "$power_delay" == "0" ]; then
        echo "Power button pressed: No power_delay configured. Turning on host cpu" | systemd-cat -p info -t hwmgmt-events
    else
        # Check if the power policy is AlwaysOn and turn on host cpu
        # after the PowerDelaySeconds configured
        power_policy=$(check_power_restore_policy)
        if [ "$power_policy" == "1" ]; then
            echo "Power button pressed: Will turn on host cpu after $((power_delay / 1000000)) seconds" | systemd-cat -p info -t hwmgmt-events
            usleep $power_delay
        else
            # This case is for other power policies AlwaysOff and LastState
            # No need to wait in this case and turn host cpu on
            echo "Power button pressed: Overriding power policy. Turning on host cpu" | systemd-cat -p info -t hwmgmt-events
        fi
    fi

    echo 0 > ${PWR_ATTR_DIR}/pwr_button_halt
    echo 0 > ${PWR_ATTR_DIR}/pwr_down
    if [ "`systemctl is-active obmc-console-ssh@*.service`" != "active" ]; then
        echo 2 > ${PWR_ATTR_DIR}/uart_sel
    fi
#    set_host_powerstate_on
#    set_requested_host_transition_on
}

grace_off_by_pwr_button()
{
    wait_for_cpu_shutdown
    echo 1 > ${PWR_ATTR_DIR}/pwr_button_halt

#    if [ "`systemctl is-active obmc-console-ssh@*.service`" == "active" ]; then
#        systemctl stop obmc-console-ssh@*.service
#    fi
#    # Make sure SoL is off and getty is on so user can have access to BMC console
#    if [ "`systemctl is-active obmc-console@ttyS12.service`" == "active" ]; then
#        systemctl stop obmc-console@ttyS12.service
#        systemctl stop obmc-console-ssh.socket
#        systemctl start serial-getty@ttyS12.service
#    fi

    echo 0 > ${PWR_ATTR_DIR}/uart_sel
#    set_host_powerstate_off
#    set_requested_host_transition_off
}

###########################################################
#                Execution starts here                    #
###########################################################
ACTION=$1
EVENT=$2
STATUS=$3

# trace_udev_events "$0: ACTION=$1 $2 $3 $4 $5"

# Note: "POWER_BUTTON" "UID_PUSH_BUTTON" do not exist on this system.

case "${ACTION}" in

"hotplug-event")
	case "${EVENT}" in
	"CPU_RESET")
		log_event "CPU reset - going up"
		log_cpld_dump
		turn_off_host_reset_leds
		set_host_powerstate_on
		exit 0
		;;
	"APML_SMB_ALERT")
		# APML interface.
		exit 0
		;;
	"GRACEFUL_POWER_OFF_REQ")
		log_event "Request host for gracefull power off"
		exit 0
		;;
	"LEAKAGE_AGGR")
		case "${STATUS}" in
		0)
			log_event "Leakage detected"
			echo "Leakage detected" >> $udev_event_log
			;;
		1)
			log_event "Leakage cleared"
			echo "Leakage cleared" >> $udev_event_log
			;;
		*)
			log_event "Hotplug event $2 $3 $4 $5"
			;;
		esac
		exit 0
		;;
	*)
		# LEAKAGE<n>: per-A2D hwmon events (udev). n matches /var/run/hw-management/leakage/<n>/;
		# channel count is defined by a2d config, not here.
		if [[ "${EVENT}" =~ ^LEAKAGE[0-9]+$ ]]; then
			ts_ms=$(awk '{ printf "%.0f", $1 * 1000 }' /proc/uptime)
			/usr/bin/hw-management-bmc-leakage-handler.sh "${EVENT#LEAKAGE}" "$ts_ms" &
			exit 0
		fi
		log_event "ACTION=${ACTION} EVENT=${EVENT} STATUS=${STATUS}"
		exit 0
		;;
	esac
	;;
"add")
	case "${EVENT}" in
	"regio"|"hotplug")
		if [ ! -d $system_path ]; then
			mkdir -p $system_path
                fi
		if [ -d "$3""$4" ]; then
			for attrpath in "$3""$4"/*; do
				attrname=$(basename "${attrpath}")
				if [ ! -d "$attrpath" ] && [ ! -L "$attrpath" ] &&
				   [ "$attrname" != "uevent" ] && [ "$attrname" != "name" ]; then
					ln -sf "$3""$4"/"$attrname" $system_path/"$attrname"
				fi
			done
		fi
		;;
	"eeprom_system")
		mkdir -p "$EEPROM_RUN_DIR"
		check_n_link "$3/eeprom" "$EEPROM_RUN_DIR/eeprom_system"
		;;
	"eeprom_bmc")
		mkdir -p "$EEPROM_RUN_DIR"
		check_n_link "$3/eeprom" "$EEPROM_RUN_DIR/eeprom_bmc"
		;;
	"cpu_temp")
		mkdir -p "$THERMAL_RUN_DIR"
		check_n_link "$3/temp1_input" "$THERMAL_RUN_DIR/cpu_temp_input"
		check_n_link "$3/temp1_max" "$THERMAL_RUN_DIR/cpu_temp"
		check_n_link "$3/temp1_min" "$THERMAL_RUN_DIR/cpu_min"
		;;
	"bmc_temp")
		mkdir -p "$THERMAL_RUN_DIR"
		check_n_link "$3/temp1_input" "$THERMAL_RUN_DIR/bmc_temp_input"
		check_n_link "$3/temp1_max" "$THERMAL_RUN_DIR/bmc_temp"
		check_n_link "$3/temp1_min" "$THERMAL_RUN_DIR/bmc_min"
		;;
	*)
		;;
	esac
	;;
"rm")
	case "${EVENT}" in
	"regio")
		if [ -d $system_path ]; then
			for attrname in $system_path/*; do
				attrname=$(basename "${attrname}")
				if [ -L $system_path/"$attrname" ]; then
					unlink $system_path/"$attrname"
				fi
			done
		fi
		;;
	"eeprom_system")
		check_n_unlink "$EEPROM_RUN_DIR/eeprom_system"
		;;
	"eeprom_bmc")
		check_n_unlink "$EEPROM_RUN_DIR/eeprom_bmc"
		;;
	"cpu_temp")
		check_n_unlink "$THERMAL_RUN_DIR/cpu_temp_input"
		check_n_unlink "$THERMAL_RUN_DIR/cpu_temp"
		check_n_unlink "$THERMAL_RUN_DIR/cpu_min"
		;;
	"bmc_temp")
		check_n_unlink "$THERMAL_RUN_DIR/bmc_temp_input"
		check_n_unlink "$THERMAL_RUN_DIR/bmc_temp"
		check_n_unlink "$THERMAL_RUN_DIR/bmc_min"
		;;
	*)
		;;
	esac
	;;
*)
	log_event "ACTION=${ACTION} EVENT=${EVENT} STATUS=${STATUS}"
	;;
esac

