#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#

"""Tests for hw_management_thermal_control.py pure helper functions and classes.

Covers: str2bool, get_dict_val_by_path, g_get_range_val, g_get_dmin,
        add_missing_to_dict, iterate_err_counter, and CONST constants.
These are all isolated from hardware — no sysfs access required.
"""

import sys
import os
import pytest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))

import hw_management_thermal_control as tc


# ---------------------------------------------------------------------------
# TestStr2Bool
# ---------------------------------------------------------------------------
class TestStr2Bool:
    """Tests for str2bool()."""

    def test_bool_true_passthrough(self):
        assert tc.str2bool(True) is True

    def test_bool_false_passthrough(self):
        assert tc.str2bool(False) is False

    def test_int_nonzero_is_true(self):
        assert tc.str2bool(1) is True
        assert tc.str2bool(42) is True

    def test_int_zero_is_false(self):
        assert tc.str2bool(0) is False

    def test_string_yes(self):
        assert tc.str2bool("yes") is True
        assert tc.str2bool("YES") is True

    def test_string_true(self):
        assert tc.str2bool("true") is True
        assert tc.str2bool("True") is True

    def test_string_t(self):
        assert tc.str2bool("t") is True
        assert tc.str2bool("T") is True

    def test_string_y(self):
        assert tc.str2bool("y") is True

    def test_string_1(self):
        assert tc.str2bool("1") is True

    def test_string_no(self):
        assert tc.str2bool("no") is False
        assert tc.str2bool("NO") is False

    def test_string_false(self):
        assert tc.str2bool("false") is False

    def test_string_f(self):
        assert tc.str2bool("f") is False

    def test_string_n(self):
        assert tc.str2bool("n") is False

    def test_string_0(self):
        assert tc.str2bool("0") is False

    def test_unknown_string_returns_none(self):
        assert tc.str2bool("maybe") is None
        assert tc.str2bool("unknown") is None
        assert tc.str2bool("") is None


# ---------------------------------------------------------------------------
# TestGetDictValByPath
# ---------------------------------------------------------------------------
class TestGetDictValByPath:
    """Tests for get_dict_val_by_path()."""

    def test_single_level(self):
        d = {"a": 1, "b": 2}
        assert tc.get_dict_val_by_path(d, ["a"]) == 1

    def test_two_levels(self):
        d = {"level1": {"level2": "value"}}
        assert tc.get_dict_val_by_path(d, ["level1", "level2"]) == "value"

    def test_three_levels(self):
        d = {"l1": {"l2": {"l3": 42}}}
        assert tc.get_dict_val_by_path(d, ["l1", "l2", "l3"]) == 42

    def test_missing_key_returns_none(self):
        d = {"a": {"b": 1}}
        assert tc.get_dict_val_by_path(d, ["a", "z"]) is None

    def test_missing_top_level_returns_none(self):
        d = {"a": 1}
        assert tc.get_dict_val_by_path(d, ["z"]) is None

    def test_empty_path(self):
        d = {"a": 1}
        assert tc.get_dict_val_by_path(d, []) == {"a": 1}

    def test_nested_none_short_circuits(self):
        d = {"a": None}
        assert tc.get_dict_val_by_path(d, ["a", "b"]) is None

    def test_returns_dict_value(self):
        d = {"key": {"nested": "data"}}
        result = tc.get_dict_val_by_path(d, ["key"])
        assert result == {"nested": "data"}


