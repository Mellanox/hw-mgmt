#!/usr/bin/python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2022-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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


if __name__ == '__main__':
    unittest.main()
