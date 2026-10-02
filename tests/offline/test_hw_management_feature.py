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
Storage contract tests for hw_management_feature.py.

CLI --set and feature_request() must share
/etc/hw-management/hw_management_features.json.
"""

import importlib.util
import json
import os
import shutil
import stat
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch

_BIN_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "..", "usr", "usr", "bin")
sys.path.insert(0, _BIN_DIR)

PRODUCTION_DB_FILE = "/etc/hw-management/hw_management_features.json"


def _feature_script_path():
    return os.path.join(_BIN_DIR, "hw_management_feature.py")


def _import_hw_management_lib():
    """Import shipped hw_management_lib. Stub dataclasses on Python < 3.7."""
    sys.modules.pop("hw_management_lib", None)
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
    import hw_management_lib as lib
    return lib


def load_feature_module():
    """Load hw_management_feature with the shipped str2bool.

    Mock run_shell_cmd so tests stay offline (no docker ps).
    """
    lib = _import_hw_management_lib()
    sys.modules.pop("hw_management_feature", None)

    def run_shell_cmd(*_args, **_kwargs):
        return 1, ""

    with patch.object(lib, "run_shell_cmd", side_effect=run_shell_cmd):
        spec = importlib.util.spec_from_file_location(
            "hw_management_feature", _feature_script_path())
        module = importlib.util.module_from_spec(spec)
        sys.modules["hw_management_feature"] = module
        spec.loader.exec_module(module)
    return module


class TestFeatureStorageContract(unittest.TestCase):
    """CLI and Python callers must read and write the same feature file."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.db_file = os.path.join(
            self.temp_dir, "hw-management", "hw_management_features.json")
        os.makedirs(os.path.dirname(self.db_file), exist_ok=True)
        self.feature = load_feature_module()
        self.default_db_file = self.feature.HW_MANAGEMENT_DB_FILE
        self._db_patch = patch.object(
            self.feature, "HW_MANAGEMENT_DB_FILE", self.db_file)
        self._db_patch.start()
        self._log_patch = patch.object(
            self.feature, "TRACE_LOG_FILE",
            os.path.join(self.temp_dir, "hw-mgmt.trace.log"))
        self._log_patch.start()
        self.feature.HW_MANAGEMENT_DB = {}

    def tearDown(self):
        self._log_patch.stop()
        self._db_patch.stop()
        self.feature.HW_MANAGEMENT_DB = {}
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_default_db_file_is_etc_hw_management(self):
        """The unpatched database path is under /etc/hw-management, not /var/run."""
        self.assertEqual(self.default_db_file, PRODUCTION_DB_FILE)
        self.assertEqual(
            os.path.dirname(self.default_db_file), "/etc/hw-management")
        self.assertEqual(
            os.path.basename(self.default_db_file),
            "hw_management_features.json")
        self.assertNotIn("/var/run/", self.default_db_file)
        self.assertNotIn("/config/", self.default_db_file)

    def test_cli_set_is_visible_to_python_get(self):
        """A value written by --set is read back by feature_request()."""
        argv = ["hw_management_feature.py", "--set", "is_redfish_disabled", "True"]
        with patch.object(sys, "argv", argv):
            self.assertEqual(self.feature.main(), 0)

        self.assertTrue(os.path.isfile(self.db_file))
        self.assertEqual(
            os.path.basename(self.db_file), "hw_management_features.json")
        self.assertEqual(
            os.path.basename(os.path.dirname(self.db_file)), "hw-management")
        with open(self.db_file, "r") as f:
            stored = json.load(f)
        self.assertTrue(stored["is_redfish_disabled"]["enabled"])

        self.feature.HW_MANAGEMENT_DB = {}
        ret, value = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, value), (0, "True"))

    def test_python_set_is_visible_to_cli_get(self):
        """A value written by feature_request() is printed by --get."""
        ret, _text = self.feature.feature_request(
            "set", "is_usb0_managed_by_nos", "True")
        self.assertEqual(ret, 0)
        self.assertTrue(os.path.isfile(self.db_file))

        self.feature.HW_MANAGEMENT_DB = {}
        argv = ["hw_management_feature.py", "--get", "is_usb0_managed_by_nos"]
        with patch.object(sys, "argv", argv), \
                patch("builtins.print") as mock_print:
            self.assertEqual(self.feature.main(), 0)
        mock_print.assert_called_with("True")

    def test_missing_file_is_success_with_default(self):
        """No database file is not a read failure and is not created."""
        ret, value = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, value), (0, "False"))
        self.assertFalse(os.path.isfile(self.db_file))

    def test_unknown_feature_is_error(self):
        """An unregistered feature name fails without creating the store."""
        ret, text = self.feature.feature_request("get", "not_a_feature")
        self.assertEqual((ret, text), (1, "Feature unknown: not_a_feature"))
        self.assertFalse(os.path.isfile(self.db_file))

    def test_unknown_action_is_error(self):
        """An unregistered action fails without creating the store."""
        ret, text = self.feature.feature_request("toggle", "is_redfish_disabled")
        self.assertEqual((ret, text), (1, "Command unknown: toggle"))
        self.assertFalse(os.path.isfile(self.db_file))

    def test_set_missing_value_is_error(self):
        """Set with no boolean argument does not write the store."""
        ret, text = self.feature.feature_request("set", "is_redfish_disabled")
        self.assertEqual((ret, text), (1, "missing value"))
        self.assertFalse(os.path.isfile(self.db_file))

    def test_set_invalid_value_is_error(self):
        """Set with a non-boolean argument does not write the store."""
        ret, text = self.feature.feature_request(
            "set", "is_redfish_disabled", "maybe")
        self.assertEqual((ret, text), (1, "invalid value"))
        self.assertFalse(os.path.isfile(self.db_file))

    def test_cli_unknown_feature_prints_stderr(self):
        """CLI --get of an unknown feature exits non-zero and prints to stderr."""
        argv = ["hw_management_feature.py", "--get", "not_a_feature"]
        with patch.object(sys, "argv", argv), \
                patch("builtins.print") as mock_print:
            self.assertEqual(self.feature.main(), 1)
        mock_print.assert_called_with(
            "Feature unknown: not_a_feature", file=sys.stderr)

    def test_corrupt_file_is_get_failure(self):
        """Get does not rewrite a corrupt file, so it cannot erase a set."""
        with open(self.db_file, "w") as f:
            f.write("not-json")
        with patch.object(self.feature, "save_hw_management_db") as mock_save:
            ret, value = self.feature.feature_request("get", "is_redfish_disabled")
        mock_save.assert_not_called()
        self.assertEqual((ret, value), (1, "DB load failed"))
        with open(self.db_file, "r") as f:
            self.assertEqual(f.read(), "not-json")

    def test_non_object_json_is_get_failure(self):
        """Get leaves a JSON array unchanged."""
        with open(self.db_file, "w") as f:
            json.dump(["not", "an", "object"], f)
        ret, value = self.feature.feature_request("get", "is_usb0_managed_by_nos")
        self.assertEqual((ret, value), (1, "DB load failed"))
        with open(self.db_file, "r") as f:
            self.assertEqual(json.load(f), ["not", "an", "object"])

    def test_set_does_not_repair_corrupt_file(self):
        """Set leaves corrupt JSON unchanged instead of overwriting it."""
        with open(self.db_file, "w") as f:
            f.write("not-json")
        ret, text = self.feature.feature_request(
            "set", "is_redfish_disabled", "True")
        self.assertEqual((ret, text), (1, "DB load failed"))
        with open(self.db_file, "r") as f:
            self.assertEqual(f.read(), "not-json")

    def test_get_does_not_erase_concurrent_set(self):
        """A get of corrupt JSON does not rewrite the file; a concurrent set also fails."""
        with open(self.db_file, "w") as f:
            f.write("not-json")
        results = []

        def do_get():
            ret, text = self.feature.feature_request("get", "is_redfish_disabled")
            results.append(("get", ret, text))

        def do_set():
            ret, text = self.feature.feature_request(
                "set", "is_redfish_disabled", "True")
            results.append(("set", ret, text))

        threads = [
            threading.Thread(target=do_get),
            threading.Thread(target=do_set),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(2)
            self.assertFalse(thread.is_alive())
        self.assertEqual(sorted(results), [
            ("get", 1, "DB load failed"),
            ("set", 1, "DB load failed"),
        ])
        with open(self.db_file, "r") as f:
            self.assertEqual(f.read(), "not-json")

    def test_failed_save_preserves_existing_file(self):
        """A failed replace leaves the previously stored settings readable."""
        original = {"is_redfish_disabled": {"enabled": True}}
        with open(self.db_file, "w") as f:
            json.dump(original, f)
        with patch.object(self.feature.os, "replace", side_effect=OSError("disk full")):
            ret, text = self.feature.feature_request(
                "set", "is_usb0_managed_by_nos", "False")
        self.assertEqual((ret, text), (1, "save_hw_management_db failed"))
        with open(self.db_file, "r") as f:
            stored = json.load(f)
        self.assertEqual(stored, original)
        self.feature.HW_MANAGEMENT_DB = {}
        ret, value = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, value), (0, "True"))

    def test_new_save_is_world_readable(self):
        """A newly created features file is readable by other users."""
        ret, _text = self.feature.feature_request(
            "set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        mode = stat.S_IMODE(os.stat(self.db_file).st_mode)
        self.assertEqual(mode, 0o644)

    def test_save_preserves_existing_permissions(self):
        """A later save keeps the mode already published on the file."""
        with open(self.db_file, "w") as f:
            json.dump({"is_usb0_managed_by_nos": {"enabled": True}}, f)
        os.chmod(self.db_file, 0o664)
        ret, _text = self.feature.feature_request(
            "set", "is_redfish_disabled", "True")
        self.assertEqual(ret, 0)
        mode = stat.S_IMODE(os.stat(self.db_file).st_mode)
        self.assertEqual(mode, 0o664)

    def test_get_does_not_require_write_access(self):
        """Get reads a valid file without rewriting it."""
        with open(self.db_file, "w") as f:
            json.dump({"is_redfish_disabled": {"enabled": True}}, f)
        ret, value = self.feature.feature_request("get", "is_redfish_disabled")
        self.assertEqual((ret, value), (0, "True"))
        with open(self.db_file, "r") as f:
            stored = json.load(f)
        self.assertTrue(stored["is_redfish_disabled"]["enabled"])

    def test_get_fails_when_db_dir_is_read_only(self):
        """Get cannot take the lock if the directory is not writable."""
        if os.geteuid() == 0:
            self.skipTest("root can write a mode 0555 directory")
        with open(self.db_file, "w") as f:
            json.dump({"is_redfish_disabled": {"enabled": True}}, f)
        db_dir = os.path.dirname(self.db_file)
        os.chmod(self.db_file, 0o444)
        os.chmod(db_dir, 0o555)
        try:
            ret, value = self.feature.feature_request("get", "is_redfish_disabled")
        finally:
            os.chmod(db_dir, 0o755)
            os.chmod(self.db_file, 0o644)
        self.assertEqual((ret, value), (1, "DB lock failed"))


class TestIsSonicOs(unittest.TestCase):
    """is_sonic_os() is the default for both features when the DB has no key."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.feature = load_feature_module()
        self.version_file = os.path.join(self.temp_dir, "sonic_version.yml")
        self.db_file = os.path.join(
            self.temp_dir, "hw-management", "hw_management_features.json")
        os.makedirs(os.path.dirname(self.db_file), exist_ok=True)
        self._patches = [
            patch.object(self.feature, "SONIC_VERSION_FILE", self.version_file),
            patch.object(self.feature, "HW_MANAGEMENT_DB_FILE", self.db_file),
            patch.object(
                self.feature, "TRACE_LOG_FILE",
                os.path.join(self.temp_dir, "hw-mgmt.trace.log")),
        ]
        for p in self._patches:
            p.start()
        self.feature.HW_MANAGEMENT_DB = {}

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self.feature.HW_MANAGEMENT_DB = {}
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _touch_version_file(self):
        with open(self.version_file, "w") as f:
            f.write("build_version: test\n")

    def test_false_without_version_file(self):
        """Missing sonic_version.yml is not SONiC."""
        self.assertFalse(self.feature.is_sonic_os())

    def test_false_when_show_missing(self):
        """Version file without show on PATH is not SONiC."""
        self._touch_version_file()
        with patch.object(self.feature.shutil, "which", return_value=None):
            self.assertFalse(self.feature.is_sonic_os())

    def test_false_when_docker_ps_fails(self):
        """docker ps failure is not SONiC."""
        self._touch_version_file()
        with patch.object(self.feature.shutil, "which", return_value="/usr/bin/show"), \
                patch.object(self.feature, "run_shell_cmd", return_value=(1, "error")):
            self.assertFalse(self.feature.is_sonic_os())

    def test_false_when_mgmt_framework_not_running(self):
        """Running containers without docker-sonic-mgmt-framework is not SONiC."""
        self._touch_version_file()
        with patch.object(self.feature.shutil, "which", return_value="/usr/bin/show"), \
                patch.object(self.feature, "run_shell_cmd",
                             return_value=(0, "docker-syncd-mlnx:latest\n")):
            self.assertFalse(self.feature.is_sonic_os())

    def test_true_when_mgmt_framework_running(self):
        """Version file, show, and mgmt-framework image mean SONiC."""
        self._touch_version_file()
        images = "docker-syncd-mlnx:latest\ndocker-sonic-mgmt-framework:latest\n"
        with patch.object(self.feature.shutil, "which", return_value="/usr/bin/show"), \
                patch.object(self.feature, "run_shell_cmd",
                             return_value=(0, images)) as mock_cmd:
            self.assertTrue(self.feature.is_sonic_os())
        mock_cmd.assert_called_with(
            "docker", ["ps", "--format", "{{.Image}}"], timeout=5)

    def test_feature_get_defaults_true_on_sonic(self):
        """No DB file: both features default True when is_sonic_os is True."""
        self._touch_version_file()
        images = "docker-sonic-mgmt-framework:latest\n"
        with patch.object(self.feature.shutil, "which", return_value="/usr/bin/show"), \
                patch.object(self.feature, "run_shell_cmd", return_value=(0, images)):
            ret, value = self.feature.feature_request(
                "get", "is_redfish_disabled")
            self.assertEqual((ret, value), (0, "True"))
            ret, value = self.feature.feature_request(
                "get", "is_usb0_managed_by_nos")
            self.assertEqual((ret, value), (0, "True"))
        self.assertFalse(os.path.isfile(self.db_file))


if __name__ == "__main__":
    unittest.main()
