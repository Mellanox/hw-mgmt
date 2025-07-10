import unittest
import os
import logging
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
    return False

def dummy_sdk_temp2degree(val):
    return 42

class TestSymlinkValidation(unittest.TestCase):
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
        self.invalid_target = f"{self.temp_dir}nonexistent_target"
        # Create an invalid symlink
        if os.path.exists(self.temp_file):
            os.remove(self.temp_file)
        os.symlink(self.invalid_target, self.temp_file)

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

    @patch("os.path.islink", side_effect=lambda path: os.path.islink(path))
    @patch("os.readlink", side_effect=lambda path: os.readlink(path))
    @patch("os.path.exists", side_effect=lambda path: os.path.exists(path))
    @patch("os.path.join", side_effect=lambda *args: f"{args[-2] if len(args) > 1 else args[-1]}" )
    def test_invalid_symlink_is_removed(self, mock_join, mock_exists, mock_readlink, mock_islink):
        arg_list = {"fin": f"{self.temp_dir}{self.module_name}", "module_count": 1, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        self.assertFalse(os.path.islink(self.temp_file), "Symlink should have been removed")
        self.assertTrue(any("Removed invalid symlink" in msg for msg in self.log_output))

if __name__ == "__main__":
    unittest.main() 