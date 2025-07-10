import unittest
import os
import threading
import time
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

class TestAtomicFileWrite(unittest.TestCase):
    def setUp(self):
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
        try:
            os.rmdir(self.temp_dir)
        except OSError:
            pass

    @patch("os.path.islink", return_value=False)
    @patch("os.path.isfile", return_value=False)
    @patch("os.path.join", side_effect=lambda *args: f"{args[-2] if len(args) > 1 else args[-1]}" )
    def test_atomic_write(self, mock_join, mock_isfile, mock_islink):
        arg_list = {"fin": f"{self.temp_dir}{self.module_name}", "module_count": 1, "fout_idx_offset": 0}
        # Run module_temp_populate in multiple threads
        def writer():
            for _ in range(10):
                hw_management_sync.module_temp_populate(arg_list, None)
                time.sleep(0.01)
        threads = [threading.Thread(target=writer) for _ in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        # After all writes, the file should always contain a full line (not partial/corrupted)
        with open(self.temp_file, "r") as f:
            content = f.read().strip()
        self.assertTrue(content.isdigit() or content == "N/A", f"File content is corrupted: {content}")

if __name__ == "__main__":
    unittest.main() 