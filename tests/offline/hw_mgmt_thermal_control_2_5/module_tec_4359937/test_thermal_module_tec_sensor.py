#!/usr/bin/env python3
# -*- coding: utf-8 -*-
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

"""
Comprehensive unittest for thermal_module_tec_sensor from hw_management_thermal_control_2_5.py
Version: 2.5.0
Author: Generated Test Suite
Date: 2025-09-24

This test suite provides comprehensive testing for the thermal_module_tec_sensor class
with beautiful colored output, detailed error reporting, and configurable iterations.
"""

# fmt: off
import sys
import os
import unittest
from unittest.mock import Mock, MagicMock, patch
import tempfile
import shutil
import random
import json
import argparse
import traceback
import platform
import datetime

# Add the source directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', 'usr', 'usr', 'bin'))

try:
    from hw_management_thermal_control_2_5 import (
        thermal_module_tec_sensor,
        CONST,
        DMIN_TABLE_DEFAULT,
        hw_management_file_op,
        system_device
    )
# fmt: on

except ImportError as e:
    print(f"[FAIL] Failed to import required modules: {e}")
    sys.exit(1)


class Colors:
    """ANSI color codes for beautiful terminal output"""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    END = '\033[0m'


class Icons:
    """ASCII icons for beautiful output"""
    CHECKMARK = '[PASS]'
    CROSS = '[FAIL]'
    WARNING = '[WARN]'
    INFO = '[INFO]'
    GEAR = '[TEST]'
    RANDOM = '[RAND]'
    ERROR = '[ERR]'
    CLOCK = '[TIME]'
    ROCKET = '[>>>]'
    FIRE = '[HOT]'
    SNOWFLAKE = '[COLD]'


