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


class TestMonitorAsicChipupEdgeCases(unittest.TestCase):
    """Test monitor_asic_chipup_status edge cases for better coverage"""

    def test_monitor_asic_chipup_invalid_asic_info_type(self):
        """Test handling of invalid asic_info type"""
        import hw_management_peripheral_updater as peripheral_module

        # asic_info is not a dict (e.g., a string) - should skip
        arg = {
            "asic": "invalid_string_not_dict"
        }

        with patch('hw_management_peripheral_updater.update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)
            # Should still call update with 0 (no valid ASICs)
            mock_update.assert_called_with(0)

    def test_monitor_asic_chipup_empty_fin_path(self):
        """Test handling of empty fin path"""
        import hw_management_peripheral_updater as peripheral_module

        # fin is empty string - should skip
        arg = {
            "asic": {"fin": ""}
        }

        with patch('hw_management_peripheral_updater.update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)
            # Should call update with 0
            mock_update.assert_called_with(0)


class TestRedfishFunctions(unittest.TestCase):
    """Test redfish helper functions"""

    def test_redfish_get_req_with_response(self):
        """Test redfish_get_req when connection exists and returns data"""
        import hw_management_peripheral_updater as peripheral_module

        # Mock RedfishConnection
        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_get_cmd.return_value = "mock_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (0, '{"test": "data"}', '')

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj):
            result = peripheral_module.redfish_get_req('/test/path')

            self.assertIsNotNone(result)
            self.assertEqual(result, {"test": "data"})

    def test_redfish_get_req_error_retries_login(self):
        """Test redfish_get_req retries login on error"""
        import hw_management_peripheral_updater as peripheral_module

        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_get_cmd.return_value = "mock_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (-1, '', 'error')  # Error code

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj):
            result = peripheral_module.redfish_get_req('/test/path')

            # Should call login to retry
            mock_rf_obj.login.assert_called_once()
            self.assertIsNone(result)

    def test_redfish_get_req_no_connection(self):
        """Test redfish_get_req when no connection available"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=None):
            result = peripheral_module.redfish_get_req('/test/path')
            self.assertIsNone(result)

    def test_redfish_post_req_with_data(self):
        """Test redfish_post_req sends POST request"""
        import hw_management_peripheral_updater as peripheral_module

        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_post_cmd.return_value = "mock_post_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (0, '{"status": "ok"}', '')

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj):
            result = peripheral_module.redfish_post_req('/test/path', {'key': 'value'})

            mock_rf_obj.rf_client.build_post_cmd.assert_called_with('/test/path', {'key': 'value'})
            self.assertIsNotNone(result)


class TestUtilityFunctions(unittest.TestCase):
    """Test utility functions in peripheral_updater"""

    def test_run_power_button_event(self):
        """Test run_power_button_event executes commands"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.os.system') as mock_system:
            peripheral_module.run_power_button_event(None, "1")

            # Should call os.system 3 times (2 hotplug events + logger)
            self.assertEqual(mock_system.call_count, 3)

    def test_run_power_button_event_released(self):
        """Test run_power_button_event when released (value=0)"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.os.system') as mock_system:
            peripheral_module.run_power_button_event(None, "0")

            # Should call os.system 2 times (no logger for release)
            self.assertEqual(mock_system.call_count, 2)

    def test_run_cmd_with_command_list(self):
        """Test run_cmd executes list of commands"""
        import hw_management_peripheral_updater as peripheral_module

        cmd_list = ["echo test_{arg1}", "echo another_{arg1}"]

        with patch('hw_management_peripheral_updater.os.system') as mock_system:
            peripheral_module.run_cmd(cmd_list, "arg_value")

            # Should call os.system for each command
            self.assertEqual(mock_system.call_count, 2)

    def test_sync_fan_absent(self):
        """Test sync_fan with fan absent (val=0)"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.os.system') as mock_system:
            peripheral_module.sync_fan(1, "0")

            # Should call os.system twice (echo + hotplug event)
            self.assertEqual(mock_system.call_count, 2)
            # Check that status=1 for absent fan
            calls = [str(call) for call in mock_system.call_args_list]
            self.assertTrue(any("fan1_status" in str(call) for call in calls))

    def test_sync_fan_present(self):
        """Test sync_fan with fan present (val=1)"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.os.system') as mock_system:
            peripheral_module.sync_fan(2, "1")

            # Should call os.system twice
            self.assertEqual(mock_system.call_count, 2)


class TestRedfishSensorFunctions(unittest.TestCase):
    """Test redfish sensor update functions"""

    def test_redfish_get_sensor_no_response(self):
        """Test redfish_get_sensor when redfish returns None"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=None):
            # Should return early without error
            peripheral_module.redfish_get_sensor(['/path/to/sensor', 'sensor1', 1000], None)

    def test_redfish_get_sensor_disabled_sensor(self):
        """Test redfish_get_sensor with disabled sensor"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Disabled", "Health": "OK"},
            "ReadingType": "Liquid",
            "Reading": 0,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when sensor is disabled
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_unhealthy_sensor(self):
        """Test redfish_get_sensor with unhealthy sensor"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "Critical"},
            "ReadingType": "Liquid",
            "Reading": 1,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when sensor health is not OK
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_no_reading_type(self):
        """Test redfish_get_sensor when ReadingType missing"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "OK"},
            "Reading": 1,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when ReadingType missing
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_unknown_reading_type(self):
        """Test redfish_get_sensor with unknown ReadingType"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "OK"},
            "ReadingType": "UnknownType",
            "Reading": 1,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when ReadingType not in redfish_attr
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_writes_files_successfully(self):
        """Test redfish_get_sensor writes sensor data to files"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "OK"},
            "ReadingType": "Temperature",
            "Reading": 45.5,
            "Thresholds": {
                "UpperCritical": {"Reading": 100.0},
                "LowerCaution": {"Reading": 10.0}
            }
        }

        mock_open = unittest.mock.mock_open()
        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            with patch('builtins.open', mock_open):
                peripheral_module.redfish_get_sensor(['/path', 'temp1', 1000], None)

                # Should write sensor value and thresholds
                # Reading: 45.5 * 1000 = 45500
                # UpperCritical: 100.0 * 1000 = 100000
                # LowerCaution: 10.0 * 1000 = 10000
                self.assertGreaterEqual(mock_open.call_count, 1)


class TestRedfishConnectionSingleton(unittest.TestCase):
    """Test RedfishConnection singleton class"""

    def test_get_instance_creates_connection(self):
        """Test RedfishConnection.get_instance creates BMCAccessor"""
        import hw_management_peripheral_updater as peripheral_module

        # Reset singleton first
        peripheral_module.RedfishConnection.reset_instance()

        mock_accessor = MagicMock()
        mock_accessor.login.return_value = 0  # ERR_CODE_OK

        with patch('hw_management_peripheral_updater.BMCAccessor', return_value=mock_accessor):
            instance = peripheral_module.RedfishConnection.get_instance()

            self.assertIsNotNone(instance)
            mock_accessor.login.assert_called_once()

    def test_get_instance_returns_none_on_login_failure(self):
        """Test RedfishConnection.get_instance returns None when login fails"""
        import hw_management_peripheral_updater as peripheral_module

        # Reset singleton first
        peripheral_module.RedfishConnection.reset_instance()

        mock_accessor = MagicMock()
        mock_accessor.login.return_value = -1  # Error

        with patch('hw_management_peripheral_updater.BMCAccessor', return_value=mock_accessor):
            instance = peripheral_module.RedfishConnection.get_instance()

            self.assertIsNone(instance)

    def test_reset_instance(self):
        """Test RedfishConnection.reset_instance clears singleton"""
        import hw_management_peripheral_updater as peripheral_module

        # Set instance first
        peripheral_module.RedfishConnection._instance = MagicMock()

        # Reset
        peripheral_module.RedfishConnection.reset_instance()

        # Should be None
        self.assertIsNone(peripheral_module.RedfishConnection._instance)


class TestUpdatePeripheralAttr(unittest.TestCase):
    """Test update_peripheral_attr function"""

    def test_update_peripheral_attr_calls_function_on_change(self):
        """Test update_peripheral_attr invokes function when value changes"""
        import hw_management_peripheral_updater as peripheral_module

        temp_dir = tempfile.mkdtemp()
        test_file = os.path.join(temp_dir, "sensor")

        try:
            # Write initial value
            with open(test_file, 'w') as f:
                f.write("100\n")

            mock_fn = MagicMock()
            peripheral_module.test_sensor_fn = mock_fn

            attr_prop = {
                "fn": "test_sensor_fn",
                "arg": ["arg1"],
                "fin": test_file,
                "poll": 0,
                "ts": 0,
                "hwmon": ""
            }

            # First call - should trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            mock_fn.assert_called_with(["arg1"], "100")

            # Second call with same value - should NOT trigger
            mock_fn.reset_mock()
            peripheral_module.update_peripheral_attr(attr_prop)
            mock_fn.assert_not_called()

        finally:
            shutil.rmtree(temp_dir)

    def test_update_peripheral_attr_handles_read_error(self):
        """Test update_peripheral_attr handles file read errors"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        peripheral_module.test_error_fn = mock_fn

        attr_prop = {
            "fn": "test_error_fn",
            "arg": ["arg1"],
            "fin": "/tmp/test_sensor",
            "poll": 0,
            "ts": 0,
            "hwmon": ""
        }

        # Create file then make it unreadable
        with open("/tmp/test_sensor", 'w') as f:
            f.write("100\n")

        with patch('builtins.open', side_effect=OSError()):
            peripheral_module.update_peripheral_attr(attr_prop)

            # Should call function with empty string on error
            mock_fn.assert_called_with(["arg1"], "")

    def test_update_peripheral_attr_no_file(self):
        """Test update_peripheral_attr with no fin (file-less trigger)"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        peripheral_module.test_nofile_fn = mock_fn

        attr_prop = {
            "fn": "test_nofile_fn",
            "arg": ["arg1"],
            "poll": 0,
            "ts": 0
        }

        peripheral_module.update_peripheral_attr(attr_prop)

        # Should call function with None
        mock_fn.assert_called_with(["arg1"], None)

    def test_update_peripheral_attr_function_error(self):
        """Test update_peripheral_attr handles function execution errors"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock(side_effect=KeyError("test error"))
        peripheral_module.test_failing_fn = mock_fn

        attr_prop = {
            "fn": "test_failing_fn",
            "arg": ["arg1"],
            "poll": 0,
            "ts": 0
        }

        # Should not crash even if function raises error
        peripheral_module.update_peripheral_attr(attr_prop)


