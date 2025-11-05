#!/usr/bin/env python3
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
Unit tests for hw_management_thermal_control.py changes

This test suite provides comprehensive testing for recent changes:
- get_file_mtime() method
- _module_get_data_from_file() method for parsing EEPROM data
- _module_get_custom_config() method for custom module configuration
- refresh_attr() method with dynamic configuration support
- _sensor_add_config() method with dev_tune support

Usage:
    # Run from tests directory
    cd tests
    python3 -m pytest offline/test_hw_management_thermal_control_changes.py -v

    # Or run from offline directory
    cd tests/offline
    python3 -m pytest test_hw_management_thermal_control_changes.py -v

    # Run specific test class
    python3 -m pytest test_hw_management_thermal_control_changes.py::TestGetFileMtime -v
"""

import sys
import os
import pytest
import tempfile
import shutil
import time
import re
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch, mock_open
from typing import Dict, Any

# Add parent directory to path to import the module under test
TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"

if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

# Mark all tests in this file as offline tests
pytestmark = pytest.mark.offline

# Status indicators
ICON_PASS = "[+]"
ICON_FAIL = "[X]"
ICON_INFO = "[i]"


class TestGetFileMtime:
    """Test suite for get_file_mtime() method"""

    def setup_method(self):
        """Setup test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.mock_logger = Mock()
        self.mock_logger.info = Mock()
        self.mock_logger.debug = Mock()
        self.mock_logger.error = Mock()
        self.mock_logger.notice = Mock()
        self.mock_logger.warn = Mock()

    def teardown_method(self):
        """Cleanup test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_get_file_mtime_existing_file(self):
        """Test get_file_mtime() with existing file"""
        print(f"\n{ICON_INFO} Testing get_file_mtime with existing file...")

        # Import the module
        import hw_management_thermal_control as tc

        # Create a config dict for hw_management_file_op
        config = {
            tc.CONST.HW_MGMT_ROOT: self.test_dir
        }

        file_op = tc.hw_management_file_op(config)

        # Create a test file
        test_file = "test_file.txt"
        full_path = os.path.join(self.test_dir, test_file)
        with open(full_path, 'w') as f:
            f.write("test content")

        # Get the modification time
        mtime = file_op.get_file_mtime(test_file)

        # Verify the modification time is returned
        assert mtime > 0, "Modification time should be greater than 0"
        assert isinstance(mtime, float), "Modification time should be a float"

        # Verify it matches os.path.getmtime
        expected_mtime = os.path.getmtime(full_path)
        assert mtime == expected_mtime, f"Expected mtime {expected_mtime}, got {mtime}"

        print(f"{ICON_PASS} Test passed: get_file_mtime returns correct modification time")

    def test_get_file_mtime_non_existing_file(self):
        """Test get_file_mtime() with non-existing file"""
        print(f"\n{ICON_INFO} Testing get_file_mtime with non-existing file...")

        # Import the module
        import hw_management_thermal_control as tc

        # Create a config dict for hw_management_file_op
        config = {
            tc.CONST.HW_MGMT_ROOT: self.test_dir
        }

        file_op = tc.hw_management_file_op(config)

        # Get the modification time for a non-existing file
        mtime = file_op.get_file_mtime("non_existing_file.txt")

        # Verify that 0 is returned for non-existing files
        assert mtime == 0, "Modification time should be 0 for non-existing files"

        print(f"{ICON_PASS} Test passed: get_file_mtime returns 0 for non-existing file")

    def test_get_file_mtime_file_update(self):
        """Test get_file_mtime() detects file updates"""
        print(f"\n{ICON_INFO} Testing get_file_mtime detects file updates...")

        # Import the module
        import hw_management_thermal_control as tc

        # Create a config dict for hw_management_file_op
        config = {
            tc.CONST.HW_MGMT_ROOT: self.test_dir
        }

        file_op = tc.hw_management_file_op(config)

        # Create a test file
        test_file = "test_file.txt"
        full_path = os.path.join(self.test_dir, test_file)
        with open(full_path, 'w') as f:
            f.write("initial content")

        # Get the first modification time
        mtime1 = file_op.get_file_mtime(test_file)

        # Sleep to ensure different timestamp
        time.sleep(0.1)

        # Update the file
        with open(full_path, 'w') as f:
            f.write("updated content")

        # Get the second modification time
        mtime2 = file_op.get_file_mtime(test_file)

        # Verify that modification time has changed
        assert mtime2 > mtime1, f"Expected mtime2 ({mtime2}) > mtime1 ({mtime1})"

        print(f"{ICON_PASS} Test passed: get_file_mtime detects file updates")


class TestModuleGetDataFromFile:
    """Test suite for _module_get_data_from_file() method"""

    def setup_method(self):
        """Setup test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.mock_logger = Mock()
        self.mock_logger.info = Mock()
        self.mock_logger.debug = Mock()
        self.mock_logger.error = Mock()
        self.mock_logger.notice = Mock()
        self.mock_logger.warn = Mock()

    def teardown_method(self):
        """Cleanup test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _create_thermal_module_sensor(self, sensor_name="module1"):
        """Helper to create a thermal_module_sensor instance"""
        import hw_management_thermal_control as tc

        # Create minimal system config
        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: {
                sensor_name: {
                    "type": "thermal_module_sensor",
                    "name": sensor_name,
                    "base_file_name": sensor_name,
                    "pwm_min": 20,
                    "pwm_max": 100,
                }
            },
            tc.CONST.SYS_CONF_DEV_PARAM: {},
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
        }

        cmd_arg = {
            tc.CONST.HW_MGMT_ROOT: self.test_dir
        }

        # Create necessary directories and files
        os.makedirs(os.path.join(self.test_dir, "thermal"), exist_ok=True)
        os.makedirs(os.path.join(self.test_dir, "eeprom"), exist_ok=True)

        # Create required thermal files
        with open(os.path.join(self.test_dir, f"{sensor_name}_scale"), 'w') as f:
            f.write("1000")

        # Mock read_val_min_max to avoid file dependencies
        with patch.object(tc.thermal_module_sensor, 'read_val_min_max', return_value=0):
            sensor = tc.thermal_module_sensor(cmd_arg, sys_config, sensor_name, self.mock_logger)

        return sensor

    def test_module_get_data_from_file_valid_eeprom(self):
        """Test _module_get_data_from_file() with valid EEPROM data"""
        print(f"\n{ICON_INFO} Testing _module_get_data_from_file with valid EEPROM data...")

        sensor = self._create_thermal_module_sensor()

        # Create EEPROM data file
        eeprom_file = os.path.join(self.test_dir, "eeprom", f"{sensor.base_file_name}_data")
        eeprom_content = """Manufacturer:            Mellanox
