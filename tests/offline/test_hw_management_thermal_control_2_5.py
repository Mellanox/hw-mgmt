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

"""Tests for hw_management_thermal_control_2_5.py pure helper functions.

Covers: natural_key, str2bool, get_dict_val_by_path, g_get_range_val, g_get_dmin,
        add_missing_to_dict, iterate_err_counter, and CONST constants.
Note: g_get_dmin in 2.5 has NO interpolated param; returns float(dmin).
"""

import sys
import os
import types
import pytest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))

import hw_management_thermal_control_2_5 as tc25


def _name_obj(name):
    """Create a minimal object with a .name attribute (for natural_key)."""
    obj = types.SimpleNamespace()
    obj.name = name
    return obj


# ---------------------------------------------------------------------------
# TestNaturalKey
# ---------------------------------------------------------------------------
class TestNaturalKey:
    """Tests for natural_key() — used for natural sorting of named objects."""

    def test_pure_text_returns_text_chunks(self):
        result = tc25.natural_key(_name_obj("abc"))
        assert result == ["abc"]

    def test_text_then_number(self):
        result = tc25.natural_key(_name_obj("fan10"))
        assert result == ["fan", 10, ""]

    def test_number_first(self):
        result = tc25.natural_key(_name_obj("10fan"))
        assert result == ["", 10, "fan"]

    def test_numeric_only(self):
        result = tc25.natural_key(_name_obj("42"))
        assert result == ["", 42, ""]

    def test_multiple_numbers(self):
        result = tc25.natural_key(_name_obj("fan3slot12"))
        assert result == ["fan", 3, "slot", 12, ""]

    def test_sorts_numerically_not_lexicographically(self):
        names = ["fan10", "fan2", "fan1"]
        sorted_names = sorted(names, key=lambda n: tc25.natural_key(_name_obj(n)))
        assert sorted_names == ["fan1", "fan2", "fan10"]

    def test_leading_trailing_spaces_stripped(self):
        result = tc25.natural_key(_name_obj("  fan1  "))
        assert result == ["fan", 1, ""]


# ---------------------------------------------------------------------------
# TestStr2Bool
# ---------------------------------------------------------------------------
class TestStr2Bool:
    """Tests for str2bool() in 2.5."""

    def test_bool_true_passthrough(self):
        assert tc25.str2bool(True) is True

    def test_bool_false_passthrough(self):
        assert tc25.str2bool(False) is False

    def test_int_nonzero_is_true(self):
        assert tc25.str2bool(1) is True

    def test_int_zero_is_false(self):
        assert tc25.str2bool(0) is False

    def test_string_yes(self):
        assert tc25.str2bool("YES") is True

    def test_string_true(self):
        assert tc25.str2bool("true") is True

    def test_string_t(self):
        assert tc25.str2bool("T") is True

    def test_string_y(self):
        assert tc25.str2bool("y") is True

    def test_string_1(self):
        assert tc25.str2bool("1") is True

    def test_string_no(self):
        assert tc25.str2bool("no") is False

    def test_string_false(self):
        assert tc25.str2bool("false") is False

    def test_string_f(self):
        assert tc25.str2bool("f") is False

    def test_string_n(self):
        assert tc25.str2bool("n") is False

    def test_string_0(self):
        assert tc25.str2bool("0") is False

    def test_unknown_string_returns_none(self):
        assert tc25.str2bool("maybe") is None


