import unittest
from unittest.mock import patch, mock_open
import logging
import builtins
import sys
import types

import importlib.util
mock_spec = importlib.util.spec_from_file_location("hw_management_redfish_client", "tests/mock_hw_management_redfish_client.py")
mock_mod = importlib.util.module_from_spec(mock_spec)
mock_spec.loader.exec_module(mock_mod)
sys.modules["hw_management_redfish_client"] = mock_mod

from usr.usr.bin import hw_management_sync

def dummy_sdk_temp2degree(val):
    return 42

class TestExceptionHandling(unittest.TestCase):
    def setUp(self):
        self.logger = logging.getLogger("hw_management_sync")
        self.logger.setLevel(logging.WARNING)
        self.log_output = []
        handler = logging.StreamHandler()
        handler.emit = lambda record: self.log_output.append(record.getMessage())
        self.logger.addHandler(handler)
        hw_management_sync.sdk_temp2degree = dummy_sdk_temp2degree

    def tearDown(self):
        for handler in self.logger.handlers[:]:
            self.logger.removeHandler(handler)

    @patch("os.path.islink", return_value=False)
    @patch("os.path.isfile", return_value=False)
    @patch("os.path.join", side_effect=lambda *args: "/mocked/path/" + args[-1])
    def test_module_present_file_ioerror(self, mock_join, mock_isfile, mock_islink):
        arg_list = {"fin": "/mocked/path/module{}", "module_count": 1, "fout_idx_offset": 0}
        with patch.object(builtins, "open", side_effect=IOError("mocked error")):
            hw_management_sync.module_temp_populate(arg_list, None)
        self.assertTrue(any("Failed to read module present file" in msg for msg in self.log_output))

    @patch("os.path.islink", return_value=False)
    @patch("os.path.isfile", return_value=False)
    @patch("os.path.join", side_effect=lambda *args: "/mocked/path/" + args[-1])
    def test_temperature_file_valueerror(self, mock_join, mock_isfile, mock_islink):
        def open_side_effect(file, *args, **kwargs):
            if "present" in file:
                m = mock_open(read_data="1").return_value
                m.__enter__.return_value = m
                return m
            raise ValueError("mocked value error")
        arg_list = {"fin": "/mocked/path/module{}", "module_count": 1, "fout_idx_offset": 0}
        with patch.object(builtins, "open", side_effect=open_side_effect):
            hw_management_sync.module_temp_populate(arg_list, None)
        self.assertTrue(any("Failed to read temperature or threshold file" in msg for msg in self.log_output))

if __name__ == "__main__":
    unittest.main() 