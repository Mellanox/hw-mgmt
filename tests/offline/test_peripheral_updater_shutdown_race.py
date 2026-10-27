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

"""
Regression test for Redmine #5349060: on service stop the peripheral updater
dumps "RuntimeError: release unlocked lock" (CPython bpo-34486 / gh-118433).

handle_shutdown() used to raise ShutdownRequested from the signal handler on
every signal. If the signal landed inside threading.Event.wait() (exit_wait())
between Condition.wait() releasing its lock and re-acquiring it, the raise
skipped the re-acquire and "with self._cond" released an unlocked lock.

Now EXIT is a lock-free ExitFlag and the handler raises only inside
EXIT.interruptible() (the sysfs polling pass).
"""

import importlib.util
import os
import signal
import sys
import threading
import time
import unittest
from unittest.mock import MagicMock, patch

BIN_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'usr', 'usr', 'bin')


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_modules():
    """Load the REAL hw_management_lib and the updater using it (other offline tests mock the lib)."""
    real_lib = _load(os.path.join(BIN_DIR, 'hw_management_lib.py'), 'hw_management_lib_real_5349060')
    rf_mock = MagicMock()
    rf_mock.RedfishClient.ERR_CODE_OK = 0
    mocks = {
        'hw_management_lib': real_lib,
        'hw_management_redfish_client': rf_mock,
        'psutil': sys.modules.get('psutil') or MagicMock(),
    }
    with patch.dict(sys.modules, mocks):
        updater = _load(os.path.join(BIN_DIR, 'hw_management_peripheral_updater.py'),
                        'hw_management_peripheral_updater_5349060')
    return real_lib, updater


class TestShutdownSignalDuringExitWait(unittest.TestCase):

    def test_exit_is_lock_free_flag(self):
        """threading.Event is what made the race possible; EXIT must not be one."""
        lib, updater = _load_modules()
        self.assertIsInstance(updater.EXIT, lib.ExitFlag)
        self.assertNotIsInstance(updater.EXIT, threading.Event)

    def test_signal_during_exit_wait_sleep_does_not_raise(self):
        """Handler fires while exit_wait() sleeps: no exception, wakes promptly."""
        lib, updater = _load_modules()
        updater.EXIT.clear()
        fired = []

        def sleep_with_signal(_seconds):
            if not fired:
                fired.append(True)
                updater.handle_shutdown(15, None)  # must not raise

        with patch.object(lib.time, "sleep", side_effect=sleep_with_signal):
            lib.exit_wait(updater.EXIT, 5)

        self.assertTrue(fired, "test did not reach the sleep inside exit_wait")
        self.assertTrue(updater.EXIT.is_set())


class TestHandleShutdownContract(unittest.TestCase):
    """handle_shutdown() raises only while the main loop is doing interruptible I/O."""

    def setUp(self):
        self.lib, self.updater = _load_modules()
        self.updater.EXIT.clear()

    def test_outside_io_sets_exit_and_does_not_raise(self):
        self.updater.handle_shutdown(signal.SIGTERM, None)
        self.assertTrue(self.updater.EXIT.is_set())
        self.assertEqual(self.updater._sig_condition_name, "SIGTERM")

    def test_during_io_sets_exit_and_raises(self):
        with self.updater.EXIT.interruptible():
            with self.assertRaises(self.updater.ShutdownRequested):
                self.updater.handle_shutdown(signal.SIGINT, None)
        self.assertTrue(self.updater.EXIT.is_set())
        self.assertEqual(self.updater._sig_condition_name, "SIGINT")

    def test_second_signal_during_io_does_not_raise_again(self):
        """One-shot: a signal arriving while the first is being handled must not re-raise."""
        with self.updater.EXIT.interruptible():
            with self.assertRaises(self.updater.ShutdownRequested):
                self.updater.handle_shutdown(signal.SIGTERM, None)
            self.updater.handle_shutdown(signal.SIGINT, None)  # no raise


class TestRealSignalStress(unittest.TestCase):
    """Deliver real SIGTERMs while exit_wait() is sleeping; none may leak RuntimeError."""

    def test_sigterm_storm_during_exit_wait(self):
        lib, updater = _load_modules()
        old = signal.signal(signal.SIGTERM, updater.handle_shutdown)
        errors = []
        try:
            for _ in range(300):
                updater.EXIT.clear()
                done = threading.Event()

                def kill():
                    done.wait(0.0005)
                    os.kill(os.getpid(), signal.SIGTERM)

                t = threading.Thread(target=kill)
                t.start()
                try:
                    lib.exit_wait(updater.EXIT, 1, chunk_sec=0.001)
                except RuntimeError as exc:
                    errors.append(exc)
                t.join()
                self.assertTrue(updater.EXIT.is_set())
        finally:
            signal.signal(signal.SIGTERM, old)
            updater.EXIT.clear()
        self.assertEqual(errors, [])


class TestMainLoopInterruptibleWindow(unittest.TestCase):
    """main() must be interruptible only around I/O, never while in exit_wait()."""

    def _run_main(self, updater, on_update=None, on_wait=None):
        states = {"update": [], "wait": []}

        def fake_update(_attr):
            states["update"].append(updater.EXIT._interruptible)
            if on_update:
                on_update()

        def fake_wait(*_a, **_k):
            states["wait"].append(updater.EXIT._interruptible)
            if on_wait:
                on_wait()
            updater.EXIT.set()

        argv = ["hw_management_peripheral_updater.py", "-s", "HI162"]
        with patch.object(sys, "argv", argv), \
                patch.object(updater, "Logger", MagicMock()), \
                patch.object(updater, "init_attr"), \
                patch.object(updater, "write_module_counter"), \
                patch.object(updater, "update_peripheral_attr", side_effect=fake_update), \
                patch.object(updater, "exit_wait", side_effect=fake_wait), \
                patch.object(updater.signal, "signal"), \
                patch.object(updater.signal, "siginterrupt"):
            updater.main()
        return states

    def setUp(self):
        _lib, self.updater = _load_modules()
        self.updater.EXIT.clear()

    def test_interruptible_only_during_work(self):
        states = self._run_main(self.updater)
        self.assertTrue(states["update"] and all(states["update"]))
        self.assertEqual(states["wait"], [False])
        self.assertFalse(self.updater.EXIT._interruptible)

    def test_signal_during_exit_wait_exits_cleanly(self):
        def sigterm():
            self.updater.handle_shutdown(signal.SIGTERM, None)  # must not raise

        self._run_main(self.updater, on_wait=sigterm)
        self.assertTrue(self.updater.EXIT.is_set())

    def test_signal_during_io_aborts_and_clears_flag(self):
        def sigterm():
            self.updater.handle_shutdown(signal.SIGTERM, None)  # raises ShutdownRequested

        states = self._run_main(self.updater, on_update=sigterm)
        self.assertEqual(states["wait"], [])  # aborted before sleeping
        self.assertFalse(self.updater.EXIT._interruptible)


if __name__ == '__main__':
    unittest.main()
