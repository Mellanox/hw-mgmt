#!/bin/bash
##################################################################################
# Copyright (c) 2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

log_info "hw-mngmt-fast-sysfs-monitor started."

FAST_SYSFS_MONITOR_ACTION=$1

__usage="
Usage: $(basename "$0") [Options]

Options:
    start   Start hw-mngmt-fast-sysfs-monitor.
    stop    Stop hw-mngmt-fast-sysfs-monitor.
    restart
    force-reload    Performs hw-mngmt-fast-sysfs-monitor 'stop' and the 'start.
"

do_start_fast_sysfs_monitor()
{
    log_info "Starting hw-mngmt-fast-sysfs-monitor logic."
    # Extract file paths from JSON manually (removes brackets, quotes, and spaces).
    FILES=($(grep -o '"[^"]*"' "$FAST_SYSFS_MONITOR_LABELS_JSON" | tr -d '"' ))
    # Extract the last element (filename) from each JSON path.
    DEV_FILES=($(for file in "${FILES[@]}"; do basename "$file"; done))
    # Get the total number of files to check.
    TOTAL_FILES=${#FILES[@]}
    declare -A FOUND_FILES
    declare -A DEVICE_ADDED  # Track added devices per file name.
    ELAPSED=0
    log_info "Monitoring ${TOTAL_FILES} files..."
    while (( ELAPSED < FAST_SYSFS_MONITOR_TIMEOUT )); do
    # Check and add missing devices from devtree_file.
    if [ -e "$devtree_file" ] && [ -d "$eeprom_path" ] && [[ ${#DEVICE_ADDED[@]} -lt ${#DEV_FILES[@]} ]]; then
        # Read the entire content into an array (space-separated tokens).
        read -ra DEVTREE_ENTRIES < "$devtree_file"
        # Process every 4 tokens as one device entry
        for ((i = 0; i < ${#DEVTREE_ENTRIES[@]}; i += 4)); do
            driver_name=${DEVTREE_ENTRIES[i]}
            address=${DEVTREE_ENTRIES[i+1]}
            bus=${DEVTREE_ENTRIES[i+2]}
            file_name=${DEVTREE_ENTRIES[i+3]}
            # Check if file_name is in monitored devices and also hasn't been added yet.
            if [[ " ${DEV_FILES[@]} " =~ " $file_name " && -z "${DEVICE_ADDED[$file_name]}" ]]; then
                if [ ! -d /sys/bus/i2c/devices/$bus-00"${address#0x}" ] && [ ! -d /sys/bus/i2c/devices/$bus-000"${address#0x}" ]; then
                    log_info "Adding device: $driver_name $address $bus $file_name"
                    echo "$driver_name $address" > "/sys/bus/i2c/devices/i2c-$bus/new_device"
                    sleep 1 # Let the filesystem relax.
                    DEVICE_ADDED[$file_name]=1
                fi
            fi
        done
    fi
    # Check monitored files.
    for FILE in "${FILES[@]}"; do
        if [[ -f "$FILE" ]]; then
            FOUND_FILES["$FILE"]=1
        fi
    done
    # Exit if all monitored files exist.
    if [[ ${#FOUND_FILES[@]} -eq $TOTAL_FILES ]]; then
        log_info "All fast sysfs labels exist. Done."
        # Get the current time in milliseconds.
        local current_time=$(awk '{print int($1 * 1000)}' /proc/uptime)
        # Write the current time into the fast sysfs ready file.
        echo "$current_time" > "$FAST_SYSFS_MONITOR_RDY_FILE"
        exit 0
    fi
    # Sleep for the defined interval.
    sleep "$FAST_SYSFS_MONITOR_INTERVAL"
    # Increment elapsed time.
    (( ELAPSED += FAST_SYSFS_MONITOR_INTERVAL ))
    done
    log_info "Timeout reached. Not all files were found."
    exit 0
}

do_stop_fast_sysfs_monitor()
{
    # Remove older fast-sysfs-monitor process if it exists.
    if [ -f "$FAST_SYSFS_MONITOR_PID_FILE" ]; then
        local FAST_MONITOR_PID
        FAST_MONITOR_PID=$(cat "$FAST_SYSFS_MONITOR_PID_FILE")
        if kill -0 "$FAST_MONITOR_PID" 2>/dev/null; then
            if kill "$FAST_MONITOR_PID"; then
                log_info "HW Mangement old fast sysfs monitor process killed succesfully."
                rm -f "$FAST_SYSFS_MONITOR_PID_FILE"
            else
                log_info "HW Mangement failed to kill old fast sysfs monitor process."
                exit 1
            fi
        else
            log_info "HW Mangement old fast sysfs monitor process $FAST_MONITOR_PID already dead, remove the pid file."
            rm -f "$FAST_SYSFS_MONITOR_PID_FILE"
        fi
    fi
}

case $FAST_SYSFS_MONITOR_ACTION in
    start)
        # Save the PID of the Fast Sysfs Monitor process.
        touch "$FAST_SYSFS_MONITOR_PID_FILE"
        echo $! > "$FAST_SYSFS_MONITOR_PID_FILE"
        log_info "HW Mangement Fast Sysfs Monitor process created."
        do_start_fast_sysfs_monitor
    ;;
    stop)
        do_stop_fast_sysfs_monitor
    ;;
    restart|force-reload)
        do_stop_fast_sysfs_monitor
        sleep 5
        do_start_fast_sysfs_monitor
    ;;
    *)
        echo "$__usage"
        exit 1
    ;;
esac
exit 0
