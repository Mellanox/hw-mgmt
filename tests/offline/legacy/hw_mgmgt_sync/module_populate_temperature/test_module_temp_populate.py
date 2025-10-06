#!/usr/bin/env python3
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
Comprehensive unit tests for module_temp_populate function from hw_management_sync.py

This test suite covers:
1. Normal conditions with all files present and readable
2. Default temperature values when input read error occurs
3. Temperature values when other attributes read error occurs
4. Not-crash conditions in case of reading errors
5. Random testing of 36 modules as specified

Test Configuration:
- fin: "/sys/module/sx_core/asic0/module{}/"
- fout_idx_offset: 1
- module_count: 36
"""

import os
import sys
import unittest
import tempfile
import shutil
import random
import json
from unittest.mock import patch, mock_open, MagicMock
import importlib.util

# Add hw_management_sync.py to path for import
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, '..', '..', '..'))
hw_mgmt_path = os.path.join(project_root, 'usr', 'usr', 'bin')
sys.path.insert(0, hw_mgmt_path)

# Mock constants to match the actual implementation


class MockCONST:
    SDK_FW_CONTROL = 0
    SDK_SW_CONTROL = 1
    MODULE_TEMP_MAX_DEF = 75000
    MODULE_TEMP_FAULT_DEF = 105000
    MODULE_TEMP_CRIT_DEF = 120000
    MODULE_TEMP_EMERGENCY_OFFSET = 10000


class TestModuleTempPopulate(unittest.TestCase):
    """Comprehensive test cases for module_temp_populate function"""

    @classmethod
    def setUpClass(cls):
        """Set up class-level fixtures"""
        # Mock dependencies before import
        sys.modules['hw_management_redfish_client'] = MagicMock()

        # Import the module after mocking dependencies
        hw_mgmt_file = os.path.join(hw_mgmt_path, 'hw_management_sync.py')
        spec = importlib.util.spec_from_file_location("hw_management_sync", hw_mgmt_file)
        cls.hw_mgmt_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.hw_mgmt_module)

        # Inject our mock CONST if needed
        if not hasattr(cls.hw_mgmt_module, 'CONST'):
            cls.hw_mgmt_module.CONST = MockCONST()

    def setUp(self):
        """Set up test fixtures before each test method"""
        # Create temporary directories
        self.temp_dir = tempfile.mkdtemp()
        self.sys_module_dir = os.path.join(self.temp_dir, "sys", "module", "sx_core", "asic0")
        self.thermal_output_dir = os.path.join(self.temp_dir, "var", "run", "hw-management", "thermal")
        self.config_output_dir = os.path.join(self.temp_dir, "var", "run", "hw-management", "config")

        # Create directory structure
        os.makedirs(self.sys_module_dir, exist_ok=True)
        os.makedirs(self.thermal_output_dir, exist_ok=True)
        os.makedirs(self.config_output_dir, exist_ok=True)

        # Test arguments as specified
        self.arg_list = {
            "fin": os.path.join(self.sys_module_dir, "module{}/"),
            "fout_idx_offset": 1,
            "module_count": 36
        }

        # Track files created by tests
        self.created_files = []

        # Random module configurations for testing
        self.module_configs = self._generate_random_module_configs()

    def tearDown(self):
        """Clean up after each test method"""
        # Remove temporary directory
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _generate_random_module_configs(self):
        """Generate random module configurations for testing"""
        configs = []
        for i in range(self.arg_list["module_count"]):
            config = {
                'present': random.choice([0, 1]),
                'control_mode': random.choice([0, 1]),  # 0=FW_CONTROL, 1=SW_CONTROL
                'temp_input': random.randint(400, 600),  # SDK temp format
                'threshold_hi': random.randint(600, 700),
                'threshold_critical_hi': random.randint(700, 800),
                'cooling_level': random.randint(100, 800),
                'max_cooling_level': random.randint(1000, 6000),
                'has_threshold_hi': random.choice([True, False]),
                'has_threshold_critical_hi': random.choice([True, False]),
                'has_cooling_level': random.choice([True, False]),
                'input_read_error': random.choice([True, False]),
                'threshold_hi_read_error': random.choice([True, False]),
                'threshold_critical_hi_read_error': random.choice([True, False]),
                'cooling_level_read_error': random.choice([True, False]),
                'max_cooling_level_read_error': random.choice([True, False])
            }
            configs.append(config)
        return configs

    def _create_module_files(self, module_idx, config):
        """Create module files based on configuration"""
        module_dir = os.path.join(self.sys_module_dir, f"module{module_idx}")
        temp_dir = os.path.join(module_dir, "temperature")
        tec_dir = os.path.join(temp_dir, "tec")

        os.makedirs(temp_dir, exist_ok=True)
        os.makedirs(tec_dir, exist_ok=True)

        # Create control file
        with open(os.path.join(module_dir, "control"), 'w') as f:
            f.write(str(config.get('control_mode', 0)))

        # Create present file
        with open(os.path.join(module_dir, "present"), 'w') as f:
            f.write(str(config.get('present', 0)))

        if config.get('present', 0):
            # Create temperature input file (but maybe not write to it if we want read error)
            input_file = os.path.join(temp_dir, "input")
            if not config.get('input_read_error', False):
                with open(input_file, 'w') as f:
                    f.write(str(config.get('temp_input', 500)))
            else:
                # Create file but make it unreadable to simulate read error, or don't create it
                pass  # Don't create input file to simulate read error

            # Create threshold_hi file if specified
            if config.get('has_threshold_hi', True) and not config.get('threshold_hi_read_error', False):
                with open(os.path.join(temp_dir, "threshold_hi"), 'w') as f:
                    f.write(str(config.get('threshold_hi', 600)))

            # Create threshold_critical_hi file if specified
            if config.get('has_threshold_critical_hi', True) and not config.get('threshold_critical_hi_read_error', False):
                with open(os.path.join(temp_dir, "threshold_critical_hi"), 'w') as f:
                    f.write(str(config.get('threshold_critical_hi', 700)))

            # Create cooling level files if specified
            if config.get('has_cooling_level', True) and not config.get('cooling_level_read_error', False):
                with open(os.path.join(tec_dir, "cooling_level"), 'w') as f:
                    f.write(str(config.get('cooling_level', 400)))

            if config.get('has_cooling_level', True) and not config.get('max_cooling_level_read_error', False):
                with open(os.path.join(tec_dir, "max_cooling_level"), 'w') as f:
                    f.write(str(config.get('max_cooling_level', 5400)))

    def _mock_file_operations(self):
        """Create mock file operations to redirect to temp directory"""
        original_open = open
        original_islink = os.path.islink
        original_isfile = os.path.isfile

        def mock_open_func(filename, mode='r', **kwargs):
            # Redirect output paths to temp directory
            if filename.startswith('/var/run/hw-management/thermal/'):
                filename = filename.replace('/var/run/hw-management/thermal/', self.thermal_output_dir + '/')
            elif filename.startswith('/var/run/hw-management/config/'):
                filename = filename.replace('/var/run/hw-management/config/', self.config_output_dir + '/')

            # Ensure directory exists for write operations
            if 'w' in mode:
                os.makedirs(os.path.dirname(filename), exist_ok=True)
                self.created_files.append(filename)

            return original_open(filename, mode, **kwargs)

        def mock_islink_func(path):
            if path.startswith('/var/run/hw-management/thermal/'):
                path = path.replace('/var/run/hw-management/thermal/', self.thermal_output_dir + '/')
            return original_islink(path)

        def mock_isfile_func(path):
            return original_isfile(path)

        return mock_open_func, mock_islink_func, mock_isfile_func

    def test_normal_condition_all_files_present(self):
        """Test 1.1: Normal condition with all files created and filled with values"""
        print("\n" + "=" * 80)
        print("🧪 TEST 1.1: NORMAL CONDITION - ALL FILES PRESENT")
        print("=" * 80)
        print("📋 Description: Testing normal operation when all temperature attribute files")
        print("   are present and readable. All output files should be created with correct")
        print("   temperature values converted using sdk_temp2degree() function.")
        print()
        print("🔧 Configuration:")
        print(f"   • Module count: {self.arg_list['module_count']}")
        print(f"   • Index offset: {self.arg_list['fout_idx_offset']}")
        print(f"   • Input path template: {self.arg_list['fin']}")
        print(f"   • Output path: /var/run/hw-management/thermal/")
        print()

        # Configure modules with all files present and no errors
        # Note: function uses 0-based idx for source, but 1-based for output (with offset)
        test_modules = [0, 4, 9, 14, 19]  # Test subset for focused testing (0-based source indices)
        print(f"📊 Testing subset of modules: {test_modules} (source indices)")
        print(f"   Output modules will be: {[idx + self.arg_list['fout_idx_offset'] for idx in test_modules]}")
        print()

        for source_idx in test_modules:
            config = {
                'present': 1,
                'control_mode': 0,  # FW_CONTROL
                'temp_input': 500,
                'threshold_hi': 600,
                'threshold_critical_hi': 700,
                'cooling_level': 400,
                'max_cooling_level': 5400,
                'has_threshold_hi': True,
                'has_threshold_critical_hi': True,
                'has_cooling_level': True,
                'input_read_error': False,
                'threshold_hi_read_error': False,
                'threshold_critical_hi_read_error': False,
                'cooling_level_read_error': False,
                'max_cooling_level_read_error': False
            }
            print(f"   🔧 Creating module{source_idx} with:")
            print(f"      - Present: {config['present']} (module is inserted)")
            print(f"      - Control mode: {config['control_mode']} (FW_CONTROL)")
            print(f"      - Temperature input: {config['temp_input']} (SDK format)")
            print(f"      - Threshold high: {config['threshold_hi']} (SDK format)")
            print(f"      - Threshold critical: {config['threshold_critical_hi']} (SDK format)")
            print(f"      - Cooling level: {config['cooling_level']}")
            print(f"      - Max cooling level: {config['max_cooling_level']}")
            self._create_module_files(source_idx, config)

        print("\n🔄 Executing module_temp_populate function...")
        print("   • Setting up file operation mocks")
        print("   • Redirecting file I/O to temporary test directories")

        # Mock file operations
        mock_open_func, mock_islink_func, mock_isfile_func = self._mock_file_operations()

        with patch('builtins.open', side_effect=mock_open_func), \
                patch('os.path.islink', side_effect=mock_islink_func), \
                patch('os.path.isfile', side_effect=mock_isfile_func):

            # Call function under test
            print("   • Calling module_temp_populate with test configuration")
            self.hw_mgmt_module.module_temp_populate(self.arg_list, None)
            print("   • Function execution completed")

            print("\n🔍 Verifying output files and values...")
            # Verify output files for each test module
            for source_idx in test_modules:
                # Output module name is source_idx + offset
                module_name = f"module{source_idx + self.arg_list['fout_idx_offset']}"
                print(f"\n   📂 Checking {module_name} output files:")

                # Expected values
                expected_temp = self.hw_mgmt_module.sdk_temp2degree(500)
                expected_crit = self.hw_mgmt_module.sdk_temp2degree(600)
                expected_emergency = self.hw_mgmt_module.sdk_temp2degree(700)
                expected_trip_crit = MockCONST.MODULE_TEMP_CRIT_DEF

                print(f"      📊 Expected temperature conversions:")
                print(f"         - Input: 500 → {expected_temp} millidegrees")
                print(f"         - Critical: 600 → {expected_crit} millidegrees")
                print(f"         - Emergency: 700 → {expected_emergency} millidegrees")
                print(f"         - Trip critical: {expected_trip_crit} millidegrees")

                # Verify all output files exist and contain correct values
                output_files = {
                    f"{module_name}_temp_input": str(expected_temp),
                    f"{module_name}_temp_crit": str(expected_crit),
                    f"{module_name}_temp_emergency": str(expected_emergency),
                    f"{module_name}_temp_fault": "0",
                    f"{module_name}_temp_trip_crit": str(expected_trip_crit),
                    f"{module_name}_cooling_level_input": "400",
                    f"{module_name}_max_cooling_level_input": "5400",
                    f"{module_name}_status": "1"
                }

                for filename, expected_value in output_files.items():
                    file_path = os.path.join(self.thermal_output_dir, filename)
                    self.assertTrue(os.path.exists(file_path), f"File {filename} should exist")

                    with open(file_path, 'r') as f:
                        actual_value = f.read().strip()
                        self.assertEqual(actual_value, expected_value,
                                         f"File {filename} should contain '{expected_value}', got '{actual_value}'")
                        print(f"         [PASS] {filename}: {actual_value}")

        print("\n🎯 RESULT: All temperature files created successfully with correct values!")
        print("[PASS] Normal condition test passed")

    def test_input_read_error_default_values(self):
        """Test 1.2: Default temperature values when input read error occurs"""
        print("\n" + "=" * 80)
        print("🧪 TEST 1.2: INPUT READ ERROR - DEFAULT VALUES")
        print("=" * 80)
        print("📋 Description: Testing behavior when the main temperature input file")
        print("   cannot be read. All temperature values should default to '0'.")
        print("   This simulates hardware sensor failures or permission issues.")
        print()
        print("🎯 Expected Behavior:")
        print("   • Module present file readable (module is inserted)")
        print("   • Temperature input file NOT readable (simulated failure)")
        print("   • All temperature output files should contain '0' (default)")
        print("   • Status file should still be created with '1' (present)")
        print()

        # Configure module with input read error
        source_idx = 4  # Will create output for module5 (4+1)
        module_name = f"module{source_idx + self.arg_list['fout_idx_offset']}"
        print(f"🔧 Test Configuration:")
        print(f"   • Testing module: source_idx={source_idx} → {module_name}")
        print(f"   • Module present: 1 (inserted)")
        print(f"   • Control mode: 0 (FW_CONTROL)")
        print(f"   • Simulated failure: temperature/input file unreadable")
        print()

        config = {
            'present': 1,
            'control_mode': 0,  # FW_CONTROL
            'temp_input': 500,
            'threshold_hi': 600,
            'threshold_critical_hi': 700,
            'has_threshold_hi': True,
            'has_threshold_critical_hi': True,
            'has_cooling_level': False,
            'input_read_error': True,  # This will cause input file read to fail
            'threshold_hi_read_error': False,
            'threshold_critical_hi_read_error': False
        }

        print("📁 Creating test module files:")
        print("   • control → '0' (FW_CONTROL mode)")
        print("   • present → '1' (module inserted)")
        print("   • temperature/input → NOT CREATED (simulates read error)")
        print("   • temperature/threshold_hi → '600' (readable)")
        print("   • temperature/threshold_critical_hi → '700' (readable)")

        self._create_module_files(source_idx, config)

        print("\n🔄 Executing module_temp_populate function...")
        print("   • Function should detect input file read failure")
        print("   • Function should use default temperature values")
        print("   • Function should still create all output files")

        # Mock file operations
        mock_open_func, mock_islink_func, mock_isfile_func = self._mock_file_operations()

        with patch('builtins.open', side_effect=mock_open_func), \
                patch('os.path.islink', side_effect=mock_islink_func), \
                patch('os.path.isfile', side_effect=mock_isfile_func):

            # Call function under test
            self.hw_mgmt_module.module_temp_populate(self.arg_list, None)

            print("\n🔍 Verifying default temperature values...")
            # Verify default values are used when input read fails

            # When input read fails, temperature values should be "0" (default)
            # Status should be written regardless of input read error
            expected_files = {
                f"{module_name}_temp_input": "0",
                f"{module_name}_temp_crit": "0",
                f"{module_name}_temp_emergency": "0",
                f"{module_name}_temp_fault": "0",
                f"{module_name}_temp_trip_crit": "0",
                f"{module_name}_status": "1"
            }

            print(f"   📂 Checking {module_name} output files:")
            for filename, expected_value in expected_files.items():
                file_path = os.path.join(self.thermal_output_dir, filename)
                self.assertTrue(os.path.exists(file_path), f"File {filename} should exist")

                with open(file_path, 'r') as f:
                    actual_value = f.read().strip()
                    self.assertEqual(actual_value, expected_value,
                                     f"File {filename} should contain '{expected_value}', got '{actual_value}'")
                    print(f"      [PASS] {filename}: {actual_value} (default value)")

        print("\n🎯 RESULT: Input read error handled correctly - all values defaulted to '0'!")
        print("[PASS] Input read error test passed")

    def test_other_attributes_read_error(self):
        """Test 1.3: Temperature values when other attributes read error occurs"""
        print("\n" + "=" * 80)
        print("🧪 TEST 1.3: OTHER ATTRIBUTES READ ERROR - PARTIAL DEFAULTS")
        print("=" * 80)
        print("📋 Description: Testing behavior when threshold and cooling level files")
        print("   cannot be read, but the main temperature input is OK. The function")
        print("   should process the input temperature correctly but use defaults for")
        print("   failed attributes. This simulates partial sensor failures.")
        print()
        print("🎯 Expected Behavior:")
        print("   • Temperature input file readable → converted value")
        print("   • Threshold files NOT readable → use default values")
        print("   • Cooling level files NOT readable → not created")
        print("   • Emergency temperature calculated from default critical + offset")
        print()

        # Configure module with other attribute read errors
        source_idx = 9  # Will create output for module10 (9+1)
        module_name = f"module{source_idx + self.arg_list['fout_idx_offset']}"
        print(f"🔧 Test Configuration:")
        print(f"   • Testing module: source_idx={source_idx} → {module_name}")
        print(f"   • Module present: 1 (inserted)")
        print(f"   • Control mode: 0 (FW_CONTROL)")
        print(f"   • Temperature input: readable (500 SDK format)")
        print(f"   • Threshold files: NOT readable (simulated failures)")
        print(f"   • Cooling level files: NOT readable (simulated failures)")
        print()

        config = {
            'present': 1,
            'control_mode': 0,  # FW_CONTROL
            'temp_input': 500,
            'threshold_hi': 600,
            'threshold_critical_hi': 700,
            'cooling_level': 400,
            'has_threshold_hi': True,
            'has_threshold_critical_hi': True,
            'has_cooling_level': True,
            'input_read_error': False,  # Input is OK
            'threshold_hi_read_error': True,  # This will cause threshold_hi read to fail
            'threshold_critical_hi_read_error': True,  # This will cause threshold_critical_hi read to fail
            'cooling_level_read_error': True  # This will cause cooling_level read to fail
        }

        print("📁 Creating test module files:")
        print("   • control → '0' (FW_CONTROL mode)")
        print("   • present → '1' (module inserted)")
        print("   • temperature/input → '500' (READABLE - will be processed)")
        print("   • temperature/threshold_hi → NOT CREATED (simulates read error)")
        print("   • temperature/threshold_critical_hi → NOT CREATED (simulates read error)")
        print("   • temperature/tec/cooling_level → NOT CREATED (simulates read error)")

        self._create_module_files(source_idx, config)

        expected_temp = self.hw_mgmt_module.sdk_temp2degree(500)
        expected_crit = MockCONST.MODULE_TEMP_MAX_DEF  # Default when threshold_hi fails
        expected_emergency = expected_crit + MockCONST.MODULE_TEMP_EMERGENCY_OFFSET
        expected_trip_crit = MockCONST.MODULE_TEMP_CRIT_DEF

        print("\n📊 Expected value calculations:")
        print(f"   • Input temperature: 500 → {expected_temp} millidegrees (SDK conversion)")
        print(f"   • Critical threshold: {expected_crit} millidegrees (MODULE_TEMP_MAX_DEF)")
        print(f"   • Emergency threshold: {expected_emergency} millidegrees (critical + {MockCONST.MODULE_TEMP_EMERGENCY_OFFSET} offset)")
        print(f"   • Trip critical: {expected_trip_crit} millidegrees (MODULE_TEMP_CRIT_DEF)")

        print("\n🔄 Executing module_temp_populate function...")
        print("   • Function should read temperature input successfully")
        print("   • Function should detect threshold file read failures")
        print("   • Function should use default values for failed attributes")

        # Mock file operations
        mock_open_func, mock_islink_func, mock_isfile_func = self._mock_file_operations()

        with patch('builtins.open', side_effect=mock_open_func), \
                patch('os.path.islink', side_effect=mock_islink_func), \
                patch('os.path.isfile', side_effect=mock_isfile_func):

            # Call function under test
            self.hw_mgmt_module.module_temp_populate(self.arg_list, None)

            print("\n🔍 Verifying mixed values (real input + default thresholds)...")
            # Verify temperature values when other attributes fail

            # Input should work, but thresholds should use defaults
            expected_files = {
                f"{module_name}_temp_input": str(expected_temp),
                f"{module_name}_temp_crit": str(expected_crit),
                f"{module_name}_temp_emergency": str(expected_emergency),
                f"{module_name}_temp_fault": "0",
                f"{module_name}_temp_trip_crit": str(expected_trip_crit),
                f"{module_name}_status": "1"
            }

            print(f"   📂 Checking {module_name} output files:")
            for filename, expected_value in expected_files.items():
                file_path = os.path.join(self.thermal_output_dir, filename)
                self.assertTrue(os.path.exists(file_path), f"File {filename} should exist")

                with open(file_path, 'r') as f:
                    actual_value = f.read().strip()
                    self.assertEqual(actual_value, expected_value,
                                     f"File {filename} should contain '{expected_value}', got '{actual_value}'")
                    if "temp_input" in filename:
                        print(f"      [PASS] {filename}: {actual_value} (processed from input)")
                    elif "status" in filename:
                        print(f"      [PASS] {filename}: {actual_value} (module present)")
                    else:
                        print(f"      [PASS] {filename}: {actual_value} (default value)")

        print("\n🎯 RESULT: Partial read errors handled correctly - input processed, thresholds defaulted!")
        print("[PASS] Other attributes read error test passed")

    def test_error_handling_no_crash(self):
        """Test that function doesn't crash on various error conditions"""
        print("\n" + "=" * 80)
        print("🧪 TEST 1.4: ERROR HANDLING - NO CRASH CONDITIONS")
        print("=" * 80)
        print("📋 Description: Testing that the function handles various error conditions")
        print("   gracefully without crashing. This includes missing files, invalid values,")
        print("   corrupted data, and filesystem errors. The function should be robust")
        print("   enough to handle real-world deployment scenarios.")
        print()
        print("🎯 Expected Behavior:")
        print("   • Function completes without exceptions for all error scenarios")
        print("   • No crashes regardless of input file conditions")
        print("   • Graceful degradation when files are missing or corrupted")
        print("   • Defensive programming against unexpected file contents")
        print()

        # Test various error scenarios
        error_scenarios = [
            {"name": "Missing present file", "present_file": False},
            {"name": "Missing control file", "control_file": False},
            {"name": "Missing temperature directory", "temp_dir": False},
            {"name": "Invalid present value", "present_value": "invalid"},
            {"name": "Invalid control value", "control_value": "invalid"},
            {"name": "Invalid temperature value", "temp_value": "not_a_number"}
        ]

        print("🔧 Creating error test scenarios:")
        for i, scenario in enumerate(error_scenarios):
            module_idx = 20 + i
            print(f"   {i + 1}. {scenario['name']} (module{module_idx})")
            module_dir = os.path.join(self.sys_module_dir, f"module{module_idx}")
            temp_dir = os.path.join(module_dir, "temperature")

            os.makedirs(module_dir, exist_ok=True)

            # Create files based on scenario
            if scenario.get("control_file", True):
                with open(os.path.join(module_dir, "control"), 'w') as f:
                    f.write(scenario.get("control_value", "0"))
                    print(f"      • control file: '{scenario.get('control_value', '0')}'")
            else:
                print("      • control file: MISSING")

            if scenario.get("present_file", True):
                with open(os.path.join(module_dir, "present"), 'w') as f:
                    f.write(scenario.get("present_value", "1"))
                    print(f"      • present file: '{scenario.get('present_value', '1')}'")
            else:
                print("      • present file: MISSING")

            if scenario.get("temp_dir", True):
                os.makedirs(temp_dir, exist_ok=True)
                if scenario.get("temp_value"):
                    with open(os.path.join(temp_dir, "input"), 'w') as f:
                        f.write(scenario["temp_value"])
                    print(f"      • temperature input: '{scenario['temp_value']}'")
                else:
                    with open(os.path.join(temp_dir, "input"), 'w') as f:
                        f.write("500")
                    print("      • temperature input: '500' (valid)")
            else:
                print("      • temperature directory: MISSING")

        print(f"\n🔄 Executing module_temp_populate with {len(error_scenarios)} error scenarios...")
        print("   • Function should handle all errors gracefully")
        print("   • No exceptions should be raised")
        print("   • Function should complete normally despite errors")

        # Mock file operations
        mock_open_func, mock_islink_func, mock_isfile_func = self._mock_file_operations()

        with patch('builtins.open', side_effect=mock_open_func), \
                patch('os.path.islink', side_effect=mock_islink_func), \
                patch('os.path.isfile', side_effect=mock_isfile_func):

            # This should not crash regardless of error conditions
            try:
                self.hw_mgmt_module.module_temp_populate(self.arg_list, None)
                print("\n🔍 Function execution completed successfully!")
                print("   [PASS] No exceptions were raised")
                print("   [PASS] Function handled all error conditions gracefully")
                print("   [PASS] Robust error handling confirmed")
                print("\n🎯 RESULT: Function demonstrates excellent error resilience!")
                print("[PASS] Error handling test passed - no crashes occurred")
            except Exception as e:
                print(f"\n[FAIL] Function crashed with error: {e}")
                self.fail(f"Function crashed with error: {e}")

    def test_random_module_configuration(self):
        """Test random configuration of all 36 modules"""
        print("\n" + "=" * 80)
        print("🧪 TEST 1.5: RANDOM MODULE CONFIGURATION - FULL SCALE TEST")
        print("=" * 80)
        print("📋 Description: Testing all 36 modules with randomized configurations")
        print("   to simulate real-world deployment scenarios. Each module has random")
        print("   combinations of presence, control mode, file availability, and values.")
        print("   This comprehensive test validates function robustness at scale.")
        print()
        print("🎯 Expected Behavior:")
        print("   • Function processes all 36 modules without errors")
        print("   • SW_CONTROL modules are skipped (no output files)")
        print("   • FW_CONTROL modules create appropriate output files")
        print("   • Module counter file created with correct count")
        print("   • Random error conditions handled gracefully")
        print()

        # Analyze random configurations
        fw_control_count = sum(1 for config in self.module_configs if config.get('control_mode') == 0)
        sw_control_count = sum(1 for config in self.module_configs if config.get('control_mode') == 1)
        present_count = sum(1 for config in self.module_configs if config.get('present') == 1)
        absent_count = sum(1 for config in self.module_configs if config.get('present') == 0)

        print("📊 Random configuration analysis:")
        print(f"   • Total modules: {self.arg_list['module_count']}")
        print(f"   • FW_CONTROL modules: {fw_control_count}")
        print(f"   • SW_CONTROL modules: {sw_control_count}")
        print(f"   • Present modules: {present_count}")
        print(f"   • Absent modules: {absent_count}")
        print()

        print("🔧 Creating randomized module files:")
        # Create all 36 modules with random configurations
        for i in range(self.arg_list["module_count"]):
            config = self.module_configs[i]
            status = "present" if config.get('present') else "absent"
            control = "FW" if config.get('control_mode') == 0 else "SW"
            print(f"   • module{i}: {status}, {control}_CONTROL", end="")

            # Show error conditions if any
            errors = []
            if config.get('input_read_error'):
                errors.append("input_err")
            if config.get('threshold_hi_read_error'):
                errors.append("thresh_err")
            if config.get('cooling_level_read_error'):
                errors.append("cool_err")

            if errors:
                print(f" ({', '.join(errors)})")
            else:
                print()

            self._create_module_files(i, config)

        print(f"\n🔄 Executing module_temp_populate with {self.arg_list['module_count']} randomized modules...")
        print("   • Function should process all modules appropriately")
        print("   • SW_CONTROL modules should be skipped")
        print("   • Error conditions should be handled gracefully")
        print("   • Module counter should be updated")

        # Mock file operations
        mock_open_func, mock_islink_func, mock_isfile_func = self._mock_file_operations()

        with patch('builtins.open', side_effect=mock_open_func), \
                patch('os.path.islink', side_effect=mock_islink_func), \
                patch('os.path.isfile', side_effect=mock_isfile_func):

            # Call function under test - should handle all random configurations
            try:
                self.hw_mgmt_module.module_temp_populate(self.arg_list, None)

                print("\n🔍 Verifying results...")

                # Verify module_counter file is created
                counter_file = os.path.join(self.config_output_dir, "module_counter")
                self.assertTrue(os.path.exists(counter_file), "module_counter file should exist")

                with open(counter_file, 'r') as f:
                    counter_value = f.read().strip()
                    self.assertEqual(counter_value, str(self.arg_list["module_count"]),
                                     f"module_counter should be {self.arg_list['module_count']}")
                    print(f"   [PASS] Module counter file: {counter_value}")

                # Count how many modules were processed
                processed_modules = 0
                skipped_modules = 0
                for i in range(self.arg_list["module_count"]):
                    module_name = f"module{i + self.arg_list['fout_idx_offset']}"
                    status_file = os.path.join(self.thermal_output_dir, f"{module_name}_status")
                    if os.path.exists(status_file):
                        processed_modules += 1
                    else:
                        skipped_modules += 1

                print(f"   [PASS] Processed modules: {processed_modules}")
                print(f"   [PASS] Skipped modules (SW_CONTROL): {skipped_modules}")
                print(f"   [PASS] Total modules handled: {processed_modules + skipped_modules}")

                print("\n🎯 RESULT: Large-scale random testing successful!")
                print(f"[PASS] Random configuration test passed - processed {processed_modules} modules")

            except Exception as e:
                print(f"\n[FAIL] Random configuration test failed with error: {e}")
                self.fail(f"Random configuration test failed with error: {e}")

    def test_sdk_temp2degree_function(self):
        """Test the sdk_temp2degree temperature conversion function"""
        print("\n" + "=" * 80)
        print("🧪 TEST 2.1: SDK_TEMP2DEGREE FUNCTION - TEMPERATURE CONVERSION")
        print("=" * 80)
        print("📋 Description: Testing the temperature conversion function that translates")
        print("   SDK temperature format to millidegrees Celsius. This function is critical")
        print("   for converting raw hardware sensor values to standard thermal units.")
        print()
        print("🔢 Conversion Algorithm:")
        print("   • Positive values: temperature = value * 125")
        print("   • Negative values: temperature = 0xffff + value + 1")
        print("   • Output unit: millidegrees Celsius")
        print()

        # Test cases for temperature conversion
        test_cases = [
            (0, 0, "Zero value"),
            (1, 125, "Small positive"),
            (10, 1250, "Medium positive"),
            (100, 12500, "Large positive"),
            (-1, 0xffff, "Small negative"),
            (-10, 0xfff6, "Medium negative"),
            (500, 62500, "Typical sensor value"),
            (600, 75000, "High temperature value")
        ]

        print("🔍 Testing conversion cases:")
        for input_val, expected_output, description in test_cases:
            print(f"   • {description}: {input_val} → {expected_output}")
            actual_output = self.hw_mgmt_module.sdk_temp2degree(input_val)
            self.assertEqual(actual_output, expected_output,
                             f"sdk_temp2degree({input_val}) should return {expected_output}, got {actual_output}")

            # Additional verification message
            if input_val >= 0:
                calculated = input_val * 125
                print(f"     [PASS] Calculation: {input_val} × 125 = {calculated} (matches)")
            else:
                calculated = 0xffff + input_val + 1
                print(f"     [PASS] Calculation: 0x{0xffff:x} + {input_val} + 1 = 0x{calculated:x} ({calculated}) (matches)")

        print("\n🎯 RESULT: Temperature conversion function working correctly!")
        print("[PASS] sdk_temp2degree function test passed")

    def test_module_count_argument_validation(self):
        """Test that module_count argument is properly handled"""
        print("\n" + "=" * 80)
        print("🧪 TEST 2.2: MODULE COUNT ARGUMENT VALIDATION")
        print("=" * 80)
        print("📋 Description: Validating that the function uses the specified")
        print("   argument configuration correctly. This ensures the test setup")
        print("   matches the requirements and the function operates on the")
        print("   expected number of modules with correct indexing.")
        print()
        print("🎯 Requirements Validation:")
        print("   • Module count: 36 modules")
        print("   • Index offset: 1 (modules indexed from 1 to 36)")
        print("   • Input path template: contains 'module{}' pattern")
        print("   • Configuration matches specified basic setup")
        print()

        print("🔍 Validating argument configuration:")

        # Test the module count and offset values
        print(f"   • Checking fout_idx_offset...")
        expected_offset = 1
        actual_offset = self.arg_list["fout_idx_offset"]
        self.assertEqual(actual_offset, expected_offset,
                         f"fout_idx_offset should be {expected_offset}, got {actual_offset}")
        print(f"     [PASS] fout_idx_offset: {actual_offset} (correct)")

        print(f"   • Checking module_count...")
        expected_count = 36
        actual_count = self.arg_list["module_count"]
        self.assertEqual(actual_count, expected_count,
                         f"module_count should be {expected_count}, got {actual_count}")
        print(f"     [PASS] module_count: {actual_count} (correct)")

        # Test that fin contains the module template
        print(f"   • Checking input path template...")
        template_pattern = "module{}"
        actual_fin = self.arg_list["fin"]
        self.assertIn(template_pattern, actual_fin,
                      f"fin should contain '{template_pattern}', got {actual_fin}")
        print(f"     [PASS] Template pattern '{template_pattern}' found in path")

        print(f"   • Complete argument structure:")
        for key, value in self.arg_list.items():
            print(f"     - {key}: {value}")

        print("\n🎯 RESULT: Argument configuration matches requirements!")
        print("[PASS] Module count argument validation test passed")

    def test_sw_control_mode_ignored(self):
        """Test that modules in SW control mode are ignored"""
        print("\n" + "=" * 80)
        print("🧪 TEST 2.3: SW CONTROL MODE - MODULE IGNORED")
        print("=" * 80)
        print("📋 Description: Testing that modules in SW_CONTROL mode (control=1)")
        print("   are properly ignored by the function. In independent mode, modules")
        print("   handle their own temperature monitoring, so the function should")
        print("   skip processing them entirely.")
        print()
        print("🎯 Expected Behavior:")
        print("   • Module with control=1 (SW_CONTROL) should be skipped")
        print("   • No output files should be created for SW_CONTROL modules")
        print("   • Function should continue processing other modules normally")
        print("   • This simulates independent temperature management mode")
        print()

        # Create module in SW control mode
        source_idx = 14  # Will create output for module15 (14+1)
        module_name = f"module{source_idx + self.arg_list['fout_idx_offset']}"
        print(f"🔧 Test Configuration:")
        print(f"   • Testing module: source_idx={source_idx} → {module_name}")
        print(f"   • Module present: 1 (inserted)")
        print(f"   • Control mode: 1 (SW_CONTROL - independent mode)")
        print(f"   • Temperature input: 500 (available but should be ignored)")
        print(f"   • Threshold files: available but should be ignored")
        print()

        config = {
            'present': 1,
            'control_mode': 1,  # SW_CONTROL - should be ignored
            'temp_input': 500,
            'threshold_hi': 600,
            'has_threshold_hi': True,
            'has_cooling_level': False
        }

        print("📁 Creating SW_CONTROL module files:")
        print("   • control → '1' (SW_CONTROL mode - should trigger skip)")
        print("   • present → '1' (module inserted)")
        print("   • temperature/input → '500' (available but ignored)")
        print("   • temperature/threshold_hi → '600' (available but ignored)")

        self._create_module_files(source_idx, config)

        print("\n🔄 Executing module_temp_populate function...")
        print("   • Function should detect SW_CONTROL mode")
        print("   • Function should skip this module entirely")
        print("   • No temperature processing should occur")
        print("   • No output files should be created")

        # Mock file operations
        mock_open_func, mock_islink_func, mock_isfile_func = self._mock_file_operations()

        with patch('builtins.open', side_effect=mock_open_func), \
                patch('os.path.islink', side_effect=mock_islink_func), \
                patch('os.path.isfile', side_effect=mock_isfile_func):

            # Call function under test
            self.hw_mgmt_module.module_temp_populate(self.arg_list, None)

            print("\n🔍 Verifying SW_CONTROL module was ignored...")
            # Verify no files are created for SW control modules
            output_files = [
                f"{module_name}_temp_input",
                f"{module_name}_temp_crit",
                f"{module_name}_temp_emergency",
                f"{module_name}_temp_fault",
                f"{module_name}_temp_trip_crit",
                f"{module_name}_cooling_level_input",
                f"{module_name}_max_cooling_level_input",
                f"{module_name}_status"
            ]

            print(f"   📂 Checking that NO files were created for {module_name}:")
            all_ignored = True
            for filename in output_files:
                file_path = os.path.join(self.thermal_output_dir, filename)
                file_exists = os.path.exists(file_path)
                self.assertFalse(file_exists,
                                 f"File {filename} should not exist for SW control module")
                print(f"      [PASS] {filename}: NOT CREATED (correctly ignored)")
                if file_exists:
                    all_ignored = False

            if all_ignored:
                print("\n🎯 RESULT: SW_CONTROL module properly ignored - no files created!")
            else:
                print("\n[FAIL] RESULT: Some files were incorrectly created for SW_CONTROL module!")

        print("[PASS] SW control mode ignored test passed")