# ---------------------------------------------------------------------------
# TestGGetRangeVal
# ---------------------------------------------------------------------------
class TestGGetRangeVal:
    """Tests for g_get_range_val()."""

    RANGES = {"-127:20": 30, "21:25": 40, "26:30": 50, "31:120": 60}

    def test_matches_first_range(self):
        val, lo, hi = tc.g_get_range_val(self.RANGES, 0)
        assert val == 30
        assert lo == -127
        assert hi == 20

    def test_matches_middle_range(self):
        val, lo, hi = tc.g_get_range_val(self.RANGES, 23)
        assert val == 40

    def test_matches_boundary_low(self):
        val, _, _ = tc.g_get_range_val(self.RANGES, 21)
        assert val == 40

    def test_matches_boundary_high(self):
        val, _, _ = tc.g_get_range_val(self.RANGES, 25)
        assert val == 40

    def test_matches_last_range(self):
        val, _, _ = tc.g_get_range_val(self.RANGES, 100)
        assert val == 60

    def test_no_match_returns_none_triple(self):
        val, lo, hi = tc.g_get_range_val(self.RANGES, 200)
        assert val is None
        assert lo is None
        assert hi is None

    def test_negative_input(self):
        val, _, _ = tc.g_get_range_val(self.RANGES, -50)
        assert val == 30

    def test_single_entry(self):
        r = {"0:100": 99}
        val, lo, hi = tc.g_get_range_val(r, 50)
        assert val == 99
        assert lo == 0
        assert hi == 100


# ---------------------------------------------------------------------------
# TestGGetDmin
# ---------------------------------------------------------------------------
class TestGGetDmin:
    """Tests for g_get_dmin() in thermal_control 2.0 (supports interpolated param)."""

    THERMAL_TABLE = {
        "C2P": {
            "trusted": {"-127:20": 30, "21:25": 40, "26:30": 50, "31:120": 60}
        }
    }

    def test_basic_lookup(self):
        result = tc.g_get_dmin(self.THERMAL_TABLE, 23, ["C2P", "trusted"])
        assert result == 40

    def test_missing_path_returns_pwm_min(self):
        result = tc.g_get_dmin(self.THERMAL_TABLE, 23, ["C2P", "nonexistent"])
        assert result == tc.CONST.PWM_MIN

    def test_empty_table_path_returns_pwm_min(self):
        result = tc.g_get_dmin({}, 23, ["C2P", "trusted"])
        assert result == tc.CONST.PWM_MIN

    def test_no_match_falls_back_to_100(self):
        # Value 200 → no match in range, falls back to range_val at 100
        result = tc.g_get_dmin(self.THERMAL_TABLE, 200, ["C2P", "trusted"])
        assert result == 60  # range "31:120" covers 100

    def test_interpolated_false_returns_exact(self):
        result = tc.g_get_dmin(self.THERMAL_TABLE, 22, ["C2P", "trusted"], interpolated=False)
        assert result == 40

    def test_interpolated_true_smooth_step(self):
        # At temp=25 (boundary of 21:25 range, next range 26:30 starts at 26)
        # interpolated=True may return value between 40 and 50
        result = tc.g_get_dmin(self.THERMAL_TABLE, 25, ["C2P", "trusted"], interpolated=True)
        assert isinstance(result, (int, float))

    def test_interpolated_max_range_returns_dmin(self):
        # At max range (31:120), no next step → returns dmin unchanged
        result = tc.g_get_dmin(self.THERMAL_TABLE, 80, ["C2P", "trusted"], interpolated=True)
        assert result == 60


# ---------------------------------------------------------------------------
# TestAddMissingToDict
# ---------------------------------------------------------------------------
class TestAddMissingToDict:
    """Tests for add_missing_to_dict()."""

    def test_adds_new_key(self):
        base = {"a": 1}
        tc.add_missing_to_dict(base, {"b": 2})
        assert base["b"] == 2

    def test_does_not_overwrite_existing(self):
        base = {"a": 1}
        tc.add_missing_to_dict(base, {"a": 99})
        assert base["a"] == 1

    def test_adds_multiple_new_keys(self):
        base = {"a": 1}
        tc.add_missing_to_dict(base, {"b": 2, "c": 3})
        assert base["b"] == 2
        assert base["c"] == 3

    def test_mixed_add_and_skip(self):
        base = {"a": 1, "b": 2}
        tc.add_missing_to_dict(base, {"b": 99, "c": 3})
        assert base["b"] == 2   # unchanged
        assert base["c"] == 3   # added

    def test_empty_new_dict_no_change(self):
        base = {"a": 1}
        tc.add_missing_to_dict(base, {})
        assert base == {"a": 1}

    def test_empty_base_gets_all(self):
        base = {}
        tc.add_missing_to_dict(base, {"x": 10, "y": 20})
        assert base == {"x": 10, "y": 20}


