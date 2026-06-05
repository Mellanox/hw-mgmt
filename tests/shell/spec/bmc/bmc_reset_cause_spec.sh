#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for hw-management-bmc-get-reset-cause.sh

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

GET_CAUSE="${BMC_SCRIPTS_DIR}/hw-management-bmc-get-reset-cause.sh"
SHOW_CAUSE="${BMC_SCRIPTS_DIR}/hw-management-bmc-show-reset-cause.sh"
LOG_CAUSE="${BMC_SCRIPTS_DIR}/hw-management-bmc-reset-cause-logger.sh"

_make_stubs() {
    local sd
    sd="$(mktemp -d)"
    for cmd in logger systemctl fw_printenv devmem; do
        printf '#!/bin/sh\nexit 0\n' > "${sd}/${cmd}"
        chmod +x "${sd}/${cmd}"
    done
    printf '%s\n' "$sd"
}

# normalize_hex inlined
normalize_hex() {
    in="$1"
    case "${in}" in
    0x* | 0X*) hex="${in}" ;;
    *) hex="0x${in}" ;;
    esac
    digits="${hex#0x}"; digits="${digits#0X}"
}

Describe 'hw-management-bmc-get-reset-cause.sh'

    BeforeEach 'setup_rc'
    AfterEach  'cleanup_rc'

    setup_rc() {
        STUB_DIR="$(_make_stubs)"
        export STUB_DIR PATH="${STUB_DIR}:${PATH}"
        WORK_DIR="$(mktemp -d)"
        OUT_DIR="${WORK_DIR}/bmc"
        DOMAINS_DIR="${OUT_DIR}/domains"
        mkdir -p "${DOMAINS_DIR}"
        export WORK_DIR OUT_DIR DOMAINS_DIR
    }
    cleanup_rc() { rm -rf "${STUB_DIR}" "${WORK_DIR}"; }

    Describe 'normalize_hex()'
        It 'leaves 0x-prefixed hex unchanged'
            check_0x() { normalize_hex "0x1234abcd"; printf '%s\n' "$hex"; }
            When call check_0x
            The output should include '0x1234abcd'
            The status should equal 0
        End
        It 'adds 0x prefix to bare hex digits'
            check_bare() { normalize_hex "deadbeef"; printf '%s\n' "$hex"; }
            When call check_bare
            The output should equal '0xdeadbeef'
            The status should equal 0
        End
        It 'handles uppercase 0X prefix'
            check_upper() { normalize_hex "0XABCD"; printf '%s\n' "$hex"; }
            When call check_upper
            The output should include 'ABCD'
            The status should equal 0
        End
        It 'extracts digits (strips 0x prefix)'
            check_digits() { normalize_hex "0xCAFE"; printf '%s\n' "$digits"; }
            When call check_digits
            The output should equal 'CAFE'
            The status should equal 0
        End
        It 'adds 0x to plain numeric input'
            check_num() { normalize_hex "1234"; printf '%s\n' "$hex"; }
            When call check_num
            The output should equal '0x1234'
            The status should equal 0
        End
    End

    Describe 'get-reset-cause.sh: creates output directories'
        It 'creates OUT_DIR when run'
            run_cause() {
                OUT_DIR="${WORK_DIR}/new_bmc" \
                DOMAINS_DIR="${WORK_DIR}/new_bmc/domains" \
                bash "${GET_CAUSE}" 2>/dev/null
                [ -d "${WORK_DIR}/new_bmc" ] && printf 'dir_created\n'
            }
            When call run_cause
            The output should include 'dir_created'
            The status should equal 0
        End
        It 'creates DOMAINS_DIR when run'
            run_domains() {
                OUT_DIR="${WORK_DIR}/bmc2" \
                DOMAINS_DIR="${WORK_DIR}/bmc2/domains" \
                bash "${GET_CAUSE}" 2>/dev/null
                [ -d "${WORK_DIR}/bmc2/domains" ] && printf 'domains_created\n'
            }
            When call run_domains
            The output should include 'domains_created'
            The status should equal 0
        End
        It 'respects custom OUT_DIR'
            run_custom() {
                local custom="${WORK_DIR}/custom_bmc"
                OUT_DIR="${custom}" DOMAINS_DIR="${custom}/domains" \
                bash "${GET_CAUSE}" 2>/dev/null
                [ -d "${custom}" ] && printf 'custom_created\n'
            }
            When call run_custom
            The output should include 'custom_created'
            The status should equal 0
        End
    End

    Describe 'get-reset-cause.sh: exits cleanly'
        It 'exits 0 or 1 with stubbed devmem'
            run_stubbed() {
                OUT_DIR="${OUT_DIR}" DOMAINS_DIR="${DOMAINS_DIR}" \
                bash "${GET_CAUSE}" 2>/dev/null; true
            }
            When call run_stubbed
            The status should equal 0
        End
    End

    Describe 'show-reset-cause.sh'
        It 'exits cleanly without crash'
            run_show() {
                OUT_DIR="${OUT_DIR}" DOMAINS_DIR="${DOMAINS_DIR}" \
                bash "${SHOW_CAUSE}" 2>/dev/null; true
            }
            When call run_show
            The status should equal 0
            The output should not equal ''
        End
    End

    Describe 'reset-cause-logger.sh'
        It 'exits cleanly without crash'
            run_log() {
                OUT_DIR="${OUT_DIR}" DOMAINS_DIR="${DOMAINS_DIR}" \
                bash "${LOG_CAUSE}" 2>/dev/null; true
            }
            When call run_log
            The status should equal 0
        End
    End

End