PN:                      MCP1600-C003
SN:                      MT1234567890
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # Call the method
        data, changed = sensor._module_get_data_from_file()

        # Verify results
        assert changed is True, "change_flag should be True on first read"
        assert "Manufacturer" in data, "Data should contain 'Manufacturer' key"
        assert "PN" in data, "Data should contain 'PN' key"
        assert "SN" in data, "Data should contain 'SN' key"
        assert data["Manufacturer"] == "Mellanox", f"Expected 'Mellanox', got '{data['Manufacturer']}'"
        assert data["PN"] == "MCP1600-C003", f"Expected 'MCP1600-C003', got '{data['PN']}'"
        assert data["SN"] == "MT1234567890", f"Expected 'MT1234567890', got '{data['SN']}'"

        print(f"{ICON_PASS} Test passed: _module_get_data_from_file parses valid EEPROM data")

    def test_module_get_data_from_file_no_change(self):
        """Test _module_get_data_from_file() returns no change when file hasn't changed"""
        print(f"\n{ICON_INFO} Testing _module_get_data_from_file with unchanged file...")

        sensor = self._create_thermal_module_sensor()

        # Create EEPROM data file
        eeprom_file = os.path.join(self.test_dir, "eeprom", f"{sensor.base_file_name}_data")
        eeprom_content = """Manufacturer:            Mellanox
PN:                      MCP1600-C003
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # First call - should return change_flag=True
        data1, changed1 = sensor._module_get_data_from_file()
        assert changed1 is True, "First call should have change_flag=True"

        # Second call without file modification - should return change_flag=False
        data2, changed2 = sensor._module_get_data_from_file()
        assert changed2 is False, "Second call without file change should have change_flag=False"
        assert data2 == {}, "Data should be empty when no change detected"

        print(f"{ICON_PASS} Test passed: _module_get_data_from_file detects no change")

    def test_module_get_data_from_file_file_updated(self):
        """Test _module_get_data_from_file() detects file updates"""
        print(f"\n{ICON_INFO} Testing _module_get_data_from_file detects file updates...")

        sensor = self._create_thermal_module_sensor()

        # Create EEPROM data file
        eeprom_file = os.path.join(self.test_dir, "eeprom", f"{sensor.base_file_name}_data")
        eeprom_content = """Manufacturer:            Mellanox
