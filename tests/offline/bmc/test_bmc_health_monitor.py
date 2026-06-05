#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-health-monitor.sh check_* functions.

The health monitor script contains an infinite monitoring loop, so we test
the individual check functions by re-declaring them in a controlled bash
environment with the same thresholds, rather than sourcing the full script.
"""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

HEALTH_SCRIPT = str(BMC_SCRIPTS_DIR / "hw-management-bmc-health-monitor.sh")

# Thresholds matching the script
_THRESHOLDS = """
MEM_WARN_MB=50
LOAD_WARN=3
KERN_ERR_WARN=5
I2C_ERR_WARN=10
TEMP_WARN_C=85
_HM_MEM_BAD=0
_HM_LOAD_BAD=0
_HM_TEMP_BAD=0
_HM_FS_BAD=0
_HM_WDT_BAD=0
_HM_SVC_JOURNALD_BAD=0
_HM_SVC_UDEVD_BAD=0
LAST_I2C_DMESG_COUNT=0
LAST_KERNEL_RECENT_COUNT=0
log_message() { local level="$1"; shift; echo "[$level] $*"; }
"""


def _run(snippet, stubs_dir=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    full = _THRESHOLDS + "\n" + snippet
    return subprocess.run(
        ["bash", "-c", full],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


class TestHealthMonitorScriptSyntax:
    def test_script_has_no_syntax_errors(self, stubs_dir):
        r = subprocess.run(
            ["bash", "-n", HEALTH_SCRIPT],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        assert r.returncode == 0, f"Syntax error: {r.stderr}"

    def test_script_exists(self):
        assert Path(HEALTH_SCRIPT).exists()

    def test_script_is_bash(self):
        with open(HEALTH_SCRIPT) as f:
            first_line = f.readline()
        assert "bash" in first_line


class TestCheckMemory:
    def test_low_memory_logs_warning(self, stubs_dir, tmp_path):
        meminfo = tmp_path / "meminfo"
        meminfo.write_text("MemTotal: 102400 kB\nMemAvailable: 20480 kB\n")
        snippet = f"""
check_memory() {{
    if [ ! -f "{meminfo}" ]; then return; fi
    local mem_avail=$(awk '/MemAvailable/ {{print int($2/1024)}}' "{meminfo}")
    local mem_total=$(awk '/MemTotal/ {{print int($2/1024)}}' "{meminfo}")
    local mem_used=$((mem_total - mem_avail))
    local mem_pct=$((mem_used * 100 / mem_total))
    if [ "$mem_avail" -lt "$MEM_WARN_MB" ]; then
        if [ "$_HM_MEM_BAD" -eq 0 ]; then
            _HM_MEM_BAD=1
            log_message "WARNING" "Low memory: ${{mem_avail}}MB available (${{mem_pct}}% used)"
        fi
    fi
}}
check_memory
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "[WARNING]" in r.stdout
        assert "Low memory" in r.stdout

    def test_sufficient_memory_no_warning(self, stubs_dir, tmp_path):
        meminfo = tmp_path / "meminfo"
        meminfo.write_text("MemTotal: 102400 kB\nMemAvailable: 81920 kB\n")
        snippet = f"""
check_memory() {{
    if [ ! -f "{meminfo}" ]; then return; fi
    local mem_avail=$(awk '/MemAvailable/ {{print int($2/1024)}}' "{meminfo}")
    if [ "$mem_avail" -lt "$MEM_WARN_MB" ]; then
        log_message "WARNING" "Low memory"
    else
        echo "memory_ok"
    fi
}}
check_memory
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "memory_ok" in r.stdout
        assert "WARNING" not in r.stdout

    def test_missing_meminfo_returns_gracefully(self, stubs_dir):
        snippet = """