class BeautifulTestResult(unittest.TextTestResult):
    """Custom test result class with beautiful colored output and detailed error reporting"""

    def __init__(self, stream, descriptions, verbosity):
        super().__init__(stream, descriptions, verbosity)
        self.success_count = 0
        self.detailed_errors = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.success_count += 1
        test_name = test._testMethodName
        class_name = test.__class__.__name__
        print(f"[PASS] {Colors.GREEN}{Colors.BOLD}PASS{Colors.END} {Colors.CYAN}{class_name}.{test_name}{Colors.END}")

    def addError(self, test, err):
        super().addError(test, err)
        test_name = test._testMethodName
        class_name = test.__class__.__name__
        print(f"[ERR] {Colors.RED}{Colors.BOLD}ERROR{Colors.END} {Colors.CYAN}{class_name}.{test_name}{Colors.END}")
        self._generate_detailed_error_report(test, err, "ERROR")

    def addFailure(self, test, err):
        super().addFailure(test, err)
        test_name = test._testMethodName
        class_name = test.__class__.__name__
        print(f"[FAIL] {Colors.RED}{Colors.BOLD}FAIL{Colors.END} {Colors.CYAN}{class_name}.{test_name}{Colors.END}")
        self._generate_detailed_error_report(test, err, "FAILURE")

    def _generate_detailed_error_report(self, test, err, error_type):
        """Generate detailed error report with system info and context"""
        exc_type, exc_value, exc_traceback = err

        # Extract test context
        context = self._extract_test_context(test)

        error_report = {
            'test_method': test._testMethodName,
            'test_class': test.__class__.__name__,
            'error_type': error_type,
            'exception_type': exc_type.__name__,
            'exception_message': str(exc_value),
            'traceback': traceback.format_exception(exc_type, exc_value, exc_traceback),
            'timestamp': datetime.datetime.now().isoformat(),
            'python_version': platform.python_version(),
            'platform': platform.platform(),
            'context': context
        }

        self.detailed_errors.append(error_report)

    def _extract_test_context(self, test):
        """Extract relevant test context for debugging"""
        context = {}

        # Try to extract sensor-related information
        if hasattr(test, 'sensor'):
            try:
                context['sensor_name'] = getattr(test.sensor, 'name', 'Unknown')
                context['sensor_type'] = getattr(test.sensor, 'type', 'Unknown')
                context['sensor_pwm'] = getattr(test.sensor, 'pwm', 'Unknown')
                context['sensor_faults'] = getattr(test.sensor, 'get_fault_list_filtered', lambda: [])()
            except BaseException:
                context['sensor_info'] = 'Could not extract sensor information'

        # Try to extract temp directory information
        if hasattr(test, 'temp_dir'):
            context['temp_directory'] = test.temp_dir

        # Try to extract configuration information
        if hasattr(test, 'sys_config'):
            context['config_keys'] = list(test.sys_config.keys()) if test.sys_config else []

        return context

    def print_detailed_error_reports(self):
        """Print all collected detailed error reports"""
        if not self.detailed_errors:
            return

        print(f"\n{Colors.RED}{Colors.BOLD}{'=' * 80}{Colors.END}")
        print(f"{Colors.RED}{Colors.BOLD}DETAILED ERROR REPORTS{Colors.END}")
        print(f"{Colors.RED}{Colors.BOLD}{'=' * 80}{Colors.END}")

        for i, error in enumerate(self.detailed_errors, 1):
            print(f"\n{Colors.YELLOW}{Colors.BOLD}Error Report #{i}{Colors.END}")
            print(f"{Colors.CYAN}Test:{Colors.END} {error['test_class']}.{error['test_method']}")
            print(f"{Colors.CYAN}Type:{Colors.END} {error['error_type']}")
            print(f"{Colors.CYAN}Exception:{Colors.END} {error['exception_type']}: {error['exception_message']}")
            print(f"{Colors.CYAN}Timestamp:{Colors.END} {error['timestamp']}")
            print(f"{Colors.CYAN}Python:{Colors.END} {error['python_version']} on {error['platform']}")

            if error['context']:
                print(f"{Colors.CYAN}Context:{Colors.END}")
                for key, value in error['context'].items():
                    print(f"  {key}: {value}")

            print(f"{Colors.CYAN}Stack Trace:{Colors.END}")
            for line in error['traceback']:
                print(f"  {line.rstrip()}")

            print(f"{Colors.YELLOW}{'-' * 60}{Colors.END}")


class BeautifulTestRunner(unittest.TextTestRunner):
    """Custom test runner with beautiful colored output"""

    def __init__(self, **kwargs):
        kwargs['resultclass'] = BeautifulTestResult
        super().__init__(**kwargs)

    def run(self, test):
        print(f"\n{Colors.BLUE}{Colors.BOLD}{'=' * 80}{Colors.END}")
        print(f"{Colors.BLUE}{Colors.BOLD}[>>>] THERMAL MODULE TEC SENSOR UNITTEST - VERSION 2.5.0{Colors.END}")
        print(f"{Colors.BLUE}{Colors.BOLD}{'=' * 80}{Colors.END}")
        print(f"{Colors.YELLOW}Testing: thermal_module_tec_sensor from hw_management_thermal_control_2_5.py{Colors.END}")
        print(f"{Colors.YELLOW}Location: /auto/mtrsysgwork/oleksandrs/hw-managment/hw_mgmt_clean/unittest/hw_mgmt_thermal_control_250/module_tec_4359937/{Colors.END}\n")

        result = super().run(test)

        # Print summary
        total_tests = result.testsRun
        failures = len(result.failures)
        errors = len(result.errors)
        successes = result.success_count

        print(f"\n{Colors.BLUE}{Colors.BOLD}{'=' * 80}{Colors.END}")
        print(f"{Colors.BLUE}{Colors.BOLD}TEST SUMMARY{Colors.END}")
        print(f"{Colors.BLUE}{Colors.BOLD}{'=' * 80}{Colors.END}")
        print(f"{Colors.GREEN}[PASS] Passed: {successes}{Colors.END}")
        print(f"{Colors.RED}[FAIL] Failed: {failures}{Colors.END}")
        print(f"{Colors.RED}[ERR] Errors: {errors}{Colors.END}")
        print(f"{Colors.CYAN}[INFO] Total: {total_tests}{Colors.END}")

        if failures == 0 and errors == 0:
            print(f"\n{Colors.GREEN}{Colors.BOLD}*** ALL TESTS PASSED! ***{Colors.END}")
        else:
            print(f"\n{Colors.RED}{Colors.BOLD}[WARN] SOME TESTS FAILED [WARN]{Colors.END}")

        # Print detailed error reports if any
        result.print_detailed_error_reports()

        return result


