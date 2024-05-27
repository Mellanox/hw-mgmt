#!/bin/bash

source hw-management-helpers.sh

trace_udev_events "hw-mngmt done called"

# Watchdog loop
while true; do
    # Get the current time with milliseconds
    current_time=$(date +%s%3N)

    # Read the last reset time atomically
    if [[ -f "$WATCHDOG_RESET_FILE" ]]; then
        last_reset_time=$(cat "$WATCHDOG_RESET_FILE")
    else
        last_reset_time=$current_time
    fi

    # Calculate the time difference in milliseconds
    time_diff=$((current_time - last_reset_time))

    # Check if the time difference exceeds the timeout in milliseconds
    if [ "$time_diff" -ge $((WATCHDOG_TIMEOUT * 1000)) ]; then
        # Update the status file
        echo "1" > "$WATCHDOG_STATUS_FILE"
        # Update syslog
        logger "hw-management script done!"

        # Exit the watchdog
        exit 0
    fi

    # Sleep for the specified delay period in seconds
    sleep "$WATCHDOG_DELAY"
done
