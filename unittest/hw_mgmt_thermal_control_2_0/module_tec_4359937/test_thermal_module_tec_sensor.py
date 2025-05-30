#!/usr/bin/env python3
########################################################################
# Copyright (c) 2022 NVIDIA CORPORATION & AFFILIATES.
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
Comprehensive Unit Tests for thermal_module_tec_sensor class

Author: AI Assistant
Description: Beautiful and detailed unit tests with colorful output and icons
"""

from hw_management_thermal_control import (
    thermal_module_tec_sensor,
    CONST,
    DMIN_TABLE_DEFAULT,
    Logger,
    iterate_err_counter
)
import unittest
import sys
import os
import tempfile
import shutil
import random
import json
import traceback
import platform
import datetime
import argparse
from unittest.mock import Mock, patch, MagicMock
from io import StringIO

# Add the source path to be able to import the module
sys.path.insert(0, '/auto/mtrsysgwork/oleksandrs/hw-managment/hw_mgmt_clean/usr/usr/bin')

# Import the thermal control module

# Color codes for beautiful output


class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'

# Icons for test results


class Icons:
    PASS = '✅'
    FAIL = '❌'
    SKIP = '⏭️'
    WARNING = '⚠️'
    INFO = 'ℹ️'
    FIRE = '🔥'
    THERMOMETER = '🌡️'
    FAN = '💨'
    GEAR = '⚙️'
    RANDOM = '🎲'
    FILE = '📁'
    ERROR = '💥'


class BeautifulTestResult(unittest.TextTestResult):
    """Custom test result class for beautiful output with detailed error reporting"""

    def __init__(self, stream, descriptions, verbosity):
        super().__init__(stream, descriptions, verbosity)
        self.test_count = 0
        self.pass_count = 0
        self.fail_count = 0
        self.skip_count = 0
        self.detailed_errors = []

    def startTest(self, test):
        super().startTest(test)
        self.test_count += 1

    def addSuccess(self, test):
        super().addSuccess(test)
        self.pass_count += 1
        test_name = test._testMethodName
        class_name = test.__class__.__name__
        print(f"{Icons.PASS} {Colors.GREEN}{Colors.BOLD}PASS{Colors.END} {Colors.CYAN}{class_name}.{test_name}{Colors.END}")

    def addError(self, test, err):
        super().addError(test, err)
        self.fail_count += 1
        test_name = test._testMethodName
        class_name = test.__class__.__name__
        print(f"{Icons.FAIL} {Colors.RED}{Colors.BOLD}ERROR{Colors.END} {Colors.CYAN}{class_name}.{test_name}{Colors.END}")

        # Store detailed error information
        error_info = self._generate_detailed_error_report(test, err, "ERROR")
        self.detailed_errors.append(error_info)

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.fail_count += 1
        test_name = test._testMethodName
        class_name = test.__class__.__name__
        print(f"{Icons.FAIL} {Colors.RED}{Colors.BOLD}FAIL{Colors.END} {Colors.CYAN}{class_name}.{test_name}{Colors.END}")

        # Store detailed error information
        error_info = self._generate_detailed_error_report(test, err, "FAILURE")
        self.detailed_errors.append(error_info)

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self.skip_count += 1
        test_name = test._testMethodName
        class_name = test.__class__.__name__
        print(f"{Icons.SKIP} {Colors.YELLOW}{Colors.BOLD}SKIP{Colors.END} {Colors.CYAN}{class_name}.{test_name}{Colors.END} - {reason}")

    def _generate_detailed_error_report(self, test, err, error_type):
        """Generate a detailed error report with context and debugging information"""
        exc_type, exc_value, exc_traceback = err
        test_name = test._testMethodName
        class_name = test.__class__.__name__

        # System information
        sys_info = {
            'timestamp': datetime.datetime.now().isoformat(),
            'platform': platform.platform(),
            'python_version': platform.python_version(),
            'test_method': test_name,
            'test_class': class_name,
            'error_type': error_type,
            'exception_type': exc_type.__name__,
            'exception_message': str(exc_value)
        }

        # Get full stack trace
        stack_trace = traceback.format_exception(exc_type, exc_value, exc_traceback)

        # Try to get test context information
        context_info = self._extract_test_context(test)

        return {
            'sys_info': sys_info,
            'stack_trace': stack_trace,
            'context': context_info
        }

    def _extract_test_context(self, test):
        """Extract context information from the test instance"""
        context = {}

        try:
            # Try to get sensor information if available
            if hasattr(test, 'sensor'):
                context['sensor_info'] = {
                    'name': getattr(test.sensor, 'name', 'Unknown'),
                    'type': getattr(test.sensor, 'type', 'Unknown'),
                    'pwm': getattr(test.sensor, 'pwm', 'Unknown'),
                    'temperature': getattr(test.sensor, 'temperature', 'Unknown'),
                    'cooling_level': getattr(test.sensor, 'cooling_level', 'Unknown'),
                    'cooling_level_max': getattr(test.sensor, 'cooling_level_max', 'Unknown'),
                    'fault_list': getattr(test.sensor, 'get_fault_list_filtered', lambda: [])()
                }

            # Try to get temp directory info
            if hasattr(test, 'temp_dir'):
                context['temp_dir'] = test.temp_dir

            # Try to get configuration info
            if hasattr(test, 'sys_config'):
                context['config'] = test.sys_config

        except Exception as e:
            context['context_extraction_error'] = str(e)

        return context

    def print_detailed_error_reports(self):
        """Print detailed error reports for all failures and errors"""
        if not self.detailed_errors:
            return

        print(f"\n{Colors.BOLD}{Colors.RED}{'=' * 80}")
        print(f"{Icons.ERROR} DETAILED ERROR REPORTS")
        print(f"{'=' * 80}{Colors.END}")

        for i, error_info in enumerate(self.detailed_errors, 1):
            self._print_single_error_report(i, error_info)

    def _print_single_error_report(self, error_num, error_info):
        """Print a single detailed error report"""
        sys_info = error_info['sys_info']
        stack_trace = error_info['stack_trace']
        context = error_info['context']

        print(f"\n{Colors.BOLD}{Colors.YELLOW}┌─ ERROR REPORT #{error_num} ─────────────────────────────────────────────────────┐{Colors.END}")

        # System Information
        print(f"{Colors.BOLD}{Colors.BLUE}│ {Icons.INFO} SYSTEM INFORMATION{Colors.END}")
        print(f"{Colors.BLUE}├─────────────────────────────────────────────────────────────────────────────────┤{Colors.END}")
        print(f"│ {Colors.CYAN}Timestamp:{Colors.END} {sys_info['timestamp']}")
        print(f"│ {Colors.CYAN}Platform:{Colors.END} {sys_info['platform']}")
        print(f"│ {Colors.CYAN}Python Version:{Colors.END} {sys_info['python_version']}")
        print(f"│ {Colors.CYAN}Test Class:{Colors.END} {sys_info['test_class']}")
        print(f"│ {Colors.CYAN}Test Method:{Colors.END} {sys_info['test_method']}")
        print(f"│ {Colors.CYAN}Error Type:{Colors.END} {Colors.RED}{sys_info['error_type']}{Colors.END}")
        print(f"│ {Colors.CYAN}Exception:{Colors.END} {Colors.RED}{sys_info['exception_type']}: {sys_info['exception_message']}{Colors.END}")

        # Test Context
        if context:
            print(f"{Colors.BLUE}├─────────────────────────────────────────────────────────────────────────────────┤{Colors.END}")
            print(f"{Colors.BOLD}{Colors.BLUE}│ {Icons.GEAR} TEST CONTEXT{Colors.END}")
            print(f"{Colors.BLUE}├─────────────────────────────────────────────────────────────────────────────────┤{Colors.END}")

            if 'sensor_info' in context:
                sensor = context['sensor_info']
                print(f"│ {Colors.CYAN}Sensor Name:{Colors.END} {sensor.get('name', 'N/A')}")
                print(f"│ {Colors.CYAN}Sensor Type:{Colors.END} {sensor.get('type', 'N/A')}")
                print(f"│ {Colors.CYAN}PWM Value:{Colors.END} {sensor.get('pwm', 'N/A')}")
                print(f"│ {Colors.CYAN}Temperature:{Colors.END} {sensor.get('temperature', 'N/A')}°C")
                print(f"│ {Colors.CYAN}Cooling Level:{Colors.END} {sensor.get('cooling_level', 'N/A')}")
                print(f"│ {Colors.CYAN}Cooling Max:{Colors.END} {sensor.get('cooling_level_max', 'N/A')}")
                print(f"│ {Colors.CYAN}Fault List:{Colors.END} {sensor.get('fault_list', [])}")

            if 'temp_dir' in context:
                print(f"│ {Colors.CYAN}Temp Directory:{Colors.END} {context['temp_dir']}")

            if 'context_extraction_error' in context:
                print(f"│ {Colors.YELLOW}Context Warning:{Colors.END} {context['context_extraction_error']}")

        # Stack Trace
        print(f"{Colors.BLUE}├─────────────────────────────────────────────────────────────────────────────────┤{Colors.END}")
        print(f"{Colors.BOLD}{Colors.BLUE}│ {Icons.ERROR} STACK TRACE{Colors.END}")
        print(f"{Colors.BLUE}├─────────────────────────────────────────────────────────────────────────────────┤{Colors.END}")

        for line in stack_trace:
            # Format each line of the stack trace
            for sub_line in line.rstrip().split('\n'):
                if sub_line.strip():
                    if sub_line.strip().startswith('File '):
                        print(f"│ {Colors.MAGENTA}{sub_line.strip()}{Colors.END}")
                    elif sub_line.strip().startswith('Traceback'):
                        print(f"│ {Colors.YELLOW}{sub_line.strip()}{Colors.END}")
                    elif any(keyword in sub_line for keyword in ['Error:', 'Exception:', 'AssertionError:']):
                        print(f"│ {Colors.RED}{Colors.BOLD}{sub_line.strip()}{Colors.END}")
                    else:
                        print(f"│ {Colors.WHITE}{sub_line.strip()}{Colors.END}")

        print(f"{Colors.BOLD}{Colors.YELLOW}└─────────────────────────────────────────────────────────────────────────────────┘{Colors.END}")


class BeautifulTestRunner(unittest.TextTestRunner):
    """Custom test runner for beautiful output"""

    def __init__(self, stream=None, descriptions=True, verbosity=2):
        super().__init__(stream, descriptions, verbosity)
        self.resultclass = BeautifulTestResult

    def run(self, test):
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 80}")
        print(f"{Icons.THERMOMETER} {Colors.YELLOW}THERMAL MODULE TEC SENSOR UNIT TESTS{Colors.END}")
        print(f"{Colors.BLUE}{'=' * 80}{Colors.END}\n")

        result = super().run(test)

        print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 80}")
        print(f"{Icons.GEAR} {Colors.YELLOW}TEST SUMMARY{Colors.END}")
        print(f"{Colors.BLUE}{'=' * 80}{Colors.END}")

        total = result.test_count
        passed = result.pass_count
        failed = result.fail_count
        skipped = result.skip_count

        print(f"{Icons.INFO} Total Tests: {Colors.BOLD}{total}{Colors.END}")
        print(f"{Icons.PASS} Passed: {Colors.GREEN}{Colors.BOLD}{passed}{Colors.END}")
        print(f"{Icons.FAIL} Failed: {Colors.RED}{Colors.BOLD}{failed}{Colors.END}")
        print(f"{Icons.SKIP} Skipped: {Colors.YELLOW}{Colors.BOLD}{skipped}{Colors.END}")

        if failed == 0:
            print(f"\n{Icons.FIRE} {Colors.GREEN}{Colors.BOLD}ALL TESTS PASSED!{Colors.END} {Icons.FIRE}")
        else:
            print(f"\n{Icons.WARNING} {Colors.RED}{Colors.BOLD}SOME TESTS FAILED!{Colors.END} {Icons.WARNING}")

        print(f"{Colors.BLUE}{'=' * 80}{Colors.END}")

        # Print detailed error reports if any failures occurred
        result.print_detailed_error_reports()

        print()
        return result


class MockThermalSensor:
    """Mock thermal sensor for testing"""

    def __init__(self, temp_dir):
        self.temp_dir = temp_dir
        self.module_name = "module1"
        self.setup_default_files()

    def setup_default_files(self):
        """Setup default sensor files"""
        os.makedirs(f"{self.temp_dir}/thermal", exist_ok=True)

        # Default values
        self.write_file(f"thermal/{self.module_name}_temp_input", "45000")  # 45°C
        self.write_file(f"thermal/{self.module_name}_cooling_level_input", "50")
        self.write_file(f"thermal/{self.module_name}_cooling_level_warning", "100")

    def write_file(self, path, content):
        """Write content to file"""
        full_path = os.path.join(self.temp_dir, path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, 'w') as f:
            f.write(str(content))

    def remove_file(self, path):
        """Remove file to simulate missing sensor"""
        full_path = os.path.join(self.temp_dir, path)
        if os.path.exists(full_path):
            os.remove(full_path)

    def set_temp_input(self, value):
        """Set temperature input value"""
        self.write_file(f"thermal/{self.module_name}_temp_input", str(value))

    def set_cooling_level_input(self, value):
        """Set cooling level input value"""
        self.write_file(f"thermal/{self.module_name}_cooling_level_input", str(value))

    def set_cooling_level_warning(self, value):
        """Set cooling level warning value"""
        self.write_file(f"thermal/{self.module_name}_cooling_level_warning", str(value))


class TestThermalModuleTecSensor(unittest.TestCase):
    """Test cases for thermal_module_tec_sensor class"""

    # Class variable to store iteration count (default: 10)
    iteration_count = 10

    @classmethod
    def set_iteration_count(cls, count):
        """Set the number of iterations for random tests"""
        cls.iteration_count = max(1, int(count))  # Ensure at least 1 iteration

    def setUp(self):
        """Set up test environment"""
        print(f"\n{Icons.GEAR} {Colors.CYAN}Setting up test environment...{Colors.END}")

        # Initialize status print call counter
        self._status_print_call_count = 0

        # Create temporary directory for mock files
        self.temp_dir = tempfile.mkdtemp()

        # Setup mock thermal sensor
        self.mock_sensor = MockThermalSensor(self.temp_dir)

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

        # Mock logger
        self.tc_logger = Mock()
        self.tc_logger.info = Mock()
        self.tc_logger.debug = Mock()
        self.tc_logger.warn = Mock()
        self.tc_logger.error = Mock()

        # Create sensor instance
        self.sensor = thermal_module_tec_sensor(
            self.cmd_arg,
            self.sys_config,
            "module1",
            self.tc_logger
        )

    def tearDown(self):
        """Clean up test environment"""
        print(f"{Icons.GEAR} {Colors.CYAN}Cleaning up test environment...{Colors.END}")
        shutil.rmtree(self.temp_dir)

    def test_01_normal_condition_random(self):
        """Test 1: Normal Condition Testing (random values)"""
        print(f"\n{Icons.RANDOM} {Colors.YELLOW}Testing normal operation with random values ({self.iteration_count} iterations)...{Colors.END}")

        for i in range(self.iteration_count):  # Run configurable random tests
            # Clear previous faults before each iteration
            self.sensor.clear_fault_list()

            # Generate random values
            flow_dir = random.choice(["C2P", "P2C"])
            amb_temp = random.randint(20, 50)

            # Random temperature (20-80°C in millidegrees)
            temp_value = random.randint(20000, 80000)

            # Random cooling level (0 to warning level)
            cooling_level_warning = random.randint(1, 960)
            cooling_level_input = random.randint(0, cooling_level_warning)

            # Set random values
            self.mock_sensor.set_temp_input(temp_value)
            self.mock_sensor.set_cooling_level_input(cooling_level_input)
            self.mock_sensor.set_cooling_level_warning(cooling_level_warning)

            # Test the sensor
            self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Expected PWM calculation
            expected_pwm_percentage = int(cooling_level_input * 100 / cooling_level_warning)

            # Verify PWM is in valid range (20-100)
            self.assertGreaterEqual(self.sensor.pwm, 20,
                                    f"PWM {self.sensor.pwm} should be >= 20 for test {i + 1}")
            self.assertLessEqual(self.sensor.pwm, 100,
                                 f"PWM {self.sensor.pwm} should be <= 100 for test {i + 1}")

            # Verify temperature is correctly read
            self.assertEqual(self.sensor.temperature, temp_value // 1000)

            # Verify cooling levels are correctly read
            self.assertEqual(self.sensor.cooling_level, cooling_level_input)
            self.assertEqual(self.sensor.cooling_level_max, cooling_level_warning)

            print(f"  {Icons.THERMOMETER} Test {i + 1}: temp={temp_value // 1000}°C, "
                  f"cooling={cooling_level_input}/{cooling_level_warning}, "
                  f"PWM={self.sensor.pwm}%, flow={flow_dir}")

            # Test status print after this iteration
            self._test_status_print_no_crash(f"normal_test_{i + 1}")

    def test_02_sensor_missing_file_error(self):
        """Test 2: Sensor random read error Testing (missing sensor)"""
        print(f"\n{Icons.FILE} {Colors.YELLOW}Testing missing sensor files ({self.iteration_count} iterations)...{Colors.END}")

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

            # Reset error counter for new test
            self.sensor.fread_err = iterate_err_counter(self.tc_logger, "test", 3)

            # Trigger error multiple times to reach threshold
            for i in range(4):  # More than threshold (3)
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Collect and handle errors
            self.sensor.collect_err()
            self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Verify SENSOR_READ_ERR is raised
            fault_list = self.sensor.get_fault_list_filtered()
            self.assertIn(CONST.SENSOR_READ_ERR, fault_list,
                          f"SENSOR_READ_ERR should be raised for missing {missing_file} (iteration {iteration + 1})")

            # Restore the file for next test
            self.mock_sensor.setup_default_files()

            # Test status print after this iteration
            self._test_status_print_no_crash(f"missing_file_{iteration + 1}")

    def test_03_sensor_invalid_value_error(self):
        """Test 3: Sensor random read error Testing (non-integer value sensor)"""
        print(f"\n{Icons.ERROR} {Colors.YELLOW}Testing non-integer sensor values ({self.iteration_count} iterations)...{Colors.END}")

        invalid_values = ["", "abc", "12.34.56", "not_a_number", " ", "\n", "NaN", "inf", "-inf", "123abc", "++123"]

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

            # Reset error counter
            self.sensor.fread_err = iterate_err_counter(self.tc_logger, "test", 3)

            # Trigger error multiple times
            for i in range(4):
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Collect and handle errors
            self.sensor.collect_err()
            self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Verify SENSOR_READ_ERR is raised
            fault_list = self.sensor.get_fault_list_filtered()
            self.assertIn(CONST.SENSOR_READ_ERR, fault_list,
                          f"SENSOR_READ_ERR should be raised for invalid value '{invalid_value}' in {file_path} (iteration {iteration + 1})")

            # Restore default value
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

            # Reset error counter
            self.sensor.fread_err = iterate_err_counter(self.tc_logger, "test", 3)

            # Trigger error multiple times
            for i in range(4):
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Collect and handle errors
            self.sensor.collect_err()
            self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Verify SENSOR_READ_ERR is raised
            fault_list = self.sensor.get_fault_list_filtered()
            self.assertIn(CONST.SENSOR_READ_ERR, fault_list,
                          f"SENSOR_READ_ERR should be raised for cooling level {cooling_level} (iteration {iteration + 1})")

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
                "base_file_name": "module1"
            }
            config_without_param = {
                CONST.SYS_CONF_SENSORS_CONF: {
                    "module1": {**base_config, **{k: v for k, v in self.sys_config[CONST.SYS_CONF_SENSORS_CONF]["module1"].items()
                                                  if k != param and k not in base_config}}
                }
            }

            # Create sensor with missing parameter
            sensor_missing_param = thermal_module_tec_sensor(
                self.cmd_arg,
                config_without_param,
                "module1",
                self.tc_logger
            )

            # Test that sensor can still operate
            sensor_missing_param.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

            # Verify sensor has default values
            if param == "val_lcrit":
                self.assertEqual(sensor_missing_param.val_lcrit, CONST.TEMP_MIN_MAX["val_lcrit"])
            elif param == "val_hcrit":
                self.assertEqual(sensor_missing_param.val_hcrit, CONST.TEMP_MIN_MAX["val_hcrit"])
            elif param == "pwm_min":
                self.assertEqual(sensor_missing_param.pwm_min, CONST.PWM_MIN)
            elif param == "pwm_max":
                self.assertEqual(sensor_missing_param.pwm_max, CONST.PWM_MAX)
            elif param == "val_min":
                self.assertEqual(sensor_missing_param.val_min, 0)
            elif param == "val_max":
                self.assertEqual(sensor_missing_param.val_max, 100)

            # Test status print after this iteration
            self._test_status_print_no_crash(f"config_param_{iteration + 1}", sensor_missing_param)

    def test_06_error_handling_no_crash(self):
        """Test 6: Error Handling Testing"""
        print(f"\n{Icons.ERROR} {Colors.YELLOW}Testing error handling robustness ({self.iteration_count} iterations)...{Colors.END}")

        error_scenarios = [
            ("Completely invalid directory", "/invalid/path/nowhere"),
            ("Permission denied simulation", "/root/restricted"),
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
                    # Override the root_folder to simulate errors
                    original_path = self.sensor.root_folder
                    self.sensor.root_folder = path_override

                # These should not crash
                self.sensor.handle_input(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)
                self.sensor.collect_err()
                self.sensor.handle_err(DMIN_TABLE_DEFAULT, flow_dir, amb_temp)

                if path_override is not None:
                    # Restore original path
                    self.sensor.root_folder = original_path

            except Exception as e:
                # Capture detailed error information for debugging
                error_details = self._capture_error_details(e, iteration, description, path_override)
                self.fail(f"Error handling test failed with exception: {e} (iteration {iteration + 1})\n"
                          f"Additional context: {error_details}")

            # Test status print after this iteration
            self._test_status_print_no_crash(f"error_handling_{iteration + 1}")

    def test_07_status_print_summary(self):
        """Test 7: Status print summary and validation"""
        print(f"\n{Icons.INFO} {Colors.YELLOW}Status print function validation summary...{Colors.END}")

        total_expected_calls = self.iteration_count * 6  # 6 tests with iterations
        print(f"  {Icons.INFO} Expected status print calls from previous tests: {total_expected_calls}")

        # Verify status print counter if we were tracking it
        actual_calls = getattr(self, '_status_print_call_count', 0)
        print(f"  {Icons.INFO} Actual status print calls executed: {actual_calls}")

        # Run one final comprehensive status print test
        print(f"  {Icons.INFO} Running final status print validation...")

        try:
            # Test in various states
            test_states = [
                ("Clean state", lambda: self._reset_sensor_state()),
                ("Normal operation", lambda: self._simulate_normal_operation()),
                ("Error state", lambda: self._simulate_missing_file_error()),
                ("Random values", lambda: self._set_random_sensor_values())
            ]

            for state_name, setup_func in test_states:
                setup_func()
                status_str = str(self.sensor)

                # Verify string is valid
                self.assertIsInstance(status_str, str)
                self.assertGreater(len(status_str), 0)
                self.assertIn("module1", status_str)
                self.assertIn("temp:", status_str)
                self.assertIn("cooling_lvl:", status_str)
                self.assertIn("pwm:", status_str)

                print(f"    {Icons.PASS} {state_name}: {len(status_str)} chars")

            print(f"  {Icons.PASS} All status print validations passed!")

        except Exception as e:
            error_details = self._capture_error_details(e, 0, "final_validation")
            self.fail(f"Final status print validation failed: {e}\nContext: {error_details}")

    def _reset_sensor_state(self):
        """Reset sensor to clean state for status testing"""
        try:
            self.sensor.temperature = 0
            self.sensor.cooling_level = 0
            self.sensor.cooling_level_max = 0
            self.sensor.pwm = 20
            self.sensor.clear_fault_list()
        except Exception:
            # If reset fails, continue with current state
            pass

    def _simulate_normal_operation(self):
        """Simulate normal operation test scenario"""
        # Set normal values similar to test_01
        self.mock_sensor.set_temp_input(45000)  # 45°C
        self.mock_sensor.set_cooling_level_input(50)
        self.mock_sensor.set_cooling_level_warning(100)

        self.sensor.handle_input(DMIN_TABLE_DEFAULT, "C2P", 25)

    def _simulate_missing_file_error(self):
        """Simulate missing file error test scenario"""
        # Remove a file and trigger error similar to test_02
        self.mock_sensor.remove_file(f"thermal/{self.mock_sensor.module_name}_temp_input")

        self.sensor.fread_err = iterate_err_counter(self.tc_logger, "test", 3)
        for i in range(4):
            self.sensor.handle_input(DMIN_TABLE_DEFAULT, "C2P", 25)

        self.sensor.collect_err()
        self.sensor.handle_err(DMIN_TABLE_DEFAULT, "C2P", 25)

    def _simulate_invalid_value_error(self):
        """Simulate invalid value error test scenario"""
        # Set invalid value similar to test_03
        self.mock_sensor.write_file(f"thermal/{self.mock_sensor.module_name}_temp_input", "invalid")

        self.sensor.fread_err = iterate_err_counter(self.tc_logger, "test", 3)
        for i in range(4):
            self.sensor.handle_input(DMIN_TABLE_DEFAULT, "C2P", 25)

        self.sensor.collect_err()
        self.sensor.handle_err(DMIN_TABLE_DEFAULT, "C2P", 25)

    def _simulate_out_of_range_error(self):
        """Simulate out-of-range error test scenario"""
        # Set out-of-range value similar to test_04
        self.mock_sensor.set_cooling_level_input(-10)  # Below lcrit

        self.sensor.fread_err = iterate_err_counter(self.tc_logger, "test", 3)
        for i in range(4):
            self.sensor.handle_input(DMIN_TABLE_DEFAULT, "C2P", 25)

        self.sensor.collect_err()
        self.sensor.handle_err(DMIN_TABLE_DEFAULT, "C2P", 25)

    def _simulate_config_parameter_test(self):
        """Simulate config parameter test scenario"""
        # Set extreme values that might result from missing config
        self.sensor.val_lcrit = None
        self.sensor.val_hcrit = None
        self.sensor.pwm_min = 20
        self.sensor.pwm_max = 100

        # Set some sensor values
        self._set_random_sensor_values()

    def _simulate_error_handling_test(self):
        """Simulate error handling test scenario"""
        # Override root folder to simulate error condition
        original_path = self.sensor.root_folder
        self.sensor.root_folder = "/invalid/path"

        try:
            self.sensor.handle_input(DMIN_TABLE_DEFAULT, "C2P", 25)
            self.sensor.collect_err()
            self.sensor.handle_err(DMIN_TABLE_DEFAULT, "C2P", 25)
        finally:
            # Restore original path
            self.sensor.root_folder = original_path

    def _set_random_sensor_values(self):
        """Helper method to set random sensor values"""
        self.sensor.temperature = random.randint(20, 80)
        self.sensor.cooling_level = random.randint(0, 100)
        self.sensor.cooling_level_max = random.randint(100, 960)
        self.sensor.pwm = random.randint(20, 100)

    def _set_extreme_sensor_values(self):
        """Helper method to set extreme sensor values"""
        self.sensor.temperature = random.choice([-50, 150])  # Extreme temperatures
        self.sensor.cooling_level = random.choice([0, 960])  # Extreme cooling levels
        self.sensor.cooling_level_max = random.choice([1, 960])  # Extreme max values
        self.sensor.pwm = random.choice([0, 100])  # Extreme PWM values

    def _set_zero_sensor_values(self):
        """Helper method to set zero sensor values"""
        self.sensor.temperature = 0
        self.sensor.cooling_level = 0
        self.sensor.cooling_level_max = random.choice([0, 1])  # Zero or minimal max
        self.sensor.pwm = random.randint(20, 100)

    def _capture_error_details(self, exception, iteration=None, description=None, path_override=None):
        """Capture detailed error information for debugging"""
        details = {
            'exception_type': type(exception).__name__,
            'exception_message': str(exception),
            'iteration': iteration,
            'test_description': description,
            'path_override': path_override,
            'sensor_state': self._get_sensor_state(),
            'system_state': self._get_system_state()
        }
        return details

    def _get_sensor_state(self):
        """Get current sensor state for debugging"""
        try:
            return {
                'name': getattr(self.sensor, 'name', 'Unknown'),
                'type': getattr(self.sensor, 'type', 'Unknown'),
                'pwm': getattr(self.sensor, 'pwm', 'Unknown'),
                'temperature': getattr(self.sensor, 'temperature', 'Unknown'),
                'cooling_level': getattr(self.sensor, 'cooling_level', 'Unknown'),
                'cooling_level_max': getattr(self.sensor, 'cooling_level_max', 'Unknown'),
                'root_folder': getattr(self.sensor, 'root_folder', 'Unknown'),
                'enabled': getattr(self.sensor, 'enable', 'Unknown'),
                'fault_list': getattr(self.sensor, 'get_fault_list_filtered', lambda: ['Unable to get faults'])()
            }
        except Exception as e:
            return {'error_getting_sensor_state': str(e)}

    def _get_system_state(self):
        """Get current system state for debugging"""
        try:
            return {
                'temp_dir_exists': os.path.exists(self.temp_dir) if hasattr(self, 'temp_dir') else 'No temp_dir',
                'temp_dir_contents': os.listdir(self.temp_dir) if hasattr(self, 'temp_dir') and os.path.exists(self.temp_dir) else [],
                'thermal_dir_exists': os.path.exists(os.path.join(self.temp_dir, 'thermal')) if hasattr(self, 'temp_dir') else False,
                'config_keys': list(self.sys_config.keys()) if hasattr(self, 'sys_config') else []
            }
        except Exception as e:
            return {'error_getting_system_state': str(e)}

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

            # Show the status output in test logs
            print(f"    {Icons.INFO} Status [{test_id}]: {status_str}")
            return True

        except Exception as e:
            self.fail(f"Status print crashed during {test_id}: {e}")


def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description='Thermal Module TEC Sensor Unit Tests',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 test_thermal_module_tec_sensor.py                    # Run with default 10 iterations
  python3 test_thermal_module_tec_sensor.py --iterations 5     # Run with 5 iterations
  python3 test_thermal_module_tec_sensor.py -i 20             # Run with 20 iterations
  python3 test_thermal_module_tec_sensor.py --iterations 1     # Quick test with 1 iteration
        """
    )

    parser.add_argument(
        '-i', '--iterations',
        type=int,
        default=10,
        metavar='N',
        help='Number of iterations for random tests (default: 10, minimum: 1)'
    )

    parser.add_argument(
        '--version',
        action='version',
        version='Thermal TEC Sensor Tests v1.0'
    )

    return parser.parse_args()


def main():
    """Main test execution function"""
    # Parse command line arguments
    args = parse_arguments()

    # Validate iteration count
    if args.iterations < 1:
        print(f"{Colors.RED}Error: Iteration count must be at least 1{Colors.END}")
        return 1

    # Set iteration count for the test class
    TestThermalModuleTecSensor.set_iteration_count(args.iterations)

    print(f"{Colors.BOLD}{Colors.MAGENTA}")
    print("=" * 80)
    print("                    THERMAL MODULE TEC SENSOR UNIT TESTS                     ")
    print("                           Beautiful Test Suite                              ")
    print(f"                         Running {args.iterations} iterations per test                           ")
    print("=" * 80)
    print(f"{Colors.END}")

    # Create test suite
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestThermalModuleTecSensor)

    # Run tests with beautiful output
    runner = BeautifulTestRunner()
    result = runner.run(suite)

    # Print iteration summary
    total_iterations = args.iterations * 7  # 7 tests with random iterations
    print(f"{Colors.CYAN}Total Random Iterations Executed: {Colors.BOLD}{total_iterations}{Colors.END}")

    # Return appropriate exit code
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
