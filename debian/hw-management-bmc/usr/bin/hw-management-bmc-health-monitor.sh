#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2025 NVIDIA CORPORATION & AFFILIATES
#
# BMC Health Monitor
# Continuously monitors BMC health and logs anomalies to help predict failures

LOG_FILE="/var/log/bmc-health.log"
CHECK_INTERVAL=60  # seconds

# Thresholds
MEM_WARN_MB=50
LOAD_WARN=3
KERN_ERR_WARN=5
I2C_ERR_WARN=10
TEMP_WARN_C=85

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # Also log to syslog for centralized logging
    if [ "$level" = "ERROR" ] || [ "$level" = "CRITICAL" ]; then
        logger -t bmc-health-monitor -p daemon.err "$message"
    elif [ "$level" = "WARNING" ]; then
        logger -t bmc-health-monitor -p daemon.warning "$message"
    fi
}

check_memory() {
    if [ ! -f /proc/meminfo ]; then
        return
    fi

    local mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    local mem_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    local mem_used=$((mem_total - mem_avail))
    local mem_pct=$((mem_used * 100 / mem_total))

    if [ "$mem_avail" -lt "$MEM_WARN_MB" ]; then
        log_message "WARNING" "Low memory: ${mem_avail}MB available (${mem_pct}% used)"

        # Log top memory consumers (BusyBox compatible)
        if command -v ps &> /dev/null; then
            log_message "INFO" "Top memory consumers:"
            ps | awk 'NR>1' | sort -k6 -rn | head -n 5 | while read line; do
                log_message "INFO" "  $line"
            done
        fi
    fi
}

check_cpu_load() {
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local load_int=${load%.*}

    if [ "$load_int" -gt "$LOAD_WARN" ]; then
        log_message "WARNING" "High CPU load: $load"

        # Log top CPU consumers (BusyBox compatible)
        if command -v ps &> /dev/null; then
            log_message "INFO" "Top CPU consumers:"
            ps | awk 'NR>1' | sort -k3 -rn | head -n 5 | while read line; do
                log_message "INFO" "  $line"
            done
        fi
    fi
}

check_kernel_errors() {
    # BusyBox dmesg may not support -T; ensure single numeric value for comparison
    local recent_errors
    recent_errors=$(dmesg 2>/dev/null | tail -100 | grep -c -i "error\|fail\|bug\|oops" 2>/dev/null)
    recent_errors=${recent_errors:-0}
    recent_errors=$(echo "$recent_errors" | head -n 1 | tr -d ' ')

    if [ "$recent_errors" -gt "$KERN_ERR_WARN" ] 2>/dev/null; then
        log_message "WARNING" "$recent_errors kernel errors in last 100 messages"

        # Log recent error messages
        dmesg 2>/dev/null | tail -100 | grep -i "error\|fail\|bug\|oops" | tail -n 5 | while read line; do
            log_message "ERROR" "KERNEL: $line"
        done
    fi
}

check_i2c_health() {
    # I2C is critical for BMC operation (sensors, CPLD communication, etc.)
    local i2c_errors
    i2c_errors=$(dmesg 2>/dev/null | grep -c "i2c.*timeout\|i2c.*error" 2>/dev/null)
    i2c_errors=${i2c_errors:-0}
    i2c_errors=$(echo "$i2c_errors" | head -n 1 | tr -d ' ')

    if [ "$i2c_errors" -gt "$I2C_ERR_WARN" ] 2>/dev/null; then
        log_message "WARNING" "I2C bus errors detected: $i2c_errors total"

        # Check for specific I2C bus issues
        dmesg 2>/dev/null | grep "i2c.*timeout\|i2c.*error" | tail -n 3 | while read line; do
            log_message "ERROR" "I2C: $line"
        done
    fi
}

check_watchdog_status() {
    # Check AST2600 watchdog status
    for wdt in /sys/class/watchdog/watchdog*; do
        if [ -d "$wdt" ]; then
            local wdt_name=$(basename "$wdt")

            if [ -f "$wdt/state" ]; then
                local state=$(cat "$wdt/state" 2>/dev/null)
                if [ "$state" = "active" ]; then
                    # Watchdog is active, check timeleft if available
                    if [ -f "$wdt/timeleft" ]; then
                        local timeleft=$(cat "$wdt/timeleft" 2>/dev/null || echo "unknown")
                        if [ "$timeleft" != "unknown" ] && [ "$timeleft" -lt 30 ]; then
                            log_message "WARNING" "$wdt_name has only ${timeleft}s remaining!"
                        fi
                    fi
                fi
            fi
        fi
    done
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
        log_message "WARNING" "High temperature detected: ${max_temp}°C (from ${temp_location})"
    fi
}

check_filesystem() {
    # Check for filesystem issues
    local root_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$root_usage" -gt 90 ]; then
        log_message "WARNING" "Root filesystem ${root_usage}% full"

        # Log largest directories
        log_message "INFO" "Largest directories in /:"
        du -hx / --max-depth=2 2>/dev/null | sort -rh | head -n 5 | while read line; do
            log_message "INFO" "  $line"
        done
    fi
}

check_critical_services() {
    # Check if critical services are running
    local critical_services="systemd-journald systemd-udevd"

    for service in $critical_services; do
        if command -v systemctl &> /dev/null; then
            if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                log_message "ERROR" "Critical service $service is not running"
            fi
        fi
    done
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

    # Rotate log if it gets too large (> 10MB to save space on BMC)
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$LOG_SIZE" -gt 10485760 ]; then
            # Keep only last rotation to save space
            rm -f "${LOG_FILE}.old" 2>/dev/null
            mv "$LOG_FILE" "${LOG_FILE}.old"
            log_message "INFO" "Log rotated (previous log saved as ${LOG_FILE}.old)"
        fi
    fi

    sleep "$CHECK_INTERVAL"
done