# ---------------------------------------------------------------------------
# TestIterateErrCounter
# ---------------------------------------------------------------------------
class TestIterateErrCounter:
    """Tests for iterate_err_counter class."""

    def _make_counter(self, err_max=5, warn_limit=32):
        mock_log = MagicMock()
        return tc.iterate_err_counter(mock_log, "test_counter", err_max, warn_limit), mock_log

    def test_initial_state_empty(self):
        ctr, _ = self._make_counter()
        assert ctr.get_err("nonexistent") == 0
        assert ctr.check_err() == []

    def test_handle_err_increments_count(self):
        ctr, _ = self._make_counter()
        ctr.handle_err("disk_err")
        assert ctr.get_err("disk_err") == 1

    def test_handle_err_twice_counts_two(self):
        ctr, _ = self._make_counter()
        ctr.handle_err("disk_err")
        ctr.handle_err("disk_err")
        assert ctr.get_err("disk_err") == 2

    def test_handle_err_reset_clears_count(self):
        ctr, _ = self._make_counter()
        ctr.handle_err("disk_err")
        ctr.handle_err("disk_err", reset=True)
        assert ctr.get_err("disk_err") == 0

    def test_check_err_returns_over_threshold(self):
        ctr, _ = self._make_counter(err_max=3)
        for _ in range(3):
            ctr.handle_err("psu_err")
        assert "psu_err" in ctr.check_err()

    def test_check_err_empty_below_threshold(self):
        ctr, _ = self._make_counter(err_max=5)
        ctr.handle_err("psu_err")
        assert ctr.check_err() == []

    def test_multiple_error_types_tracked_independently(self):
        ctr, _ = self._make_counter()
        ctr.handle_err("err_a")
        ctr.handle_err("err_b")
        ctr.handle_err("err_b")
        assert ctr.get_err("err_a") == 1
        assert ctr.get_err("err_b") == 2

    def test_reset_all_clears_everything(self):
        ctr, _ = self._make_counter()
        ctr.handle_err("err_a")
        ctr.handle_err("err_b")
        ctr.reset_all()
        assert ctr.get_err("err_a") == 0
        assert ctr.get_err("err_b") == 0
        assert ctr.check_err() == []

    def test_handle_err_with_cause(self):
        ctr, _ = self._make_counter()
        result = ctr.handle_err("fan_err", cause="sensor timeout")
        assert result is True

    def test_handle_err_exceeds_warn_limit_blocks(self):
        ctr, _ = self._make_counter(warn_limit=2)
        ctr.handle_err("err_a")
        ctr.handle_err("err_b")
        # Third unique error key — dict is at limit
        result = ctr.handle_err("err_c")
        assert result is False

    def test_get_err_unknown_returns_zero(self):
        ctr, _ = self._make_counter()
        assert ctr.get_err("nonexistent_error") == 0

    def test_handle_err_no_print_log(self):
        ctr, mock_log = self._make_counter()
        ctr.handle_err("err_x", print_log=False)
        # With print_log=False, log methods should not be called on first error
        # (err_cnt < err_max initially so the log would normally trigger — but print_log=False skips it)
        mock_log.notice.assert_not_called()


# ---------------------------------------------------------------------------
# TestCONSTClass
# ---------------------------------------------------------------------------
class TestCONSTClass:
    """Verify key CONST values are sane."""

    def test_pwm_min_is_defined(self):
        assert hasattr(tc.CONST, 'PWM_MIN')

    def test_hw_mgmt_folder_default(self):
        assert tc.CONST.HW_MGMT_FOLDER_DEF == "/var/run/hw-management"

    def test_temp_sensor_scale(self):
        assert tc.CONST.TEMP_SENSOR_SCALE == 1000.0

    def test_fan_dir_strings(self):
        assert tc.CONST.C2P == "C2P"
        assert tc.CONST.P2C == "P2C"

    def test_temp_na_val(self):
        assert tc.CONST.TEMP_NA_VAL == 255


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