# ---------------------------------------------------------------------------
# TestGetDictValByPath
# ---------------------------------------------------------------------------
class TestGetDictValByPath:
    """Tests for get_dict_val_by_path() in 2.5."""

    def test_single_level(self):
        d = {"a": 1}
        assert tc25.get_dict_val_by_path(d, ["a"]) == 1

    def test_two_levels(self):
        d = {"level1": {"level2": "value"}}
        assert tc25.get_dict_val_by_path(d, ["level1", "level2"]) == "value"

    def test_missing_key_returns_none(self):
        d = {"a": {"b": 1}}
        assert tc25.get_dict_val_by_path(d, ["a", "z"]) is None

    def test_missing_top_level_returns_none(self):
        d = {"a": 1}
        assert tc25.get_dict_val_by_path(d, ["z"]) is None

    def test_empty_path_returns_dict(self):
        d = {"a": 1}
        assert tc25.get_dict_val_by_path(d, []) == {"a": 1}

    def test_nested_none_short_circuits(self):
        d = {"a": None}
        assert tc25.get_dict_val_by_path(d, ["a", "b"]) is None

    def test_three_levels(self):
        d = {"l1": {"l2": {"l3": 99}}}
        assert tc25.get_dict_val_by_path(d, ["l1", "l2", "l3"]) == 99

    def test_returns_dict_value(self):
        d = {"key": {"nested": "data"}}
        assert tc25.get_dict_val_by_path(d, ["key"]) == {"nested": "data"}


# ---------------------------------------------------------------------------
# TestGGetRangeVal
# ---------------------------------------------------------------------------
class TestGGetRangeVal:
    """Tests for g_get_range_val() in 2.5."""

    RANGES = {"-127:20": 30, "21:25": 40, "26:30": 50, "31:120": 60}

    def test_matches_first_range(self):
        val, lo, hi = tc25.g_get_range_val(self.RANGES, 0)
        assert val == 30

    def test_matches_middle_range(self):
        val, _, _ = tc25.g_get_range_val(self.RANGES, 23)
        assert val == 40

    def test_matches_boundary_low(self):
        val, _, _ = tc25.g_get_range_val(self.RANGES, 21)
        assert val == 40

    def test_matches_boundary_high(self):
        val, _, _ = tc25.g_get_range_val(self.RANGES, 25)
        assert val == 40

    def test_matches_last_range(self):
        val, _, _ = tc25.g_get_range_val(self.RANGES, 100)
        assert val == 60

    def test_no_match_returns_none_triple(self):
        val, lo, hi = tc25.g_get_range_val(self.RANGES, 200)
        assert val is None
        assert lo is None
        assert hi is None

    def test_negative_input(self):
        val, _, _ = tc25.g_get_range_val(self.RANGES, -50)
        assert val == 30

    def test_single_entry(self):
        r = {"0:100": 99}
        val, lo, hi = tc25.g_get_range_val(r, 50)
        assert val == 99
        assert lo == 0
        assert hi == 100


# ---------------------------------------------------------------------------
# TestGGetDmin25
# ---------------------------------------------------------------------------
class TestGGetDmin25:
    """Tests for g_get_dmin() in thermal_control 2.5 (no interpolated param, returns float)."""

    THERMAL_TABLE = {
        "C2P": {
            "trusted": {"-127:20": 30, "21:25": 40, "26:30": 50, "31:120": 60}
        }
    }

    def test_basic_lookup_returns_float(self):
        result = tc25.g_get_dmin(self.THERMAL_TABLE, 23, ["C2P", "trusted"])
        assert result == 40.0
        assert isinstance(result, float)

    def test_missing_path_returns_pwm_min(self):
        result = tc25.g_get_dmin(self.THERMAL_TABLE, 23, ["C2P", "nonexistent"])
        assert result == tc25.CONST.PWM_MIN

    def test_empty_table_returns_pwm_min(self):
        result = tc25.g_get_dmin({}, 23, ["C2P", "trusted"])
        assert result == tc25.CONST.PWM_MIN

    def test_low_temp_first_range(self):
        result = tc25.g_get_dmin(self.THERMAL_TABLE, -50, ["C2P", "trusted"])
        assert result == 30.0

    def test_high_temp_last_range(self):
        result = tc25.g_get_dmin(self.THERMAL_TABLE, 80, ["C2P", "trusted"])
        assert result == 60.0

    def test_boundary_value(self):
        result = tc25.g_get_dmin(self.THERMAL_TABLE, 26, ["C2P", "trusted"])
        assert result == 50.0

    def test_out_of_range_raises_typeerror(self):
        # 2.5 g_get_dmin does float(None) when temp is out of all ranges
        with pytest.raises(TypeError):
            tc25.g_get_dmin(self.THERMAL_TABLE, 200, ["C2P", "trusted"])


