import unittest
import os
from unittest.mock import patch
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

class TestModuleCounterUpdate(unittest.TestCase):
    def setUp(self):
        hw_management_sync.is_module_host_management_mode = dummy_is_module_host_management_mode
        hw_management_sync.sdk_temp2degree = dummy_sdk_temp2degree
        self.temp_dir = "/tmp/hw-mgmt-test/"
        os.makedirs(self.temp_dir, exist_ok=True)
        self.counter_file = f"{self.temp_dir}module_counter"
        self.module_name = "module0"
        self.orig_counter_path = "/var/run/hw-management/config/module_counter"
        # Patch the path in the function to use our temp file
        self.patcher = patch("usr.usr.bin.hw_management_sync.open", create=True)
        self.mock_open = self.patcher.start()
        self.mock_open.side_effect = lambda file, mode='r', encoding=None: open(self.counter_file, mode, encoding=encoding) if file == self.orig_counter_path else open(file, mode, encoding=encoding)

    def tearDown(self):
        try:
            os.remove(self.counter_file)
        except FileNotFoundError:
            pass
        try:
            os.rmdir(self.temp_dir)
        except OSError:
            pass
        self.patcher.stop()

    @patch("os.path.islink", return_value=False)
    @patch("os.path.exists", return_value=False)
    def test_counter_updated_even_if_skipped(self, mock_exists, mock_islink):
        arg_list = {"fin": f"{self.temp_dir}{self.module_name}", "module_count": 3, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        with open(self.counter_file, "r") as f:
            content = f.read().strip()
        self.assertEqual(content, "3")

if __name__ == "__main__":
    unittest.main() 