#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Periodic-report formatting must not call round() on missing-sensor sentinels.
# That raised "type str doesn't define __round__ method" from RepeatedTimer.
#

import threading

import pytest

import hw_management_thermal_control_2_5 as tc
from hw_management_lib import RepeatedTimer


def _bare(cls, **attrs):
    obj = cls.__new__(cls)
    for key, value in attrs.items():
        setattr(obj, key, value)
    return obj


def _fault_attrs():
    return {
        "fault_list": [],
        "mask_fault_list": [],
        "fault_list_static_filtered": [],
        "fault_list_dynamic_filtered": [],
    }


@pytest.mark.unit
@pytest.mark.thermal
class TestGSafeRound:
    def test_numeric_values_are_rounded(self):
        assert tc.g_safe_round(32.44, 1) == 32.4
        assert tc.g_safe_round(30, 1) == 30

    def test_none_becomes_na(self):
        assert tc.g_safe_round(None, 1) == "N/A"

    def test_na_string_is_preserved(self):
        assert tc.g_safe_round("N/A", 1) == "N/A"

    def test_numeric_string_is_rounded(self):
        assert tc.g_safe_round("70.04", 1) == 70.0

    def test_non_numeric_string_is_preserved(self):
        assert tc.g_safe_round("!70000", 1) == "!70000"


@pytest.mark.unit
@pytest.mark.thermal
class TestAmbientPeriodicReport:
    def _sensor(self, values, pwm=30):
        return _bare(
            tc.ambient_thermal_sensor,
            name="sensor_amb",
            value_dict=values,
            flow_dir=tc.CONST.C2P,
            pwm=pwm,
            state=tc.CONST.RUNNING,
            **_fault_attrs()
        )

    def test_missing_ambient_values_do_not_raise(self):
        sensor = self._sensor({
            "port_amb": tc.CONST.AMB_TEMP_ERR_VAL,
            "fan_amb": tc.CONST.AMB_TEMP_ERR_VAL,
        })

        text = str(sensor)

        assert "port_amb:N/A" in text
        assert "fan_amb:N/A" in text
        assert "(N/A)" in text
        assert "pwm:30" in text

    def test_mixed_ambient_values(self):
        sensor = self._sensor({
            "port_amb": tc.CONST.AMB_TEMP_ERR_VAL,
            "fan_amb": 32.44,
        })

        text = str(sensor)

        assert "port_amb:N/A" in text
        assert "fan_amb:32.4" in text
        assert "(32.4)" in text

    def test_periodic_timer_does_not_print_round_error(self, capsys):
        sensor = self._sensor({"port_amb": tc.CONST.AMB_TEMP_ERR_VAL})
        reported = threading.Event()

        def report():
            str(sensor)
            reported.set()

        timer = RepeatedTimer(0.01, report)
        timer.start()
        assert reported.wait(1.0)
        timer.stop()

        captured = capsys.readouterr()
        assert "Error in periodic task" not in captured.out
        assert "__round__" not in captured.out
        assert "__round__" not in captured.err


@pytest.mark.unit
@pytest.mark.thermal
class TestSensorReportSentinels:
    def test_system_device_none_limits(self):
        sensor = _bare(
            tc.system_device,
            name="sodimm1_temp",
            value=45.2,
            val_min=None,
            val_max=None,
            pwm=20,
            state=tc.CONST.STOPPED,
            **_fault_attrs()
        )

        text = str(sensor)

        assert "temp: 45.2" in text
        assert "tmin: N/A" in text
        assert "tmax: N/A" in text
        assert "pwm: 20" in text

    def test_module_none_limits(self):
        sensor = _bare(
            tc.thermal_module_sensor,
            name="module1",
            value=40.0,
            val_min=None,
            val_max=None,
            pwm=30.0,
            pwm_prev=30.0,
            pwm_regulator="reg",
            state=tc.CONST.RUNNING,
            **_fault_attrs()
        )

        text = str(sensor)

        assert "tmin:N/A" in text
        assert "tmax:N/A" in text
        assert "temp:40.0" in text

    def test_tec_non_numeric_readings(self):
        sensor = _bare(
            tc.thermal_module_tec_sensor,
            name="module1",
            temperature="N/A",
            cooling_level="N/A",
            cooling_level_max="N/A",
            pwm=30.0,
            pwm_prev=30.0,
            state=tc.CONST.STOPPED,
            **_fault_attrs()
        )

        text = str(sensor)

        assert "temp:N/A" in text
        assert "cooling_lvl:N/A" in text
        assert "cooling_lvl_max:N/A" in text
        assert "pwm: 30.0" in text
