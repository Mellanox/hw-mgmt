#!/bin/bash
##################################################################################
# Copyright (c) 2020 - 2024, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
source hw-management-helpers.sh

log_info "hw-mngmt-sysfs-monitor started."

SYSFS_MONITOR_ACTION=$1

__usage="
Usage: $(basename "$0") [Options]

Options:
    start   Start hw-mngmt-sysfs-monitor.
	stop	Stop hw-mngmt-sysfs-monitor.
    restart
    force-reload	Performs hw-management 'stop' and the 'start.
"

do_start_sysfs_monitor()
{
    log_info "Starting hw-mngmt-sysfs-monitor logic."
    # Watchdog loop
    while true; do
        # Get the current time with milliseconds.
        current_time=$(date +%s%3N)
        # Read the last reset time atomically by checking both files.
        last_reset_time_A=$(cat "/tmp/watchdog_reset_time_a" 2>/dev/null || echo 0)
        last_reset_time_B=$(cat "/tmp/watchdog_reset_time_b" 2>/dev/null || echo 0)
        # Determine which file has the most recent reset time.
        last_reset_time=$(( last_reset_time_A > last_reset_time_B ? last_reset_time_A : last_reset_time_B ))
        # Calculate the time difference in milliseconds.
        time_diff=$((current_time - last_reset_time))
        # Check if the time difference exceeds the timeout in milliseconds.
        if [ "$time_diff" -ge $((SYSFS_MONITOR_TIMEOUT * 1000)) ]; then
            # Update syslog.
            log_info "current_time $current_time"
            log_info "last_reset_time $last_reset_time"
            log_info "WD time diff = $time_diff"
            log_info "hw-management script done!"
            # Create the sysfs ready file
            touch "$SYSFS_MONITOR_RDY_FILE"
            # Exit the watchdog.
            exit 0
        fi
        # Sleep for the specified delay period in seconds.
        sleep "$SYSFS_MONITOR_DELAY"
    done
}

do_stop_sysfs_monitor()
{
    # Remove older WD process if it exists.
    if [ -f "$SYSFS_MONITOR_PID_FILE" ]; then
        local MONITOR_PID
        MONITOR_PID=$(cat "$SYSFS_MONITOR_PID_FILE")
        if kill -0 "$MONITOR_PID" 2>/dev/null; then
            if kill "$MONITOR_PID"; then
                log_info "HW Mangement old sysfs monitor process killed succesfully."
                rm -f "$SYSFS_MONITOR_PID_FILE"
            else
                log_info "HW Mangement failed to kill old sysfs monitor process."
                exit 1
            fi
        else
            log_info "HW Mangement old sysfs monitor process $MONITOR_PID already dead, remove the pid file."
            rm -f "$SYSFS_MONITOR_PID_FILE"
        fi
    fi
}

case $SYSFS_MONITOR_ACTION in
    start)
        # Save the PID of the watchdog process.
        touch "$SYSFS_MONITOR_PID_FILE"
        echo $! > "$SYSFS_MONITOR_PID_FILE"
        log_info "HW Mangement Sysfs Monitor process created."
        do_start_sysfs_monitor
    ;;
    stop)
        do_stop_sysfs_monitor
    ;;
    restart|force-reload)
        do_stop_sysfs_monitor
        sleep 5
        do_start_sysfs_monitor
    ;;
    *)
        echo "$__usage"
        exit 1
    ;;
esac
exit 0