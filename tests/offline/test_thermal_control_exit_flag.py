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
ThermalManagement (thermal control 2.0 and 2.5) must use the lock-free ExitFlag:
its signal handler runs on the main thread and calls exit.set(), which on a
threading.Event can self-deadlock or race Event.wait() (CPython bpo-34486).
Same family as Redmine #5349060 (updaters).
"""

import importlib.util
import inspect
import os
import signal
import sys
import threading
from pathlib import Path
from unittest.mock import patch

import pytest

HW_MGMT_BIN = Path(__file__).parent.parent.parent / "usr" / "usr" / "bin"
if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

pytestmark = pytest.mark.offline

MODULES = ["hw_management_thermal_control", "hw_management_thermal_control_2_5"]


def _real_lib():
    """Real hw_management_lib under a private name: other offline tests mock it in sys.modules."""
    spec = importlib.util.spec_from_file_location(
        "hw_management_lib_tc_exitflag_test", HW_MGMT_BIN / "hw_management_lib.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _tm_class(modname):
    mod = __import__(modname)
    return mod, mod.ThermalManagement


def _bare_instance(modname, lib):
    mod, cls = _tm_class(modname)
    tm = cls.__new__(cls)  # skip heavy __init__
    tm.exit = lib.ExitFlag()
    return mod, tm




@pytest.mark.parametrize("modname", MODULES)
def test_exit_is_created_as_exitflag_before_handlers_installed(modname):
    """__init__ builds an ExitFlag (not an Event), and does so before signal.signal()."""
    _mod, cls = _tm_class(modname)
    src = inspect.getsource(cls.__init__)
    assert "self.exit = ExitFlag()" in src
    assert "self.exit = threading.Event()" not in src
    assert src.index("self.exit = ExitFlag()") < src.index("signal.signal(signal.SIGTERM")


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT, signal.SIGHUP])
@pytest.mark.parametrize("modname", MODULES)
def test_sig_handler_sets_flag_and_does_not_raise(modname, sig):
    lib = _real_lib()
    mod, tm = _bare_instance(modname, lib)
    assert not tm.exit.is_set()
    tm.sig_handler(sig)  # must not raise
    assert tm.exit.is_set()
    assert mod._sig_condition_name == signal.Signals(sig).name


@pytest.mark.parametrize("modname", MODULES)
def test_sig_handler_ignores_other_signals(modname):
    lib = _real_lib()
    _mod, tm = _bare_instance(modname, lib)
    tm.sig_handler(signal.SIGUSR2)
    assert not tm.exit.is_set()


@pytest.mark.parametrize("modname", MODULES)
def test_sig_handler_during_exit_wait_sleep_wakes_without_error(modname):
    """Handler fires while exit_wait() sleeps: no exception, exit_wait stops waiting."""
    lib = _real_lib()
    _mod, tm = _bare_instance(modname, lib)
    fired = []

    def sleep_with_signal(_seconds):
        if not fired:
            fired.append(True)
            tm.sig_handler(signal.SIGTERM)

    with patch.object(lib.time, "sleep", side_effect=sleep_with_signal):
        lib.exit_wait(tm.exit, 5)

    assert fired
    assert tm.exit.is_set()


@pytest.mark.parametrize("modname", MODULES)
def test_real_sigterm_storm_during_exit_wait(modname):
    """Real SIGTERMs delivered while exit_wait() sleeps never leak an exception."""
    lib = _real_lib()
    _mod, tm = _bare_instance(modname, lib)
    old = signal.signal(signal.SIGTERM, tm.sig_handler)
    errors = []
    try:
        for _ in range(200):
            tm.exit.clear()
            done = threading.Event()

            def kill():
                done.wait(0.0005)
                os.kill(os.getpid(), signal.SIGTERM)

            t = threading.Thread(target=kill)
            t.start()
            try:
                lib.exit_wait(tm.exit, 1, chunk_sec=0.001)
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)
            t.join()
            assert tm.exit.is_set()
    finally:
        signal.signal(signal.SIGTERM, old)
    assert errors == []