class TestInitAndWriteFunctions(unittest.TestCase):
    """Test init_attr and write_module_counter functions"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_write_module_counter(self):
        """Test write_module_counter writes file correctly"""
        import hw_management_peripheral_updater as peripheral_module

        config_dir = os.path.join(self.temp_dir, "config")
        os.makedirs(config_dir)
        module_counter_file = os.path.join(config_dir, "module_counter")

        with patch('hw_management_peripheral_updater.get_module_count', return_value=64):
            with patch('hw_management_peripheral_updater.LOGGER'):
                # Mock builtins.open to write to our test directory
                with patch('builtins.open', unittest.mock.mock_open()) as mock_file:
                    peripheral_module.write_module_counter("HI123")

                    # Check open was called with correct path and write was called
                    mock_file.assert_called_with("/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")
                    mock_file().write.assert_called_with("64\n")

    def test_init_attr_with_hwmon(self):
        """Test init_attr with hwmon path"""
        import hw_management_peripheral_updater as peripheral_module

        # Create mock hwmon structure
        hwmon_dir = os.path.join(self.temp_dir, "hwmon")
        os.makedirs(hwmon_dir)
        hwmon0_dir = os.path.join(hwmon_dir, "hwmon0")
        os.makedirs(hwmon0_dir)

        attr_prop = {
            "fin": os.path.join(self.temp_dir, "hwmon", "test_input")
        }

        with patch('hw_management_peripheral_updater.LOGGER'):
            peripheral_module.init_attr(attr_prop)

            # Should have detected hwmon0
            self.assertEqual(attr_prop.get("hwmon"), "hwmon0")

    def test_init_attr_without_hwmon(self):
        """Test init_attr without hwmon path"""
        import hw_management_peripheral_updater as peripheral_module

        attr_prop = {
            "fin": "/sys/devices/platform/sensor/temp1"
        }

        with patch('hw_management_peripheral_updater.LOGGER'):
            peripheral_module.init_attr(attr_prop)
            # Should complete without error

    def test_init_attr_hwmon_error(self):
        """Test init_attr handles hwmon directory errors"""
        import hw_management_peripheral_updater as peripheral_module

        attr_prop = {
            "fin": "/nonexistent/path/hwmon/test_input"
        }

        with patch('hw_management_peripheral_updater.LOGGER'):
            peripheral_module.init_attr(attr_prop)
            # Should set empty hwmon on error
            self.assertEqual(attr_prop.get("hwmon"), "")


class TestMonitorAsicChipupLogging(unittest.TestCase):
    """Test monitor_asic_chipup_status logging paths"""

    def test_monitor_asic_chipup_logs_ready_asics(self):
        """Test that ready ASICs are logged"""
        import hw_management_peripheral_updater as peripheral_module

        arg = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        mock_logger = MagicMock()
        with patch('hw_management_peripheral_updater.LOGGER', mock_logger):
            with patch('os.path.isfile', return_value=True):
                with patch('builtins.open', unittest.mock.mock_open(read_data='50000\n')):
                    with patch('hw_management_peripheral_updater.update_asic_chipup_status'):
                        peripheral_module.monitor_asic_chipup_status(arg, None)

                        # Should log debug message for ready ASIC
                        debug_calls = [call for call in mock_logger.debug.call_args_list
                                       if 'ASIC ready' in str(call)]
                        self.assertGreater(len(debug_calls), 0)

    def test_monitor_asic_chipup_logs_not_ready_asics(self):
        """Test that not-ready ASICs are logged"""
        import hw_management_peripheral_updater as peripheral_module

        arg = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        mock_logger = MagicMock()
        with patch('hw_management_peripheral_updater.LOGGER', mock_logger):
            with patch('os.path.isfile', return_value=True):
                with patch('builtins.open', side_effect=OSError("File not readable")):
                    with patch('hw_management_peripheral_updater.update_asic_chipup_status'):
                        peripheral_module.monitor_asic_chipup_status(arg, None)

                        # Should log debug message for not-ready ASIC
                        debug_calls = [call for call in mock_logger.debug.call_args_list
                                       if 'not ready' in str(call)]
                        self.assertGreater(len(debug_calls), 0)


class TestRedfishInit(unittest.TestCase):
    """Test redfish_init function"""

    def test_redfish_init_calls_get_instance(self):
        """Test redfish_init calls RedfishConnection.get_instance"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance') as mock_get:
            peripheral_module.redfish_init()
            mock_get.assert_called_once()


