#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for fan_sensor._validate_rpm (cached fan_tacho_state during
# PWM settle / stabilization). Covers hw_management_thermal_control and
# hw_management_thermal_control_2_5. Multi-tacho and tacho_idx base 1 or 2.
################################################################################

import re
import sys
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"
if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

pytestmark = pytest.mark.offline

# slope=200, rpm_max=35000, CONST.PWM_MAX=100 -> b=15000; at pwm 50 -> rpm_calc=25000
_EXPECTED_RPM_AT_PWM_50 = 25000

_DRWR = {
    "rpm_min": 3000,
    "rpm_max": 35000,
    "slope": 200,
    "pwm_min": 20,
    "rpm_tolerance": 30,
}

_FAN_SPEED_FN = re.compile(r"fan(\d+)_speed_get$")


class _ValidateRpmHarness:
    """Minimal object to invoke fan_sensor._validate_rpm(self).

    tacho_idx: base fan index (1 or 2 in HW); loop reads fan{tacho_idx+i}_speed_get.
    """

    name = "fan_test"
    log = Mock()
    fread_err = Mock()
    fread_err.handle_err = Mock()

    def __init__(
        self,
        read_pwm_val,
        pwm_set,
        rpm_relax_ts,
        fan_tacho_state,
        rpm_read=None,
        rpm_reads=None,
        drwr_param=None,
        tacho_idx=1,
    ):
        self.tacho_idx = tacho_idx
        self.read_pwm_val = read_pwm_val
        self.pwm_set = pwm_set
        self.rpm_relax_timestamp = rpm_relax_ts
        self.fan_tacho_state = fan_tacho_state
        if rpm_reads is not None:
            self.tacho_cnt = len(rpm_reads)
            self._rpm_list = list(rpm_reads)
            self.value = list(rpm_reads)
            if drwr_param is not None:
                self.drwr_param = drwr_param
            else:
                self.drwr_param = {str(i): dict(_DRWR) for i in range(self.tacho_cnt)}
        else:
            self.tacho_cnt = 1
            r = rpm_read if rpm_read is not None else _EXPECTED_RPM_AT_PWM_50
            self._rpm_list = [r]
            self.value = [r]
            self.drwr_param = drwr_param if drwr_param is not None else {"0": dict(_DRWR)}
        self.val_min_def = 3000
        self.val_max_def = 35000
        self.rpm_tolerance = 0.30

    def read_pwm(self):
        return self.read_pwm_val

    def get_hw_path(self, p):
        return p

    def thermal_read_file_int(self, fn):
        m = _FAN_SPEED_FN.search(fn)
        assert m, fn
        fan_num = int(m.group(1))
        idx = fan_num - self.tacho_idx
        return self._rpm_list[idx]


def _modules():
    import hw_management_thermal_control as tc
    import hw_management_thermal_control_2_5 as tc25
    return [("thermal_control", tc), ("thermal_control_2_5", tc25)]


@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_pwm_read_none_returns_false(module_name, tc_mod):
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(50, 50, 0, True)
        h.read_pwm_val = None
        assert tc_mod.fan_sensor._validate_rpm(h) is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_not_stabilized_returns_previous_false(module_name, tc_mod, tacho_idx):
    """After PWM change, until relax time: keep prior fault (False)."""
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            read_pwm_val=50,
            pwm_set=50,
            rpm_relax_ts=9_999_999_999,  # future -> not stabilized
            fan_tacho_state=False,
            tacho_idx=tacho_idx,
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is False
        assert h.fan_tacho_state is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_not_stabilized_returns_previous_true(module_name, tc_mod, tacho_idx):
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(50, 50, 9_999_999_999, True, tacho_idx=tacho_idx)
        assert tc_mod.fan_sensor._validate_rpm(h) is True
        assert h.fan_tacho_state is True


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_read_pwm_mismatch_uses_cached_false(module_name, tc_mod, tacho_idx):
    """read_pwm != pwm_set counts as not stabilized."""
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            read_pwm_val=55,
            pwm_set=50,
            rpm_relax_ts=0,
            fan_tacho_state=False,
            tacho_idx=tacho_idx,
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_stabilized_speed_ok(module_name, tc_mod, tacho_idx):
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            50, 50, 0, False, rpm_read=_EXPECTED_RPM_AT_PWM_50, tacho_idx=tacho_idx
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is True
        assert h.fan_tacho_state is True


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_stabilized_speed_wrong(module_name, tc_mod, tacho_idx):
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(50, 50, 0, True, rpm_read=5000, tacho_idx=tacho_idx)
        assert tc_mod.fan_sensor._validate_rpm(h) is False
        assert h.fan_tacho_state is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_out_of_range(module_name, tc_mod, tacho_idx):
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(50, 50, 9_999_999_999, True, rpm_read=500, tacho_idx=tacho_idx)
        assert tc_mod.fan_sensor._validate_rpm(h) is False
        assert h.fan_tacho_state is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_pwm_below_pwm_min_skips_trend_true(module_name, tc_mod, tacho_idx):
    dp = {"0": dict(_DRWR)}
    h = _ValidateRpmHarness(
        15, 15, 0, False, rpm_read=8000, drwr_param=dp, tacho_idx=tacho_idx
    )
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        assert tc_mod.fan_sensor._validate_rpm(h) is True
        assert h.fan_tacho_state is True


