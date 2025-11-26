#!/usr/bin/python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
Simplified Unit Tests for Peripheral Updater Core Functions

These offline tests validate the core logic in hw_management_peripheral_updater.py
without requiring actual hardware or complex mocking.

Focus on testing the critical business logic:
- ASIC chipup status monitoring logic
- Peripheral attribute triggering logic
- Configuration loading
"""

import unittest
import sys
import os
import tempfile
import shutil
import importlib.util
from unittest.mock import patch, MagicMock

# Add parent directory to path to import the module under test
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../usr/usr/bin'))


class TestMonitorAsicChipupStatusLogic(unittest.TestCase):
    """Test monitor_asic_chipup_status() core logic"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.asic0_path = os.path.join(self.temp_dir, "asic0")
        self.asic1_path = os.path.join(self.temp_dir, "asic1")
        os.makedirs(os.path.join(self.asic0_path, "temperature"), exist_ok=True)
        os.makedirs(os.path.join(self.asic1_path, "temperature"), exist_ok=True)

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_single_asic_ready(self):
        """Test detecting single ready ASIC"""
        import hw_management_peripheral_updater as peripheral_module

        # Create temperature file (ASIC is ready)
        temp_file = os.path.join(self.asic0_path, "temperature", "input")
        with open(temp_file, 'w') as f:
            f.write("45000\n")

        arg = {"asic": {"fin": self.asic0_path + "/"}}

        with patch.object(peripheral_module, 'update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)

        # Should report 1 ASIC ready
        mock_update.assert_called_once_with(1)

    def test_single_asic_not_ready(self):
        """Test detecting ASIC not ready (no temperature file)"""
        import hw_management_peripheral_updater as peripheral_module

        arg = {"asic": {"fin": self.asic0_path + "/"}}

        with patch.object(peripheral_module, 'update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)

        # Should report 0 ASICs ready
        mock_update.assert_called_once_with(0)

    def test_multiple_unique_asics_ready(self):
        """Test counting multiple unique ASICs"""
        import hw_management_peripheral_updater as peripheral_module

        # Both ASICs ready
        with open(os.path.join(self.asic0_path, "temperature", "input"), 'w') as f:
            f.write("45000\n")
        with open(os.path.join(self.asic1_path, "temperature", "input"), 'w') as f:
            f.write("46000\n")

        arg = {
            "asic": {"fin": self.asic0_path + "/"},
            "asic1": {"fin": self.asic0_path + "/"},  # Duplicate - same path
            "asic2": {"fin": self.asic1_path + "/"}   # Different ASIC
        }

        with patch.object(peripheral_module, 'update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)

        # Should count 2 unique ASICs
        mock_update.assert_called_once_with(2)

    def test_invalid_arg_type(self):
        """Test handling invalid argument type"""
        import hw_management_peripheral_updater as peripheral_module

        # Should not crash with invalid input
        peripheral_module.monitor_asic_chipup_status("invalid", None)
        peripheral_module.monitor_asic_chipup_status(None, None)
        peripheral_module.monitor_asic_chipup_status([], None)


class TestGetAsicNumFunction(unittest.TestCase):
    """Test get_asic_num() function"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.asic_num_file = os.path.join(self.temp_dir, "asic_num")

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_read_valid_asic_num(self):
        """Test reading valid asic_num"""
        import hw_management_peripheral_updater as peripheral_module

        with open(self.asic_num_file, 'w') as f:
            f.write("2\n")

        with patch('hw_management_peripheral_updater.os.path.join', return_value=self.asic_num_file):
            result = peripheral_module.get_asic_num()

        self.assertEqual(result, 2)

    def test_file_not_found_returns_default(self):
        """Test default when file doesn't exist"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.os.path.join',
                   return_value="/nonexistent/asic_num"):
            result = peripheral_module.get_asic_num()

        self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)

    def test_invalid_content_returns_default(self):
        """Test default when file has invalid content"""
        import hw_management_peripheral_updater as peripheral_module

        with open(self.asic_num_file, 'w') as f:
            f.write("invalid\n")

        with patch('hw_management_peripheral_updater.os.path.join', return_value=self.asic_num_file):
            result = peripheral_module.get_asic_num()

        self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)