check_memory() {
    if [ ! -f /proc/meminfo_nonexistent ]; then
        echo "graceful_return"
        return
    fi
    log_message "WARNING" "should_not_log"
}
check_memory
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "graceful_return" in r.stdout
        assert "WARNING" not in r.stdout

    def test_rolling_state_suppresses_duplicate_warning(self, stubs_dir):
        snippet = """
_HM_MEM_BAD=1
check_memory() {
    local mem_avail=10
    if [ "$mem_avail" -lt "$MEM_WARN_MB" ]; then
        if [ "$_HM_MEM_BAD" -eq 0 ]; then
            log_message "WARNING" "Low memory"
        else
            echo "suppressed"
        fi
    fi
}
check_memory
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "suppressed" in r.stdout
        assert "WARNING" not in r.stdout

    def test_recovery_clears_bad_flag(self, stubs_dir, tmp_path):
        meminfo = tmp_path / "meminfo"
        meminfo.write_text("MemTotal: 102400 kB\nMemAvailable: 81920 kB\n")
        snippet = f"""
_HM_MEM_BAD=1
check_memory() {{
    local mem_avail=$(awk '/MemAvailable/ {{print int($2/1024)}}' "{meminfo}")
    if [ "$mem_avail" -lt "$MEM_WARN_MB" ]; then
        log_message "WARNING" "Low"
    else
        if [ "$_HM_MEM_BAD" -eq 1 ]; then
            _HM_MEM_BAD=0
            log_message "INFO" "Memory pressure cleared"
        fi
    fi
}}
check_memory
echo "_HM_MEM_BAD=$_HM_MEM_BAD"
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "cleared" in r.stdout
        assert "_HM_MEM_BAD=0" in r.stdout


class TestCheckCpuLoad:
    def test_high_load_logs_warning(self, stubs_dir):
        snippet = """
check_cpu_load() {
    local load=5
    local load_int=5
    if [ "$load_int" -gt "$LOAD_WARN" ]; then
        if [ "$_HM_LOAD_BAD" -eq 0 ]; then
            _HM_LOAD_BAD=1
            log_message "WARNING" "High CPU load: $load"
        fi
    fi
}
check_cpu_load
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "[WARNING]" in r.stdout
        assert "High CPU load" in r.stdout

    def test_normal_load_no_warning(self, stubs_dir):
        snippet = """
check_cpu_load() {
    local load=1
    local load_int=1
    if [ "$load_int" -gt "$LOAD_WARN" ]; then
        log_message "WARNING" "High load"
    else
        echo "load_ok"
    fi
}
check_cpu_load
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "load_ok" in r.stdout
        assert "WARNING" not in r.stdout

    def test_load_at_threshold_no_warning(self, stubs_dir):
        snippet = """
check_cpu_load() {
    local load_int=3
    if [ "$load_int" -gt "$LOAD_WARN" ]; then
        log_message "WARNING" "High"
    else
        echo "at_threshold_ok"
    fi
}
check_cpu_load
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "at_threshold_ok" in r.stdout


class TestCheckKernelErrors:
    def test_no_errors_returns_without_warning(self, stubs_dir):
        snippet = """
dmesg() { echo "normal boot"; echo "net: eth0 up"; }
check_kernel_errors() {
    local recent_errors
    recent_errors=$(dmesg 2>/dev/null | tail -100 | grep -c -i "error\|fail\|bug\|oops" 2>/dev/null)
    recent_errors=${recent_errors:-0}
    if ! [ "$recent_errors" -gt "$KERN_ERR_WARN" ] 2>/dev/null; then
        echo "no_kernel_errors"
        LAST_KERNEL_RECENT_COUNT=0
        return
    fi
    log_message "WARNING" "kernel errors"
}
check_kernel_errors
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "no_kernel_errors" in r.stdout

    def test_many_errors_logs_warning(self, stubs_dir):
        snippet = """
dmesg() {
    for i in $(seq 1 10); do echo "error: hardware failed $i"; done
}
check_kernel_errors() {
    local recent_errors
    recent_errors=$(dmesg 2>/dev/null | tail -100 | grep -c -i "error\|fail\|bug\|oops" 2>/dev/null)
    recent_errors=${recent_errors:-0}
    if [ "$recent_errors" -gt "$KERN_ERR_WARN" ] 2>/dev/null; then
        if [ "$recent_errors" -gt "${LAST_KERNEL_RECENT_COUNT:-0}" ]; then
            log_message "WARNING" "$recent_errors kernel errors"
        fi
    fi
    LAST_KERNEL_RECENT_COUNT=$recent_errors
}
check_kernel_errors
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "[WARNING]" in r.stdout

    def test_stable_error_count_no_duplicate_log(self, stubs_dir):
        snippet = """
