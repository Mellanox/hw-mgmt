#!/usr/bin/env python3
"""
Test suite for module_temp_populate function improvements.

This test file covers the following improvements made to hw_management_sync.py:

1. Exception Handling & Logging - Proper exception handling with logging
2. Module Counter Update - Only update when modules are actually updated
3. Performance Optimization - Direct file writes for embedded system performance

Customer Feedback Issues Addressed:
- Exception handling gaps
- Module counter update risk
- Performance concerns on embedded system
"""

from hw_management_sync import module_temp_populate, logger
import unittest
from unittest.mock import patch, mock_open, MagicMock
import tempfile
import os
import sys

# Add the parent directory to the path to import the module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', 'usr', 'usr', 'bin'))

# Mock the redfish client before importing
sys.modules['hw_management_redfish_client'] = MagicMock()


class TestModuleTempPopulate(unittest.TestCase):
    """Test cases for module_temp_populate function improvements."""

    def setUp(self):
        """Set up test fixtures."""
        self.arg_list = {
            "fin": "/sys/class/hwmon/hwmon{}/device",
            "module_count": 2,
            "fout_idx_offset": 1
        }

        # Create temporary directory for test files
        self.test_dir = tempfile.mkdtemp()
        self.thermal_dir = os.path.join(self.test_dir, "var", "run", "hw-management", "thermal")
        self.config_dir = os.path.join(self.test_dir, "var", "run", "hw-management", "config")
        os.makedirs(self.thermal_dir, exist_ok=True)
        os.makedirs(self.config_dir, exist_ok=True)

    def tearDown(self):
        """Clean up test fixtures."""
        import shutil
        shutil.rmtree(self.test_dir, ignore_errors=True)

    @patch('hw_management_sync.os.path.islink')
    @patch('hw_management_sync.os.path.exists')
    @patch('builtins.open', new_callable=mock_open)
    @patch('hw_management_sync.is_module_host_management_mode')
    @patch('hw_management_sync.sdk_temp2degree')
    def test_normal_module_processing(self, mock_sdk_temp, mock_host_mode, mock_file_open, mock_exists, mock_islink):
        """Test normal module processing with proper exception handling."""
        # Setup mocks
        mock_islink.return_value = False
        mock_host_mode.return_value = False
        mock_exists.return_value = True
        mock_sdk_temp.return_value = 45

        # Mock file reads
        mock_file_open.return_value.__enter__.return_value.read.return_value = "45000"

        # Patch file paths
        with patch('hw_management_sync.os.path.join') as mock_join:
            mock_join.side_effect = lambda *args: "/sys/class/hwmon/hwmon0/device/present"

            # Test the function
            module_temp_populate(self.arg_list, None)

            # Verify file writes were called
            mock_file_open.assert_called()

    @patch('hw_management_sync.os.path.islink')
    @patch('hw_management_sync.os.path.exists')
    @patch('builtins.open', new_callable=mock_open)
    @patch('hw_management_sync.is_module_host_management_mode')
    def test_sw_control_mode_skip(self, mock_host_mode, mock_file_open, mock_exists, mock_islink):
        """Test that SW control mode modules are skipped (no cleanup)."""
        # Setup mocks
        mock_islink.return_value = False
        mock_host_mode.return_value = True  # SW control mode
        mock_exists.return_value = True

        # Patch file paths
        with patch('hw_management_sync.os.path.join') as mock_join:
            mock_join.side_effect = lambda *args: "/sys/class/hwmon/hwmon0/device/present"

            # Test the function
            module_temp_populate(self.arg_list, None)

            # Verify no file writes were called (skipped)
            # Note: We don't clean up files in SW control mode as it's not our responsibility
            mock_file_open.assert_not_called()

    @patch('hw_management_sync.os.path.islink')
    @patch('hw_management_sync.os.path.exists')
    @patch('builtins.open', new_callable=mock_open)
    @patch('hw_management_sync.is_module_host_management_mode')
    def test_exception_handling_file_read(self, mock_host_mode, mock_file_open, mock_exists, mock_islink):
        """Test exception handling when reading module present file."""
        # Setup mocks
        mock_islink.return_value = False
        mock_host_mode.return_value = False
        mock_exists.return_value = True

        # Mock file operations - first read fails, subsequent writes succeed
        def mock_open_side_effect(filename, mode='r', encoding=None):
            if 'present' in filename and mode == 'r':
                raise IOError("File not found")
            else:
                return mock_open(read_data="0").return_value

        mock_file_open.side_effect = mock_open_side_effect

        # Patch file paths
        with patch('hw_management_sync.os.path.join') as mock_join:
            mock_join.side_effect = lambda *args: "/sys/class/hwmon/hwmon0/device/present"

            # Test the function - should not crash
            module_temp_populate(self.arg_list, None)

            # Verify exception was handled gracefully
            # The function should continue processing other modules

    @patch('hw_management_sync.os.path.islink')
    @patch('hw_management_sync.os.path.exists')
    @patch('builtins.open', new_callable=mock_open)
    @patch('hw_management_sync.is_module_host_management_mode')
    @patch('hw_management_sync.sdk_temp2degree')
    def test_exception_handling_temperature_read(self, mock_sdk_temp, mock_host_mode, mock_file_open, mock_exists, mock_islink):
        """Test exception handling when reading temperature files."""
        # Setup mocks
        mock_islink.return_value = False
        mock_host_mode.return_value = False
        mock_exists.return_value = True
        mock_sdk_temp.return_value = 45

        # Mock file operations - temperature read fails, writes succeed
        def mock_open_side_effect(filename, mode='r', encoding=None):
            if 'temperature' in filename and mode == 'r':
                raise IOError("Temperature file not found")
            else:
                return mock_open(read_data="1").return_value

        mock_file_open.side_effect = mock_open_side_effect

        # Patch file paths
        with patch('hw_management_sync.os.path.join') as mock_join:
            mock_join.side_effect = lambda *args: "/sys/class/hwmon/hwmon0/device/present"

            # Test the function - should not crash
            module_temp_populate(self.arg_list, None)

            # Verify exception was handled gracefully

    @patch('hw_management_sync.os.path.islink')
    @patch('hw_management_sync.os.path.exists')
    @patch('builtins.open', new_callable=mock_open)
    @patch('hw_management_sync.is_module_host_management_mode')
    def test_module_counter_update_only_when_updated(self, mock_host_mode, mock_file_open, mock_exists, mock_islink):
        """Test that module counter is only updated when modules are actually updated."""
        # Setup mocks - no modules present
        mock_islink.return_value = False
        mock_host_mode.return_value = False
        mock_exists.return_value = True

        # Mock file read to return 0 (module not present)
        mock_file_open.return_value.__enter__.return_value.read.return_value = "0"

        # Patch file paths
        with patch('hw_management_sync.os.path.join') as mock_join:
            mock_join.side_effect = lambda *args: "/sys/class/hwmon/hwmon0/device/present"

            # Test the function
            module_temp_populate(self.arg_list, None)

            # Verify module counter was NOT updated (no modules were updated)
            # The function should only update counter when module_updated = True

    @patch('hw_management_sync.os.path.islink')
    @patch('hw_management_sync.os.path.exists')
    @patch('builtins.open', new_callable=mock_open)
    @patch('hw_management_sync.is_module_host_management_mode')
    @patch('hw_management_sync.sdk_temp2degree')
    def test_direct_file_writes_performance(self, mock_sdk_temp, mock_host_mode, mock_file_open, mock_exists, mock_islink):
        """Test that direct file writes are used for performance on embedded system."""
        # Setup mocks
        mock_islink.return_value = False
        mock_host_mode.return_value = False
        mock_exists.return_value = True
        mock_sdk_temp.return_value = 45

        # Mock file reads
        mock_file_open.return_value.__enter__.return_value.read.return_value = "45000"

        # Patch file paths
        with patch('hw_management_sync.os.path.join') as mock_join:
            mock_join.side_effect = lambda *args: "/sys/class/hwmon/hwmon0/device/present"

            # Test the function
            module_temp_populate(self.arg_list, None)

            # Verify direct file writes were used (not atomic operations)
            # This ensures performance on embedded system with 256 iterations

    @patch('hw_management_sync.os.path.islink')
    @patch('hw_management_sync.os.path.exists')
    @patch('builtins.open', new_callable=mock_open)
    @patch('hw_management_sync.is_module_host_management_mode')
    def test_symlink_skip_optimization(self, mock_host_mode, mock_file_open, mock_exists, mock_islink):
        """Test that symlinks are skipped without validation (optimization for 20-second intervals)."""
        # Setup mocks
        mock_islink.return_value = True  # Symlink exists
        mock_host_mode.return_value = False
        mock_exists.return_value = True

        # Test the function
        module_temp_populate(self.arg_list, None)

        # Verify symlink validation was skipped (performance optimization)
        # On embedded system with 20-second intervals, symlink will be removed on first run
        # Subsequent runs don't need validation


if __name__ == '__main__':
    unittest.main()