# --- Multi-tacho (tacho_cnt=2: fan{N}, fan{N+1} for base N = tacho_idx 1 or 2) ---


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_multi_first_not_stabilized_false_second_ok_stays_false(
    module_name, tc_mod, tacho_idx
):
    """Tacho0 not stabilized -> cached False; tacho1 stabilized OK does not clear it."""
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            50,
            50,
            rpm_relax_ts=9_999_999_999,
            fan_tacho_state=False,
            rpm_reads=[_EXPECTED_RPM_AT_PWM_50, _EXPECTED_RPM_AT_PWM_50],
            tacho_idx=tacho_idx,
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is False
        assert h.fan_tacho_state is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_multi_second_tacho_out_of_range_fails(module_name, tc_mod, tacho_idx):
    """Tacho0 in range + stabilized OK; tacho1 RPM out of range -> immediate False."""
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            50,
            50,
            rpm_relax_ts=0,
            fan_tacho_state=True,
            rpm_reads=[_EXPECTED_RPM_AT_PWM_50, 500],
            tacho_idx=tacho_idx,
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is False
        assert h.fan_tacho_state is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_multi_tacho0_skip_trend_tacho1_trend_fail(module_name, tc_mod, tacho_idx):
    """Tacho0 pwm < pwm_min (continue); tacho1 stabilized, wrong RPM -> False."""
    dp = {
        "0": {**_DRWR, "pwm_min": 60},
        "1": dict(_DRWR),
    }
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            50,
            50,
            rpm_relax_ts=0,
            fan_tacho_state=True,
            rpm_reads=[_EXPECTED_RPM_AT_PWM_50, 5000],
            drwr_param=dp,
            tacho_idx=tacho_idx,
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is False
        assert h.fan_tacho_state is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_multi_tacho1_high_pwm_min_continue_keeps_first_false(
    module_name, tc_mod, tacho_idx
):
    """Tacho0 not stabilized -> False; tacho1 pwm_min > pwm (continue) leaves False."""
    dp = {
        "0": dict(_DRWR),
        "1": {**_DRWR, "pwm_min": 101},
    }
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            50,
            50,
            rpm_relax_ts=9_999_999_999,
            fan_tacho_state=False,
            rpm_reads=[_EXPECTED_RPM_AT_PWM_50, _EXPECTED_RPM_AT_PWM_50],
            drwr_param=dp,
            tacho_idx=tacho_idx,
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is False
        assert h.fan_tacho_state is False


@pytest.mark.parametrize("tacho_idx", [1, 2])
@pytest.mark.parametrize("module_name,tc_mod", _modules())
def test_validate_rpm_multi_both_ok(module_name, tc_mod, tacho_idx):
    """Two tachos, both stabilized with expected RPM -> True."""
    with patch.object(tc_mod, "current_milli_time", return_value=1_000_000):
        h = _ValidateRpmHarness(
            50,
            50,
            rpm_relax_ts=0,
            fan_tacho_state=False,
            rpm_reads=[_EXPECTED_RPM_AT_PWM_50, _EXPECTED_RPM_AT_PWM_50],
            tacho_idx=tacho_idx,
        )
        assert tc_mod.fan_sensor._validate_rpm(h) is True
        assert h.fan_tacho_state is True