PN:                      MCP1600-C003
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # First call
        data1, changed1 = sensor._module_get_data_from_file()
        assert changed1 is True

        # Sleep to ensure different timestamp
        time.sleep(0.1)

        # Update the file
        updated_content = """Manufacturer:            NVIDIA
PN:                      MCP1600-C004
"""
        with open(eeprom_file, 'w') as f:
            f.write(updated_content)

        # Second call - should detect change
        data2, changed2 = sensor._module_get_data_from_file()
        assert changed2 is True, "Should detect file change"
        assert data2["Manufacturer"] == "NVIDIA", "Should read updated data"
        assert data2["PN"] == "MCP1600-C004", "Should read updated data"

        print(f"{ICON_PASS} Test passed: _module_get_data_from_file detects file updates")

    def test_module_get_data_from_file_missing_file(self):
        """Test _module_get_data_from_file() with missing EEPROM file"""
        print(f"\n{ICON_INFO} Testing _module_get_data_from_file with missing file...")

        sensor = self._create_thermal_module_sensor()

        # Don't create EEPROM file
        data, changed = sensor._module_get_data_from_file()

        # Verify results - When file doesn't exist initially, timestamp is None then changes to 0
        # So change_flag is True on first call
        assert changed is True, "change_flag should be True on first call even when file doesn't exist"
        assert data == {}, "Data should be empty when file doesn't exist"

        # Second call should return False since timestamp hasn't changed (both 0)
        data2, changed2 = sensor._module_get_data_from_file()
        assert changed2 is False, "change_flag should be False on second call when file still doesn't exist"
        assert data2 == {}, "Data should be empty when file doesn't exist"

        print(f"{ICON_PASS} Test passed: _module_get_data_from_file handles missing file")

    def test_module_get_data_from_file_malformed_lines(self):
        """Test _module_get_data_from_file() with malformed EEPROM data"""
        print(f"\n{ICON_INFO} Testing _module_get_data_from_file with malformed data...")

        sensor = self._create_thermal_module_sensor()

        # Create EEPROM data file with malformed lines
        eeprom_file = os.path.join(self.test_dir, "eeprom", f"{sensor.base_file_name}_data")
        eeprom_content = """Manufacturer:            Mellanox
InvalidLine
PN:                      MCP1600-C003
: NoKey
EmptyValue:
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # Call the method
        data, changed = sensor._module_get_data_from_file()

        # Verify results - should only parse valid lines
        assert changed is True
        assert "Manufacturer" in data
        assert "PN" in data
        assert "InvalidLine" not in data, "Should skip lines without ':'"
        assert "" not in data, "Should skip empty keys"

        print(f"{ICON_PASS} Test passed: _module_get_data_from_file handles malformed data")

    def test_module_get_data_from_file_empty_file(self):
        """Test _module_get_data_from_file() with empty EEPROM file"""
        print(f"\n{ICON_INFO} Testing _module_get_data_from_file with empty file...")

        sensor = self._create_thermal_module_sensor()

        # Create empty EEPROM data file
        eeprom_file = os.path.join(self.test_dir, "eeprom", f"{sensor.base_file_name}_data")
        with open(eeprom_file, 'w') as f:
            f.write("")

        # Call the method
        data, changed = sensor._module_get_data_from_file()

        # Verify results
        assert changed is True, "change_flag should be True on first read"
        assert data == {}, "Data should be empty for empty file"

        print(f"{ICON_PASS} Test passed: _module_get_data_from_file handles empty file")


class TestModuleGetCustomConfig:
    """Test suite for _module_get_custom_config() method"""

    def setup_method(self):
        """Setup test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.mock_logger = Mock()
        self.mock_logger.info = Mock()
        self.mock_logger.debug = Mock()
        self.mock_logger.error = Mock()
        self.mock_logger.notice = Mock()
        self.mock_logger.warn = Mock()

    def teardown_method(self):
        """Cleanup test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _create_thermal_module_sensor_with_extra_config(self, extra_config):
        """Helper to create a thermal_module_sensor instance with extra_config"""
        import hw_management_thermal_control as tc

        # Create minimal system config
        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: {
                "module1": {
                    "type": "thermal_module_sensor",
                    "name": "module1",
                    "base_file_name": "module1",
                    "pwm_min": 20,
                    "pwm_max": 100,
                    tc.CONST.DEV_CONF_EXTRA_PARAM: extra_config,
                }
            },
            tc.CONST.SYS_CONF_DEV_PARAM: {},
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
        }

        cmd_arg = {
            tc.CONST.HW_MGMT_ROOT: self.test_dir
        }

        # Create necessary directories and files
        os.makedirs(os.path.join(self.test_dir, "thermal"), exist_ok=True)

        # Create required thermal files
        with open(os.path.join(self.test_dir, "module1_scale"), 'w') as f:
            f.write("1000")

        # Mock read_val_min_max to avoid file dependencies
        with patch.object(tc.thermal_module_sensor, 'read_val_min_max', return_value=0):
            sensor = tc.thermal_module_sensor(cmd_arg, sys_config, "module1", self.mock_logger)

        return sensor

    def test_module_get_custom_config_exact_match(self):
        """Test _module_get_custom_config() with exact match"""
        print(f"\n{ICON_INFO} Testing _module_get_custom_config with exact match...")

        # New format uses manufacturer:pn instead of manufacturer_pn_pn
        # For exact match, we need to escape regex special chars in the pattern
        extra_config = {
            r"Mellanox:MCP1600\-C003": {  # Escape the hyphen for literal match
                "pwm_min": 30,
                "pwm_max": 90,
                "val_min_offset": -5,
                "val_max_offset": 5,
            }
        }

        sensor = self._create_thermal_module_sensor_with_extra_config(extra_config)

        # Test exact match
        config = sensor._module_get_custom_config("Mellanox", "MCP1600-C003")

        assert config is not None, "Should return config for exact match"
        assert config["pwm_min"] == 30, f"Expected pwm_min=30, got {config['pwm_min']}"
        assert config["pwm_max"] == 90, f"Expected pwm_max=90, got {config['pwm_max']}"
        assert config["val_min_offset"] == -5
        assert config["val_max_offset"] == 5

        print(f"{ICON_PASS} Test passed: _module_get_custom_config exact match")

    def test_module_get_custom_config_regex_match(self):
        """Test _module_get_custom_config() with regex pattern match"""
        print(f"\n{ICON_INFO} Testing _module_get_custom_config with regex match...")

        # Use regex pattern that matches the new format
        extra_config = {
            r"Mellanox:MCP1600\-.*": {  # Matches Mellanox:MCP1600-C003, Mellanox:MCP1600-C004, etc.
                "pwm_min": 25,
                "pwm_max": 95,
            }
        }

        sensor = self._create_thermal_module_sensor_with_extra_config(extra_config)

        # Test regex match
        config = sensor._module_get_custom_config("Mellanox", "MCP1600-C003")

        assert config is not None, "Should return config for regex match"
        assert config["pwm_min"] == 25, f"Expected pwm_min=25, got {config['pwm_min']}"

        print(f"{ICON_PASS} Test passed: _module_get_custom_config regex match")

    def test_module_get_custom_config_no_match(self):
        """Test _module_get_custom_config() with no match"""
        print(f"\n{ICON_INFO} Testing _module_get_custom_config with no match...")

        extra_config = {
            "Mellanox_pn_MCP1600-C003": {
                "pwm_min": 30,
            }
        }

        sensor = self._create_thermal_module_sensor_with_extra_config(extra_config)

        # Test no match
        config = sensor._module_get_custom_config("NVIDIA", "MCP1600-C004")

        assert config is None, "Should return None when no match found"

        print(f"{ICON_PASS} Test passed: _module_get_custom_config no match")

    def test_module_get_custom_config_regex_injection_prevention(self):
        """Test _module_get_custom_config() prevents regex injection"""
        print(f"\n{ICON_INFO} Testing _module_get_custom_config prevents regex injection...")

        # NOTE: With the updated implementation, re.escape() was removed because
        # manufacturer/PN are used in the match_string (the target string being tested),
        # not as the regex pattern itself. Special characters in the target string
        # are treated as literal characters, so there's no regex injection risk.

        # Create a sensor with a pattern that uses regex (controlled by system, not user input)
        extra_config = {
            r"Mellanox:MCP\-.*": {  # Pattern to match any MCP- variants
                "pwm_min": 30,
            }
        }

        sensor = self._create_thermal_module_sensor_with_extra_config(extra_config)

        # Normal case: PN "MCP-1234" should match the pattern
        config1 = sensor._module_get_custom_config("Mellanox", "MCP-1234")
        assert config1 is not None, "Should match MCP-1234"

        # Test: If a user somehow provides a PN with regex characters like ".*"
        # Since match_string is the target (not the pattern), special chars are treated literally
        # So ".*" in the PN won't act as a wildcard - it's just two literal characters
        extra_config2 = {
            r"Mellanox:MCP": {  # Exact prefix match
                "pwm_min": 40,
            }
        }
        sensor2 = self._create_thermal_module_sensor_with_extra_config(extra_config2)

        # PN with ".*" - treated as literal string ".*", not regex wildcard
        config2 = sensor2._module_get_custom_config("Mellanox", ".*")
        # This won't match "MCP" pattern because the match_string is literally "Mellanox:.*"
        assert config2 is None, "Literal '.*' doesn't match 'MCP' pattern"

        print(f"{ICON_PASS} Test passed: _module_get_custom_config prevents regex injection")

    def test_module_get_custom_config_invalid_regex(self):
        """Test _module_get_custom_config() handles invalid regex patterns"""
        print(f"\n{ICON_INFO} Testing _module_get_custom_config handles invalid regex...")

        extra_config = {
            "[invalid(regex": {
                "pwm_min": 30,
            },
            "valid_pattern": {
                "pwm_min": 40,
            }
        }

        sensor = self._create_thermal_module_sensor_with_extra_config(extra_config)

        # Test with invalid regex - should log notice and continue
        config = sensor._module_get_custom_config("valid", "pattern")

        # Should continue past invalid regex and not find match
        assert config is None, "Should handle invalid regex gracefully"

        # Verify notice was logged
        self.mock_logger.notice.assert_called()

        print(f"{ICON_PASS} Test passed: _module_get_custom_config handles invalid regex")

    def test_module_get_custom_config_empty_extra_config(self):
        """Test _module_get_custom_config() with empty extra_config"""
        print(f"\n{ICON_INFO} Testing _module_get_custom_config with empty extra_config...")

        sensor = self._create_thermal_module_sensor_with_extra_config({})

        config = sensor._module_get_custom_config("Mellanox", "MCP1600-C003")

        assert config is None, "Should return None when extra_config is empty"

        print(f"{ICON_PASS} Test passed: _module_get_custom_config handles empty extra_config")


class TestRefreshAttr:
    """Test suite for refresh_attr() method with dynamic configuration"""

    def setup_method(self):
        """Setup test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.mock_logger = Mock()
        self.mock_logger.info = Mock()
        self.mock_logger.debug = Mock()
        self.mock_logger.error = Mock()
        self.mock_logger.notice = Mock()
        self.mock_logger.warn = Mock()

    def teardown_method(self):
        """Cleanup test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _create_thermal_module_sensor_for_refresh(self, extra_config=None):
        """Helper to create a thermal_module_sensor instance for refresh_attr tests"""
        import hw_management_thermal_control as tc

        sensors_config = {
            "module1": {
                "type": "thermal_module_sensor",
                "name": "module1",
                "base_file_name": "module1",
                "pwm_min": 20,
                "pwm_max": 100,
                "val_min_offset": 0,
                "val_max_offset": 0,
            }
        }

        if extra_config:
            sensors_config["module1"][tc.CONST.DEV_CONF_EXTRA_PARAM] = extra_config

        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: sensors_config,
            tc.CONST.SYS_CONF_DEV_PARAM: {},
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
        }

        cmd_arg = {
            tc.CONST.HW_MGMT_ROOT: self.test_dir
        }

        # Create necessary directories
        os.makedirs(os.path.join(self.test_dir, "thermal"), exist_ok=True)
        os.makedirs(os.path.join(self.test_dir, "eeprom"), exist_ok=True)

        # Create required thermal files
        with open(os.path.join(self.test_dir, "module1_scale"), 'w') as f:
            f.write("1000")

        # Create thermal crit file
        thermal_crit_file = os.path.join(self.test_dir, "thermal", "module1_temp_crit")
        with open(thermal_crit_file, 'w') as f:
            f.write("85000")  # 85 degrees Celsius

        # Mock read_val_min_max to avoid file dependencies
        with patch.object(tc.thermal_module_sensor, 'read_val_min_max', return_value=0):
            sensor = tc.thermal_module_sensor(cmd_arg, sys_config, "module1", self.mock_logger)

        return sensor

    def test_refresh_attr_without_extra_config(self):
        """Test refresh_attr() without extra_config"""
        print(f"\n{ICON_INFO} Testing refresh_attr without extra_config...")

        sensor = self._create_thermal_module_sensor_for_refresh()

        # Call refresh_attr
        sensor.refresh_attr()

        # Verify default values are maintained
        assert sensor.pwm_min == 20, f"Expected pwm_min=20, got {sensor.pwm_min}"
        assert sensor.pwm_max == 100, f"Expected pwm_max=100, got {sensor.pwm_max}"

        print(f"{ICON_PASS} Test passed: refresh_attr without extra_config")

    def test_refresh_attr_with_custom_config(self):
        """Test refresh_attr() with custom config from EEPROM"""
        print(f"\n{ICON_INFO} Testing refresh_attr with custom config...")

        extra_config = {
            r"Mellanox:MCP1600\-C003": {  # Need to escape the hyphen for regex
                "pwm_min": 30,
                "pwm_max": 90,
                "val_min_offset": -5000,
                "val_max_offset": 5000,
            }
        }

        sensor = self._create_thermal_module_sensor_for_refresh(extra_config)

        # Initial values should be defaults
        assert sensor.pwm_min == 20, f"Initial pwm_min should be 20, got {sensor.pwm_min}"

        # Create EEPROM data file
        eeprom_file = os.path.join(self.test_dir, "eeprom", "module1_data")
        eeprom_content = """Manufacturer:            Mellanox
