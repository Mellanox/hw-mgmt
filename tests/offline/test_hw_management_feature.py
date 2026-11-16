#!/usr/bin/python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
Offline unit tests for hw_management_feature.py (the feature get/set API).

Scope: the persistent JSON store contract (load/set/save), the registered
feature handlers (is_redfish_disabled, is_usb0_managed_by_nos), and the CLI
entry point (main()). No hardware; is_sonic_os() is stubbed wherever a test
needs a specific default.

Each test loads a fresh module instance via importlib so that the module
level globals (HW_MANAGEMENT_DB_FILE, TRACE_LOG_FILE) can be redirected to a
per-test temporary directory without leaking state between tests.

Loading the feature module needs the real hw_management_lib (other offline
files install a MagicMock under that name). The previous sys.modules entry
is restored after the import so this file does not leak that change into
whatever test runs next in the same pytest session.
"""

import contextlib
import fcntl
import functools
import importlib.util
import io
import json
import multiprocessing
import os
import shutil
import stat
import sys
import tempfile
import threading
import time
import types
import unittest
from unittest.mock import patch


def _bin_dir():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.join(script_dir, "..", "..")
    return os.path.abspath(os.path.join(repo_root, "usr", "usr", "bin"))


def _feature_script_path():
    return os.path.join(_bin_dir(), "hw_management_feature.py")


def _read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def _ensure_dataclasses_stub():
    """hw_management_lib imports dataclasses; stub it on Python < 3.7."""
    try:
        import dataclasses  # noqa: F401
    except ImportError:
        dc = types.ModuleType("dataclasses")

        def dataclass(*args, **_kwargs):
            def deco(cls):
                return cls
            if args and callable(args[0]):
                return args[0]
            return deco

        dc.dataclass = dataclass
        sys.modules["dataclasses"] = dc


def _load_feature_module(suffix):
    """Load a fresh, isolated hw_management_feature module instance.

    @param suffix: unique suffix so each test gets its own sys.modules entry.
    """
    _ensure_dataclasses_stub()
    bin_dir = _bin_dir()
    if bin_dir not in sys.path:
        sys.path.insert(0, bin_dir)
    # Other offline files install a MagicMock as hw_management_lib. Import
    # the real module for this load, then put the previous entry back.
    previous_lib = sys.modules.pop("hw_management_lib", None)

    mod_name = "hw_management_feature_{}".format(suffix)
    sys.modules.pop(mod_name, None)
    spec = importlib.util.spec_from_file_location(mod_name, _feature_script_path())
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    finally:
        if previous_lib is not None:
            sys.modules["hw_management_lib"] = previous_lib
    return module


class _FeatureModuleTestCase(unittest.TestCase):
    """Common setup: fresh module instance pointed at a temp DB/log file."""

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.db_file = os.path.join(
            self.tmp_dir, "hw-management", "hw_management_features.json")
        self.trace_file = os.path.join(self.tmp_dir, "hw-mgmt.trace.log")
        self.feature = _load_feature_module(self._testMethodName)
        self.feature.HW_MANAGEMENT_DB_FILE = self.db_file
        self.feature.TRACE_LOG_FILE = self.trace_file

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)


class TestFeatureStorageContract(unittest.TestCase):
    """Default DB path and basic store load/save rules."""

    def test_default_db_file_is_etc_hw_management(self):
        module = _load_feature_module("default_db_path")
        self.assertEqual(
            module.HW_MANAGEMENT_DB_FILE,
            "/etc/hw-management/hw_management_features.json")

    def test_default_trace_log_is_var_log(self):
        module = _load_feature_module("default_trace_log")
        self.assertEqual(module.TRACE_LOG_FILE, "/var/log/hw-mgmt.trace.log")


class TestGetSetRoundTrip(_FeatureModuleTestCase):
    """A value written through one call path is visible through the other."""

    def test_python_set_is_visible_to_python_get(self):
        ret, text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual((ret, text), (0, ""))

        ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "True"))

    def test_cli_set_is_visible_to_python_get(self):
        argv = ["hw_management_feature.py", "-l", self.trace_file,
                "--set", "is_redfish_disabled", "True"]
        with patch.object(sys, "argv", argv):
            ret = self.feature.main()
        self.assertEqual(ret, 0)

        ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "True"))

    def test_python_set_is_visible_to_cli_get(self):
        ret, _text = self.feature.feature_request(
            "set", "is_usb0_managed_by_nos", "True")
        self.assertEqual(ret, 0)

        argv = ["hw_management_feature.py", "-l", self.trace_file,
                "--get", "is_usb0_managed_by_nos"]
        out = io.StringIO()
        with patch.object(sys, "argv", argv), contextlib.redirect_stdout(out):
            ret = self.feature.main()
        self.assertEqual(ret, 0)
        self.assertEqual(out.getvalue().strip(), "True")

    def test_set_false_then_true_updates_stored_value(self):
        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "False")
        self.assertEqual(ret, 0)
        ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "False"))

        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "True"))

    def test_set_one_feature_preserves_the_other(self):
        """Saving one feature must not drop the other feature already on disk.

        is_sonic_os() is False, and the preserved flag is True, so a save that
        dropped that key would come back as the default False.
        """
        with patch.object(self.feature, "is_sonic_os", return_value=False):
            self.assertEqual(
                self.feature.feature_request("set", "is_redfish_disabled", "False")[0], 0)
            self.assertEqual(
                self.feature.feature_request("set", "is_usb0_managed_by_nos", "True")[0], 0)
            self.assertEqual(
                self.feature.feature_request("set", "is_redfish_disabled", "True")[0], 0)

            self.assertEqual(
                self.feature.feature_request("get", "is_redfish_disabled"), (0, "True"))
            self.assertEqual(
                self.feature.feature_request("get", "is_usb0_managed_by_nos"), (0, "True"))


class TestMissingAndCorruptStore(_FeatureModuleTestCase):
    """Missing file, corrupt JSON, and non-object JSON handling."""

    def test_missing_file_is_get_success_with_default(self):
        self.assertFalse(os.path.exists(self.db_file))
        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "False"))

    def _write_db_text(self, text):
        os.makedirs(os.path.dirname(self.db_file), exist_ok=True)
        with open(self.db_file, "w", encoding="utf-8") as handle:
            handle.write(text)

    def _assert_db_recovered(self, corrupted_text):
        """The bad file is kept as .corrupted and the DB is a valid JSON object."""
        self.assertEqual(_read_text(self.db_file + ".corrupted"), corrupted_text)
        self.assertIsInstance(json.loads(_read_text(self.db_file)), dict)

    def test_corrupt_file_is_recovered_and_get_returns_default(self):
        bad = "{ this is not valid json"
        self._write_db_text(bad)

        with patch.object(self.feature, "is_sonic_os", return_value=True):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")

        self.assertEqual((ret, text), (0, "True"))
        self._assert_db_recovered(bad)

    def test_non_object_json_is_recovered_and_get_returns_default(self):
        bad = json.dumps([1, 2, 3])
        self._write_db_text(bad)

        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")

        self.assertEqual((ret, text), (0, "False"))
        self._assert_db_recovered(bad)

    def test_set_on_corrupt_file_recovers_and_stores_value(self):
        bad = "{ this is not valid json"
        self._write_db_text(bad)

        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "True")

        self.assertEqual(ret, 0)
        self._assert_db_recovered(bad)
        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "True"))

    def test_recovery_keeps_only_the_latest_corrupted_copy(self):
        self._write_db_text("first bad")
        self.feature.feature_request("set", "is_redfish_disabled", "True")
        self._write_db_text("second bad")

        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "False")

        self.assertEqual(ret, 0)
        self._assert_db_recovered("second bad")

    def test_valid_file_is_not_recovered(self):
        self.feature.feature_request("set", "is_redfish_disabled", "True")

        self.feature.feature_request("get", "is_redfish_disabled")

        self.assertFalse(os.path.exists(self.db_file + ".corrupted"))

    def test_recovery_rename_failure_fails_request_and_keeps_file(self):
        bad = "{ this is not valid json"
        self._write_db_text(bad)

        with patch.object(self.feature.os, "rename", side_effect=OSError("boom")):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")

        self.assertEqual(ret, 1)
        self.assertTrue(text)
        self.assertEqual(_read_text(self.db_file), bad)

    def test_recovery_save_failure_fails_request_and_next_request_recovers(self):
        bad = "{ this is not valid json"
        self._write_db_text(bad)

        with patch.object(self.feature, "_save_hw_management_db", return_value=1):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (1, "Cannot load DB file"))
        self.assertEqual(_read_text(self.db_file + ".corrupted"), bad)
        self.assertFalse(os.path.exists(self.db_file))

        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "False"))

    def test_non_boolean_stored_value_is_get_failure_and_is_not_rewritten(self):
        """A stored non-boolean value fails the get and is left unchanged."""
        os.makedirs(os.path.dirname(self.db_file), exist_ok=True)
        with open(self.db_file, "w", encoding="utf-8") as handle:
            json.dump(
                {"is_redfish_disabled": {"value": "maybe", "user": "sw"}}, handle)
        before = _read_text(self.db_file)

        ret, text = self.feature.feature_request("get", "is_redfish_disabled")

        self.assertEqual((ret, text), (1, "invalid value"))
        self.assertEqual(_read_text(self.db_file), before)


class TestAtomicSave(_FeatureModuleTestCase):
    """Save-path contract: mode bits and failure handling."""

    def test_new_file_is_mode_0644(self):
        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        mode = stat.S_IMODE(os.stat(self.db_file).st_mode)
        self.assertEqual(mode, 0o644)

    def test_existing_file_mode_is_preserved_on_later_save(self):
        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        os.chmod(self.db_file, 0o640)

        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "False")
        self.assertEqual(ret, 0)
        mode = stat.S_IMODE(os.stat(self.db_file).st_mode)
        self.assertEqual(mode, 0o640)

    def test_failed_save_preserves_existing_file(self):
        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        before = _read_text(self.db_file)

        with patch.object(self.feature, "_save_hw_management_db", return_value=1):
            ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "False")
        self.assertNotEqual(ret, 0)

        after = _read_text(self.db_file)
        self.assertEqual(before, after)

    def test_get_with_persist_failure_still_returns_computed_value(self):
        """A failed cache write must not hide the value get already computed."""
        with patch.object(self.feature, "is_sonic_os", return_value=True), \
                patch.object(self.feature, "update_hw_management_db", return_value=1):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "True"))

    def test_no_file_is_created_when_nothing_is_written(self):
        # A failing set must not leave a partial file behind.
        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "not-a-bool")
        self.assertNotEqual(ret, 0)
        self.assertFalse(os.path.exists(self.db_file))


def _slow_default_get(feature, loaded_event, hold_seconds):
    """Child process: get a missing flag, pausing after the DB is loaded.

    is_sonic_os() runs after the load and before the save, so the pause
    keeps this process inside its read-modify-save window.
    """
    def slow_is_sonic_os():
        loaded_event.set()
        time.sleep(hold_seconds)
        return False

    feature.is_sonic_os = slow_is_sonic_os
    ret, _text = feature.feature_request("get", "is_redfish_disabled")
    sys.exit(ret)


def _set_after_load(feature, loaded_event):
    """Child process: set the flag once the other process has loaded the DB."""
    if not loaded_event.wait(10):
        sys.exit(3)
    ret, _text = feature.feature_request("set", "is_redfish_disabled", "True")
    sys.exit(ret)


class TestDbLock(_FeatureModuleTestCase):
    """feature_request serializes load, handler, and save across processes."""

    def _short_lock_timeout(self, seconds):
        """Make feature_request wait only `seconds` for the DB lock.

        _DbFileLock.__init__ binds its default timeout when the class is
        defined, so patching the DB_LOCK_TIMEOUT class attribute has no effect.
        Replace the class used by feature_request with one that passes an
        explicit timeout.
        """
        return patch.object(
            self.feature, "_DbFileLock",
            functools.partial(self.feature._DbFileLock, timeout=seconds))

    def _hold_db_lock(self):
        """Take the DB lock on a separate fd, as another process would."""
        lock_file = self.db_file + ".lock"
        os.makedirs(os.path.dirname(lock_file), exist_ok=True)
        fd = os.open(lock_file, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        self.addCleanup(os.close, fd)
        return fd

    def test_lock_file_is_created_next_to_db_with_mode_0600(self):
        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        mode = stat.S_IMODE(os.stat(self.db_file + ".lock").st_mode)
        self.assertEqual(mode, 0o600)

    def test_set_fails_when_lock_is_held(self):
        self._hold_db_lock()
        with self._short_lock_timeout(0.2):
            ret, text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual((ret, text), (1, "DB lock failed"))
        self.assertFalse(os.path.exists(self.db_file))

    def test_get_fails_when_lock_is_held(self):
        """Without the lock the DB is neither read nor written."""
        self._hold_db_lock()
        with self._short_lock_timeout(0.2), \
                patch.object(self.feature, "is_sonic_os", return_value=True):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (1, "DB lock failed"))
        self.assertFalse(os.path.exists(self.db_file))

    def test_get_fails_when_lock_file_cannot_be_opened(self):
        with patch.object(self.feature.os, "open", side_effect=PermissionError("denied")):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (1, "DB lock failed"))

    def test_lock_is_released_after_request(self):
        ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        fd = os.open(self.db_file + ".lock", os.O_RDWR)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(fd)

    def test_concurrent_set_is_not_overwritten_by_stale_get_default(self):
        """A set that runs while a get is mid-update must survive.

        Without the lock, the set commits during the get's pause and the get
        then saves its default (False) over it.
        """
        ctx = multiprocessing.get_context("fork")
        loaded = ctx.Event()
        getter = ctx.Process(
            target=_slow_default_get, args=(self.feature, loaded, 0.5))
        setter = ctx.Process(
            target=_set_after_load, args=(self.feature, loaded))
        getter.start()
        setter.start()
        getter.join(15)
        setter.join(15)
        self.assertEqual(getter.exitcode, 0)
        self.assertEqual(setter.exitcode, 0)

        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "True"))


class TestDispatchErrors(_FeatureModuleTestCase):
    """Unknown action/feature and malformed set arguments."""

    def test_unknown_action_returns_error(self):
        ret, text = self.feature.feature_request("delete", "is_redfish_disabled")
        self.assertEqual(ret, 1)
        self.assertIn("Command unknown", text)

    def test_unknown_feature_returns_error(self):
        ret, text = self.feature.feature_request("get", "does_not_exist")
        self.assertEqual(ret, 1)
        self.assertIn("Feature unknown", text)

    def test_set_with_no_value_returns_error(self):
        ret, text = self.feature.feature_request("set", "is_redfish_disabled")
        self.assertEqual(ret, 1)
        self.assertIn("expected exactly one value", text)

    def test_set_with_too_many_values_returns_error(self):
        ret, text = self.feature.feature_request(
            "set", "is_redfish_disabled", "True", "extra")
        self.assertEqual(ret, 1)
        self.assertIn("expected exactly one value", text)

    def test_set_with_invalid_boolean_returns_error(self):
        ret, text = self.feature.feature_request("set", "is_redfish_disabled", "maybe")
        self.assertEqual(ret, 1)
        self.assertIn("invalid value", text)


class TestRedfishDisabledDefault(_FeatureModuleTestCase):
    """is_redfish_disabled default follows is_sonic_os() when unset."""

    def test_default_false_when_not_sonic(self):
        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "False"))

    def test_default_true_when_sonic(self):
        with patch.object(self.feature, "is_sonic_os", return_value=True):
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "True"))

    def test_stored_value_overrides_default(self):
        with patch.object(self.feature, "is_sonic_os", return_value=True):
            ret, _text = self.feature.feature_request("set", "is_redfish_disabled", "False")
            self.assertEqual(ret, 0)
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, text), (0, "False"))


class TestUsb0ManagedByNosDefault(_FeatureModuleTestCase):
    """is_usb0_managed_by_nos default follows is_sonic_os() when unset."""

    def test_default_false_when_not_sonic(self):
        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, text = self.feature.feature_request("get", "is_usb0_managed_by_nos")
        self.assertEqual((ret, text), (0, "False"))

    def test_default_true_when_sonic(self):
        with patch.object(self.feature, "is_sonic_os", return_value=True):
            ret, text = self.feature.feature_request("get", "is_usb0_managed_by_nos")
        self.assertEqual((ret, text), (0, "True"))

    def test_stored_value_overrides_default(self):
        with patch.object(self.feature, "is_sonic_os", return_value=False):
            ret, _text = self.feature.feature_request("set", "is_usb0_managed_by_nos", "True")
            self.assertEqual(ret, 0)
            ret, text = self.feature.feature_request("get", "is_usb0_managed_by_nos")
        self.assertEqual((ret, text), (0, "True"))


class TestIsSonicOsDetection(unittest.TestCase):
    """is_sonic_os() needs both the manifest file and 'show' on PATH."""

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.module = _load_feature_module(self._testMethodName)
        self.module.TRACE_LOG_FILE = os.path.join(self.tmp_dir, "t.log")

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_false_without_manifest_file(self):
        missing = os.path.join(self.tmp_dir, "no_such_sonic_version.yml")
        with patch.object(self.module, "SONIC_VERSION_FILE", missing):
            self.assertFalse(self.module.is_sonic_os())

    def test_false_with_manifest_but_no_show_on_path(self):
        manifest = os.path.join(self.tmp_dir, "sonic_version.yml")
        with open(manifest, "w", encoding="utf-8"):
            pass
        # shutil is the process-wide module, not a copy on self.module.
        # patch restores it on exit; this stays correct under serial unittest.
        with patch.object(self.module, "SONIC_VERSION_FILE", manifest), \
                patch.object(self.module.shutil, "which", return_value=None):
            self.assertFalse(self.module.is_sonic_os())

    def test_true_with_manifest_and_show_on_path(self):
        manifest = os.path.join(self.tmp_dir, "sonic_version.yml")
        with open(manifest, "w", encoding="utf-8"):
            pass
        with patch.object(self.module, "SONIC_VERSION_FILE", manifest), \
                patch.object(self.module.shutil, "which", return_value="/usr/bin/show"):
            self.assertTrue(self.module.is_sonic_os())


class TestCliEntryPoint(unittest.TestCase):
    """main(): argparse wiring, help listing, and exit codes."""

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.module = _load_feature_module(self._testMethodName)
        self.module.HW_MANAGEMENT_DB_FILE = os.path.join(
            self.tmp_dir, "hw-management", "hw_management_features.json")
        self.module.TRACE_LOG_FILE = os.path.join(self.tmp_dir, "t.log")

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_get_with_no_feature_lists_options(self):
        argv = ["hw_management_feature.py", "--get"]
        out = io.StringIO()
        with patch.object(sys, "argv", argv), contextlib.redirect_stdout(out):
            ret = self.module.main()
        self.assertEqual(ret, 0)
        self.assertIn("is_redfish_disabled", out.getvalue())
        self.assertIn("is_usb0_managed_by_nos", out.getvalue())

    def test_set_with_no_feature_lists_options(self):
        argv = ["hw_management_feature.py", "--set"]
        out = io.StringIO()
        with patch.object(sys, "argv", argv), contextlib.redirect_stdout(out):
            ret = self.module.main()
        self.assertEqual(ret, 0)
        self.assertIn("is_redfish_disabled", out.getvalue())
        self.assertIn("is_usb0_managed_by_nos", out.getvalue())

    def test_missing_action_is_argparse_error(self):
        argv = ["hw_management_feature.py"]
        with patch.object(sys, "argv", argv):
            with self.assertRaises(SystemExit) as ctx:
                self.module.main()
        self.assertEqual(ctx.exception.code, 2)

    def test_get_and_set_together_is_argparse_error(self):
        argv = ["hw_management_feature.py", "--get", "is_redfish_disabled",
                "--set", "is_redfish_disabled", "True"]
        with patch.object(sys, "argv", argv):
            with self.assertRaises(SystemExit) as ctx:
                self.module.main()
        self.assertEqual(ctx.exception.code, 2)

    def test_get_unknown_feature_exits_non_zero_and_prints_to_stderr(self):
        argv = ["hw_management_feature.py", "--get", "does_not_exist"]
        err = io.StringIO()
        with patch.object(sys, "argv", argv), contextlib.redirect_stderr(err):
            ret = self.module.main()
        self.assertNotEqual(ret, 0)
        self.assertIn("Feature unknown", err.getvalue())

    def test_log_file_flag_redirects_trace_log(self):
        custom_log = os.path.join(self.tmp_dir, "custom.trace.log")
        argv = ["hw_management_feature.py", "-l", custom_log,
                "--get", "is_redfish_disabled"]
        with patch.object(self.module, "is_sonic_os", return_value=False), \
                patch.object(sys, "argv", argv):
            ret = self.module.main()
        self.assertEqual(ret, 0)
        self.assertTrue(os.path.isfile(custom_log))


if __name__ == "__main__":
    unittest.main()