class MockThermalSensor:
    """Mock class to simulate thermal sensor file operations"""

    def __init__(self, temp_dir, module_name="module1"):
        self.temp_dir = temp_dir
        self.module_name = module_name
        self.setup_default_files()

    def setup_default_files(self):
        """Setup default sensor files with reasonable values"""
        thermal_dir = os.path.join(self.temp_dir, "thermal")
        os.makedirs(thermal_dir, exist_ok=True)

        # Default values
        self.write_file(f"thermal/{self.module_name}_temp_input", "45000")  # 45 degreesC in millidegrees
        self.write_file(f"thermal/{self.module_name}_cooling_level_input", "50")
        self.write_file(f"thermal/{self.module_name}_cooling_level_warning", "100")

    def write_file(self, relative_path, content):
        """Write content to a file"""
        full_path = os.path.join(self.temp_dir, relative_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, 'w') as f:
            f.write(str(content))

    def read_file_int(self, relative_path):
        """Read integer value from file"""
        full_path = os.path.join(self.temp_dir, relative_path)
        with open(full_path, 'r') as f:
            return int(f.read().strip())

    def check_file(self, relative_path):
        """Check if file exists"""
        full_path = os.path.join(self.temp_dir, relative_path)
        return os.path.exists(full_path)

    def remove_file(self, relative_path):
        """Remove a file"""
        full_path = os.path.join(self.temp_dir, relative_path)
        if os.path.exists(full_path):
            os.remove(full_path)

    def set_cooling_level_input(self, value):
        """Set cooling level input value"""
        self.write_file(f"thermal/{self.module_name}_cooling_level_input", str(value))

    def set_temp_input(self, value):
        """Set temperature input value (in millidegrees)"""
        self.write_file(f"thermal/{self.module_name}_temp_input", str(value))

    def set_cooling_level_warning(self, value):
        """Set cooling level warning value"""
        self.write_file(f"thermal/{self.module_name}_cooling_level_warning", str(value))


