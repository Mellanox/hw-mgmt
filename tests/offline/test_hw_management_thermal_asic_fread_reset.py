#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for thermal_asic_sensor.handle_input fread_err reset (commit
# 1c294f7a3770e4aed227a4e6b77be81265792c29, Bug 4931215). TC 2.5 only:
# after ASIC read succeeds and value is in range, fread_err must reset so
# SENSOR_READ_ERR clears and PWM can drop from emergency level.
################################################################################

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


def _asic_handle_input_harness():
    """Minimal self for thermal_asic_sensor.handle_input."""
    h = SimpleNamespace()
    h.file_input = "asic0"
    h.name = "asic_ut"
    h.scale = 1.0
    h.pwm_min = 10.0
    h.pwm = 15.0
    h.value = 40.0
    h.fread_err = Mock()
    h.asic_fault_err = Mock()
    h.log = Mock()
    h.pwm_regulator = Mock()
    h.pwm_regulator.get_pwm = Mock(return_value=22.0)
    h.pwm_regulator.tick = Mock()
    h.check_file = Mock(return_value=True)
    h.read_file_float = Mock(return_value=55.0)
    h.get_hw_path = lambda p: "/mock/" + p
    h.is_crit_range_violation = Mock(return_value=False)
    # SDK fully initialized: sensor read errors are real (not suppressed as
    # transient) so the normal fread_err handling path runs (commit 381c955d).
    h._sdk_init_in_progress = Mock(return_value=False)
    h._read_asic_ready = Mock(return_value=True)

    h._updated = []

    def _upd(v):
        h.value = v
        h._updated.append(v)

    h.update_value = _upd
    h.validate_value_in_min_max_range = Mock()
    return h


def _call_kwargs(c):
    """Extract kwargs dict from a mock call — works on Python 3.6 and 3.8+.

    On Python 3.6, call objects are plain 2-tuples (args, kwargs); the .kwargs
    attribute exists only for call-chaining (call.method()), so it returns
    another _Call, not a dict. Index access is reliable across all versions.
    """
    kw = c[1]
    return kw if isinstance(kw, dict) else {}


def _call_args(c):
    """Extract positional args tuple from a mock call."""
    return c[0]


def test_asic_successful_read_resets_fread_err():
    import hw_management_thermal_control_2_5 as tc25

    h = _asic_handle_input_harness()
    tc25.thermal_asic_sensor.handle_input(h, {}, tc25.CONST.C2P, 25.0)

    reset_calls = [
        c for c in h.fread_err.handle_err.call_args_list if _call_kwargs(c).get("reset") is True
    ]
    assert len(reset_calls) >= 1, (
        "Expected fread_err.handle_err(..., reset=True) after good ASIC read; "
        "got %s" % h.fread_err.handle_err.call_args_list
    )
    path = _call_args(reset_calls[0])[0]
    assert "thermal/asic0" in path or path.endswith("asic0")
    assert h._updated == [55.0]
    h.validate_value_in_min_max_range.assert_called_once()


def test_asic_crit_range_sets_fread_err_no_reset():
    import hw_management_thermal_control_2_5 as tc25

    h = _asic_handle_input_harness()
    h.is_crit_range_violation = Mock(return_value=True)
    tc25.thermal_asic_sensor.handle_input(h, {}, tc25.CONST.C2P, 25.0)

    crit_calls = [c for c in h.fread_err.handle_err.call_args_list if _call_kwargs(c).get("cause") == "crit range"]
    assert len(crit_calls) == 1
    reset_calls = [c for c in h.fread_err.handle_err.call_args_list if _call_kwargs(c).get("reset") is True]
    assert reset_calls == []
    assert h._updated == []


def test_asic_read_exception_fread_err_value():
    import hw_management_thermal_control_2_5 as tc25

    h = _asic_handle_input_harness()
    h.read_file_float = Mock(side_effect=ValueError("bad"))
    tc25.thermal_asic_sensor.handle_input(h, {}, tc25.CONST.C2P, 25.0)

    h.fread_err.handle_err.assert_called_once()
    ca = h.fread_err.handle_err.call_args
    kw = _call_kwargs(ca)
    assert kw.get("cause") == "value"
    assert kw.get("reset") is not True


def test_source_contains_asic_fread_reset_comment():
    """Regression anchor for 1c294f7 (no behavior change if comment removed)."""
    src = (HW_MGMT_BIN / "hw_management_thermal_control_2_5.py").read_text()
    assert "value is readable and in expected range" in src
    assert "fread_err.handle_err(self.get_hw_path(val_read_file), reset=True)" in src
    assert 'cause="crit range"' in src