PN:                      MCP1600-C003
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # Call refresh_attr - this should detect EEPROM change and apply custom config
        sensor.refresh_attr()

        # Verify custom config is applied
        assert sensor.pwm_min == 30, f"Expected pwm_min=30, got {sensor.pwm_min}"
        assert sensor.pwm_max == 90, f"Expected pwm_max=90, got {sensor.pwm_max}"
        assert sensor.val_min_offset == -5000, f"Expected val_min_offset=-5000, got {sensor.val_min_offset}"
        assert sensor.val_max_offset == 5000, f"Expected val_max_offset=5000, got {sensor.val_max_offset}"

        print(f"{ICON_PASS} Test passed: refresh_attr with custom config")

    def test_refresh_attr_case_insensitive_eeprom(self):
        """Test refresh_attr() with case-insensitive EEPROM key matching"""
        print(f"\n{ICON_INFO} Testing refresh_attr with case-insensitive EEPROM keys...")

        extra_config = {
            r"Mellanox:MCP1600\-C003": {  # Need to escape the hyphen for regex
                "pwm_min": 35,
            }
        }

        sensor = self._create_thermal_module_sensor_for_refresh(extra_config)

        # Create EEPROM data file with different cases
        eeprom_file = os.path.join(self.test_dir, "eeprom", "module1_data")
        eeprom_content = """MANUFACTURER:            Mellanox
pn:                      MCP1600-C003
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # Call refresh_attr
        sensor.refresh_attr()

        # Verify case-insensitive matching works
        assert sensor.pwm_min == 35, f"Expected pwm_min=35, got {sensor.pwm_min}"

        print(f"{ICON_PASS} Test passed: refresh_attr with case-insensitive keys")

    def test_refresh_attr_missing_eeprom_keys(self):
        """Test refresh_attr() with missing EEPROM keys"""
        print(f"\n{ICON_INFO} Testing refresh_attr with missing EEPROM keys...")

        extra_config = {
            "Mellanox_pn_MCP1600-C003": {
                "pwm_min": 35,
            }
        }

        sensor = self._create_thermal_module_sensor_for_refresh(extra_config)

        # Create EEPROM data file without PN
        eeprom_file = os.path.join(self.test_dir, "eeprom", "module1_data")
        eeprom_content = """Manufacturer:            Mellanox