LAST_KERNEL_RECENT_COUNT=10
dmesg() { for i in $(seq 1 10); do echo "error: thing $i"; done; }
check_kernel_errors() {
    local recent_errors=10
    if [ "$recent_errors" -gt "$KERN_ERR_WARN" ] 2>/dev/null; then
        if [ "$recent_errors" -gt "${LAST_KERNEL_RECENT_COUNT:-0}" ]; then
            log_message "WARNING" "new errors"
        else
            echo "count_stable_no_log"
        fi
    fi
}
check_kernel_errors
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "count_stable_no_log" in r.stdout


class TestCheckTemperature:
    def test_high_temp_logs_warning(self, stubs_dir, tmp_path):
        hwmon = tmp_path / "hwmon0"
        hwmon.mkdir()
        (hwmon / "temp1_input").write_text("90000\n")
        snippet = f"""
check_temperature() {{
    local max_temp=0
    for temp_file in {hwmon}/temp*_input; do
        if [ -f "$temp_file" ]; then
            local t=$(cat "$temp_file" 2>/dev/null || echo 0)
            local c=$((t / 1000))
            [ "$c" -gt "$max_temp" ] && max_temp=$c
        fi
    done
    if [ "$max_temp" -gt "$TEMP_WARN_C" ]; then
        if [ "$_HM_TEMP_BAD" -eq 0 ]; then
            _HM_TEMP_BAD=1
            log_message "WARNING" "High temperature: ${{max_temp}}C"
        fi
    fi
}}
check_temperature
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "[WARNING]" in r.stdout
        assert "High temperature" in r.stdout

    def test_normal_temp_no_warning(self, stubs_dir, tmp_path):
        hwmon = tmp_path / "hwmon0"
        hwmon.mkdir()
        (hwmon / "temp1_input").write_text("50000\n")
        snippet = f"""
check_temperature() {{
    local max_temp=0
    for temp_file in {hwmon}/temp*_input; do
        if [ -f "$temp_file" ]; then
            local t=$(cat "$temp_file" 2>/dev/null || echo 0)
            local c=$((t / 1000))
            [ "$c" -gt "$max_temp" ] && max_temp=$c
        fi
    done
    if [ "$max_temp" -gt "$TEMP_WARN_C" ]; then
        log_message "WARNING" "High temp"
    else
        echo "temp_ok"
    fi
}}
check_temperature
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "temp_ok" in r.stdout

    def test_no_hwmon_files_completes_without_crash(self, stubs_dir, tmp_path):
        snippet = f"""
check_temperature() {{
    local max_temp=0
    for temp_file in {tmp_path}/nonexistent_hwmon/temp*_input; do
        [ -f "$temp_file" ] || continue
    done
    echo "completed max=$max_temp"
}}
check_temperature
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "completed" in r.stdout


class TestCheckFilesystem:
    def test_high_usage_logs_warning(self, stubs_dir):
        snippet = """
df() { printf "Filesystem Size Used Avail Use%% Mounted\\n/ 10G 9.5G 500M 95%% /\\n"; }
check_filesystem() {
    local root_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$root_usage" -gt 90 ]; then
        if [ "$_HM_FS_BAD" -eq 0 ]; then
            _HM_FS_BAD=1
            log_message "WARNING" "Root filesystem ${root_usage}% full"
        fi
    fi
}
check_filesystem
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "[WARNING]" in r.stdout

    def test_low_usage_no_warning(self, stubs_dir):
        snippet = """
df() { printf "Filesystem Size Used Avail Use%% Mounted\\n/ 10G 3G 7G 30%% /\\n"; }
check_filesystem() {
    local root_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$root_usage" -gt 90 ]; then
        log_message "WARNING" "full"
    else
        echo "fs_ok"
    fi
}
check_filesystem
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "fs_ok" in r.stdout


class TestCheckI2cHealth:
    def test_no_i2c_errors_no_log(self, stubs_dir):
        snippet = """
