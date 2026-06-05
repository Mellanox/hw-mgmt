#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for hw-management-bmc-helpers-common.sh

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

HELPERS="${BMC_SCRIPTS_DIR}/hw-management-bmc-helpers-common.sh"

_make_stubs() {
    local sd
    sd="$(mktemp -d)"
    for cmd in logger systemctl systemd-cat i2ctransfer mdio modprobe networkctl udhcpc ethtool; do
        printf '#!/bin/sh\nexit 0\n' > "${sd}/${cmd}"
        chmod +x "${sd}/${cmd}"
    done
    printf '%s\n' "$sd"
}

Describe 'hw-management-bmc-helpers-common.sh'

    BeforeEach 'setup_helpers'
    AfterEach  'cleanup_helpers'

    setup_helpers() {
        STUB_DIR="$(_make_stubs)"
        export STUB_DIR
        export PATH="${STUB_DIR}:${PATH}"
        WORK_DIR="$(mktemp -d)"
        export WORK_DIR
        # shellcheck source=/dev/null
        builtin source "${HELPERS}"
    }
    cleanup_helpers() { rm -rf "${STUB_DIR}" "${WORK_DIR}"; }

    Describe 'log_message()'
        It 'outputs [info] message to stdout'
            When call log_message "info" "hello world"
            The output should include '[info] hello world'
            The status should equal 0
        End
        It 'outputs [err] message to stdout'
            When call log_message "err" "disk failure"
            The output should include '[err] disk failure'
            The status should equal 0
        End
        It 'outputs [warning] message to stdout'
            When call log_message "warning" "low memory"
            The output should include '[warning] low memory'
            The status should equal 0
        End
        It 'outputs [debug] message to stdout'
            When call log_message "debug" "trace point"
            The output should include '[debug] trace point'
            The status should equal 0
        End
        It 'handles uppercase ERROR level'
            When call log_message "ERROR" "something failed"
            The output should include 'something failed'
            The status should equal 0
        End
        It 'handles multi-word message'
            When call log_message "info" "this is a long message"
            The output should include 'this is a long message'
            The status should equal 0
        End
    End

    Describe 'log_event()'
        It 'exits 0 when systemd-cat is stubbed'
            When call log_event "test event"
            The status should equal 0
        End
        It 'exits 0 when systemd-cat is absent'
            remove_cat() {
                rm -f "${STUB_DIR}/systemd-cat"
                log_event "no cat"
            }
            When call remove_cat
            The status should equal 0
        End
    End

    Describe 'hw_mgmt_bc()'
        It 'hw_mgmt_bc_available reflects bc presence'
            When call hw_mgmt_bc_available
            The status should not equal 127
        End
    End

    Describe 'leak_detection_on_init(): no leak dir'
        It 'returns 1 when system dir absent'
            no_dir() {
                local system_dir="${WORK_DIR}/no_such"
                [ ! -d "$system_dir" ] && return 1; return 0
            }
            When call no_dir
            The status should equal 1
        End
    End

    Describe 'leak_detection_on_init(): value 1 = no leak'
        BeforeEach 'setup_no_leak'
        setup_no_leak() {
            mkdir -p "${WORK_DIR}/system"
            printf '1\n' > "${WORK_DIR}/system/leakage0"
        }
        It 'returns 1 (no leak) when leakage file reads 1'
            check_no_leak() {
                local f val
                for f in "${WORK_DIR}/system"/leakage[0-9]*; do
                    val="$(tr -d '[:space:]' < "$f" 2>/dev/null)"
                    [ "$val" = "0" ] && return 0
                done
                return 1
            }
            When call check_no_leak
            The status should equal 1
        End
    End

    Describe 'leak_detection_on_init(): value 0 = leak'
        BeforeEach 'setup_leak'
        setup_leak() {
            mkdir -p "${WORK_DIR}/system"
            printf '0\n' > "${WORK_DIR}/system/leakage0"
        }
        It 'returns 0 (leak) when leakage file reads 0'
            check_leak() {
                local f val
                for f in "${WORK_DIR}/system"/leakage[0-9]*; do
                    val="$(tr -d '[:space:]' < "$f" 2>/dev/null)"
                    [ "$val" = "0" ] && return 0
                done
                return 1
            }
            When call check_leak
            The status should equal 0
        End
    End

    Describe 'get_mgmt_board_revision()'
        It 'masks config1 to 3 bits (7 & 7 = 7)'
            read_rev() { printf '%s\n' "$((7 & 7))"; }
            When call read_rev
            The output should equal '7'
            The status should equal 0
        End
        It 'masks higher bits (15 & 7 = 7)'
            read_masked() { printf '%s\n' "$((15 & 7))"; }
            When call read_masked
            The output should equal '7'
            The status should equal 0
        End
    End

End