SN:                      MT1234567890
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # Call refresh_attr
        sensor.refresh_attr()

        # Verify default values are used when keys are missing
        assert sensor.pwm_min == 20, f"Expected pwm_min=20 (default), got {sensor.pwm_min}"

        # Verify debug logs were called
        assert self.mock_logger.debug.called, "Should log debug message for missing keys"

        print(f"{ICON_PASS} Test passed: refresh_attr with missing EEPROM keys")

    def test_refresh_attr_no_custom_config_found(self):
        """Test refresh_attr() when no custom config matches"""
        print(f"\n{ICON_INFO} Testing refresh_attr when no custom config matches...")

        extra_config = {
            "Mellanox_pn_MCP1600-C003": {
                "pwm_min": 35,
            }
        }

        sensor = self._create_thermal_module_sensor_for_refresh(extra_config)

        # Create EEPROM data file that won't match
        eeprom_file = os.path.join(self.test_dir, "eeprom", "module1_data")
        eeprom_content = """Manufacturer:            NVIDIA
PN:                      MCP1600-C999
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # Call refresh_attr
        sensor.refresh_attr()

        # Verify default values from sensors_config are restored
        assert sensor.pwm_min == 20, f"Expected pwm_min=20 (default), got {sensor.pwm_min}"
        assert sensor.pwm_max == 100, f"Expected pwm_max=100 (default), got {sensor.pwm_max}"

        print(f"{ICON_PASS} Test passed: refresh_attr when no custom config matches")

    def test_refresh_attr_val_min_max_calculation(self):
        """Test refresh_attr() calculates val_min and val_max correctly"""
        print(f"\n{ICON_INFO} Testing refresh_attr val_min/val_max calculation...")

        extra_config = {
            r"Mellanox:MCP1600\-C003": {
                "val_min_offset": -10000,  # -10 degrees
                "val_max_offset": 5000,    # +5 degrees
            }
        }

        sensor = self._create_thermal_module_sensor_for_refresh(extra_config)

        # Create EEPROM data file
        eeprom_file = os.path.join(self.test_dir, "eeprom", "module1_data")
        eeprom_content = """Manufacturer:            Mellanox
