#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for ThermalManagement._exit_wait() (Bug 4879247 / f1428bc1):
# chunked Event.wait so SIGTERM handler can run during long waits.
################################################################################

import sys
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"
if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

pytestmark = pytest.mark.offline


class _FakeExit:
    """Minimal threading.Event-like object for _exit_wait tests."""

    def __init__(self, stop_after_waits=None):
        self._manual = False
        self._wait_calls = []
        self._n_waits = 0
        self._stop_after = stop_after_waits

    def is_set(self):
        if self._manual:
            return True
        if self._stop_after is not None and self._n_waits >= self._stop_after:
            return True
        return False

    def set(self):
        self._manual = True

    def wait(self, timeout):
        self._wait_calls.append(timeout)
        self._n_waits += 1


def _thermal_modules():
    import hw_management_thermal_control as tc
    import hw_management_thermal_control_2_5 as tc25
    return [("tc", tc), ("tc_2_5", tc25)]


@pytest.mark.parametrize("name,mod", _thermal_modules())
def test_exit_wait_noop_when_exit_already_set(name, mod):
    fe = _FakeExit()
    fe.set()
    obj = type("O", (), {"exit": fe})()
    mod.ThermalManagement._exit_wait(obj, 100.0, chunk_sec=1.0)
    assert fe._wait_calls == []


@pytest.mark.parametrize("name,mod", _thermal_modules())
def test_exit_wait_chunks_until_timeout(name, mod):
    fe = _FakeExit(stop_after_waits=9999)
    obj = type("O", (), {"exit": fe})()
    mod.ThermalManagement._exit_wait(obj, 3.7, chunk_sec=1.0)
    assert len(fe._wait_calls) == 4
    assert sum(fe._wait_calls) == pytest.approx(3.7, rel=1e-9, abs=1e-9)
    assert fe._wait_calls[:3] == [1.0, 1.0, 1.0]


@pytest.mark.parametrize("name,mod", _thermal_modules())
def test_exit_wait_small_timeout_single_chunk(name, mod):
    fe = _FakeExit(stop_after_waits=9999)
    obj = type("O", (), {"exit": fe})()
    mod.ThermalManagement._exit_wait(obj, 0.25, chunk_sec=1.0)
    assert fe._wait_calls == [0.25]


@pytest.mark.parametrize("name,mod", _thermal_modules())
def test_exit_wait_stops_early_when_exit_set_after_chunks(name, mod):
    fe = _FakeExit(stop_after_waits=2)
    obj = type("O", (), {"exit": fe})()
    mod.ThermalManagement._exit_wait(obj, 30.0, chunk_sec=1.0)
    assert fe._wait_calls == [1.0, 1.0]


@pytest.mark.parametrize("name,mod", _thermal_modules())
def test_exit_wait_custom_chunk(name, mod):
    fe = _FakeExit(stop_after_waits=9999)
    obj = type("O", (), {"exit": fe})()
    mod.ThermalManagement._exit_wait(obj, 2.5, chunk_sec=0.5)
    assert fe._wait_calls == [0.5, 0.5, 0.5, 0.5, 0.5]