# ---------------------------------------------------------------------------
# TestAddMissingToDict
# ---------------------------------------------------------------------------
class TestAddMissingToDict:
    """Tests for add_missing_to_dict() in 2.5."""

    def test_adds_new_key(self):
        base = {"a": 1}
        tc25.add_missing_to_dict(base, {"b": 2})
        assert base["b"] == 2

    def test_does_not_overwrite_existing(self):
        base = {"a": 1}
        tc25.add_missing_to_dict(base, {"a": 99})
        assert base["a"] == 1

    def test_adds_multiple_new_keys(self):
        base = {"a": 1}
        tc25.add_missing_to_dict(base, {"b": 2, "c": 3})
        assert base["b"] == 2
        assert base["c"] == 3

    def test_mixed_add_and_skip(self):
        base = {"a": 1, "b": 2}
        tc25.add_missing_to_dict(base, {"b": 99, "c": 3})
        assert base["b"] == 2
        assert base["c"] == 3

    def test_empty_new_dict_no_change(self):
        base = {"a": 1}
        tc25.add_missing_to_dict(base, {})
        assert base == {"a": 1}

    def test_empty_base_gets_all(self):
        base = {}
        tc25.add_missing_to_dict(base, {"x": 10, "y": 20})
        assert base == {"x": 10, "y": 20}


# ---------------------------------------------------------------------------
# TestIterateErrCounter25
# ---------------------------------------------------------------------------
class TestIterateErrCounter25:
    """Tests for iterate_err_counter in 2.5 (uses .warn() instead of .notice for repeats)."""

    def _make_counter(self, err_max=5, warn_limit=32):
        mock_log = MagicMock()
        return tc25.iterate_err_counter(mock_log, "test_counter_25", err_max, warn_limit), mock_log

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

    def test_handle_err_returns_true_on_success(self):
        ctr, _ = self._make_counter()
        result = ctr.handle_err("fan_err", cause="sensor timeout")
        assert result is True

    def test_handle_err_exceeds_warn_limit_blocks(self):
        ctr, _ = self._make_counter(warn_limit=2)
        ctr.handle_err("err_a")
        ctr.handle_err("err_b")
        # Third unique key — dict full, resolved entries cleared, still full → returns False
        result = ctr.handle_err("err_c")
        assert result is False

    def test_get_err_unknown_returns_zero(self):
        ctr, _ = self._make_counter()
        assert ctr.get_err("ghost_error") == 0

    def test_handle_err_no_print_log(self):
        ctr, mock_log = self._make_counter()
        ctr.handle_err("err_x", print_log=False)
        mock_log.notice.assert_not_called()


# ---------------------------------------------------------------------------
# TestCONSTClass25
# ---------------------------------------------------------------------------
class TestCONSTClass25:
    """Verify CONST values in 2.5."""

    def test_pwm_min_is_defined(self):
        assert hasattr(tc25.CONST, 'PWM_MIN')

    def test_hw_mgmt_folder_default(self):
        assert tc25.CONST.HW_MGMT_FOLDER_DEF == "/var/run/hw-management"

    def test_temp_sensor_scale(self):
        assert tc25.CONST.TEMP_SENSOR_SCALE == 1000.0

    def test_fan_dir_strings(self):
        assert tc25.CONST.C2P == "C2P"
        assert tc25.CONST.P2C == "P2C"

    def test_temp_na_val(self):
        assert tc25.CONST.TEMP_NA_VAL == 255


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