PN:                      MCP1600-C003
"""
        with open(eeprom_file, 'w') as f:
            f.write(eeprom_content)

        # Call refresh_attr
        sensor.refresh_attr()

        # Verify calculations
        # scale = 1000 / 1000 = 1.0
        # val_max from file = 85000 (from thermal/module1_temp_crit), scaled = 85000.0
        # val_max = 85000.0 + 5000/1.0 = 90000.0
        # val_min = 90000.0 + (-10000/1.0) = 80000.0
        expected_val_max = 85000.0 + 5000.0
        expected_val_min = expected_val_max - 10000.0

        assert sensor.val_max == expected_val_max, f"Expected val_max={expected_val_max}, got {sensor.val_max}"
        assert sensor.val_min == expected_val_min, f"Expected val_min={expected_val_min}, got {sensor.val_min}"

        print(f"{ICON_PASS} Test passed: refresh_attr val_min/val_max calculation")


class TestSensorAddConfig:
    """Test suite for _sensor_add_config() method with dev_tune support"""

    def setup_method(self):
        """Setup test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.mock_logger = Mock()
        self.mock_logger.info = Mock()
        self.mock_logger.debug = Mock()
        self.mock_logger.error = Mock()
        self.mock_logger.notice = Mock()
        self.mock_logger.warn = Mock()

    def teardown_method(self):
        """Cleanup test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _create_thermal_management(self, sys_config=None):
        """Helper to create a ThermalManagement instance"""
        import hw_management_thermal_control as tc

        if sys_config is None:
            sys_config = {
                tc.CONST.SYS_CONF_SENSORS_CONF: {},
                tc.CONST.SYS_CONF_DEV_PARAM: {},
                tc.CONST.SYS_CONF_ASIC_PARAM: {
                    "1": {"pwm_control": False, "fan_control": False}
                },
            }

        cmd_arg = Mock()
        cmd_arg.log_file = None
        cmd_arg.use_syslog = False
        cmd_arg.root_folder = self.test_dir
        cmd_arg.json_config_file = None

        # Create a minimal ThermalManagement instance
        # We'll need to mock several methods
        with patch.object(tc.ThermalManagement, '__init__', lambda x, y, z, w: None):
            tm = tc.ThermalManagement(None, None, None)
            tm.sys_config = sys_config
            tm.log = self.mock_logger
            tm.root_folder = self.test_dir

        return tm

    def test_sensor_add_config_basic(self):
        """Test _sensor_add_config() basic functionality"""
        print(f"\n{ICON_INFO} Testing _sensor_add_config basic functionality...")

        import hw_management_thermal_control as tc

        tm = self._create_thermal_management()

        # Call _sensor_add_config
        tm._sensor_add_config("test_sensor", "sensor1")

        # Verify sensor was added
        assert "sensor1" in tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["sensor1"]
        assert sensor_config["type"] == "test_sensor"
        assert sensor_config["name"] == "sensor1"

        print(f"{ICON_PASS} Test passed: _sensor_add_config basic functionality")

    def test_sensor_add_config_with_initial_config(self):
        """Test _sensor_add_config() with initial_config"""
        print(f"\n{ICON_INFO} Testing _sensor_add_config with initial_config...")

        import hw_management_thermal_control as tc

        tm = self._create_thermal_management()

        initial_config = {
            "pwm_min": 25,
            "pwm_max": 95,
            "custom_param": "test_value"
        }

        # Call _sensor_add_config with initial_config
        tm._sensor_add_config("test_sensor", "sensor1", initial_config)

        # Verify initial_config was applied
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["sensor1"]
        assert sensor_config["pwm_min"] == 25
        assert sensor_config["pwm_max"] == 95
        assert sensor_config["custom_param"] == "test_value"

        print(f"{ICON_PASS} Test passed: _sensor_add_config with initial_config")

    def test_sensor_add_config_with_dev_tune(self):
        """Test _sensor_add_config() with dev_tune configuration"""
        print(f"\n{ICON_INFO} Testing _sensor_add_config with dev_tune...")

        import hw_management_thermal_control as tc

        dev_tune_config = {
            "module.*": {
                "Mellanox_pn_MCP1600-C003": {
                    "pwm_min": 30,
                    "pwm_max": 90,
                }
            }
        }

        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: {},
            tc.CONST.SYS_CONF_DEV_PARAM: {},
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
            tc.CONST.SYS_CONF_DEV_TUNE: dev_tune_config,
        }

        tm = self._create_thermal_management(sys_config)

        # Call _sensor_add_config for a sensor matching dev_tune pattern
        tm._sensor_add_config("test_sensor", "module1")

        # Verify dev_tune was applied as extra_param
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["module1"]
        assert tc.CONST.DEV_CONF_EXTRA_PARAM in sensor_config
        assert sensor_config[tc.CONST.DEV_CONF_EXTRA_PARAM] == dev_tune_config["module.*"]

        print(f"{ICON_PASS} Test passed: _sensor_add_config with dev_tune")

    def test_sensor_add_config_dev_tune_regex_match(self):
        """Test _sensor_add_config() dev_tune regex matching"""
        print(f"\n{ICON_INFO} Testing _sensor_add_config dev_tune regex matching...")

        import hw_management_thermal_control as tc

        dev_tune_config = {
            "module[0-9]+": {
                "config": "module_config"
            },
            "gearbox.*": {
                "config": "gearbox_config"
            }
        }

        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: {},
            tc.CONST.SYS_CONF_DEV_PARAM: {},
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
            tc.CONST.SYS_CONF_DEV_TUNE: dev_tune_config,
        }

        tm = self._create_thermal_management(sys_config)

        # Test module sensor
        tm._sensor_add_config("test_sensor", "module1")
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["module1"]
        assert sensor_config[tc.CONST.DEV_CONF_EXTRA_PARAM]["config"] == "module_config"

        # Test gearbox sensor
        tm._sensor_add_config("test_sensor", "gearbox5")
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["gearbox5"]
        assert sensor_config[tc.CONST.DEV_CONF_EXTRA_PARAM]["config"] == "gearbox_config"

        print(f"{ICON_PASS} Test passed: _sensor_add_config dev_tune regex matching")

    def test_sensor_add_config_dev_tune_no_match(self):
        """Test _sensor_add_config() when dev_tune doesn't match"""
        print(f"\n{ICON_INFO} Testing _sensor_add_config when dev_tune doesn't match...")

        import hw_management_thermal_control as tc

        dev_tune_config = {
            "module.*": {
                "config": "module_config"
            }
        }

        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: {},
            tc.CONST.SYS_CONF_DEV_PARAM: {},
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
            tc.CONST.SYS_CONF_DEV_TUNE: dev_tune_config,
        }

        tm = self._create_thermal_management(sys_config)

        # Test sensor that doesn't match dev_tune pattern
        tm._sensor_add_config("test_sensor", "asic1")
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["asic1"]

        # Verify extra_param was not added
        assert tc.CONST.DEV_CONF_EXTRA_PARAM not in sensor_config

        print(f"{ICON_PASS} Test passed: _sensor_add_config when dev_tune doesn't match")

    def test_sensor_add_config_priority_order(self):
        """Test _sensor_add_config() configuration priority order"""
        print(f"\n{ICON_INFO} Testing _sensor_add_config configuration priority...")

        import hw_management_thermal_control as tc

        # Set up different configs with overlapping keys
        initial_config = {
            "param1": "initial",
            "param2": "initial",
        }

        dev_tune_config = {
            "sensor1": {
                "tune_data": "from_tune"
            }
        }

        dev_param_config = {
            "sensor1": {
                "param2": "from_dev_param",
                "param3": "from_dev_param",
            }
        }

        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: {},
            tc.CONST.SYS_CONF_DEV_PARAM: dev_param_config,
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
            tc.CONST.SYS_CONF_DEV_TUNE: dev_tune_config,
        }

        tm = self._create_thermal_management(sys_config)

        # Call _sensor_add_config
        tm._sensor_add_config("test_sensor", "sensor1", initial_config)

        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["sensor1"]

        # Verify priority: initial_config has highest priority
        assert sensor_config["param1"] == "initial", "param1 should be from initial_config"
        assert sensor_config["param2"] == "initial", "param2 should be from initial_config (not overridden)"
        assert sensor_config["param3"] == "from_dev_param", "param3 should be from dev_param"
        assert tc.CONST.DEV_CONF_EXTRA_PARAM in sensor_config, "extra_param should be from dev_tune"

        print(f"{ICON_PASS} Test passed: _sensor_add_config configuration priority")

    def test_sensor_add_config_regex_dollar_sign(self):
        """Test _sensor_add_config() auto-appends $ to regex patterns"""
        print(f"\n{ICON_INFO} Testing _sensor_add_config auto-appends $ to regex...")

        import hw_management_thermal_control as tc

        # Pattern without $ should match "module1" but not "module10"
        dev_tune_config = {
            "module1": {  # Without $
                "config": "module1_config"
            }
        }

        sys_config = {
            tc.CONST.SYS_CONF_SENSORS_CONF: {},
            tc.CONST.SYS_CONF_DEV_PARAM: {},
            tc.CONST.SYS_CONF_ASIC_PARAM: {
                "1": {"pwm_control": False, "fan_control": False}
            },
            tc.CONST.SYS_CONF_DEV_TUNE: dev_tune_config,
        }

        tm = self._create_thermal_management(sys_config)

        # Test exact match
        tm._sensor_add_config("test_sensor", "module1")
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["module1"]
        assert tc.CONST.DEV_CONF_EXTRA_PARAM in sensor_config

        # Test non-match (module10 should not match "module1$")
        tm._sensor_add_config("test_sensor", "module10")
        sensor_config = tm.sys_config[tc.CONST.SYS_CONF_SENSORS_CONF]["module10"]
        assert tc.CONST.DEV_CONF_EXTRA_PARAM not in sensor_config, "module10 should not match 'module1$'"

        print(f"{ICON_PASS} Test passed: _sensor_add_config auto-appends $ to regex")


