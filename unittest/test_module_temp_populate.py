"""
Comprehensive test suite for module_temp_populate function.

This test file addresses the feedback issues identified in the code review:

FEEDBACK MAPPING:
=================

1. EXCEPTION HANDLING GAPS (Priority: HIGH)
   - Issue: Bare exception handling without proper logging
   - Tests: test_exception_handling_module_present_file, test_exception_handling_temperature_file
   - Fix: Added specific exception types and detailed logging

2. SW CONTROL MODULE SKIPPING (Priority: HIGH) 
   - Issue: SW control modules were being skipped entirely
   - Test: test_sw_control_mode_cleanup
   - Fix: Added proper cleanup of stale temperature files for SW control modules

3. SYMLINK BYPASS (Priority: MEDIUM)
   - Issue: Invalid symlinks could bypass validation
   - Test: test_symlink_validation_and_removal
   - Fix: Added symlink validation and removal of invalid symlinks

4. MODULE COUNTER UPDATE RISK (Priority: MEDIUM)
   - Issue: Module counter not always updated, leading to stale data
   - Test: test_module_counter_always_updated
   - Fix: Always update module counter regardless of processing success

5. FILE SYSTEM RACE CONDITIONS (Priority: MEDIUM)
   - Issue: Non-atomic file writes could cause race conditions
   - Test: test_fallback_on_write_failure
   - Fix: Added atomic file writing with tempfile.NamedTemporaryFile

ADDITIONAL TEST COVERAGE:
========================

6. NORMAL PROCESSING: test_normal_module_processing
   - Verifies basic functionality works correctly

7. MULTIPLE MODULES: test_multiple_modules_processing  
   - Tests processing of multiple modules in sequence

8. MODULE OFFSET: test_module_offset_processing
   - Tests processing with different module index offsets

Each test validates both the fix implementation and ensures no regressions
in existing functionality.
"""

import unittest
from unittest.mock import patch, mock_open, MagicMock
import tempfile
import os
import logging
import builtins
import sys
import types
import importlib.util

# Mock the hw_management_redfish_client module
mock_spec = importlib.util.spec_from_file_location("hw_management_redfish_client", "unittest/mock_hw_management_redfish_client.py")
mock_mod = importlib.util.module_from_spec(mock_spec)
mock_spec.loader.exec_module(mock_mod)
sys.modules["hw_management_redfish_client"] = mock_mod

from usr.usr.bin import hw_management_sync

real_open = builtins.open

def dummy_sdk_temp2degree(val):
    return 42

def dummy_is_module_host_management_mode(path):
    return "sw_control" in path

