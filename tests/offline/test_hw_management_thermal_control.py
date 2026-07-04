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

"""Tests for hw_management_thermal_control.py helper functions and classes.

Covers: str2bool, get_dict_val_by_path, g_get_range_val, g_get_dmin,
        add_missing_to_dict, iterate_err_counter, CONST constants,
        hw_management_file_op, and system_device methods.
These are all isolated from hardware — no sysfs access required.
"""

import hw_management_thermal_control as tc
import sys
import os
import pytest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))


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


# ---------------------------------------------------------------------------
# TestHwMgmtFileOp
# ---------------------------------------------------------------------------
class TestHwMgmtFileOp:
    """Tests for hw_management_file_op — the base file-operation class."""

    def _make_op(self, root):
        config = {tc.CONST.HW_MGMT_ROOT: root}
        return tc.hw_management_file_op(config)

    def test_init_with_explicit_root(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.root_folder == str(tmp_path)

    def test_init_falsy_root_uses_default(self):
        config = {tc.CONST.HW_MGMT_ROOT: ""}
        op = tc.hw_management_file_op(config)
        assert op.root_folder == tc.CONST.HW_MGMT_FOLDER_DEF

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
        assert op.check_file("absent.txt") is False

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
        assert op.read_file("absent.txt") is None

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

    def test_thermal_read_file(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        (thermal / "temp").write_text("55\n")
        op = self._make_op(str(tmp_path))
        assert op.thermal_read_file("temp") == "55"

    def test_read_file_int_no_scale(self, tmp_path):
        (tmp_path / "pwm").write_text("200\n")
        op = self._make_op(str(tmp_path))
        assert op.read_file_int("pwm") == 200

    def test_read_file_int_with_scale(self, tmp_path):
        (tmp_path / "temp").write_text("75000\n")
        op = self._make_op(str(tmp_path))
        assert op.read_file_int("temp", scale=1000) == 75

    def test_thermal_read_file_int(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        (thermal / "temp").write_text("50000\n")
        op = self._make_op(str(tmp_path))
        assert op.thermal_read_file_int("temp", scale=1000) == 50

    def test_thermal_write_file(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        op = self._make_op(str(tmp_path))
        op.thermal_write_file("pwm1", "128")
        assert (thermal / "pwm1").read_text() == "128"

    def test_get_file_val_existing_file(self, tmp_path):
        (tmp_path / "sensor").write_text("300\n")
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("sensor") == 300

    def test_get_file_val_missing_returns_default(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("absent.txt", def_val=99) == 99

    def test_get_file_val_with_scale(self, tmp_path):
        (tmp_path / "t").write_text("75000\n")
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("t", scale=1000) == 75

    def test_get_file_val_bad_content_returns_default(self, tmp_path):
        (tmp_path / "bad").write_text("invalid\n")
        op = self._make_op(str(tmp_path))
        assert op.get_file_val("bad", def_val=7) == 7

    def test_rm_file_removes_existing(self, tmp_path):
        f = tmp_path / "remove.txt"
        f.write_text("x")
        op = self._make_op(str(tmp_path))
        op.rm_file("remove.txt")
        assert not f.exists()

    def test_get_file_mtime_existing(self, tmp_path):
        f = tmp_path / "f"
        f.write_text("x")
        op = self._make_op(str(tmp_path))
        mtime = op.get_file_mtime("f")
        assert mtime > 0

    def test_get_file_mtime_missing_returns_zero(self, tmp_path):
        op = self._make_op(str(tmp_path))
        assert op.get_file_mtime("absent.txt") == 0

    def test_read_pwm_reads_and_converts(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        (thermal / "pwm1").write_text("128\n")
        op = self._make_op(str(tmp_path))
        pwm = op.read_pwm()
        assert pwm == 50  # 128/2.55 + 0.5 ≈ 50

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


# ---------------------------------------------------------------------------
# TestSystemDevice
# ---------------------------------------------------------------------------
def _make_sensor_config(base_file_name="sensor", extra=None):
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


def _make_system_device(root, name="sensor1", extra=None):
    """Helper to create a system_device with a mock logger and minimal config."""
    cmd_arg = {tc.CONST.HW_MGMT_ROOT: root}
    sys_config = {
        tc.CONST.SYS_CONF_SENSORS_CONF: {
            name: _make_sensor_config(extra=extra)
        }
    }
    mock_log = MagicMock()
    return tc.system_device(cmd_arg, sys_config, name, mock_log), mock_log


class TestSystemDevice:
    """Tests for system_device — base sensor class."""

    def test_init_sets_name(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path), "my_sensor")
        assert dev.name == "my_sensor"

    def test_init_sets_type(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path), extra={"type": "thermal"})
        assert dev.type == "thermal"

    def test_init_state_is_stopped(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.state == tc.CONST.STOPPED

    def test_init_pwm_is_pwm_min(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.pwm == tc.CONST.PWM_MIN

    def test_get_value_returns_initial(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.get_value() == tc.CONST.TEMP_INIT_VAL_DEF

    def test_get_pwm_returns_last_pwm(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.get_pwm() == tc.CONST.PWM_MIN

    def test_get_timestamp_returns_int(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert isinstance(dev.get_timestamp(), int)

    def test_stop_when_already_stopped_no_op(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.stop()
        assert dev.state == tc.CONST.STOPPED

    def test_set_system_flow_dir(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.set_system_flow_dir(tc.CONST.C2P)
        assert dev.system_flow_dir == tc.CONST.C2P

    def test_update_value_smoothing(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        result = dev.update_value(50)
        assert isinstance(result, int)

    def test_update_value_no_hyst_triggers_pwm_update(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.update_value(50)
        assert dev.update_pwm_flag == 1

    def test_calculate_pwm_formula_min_val(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.value = dev.val_min
        pwm = dev.calculate_pwm_formula()
        assert pwm == dev.pwm_min

    def test_calculate_pwm_formula_max_val(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.value = dev.val_max
        pwm = dev.calculate_pwm_formula()
        assert pwm == dev.pwm_max

    def test_calculate_pwm_formula_equal_min_max(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.val_min = 50
        dev.val_max = 50
        pwm = dev.calculate_pwm_formula()
        assert pwm == dev.pwm_min

    def test_check_sensor_blocked_no_file(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.check_sensor_blocked() is False

    def test_validate_value_in_range_over_max(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        result = dev.validate_value_in_min_max_range(99999)
        assert result is True

    def test_validate_value_in_range_normal(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        mid = (dev.val_min + dev.val_max) // 2
        result = dev.validate_value_in_min_max_range(mid)
        assert result is False

    def test_is_crit_range_violation_no_limits(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.val_hcrit = None
        dev.val_lcrit = None
        result = dev.is_crit_range_violation(50000, "sensor.txt")
        assert result is False

    def test_is_crit_range_violation_over_hcrit(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.val_hcrit = 80000
        dev.val_lcrit = None
        result = dev.is_crit_range_violation(90000, "sensor.txt")
        assert result is True

    def test_append_fault_adds_to_list(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.append_fault("err1")
        assert "err1" in dev.fault_list

    def test_append_fault_no_duplicate(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.append_fault("err1")
        dev.append_fault("err1")
        assert dev.fault_list.count("err1") == 1

    def test_clear_fault_list_empties_all(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.append_fault("err1")
        dev.clear_fault_list()
        assert dev.fault_list == []
        assert dev.fault_list_static_filtered == []

    def test_get_fault_list_filtered(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.append_fault("err_a")
        result = dev.get_fault_list_filtered()
        assert "err_a" in result

    def test_get_fault_list_str_empty(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.get_fault_list_str() == ""

    def test_get_fault_list_str_with_fault(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.append_fault("READ_ERR")
        s = dev.get_fault_list_str()
        assert "READ_ERR" in s

    def test_get_fault_cnt_zero_when_no_faults(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.get_fault_cnt() == 0

    def test_get_fault_cnt_one_when_faults_exist(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.fault_list_static_filtered.append("ERR")
        assert dev.get_fault_cnt() == 1

    def test_info_returns_string(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        result = dev.info()
        assert isinstance(result, str)
        assert dev.name in result

    def test_get_child_list_empty(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        assert dev.get_child_list() == []

    def test_set_dynamic_filter_ena_changes_mask(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path), extra={"dynamic_err_mask": ["DYN_ERR"]})
        dev.set_dynamic_filter_ena(True)
        assert dev.dynamic_filter_ena is True

    def test_set_dynamic_filter_ena_no_change_if_same(self, tmp_path):
        dev, _ = _make_system_device(str(tmp_path))
        dev.dynamic_filter_ena = False
        dev.set_dynamic_filter_ena(False)
        assert dev.dynamic_filter_ena is False


# ---------------------------------------------------------------------------
# TestThermalSensor
# ---------------------------------------------------------------------------
def _make_thermal_sensor(root, name="temp1"):
    cmd_arg = {tc.CONST.HW_MGMT_ROOT: root}
    sys_config = {
        tc.CONST.SYS_CONF_SENSORS_CONF: {
            name: {
                "type": "thermal",
                "base_file_name": "thermal/{}".format(name),
                "input_suffix": "_input",
                "enable": 1,
                "input_smooth_level": 1,
                "poll_time": 30,
                "pwm_hyst": 0,
                "dynamic_err_mask": [],
            }
        }
    }
    mock_log = MagicMock()
    return tc.thermal_sensor(cmd_arg, sys_config, name, mock_log), mock_log


class TestThermalSensor:
    """Tests for thermal_sensor class."""

    def test_init_creates_sensor(self, tmp_path):
        sensor, _ = _make_thermal_sensor(str(tmp_path))
        assert sensor.name == "temp1"

    def test_init_state_is_stopped(self, tmp_path):
        sensor, _ = _make_thermal_sensor(str(tmp_path))
        assert sensor.state == tc.CONST.STOPPED

    def test_handle_input_missing_file_updates_err(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        sensor, _ = _make_thermal_sensor(str(tmp_path))
        sensor.handle_input({}, tc.CONST.C2P, 25000)
        assert sensor.fread_err.get_err("{}{}".format(
            sensor.get_hw_path("thermal/temp1"), "_input")) >= 0

    def test_handle_input_with_valid_file(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        input_file = thermal / "temp1_input"
        input_file.write_text("50000\n")
        sensor, _ = _make_thermal_sensor(str(tmp_path))
        sensor.handle_input({}, tc.CONST.C2P, 25000)
        assert sensor.value == 50

    def test_collect_err_empty_when_no_errors(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        (thermal / "temp1_input").write_text("50000\n")
        sensor, _ = _make_thermal_sensor(str(tmp_path))
        sensor.handle_input({}, tc.CONST.C2P, 25000)
        sensor.collect_err()
        assert sensor.fault_list == []

    def test_handle_input_bad_value_triggers_err(self, tmp_path):
        thermal = tmp_path / "thermal"
        thermal.mkdir()
        (thermal / "temp1_input").write_text("not_a_number\n")
        sensor, _ = _make_thermal_sensor(str(tmp_path))
        sensor.handle_input({}, tc.CONST.C2P, 25000)
        err_path = sensor.get_hw_path("thermal/temp1_input")
        assert sensor.fread_err.get_err(err_path) >= 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
