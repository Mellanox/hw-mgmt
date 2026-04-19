#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# BMC Health Monitor
# Continuously monitors BMC health and logs anomalies to help predict failures

LOG_TAG="bmc-health-monitor"
# shellcheck source=/dev/null
source /usr/bin/hw-management-bmc-helpers-common.sh

# Detailed history on disk; avoid flooding syslog/journal with periodic INFO lines.
LOG_FILE="/var/log/bmc-health.log"
mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(date "+%Y-%m-%d %H:%M:%S")
	echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

	case "${level,,}" in
		err|error|critical|crit)
			logger -t "$LOG_TAG" -p daemon.err "$message"
			;;
		warning|warn)
			logger -t "$LOG_TAG" -p daemon.warning "$message"
			;;
		*)
			# INFO and other routine messages: private log only
			;;
	esac
}

CHECK_INTERVAL=60  # seconds

# Thresholds
MEM_WARN_MB=50
LOAD_WARN=3
KERN_ERR_WARN=5
I2C_ERR_WARN=10
TEMP_WARN_C=85

# Rolling state (same shell process): avoid logging the same fault every CHECK_INTERVAL.
LAST_I2C_DMESG_COUNT=0
LAST_KERNEL_RECENT_COUNT=0
_HM_MEM_BAD=0
_HM_LOAD_BAD=0
_HM_TEMP_BAD=0
_HM_FS_BAD=0
_HM_WDT_BAD=0
_HM_SVC_JOURNALD_BAD=0
_HM_SVC_UDEVD_BAD=0

check_memory() {
    if [ ! -f /proc/meminfo ]; then
        return
    fi

    local mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    local mem_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    local mem_used=$((mem_total - mem_avail))
    local mem_pct=$((mem_used * 100 / mem_total))

    if [ "$mem_avail" -lt "$MEM_WARN_MB" ]; then
        if [ "$_HM_MEM_BAD" -eq 0 ]; then
            _HM_MEM_BAD=1
            log_message "WARNING" "Low memory: ${mem_avail}MB available (${mem_pct}% used)"

            # Log top memory consumers (BusyBox compatible)
            if command -v ps &> /dev/null; then
                log_message "INFO" "Top memory consumers:"
                ps | awk 'NR>1' | sort -k6 -rn | head -n 5 | while read line; do
                    log_message "INFO" "  $line"
                done
            fi
        fi
    else
        if [ "$_HM_MEM_BAD" -eq 1 ]; then
            _HM_MEM_BAD=0
            log_message "INFO" "Memory pressure cleared (${mem_avail}MB available)"
        fi
    fi
}

check_cpu_load() {
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local load_int=${load%.*}

    if [ "$load_int" -gt "$LOAD_WARN" ]; then
        if [ "$_HM_LOAD_BAD" -eq 0 ]; then
            _HM_LOAD_BAD=1
            log_message "WARNING" "High CPU load: $load"

            # Log top CPU consumers (BusyBox compatible)
            if command -v ps &> /dev/null; then
                log_message "INFO" "Top CPU consumers:"
                ps | awk 'NR>1' | sort -k3 -rn | head -n 5 | while read line; do
                    log_message "INFO" "  $line"
                done
            fi
        fi
    else
        if [ "$_HM_LOAD_BAD" -eq 1 ]; then
            _HM_LOAD_BAD=0
            log_message "INFO" "CPU load returned to normal (load $load)"
        fi
    fi
}

