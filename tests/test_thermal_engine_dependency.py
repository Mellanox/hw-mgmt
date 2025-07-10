import unittest
import os
import logging
from unittest.mock import patch, mock_open
import sys
import types
import importlib.util

mock_spec = importlib.util.spec_from_file_location("hw_management_redfish_client", "tests/mock_hw_management_redfish_client.py")
mock_mod = importlib.util.module_from_spec(mock_spec)
mock_spec.loader.exec_module(mock_mod)
sys.modules["hw_management_redfish_client"] = mock_mod

from usr.usr.bin import hw_management_sync

def dummy_is_module_host_management_mode(path):
    return False

def dummy_sdk_temp2degree(val):
    return 42

class TestThermalEngineDependency(unittest.TestCase):
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
        self.temp_file = f"{self.temp_dir}{self.module_name}_temp_input"

    def tearDown(self):
        try:
            os.remove(self.temp_file)
        except FileNotFoundError:
            pass
        for handler in self.logger.handlers[:]:
            self.logger.removeHandler(handler)
        try:
            os.rmdir(self.temp_dir)
        except OSError:
            pass

    @patch("os.path.islink", return_value=False)
    @patch("os.path.isfile", return_value=False)
    @patch("os.path.join", side_effect=lambda *args: f"{args[-2] if len(args) > 1 else args[-1]}" )
    def test_fallback_on_write_failure(self, mock_join, mock_isfile, mock_islink):
        arg_list = {"fin": f"{self.temp_dir}{self.module_name}", "module_count": 1, "fout_idx_offset": 0}
        # Simulate IOError on first write, succeed on fallback
        def open_side_effect(file, mode='r', encoding=None):
            if "w" in mode and not hasattr(open_side_effect, "called"):
                open_side_effect.called = True
                raise IOError("mocked write error")
            return open(file, mode, encoding=encoding)  # normal open
        with patch("builtins.open", side_effect=open_side_effect):
            hw_management_sync.module_temp_populate(arg_list, None)
        # Check fallback value is written
        with open(self.temp_file, "r") as f:
            content = f.read().strip()
        self.assertEqual(content, "N/A")
        self.assertTrue(any("Failed to write temperature file" in msg for msg in self.log_output))

if __name__ == "__main__":
    unittest.main() 