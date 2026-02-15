#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# hw-management-powerctrl: host and board power control via sysfs.
# Host state updates (when available) go through hw-management-dbus-if.sh.
# No dependency on phosphor/OpenBMC services or bmc-boot-complete.
################################################################################

RETRIES=20
PWR_ATTR_DIR=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-io/hwmon/hwmon*

set_host_powerstate_off()
{
    /usr/bin/hw-management-dbus-if.sh host_state_off 2>/dev/null || true
}

set_host_powerstate_on()
{
    /usr/bin/hw-management-dbus-if.sh host_state_on 2>/dev/null || true
}

set_requested_host_transition()
{
    /usr/bin/hw-management-dbus-if.sh requested_host_transition_on 2>/dev/null || true
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
    echo "Power On Host"
    echo 0 > ${PWR_ATTR_DIR}/pwr_down

    if [ -f ${PWR_ATTR_DIR}/pwr_button_halt ]; then
        echo 0 > ${PWR_ATTR_DIR}/pwr_button_halt
    fi

    echo 0 > ${PWR_ATTR_DIR}/bmc_to_cpu_ctrl
    echo "Setting CurrentHostState to On"
    set_host_powerstate_on
}

power_off()
{
    echo "Force Power Off Host"
    echo 1 > ${PWR_ATTR_DIR}/pwr_down

    echo 0 > ${PWR_ATTR_DIR}/uart_sel
    echo 1 > ${PWR_ATTR_DIR}/bmc_to_cpu_ctrl
    echo "Setting CurrentHostState to Off"
    set_host_powerstate_off
}

reset()
{
    echo 'Force Power Cycle Host'
    echo 1 > ${PWR_ATTR_DIR}/pwr_cycle
    set_host_powerstate_off
}

reset_board()
{
    reset_bypass_file="/var/reset_bypass"
    if [ -f "$reset_bypass_file" ]; then
        echo "Power Cycle Bypass Board"
    else
        echo 'Power Cycle Board'
    fi
    wait_for_cpu_shutdown
    echo 1 > ${PWR_ATTR_DIR}/aux_pwr_cycle
}

grace_off()
{
    grace_reset_bypass_file="/var/grace_reset_bypass"
    if [ -f "$grace_reset_bypass_file" ]; then
        echo "$grace_reset_bypass_file exists, removing and skipping graceful power off."
        rm -f "$grace_reset_bypass_file"
        set_requested_host_transition
        return
    fi

    echo 'Graceful Power Off Host'
    wait_for_cpu_shutdown
    echo 1 > ${PWR_ATTR_DIR}/pwr_down
    echo 0 > ${PWR_ATTR_DIR}/uart_sel
    set_host_powerstate_off
}

grace_reset()
{
    echo 'Graceful Power Cycle Host'
    wait_for_cpu_shutdown
    echo 1 > ${PWR_ATTR_DIR}/pwr_cycle
    set_host_powerstate_off
}

### MAIN ###
if [ $# -eq 0 ]; then
    echo "$0 <power_on|power_off|reset|reset_board|grace_off|grace_reset>"
    echo "    power_off:   immediate force host power off"
    echo "    power_on:    immediate host power on"
    echo "    reset:       immediate force host power cycle"
    echo "    reset_board: graceful host power off and board power cycle"
    echo "    grace_off:   graceful host power off"
    echo "    grace_reset: graceful host power cycle"
    exit 1
fi

echo "Host Power Control"
$*