class TestConstants:
    """Test suite for new constants"""

    def test_new_constants_exist(self):
        """Test that new constants are defined"""
        print(f"\n{ICON_INFO} Testing new constants exist...")

        import hw_management_thermal_control as tc

        # Verify new constants exist
        assert hasattr(tc.CONST, 'SYS_CONF_DEV_TUNE'), "SYS_CONF_DEV_TUNE constant should exist"
        assert hasattr(tc.CONST, 'DEV_CONF_EXTRA_PARAM'), "DEV_CONF_EXTRA_PARAM constant should exist"

        # Verify constant values
        assert tc.CONST.SYS_CONF_DEV_TUNE == "dev_tune", f"Expected 'dev_tune', got '{tc.CONST.SYS_CONF_DEV_TUNE}'"
        assert tc.CONST.DEV_CONF_EXTRA_PARAM == "extra_param", f"Expected 'extra_param', got '{tc.CONST.DEV_CONF_EXTRA_PARAM}'"

        print(f"{ICON_PASS} Test passed: new constants exist and have correct values")


# Test runner for standalone execution
def run_tests():
    """Run all tests when executed standalone"""
    import sys

    print("\n" + "=" * 70)
    print("Running unit tests for hw_management_thermal_control.py changes")
    print("=" * 70)

    # Run pytest with verbose output
    pytest_args = [
        __file__,
        "-v",
        "--tb=short",
        "-p", "no:cacheprovider",
    ]

    exit_code = pytest.main(pytest_args)

    print("\n" + "=" * 70)
    if exit_code == 0:
        print(f"{ICON_PASS} All tests passed!")
    else:
        print(f"{ICON_FAIL} Some tests failed (exit code: {exit_code})")
    print("=" * 70 + "\n")

    return exit_code


if __name__ == "__main__":
    sys.exit(run_tests())
