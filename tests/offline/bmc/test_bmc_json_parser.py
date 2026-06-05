#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-json-parser.sh — pure AWK logic, no hardware needed."""

import json
import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

PARSER = str(BMC_SCRIPTS_DIR / "hw-management-bmc-json-parser.sh")

SAMPLE_ARRAY = """[
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
    "Name": "sensor c with spaces",
    "Active": true
  }
]
"""

NESTED_JSON = """{
  "Devices": [
    { "chip": "ads1015", "bus": 12 },
    { "chip": "ads7924", "bus": 13 }
  ]
}
"""


def _src(func_call):
    return f"source {PARSER}; {func_call}"


def _run(snippet, input_text=None):
    return subprocess.run(
        ["bash", "-c", snippet],
        input=input_text,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True,
    )


class TestJsonGetArrayElement:
    def test_index_zero_returns_first_object(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        r = _run(_src(f'json_get_array_element "{f}" 0'))
        assert r.returncode == 0
        assert '"sensor_a"' in r.stdout

    def test_index_one_returns_second_object(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        r = _run(_src(f'json_get_array_element "{f}" 1'))
        assert '"sensor_b"' in r.stdout

    def test_index_two_returns_third_object(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        r = _run(_src(f'json_get_array_element "{f}" 2'))
        assert '"sensor c with spaces"' in r.stdout

    def test_out_of_range_returns_empty(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        r = _run(_src(f'json_get_array_element "{f}" 99'))
        assert r.stdout.strip() == ""

    def test_missing_file_produces_no_output(self, tmp_path):
        r = _run(_src(f'json_get_array_element "{tmp_path}/nonexistent.json" 0'))
        assert r.stdout.strip() == ""


class TestJsonGetString:
    def test_extracts_string_value(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        elem = subprocess.run(
            ["bash", "-c", _src(f'json_get_array_element "{f}" 0')],
            stdout=subprocess.PIPE, universal_newlines=True,
        ).stdout
        r = _run(_src('json_get_string "Name"'), input_text=elem)
        assert r.stdout.strip() == "sensor_a"

    def test_extracts_addr_string(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        elem = subprocess.run(
            ["bash", "-c", _src(f'json_get_array_element "{f}" 0')],
            stdout=subprocess.PIPE, universal_newlines=True,
        ).stdout
        r = _run(_src('json_get_string "Addr"'), input_text=elem)
        assert r.stdout.strip() == "0x48"

    def test_missing_key_returns_empty(self):
        r = _run(_src('json_get_string "NoSuchKey"'), input_text='{"Name": "x"}')
        assert r.stdout.strip() == ""

    def test_value_with_spaces(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        elem = subprocess.run(
            ["bash", "-c", _src(f'json_get_array_element "{f}" 2')],
            stdout=subprocess.PIPE, universal_newlines=True,
        ).stdout
        r = _run(_src('json_get_string "Name"'), input_text=elem)
        assert r.stdout.strip() == "sensor c with spaces"


class TestJsonGetNumber:
    def test_extracts_integer(self):
        r = _run(_src('json_get_number "Bus"'), input_text='{"Bus": 12, "other": 99}')
        assert r.stdout.strip() == "12"

    def test_extracts_correct_key_not_first_number(self):
        r = _run(_src('json_get_number "Scale"'), input_text='{"Bus": 5, "NumChnl": 4, "Scale": 7}')
        assert r.stdout.strip() == "7"

    def test_missing_key_returns_empty(self):
        r = _run(_src('json_get_number "Missing"'), input_text='{"Bus": 1}')
        assert r.stdout.strip() == ""

    def test_negative_number(self):
        r = _run(_src('json_get_number "Offset"'), input_text='{"Offset": -3}')
        assert r.stdout.strip() == "-3"


class TestJsonGetBool:
    def test_true_value(self):
        r = _run(_src('json_get_bool "Active"'), input_text='{"Active": true}')
        assert r.stdout.strip() == "true"
        assert r.returncode == 0

    def test_false_value(self):
        r = _run(_src('json_get_bool "Active"'), input_text='{"Active": false}')
        assert r.stdout.strip() == "false"
        assert r.returncode == 0

    def test_missing_key_nonzero_exit(self):
        r = _run(_src('json_get_bool "Missing"'), input_text='{"Active": true}')
        assert r.returncode != 0


class TestJsonCountArrayElements:
    def test_three_element_array(self, tmp_path):
        f = tmp_path / "a.json"
        f.write_text(SAMPLE_ARRAY)
        r = _run(_src(f'json_count_array_elements "{f}"'))
        assert r.stdout.strip() == "3"

    def test_single_element(self, tmp_path):
        f = tmp_path / "single.json"
        f.write_text('[{"Bus": 1}]')
        r = _run(_src(f'json_count_array_elements "{f}"'))
        assert r.stdout.strip() == "1"

    def test_empty_array(self, tmp_path):
        f = tmp_path / "empty.json"
        f.write_text("[]")
        r = _run(_src(f'json_count_array_elements "{f}"'))
        assert r.stdout.strip() == "0"


class TestJsonValidate:
    def test_valid_json_exits_zero(self, tmp_path):
        f = tmp_path / "v.json"
        f.write_text(SAMPLE_ARRAY)
        r = _run(_src(f'json_validate "{f}"; echo $?'))
        assert r.stdout.strip() == "0"

    def test_unbalanced_braces_exits_nonzero(self, tmp_path):
        f = tmp_path / "bad.json"
        f.write_text('[{"key": "val"')
        r = _run(_src(f'json_validate "{f}"; echo $?'))
        assert r.stdout.strip() == "1"

    def test_missing_file_exits_nonzero(self, tmp_path):
        r = _run(_src(f'json_validate "{tmp_path}/no.json"; echo $?'))
        assert r.stdout.strip() == "1"


class TestJsonGetNestedArrayElement:
    def test_first_nested_element(self):
        r = _run(_src('json_get_nested_array_element "Devices" 0'), input_text=NESTED_JSON)
        assert '"ads1015"' in r.stdout

    def test_second_nested_element(self):
        r = _run(_src('json_get_nested_array_element "Devices" 1'), input_text=NESTED_JSON)
        assert '"ads7924"' in r.stdout

    def test_out_of_range_returns_empty(self):
        r = _run(_src('json_get_nested_array_element "Devices" 5'), input_text=NESTED_JSON)
        assert r.stdout.strip() == ""


class TestJsonGetArray:
    def test_extracts_string_array_elements(self):
        # json_get_array requires each element on its own line
        data = '{"Tags": [\n  "alpha",\n  "beta",\n  "gamma"\n]}'
        r = _run(_src('json_get_array "Tags"'), input_text=data)
        lines = [l.strip() for l in r.stdout.strip().splitlines() if l.strip()]
        assert "alpha" in lines
        assert "beta" in lines
        assert "gamma" in lines
