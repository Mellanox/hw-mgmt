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

import hw_management_thermal_control_2_5 as tc25
import sys
import os
import types
import pytest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))


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


# ---------------------------------------------------------------------------
# TestHwMgmtFileOp25
# ---------------------------------------------------------------------------
class TestHwMgmtFileOp25:
    """Tests for hw_management_file_op in hw_management_thermal_control_2_5."""

    def _make_op(self, root):
        config = {tc25.CONST.HW_MGMT_ROOT: root}
        return tc25.hw_management_file_op(config)

    def test_init_with_explicit_root(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.root_folder == str(tmp_path)

    def test_init_falsy_root_uses_default(self):
        config = {tc25.CONST.HW_MGMT_ROOT: ""}
        op = tc25.hw_management_file_op(config)
        assert op.root_folder == tc25.CONST.HW_MGMT_FOLDER_DEF

    def test_get_hw_path(self, tmp_path):
        op = self._make_op(str(tmp_path))
        result = op.get_hw_path("thermal/temp1")
        assert result == str(tmp_path / "thermal" / "temp1")

    def test_check_file_existing(self, tmp_path):
        f = tmp_path / "sensor"
        f.write_text("42")
        op = self._make_op(str(tmp_path))
        assert op.check_file("sensor") is True

    def test_check_file_missing(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.check_file("nosuchfile") is False

    def test_check_file_empty_name(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.check_file("") is False

    def test_read_file_existing(self, tmp_path):
        f = tmp_path / "sensor"
        f.write_text("42\n")
        op = self._make_op(str(tmp_path))
        assert op.read_file("sensor") == "42"

    def test_read_file_missing_returns_none(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.read_file("nosuchfile") is None

    def test_write_file_creates_file(self, tmp_path):
        op = self._make_op(str(tmp_path))
        op.write_file("out", "hello")
        assert (tmp_path / "out").read_text() == "hello"

    def test_write_file_overwrites(self, tmp_path):
        f = tmp_path / "out"
        f.write_text("old")
        op = self._make_op(str(tmp_path))
        op.write_file("out", "new")
        assert f.read_text() == "new"

    def test_get_file_val_existing_file(self, tmp_path):
        (tmp_path / "sensor").write_text("300\n")
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("sensor") == 300

    def test_get_file_val_missing_returns_default(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("nosuchfile", def_val=99) == 99

    def test_get_file_val_with_scale(self, tmp_path):
        (tmp_path / "t").write_text("75000\n")
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("t", scale=1000) == 75

    def test_get_file_val_bad_content_returns_default(self, tmp_path):
        (tmp_path / "bad").write_text("notanumber\n")
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("bad", def_val=7) == 7

    def test_rm_file_removes_existing(self, tmp_path):
        f = tmp_path / "todelete"
        f.write_text("x")
        op = self._make_op(str(tmp_path))
        op.rm_file("todelete")
        assert not f.exists()

    def test_get_file_mtime_existing(self, tmp_path):
        f = tmp_path / "f"
        f.write_text("x")
        op = self._make_op(str(tmp_path))
        mtime = op.get_file_mtime("f")
        assert mtime > 0

    def test_get_file_mtime_missing_returns_zero(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.get_file_mtime("nosuchfile") == 0

    def test_read_pwm_reads_and_converts(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        (thermal / "pwm1").write_text("128\n")
        op = self._make_op(str(tmp_path))
        pwm = op.read_pwm()
        assert pwm == pytest.approx(50, abs=1)

    def test_read_pwm_missing_returns_default(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.read_pwm(default_val=42) == 42

    def test_write_pwm_writes_to_pwm1(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        pwm_file = thermal / "pwm1"
        pwm_file.write_text("0\n")
        op = self._make_op(str(tmp_path))
        result = op.write_pwm(100)
        assert result is True
        assert pwm_file.read_text() == "255"

    def test_write_pwm_missing_file_returns_false(self, tmp_path):
        op = self._make_op(str(tmp_path))
        result = op.write_pwm(50)
        assert result is False

    def test_thermal_read_file(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        (thermal / "temp").write_text("55\n")
        op = self._make_op(str(tmp_path))
        assert op.thermal_read_file("temp") == "55"

    def test_thermal_write_file(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        op = self._make_op(str(tmp_path))
        op.thermal_write_file("pwm1", "128")
        assert (thermal / "pwm1").read_text() == "128"

    def test_read_file_int_no_scale(self, tmp_path):
        (tmp_path / "pwm").write_text("200\n")
        op = self._make_op(str(tmp_path))
        assert op.read_file_int("pwm") == 200

    def test_read_file_int_with_scale(self, tmp_path):
        (tmp_path / "temp").write_text("75000\n")
        op = self._make_op(str(tmp_path))
        assert op.read_file_int("temp", scale=1000) == 75


# ---------------------------------------------------------------------------
# TestPwmRegulatorSimple
# ---------------------------------------------------------------------------
class TestPwmRegulatorSimple:
    """Tests for pwm_regulator_simple — pure-math PWM controller."""

    def _make_reg(self, val_min=35000, val_max=70000, pwm_min=20, pwm_max=100):
        mock_log = MagicMock()
        return tc25.pwm_regulator_simple(mock_log, "reg1", val_min, val_max, pwm_min, pwm_max), mock_log

    def test_init_sets_name(self):
        reg, _ = self._make_reg()
        assert reg.name == "reg1"

    def test_init_sets_pwm_min(self):
        reg, _ = self._make_reg(pwm_min=30)
        assert reg.pwm_min == 30

    def test_init_sets_pwm_max(self):
        reg, _ = self._make_reg(pwm_max=90)
        assert reg.pwm_max == 90

    def test_get_pwm_returns_pwm_min_initially(self):
        reg, _ = self._make_reg()
        assert reg.get_pwm() == 20

    def test_tick_at_val_min_gives_pwm_min(self):
        reg, _ = self._make_reg(val_min=35000, val_max=70000, pwm_min=20, pwm_max=100)
        reg.tick(35000)
        assert reg.get_pwm() == pytest.approx(20, abs=1)

    def test_tick_at_val_max_gives_pwm_max(self):
        reg, _ = self._make_reg(val_min=35000, val_max=70000, pwm_min=20, pwm_max=100)
        reg.tick(70000)
        assert reg.get_pwm() == pytest.approx(100, abs=1)

    def test_tick_midpoint_gives_mid_pwm(self):
        reg, _ = self._make_reg(val_min=0, val_max=100, pwm_min=0, pwm_max=100)
        reg.tick(50)
        assert reg.get_pwm() == pytest.approx(50, abs=1)

    def test_tick_over_val_max_clamped_to_pwm_max(self):
        reg, _ = self._make_reg(val_min=0, val_max=100, pwm_min=20, pwm_max=80)
        reg.tick(999)
        assert reg.get_pwm() == 80

    def test_tick_below_val_min_clamped_to_pwm_min(self):
        reg, _ = self._make_reg(val_min=0, val_max=100, pwm_min=20, pwm_max=80)
        reg.tick(-999)
        assert reg.get_pwm() == 20

    def test_calculate_pwm_formula_equal_min_max(self):
        reg, _ = self._make_reg(val_min=50, val_max=50)
        result = reg._calculate_pwm_formula(50, 50, 20, 100, 50)
        assert result == 20

    def test_update_param_updates_val_min(self):
        reg, _ = self._make_reg(val_min=35000, val_max=70000)
        reg.update_param(40000, None, None, None)
        assert reg.val_min == 40000

    def test_update_param_none_preserves_existing(self):
        reg, _ = self._make_reg(val_min=35000)
        reg.update_param(None, None, None, None)
        assert reg.val_min == 35000

    def test_str_contains_name(self):
        reg, _ = self._make_reg()
        assert "reg1" in str(reg)

    def test_init_no_logger(self):
        reg = tc25.pwm_regulator_simple(None, "no_log", 35000, 70000, 20, 100)
        reg.tick(50000)
        assert reg.get_pwm() is not None


# ---------------------------------------------------------------------------
# TestPwmRegulatorDynamic
# ---------------------------------------------------------------------------
class TestPwmRegulatorDynamic:
    """Tests for pwm_regulator_dynamic — PI-style PWM controller."""

    def _make_reg(self, val_min=35000, val_max=70000, pwm_min=20, pwm_max=100, extra=None):
        mock_log = MagicMock()
        ep = extra or {}
        return tc25.pwm_regulator_dynamic(mock_log, "dynreg", val_min, val_max, pwm_min, pwm_max, ep), mock_log

    def test_init_sets_name(self):
        reg, _ = self._make_reg()
        assert reg.name == "dynreg"

    def test_init_iterm_is_zero(self):
        reg, _ = self._make_reg()
        assert reg.Iterm == 0

    def test_tick_above_threshold_increases_pwm_max_dynamic(self):
        reg, _ = self._make_reg(val_max=70000)
        initial = reg.pwm_max_dynamic
        reg.tick(69999)
        assert reg.pwm_max_dynamic >= initial

    def test_tick_below_threshold_decreases_iterm(self):
        reg, _ = self._make_reg(val_max=70000)
        reg.Iterm = 20
        reg.tick(10000)
        assert reg.Iterm == 0

    def test_tick_in_middle_sets_iterm_zero(self):
        reg, _ = self._make_reg(val_max=70000)
        reg.Iterm = 5
        mid_val = 65000
        reg.tick(mid_val)
        assert reg.Iterm == 0

    def test_str_contains_iterm(self):
        reg, _ = self._make_reg()
        s = str(reg)
        assert "I:" in s

    def test_str_contains_pwm_dmax(self):
        reg, _ = self._make_reg()
        s = str(reg)
        assert "pwm_dmax" in s

    def test_update_param_changes_pwm_max_dynamic(self):
        reg, _ = self._make_reg(pwm_max=100)
        reg.update_param(None, None, None, 90)
        assert reg.pwm_max_dynamic == 90

    def test_calculate_pwm_formula_equal_min_max(self):
        reg, _ = self._make_reg(val_min=50, val_max=50)
        result = reg._calculate_pwm_formula(50, 50, 20, 100, 50)
        assert result == 20

    def test_tick_does_not_exceed_100(self):
        reg, _ = self._make_reg(val_max=70000)
        for _ in range(20):
            reg.tick(75000)
        assert reg.pwm_max_dynamic <= 100


# ---------------------------------------------------------------------------
# TestSystemDevice25
# ---------------------------------------------------------------------------
def _make_sensor_config25(base_file_name="sensor", extra=None):
    cfg = {
        "type": "test_type",
        "base_file_name": base_file_name,
        "input_suffix": "_input",
        "enable": 1,
        "input_smooth_level": 1,
        "poll_time": 30,
        "pwm_hyst": 0,
        "dynamic_err_mask": [],
    }
    if extra:
        cfg.update(extra)
    return cfg


def _make_system_device25(root, name="sensor1", extra=None):
    cmd_arg = {tc25.CONST.HW_MGMT_ROOT: root}
    sys_config = {
        tc25.CONST.SYS_CONF_SENSORS_CONF: {
            name: _make_sensor_config25(extra=extra)
        }
    }
    mock_log = MagicMock()
    return tc25.system_device(cmd_arg, sys_config, name, mock_log), mock_log


class TestSystemDevice25:
    """Tests for system_device in hw_management_thermal_control_2_5."""

    def test_init_sets_name(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path), "my_sensor")
        assert dev.name == "my_sensor"

    def test_init_state_is_stopped(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        assert dev.state == tc25.CONST.STOPPED

    def test_get_value_returns_initial(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        assert dev.get_value() == tc25.CONST.TEMP_NA_VAL

    def test_get_pwm_returns_last_pwm(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        assert dev.get_pwm() == tc25.CONST.PWM_MIN

    def test_stop_when_already_stopped_no_op(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        dev.stop()
        assert dev.state == tc25.CONST.STOPPED

    def test_set_system_flow_dir(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        dev.set_system_flow_dir(tc25.CONST.C2P)
        assert dev.system_flow_dir == tc25.CONST.C2P

    def test_update_value_smoothing(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        result = dev.update_value(50)
        assert isinstance(result, int)

    def test_check_sensor_blocked_no_file(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        assert dev.check_sensor_blocked() is False

    def test_validate_value_in_range_over_max(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        result = dev.validate_value_in_min_max_range(99999)
        assert result is True

    def test_validate_value_in_range_normal(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        mid = (dev.val_min + dev.val_max) // 2
        result = dev.validate_value_in_min_max_range(mid)
        assert result is False

    def test_is_crit_range_violation_no_limits(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        dev.val_hcrit = None
        dev.val_lcrit = None
        result = dev.is_crit_range_violation(50000, "testfile")
        assert result is False

    def test_append_fault_adds_to_list(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        dev.append_fault("err1")
        assert "err1" in dev.fault_list

    def test_append_fault_no_duplicate(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        dev.append_fault("err1")
        dev.append_fault("err1")
        assert dev.fault_list.count("err1") == 1

    def test_clear_fault_list_empties_all(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        dev.append_fault("err1")
        dev.clear_fault_list()
        assert dev.fault_list == []

    def test_get_fault_list_filtered(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        dev.append_fault("err_a")
        result = dev.get_fault_list_filtered()
        assert "err_a" in result

    def test_get_fault_cnt_zero_when_no_faults(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        assert dev.get_fault_cnt() == 0

    def test_get_child_list_empty(self, tmp_path):
        dev, _ = _make_system_device25(str(tmp_path))
        assert dev.get_child_list() == []


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
