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
Unit test for hw_management_thermal_updater.py module_temp_populate function.
This test is agnostic to the folder from where it is running.
"""

import os
import sys
import unittest
import tempfile
import shutil
import random
import argparse
from unittest.mock import patch, MagicMock
import importlib.util


class TestModuleTempPopulate(unittest.TestCase):
    """Test class for module_temp_populate function"""

    def setUp(self):
        """Set up test fixtures before each test method."""
        # Create temporary directories for testing
        self.temp_dir = tempfile.mkdtemp()
        self.thermal_dir = os.path.join(self.temp_dir, "var", "run", "hw-management", "thermal")
        self.config_dir = os.path.join(self.temp_dir, "var", "run", "hw-management", "config")
        self.module_src_dir = os.path.join(self.temp_dir, "sys", "module", "sx_core", "asic0")

        # Create directory structure
        os.makedirs(self.thermal_dir, exist_ok=True)
        os.makedirs(self.config_dir, exist_ok=True)
        os.makedirs(self.module_src_dir, exist_ok=True)

        # Store original working directory
        self.original_cwd = os.getcwd()

        # Module configuration
        self.module_count = 5
        self.offset = 1

        # Generate random module configurations
        self.module_configs = []
        for i in range(self.module_count):
            config = {
                'present': random.choice([0, 1]),
                'mode': random.choice([0, 1]),  # 0 = SDK_FW_CONTROL, 1 = SDK_SW_CONTROL
                'temperature_input': random.randint(20, 50),  # Temperature in SDK format
                'temperature_threshold': random.randint(60, 80)  # Threshold temperature
            }
            self.module_configs.append(config)
            print(f"Module {i + self.offset}: present={config['present']}, mode={config['mode']}, "
                  f"temp={config['temperature_input']}, threshold={config['temperature_threshold']}")

        # Create module directories and files
        self._setup_module_files()

    def tearDown(self):
        """Clean up after each test method."""
        # Remove temporary directory
        shutil.rmtree(self.temp_dir, ignore_errors=True)

        # Restore original working directory
        os.chdir(self.original_cwd)

    def _setup_module_files(self):
        """Set up module files for testing"""
        for idx, config in enumerate(self.module_configs):
            module_dir = os.path.join(self.module_src_dir, f"module{idx}")
            temp_dir = os.path.join(module_dir, "temperature")

            os.makedirs(temp_dir, exist_ok=True)

            # Create control file (mode)
            with open(os.path.join(module_dir, "control"), 'w') as f:
                f.write(str(config['mode']))

            # Create present file
            with open(os.path.join(module_dir, "present"), 'w') as f:
                f.write(str(config['present']))

            # Create temperature files if present
            if config['present']:
                with open(os.path.join(temp_dir, "input"), 'w') as f:
                    f.write(str(config['temperature_input']))

                with open(os.path.join(temp_dir, "threshold_hi"), 'w') as f:
                    f.write(str(config['temperature_threshold']))

    def _load_hw_management_module(self, hw_mgmt_path):
        """Dynamically load the hw_management_thermal_updater module from given path"""
        # Add the directory containing hw_management_thermal_updater.py to sys.path
        hw_mgmt_dir = os.path.dirname(os.path.abspath(hw_mgmt_path))
        if hw_mgmt_dir not in sys.path:
            sys.path.insert(0, hw_mgmt_dir)

        spec = importlib.util.spec_from_file_location("hw_management_thermal_updater", hw_mgmt_path)
        hw_mgmt_module = importlib.util.module_from_spec(spec)

        # Mock sys.modules to avoid import issues
        sys.modules["hw_management_redfish_client"] = MagicMock()

        spec.loader.exec_module(hw_mgmt_module)

        # Ensure LOGGER is mocked if it's None
        if hw_mgmt_module.LOGGER is None:
            hw_mgmt_module.LOGGER = MagicMock()

        return hw_mgmt_module

    def _sdk_temp2degree(self, val):
        """Convert SDK temperature format to degrees (copied from original)"""
        if val >= 0:
            temperature = val * 125
        else:
            temperature = 0xffff + val + 1
        return temperature

    def test_module_temp_populate_all_scenarios(self):
        """Test module_temp_populate with various module configurations"""

        # Load the module
        hw_mgmt_module = self._load_hw_management_module(self.hw_mgmt_path)

        # Prepare arguments
        arg_list = {
            "fin": os.path.join(self.module_src_dir, "module{}/"),
            "fout_idx_offset": self.offset,
            "module_count": self.module_count
        }

        # Track written files and their content
        written_files = {}
        original_open = open
        original_islink = os.path.islink

        def mock_open_func(filename, mode='r', **kwargs):
            # Redirect thermal directory paths to our temp directory
            if filename.startswith('/var/run/hw-management/thermal/'):
                filename = filename.replace('/var/run/hw-management/thermal/',
                                            self.thermal_dir + '/')
            elif filename.startswith('/var/run/hw-management/config/'):
                filename = filename.replace('/var/run/hw-management/config/',
                                            self.config_dir + '/')

            # Ensure directory exists for write operations
            if 'w' in mode:
                os.makedirs(os.path.dirname(filename), exist_ok=True)
                # Track what files are being written to
                written_files[filename] = None

            return original_open(filename, mode, **kwargs)

        def mock_islink_func(path):
            # Redirect thermal directory paths to our temp directory
            if path.startswith('/var/run/hw-management/thermal/'):
                path = path.replace('/var/run/hw-management/thermal/',
                                    self.thermal_dir + '/')
            # Always return False (no links exist in our test environment)
            return False

        # Apply patches
        with patch('builtins.open', side_effect=mock_open_func), \
                patch('os.path.islink', side_effect=mock_islink_func):

            # Call the function under test
            hw_mgmt_module.module_temp_populate(arg_list, None)

            # Verify results for each module
            for idx, config in enumerate(self.module_configs):
                module_name = f"module{idx + self.offset}"

                if config['mode'] == 1:  # SDK_SW_CONTROL
                    # Files should NOT be created for SW control mode
                    self._verify_files_not_created(module_name, written_files)
                    print(f"[+] Module {module_name}: SW control mode - no files created")

                else:  # SDK_FW_CONTROL
                    if config['present'] == 0:
                        # Files should contain zeros for absent modules
                        self._verify_absent_module_files(module_name)
                        print(f"[+] Module {module_name}: FW control, not present - zero values")

                    else:
                        # Files should contain actual temperature values
                        expected_temp = self._sdk_temp2degree(config['temperature_input'])
                        expected_crit = self._sdk_temp2degree(config['temperature_threshold'])
                        self._verify_present_module_files(module_name, expected_temp, expected_crit)
                        print(f"[+] Module {module_name}: FW control, present - actual values "
                              f"(temp={expected_temp}, crit={expected_crit})")

            # Note: module_counter file is now written by write_module_counter() during initialization,
            # not by module_temp_populate(). This is a design change to improve reliability.
            # self._verify_module_counter()  # Disabled - module_counter now handled separately
            print("[+] Test completed (Note: module_counter now written by write_module_counter() during init)")

    def _verify_files_not_created(self, module_name, written_files):
        """Verify that thermal files are not created for SW control modules"""
        suffixes = ["_temp_input", "_temp_crit", "_temp_emergency", "_temp_fault", "_temp_trip_crit"]

        for suffix in suffixes:
            filename = os.path.join(self.thermal_dir, f"{module_name}{suffix}")
            self.assertFalse(os.path.exists(filename),
                             f"File {filename} should not exist for SW control module")
            # Also check that it wasn't in the written files list
            self.assertNotIn(filename, written_files,
                             f"File {filename} should not have been written for SW control module")

    def _verify_absent_module_files(self, module_name):
        """Verify thermal files contain zeros for absent modules"""
        expected_values = {
            "_temp_input": "0",
            "_temp_crit": "0",
            "_temp_emergency": "0",
            "_temp_fault": "0",
            "_temp_trip_crit": "0"
        }

        for suffix, expected_value in expected_values.items():
            filename = os.path.join(self.thermal_dir, f"{module_name}{suffix}")
            self.assertTrue(os.path.exists(filename), f"File {filename} should exist")

            with open(filename, 'r') as f:
                content = f.read().strip()
                self.assertEqual(content, expected_value,
                                 f"File {filename} should contain '{expected_value}', got '{content}'")

    def _verify_present_module_files(self, module_name, expected_temp, expected_crit):
        """Verify thermal files contain correct values for present modules"""
        expected_emergency = expected_crit + 10000  # CONST.MODULE_TEMP_EMERGENCY_OFFSET
        expected_trip_crit = 120000  # CONST.MODULE_TEMP_CRIT_DEF

        expected_values = {
            "_temp_input": str(expected_temp),
            "_temp_crit": str(expected_crit),
            "_temp_emergency": str(expected_emergency),
            "_temp_fault": "0",
            "_temp_trip_crit": str(expected_trip_crit)
        }

        for suffix, expected_value in expected_values.items():
            filename = os.path.join(self.thermal_dir, f"{module_name}{suffix}")
            self.assertTrue(os.path.exists(filename), f"File {filename} should exist")

            with open(filename, 'r') as f:
                content = f.read().strip()
                self.assertEqual(content, expected_value,
                                 f"File {filename} should contain '{expected_value}', got '{content}'")

    def _verify_module_counter(self):
        """Verify module counter file is created with correct count"""
        counter_file = os.path.join(self.config_dir, "module_counter")
        self.assertTrue(os.path.exists(counter_file), "module_counter file should exist")

        with open(counter_file, 'r') as f:
            content = f.read().strip()
            self.assertEqual(content, str(self.module_count),
                             f"module_counter should contain '{self.module_count}', got '{content}'")


def main():
    """Main function to run tests with command line arguments"""
    parser = argparse.ArgumentParser(description='Test module_temp_populate function')
    parser.add_argument('hw_mgmt_path', nargs='?',
                        help='Path to hw_management_thermal_updater.py file (optional, auto-detects if not provided)')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Verbose output')

    args, unittest_args = parser.parse_known_args()

    # Determine the hw_management_thermal_updater.py path
    if args.hw_mgmt_path:
        hw_mgmt_path = args.hw_mgmt_path
    else:
        # Auto-detect using relative path from test location
        script_dir = os.path.dirname(os.path.abspath(__file__))
        hw_mgmt_path = os.path.join(script_dir, '..', '..', '..', '..', 'usr', 'usr', 'bin', 'hw_management_thermal_updater.py')
        hw_mgmt_path = os.path.abspath(hw_mgmt_path)

    # Validate the hw_management_thermal_updater.py path
    if not os.path.isfile(hw_mgmt_path):
        print(f"Error: File {hw_mgmt_path} does not exist")
        sys.exit(1)

    # Store the path for use in tests
    TestModuleTempPopulate.hw_mgmt_path = os.path.abspath(hw_mgmt_path)

    print(f"Testing hw_management_thermal_updater.py from: {TestModuleTempPopulate.hw_mgmt_path}")
    print("=" * 70)

    # Run the tests
    unittest.main(argv=[sys.argv[0]] + unittest_args,
                  verbosity=2 if args.verbose else 1)


if __name__ == '__main__':
    main()
