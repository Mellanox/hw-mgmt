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

log_info "hw-mngmt-done started."

# Wait until the first run file is created by check_n_link.
while [[ ! -f "$WATCHDOG_FIRST_RUN_FILE" ]]; do
    sleep "$WATCHDOG_DELAY"
done

log_info "first run file created, starting Watchdog logic."

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
    if [ "$time_diff" -ge $((WATCHDOG_TIMEOUT * 1000)) ]; then
        # Update the status file atomically using using a temporary file.
        echo "1" > "$WATCHDOG_STATUS_TEMP_FILE"
        mv "$WATCHDOG_STATUS_TEMP_FILE" "$WATCHDOG_STATUS_FILE"  # Atomic move.
        # Update syslog.
        log_info "current_time $current_time"
        log_info "last_reset_time $last_reset_time"
        log_info "WD time diff = $time_diff"
        log_info "hw-management script done!"
        # Create the sysfs ready file
        touch "$HW_MGMT_SYSFS_RDY"
        # Exit the watchdog.
        exit 0
    fi
    # Sleep for the specified delay period in seconds.
    sleep "$WATCHDOG_DELAY"
done