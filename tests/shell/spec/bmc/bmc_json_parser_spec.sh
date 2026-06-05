#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for hw-management-bmc-json-parser.sh

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

PARSER="${BMC_SCRIPTS_DIR}/hw-management-bmc-json-parser.sh"

SAMPLE_JSON='[
  {
    "Bus": 1,
    "Addr": "0x48",
    "Name": "sensor_a",
    "Active": true
  },
  {
    "Bus": 2,
    "Addr": "0x49",
    "Name": "sensor_b",
    "Active": false
  },
  {
    "Bus": 3,
    "Addr": "0x4a",
    "Name": "sensor c",
    "Active": true
  }
]'

Describe 'hw-management-bmc-json-parser.sh'

    BeforeEach 'setup_parser'
    AfterEach  'cleanup_parser'

    setup_parser() {
        WORK_DIR=$(mktemp -d)
        export WORK_DIR
        printf '%s\n' "$SAMPLE_JSON" > "${WORK_DIR}/sample.json"
        printf '[{"Bus": 1}]\n' > "${WORK_DIR}/single.json"
        printf '[]\n' > "${WORK_DIR}/empty.json"
        printf '[{"key": "val"\n' > "${WORK_DIR}/bad.json"
        # shellcheck source=/dev/null
        builtin source "${PARSER}"
    }

    cleanup_parser() { rm -rf "${WORK_DIR}"; }

    Describe 'json_get_array_element()'

        It 'returns the first object (index 0)'
            When call json_get_array_element "${WORK_DIR}/sample.json" 0
            The status should equal 0
            The output should include '"sensor_a"'
        End

        It 'returns the second object (index 1)'
            When call json_get_array_element "${WORK_DIR}/sample.json" 1
            The output should include '"sensor_b"'
        End

        It 'returns the third object (index 2)'
            When call json_get_array_element "${WORK_DIR}/sample.json" 2
            The output should include '"sensor c"'
        End

        It 'returns empty output for out-of-range index'
            When call json_get_array_element "${WORK_DIR}/sample.json" 99
            The output should equal ''
        End

        It 'returns empty output for missing file'
            missing_file() { json_get_array_element "${WORK_DIR}/nonexistent.json" 0 2>/dev/null; }
            When call missing_file
            The output should equal ''
            The status should not equal 0
        End

    End

    Describe 'json_get_string()'

        It 'extracts Name from first element'
            extract_name() { json_get_array_element "${WORK_DIR}/sample.json" 0 | json_get_string "Name"; }
            When call extract_name
            The output should equal 'sensor_a'
        End

        It 'extracts Addr from first element'
            extract_addr() { json_get_array_element "${WORK_DIR}/sample.json" 0 | json_get_string "Addr"; }
            When call extract_addr
            The output should equal '0x48'
        End

        It 'returns empty for missing key'
            missing_key() { printf '{"Name": "x"}\n' | json_get_string "NoSuchKey"; }
            When call missing_key
            The output should equal ''
        End

    End

    Describe 'json_get_number()'

        It 'extracts integer value for Bus'
            extract_bus() { printf '{"Bus": 12}\n' | json_get_number "Bus"; }
            When call extract_bus
            The output should equal '12'
        End

        It 'extracts correct key when multiple numbers exist'
            extract_scale() { printf '{"Bus": 5, "NumChnl": 4, "Scale": 7}\n' | json_get_number "Scale"; }
            When call extract_scale
            The output should equal '7'
        End

        It 'returns empty for missing key'
            missing_num() { printf '{"Bus": 1}\n' | json_get_number "Missing"; }
            When call missing_num
            The output should equal ''
        End

    End

    Describe 'json_get_bool()'

        It 'returns true for a true boolean'
            get_true() { printf '{"Active": true}\n' | json_get_bool "Active"; }
            When call get_true
            The status should equal 0
            The output should equal 'true'
        End

        It 'returns false for a false boolean'
            get_false() { printf '{"Active": false}\n' | json_get_bool "Active"; }
            When call get_false
            The status should equal 0
            The output should equal 'false'
        End

        It 'exits non-zero for missing key'
            get_missing() { printf '{"Active": true}\n' | json_get_bool "Missing"; }
            When call get_missing
            The status should not equal 0
        End

    End

    Describe 'json_count_array_elements()'

        It 'counts 3 elements in the sample array'
            When call json_count_array_elements "${WORK_DIR}/sample.json"
            The output should equal '3'
        End

        It 'counts 1 element in a single-element array'
            When call json_count_array_elements "${WORK_DIR}/single.json"
            The output should equal '1'
        End

        It 'counts 0 elements in an empty array'
            When call json_count_array_elements "${WORK_DIR}/empty.json"
            The output should equal '0'
        End

    End

    Describe 'json_validate()'

        It 'exits 0 for valid JSON'
            validate_ok() { json_validate "${WORK_DIR}/sample.json"; }
            When call validate_ok
            The status should equal 0
        End

        It 'exits 1 for unbalanced braces'
            validate_bad() { json_validate "${WORK_DIR}/bad.json"; }
            When call validate_bad
            The status should equal 1
        End

        It 'exits 1 for missing file'
            validate_missing() { json_validate "${WORK_DIR}/no.json"; }
            When call validate_missing
            The status should equal 1
        End

    End

    Describe 'json_get_array()'

        It 'extracts string array elements one per line'
            get_tags() { printf '{"Tags": [\n  "alpha",\n  "beta",\n  "gamma"\n]}\n' | json_get_array "Tags"; }
            When call get_tags
            The output should include 'alpha'
            The output should include 'beta'
            The output should include 'gamma'
        End

    End

    Describe 'json_get_nested_array_element()'

        NESTED='{"Devices": [
  { "chip": "ads1015", "bus": 12 },
  { "chip": "ads7924", "bus": 13 }
]}'

        It 'returns first nested element'
            get_first() { printf '%s\n' "$NESTED" | json_get_nested_array_element "Devices" 0; }
            When call get_first
            The output should include '"ads1015"'
        End

        It 'returns second nested element'
            get_second() { printf '%s\n' "$NESTED" | json_get_nested_array_element "Devices" 1; }
            When call get_second
            The output should include '"ads7924"'
        End

        It 'returns empty for out-of-range index'
            get_oor() { printf '%s\n' "$NESTED" | json_get_nested_array_element "Devices" 5; }
            When call get_oor
            The output should equal ''
        End

    End

End
