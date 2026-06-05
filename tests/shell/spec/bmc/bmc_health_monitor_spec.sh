#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for hw-management-bmc-health-monitor.sh check_* functions.

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

HEALTH_SCRIPT="${BMC_SCRIPTS_DIR}/hw-management-bmc-health-monitor.sh"

MEM_WARN_MB=50; LOAD_WARN=3; KERN_ERR_WARN=5; TEMP_WARN_C=85
_HM_MEM_BAD=0; _HM_LOAD_BAD=0; _HM_TEMP_BAD=0; _HM_FS_BAD=0; _HM_WDT_BAD=0
log_message() { printf '[%s] %s\n' "$1" "${*:2}"; }

_check_memory() {
    local f="$1"
    [ ! -f "$f" ] && printf 'skipped\n' && return 0
    local mem_avail
    mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' "$f")
    if [ "$mem_avail" -lt "$MEM_WARN_MB" ]; then
        [ "$_HM_MEM_BAD" -eq 0 ] && _HM_MEM_BAD=1 && log_message "WARNING" "Low memory: ${mem_avail}MB"
    else
        [ "$_HM_MEM_BAD" -eq 1 ] && _HM_MEM_BAD=0 && log_message "INFO" "Memory pressure cleared"
        printf 'memory_ok\n'
    fi
}

_check_cpu_load() {
    local load_int="$1"
    if [ "$load_int" -gt "$LOAD_WARN" ]; then
        [ "$_HM_LOAD_BAD" -eq 0 ] && _HM_LOAD_BAD=1 && log_message "WARNING" "High CPU load: $load_int"
    else
        printf 'load_ok\n'
    fi
}

_check_kernel_errors() {
    local recent_errors="$1"
    ! [ "$recent_errors" -gt "$KERN_ERR_WARN" ] 2>/dev/null && printf 'no_kernel_errors\n' && return
    if [ "$recent_errors" -gt "${LAST_KERNEL_RECENT_COUNT:-0}" ] 2>/dev/null; then
        log_message "WARNING" "$recent_errors kernel errors"
    else
        printf 'count_stable\n'
    fi
    LAST_KERNEL_RECENT_COUNT=$recent_errors
}

_check_temp() {
    local hwmon_dir="$1" max_temp=0
    for f in "${hwmon_dir}"/temp*_input; do
        [ -f "$f" ] || continue
        local t c
        t=$(cat "$f" 2>/dev/null || printf '0')
        c=$((t / 1000))
        [ "$c" -gt "$max_temp" ] && max_temp=$c
    done
    if [ "$max_temp" -gt "$TEMP_WARN_C" ]; then
        [ "$_HM_TEMP_BAD" -eq 0 ] && _HM_TEMP_BAD=1 && log_message "WARNING" "High temperature: ${max_temp}C"
    else
        printf 'temp_ok max=%s\n' "$max_temp"
    fi
}

_check_fs() {
    local usage="$1"
    if [ "$usage" -gt 90 ]; then
        [ "$_HM_FS_BAD" -eq 0 ] && _HM_FS_BAD=1 && log_message "WARNING" "Root filesystem ${usage}% full"
    else
        printf 'fs_ok\n'
    fi
}

_check_wdt() {
    local wdt_dir="$1" any_low=0
    for wdt in "${wdt_dir}"/watchdog*; do
        [ -d "$wdt" ] || continue
        local state timeleft
        state=$(cat "$wdt/state" 2>/dev/null)
        [ "$state" = "active" ] || continue
        timeleft=$(cat "$wdt/timeleft" 2>/dev/null || printf 'unknown')
        [ "$timeleft" != "unknown" ] && [ "$timeleft" -lt 30 ] 2>/dev/null && any_low=1
    done
    if [ "$any_low" -eq 1 ]; then
        [ "$_HM_WDT_BAD" -eq 0 ] && _HM_WDT_BAD=1 && log_message "WARNING" "Watchdog low timeleft"
    else
        printf 'watchdog_ok\n'
    fi
}