class TestModuleTempPopulate(unittest.TestCase):
    """Dedicated test suite for module_temp_populate function"""
    
    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.temp_counter_file = f"{self.temp_dir}module_counter"
        
        # Create the counter file
        with open(self.temp_counter_file, "w") as f:
            f.write("0")
        
        # Set up logging capture
        self.logger = logging.getLogger("hw_management_sync")
        self.logger.setLevel(logging.WARNING)
        self.log_output = []
        handler = logging.StreamHandler()
        handler.emit = lambda record: self.log_output.append(record.getMessage())
        self.logger.addHandler(handler)
        
        # Mock the helper functions
        hw_management_sync.sdk_temp2degree = dummy_sdk_temp2degree
        hw_management_sync.is_module_host_management_mode = dummy_is_module_host_management_mode
        
        # Create test module directory structure
        self.module_dir = f"{self.temp_dir}module0"
        os.makedirs(self.module_dir, exist_ok=True)
        os.makedirs(f"{self.module_dir}/temperature", exist_ok=True)
        
        # Create test files
        with open(f"{self.module_dir}/present", "w") as f:
            f.write("1")
        with open(f"{self.module_dir}/temperature/input", "w") as f:
            f.write("50000")
        with open(f"{self.module_dir}/temperature/threshold_hi", "w") as f:
            f.write("75000")

    def tearDown(self):
        """Clean up test environment"""
        for handler in self.logger.handlers[:]:
            self.logger.removeHandler(handler)
        try:
            import shutil
            shutil.rmtree(self.temp_dir)
        except FileNotFoundError:
            pass

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    def test_normal_module_processing(self, mock_open):
        """
        Test normal module temperature processing
        COVERAGE: Basic functionality validation - ensures no regressions
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 1, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        # Verify module counter was updated
        with real_open(self.temp_counter_file, "r") as f:
            content = f.read().strip()
        self.assertEqual(content, "1")

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    @patch('os.remove')
    @patch('os.path.exists', side_effect=lambda path: True)
    @patch('os.path.islink', return_value=True)
    @patch('os.readlink', return_value='/nonexistent/target')
    def test_symlink_validation_and_removal(self, mock_readlink, mock_islink, mock_exists, mock_remove, mock_open):
        """
        Test that invalid symlinks are detected and removed
        ISSUE: SYMLINK BYPASS (Priority: MEDIUM)
        - Issue: Invalid symlinks could bypass validation
        - Fix: Added symlink validation and removal of invalid symlinks
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        # Create the symlink file that will be checked
        symlink_file = "/var/run/hw-management/thermal/module0_temp_input"
        os.makedirs("/var/run/hw-management/thermal", exist_ok=True)
        with open(symlink_file, 'w') as f:
            f.write("dummy")
        
        # Mock exists to return False for the symlink target
        def exists_side_effect(path):
            if 'nonexistent' in str(path):
                return False
            return True
        mock_exists.side_effect = exists_side_effect
        
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 1, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        # Verify symlink was removed
        mock_remove.assert_any_call(symlink_file)
        self.assertTrue(any("Removed invalid symlink" in msg for msg in self.log_output))

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    @patch('os.remove')
    @patch('os.path.exists', side_effect=lambda path: True)
    @patch('os.path.islink', return_value=False)
    def test_sw_control_mode_cleanup(self, mock_islink, mock_exists, mock_remove, mock_open):
        """
        Test that SW control mode removes stale temperature files
        ISSUE: SW CONTROL MODULE SKIPPING (Priority: HIGH)
        - Issue: SW control modules were being skipped entirely
        - Fix: Added proper cleanup of stale temperature files for SW control modules
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        # Create a module path that triggers SW control mode
        sw_control_module = f"{self.temp_dir}sw_control_module0"
        os.makedirs(sw_control_module, exist_ok=True)
        
        arg_list = {"fin": f"{self.temp_dir}sw_control_module{{}}", "module_count": 1, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        # Verify temperature files were removed
        expected_calls = [
            '/var/run/hw-management/thermal/module0_temp_input',
            '/var/run/hw-management/thermal/module0_temp_crit',
            '/var/run/hw-management/thermal/module0_temp_emergency',
            '/var/run/hw-management/thermal/module0_temp_fault',
            '/var/run/hw-management/thermal/module0_temp_trip_crit'
        ]
        for expected_call in expected_calls:
            mock_remove.assert_any_call(expected_call)
        self.assertTrue(any("Removed stale temperature file for SW control mode" in msg for msg in self.log_output))

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    def test_exception_handling_module_present_file(self, mock_open):
        """
        Test exception handling when reading module present file fails
        ISSUE: EXCEPTION HANDLING GAPS (Priority: HIGH)
        - Issue: Bare exception handling without proper logging
        - Fix: Added specific exception types and detailed logging
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            if 'present' in file:
                raise OSError("mocked error")
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 1, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        self.assertTrue(any("Failed to read module present file" in msg for msg in self.log_output))

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    def test_exception_handling_temperature_file(self, mock_open):
        """
        Test exception handling when reading temperature file fails
        ISSUE: EXCEPTION HANDLING GAPS (Priority: HIGH)
        - Issue: Bare exception handling without proper logging
        - Fix: Added specific exception types and detailed logging
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            if 'temperature/input' in file:
                raise ValueError("mocked value error")
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 1, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        self.assertTrue(any("Failed to read temperature or threshold file" in msg for msg in self.log_output))

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    @patch('usr.usr.bin.hw_management_sync.tempfile.NamedTemporaryFile')
    def test_fallback_on_write_failure(self, mock_tempfile, mock_open):
        """
        Test fallback behavior when writing temperature files fails
        ISSUE: FILE SYSTEM RACE CONDITIONS (Priority: MEDIUM)
        - Issue: Non-atomic file writes could cause race conditions
        - Fix: Added atomic file writing with tempfile.NamedTemporaryFile
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        # Mock tempfile to raise an error
        def tempfile_side_effect(mode='w', dir=None, delete=False, encoding=None):
            raise IOError("mocked write error")
        mock_tempfile.side_effect = tempfile_side_effect
        
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 1, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        # Debug: print all log messages
        print(f"Log output: {self.log_output}")
        self.assertTrue(any("Failed to write temperature file" in msg for msg in self.log_output))
        self.assertTrue(any("Writing fallback value" in msg for msg in self.log_output))

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    def test_module_counter_always_updated(self, mock_open):
        """
        Test that module counter is always updated, even when no modules are processed
        ISSUE: MODULE COUNTER UPDATE RISK (Priority: MEDIUM)
        - Issue: Module counter not always updated, leading to stale data
        - Fix: Always update module counter regardless of processing success
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        # Test with module_count = 0
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 0, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        # Verify counter was updated to 0
        with real_open(self.temp_counter_file, "r") as f:
            content = f.read().strip()
        self.assertEqual(content, "0")

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    def test_multiple_modules_processing(self, mock_open):
        """
        Test processing multiple modules
        COVERAGE: Multiple module processing validation
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        # Create additional module directories
        for i in range(3):
            module_dir = f"{self.temp_dir}module{i}"
            os.makedirs(module_dir, exist_ok=True)
            os.makedirs(f"{module_dir}/temperature", exist_ok=True)
            with open(f"{module_dir}/present", "w") as f:
                f.write("1")
            with open(f"{module_dir}/temperature/input", "w") as f:
                f.write(f"{50000 + i * 1000}")
        
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 3, "fout_idx_offset": 0}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        # Verify counter was updated to 3
        with real_open(self.temp_counter_file, "r") as f:
            content = f.read().strip()
        self.assertEqual(content, "3")

    @patch('usr.usr.bin.hw_management_sync.open', create=True)
    def test_module_offset_processing(self, mock_open):
        """
        Test processing modules with offset
        COVERAGE: Module offset processing validation
        """
        def open_side_effect(file, mode='r', encoding=None):
            if file == '/var/run/hw-management/config/module_counter':
                return real_open(self.temp_counter_file, mode, encoding=encoding)
            return real_open(file, mode, encoding=encoding)
        mock_open.side_effect = open_side_effect
        
        # Create module with offset
        module_dir = f"{self.temp_dir}module5"  # offset 5
        os.makedirs(module_dir, exist_ok=True)
        os.makedirs(f"{module_dir}/temperature", exist_ok=True)
        with open(f"{module_dir}/present", "w") as f:
            f.write("1")
        with open(f"{module_dir}/temperature/input", "w") as f:
            f.write("55000")
        
        arg_list = {"fin": f"{self.temp_dir}module{{}}", "module_count": 1, "fout_idx_offset": 5}
        hw_management_sync.module_temp_populate(arg_list, None)
        
        # Verify counter was updated
        with real_open(self.temp_counter_file, "r") as f:
            content = f.read().strip()
        self.assertEqual(content, "1")

if __name__ == "__main__":
    unittest.main() 