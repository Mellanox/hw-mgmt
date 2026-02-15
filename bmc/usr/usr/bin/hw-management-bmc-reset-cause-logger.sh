#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2025 NVIDIA CORPORATION & AFFILIATES
#
# BMC Reset Cause Logger
# Logs BMC reset/boot cause on every boot for debugging unexpected reboots

LOG_FILE="/var/log/bmc-reset-cause.log"
CRASH_DIR="/var/log/bmc-crashes"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$CRASH_DIR"

echo "========================================" >> "$LOG_FILE"
echo "BMC Boot at $TIMESTAMP" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# Get boot count
if [ -f /proc/sys/kernel/random/boot_id ]; then
    BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)
    echo "Boot ID: $BOOT_ID" >> "$LOG_FILE"
fi

# Note: CPLD reset cause registers are for CPU/host reset causes, not BMC
# They are not checked here as they don't indicate BMC reset reasons

# Check AST2600/AST2700 watchdog status
for wdt in /sys/class/watchdog/watchdog*; do
    if [ -d "$wdt" ]; then
        WDT_NAME=$(basename "$wdt")
        if [ -f "$wdt/identity" ]; then
            IDENTITY=$(cat "$wdt/identity" 2>/dev/null)
            echo "  $WDT_NAME identity: $IDENTITY" >> "$LOG_FILE"
        fi
        if [ -f "$wdt/bootstatus" ]; then
            BOOTSTATUS=$(cat "$wdt/bootstatus" 2>/dev/null)
            if [ "$BOOTSTATUS" != "0" ]; then
                echo "  $WDT_NAME bootstatus: $BOOTSTATUS (WATCHDOG CAUSED RESET!)" >> "$LOG_FILE"
            fi
        fi
    fi
done

# Check for kernel panic/crash in pstore
if [ -d /sys/fs/pstore ]; then
    PSTORE_FILES=$(ls /sys/fs/pstore/ 2>/dev/null)
    PSTORE_COUNT=$(echo "$PSTORE_FILES" | wc -w)

    if [ "$PSTORE_COUNT" -gt 0 ]; then
        echo "" >> "$LOG_FILE"
        echo "!!! KERNEL CRASH DETECTED - pstore data available !!!" >> "$LOG_FILE"
        echo "pstore entries found: $PSTORE_COUNT" >> "$LOG_FILE"

        # Create crash dump directory
        CRASH_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        CRASH_DUMP_DIR="$CRASH_DIR/crash-$CRASH_TIMESTAMP"
        mkdir -p "$CRASH_DUMP_DIR"

        # Copy pstore files
        cp -r /sys/fs/pstore/* "$CRASH_DUMP_DIR/" 2>/dev/null

        # Log crash file names
        echo "Crash data saved to: $CRASH_DUMP_DIR" >> "$LOG_FILE"
        echo "Files:" >> "$LOG_FILE"
        ls -lh "$CRASH_DUMP_DIR/" >> "$LOG_FILE"

        # Extract panic message if available
        for pstore_file in /sys/fs/pstore/dmesg-ramoops-*; do
            if [ -f "$pstore_file" ]; then
                echo "" >> "$LOG_FILE"
                echo "Panic excerpt from $(basename "$pstore_file"):" >> "$LOG_FILE"
                grep -A 10 "Kernel panic\|BUG:\|Oops:\|Call Trace:" "$pstore_file" | head -n 30 >> "$LOG_FILE" 2>/dev/null || true
            fi
        done
    else
        echo "pstore: No crash data found (clean boot)" >> "$LOG_FILE"
    fi
else
    echo "pstore: Not available or not mounted" >> "$LOG_FILE"
fi

# Check system uptime
UPTIME=$(uptime)
echo "" >> "$LOG_FILE"
echo "Current Uptime: $UPTIME" >> "$LOG_FILE"

# Check memory status
if [ -f /proc/meminfo ]; then
    MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_FREE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    MEM_USED=$((MEM_TOTAL - MEM_FREE))
    MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
    echo "Memory: ${MEM_USED}KB used / ${MEM_TOTAL}KB total (${MEM_PCT}%)" >> "$LOG_FILE"
fi

# Check for critical kernel messages from current boot
echo "" >> "$LOG_FILE"
echo "Critical kernel messages (current boot):" >> "$LOG_FILE"
dmesg | grep -i "error\|fail\|bug\|oops\|panic\|watchdog" | tail -20 >> "$LOG_FILE" 2>/dev/null || echo "  None" >> "$LOG_FILE"

# Check previous boot journal if available (systemd-based systems)
if command -v journalctl &> /dev/null; then
    echo "" >> "$LOG_FILE"
    echo "Previous boot errors (last 30 lines):" >> "$LOG_FILE"
    journalctl -b -1 -p err --no-pager 2>/dev/null | tail -30 >> "$LOG_FILE" || echo "  Previous boot journal not available" >> "$LOG_FILE"
fi

# Check GPIO states of critical pins
echo "" >> "$LOG_FILE"
echo "Critical GPIO States:" >> "$LOG_FILE"
if command -v gpioinfo &> /dev/null; then
    # Check for standby enable GPIO
    gpioinfo 2>/dev/null | grep -i "stby\|standby" >> "$LOG_FILE" || true
    # Check for power-related GPIOs
    gpioinfo 2>/dev/null | grep -i "pwr\|power" >> "$LOG_FILE" || true
fi

echo "" >> "$LOG_FILE"
echo "End of boot analysis" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Rotate log file if it gets too large (> 10MB)
LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
if [ "$LOG_SIZE" -gt 10485760 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    echo "Log rotated at $TIMESTAMP" > "$LOG_FILE"
fi

exit 0