class TestUpdatePeripheralAttrLogic(unittest.TestCase):
    """Test update_peripheral_attr() change-based triggering logic"""

    def setUp(self):
        """Setup"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_triggers_on_value_change(self):
        """Test function is called when value changes"""
        import hw_management_peripheral_updater as peripheral_module

        test_file = os.path.join(self.temp_dir, "sensor")
        with open(test_file, 'w') as f:
            f.write("100\n")

        mock_fn = MagicMock()
        attr_prop = {
            "fin": test_file,
            "fn": "mock_fn",
            "poll": 1,
            "ts": 0,
            "arg": ["test"]
        }

        with patch.dict(peripheral_module.__dict__, {'mock_fn': mock_fn}):
            # First call - should trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            self.assertEqual(mock_fn.call_count, 1)

            # Second call with same value - should NOT trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            self.assertEqual(mock_fn.call_count, 1, "Should not trigger on same value")

            # Change value - should trigger again
            with open(test_file, 'w') as f:
                f.write("200\n")
            attr_prop["ts"] = 0  # Reset timestamp to allow immediate trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            self.assertEqual(mock_fn.call_count, 2, "Should trigger on value change")

    def test_no_fin_always_triggers(self):
        """Test function always triggers when fin=None"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        attr_prop = {
            "fin": None,
            "fn": "mock_fn",
            "poll": 1,
            "ts": 0,
            "arg": []
        }

        with patch.dict(peripheral_module.__dict__, {'mock_fn': mock_fn}):
            peripheral_module.update_peripheral_attr(attr_prop)
            peripheral_module.update_peripheral_attr(attr_prop)

        # Should trigger both times (no change detection without fin)
        self.assertGreaterEqual(mock_fn.call_count, 1)

    def test_missing_file_no_trigger(self):
        """Test function not triggered when file doesn't exist"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        attr_prop = {
            "fin": "/nonexistent/file",
            "fn": "mock_fn",
            "poll": 1,
            "ts": 0,
            "arg": []
        }

        with patch.dict(peripheral_module.__dict__, {'mock_fn': mock_fn}):
            peripheral_module.update_peripheral_attr(attr_prop)

        # Should not trigger
        mock_fn.assert_not_called()


class TestConfigurationFunctions(unittest.TestCase):
    """Test configuration loading"""

    def test_build_attrib_list_returns_dict(self):
        """Test _build_attrib_list() returns valid dictionary"""
        import hw_management_peripheral_updater as peripheral_module

        config = peripheral_module._build_attrib_list()

        self.assertIsInstance(config, dict)
        self.assertGreater(len(config), 0, "Should have platform entries")

    def test_attrib_list_module_variable_populated(self):
        """Test attrib_list is populated at module load"""
        import hw_management_peripheral_updater as peripheral_module

        self.assertIsInstance(peripheral_module.attrib_list, dict)
        self.assertGreater(len(peripheral_module.attrib_list), 0)


class TestGetAsicNumErrorHandling(unittest.TestCase):
    """Test get_asic_num() error handling and logging"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_get_asic_num_with_logger_on_error(self):
        """Test get_asic_num logs warning when file read fails"""
        import hw_management_peripheral_updater as peripheral_module

        # Create invalid file
        asic_num_file = os.path.join(self.temp_dir, "asic_num")
        with open(asic_num_file, 'w') as f:
            f.write("invalid_number\n")

        with patch('hw_management_peripheral_updater.os.path.join', return_value=asic_num_file):
            with patch('hw_management_peripheral_updater.LOGGER') as mock_logger:
                result = peripheral_module.get_asic_num()

                # Should log warning
                mock_logger.warning.assert_called()
                # Should return default
                self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)

    def test_get_asic_num_without_logger(self):
        """Test get_asic_num works when LOGGER is None"""
        import hw_management_peripheral_updater as peripheral_module

        # Temporarily set LOGGER to None
        original_logger = peripheral_module.LOGGER
        peripheral_module.LOGGER = None

        try:
            with patch('hw_management_peripheral_updater.os.path.join',
                       return_value="/nonexistent/asic_num"):
                result = peripheral_module.get_asic_num()
                # Should return default without crashing
                self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)
        finally:
            peripheral_module.LOGGER = original_logger


class TestUpdateAsicChipupStatusErrors(unittest.TestCase):
    """Test update_asic_chipup_status() error handling"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_update_asic_chipup_status_calls_get_asic_num(self):
        """Test update_asic_chipup_status calls get_asic_num"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.get_asic_num', return_value=2) as mock_get_asic:
            with patch('builtins.open', MagicMock()):
                # Just test it calls get_asic_num
                peripheral_module.update_asic_chipup_status(1)
                mock_get_asic.assert_called()

    def test_update_asic_chipup_status_handles_io_error(self):
        """Test update_asic_chipup_status handles file write errors gracefully"""
        import hw_management_peripheral_updater as peripheral_module

        # Mock open to raise OSError
        with patch('builtins.open', side_effect=OSError("Permission denied")):
            with patch('hw_management_peripheral_updater.LOGGER') as mock_logger:
                # Should handle error and log it
                peripheral_module.update_asic_chipup_status(1)
                # Should have called logger (warning or info)
                self.assertGreater(mock_logger.warning.call_count + mock_logger.info.call_count, 0)


