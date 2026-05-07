#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for hw_management_lib.exit_wait():
#   chunked Event.wait so SIGTERM handler can run during long waits.
#
# Feature history (verified against git on Nhugi_dev):
#   - d73ee15d (2026-03-17, Bug 4879247) introduced ThermalManagement._exit_wait
#     as a class method in TC 2.0 and 2.5.
#   - 6703a009 (2026-03-25, Bug 4946747) introduced module-level
#     hw_management_lib.exit_wait() and adopted it in thermal-updater and
#     peripheral-updater.
#   - 8aaba0f1 (2026-04-02, Bug 4953142) added the `if timeout <= 0: return`
#     guard and migrated the TC 2.0 / TC 2.5 call sites from the per-class
#     ThermalManagement._exit_wait method to the module-level function.
################################################################################

import sys
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"
if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

from hw_management_lib import exit_wait  # noqa: E402

pytestmark = pytest.mark.offline


class _FakeExit:
    """Minimal threading.Event-like object for exit_wait tests."""

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


def test_exit_wait_noop_when_exit_already_set():
    fe = _FakeExit()
    fe.set()
    exit_wait(fe, 100.0, chunk_sec=1.0)
    assert fe._wait_calls == []


def test_exit_wait_chunks_until_timeout():
    fe = _FakeExit(stop_after_waits=9999)
    exit_wait(fe, 3.7, chunk_sec=1.0)
    assert fe._wait_calls == [1.0, 1.0, 1.0, pytest.approx(0.7, rel=1e-9, abs=1e-9)]


def test_exit_wait_small_timeout_single_chunk():
    fe = _FakeExit(stop_after_waits=9999)
    exit_wait(fe, 0.25, chunk_sec=1.0)
    assert fe._wait_calls == [0.25]


def test_exit_wait_stops_early_when_exit_set_after_chunks():
    fe = _FakeExit(stop_after_waits=2)
    exit_wait(fe, 30.0, chunk_sec=1.0)
    assert fe._wait_calls == [1.0, 1.0]


def test_exit_wait_custom_chunk():
    fe = _FakeExit(stop_after_waits=9999)
    exit_wait(fe, 2.5, chunk_sec=0.5)
    assert fe._wait_calls == [0.5, 0.5, 0.5, 0.5, 0.5]


def test_exit_wait_zero_timeout_is_noop():
    fe = _FakeExit()
    exit_wait(fe, 0.0, chunk_sec=1.0)
    assert fe._wait_calls == []


def test_exit_wait_negative_timeout_is_noop():
    # Production passes `sleep_ms / 1000` (e.g. hw_management_thermal_control.py:4352)
    # which can be negative when computed; the `if timeout <= 0: return` guard
    # in hw_management_lib.exit_wait must cover this case.
    fe = _FakeExit()
    exit_wait(fe, -1.0, chunk_sec=1.0)
    assert fe._wait_calls == []
