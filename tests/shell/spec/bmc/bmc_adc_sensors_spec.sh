#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for ADS1015, ADS7924, and MAX1363 read-status / force-alarm scripts.

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

_stub_path() {
    local sd
    sd="$(mktemp -d)"
    for cmd in logger i2ctransfer i2cset i2cget systemctl systemd-cat; do
        printf '#!/bin/sh\nexit 0\n' > "${sd}/${cmd}"
        chmod +x "${sd}/${cmd}"
    done
    printf '%s\n' "$sd"
}

Describe 'ADC sensor scripts'

    BeforeEach 'setup_stubs'
    AfterEach  'cleanup_stubs'

    setup_stubs() {
        STUB_DIR="$(_stub_path)"
        export STUB_DIR
        export PATH="${STUB_DIR}:${PATH}"
    }
    cleanup_stubs() { rm -rf "${STUB_DIR}"; }

    Describe 'hw-management-bmc-ads1015-read-status.sh'

        ADS1015="${BMC_SCRIPTS_DIR}/hw-management-bmc-ads1015-read-status.sh"

        It 'script file exists'
            The path "${ADS1015}" should be exist
        End

        It 'exits 1 and shows Usage when no arguments given'
            When run bash "${ADS1015}"
            The status should equal 1
            The output should include 'Usage'
        End

        It 'exits 1 and shows Usage when only bus argument given'
            When run bash "${ADS1015}" "12"
            The status should equal 1
            The output should include 'Usage'
        End

        It 'exits 1 for invalid channel 0'
            When run bash "${ADS1015}" "12" "0x49" "0"
            The status should equal 1
            The output should include 'Invalid channel'
        End

        It 'exits 1 for invalid channel 5'
            When run bash "${ADS1015}" "12" "0x49" "5"
            The status should equal 1
            The output should include 'Invalid channel'
        End

        It 'exits non-zero with no hardware for valid bus/addr'
            When run bash "${ADS1015}" "12" "0x49"
            The status should not equal 0
            The output should not equal ''
        End

    End

    Describe 'hw-management-bmc-ads1015-force-alarm.sh'

        ADS1015A="${BMC_SCRIPTS_DIR}/hw-management-bmc-ads1015-force-alarm.sh"

        It 'script file exists'
            The path "${ADS1015A}" should be exist
        End

        It 'exits non-zero and shows Usage when no arguments given'
            When run bash "${ADS1015A}"
            The status should not equal 0
            The output should include 'Usage'
        End

    End

    Describe 'hw-management-bmc-ads7924-read-status.sh'

        ADS7924="${BMC_SCRIPTS_DIR}/hw-management-bmc-ads7924-read-status.sh"

        It 'script file exists'
            The path "${ADS7924}" should be exist
        End

        It 'exits non-zero and shows Usage when no arguments given'
            When run bash "${ADS7924}"
            The status should not equal 0
            The output should include 'Usage'
        End

    End

    Describe 'hw-management-bmc-ads7924-force-alarm.sh'

        ADS7924A="${BMC_SCRIPTS_DIR}/hw-management-bmc-ads7924-force-alarm.sh"

        It 'script file exists'
            The path "${ADS7924A}" should be exist
        End

        It 'exits non-zero and shows Usage when no arguments given'
            When run bash "${ADS7924A}"
            The status should not equal 0
            The output should include 'Usage'
        End

    End

    Describe 'hw-management-bmc-max1363-read-status.sh'

        MAX1363="${BMC_SCRIPTS_DIR}/hw-management-bmc-max1363-read-status.sh"

        It 'script file exists'
            The path "${MAX1363}" should be exist
        End

        It 'exits non-zero and shows Usage when no arguments given'
            When run bash "${MAX1363}"
            The status should not equal 0
            The output should include 'Usage'
        End

    End

    Describe 'hw-management-bmc-max1363-force-alarm.sh'

        MAX1363A="${BMC_SCRIPTS_DIR}/hw-management-bmc-max1363-force-alarm.sh"

        It 'script file exists'
            The path "${MAX1363A}" should be exist
        End

        It 'exits non-zero and shows Usage when no arguments given'
            When run bash "${MAX1363A}"
            The status should not equal 0
            The output should include 'Usage'
        End

    End

End