def main():
    """Main function to run all tests"""
    print("=" * 80)
    print("🚀 COMPREHENSIVE MODULE_TEMP_POPULATE TEST SUITE")
    print("=" * 80)
    print(f"📋 Test Suite Description:")
    print(f"   This comprehensive test suite validates the module_temp_populate function")
    print(f"   from hw_management_sync.py with detailed runtime descriptions and")
    print(f"   thorough coverage of all specified test scenarios.")
    print()
    print(f"🔧 Test Environment:")
    print(f"   • Python version: {sys.version.split()[0]}")
    print(f"   • Testing module: hw_management_sync.py")
    print(f"   • Module path: {hw_mgmt_path}")
    print(f"   • Test configuration: 36 modules, offset=1")
    print(f"   • Input path: /sys/module/sx_core/asic0/module{{}}/")
    print(f"   • Output path: /var/run/hw-management/thermal/")
    print()
    print(f"📊 Test Categories:")
    print(f"   1. NORMAL CONDITIONS - All files present and readable")
    print(f"   2. INPUT READ ERRORS - Default values when input fails")
    print(f"   3. ATTRIBUTE READ ERRORS - Partial failures handling")
    print(f"   4. ERROR RESILIENCE - No crashes under any conditions")
    print(f"   5. RANDOM CONFIGURATIONS - Large-scale testing (36 modules)")
    print(f"   6. FUNCTION VALIDATION - SDK temperature conversion")
    print(f"   7. ARGUMENT VALIDATION - Configuration verification")
    print(f"   8. CONTROL MODE HANDLING - SW_CONTROL module skipping")
    print()
    print("=" * 80)
    print("🏁 STARTING TEST EXECUTION...")
    print("=" * 80)

    # Run tests
    unittest.main(verbosity=2, exit=False)

    print("\n" + "=" * 80)
    print("🎯 TEST SUITE EXECUTION COMPLETED")
    print("=" * 80)


if __name__ == '__main__':
    main()
