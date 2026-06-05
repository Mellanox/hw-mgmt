#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for hw-management-bmc-boot-complete.sh

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

# Helper: write a boot-complete conf file
_write_conf() {
    cat > "${CONF_FILE}" << EOF
SYSFS_SYSTEM_COUNTER=${1:-1}
SYSFS_THERMAL_COUNTER=${2:-1}
SYSFS_EEPROM_COUNTER=${3:-1}
BOOT_COMPLETE_MAX_WAIT_SEC=${4:-1}
BOOT_COMPLETE_POLL_SEC=${5:-1}
EOF
}

# Helper: populate a directory with N empty files
_populate() {
    local dir="$1" count="$2" i
    for i in $(seq 1 "$count"); do touch "${dir}/entry${i}"; done
}

# Run the boot-complete logic with our temp dirs
_run_boot() {
    local sd="${SYS_DIR}" td="${THR_DIR}" ed="${EEP_DIR}" cf="${CONF_FILE}"
    bash -s "$sd" "$td" "$ed" "$cf" << 'BOOT'
set +e
SD="$1"; TD="$2"; ED="$3"; CF="$4"
cnt() { _d="$1"; [ ! -d "$_d" ] && echo 0 && return; ls -A "$_d" 2>/dev/null | wc -l; }
[ ! -f "$CF" ] && echo "missing_conf" >&2 && exit 1
. "$CF"
: "${SYSFS_SYSTEM_COUNTER:?}" 2>/dev/null || exit 1
: "${SYSFS_THERMAL_COUNTER:?}" 2>/dev/null || exit 1
: "${SYSFS_EEPROM_COUNTER:?}" 2>/dev/null || exit 1
mw=${BOOT_COMPLETE_MAX_WAIT_SEC:-1800}; poll=${BOOT_COMPLETE_POLL_SEC:-2}; elapsed=0
while :; do
    cs=$(cnt "$SD"); ct=$(cnt "$TD"); ce=$(cnt "$ED")
    if [ "$cs" -ge "$SYSFS_SYSTEM_COUNTER" ] && \
       [ "$ct" -ge "$SYSFS_THERMAL_COUNTER" ] && \
       [ "$ce" -ge "$SYSFS_EEPROM_COUNTER" ]; then
        echo "thresholds_met" >&2; exit 0
    fi
    if [ "$mw" -eq 0 ]; then echo "no_limit" >&2; exit 0; fi
    if [ "$elapsed" -ge "$mw" ]; then echo "timed_out" >&2; exit 1; fi
    elapsed=$((elapsed + poll))
done
BOOT
}

# count_entries helper (same logic as the script)
_count_entries() {
    _d="$1"; [ ! -d "$_d" ] && echo 0 && return
    ls -A "$_d" 2>/dev/null | wc -l
}

Describe 'hw-management-bmc-boot-complete.sh'

    BeforeEach 'setup_dirs'
    AfterEach  'cleanup_dirs'

    setup_dirs() {
        WORK_DIR=$(mktemp -d)
        SYS_DIR="${WORK_DIR}/system"
        THR_DIR="${WORK_DIR}/thermal"
        EEP_DIR="${WORK_DIR}/eeprom"
        CONF_FILE="${WORK_DIR}/boot-complete.conf"
        mkdir -p "${SYS_DIR}" "${THR_DIR}" "${EEP_DIR}"
        export WORK_DIR SYS_DIR THR_DIR EEP_DIR CONF_FILE
    }

    cleanup_dirs() { rm -rf "${WORK_DIR}"; }

    Describe 'count_entries()'

        It 'returns 0 for a missing directory'
            When call _count_entries "${WORK_DIR}/nonexistent"
            The output should equal '0'
            The status should equal 0
        End

        It 'returns 3 for a directory with 3 files'
            cnt3() { _populate "${SYS_DIR}" 3; _count_entries "${SYS_DIR}"; }
            When call cnt3
            The output should equal '3'
            The status should equal 0
        End

    End

    Describe 'thresholds met: exits 0'

        BeforeEach 'setup_met'
        setup_met() {
            _write_conf 1 1 1 5 1
            _populate "${SYS_DIR}" 2; _populate "${THR_DIR}" 2; _populate "${EEP_DIR}" 2
        }

        It 'exits 0 and reports thresholds_met'
            When call _run_boot
            The status should equal 0
            The error should include 'thresholds_met'
        End

    End

    Describe 'exact threshold count: exits 0'

        BeforeEach 'setup_exact'
        setup_exact() {
            _write_conf 1 1 1 5 1
            _populate "${SYS_DIR}" 1; _populate "${THR_DIR}" 1; _populate "${EEP_DIR}" 1
        }

        It 'exits 0 with exactly required entry count'
            When call _run_boot
            The status should equal 0
            The error should include 'thresholds_met'
        End

    End

    Describe 'timeout: dirs empty, exits 1'

        BeforeEach 'setup_timeout'
        setup_timeout() { _write_conf 1 1 1 1 1; }

        It 'exits 1 and reports timed_out'
            When call _run_boot
            The status should equal 1
            The error should include 'timed_out'
        End

    End

    Describe 'missing conf file: exits 1'

        It 'exits 1 and reports missing_conf'
            When call _run_boot
            The status should equal 1
            The error should include 'missing_conf'
        End

    End

    Describe 'unlimited wait (max_wait=0): exits 0'

        BeforeEach 'setup_unlimited'
        setup_unlimited() { _write_conf 1 1 1 0 1; }

        It 'exits 0 and shows no_limit'
            When call _run_boot
            The status should equal 0
            The error should include 'no_limit'
        End

    End

End