check_kernel_errors() {
    # BusyBox dmesg may not support -T; ensure single numeric value for comparison
    local recent_errors
    recent_errors=$(dmesg 2>/dev/null | tail -100 | grep -c -i "error\|fail\|bug\|oops" 2>/dev/null)
    recent_errors=${recent_errors:-0}
    recent_errors=$(echo "$recent_errors" | head -n 1 | tr -d ' ')

    if ! [ "$recent_errors" -gt "$KERN_ERR_WARN" ] 2>/dev/null; then
        LAST_KERNEL_RECENT_COUNT=0
        return
    fi

    # Only react when the rolling-window count increases (avoids spamming while stable).
    if [ "$recent_errors" -gt "${LAST_KERNEL_RECENT_COUNT:-0}" ] 2>/dev/null; then
        log_message "WARNING" "$recent_errors kernel errors in last 100 messages (previously ${LAST_KERNEL_RECENT_COUNT:-0})"

        # Log recent error messages
        dmesg 2>/dev/null | tail -100 | grep -i "error\|fail\|bug\|oops" | tail -n 5 | while read line; do
            log_message "ERROR" "KERNEL: $line"
        done
    fi
    LAST_KERNEL_RECENT_COUNT=$recent_errors
}

check_i2c_health() {
    # I2C is critical for BMC operation (sensors, CPLD communication, etc.)
    local i2c_errors prev delta
    i2c_errors=$(dmesg 2>/dev/null | grep -c "i2c.*timeout\|i2c.*error" 2>/dev/null)
    i2c_errors=${i2c_errors:-0}
    i2c_errors=$(echo "$i2c_errors" | head -n 1 | tr -d ' ')

    prev=${LAST_I2C_DMESG_COUNT:-0}
    if [ "$i2c_errors" -lt "$prev" ] 2>/dev/null; then
        prev=$i2c_errors
    fi
    delta=$((i2c_errors - prev))
    LAST_I2C_DMESG_COUNT=$i2c_errors

    # Only log when new matching lines appear (delta), not on every interval for stale totals.
    if [ "$delta" -le 0 ] 2>/dev/null; then
        return
    fi
    if ! [ "$i2c_errors" -gt "$I2C_ERR_WARN" ] 2>/dev/null; then
        return
    fi

    log_message "WARNING" "I2C dmesg matches increased by ${delta} (total ${i2c_errors})"

    dmesg 2>/dev/null | grep "i2c.*timeout\|i2c.*error" | tail -n 3 | while read line; do
        log_message "ERROR" "I2C: $line"
    done
}

check_watchdog_status() {
    # Check AST2600 watchdog status; log once when any device enters "low timeleft" until all recover.
    local any_low=0
    local low_detail=""

    for wdt in /sys/class/watchdog/watchdog*; do
        if [ -d "$wdt" ]; then
            local wdt_name=$(basename "$wdt")

            if [ -f "$wdt/state" ]; then
                local state=$(cat "$wdt/state" 2>/dev/null)
                if [ "$state" = "active" ]; then
                    if [ -f "$wdt/timeleft" ]; then
                        local timeleft=$(cat "$wdt/timeleft" 2>/dev/null || echo "unknown")
                        if [ "$timeleft" != "unknown" ] && [ "$timeleft" -lt 30 ] 2>/dev/null; then
                            any_low=1
                            low_detail="${low_detail} ${wdt_name}=${timeleft}s"
                        fi
                    fi
                fi
            fi
        fi
    done

    if [ "$any_low" -eq 1 ]; then
        if [ "$_HM_WDT_BAD" -eq 0 ]; then
            _HM_WDT_BAD=1
            log_message "WARNING" "Watchdog low timeleft:${low_detail}"
        fi
    else
        if [ "$_HM_WDT_BAD" -eq 1 ]; then
            _HM_WDT_BAD=0
            log_message "INFO" "Watchdog timeleft OK"
        fi
    fi
}

