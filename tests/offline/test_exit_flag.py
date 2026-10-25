#!/usr/bin/python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

"""Unit tests for hw_management_lib.ExitFlag (signal-handler-safe exit flag)."""

import importlib.util
import os
import signal
import threading
import time
import unittest
from unittest.mock import patch

LIB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        '..', '..', 'usr', 'usr', 'bin', 'hw_management_lib.py')


def _load_lib():
    # Load the real lib under a private name: other offline tests mock it in sys.modules.
    spec = importlib.util.spec_from_file_location('hw_management_lib_exitflag_test', LIB_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestExitFlag(unittest.TestCase):

    def setUp(self):
        self.lib = _load_lib()
        self.flag = self.lib.ExitFlag()

    def test_set_clear_is_set(self):
        self.assertFalse(self.flag.is_set())
        self.flag.set()
        self.assertTrue(self.flag.is_set())
        self.flag.clear()
        self.assertFalse(self.flag.is_set())

    def test_wait_returns_immediately_when_set(self):
        self.flag.set()
        with patch.object(self.lib.time, "sleep", side_effect=AssertionError("must not sleep")):
            self.assertTrue(self.flag.wait(10.0))

    def test_wait_sleeps_timeout_when_clear(self):
        slept = []
        with patch.object(self.lib.time, "sleep", side_effect=slept.append):
            self.assertFalse(self.flag.wait(0.5))
        self.assertEqual(slept, [0.5])

    def test_wait_non_positive_timeout_does_not_sleep(self):
        with patch.object(self.lib.time, "sleep", side_effect=AssertionError("must not sleep")):
            self.assertFalse(self.flag.wait(0))
            self.assertFalse(self.flag.wait(-1))

    def test_wait_without_timeout_blocks_until_set(self):
        calls = []

        def fake_sleep(_t):
            calls.append(1)
            if len(calls) == 3:
                self.flag.set()

        with patch.object(self.lib.time, "sleep", side_effect=fake_sleep):
            self.assertTrue(self.flag.wait())
        self.assertEqual(len(calls), 3)

    def test_take_interruptible_outside_section_is_false(self):
        self.assertFalse(self.flag.take_interruptible())

    def test_interruptible_is_one_shot_and_scoped(self):
        with self.flag.interruptible():
            self.assertTrue(self.flag.take_interruptible())   # first signal may raise
            self.assertFalse(self.flag.take_interruptible())  # second must not
        with self.flag.interruptible():
            pass
        self.assertFalse(self.flag.take_interruptible())      # disarmed on exit

    def test_interruptible_rearms_on_each_entry(self):
        for _ in range(3):
            with self.flag.interruptible():
                self.assertTrue(self.flag.take_interruptible())

    def test_interruptible_disarms_when_body_raises(self):
        with self.assertRaises(KeyError):
            with self.flag.interruptible():
                raise KeyError("x")
        self.assertFalse(self.flag.take_interruptible())

    def test_exit_wait_wakes_on_real_signal_without_raising(self):
        """Handler only sets the flag (updater behaviour outside interruptible sections)."""
        flag = self.flag
        old = signal.signal(signal.SIGUSR1, lambda _s, _f: flag.set())
        timer = threading.Timer(0.3, os.kill, args=(os.getpid(), signal.SIGUSR1))
        try:
            timer.start()
            start = time.monotonic()
            self.lib.exit_wait(flag, 5.0, chunk_sec=0.2)
            elapsed = time.monotonic() - start
        finally:
            timer.cancel()
            signal.signal(signal.SIGUSR1, old)
        self.assertTrue(flag.is_set())
        self.assertLess(elapsed, 2.0)

    def test_exit_wait_returns_early_when_already_set(self):
        self.flag.set()
        with patch.object(self.lib.time, "sleep", side_effect=AssertionError("must not sleep")):
            self.lib.exit_wait(self.flag, 5.0)


if __name__ == '__main__':
    unittest.main()
