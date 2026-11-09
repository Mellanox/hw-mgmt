#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Unit tests for g_get_range_val()/g_get_dmin() (Bug SW #5399964).
# Temperatures outside the table (e.g. TEMP_NA_VAL=255 before the first
# successful ambient read) must not crash thermal control; they must be
# clamped to the nearest range so the read-error cooling rule applies.
# Covers both TC 2.0 (hw_management_thermal_control) and
# TC 2.5 (hw_management_thermal_control_2_5).

import importlib
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"
if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

pytestmark = pytest.mark.offline

TABLE = {"-127:20": 30, "21:25": 40, "26:30": 50, "31:120": 60}
GAP_TABLE = {"0:10": 10, "20:30": 20}


@pytest.fixture(params=["hw_management_thermal_control", "hw_management_thermal_control_2_5"])
def tc(request):
    """Run each test against both thermal control versions."""
    return importlib.import_module(request.param)


@pytest.fixture
def tc25():
    return importlib.import_module("hw_management_thermal_control_2_5")


# ----------------------------------------------------------------------
# g_get_range_val
# ----------------------------------------------------------------------
@pytest.mark.parametrize("value, expected", [
    (-127, (30, -127, 20)),   # negative lower bound
    (-5, (30, -127, 20)),
    (20, (30, -127, 20)),     # boundaries are inclusive
    (21, (40, 21, 25)),
    (28, (50, 26, 30)),
    (120, (60, 31, 120)),
])
def test_range_match(tc, value, expected):
    assert tc.g_get_range_val(TABLE, value) == expected


@pytest.mark.parametrize("value, expected", [
    (-200, (30, -127, -127)),  # below lowest range
    (121, (60, 120, 120)),     # above highest range
    (255, (60, 120, 120)),     # TEMP_NA_VAL
])
def test_range_clamped(tc, value, expected):
    assert tc.g_get_range_val(TABLE, value) == expected


@pytest.mark.parametrize("value", [-200, 121, 255])
def test_range_no_clamp_returns_none(tc, value):
    assert tc.g_get_range_val(TABLE, value, clamp=False) == (None, None, None)


def test_range_gap_returns_none(tc):
    assert tc.g_get_range_val(GAP_TABLE, 15) == (None, None, None)


@pytest.mark.parametrize("value", [None, "abc", "", [], {}])
def test_range_invalid_input(tc, value):
    assert tc.g_get_range_val(TABLE, value) == (None, None, None)


def test_range_numeric_string_input(tc):
    assert tc.g_get_range_val(TABLE, "22") == (40, 21, 25)


@pytest.mark.parametrize("line", [None, {}])
def test_range_empty_table(tc, line):
    assert tc.g_get_range_val(line, 25) == (None, None, None)


@pytest.mark.parametrize("line", [
    {"bad": 1},
    {"10-20": 1},
    {"a:b": 1},
    {"10:": 1},
    {1: 1},
])
def test_range_malformed_key(tc, line):
    assert tc.g_get_range_val(line, 15) == (None, None, None)


def test_range_zero_value_is_valid(tc):
    assert tc.g_get_range_val({"-127:120": 0}, 50) == (0, -127, 120)


# ----------------------------------------------------------------------
# g_get_dmin
# ----------------------------------------------------------------------
def test_dmin_read_err_table_normal_temp(tc):
    pwm = tc.g_get_dmin(tc.DMIN_TABLE_DEFAULT, 25, [tc.CONST.C2P, tc.CONST.SENSOR_READ_ERR])
    assert pwm == 100


def test_dmin_temp_na_val_does_not_crash(tc):
    """Bug 5399964: 255 is outside the table (max 120) - must not raise."""
    for flow_dir in (tc.CONST.C2P, tc.CONST.P2C):
        pwm = tc.g_get_dmin(tc.DMIN_TABLE_DEFAULT, tc.CONST.TEMP_NA_VAL,
                            [flow_dir, tc.CONST.SENSOR_READ_ERR])
        assert float(pwm) == 100


def test_dmin_missing_table_returns_pwm_min(tc):
    pwm = tc.g_get_dmin(tc.DMIN_TABLE_DEFAULT, 25, [tc.CONST.C2P, "no_such_cause"])
    assert pwm == tc.CONST.PWM_MIN


