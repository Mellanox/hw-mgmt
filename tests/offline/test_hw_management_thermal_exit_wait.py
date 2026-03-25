#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for hw_management_lib.exit_wait() (Bug 4879247 / f1428bc1):
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
    assert len(fe._wait_calls) == 4
    assert sum(fe._wait_calls) == pytest.approx(3.7, rel=1e-9, abs=1e-9)
    assert fe._wait_calls[:3] == [1.0, 1.0, 1.0]


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