class TestThermalModuleTecSensor(unittest.TestCase):
    """Comprehensive test suite for thermal_module_tec_sensor from hw_management_thermal_control_2_5.py"""

    # Class variable for configurable iterations
    iteration_count = 10  # Default value

    @classmethod
    def set_iteration_count(cls, count):
        """Set the number of iterations for random tests"""
        cls.iteration_count = max(1, int(count))

    def setUp(self):
        """Set up test environment"""
        # Create temporary directory for test files
        self.temp_dir = tempfile.mkdtemp()

        # Mock command arguments - needs to be a dictionary-like object
        self.cmd_arg = {
            CONST.HW_MGMT_ROOT: self.temp_dir,
            'hw_management_path': self.temp_dir
        }

        # Mock system config
        self.sys_config = {
            CONST.SYS_CONF_SENSORS_CONF: {
                "module1": {
                    "type": "TEC",
                    "scale": 1,
                    "val_lcrit": 0,
                    "val_hcrit": 960,
                    "pwm_min": 20,
                    "pwm_max": 100,
                    "val_min": 0,
                    "val_max": 100,
                    "base_file_name": "module1"
                }
            }
        }

        # Create mock logger
        self.mock_logger = Mock()

        # Create mock sensor helper
        self.mock_sensor = MockThermalSensor(self.temp_dir)

        # Create the thermal sensor instance
        self.sensor = thermal_module_tec_sensor(
            self.cmd_arg,
            self.sys_config,
            "module1",
            self.mock_logger
        )

        # Initialize status print call counter
        self._status_print_call_count = 0

    def tearDown(self):
        """Clean up test environment"""
        # Remove temporary directory
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _test_status_print_no_crash(self, test_id, sensor=None):
        """Test that status print doesn't crash and show the output"""
        if sensor is None:
            sensor = self.sensor

        try:
            status_str = str(sensor)
            self._status_print_call_count += 1

            # Verify basic requirements
            self.assertIsInstance(status_str, str)
            self.assertGreater(len(status_str), 0)

            # Show the status output in test logs, encode to ASCII-compatible format
            # Replace Unicode characters that can't be encoded in latin-1
            status_str_safe = status_str.encode('ascii', errors='replace').decode('ascii')
            print(f"    {Icons.INFO} Status [{test_id}]: {status_str_safe}")
            return True

        except Exception as e:
            self.fail(f"Status print crashed during {test_id}: {e}")

    def test_01_normal_condition_random(self):
        """Test 1: Normal Condition Testing (random values)"""
        print(f"\n{Icons.RANDOM} {Colors.YELLOW}Testing normal operation with random values ({self.iteration_count} iterations)...{Colors.END}")

        for i in range(self.iteration_count):  # Run configurable random tests
            # Clear previous faults before each iteration
            self.sensor.clear_fault_list()

            # Generate random values
            flow_dir = random.choice(["C2P", "P2C"])
            amb_temp = random.randint(20, 50)

            # Random temperature (20-80 degreesC in millidegrees)
            temp_value = random.randint(20000, 80000)

            # Random cooling level (0 to warning level)
            cooling_level_warning = random.randint(100, 960)
            cooling_level_input = random.randint(0, cooling_level_warning)

            print(f"  {Icons.GEAR} Iteration {i + 1}: temp={temp_value // 1000} degreesC, cooling_level={cooling_level_input}, warning={cooling_level_warning}")

            # Set sensor values
            self.mock_sensor.set_temp_input(temp_value)
            self.mock_sensor.set_cooling_level_input(cooling_level_input)
            self.mock_sensor.set_cooling_level_warning(cooling_level_warning)

            # Test sensor operation
            self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Verify PWM is in expected range (20-100)
            self.assertGreaterEqual(self.sensor.pwm, 20, f"PWM should be >= 20, got {self.sensor.pwm}")
            self.assertLessEqual(self.sensor.pwm, 100, f"PWM should be <= 100, got {self.sensor.pwm}")

            # Verify no faults for normal operation
            fault_list = self.sensor.get_fault_list_filtered()
            self.assertEqual(len(fault_list), 0, f"No faults expected for normal operation, got {fault_list}")

            # Test status print after this iteration
            self._test_status_print_no_crash(f"normal_test_{i + 1}")

    def test_02_sensor_missing_file_error(self):
        """Test 2: Sensor random read error Testing (missing sensor)"""
        print(f"\n{Icons.ERROR} {Colors.YELLOW}Testing missing sensor files ({self.iteration_count} iterations)...{Colors.END}")

        files_to_test = [
            f"thermal/{self.mock_sensor.module_name}_temp_input",
            f"thermal/{self.mock_sensor.module_name}_cooling_level_input",
            f"thermal/{self.mock_sensor.module_name}_cooling_level_warning"
        ]

        for iteration in range(self.iteration_count):  # Run configurable iterations
            # Clear previous faults before each iteration
            self.sensor.clear_fault_list()

            # Randomly select a file to test
            missing_file = random.choice(files_to_test)
            flow_dir = random.choice(["C2P", "P2C"])
            amb_temp = random.randint(20, 50)

            print(f"  {Icons.ERROR} Iteration {iteration + 1}: Testing missing file: {missing_file}")

            # Remove the file to simulate missing sensor
            self.mock_sensor.remove_file(missing_file)

            # Test sensor operation - should trigger 3 errors
            for attempt in range(4):  # Need 4 attempts to trigger error after 3 failures
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)
                self.sensor.collect_err()

            # Verify SENSOR_READ_ERR is raised after 3 attempts
            fault_list = self.sensor.get_fault_list_filtered()
            self.assertIn(CONST.SENSOR_READ_ERR, fault_list,
                          f"SENSOR_READ_ERR should be raised for missing file {missing_file} (iteration {iteration + 1})")

            # Handle error to set PWM according to thermal table
            self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Verify PWM is set according to thermal table (should be 100 for error condition)
            self.assertGreaterEqual(self.sensor.pwm, 90, f"PWM should be high for error condition, got {self.sensor.pwm}")

            # Restore the file for next iteration
            self.mock_sensor.setup_default_files()

            # Test status print after this iteration
            self._test_status_print_no_crash(f"missing_file_{iteration + 1}")

    def test_03_sensor_invalid_value_error(self):
        """Test 3: Sensor random read error Testing (non-integer value sensor)"""
        print(f"\n{Icons.ERROR} {Colors.YELLOW}Testing invalid sensor values ({self.iteration_count} iterations)...{Colors.END}")

        invalid_values = ["", "not_a_number", "12.5.7", "abc123", "-", "+", "0x123", "None", "null"]
        files_to_test = [
            f"thermal/{self.mock_sensor.module_name}_temp_input",
            f"thermal/{self.mock_sensor.module_name}_cooling_level_input",
            f"thermal/{self.mock_sensor.module_name}_cooling_level_warning"
        ]

        for iteration in range(self.iteration_count):  # Run configurable iterations
            # Clear previous faults before each iteration
            self.sensor.clear_fault_list()

            # Randomly select file and invalid value
            file_path = random.choice(files_to_test)
            invalid_value = random.choice(invalid_values)
            flow_dir = random.choice(["C2P", "P2C"])
            amb_temp = random.randint(20, 50)

            print(f"  {Icons.ERROR} Iteration {iteration + 1}: Testing {file_path} with invalid value: '{invalid_value}'")

            # Set invalid value
            self.mock_sensor.write_file(file_path, invalid_value)

            # Test sensor operation - should trigger errors after 3 attempts
            for attempt in range(4):
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)
                self.sensor.collect_err()

            # Verify SENSOR_READ_ERR is raised
            fault_list = self.sensor.get_fault_list_filtered()
            self.assertIn(CONST.SENSOR_READ_ERR, fault_list,
                          f"SENSOR_READ_ERR should be raised for invalid value '{invalid_value}' (iteration {iteration + 1})")

            # Handle error to set PWM according to thermal table
            self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Restore default values
            self.mock_sensor.setup_default_files()

            # Test status print after this iteration
            self._test_status_print_no_crash(f"invalid_value_{iteration + 1}")

    def test_04_sensor_out_of_range_error(self):
        """Test 4: Sensor random read error Testing (value out of lcrit/hcrit range)"""
        print(f"\n{Icons.WARNING} {Colors.YELLOW}Testing out-of-range cooling level values ({self.iteration_count} iterations)...{Colors.END}")

        for iteration in range(self.iteration_count):  # Run configurable iterations
            # Clear previous faults before each iteration
            self.sensor.clear_fault_list()

            # Generate random out-of-range values
            if random.choice([True, False]):
                # Below lcrit (0)
                cooling_level = random.randint(-100, -1)
                description = "below lcrit"
            else:
                # Above hcrit (960)
                cooling_level = random.randint(961, 2000)
                description = "above hcrit"

            flow_dir = random.choice(["C2P", "P2C"])
            amb_temp = random.randint(20, 50)

            print(f"  {Icons.WARNING} Iteration {iteration + 1}: Testing cooling level {cooling_level} ({description})")

            # Set out-of-range cooling level
            self.mock_sensor.set_cooling_level_input(cooling_level)

            # Test sensor operation - should trigger errors after 3 attempts
            for attempt in range(4):
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)
                self.sensor.collect_err()

            # Verify SENSOR_READ_ERR is raised
            fault_list = self.sensor.get_fault_list_filtered()
            self.assertIn(CONST.SENSOR_READ_ERR, fault_list,
                          f"SENSOR_READ_ERR should be raised for cooling level {cooling_level} (iteration {iteration + 1})")

            # Handle error to set PWM according to thermal table
            self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Restore default value
            self.mock_sensor.setup_default_files()

            # Test status print after this iteration
            self._test_status_print_no_crash(f"out_of_range_{iteration + 1}")

    def test_05_config_missing_parameters(self):
        """Test 5: Sensor config random parameters testing (not defined parameters)"""
        print(f"\n{Icons.GEAR} {Colors.YELLOW}Testing missing config parameters ({self.iteration_count} iterations)...{Colors.END}")

        parameters_to_test = [
            "val_lcrit", "val_hcrit", "pwm_min", "pwm_max", "val_min", "val_max"
        ]

        for iteration in range(self.iteration_count):  # Run configurable iterations
            # Clear previous faults before each iteration
            self.sensor.clear_fault_list()

            # Randomly select parameter to test
            param = random.choice(parameters_to_test)
            flow_dir = random.choice(["C2P", "P2C"])
            amb_temp = random.randint(20, 50)

            print(f"  {Icons.GEAR} Iteration {iteration + 1}: Testing missing parameter: {param}")

            # Create config without the parameter (but keep required ones)
            base_config = {
                "type": "TEC",
                "scale": 1,
                "base_file_name": "module1"
            }

            # Add all parameters except the one being tested
            for p in parameters_to_test:
                if p != param:
                    if p in ["val_lcrit", "val_min"]:
                        base_config[p] = 0
                    elif p in ["val_hcrit", "val_max"]:
                        base_config[p] = 960 if p == "val_hcrit" else 100
                    elif p in ["pwm_min"]:
                        base_config[p] = 20
                    elif p in ["pwm_max"]:
                        base_config[p] = 100

            # Create new config
            test_config = {
                CONST.SYS_CONF_SENSORS_CONF: {
                    "module1": base_config
                }
            }

            # Create new sensor with missing parameter
            test_sensor = thermal_module_tec_sensor(
                self.cmd_arg,
                test_config,
                "module1",
                self.mock_logger
            )

            # Test operation - should not crash even with missing parameters
            try:
                test_sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)
                test_sensor.collect_err()
                # Verify sensor doesn't crash and has reasonable PWM value
                self.assertIsInstance(test_sensor.pwm, (int, float))
                self.assertGreaterEqual(test_sensor.pwm, 0)
                self.assertLessEqual(test_sensor.pwm, 100)
            except Exception as e:
                self.fail(f"Sensor should not crash with missing {param}: {e}")

            # Test status print after this iteration
            self._test_status_print_no_crash(f"config_param_{iteration + 1}", test_sensor)

    def test_06_error_handling_no_crash(self):
        """Test 6: Error Handling Testing - Function doesn't crash under various error conditions"""
        print(f"\n{Icons.ERROR} {Colors.YELLOW}Testing error handling robustness ({self.iteration_count} iterations)...{Colors.END}")

        error_scenarios = [
            ("Corrupted file system", ""),
            ("Non-existent path", "/non/existent/path"),
            ("Very long path", "/very/long/path/" + "x" * 200)
        ]

        for iteration in range(self.iteration_count):  # Run configurable iterations
            # Clear previous faults before each iteration
            self.sensor.clear_fault_list()

            # Randomly select error scenario
            description, path_override = random.choice(error_scenarios)
            flow_dir = random.choice(["C2P", "P2C"])
            amb_temp = random.randint(20, 50)

            print(f"  {Icons.ERROR} Iteration {iteration + 1}: Testing: {description}")

            try:
                if path_override is not None:
                    # Temporarily override the root folder
                    original_path = self.sensor.root_folder
                    self.sensor.root_folder = path_override

                # Test various operations that might fail
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)
                self.sensor.collect_err()
                self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

                # Verify the function completes without crashing
                self.assertIsInstance(self.sensor.pwm, (int, float))

            except Exception as e:
                # The function should handle errors gracefully, but if it throws,
                # we record this as a failure of error handling
                self.fail(f"Function crashed during {description}: {e}")

            finally:
                # Restore original path if it was overridden
                if path_override is not None:
                    self.sensor.root_folder = original_path

            # Test status print after this iteration
            self._test_status_print_no_crash(f"error_handling_{iteration + 1}")

    def test_07_status_print_summary(self):
        """Test 7: Status print summary and validation"""
        print(f"\n{Icons.INFO} {Colors.YELLOW}Testing status print function summary...{Colors.END}")

        # Note: Status print is already tested after each iteration of previous tests
        # This test provides a summary of status print functionality

        # Test with various sensor states
        test_states = [
            {"temp": 25000, "cooling_level": 30, "cooling_level_warning": 100, "description": "Low load"},
            {"temp": 50000, "cooling_level": 80, "cooling_level_warning": 100, "description": "High load"},
            {"temp": 70000, "cooling_level": 95, "cooling_level_warning": 100, "description": "Critical load"}
        ]

        for i, state in enumerate(test_states, 1):
            # Clear previous faults
            self.sensor.clear_fault_list()

            print(f"  {Icons.GEAR} Testing status print with {state['description']}")

            # Set sensor state
            self.mock_sensor.set_temp_input(state["temp"])
            self.mock_sensor.set_cooling_level_input(state["cooling_level"])
            self.mock_sensor.set_cooling_level_warning(state["cooling_level_warning"])

            # Update sensor
            self.sensor.handle_input(DMIN_TABLE_DEFAULT, "C2P", 30)

            # Test status print
            self._test_status_print_no_crash(f"summary_test_{i}")

        print(f"  {Icons.CHECKMARK} Total status print calls in this test: {self._status_print_call_count}")
        print(f"  {Icons.INFO} Note: Status print was also called after each iteration of tests #1-#6")


def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description='Comprehensive unittest for thermal_module_tec_sensor (v2.5.0)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python test_thermal_module_tec_sensor.py                    # Run with default 10 iterations
  python test_thermal_module_tec_sensor.py --iterations 20   # Run with 20 iterations
  python test_thermal_module_tec_sensor.py -i 5              # Run with 5 iterations
        """)

    parser.add_argument('-i', '--iterations', type=int, default=20, metavar='N',
                        help='Number of iterations for random tests (default: 10, minimum: 1)')

    return parser.parse_args()


def main():
    """Main function to run the tests"""
    try:
        # Parse command line arguments
        args = parse_arguments()

        # Set iteration count for the test class
        TestThermalModuleTecSensor.set_iteration_count(args.iterations)

        # Create test suite
        suite = unittest.TestLoader().loadTestsFromTestCase(TestThermalModuleTecSensor)

        # Run tests with beautiful output
        runner = BeautifulTestRunner(verbosity=2)
        result = runner.run(suite)

        # Exit with appropriate code
        sys.exit(0 if result.wasSuccessful() else 1)

    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Tests interrupted by user{Colors.END}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.RED}Unexpected error: {e}{Colors.END}")
        sys.exit(1)


if __name__ == '__main__':
    main()