check_temperature() {
    # Check BMC ambient temperature sensors via sysfs
    # Find all temp*_input files and check values
    local max_temp=0
    local temp_location=""

    for temp_file in /sys/class/hwmon/hwmon*/temp*_input; do
        if [ -f "$temp_file" ]; then
            local temp_millidegrees=$(cat "$temp_file" 2>/dev/null || echo 0)
            local temp_celsius=$((temp_millidegrees / 1000))

            if [ "$temp_celsius" -gt "$max_temp" ]; then
                max_temp=$temp_celsius
                temp_location="$temp_file"
            fi
        fi
    done

    # Also check AST2600 specific temperature sensors
    for temp_file in /sys/devices/platform/ahb/*/hwmon/hwmon*/temp*_input; do
        if [ -f "$temp_file" ]; then
            local temp_millidegrees=$(cat "$temp_file" 2>/dev/null || echo 0)
            local temp_celsius=$((temp_millidegrees / 1000))

            if [ "$temp_celsius" -gt "$max_temp" ]; then
                max_temp=$temp_celsius
                temp_location="$temp_file"
            fi
        fi
    done

    if [ "$max_temp" -gt "$TEMP_WARN_C" ]; then
        if [ "$_HM_TEMP_BAD" -eq 0 ]; then
            _HM_TEMP_BAD=1
            log_message "WARNING" "High temperature detected: ${max_temp}°C (from ${temp_location})"
        fi
    else
        if [ "$_HM_TEMP_BAD" -eq 1 ]; then
            _HM_TEMP_BAD=0
            log_message "INFO" "Temperature returned below ${TEMP_WARN_C}°C (max ${max_temp}°C)"
        fi
    fi
}

check_filesystem() {
    # Check for filesystem issues
    local root_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$root_usage" -gt 90 ]; then
        if [ "$_HM_FS_BAD" -eq 0 ]; then
            _HM_FS_BAD=1
            log_message "WARNING" "Root filesystem ${root_usage}% full"

            # Log largest directories
            log_message "INFO" "Largest directories in /:"
            du -hx / --max-depth=2 2>/dev/null | sort -rh | head -n 5 | while read line; do
                log_message "INFO" "  $line"
            done
        fi
    else
        if [ "$_HM_FS_BAD" -eq 1 ]; then
            _HM_FS_BAD=0
            log_message "INFO" "Root filesystem usage OK (${root_usage}%)"
        fi
    fi
}

check_critical_services() {
    # Check if critical services are running (edge-triggered to avoid log spam).
    if ! command -v systemctl &> /dev/null; then
        return
    fi

    if ! systemctl is-active --quiet "systemd-journald" 2>/dev/null; then
        if [ "$_HM_SVC_JOURNALD_BAD" -eq 0 ]; then
            _HM_SVC_JOURNALD_BAD=1
            log_message "ERROR" "Critical service systemd-journald is not running"
        fi
    else
        if [ "$_HM_SVC_JOURNALD_BAD" -eq 1 ]; then
            _HM_SVC_JOURNALD_BAD=0
            log_message "INFO" "Critical service systemd-journald is active again"
        fi
    fi

    if ! systemctl is-active --quiet "systemd-udevd" 2>/dev/null; then
        if [ "$_HM_SVC_UDEVD_BAD" -eq 0 ]; then
            _HM_SVC_UDEVD_BAD=1
            log_message "ERROR" "Critical service systemd-udevd is not running"
        fi
    else
        if [ "$_HM_SVC_UDEVD_BAD" -eq 1 ]; then
            _HM_SVC_UDEVD_BAD=0
            log_message "INFO" "Critical service systemd-udevd is active again"
        fi
    fi
}

# Log startup
log_message "INFO" "BMC Health Monitor started (interval: ${CHECK_INTERVAL}s)"

# Main monitoring loop
while true; do
    check_memory
    check_cpu_load
    check_kernel_errors
    check_i2c_health
    check_watchdog_status
    check_temperature
    check_filesystem
    check_critical_services

    # Rotate private log if it gets too large (> 10MB to save space on BMC)
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$LOG_SIZE" -gt 10485760 ]; then
            rm -f "${LOG_FILE}.old" 2>/dev/null
            mv "$LOG_FILE" "${LOG_FILE}.old"
            log_message "INFO" "Log rotated (previous log saved as ${LOG_FILE}.old)"
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