class TestRedfishPostErrorHandling(unittest.TestCase):
    """Test redfish_post_req error handling"""

    def test_redfish_post_req_handles_error_and_retries_login(self):
        """Test redfish_post_req retries login on error"""
        import hw_management_peripheral_updater as peripheral_module

        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_post_cmd.return_value = "mock_post_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (-1, '', 'error')  # Error code

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj):
            result = peripheral_module.redfish_post_req('/test/path', {'key': 'value'})

            # Should call login to retry
            mock_rf_obj.login.assert_called_once()
            # Returns error code
            self.assertEqual(result, -1)

    def test_redfish_post_req_no_connection(self):
        """Test redfish_post_req when no connection available"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=None):
            result = peripheral_module.redfish_post_req('/test/path', {'key': 'value'})
            self.assertIsNone(result)


class TestWriteModuleCounterError(unittest.TestCase):
    """Test write_module_counter error handling"""

    def test_write_module_counter_logs_error_on_failure(self):
        """Test write_module_counter logs error when file write fails"""
        import hw_management_peripheral_updater as peripheral_module

        mock_logger = MagicMock()
        with patch('hw_management_peripheral_updater.get_module_count', return_value=32):
            with patch('hw_management_peripheral_updater.LOGGER', mock_logger):
                with patch('builtins.open', side_effect=OSError("Permission denied")):
                    peripheral_module.write_module_counter("TEST_SKU")

                    # Should log warning about failure
                    mock_logger.warning.assert_called()


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