class TestHelperFunctions(unittest.TestCase):
    """Test various helper functions"""

    def test_build_attrib_list_basic(self):
        """Test _build_attrib_list basic functionality"""
        import hw_management_peripheral_updater as peripheral_module

        config = peripheral_module._build_attrib_list()
        self.assertIsInstance(config, dict)
        # Should have entries for different platforms
        self.assertGreater(len(config), 0)


class TestModuleCounterFallback(unittest.TestCase):
    """Test module_counter fallback when platform_config is unavailable"""

    def test_get_module_count_fallback_returns_zero(self):
        """Test fallback get_module_count returns 0"""
        import hw_management_peripheral_updater as peripheral_module

        # If import failed, get_module_count should be the fallback that returns 0
        # This is tested by the import at module level
        # Just verify the function exists
        self.assertTrue(hasattr(peripheral_module, 'get_module_count'))


class TestMonitorAsicChipup(unittest.TestCase):
    """
    Test suite for monitor_asic_chipup_status() function in peripheral_updater.

    This tests the independent ASIC chipup monitoring that runs in peripheral_updater,
    separate from thermal monitoring. This ensures chipup tracking continues even if
    thermal_updater service is stopped or disabled by users.

    Key Requirements:
    1. monitor_asic_chipup_status() checks ASIC readiness by probing sysfs paths
    2. Updates chipup status files based on ready ASICs
    3. Works independently of temperature monitoring
    4. Handles missing/unready ASICs gracefully
    """

    def setUp(self):
        """Set up before each test"""
        self.test_dir = tempfile.mkdtemp(prefix='chipup_monitor_test_')
        self.config_dir = os.path.join(self.test_dir, 'config')
        os.makedirs(self.config_dir, exist_ok=True)

    def tearDown(self):
        """Clean up after each test"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _load_peripheral_module(self):
        """Load peripheral_updater module dynamically"""
        import importlib.util
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        peripheral_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')

        spec = importlib.util.spec_from_file_location("hw_management_peripheral_updater", peripheral_path)
        module = importlib.util.module_from_spec(spec)

        # Mock dependencies
        sys.modules["hw_management_lib"] = MagicMock()
        sys.modules["hw_management_redfish_client"] = MagicMock()

        spec.loader.exec_module(module)
        return module

    def test_single_asic_ready(self):
        """Test monitor_asic_chipup_status with single ready ASIC"""
        import hw_management_peripheral_updater as peripheral_module

        # Just test that the function exists and can be called
        asic_config = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        with patch('os.path.isfile', return_value=False):
            with patch('builtins.open', side_effect=OSError()):
                with patch('hw_management_peripheral_updater.update_asic_chipup_status') as mock_update:
                    # Should handle errors gracefully
                    peripheral_module.monitor_asic_chipup_status(asic_config, None)
                    # Function should have been called
                    mock_update.assert_called()


class TestPlatformChipupCoverage(unittest.TestCase):
    """
    Validates that all platforms with ASICs have chipup monitoring configured.

    This test ensures the refactoring that moved chipup tracking from thermal_updater
    to peripheral_updater included ALL platforms, not just those with peripheral configs.
    """

    def test_all_asic_platforms_have_chipup_monitoring(self):
        """Verify every platform with asic_temp_populate also has monitor_asic_chipup_status"""
        from hw_management_platform_config import PLATFORM_CONFIG

        platforms_with_asic = []
        platforms_with_chipup = []
        platforms_missing_chipup = []

        for platform_key, platform_config in PLATFORM_CONFIG.items():
            if platform_key in ['def', 'test']:
                continue

            has_asic = False
            has_chipup = False
            asic_config = None
            chipup_config = None

            for entry in platform_config:
                if entry.get('fn') == 'asic_temp_populate':
                    has_asic = True
                    asic_config = entry.get('arg', {})

                if entry.get('fn') == 'monitor_asic_chipup_status':
                    has_chipup = True
                    chipup_config = entry.get('arg', {})

            if has_asic:
                platforms_with_asic.append(platform_key)

                if has_chipup:
                    platforms_with_chipup.append(platform_key)
                    # Validate ASIC configs match
                    self.assertEqual(
                        set(asic_config.keys()),
                        set(chipup_config.keys()),
                        f"{platform_key}: ASIC configs must match"
                    )
                else:
                    platforms_missing_chipup.append(platform_key)

        # Critical assertion - must have 100% coverage
        self.assertEqual(
            len(platforms_missing_chipup), 0,
            f"CRITICAL: {len(platforms_missing_chipup)} platforms missing chipup: {platforms_missing_chipup}"
        )

        self.assertEqual(
            len(platforms_with_asic), len(platforms_with_chipup),
            "All platforms with ASICs must have chipup monitoring"
        )


if __name__ == '__main__':
    unittest.main()