def test_dmin_value_above_table(tc):
    table = {"x": {"-127:20": 30, "21:120": 60}}
    assert float(tc.g_get_dmin(table, 300, ["x"])) == 60


def test_dmin_value_below_table(tc):
    table = {"x": {"-127:20": 30, "21:120": 60}}
    assert float(tc.g_get_dmin(table, -300, ["x"])) == 30


def test_dmin_no_match_does_not_crash_2_5(tc25):
    """Gap in the table: fall back instead of float(None) TypeError."""
    table = {"x": {"0:10": 10, "20:30": 20}}
    assert tc25.g_get_dmin(table, 15, ["x"]) == 20.0


def test_dmin_malformed_table_2_5(tc25):
    """Malformed table: fall back to PWM_MIN instead of crashing."""
    assert tc25.g_get_dmin({"x": {"bad": 10}}, 15, ["x"]) == tc25.CONST.PWM_MIN


# ----------------------------------------------------------------------
# TC 2.0 specifics: interpolation and the dmin == 0 case
# ----------------------------------------------------------------------
@pytest.fixture
def tc20():
    return importlib.import_module("hw_management_thermal_control")


INTERP_TABLE = {"t": {"-127:20": 30, "21:30": 40, "31:120": 60}}


def test_dmin_interpolated_top_range(tc20):
    """Top range has no next step: result is the plain dmin, also for 255."""
    assert tc20.g_get_dmin(INTERP_TABLE, 80, ["t"], interpolated=True) == 60
    assert tc20.g_get_dmin(INTERP_TABLE, 255, ["t"], interpolated=True) == 60


def test_dmin_interpolated_does_not_clamp_lookahead(tc20):
    """The lookahead must not clamp, otherwise 'max range reached' is lost."""
    assert tc20.g_get_range_val(INTERP_TABLE["t"], 121, clamp=False) == (None, None, None)


def test_dmin_interpolated_below_smooth_start(tc20):
    """Small step to the next range: smoothing starts late, plain dmin before it."""
    table = {"t": {"-127:20": 30, "21:30": 32, "31:120": 34}}
    assert tc20.g_get_dmin(table, 22, ["t"], interpolated=True) == 32


def test_dmin_interpolated_ramp(tc20):
    """Large step to the next range: PWM ramps up before the range boundary."""
    assert tc20.g_get_dmin(INTERP_TABLE, 30, ["t"], interpolated=True) == 58


def test_dmin_zero_pwm_is_not_failure(tc20):
    """dmin == 0 is a valid table value and must be returned as-is."""
    table = {"t": {"-127:50": 0, "51:120": 60}}
    assert tc20.g_get_dmin(table, 10, ["t"]) == 0


# ----------------------------------------------------------------------
# TC 2.5: ambient sensor read-error flow (the scenario from the bug)
# ----------------------------------------------------------------------
def _ambient_harness(tc25, value):
    h = SimpleNamespace()
    h.value = value
    h.flow_dir = tc25.CONST.C2P
    h.pwm = 30.0
    h.sensors_config = {tc25.CONST.SENSOR_READ_ERR: 60}
    h.get_fault_list_filtered = Mock(return_value=[tc25.CONST.SENSOR_READ_ERR])
    h._update_pwm = Mock()
    return h


def test_ambient_handle_err_with_temp_na_val(tc25):
    """No ambient read succeeded: value is still TEMP_NA_VAL (255)."""
    h = _ambient_harness(tc25, tc25.CONST.TEMP_NA_VAL)
    tc25.ambient_thermal_sensor.handle_err(
        h, tc25.DMIN_TABLE_DEFAULT, tc25.CONST.C2P, tc25.CONST.TEMP_NA_VAL)
    # read-error cooling rule applied instead of crashing
    assert h.pwm == 100
    h._update_pwm.assert_called_once()


def test_ambient_handle_err_without_fault(tc25):
    h = _ambient_harness(tc25, tc25.CONST.TEMP_NA_VAL)
    h.get_fault_list_filtered = Mock(return_value=[])
    tc25.ambient_thermal_sensor.handle_err(
        h, tc25.DMIN_TABLE_DEFAULT, tc25.CONST.C2P, tc25.CONST.TEMP_NA_VAL)
    assert h.pwm == 30.0
    h._update_pwm.assert_called_once()
