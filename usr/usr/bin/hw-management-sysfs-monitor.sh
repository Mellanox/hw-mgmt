#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause
source hw-management-helpers.sh

log_info "hw-mngmt-sysfs-monitor started."

SYSFS_MONITOR_ACTION=$1

__usage="
Usage: $(basename "$0") [Options]

Options:
    start   Start hw-mngmt-sysfs-monitor.
    stop    Stop hw-mngmt-sysfs-monitor.
    restart
    force-reload    Performs hw-mngmt-sysfs-monitor 'stop' and the 'start.
"

do_start_sysfs_monitor()
{
    log_info "Starting hw-mngmt-sysfs-monitor logic."

    # Initialize timestamp to current time to avoid stale data
    local current_time
    current_time=$(awk '{print int($1 * 1000)}' /proc/uptime)
    echo "$current_time" > "$SYSFS_MONITOR_RESET_FILE_A"
    echo "$current_time" > "$SYSFS_MONITOR_RESET_FILE_B"

    # Clear the ready file in case this is a service restart
    [ -f "$SYSFS_MONITOR_RDY_FILE" ] && rm -f "$SYSFS_MONITOR_RDY_FILE"

    while true; do
        # Get the current time with milliseconds.
        current_time=$(awk '{print int($1 * 1000)}' /proc/uptime)
        # Read the last update time from both reset files.
        local last_reset_time_A=$(cat "$SYSFS_MONITOR_RESET_FILE_A" 2>/dev/null || echo 0)
        local last_reset_time_B=$(cat "$SYSFS_MONITOR_RESET_FILE_B" 2>/dev/null || echo 0)
        # Ensure both variables are valid integers, defaulting to 0 if empty or invalid.
        last_reset_time_A=${last_reset_time_A:-0}
        last_reset_time_B=${last_reset_time_B:-0}
        # Determine which file has the most recent reset time.
        if [ "$last_reset_time_A" -gt "$last_reset_time_B" ]; then
            last_reset_time="$last_reset_time_A"
        else
            last_reset_time="$last_reset_time_B"
        fi
        # Calculate the time difference in milliseconds.
        local time_diff=$((current_time - last_reset_time))
        # Check if the time difference exceeds the timeout in milliseconds.
        if [ "$time_diff" -ge $((SYSFS_MONITOR_TIMEOUT * 1000)) ]; then
            # Update syslog.
            log_info "current_time $current_time"
            log_info "last_reset_time $last_reset_time"
            log_info "sysfs monitor time diff = $time_diff"
            log_info "sysfs monitor done!"
            # Write the current time into the sysfs ready file.
            echo "$current_time" > "$SYSFS_MONITOR_RDY_FILE"
            # Generate debug dump of hw-mgmt tree
            find -L $hw_management_path -maxdepth 4 ! -name '*_info' ! -name '*_eeprom' \
               ! -name '*.sh' ! -name '*.py' ! -name 'led_*_state' -exec ls -la {} \; -exec cat {} \; > /var/log/hw-mgmt-val.log 2>/dev/null
            # Run post-init fixup hook
            run_fixup_script post

            # stop i2c bus trace recording (if running)
            stop_i2c_trace
            # Exit the sysfs monitor.
            exit 0
        fi
        # Sleep for the specified delay period in seconds.
        sleep "$SYSFS_MONITOR_DELAY"
    done
}

do_stop_sysfs_monitor()
{
    # stop i2c bus trace recording (if running)
    stop_i2c_trace
    # Remove older sysfs-monitor process if it exists.
    if [ -f "$SYSFS_MONITOR_PID_FILE" ]; then
        local MONITOR_PID
        MONITOR_PID=$(cat "$SYSFS_MONITOR_PID_FILE")
        if kill -0 "$MONITOR_PID" 2>/dev/null; then
            if kill "$MONITOR_PID"; then
                log_info "HW Management old sysfs monitor process killed succesfully."
                rm -f "$SYSFS_MONITOR_PID_FILE"
            else
                log_info "HW Management failed to kill old sysfs monitor process."
                exit 1
            fi
        else
            log_info "HW Management old sysfs monitor process $MONITOR_PID already dead, remove the pid file."
            rm -f "$SYSFS_MONITOR_PID_FILE"
        fi
    fi
}

case $SYSFS_MONITOR_ACTION in
    start)
        # Save the PID of the sysfs monitor process.
        echo $$ > "$SYSFS_MONITOR_PID_FILE"
        log_info "HW Management Sysfs Monitor process created."
        do_start_sysfs_monitor
    ;;
    stop)
        do_stop_sysfs_monitor
    ;;
    restart|force-reload)
        do_stop_sysfs_monitor
        sleep 5
        # Save the PID of the sysfs monitor process.
        echo $$ > "$SYSFS_MONITOR_PID_FILE"
        do_start_sysfs_monitor
    ;;
    *)
        echo "$__usage"
        exit 1
    ;;
esac
exit 0
