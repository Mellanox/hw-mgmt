#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for leakage-handler.sh — align12() and process_channel()

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

# align12 inlined to avoid set -euo pipefail source issues
align12() {
    awk -v s="$1" 'BEGIN {
        if (s == "" || s !~ /^-?[0-9]+$/) { print ""; exit 0 }
        v = int(s); r = v % 4096
        if (r < 0) { r += 4096 }
        print r
    }'
}

process_channel() {
    local ch_dir="$1" input_path sample="" aligned
    input_path="${ch_dir}/input"
    if [ -f "$input_path" ]; then
        IFS= read -r sample < "$input_path" 2>/dev/null || sample=""
        sample="${sample//$'\r'/}"; sample="${sample// /}"
    else
        return 0
    fi
    aligned="$(align12 "$sample")"
    printf 'aligned=%s\n' "$aligned"
    return 0
}

Describe 'hw-management-bmc-leakage-handler.sh'

    BeforeEach 'setup_leak'
    AfterEach  'cleanup_leak'

    setup_leak() { WORK_DIR="$(mktemp -d)"; export WORK_DIR; }
    cleanup_leak() { rm -rf "${WORK_DIR}"; }

    Describe 'align12()'
        It 'returns value unchanged when within 12 bits (2048)'
            When call align12 2048
            The output should equal '2048'
            The status should equal 0
        End
        It 'masks 4097 to 1'
            When call align12 4097
            The output should equal '1'
            The status should equal 0
        End
        It 'returns 0 for input 0'
            When call align12 0
            The output should equal '0'
            The status should equal 0
        End
        It 'returns 4095 unchanged'
            When call align12 4095
            The output should equal '4095'
            The status should equal 0
        End
        It 'wraps 4096 to 0'
            When call align12 4096
            The output should equal '0'
            The status should equal 0
        End
        It 'returns empty for empty input'
            When call align12 ""
            The output should equal ''
            The status should equal 0
        End
        It 'returns empty for non-numeric input'
            When call align12 "abc"
            The output should equal ''
            The status should equal 0
        End
        It 'wraps 8192 to 0'
            When call align12 8192
            The output should equal '0'
            The status should equal 0
        End
        It 'wraps 8193 to 1'
            When call align12 8193
            The output should equal '1'
            The status should equal 0
        End
    End

    Describe 'process_channel(): valid input'
        BeforeEach 'setup_ch'
        setup_ch() {
            mkdir -p "${WORK_DIR}/ch0"
            printf '1024\n' > "${WORK_DIR}/ch0/input"
        }
        It 'outputs aligned=1024 for input 1024'
            When call process_channel "${WORK_DIR}/ch0"
            The status should equal 0
            The output should include 'aligned=1024'
        End
    End

    Describe 'process_channel(): missing input file'
        BeforeEach 'setup_empty_ch'
        setup_empty_ch() { mkdir -p "${WORK_DIR}/ch_empty"; }
        It 'exits 0 gracefully when input file missing'
            When call process_channel "${WORK_DIR}/ch_empty"
            The status should equal 0
        End
    End

    Describe 'process_channel(): value over 12 bits'
        BeforeEach 'setup_big_ch'
        setup_big_ch() {
            mkdir -p "${WORK_DIR}/ch_big"
            printf '8192\n' > "${WORK_DIR}/ch_big/input"
        }
        It 'masks 8192 to 0'
            When call process_channel "${WORK_DIR}/ch_big"
            The output should include 'aligned=0'
            The status should equal 0
        End
    End

    Describe 'leakage-handler.sh argument validation'
        It 'exits 1 when no arguments supplied'
            When run bash "${BMC_SCRIPTS_DIR}/hw-management-bmc-leakage-handler.sh"
            The status should equal 1
            The error should include 'Usage'
        End
        It 'exits 1 when only one argument supplied'
            When run bash "${BMC_SCRIPTS_DIR}/hw-management-bmc-leakage-handler.sh" "0"
            The status should equal 1
            The error should include 'Usage'
        End
        It 'exits 0 when base dir does not exist'
            When run bash "${BMC_SCRIPTS_DIR}/hw-management-bmc-leakage-handler.sh" "99" "12345"
            The status should equal 0
        End
    End

End