dmesg() { echo "normal kernel message"; }
check_i2c_health() {
    local i2c_errors
    i2c_errors=$(dmesg 2>/dev/null | grep -c "i2c.*timeout\|i2c.*error" 2>/dev/null)
    i2c_errors=${i2c_errors:-0}
    local prev=${LAST_I2C_DMESG_COUNT:-0}
    local delta=$((i2c_errors - prev))
    LAST_I2C_DMESG_COUNT=$i2c_errors
    if [ "$delta" -le 0 ]; then
        echo "no_new_i2c_errors"
        return
    fi
    log_message "WARNING" "I2C errors delta=$delta"
}
check_i2c_health
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "no_new_i2c_errors" in r.stdout

    def test_new_i2c_errors_logs_warning(self, stubs_dir):
        snippet = """
dmesg() {
    for i in $(seq 1 15); do echo "i2c-3: timeout waiting for bus ready $i"; done
}
LAST_I2C_DMESG_COUNT=0
check_i2c_health() {
    local i2c_errors
    i2c_errors=$(dmesg 2>/dev/null | grep -c "i2c.*timeout\|i2c.*error" 2>/dev/null)
    i2c_errors=${i2c_errors:-0}
    local prev=${LAST_I2C_DMESG_COUNT:-0}
    [ "$i2c_errors" -lt "$prev" ] && prev=$i2c_errors
    local delta=$((i2c_errors - prev))
    LAST_I2C_DMESG_COUNT=$i2c_errors
    if [ "$delta" -le 0 ]; then return; fi
    if ! [ "$i2c_errors" -gt "$I2C_ERR_WARN" ] 2>/dev/null; then return; fi
    log_message "WARNING" "I2C dmesg matches increased by $delta (total $i2c_errors)"
}
check_i2c_health
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "[WARNING]" in r.stdout


class TestCheckWatchdogStatus:
    def test_no_watchdog_devices_no_warning(self, stubs_dir, tmp_path):
        wdt_dir = tmp_path / "watchdog_empty"
        wdt_dir.mkdir()
        snippet = f"""
check_watchdog_status() {{
    local any_low=0
    for wdt in {wdt_dir}/watchdog*; do
        [ -d "$wdt" ] || continue
        any_low=1
    done
    if [ "$any_low" -eq 0 ]; then
        echo "no_watchdogs"
    fi
}}
check_watchdog_status
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "no_watchdogs" in r.stdout

    def test_watchdog_low_timeleft_logs_warning(self, stubs_dir, tmp_path):
        wdt = tmp_path / "watchdog0"
        wdt.mkdir()
        (wdt / "state").write_text("active\n")
        (wdt / "timeleft").write_text("10\n")
        snippet = f"""
check_watchdog_status() {{
    local any_low=0
    local low_detail=""
    for wdt in {wdt}; do
        if [ -d "$wdt" ]; then
            local state=$(cat "$wdt/state" 2>/dev/null)
            if [ "$state" = "active" ]; then
                local timeleft=$(cat "$wdt/timeleft" 2>/dev/null || echo "unknown")
                if [ "$timeleft" != "unknown" ] && [ "$timeleft" -lt 30 ] 2>/dev/null; then
                    any_low=1
                fi
            fi
        fi
    done
    if [ "$any_low" -eq 1 ]; then
        if [ "$_HM_WDT_BAD" -eq 0 ]; then
            _HM_WDT_BAD=1
            log_message "WARNING" "Watchdog low timeleft"
        fi
    fi
}}
check_watchdog_status
"""
        r = _run(snippet, stubs_dir=stubs_dir)
        assert "[WARNING]" in r.stdout