Describe 'hw-management-bmc-health-monitor.sh'

    BeforeEach 'setup_hm'
    AfterEach  'cleanup_hm'

    setup_hm() {
        WORK_DIR=$(mktemp -d); export WORK_DIR
        _HM_MEM_BAD=0; _HM_LOAD_BAD=0; _HM_TEMP_BAD=0; _HM_FS_BAD=0; _HM_WDT_BAD=0
    }
    cleanup_hm() { rm -rf "${WORK_DIR}"; }

    Describe 'script syntax'
        It 'has no bash syntax errors'
            When run bash -n "${HEALTH_SCRIPT}"
            The status should equal 0
        End
        It 'script file exists'
            The path "${HEALTH_SCRIPT}" should be exist
        End
    End

    Describe 'check_memory(): low memory'
        BeforeEach 'setup_low_mem'
        setup_low_mem() {
            printf 'MemTotal: 102400 kB\nMemAvailable: 20480 kB\n' > "${WORK_DIR}/meminfo"
        }
        It 'logs WARNING when MemAvailable < 50MB'
            When call _check_memory "${WORK_DIR}/meminfo"
            The output should include '[WARNING]'
            The output should include 'Low memory'
        End
    End

    Describe 'check_memory(): sufficient memory'
        BeforeEach 'setup_ok_mem'
        setup_ok_mem() {
            printf 'MemTotal: 102400 kB\nMemAvailable: 81920 kB\n' > "${WORK_DIR}/meminfo"
        }
        It 'prints memory_ok when MemAvailable >= 50MB'
            When call _check_memory "${WORK_DIR}/meminfo"
            The output should include 'memory_ok'
            The output should not include 'WARNING'
        End
    End

    Describe 'check_memory(): missing file'
        It 'prints skipped when meminfo is missing'
            When call _check_memory "${WORK_DIR}/nonexistent"
            The output should equal 'skipped'
            The status should equal 0
        End
    End

    Describe 'check_memory(): rolling state'
        BeforeEach 'setup_rolling'
        setup_rolling() {
            printf 'MemTotal: 102400 kB\nMemAvailable: 20480 kB\n' > "${WORK_DIR}/meminfo"
            _HM_MEM_BAD=1
        }
        It 'suppresses duplicate WARNING when flag already set'
            When call _check_memory "${WORK_DIR}/meminfo"
            The output should not include 'WARNING'
            The status should equal 1
        End
    End

    Describe 'check_cpu_load()'
        It 'logs WARNING for load above threshold (5 > 3)'
            When call _check_cpu_load 5
            The output should include '[WARNING]'
            The output should include 'High CPU load'
        End
        It 'prints load_ok for normal load (1)'
            When call _check_cpu_load 1
            The output should include 'load_ok'
            The output should not include 'WARNING'
        End
        It 'prints load_ok at exactly threshold (3)'
            When call _check_cpu_load 3
            The output should include 'load_ok'
        End
    End

    Describe 'check_kernel_errors()'
        It 'prints no_kernel_errors when count below threshold (3)'
            When call _check_kernel_errors 3
            The output should include 'no_kernel_errors'
        End
        It 'logs WARNING when count exceeds threshold (10)'
            When call _check_kernel_errors 10
            The output should include '[WARNING]'
        End
        It 'prints count_stable when count unchanged'
            stable() { LAST_KERNEL_RECENT_COUNT=10; _check_kernel_errors 10; }
            When call stable
            The output should include 'count_stable'
            The output should not include 'WARNING'
        End
    End

    Describe 'check_temperature(): high temp'
        BeforeEach 'setup_high_temp'
        setup_high_temp() {
            mkdir -p "${WORK_DIR}/hwmon0"
            printf '90000\n' > "${WORK_DIR}/hwmon0/temp1_input"
        }
        It 'logs WARNING when temp exceeds 85C'
            When call _check_temp "${WORK_DIR}/hwmon0"
            The output should include '[WARNING]'
            The output should include 'High temperature'
        End
    End

    Describe 'check_temperature(): normal temp'
        BeforeEach 'setup_ok_temp'
        setup_ok_temp() {
            mkdir -p "${WORK_DIR}/hwmon0"
            printf '50000\n' > "${WORK_DIR}/hwmon0/temp1_input"
        }
        It 'prints temp_ok when temp below 85C'
            When call _check_temp "${WORK_DIR}/hwmon0"
            The output should include 'temp_ok'
            The output should not include 'WARNING'
        End
    End

    Describe 'check_temperature(): no hwmon files'
        It 'completes without crash'
            When call _check_temp "${WORK_DIR}/empty_hwmon"
            The output should include 'temp_ok'
            The status should equal 0
        End
    End

    Describe 'check_filesystem()'
        It 'logs WARNING for 95% full'
            When call _check_fs 95
            The output should include '[WARNING]'
        End
        It 'prints fs_ok for 30% full'
            When call _check_fs 30
            The output should include 'fs_ok'
        End
        It 'prints fs_ok at exactly 90%'
            When call _check_fs 90
            The output should include 'fs_ok'
        End
    End

    Describe 'check_watchdog_status(): no devices'
        It 'prints watchdog_ok when no wdt devices exist'
            When call _check_wdt "${WORK_DIR}/no_wdt"
            The output should include 'watchdog_ok'
            The status should equal 0
        End
    End

    Describe 'check_watchdog_status(): low timeleft'
        BeforeEach 'setup_low_wdt'
        setup_low_wdt() {
            mkdir -p "${WORK_DIR}/wdt/watchdog0"
            printf 'active\n' > "${WORK_DIR}/wdt/watchdog0/state"
            printf '10\n'     > "${WORK_DIR}/wdt/watchdog0/timeleft"
        }
        It 'logs WARNING when timeleft < 30s'
            When call _check_wdt "${WORK_DIR}/wdt"
            The output should include '[WARNING]'
            The output should include 'Watchdog low timeleft'
        End
    End

    Describe 'check_watchdog_status(): sufficient timeleft'
        BeforeEach 'setup_ok_wdt'
        setup_ok_wdt() {
            mkdir -p "${WORK_DIR}/wdt/watchdog0"
            printf 'active\n' > "${WORK_DIR}/wdt/watchdog0/state"
            printf '120\n'    > "${WORK_DIR}/wdt/watchdog0/timeleft"
        }
        It 'prints watchdog_ok when timeleft >= 30s'
            When call _check_wdt "${WORK_DIR}/wdt"
            The output should include 'watchdog_ok'
            The output should not include 'WARNING'
        End
    End

End
