import unittest
import os
import logging
from unittest.mock import patch, MagicMock
import sys
import types
import importlib.util

mock_spec = importlib.util.spec_from_file_location("hw_management_redfish_client", "tests/mock_hw_management_redfish_client.py")
mock_mod = importlib.util.module_from_spec(mock_spec)
mock_spec.loader.exec_module(mock_mod)
sys.modules["hw_management_redfish_client"] = mock_mod

from usr.usr.bin import hw_management_sync

def dummy_is_module_host_management_mode(path):
    return True

def dummy_sdk_temp2degree(val):
    return 42

class TestSWControlModeCleanup(unittest.TestCase):
    def setUp(self):
        self.logger = logging.getLogger("hw_management_sync")
        self.logger.setLevel(logging.WARNING)
        self.log_output = []
        handler = logging.StreamHandler()
        handler.emit = lambda record: self.log_output.append(record.getMessage())
        self.logger.addHandler(handler)
        hw_management_sync.is_module_host_management_mode = dummy_is_module_host_management_mode
        hw_management_sync.sdk_temp2degree = dummy_sdk_temp2degree
        self.temp_dir = "/tmp/hw-mgmt-test/"
        os.makedirs(self.temp_dir, exist_ok=True)
        self.module_name = "module0"
        self.temp_files = [f"{self.temp_dir}{self.module_name}{suffix}" for suffix in ["_temp_input", "_temp_crit", "_temp_emergency", "_temp_fault", "_temp_trip_crit"]]
        for f in self.temp_files:
            with open(f, "w") as fp:
                fp.write("stale\n")

    def tearDown(self):
        for f in self.temp_files:
            try:
                os.remove(f)
            except FileNotFoundError:
                pass
        for handler in self.logger.handlers[:]:
            self.logger.removeHandler(handler)
        try:
            os.rmdir(self.temp_dir)
        except OSError:
            pass

    @patch("os.path.islink", return_value=False)
    @patch("os.path.exists", side_effect=lambda path: os.path.isfile(path))
    @patch("os.remove", side_effect=os.remove)
    def test_sw_control_mode_removes_temp_files(self, mock_remove, mock_exists, mock_islink):
        arg_list = {"fin": f"{self.temp_dir}{self.module_name}", "module_count": 1, "fout_idx_offset": 0}
        with patch("os.path.join", side_effect=lambda *args: f"{self.temp_dir}{args[-2] if len(args) > 1 else args[-1]}"):
            hw_management_sync.module_temp_populate(arg_list, None)
        for f in self.temp_files:
            self.assertFalse(os.path.exists(f), f"File {f} should have been removed")
        self.assertTrue(any("Removed stale temperature file for SW control mode" in msg for msg in self.log_output))

if __name__ == "__main__":
    unittest.main() 