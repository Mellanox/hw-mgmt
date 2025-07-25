#!/usr/bin/env python3
"""
Unittest for thermal sensor error handling when temperature values are outside critical range.
Tests that SENSOR_READ_ERR is asserted after 3 consecutive errors.
"""

import hw_management_thermal_control as thermal_control
import unittest
import tempfile
import os
import sys
import json
from unittest.mock import Mock, patch, MagicMock, mock_open
import time

# Add the path to the thermal control module
sys.path.insert(0, 'usr/usr/bin')

# Import the thermal control module


class TestThermalSensorErrorHandling(unittest.TestCase):
    """Test class for thermal sensor error handling with critical range violations."""

    def setUp(self):
        """Set up test fixtures."""
        self.temp_dir = tempfile.mkdtemp()
        self.cmd_arg = {"verbosity": 1}
        self.tc_logger = Mock()

        # Mock system configuration
        self.sys_config = {
            "sensors_conf": {
                "test_sensor": {
                    "type": "thermal_sensor",
                    "base_file_name": "test_temp",
                    "enable": 1,
                    "poll_time": 1,
                    "val_lcrit": 10,
                    "val_hcrit": 90,
                    "val_min": 0,
                    "val_max": 100,
                    "pwm_min": 0,
                    "pwm_max": 100,
                    "sensor_read_error": 50
                }
            },
            "dmin": {},
            "fan_pwm": {},
            "fan_param": {},
            "dev_param": {},
            "asic_param": {},
            "sensor_list_param": [],
            "err_mask": []
        }

    def tearDown(self):
        """Clean up test fixtures."""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def create_temp_file(self, filename, content):
        """Create a temporary file with given content."""
        filepath = os.path.join(self.temp_dir, filename)
        with open(filepath, 'w') as f:
            f.write(str(content))
        return filepath

    def test_sensor_value_below_lcrit_asserts_error_after_3_times(self):
        """Test that SENSOR_READ_ERR is asserted after 3 consecutive readings below lcrit."""

        # Create a mock thermal sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["test_temp"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Create sensor instance
            sensor = thermal_control.thermal_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations
            with patch.object(sensor, 'check_file', return_value=True), \
                    patch.object(sensor, 'read_file_int', return_value=5):  # Value below lcrit (10)

                # First reading - below lcrit, should increment error count
                sensor.handle_input({}, "C2P", 25)
                sensor.collect_err()

                # Check that error was handled but not yet asserted
                mock_err_counter.handle_err.assert_called_with("test_temp")
                self.assertNotIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

                # Second reading - still below lcrit
                sensor.handle_input({}, "C2P", 25)
                sensor.collect_err()

                # Still not enough errors
                self.assertNotIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

                # Third reading - below lcrit, should trigger SENSOR_READ_ERR
                sensor.handle_input({}, "C2P", 25)
                sensor.collect_err()

                # Now SENSOR_READ_ERR should be asserted
                self.assertIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

    def test_sensor_value_above_hcrit_asserts_error_after_3_times(self):
        """Test that SENSOR_READ_ERR is asserted after 3 consecutive readings above hcrit."""

        # Create a mock thermal sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["test_temp"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Create sensor instance
            sensor = thermal_control.thermal_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations
            with patch.object(sensor, 'check_file', return_value=True), \
                    patch.object(sensor, 'read_file_int', return_value=95):  # Value above hcrit (90)

                # First reading - above hcrit, should increment error count
                sensor.handle_input({}, "C2P", 25)
                sensor.collect_err()

                # Check that error was handled but not yet asserted
                mock_err_counter.handle_err.assert_called_with("test_temp")
                self.assertNotIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

                # Second reading - still above hcrit
                sensor.handle_input({}, "C2P", 25)
                sensor.collect_err()

                # Still not enough errors
                self.assertNotIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

                # Third reading - above hcrit, should trigger SENSOR_READ_ERR
                sensor.handle_input({}, "C2P", 25)
                sensor.collect_err()

                # Now SENSOR_READ_ERR should be asserted
                self.assertIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

    def test_sensor_value_in_range_resets_error_counter(self):
        """Test that error counter is reset when value is within critical range."""

        # Create a mock thermal sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["test_temp"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Create sensor instance
            sensor = thermal_control.thermal_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations
            with patch.object(sensor, 'check_file', return_value=True):

                # First reading - below lcrit
                with patch.object(sensor, 'read_file_int', return_value=5):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # Second reading - below lcrit
                with patch.object(sensor, 'read_file_int', return_value=5):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # Third reading - within range, should reset error counter
                with patch.object(sensor, 'read_file_int', return_value=50):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # Error counter should be reset, no SENSOR_READ_ERR
                self.assertNotIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

                # Verify reset was called
                mock_err_counter.handle_err.assert_called_with("test_temp", reset=True)

    def test_thermal_module_sensor_critical_range_handling(self):
        """Test thermal module sensor critical range error handling."""

        # Create a mock thermal module sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["test_temp"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Create sensor instance
            sensor = thermal_control.thermal_module_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations and temp support
            with patch.object(sensor, 'check_file', return_value=True), \
                    patch.object(sensor, 'read_file_int', return_value=95), \
                    patch.object(sensor, 'get_temp_support_status', return_value=True):

                # Three consecutive readings above hcrit
                for _ in range(3):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # SENSOR_READ_ERR should be asserted
                self.assertIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

    def test_thermal_asic_sensor_critical_range_handling(self):
        """Test thermal ASIC sensor critical range error handling."""

        # Create a mock thermal ASIC sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["test_temp"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Create sensor instance
            sensor = thermal_control.thermal_asic_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations
            with patch.object(sensor, 'check_file', return_value=True), \
                    patch.object(sensor, 'read_file_int', return_value=5):  # Below lcrit

                # Three consecutive readings below lcrit
                for _ in range(3):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # SENSOR_READ_ERR should be asserted
                self.assertIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

    def test_error_counter_reset_after_valid_reading(self):
        """Test that error counter resets after a valid reading following errors."""

        # Create a mock thermal sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["test_temp"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Create sensor instance
            sensor = thermal_control.thermal_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations
            with patch.object(sensor, 'check_file', return_value=True):

                # Two readings below lcrit
                with patch.object(sensor, 'read_file_int', return_value=5):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # One valid reading
                with patch.object(sensor, 'read_file_int', return_value=50):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # Error counter should be reset, no SENSOR_READ_ERR
                self.assertNotIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

                # Two more readings below lcrit
                with patch.object(sensor, 'read_file_int', return_value=5):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # Still not enough errors (counter was reset)
                self.assertNotIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

    def test_error_handling_with_file_read_exceptions(self):
        """Test error handling when file reading throws exceptions."""

        # Create a mock thermal sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["test_temp"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Create sensor instance
            sensor = thermal_control.thermal_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations
            with patch.object(sensor, 'check_file', return_value=True), \
                    patch.object(sensor, 'read_file_int', side_effect=Exception("File read error")):

                # Three consecutive file read errors
                for _ in range(3):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # SENSOR_READ_ERR should be asserted
                self.assertIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())

    def test_ambient_thermal_sensor_critical_range_handling(self):
        """Test ambient thermal sensor critical range error handling."""

        # Create a mock ambient thermal sensor
        with patch('hw_management_thermal_control.iterate_err_counter') as mock_err_counter_class:
            mock_err_counter = Mock()
            mock_err_counter_class.return_value = mock_err_counter

            # Initialize error counter to track errors
            error_count = 0

            def mock_handle_err(file_name, reset=False):
                nonlocal error_count
                if reset:
                    error_count = 0
                else:
                    error_count += 1
                return error_count

            def mock_check_err():
                return ["thermal/test_amb"] if error_count >= 3 else []

            mock_err_counter.handle_err.side_effect = mock_handle_err
            mock_err_counter.check_err.side_effect = mock_check_err

            # Update sys_config for ambient sensor
            self.sys_config["sensors_conf"]["test_sensor"]["type"] = "ambiant_thermal_sensor"
            self.sys_config["sensors_conf"]["test_sensor"]["base_file_name"] = {"amb1": "test_amb"}

            # Create sensor instance
            sensor = thermal_control.ambiant_thermal_sensor(
                self.cmd_arg,
                self.sys_config,
                "test_sensor",
                self.tc_logger
            )

            # Mock file operations
            with patch.object(sensor, 'check_file', return_value=True), \
                    patch.object(sensor, 'read_file_int', return_value=95):  # Above hcrit

                # Three consecutive readings above hcrit
                for _ in range(3):
                    sensor.handle_input({}, "C2P", 25)
                    sensor.collect_err()

                # SENSOR_READ_ERR should be asserted
                self.assertIn(thermal_control.CONST.SENSOR_READ_ERR, sensor.get_fault_list_filtered())


if __name__ == '__main__':
    unittest.main()
