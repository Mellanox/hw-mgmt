#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Suite for monitor_asic_chipup_status() in peripheral_updater
#
# Verifies that ASIC chipup monitoring works independently of thermal_updater,
# ensuring chipup status tracking continues even if thermal_updater is stopped.
#
# Critical Files:
# - /var/run/hw-management/config/asic_chipup_completed
# - /var/run/hw-management/config/asics_init_done
# - /var/run/hw-management/config/asic_num
########################################################################

import os
import sys
import unittest
import tempfile
import shutil
from unittest.mock import patch, MagicMock, mock_open, call
import importlib.util


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

    @classmethod
    def setUpClass(cls):
        """Set up test class - load hw_management_peripheral_updater module"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)

        if hw_mgmt_dir not in sys.path:
            sys.path.insert(0, hw_mgmt_dir)

        print(f"\n[INFO] Loading modules from: {hw_mgmt_dir}")

        # Verify peripheral_updater exists
        peripheral_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')
        if not os.path.exists(peripheral_path):
            raise FileNotFoundError(f"Cannot find hw_management_peripheral_updater.py in {hw_mgmt_dir}")

    def setUp(self):
        """Set up before each test"""
        self.test_dir = tempfile.mkdtemp(prefix='chipup_monitor_test_')
        self.config_dir = os.path.join(self.test_dir, 'config')
        os.makedirs(self.config_dir, exist_ok=True)

        # Paths to chipup status files
        self.asic_chipup_completed_path = os.path.join(self.config_dir, 'asic_chipup_completed')
        self.asics_init_done_path = os.path.join(self.config_dir, 'asics_init_done')
        self.asic_num_path = os.path.join(self.config_dir, 'asic_num')

        print(f"\n[TEST] Test directory: {self.test_dir}")

    def tearDown(self):
        """Clean up after each test"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _load_peripheral_module(self):
        """Load peripheral_updater module dynamically"""
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

    def test_01_single_asic_ready(self):
        """
        Test monitor_asic_chipup_status with single ready ASIC.

        Scenario: 1 ASIC configured, ASIC is ready (temperature file readable)
        Expected: asic_chipup_completed=1, asics_init_done=1
        """
        print("\n[TEST 1] Single ASIC - ready")

        peripheral_module = self._load_peripheral_module()

        # Mock LOGGER
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        # ASIC configuration - same format as in platform_config
        asic_config = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"},
            "asic1": {"fin": "/sys/module/sx_core/asic0/"}
        }

        # Mock file operations
        file_contents = {}

        def mock_open_func(filename, mode='r', encoding=None):
            if 'asic_num' in filename:
                return mock_open(read_data="1\n")()
            elif 'asic_chipup_completed' in filename or 'asics_init_done' in filename:
                # Capture written values
                m = mock_open()()
                original_write = m.write

                def capturing_write(data):
                    file_contents[filename] = data
                    return original_write(data)
                m.write = capturing_write
                return m
            elif 'temperature/input' in filename:
                # ASIC is ready - temperature file is readable
                return mock_open(read_data="50000")()
            else:
                return mock_open(read_data="")()

        with patch('builtins.open', mock_open_func):
            with patch('os.path.isfile') as mock_isfile:
                # temperature/input file exists for ready ASIC
                def isfile_side_effect(path):
                    return 'temperature/input' in path
                mock_isfile.side_effect = isfile_side_effect

                # Call monitor_asic_chipup_status
                peripheral_module.monitor_asic_chipup_status(asic_config, None)

        # Verify chipup files were written
        chipup_found = False
        init_done_found = False

        for filename, content in file_contents.items():
            if 'asic_chipup_completed' in filename:
                chipup_found = True
                self.assertIn("1", content, "Should write asic_chipup_completed=1 for 1 ready ASIC")
                print(f"[VERIFY] asic_chipup_completed written: {content.strip()}")
            if 'asics_init_done' in filename:
                init_done_found = True
                self.assertIn("1", content, "Should write asics_init_done=1 when all ASICs ready")
                print(f"[VERIFY] asics_init_done written: {content.strip()}")

        self.assertTrue(chipup_found, "asic_chipup_completed must be written")
        self.assertTrue(init_done_found, "asics_init_done must be written")

        print("[PASS] Single ASIC chipup monitoring verified")

    def test_02_multi_asic_all_ready(self):
        """
        Test monitor_asic_chipup_status with multiple ready ASICs.

        Scenario: 3 ASICs configured (2 unique physical ASICs), all ready
        Expected: asic_chipup_completed=2, asics_init_done=1
        """
        print("\n[TEST 2] Multi-ASIC - all ready")

        peripheral_module = self._load_peripheral_module()
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        # ASIC configuration - asic and asic1 point to same physical ASIC
        asic_config = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"},
            "asic1": {"fin": "/sys/module/sx_core/asic0/"},
            "asic2": {"fin": "/sys/module/sx_core/asic1/"}
        }

        file_contents = {}

        def mock_open_func(filename, mode='r', encoding=None):
            if 'asic_num' in filename:
                return mock_open(read_data="2\n")()
            elif 'asic_chipup_completed' in filename or 'asics_init_done' in filename:
                m = mock_open()()
                original_write = m.write

                def capturing_write(data):
                    file_contents[filename] = data
                    return original_write(data)
                m.write = capturing_write
                return m
            elif 'temperature/input' in filename:
                return mock_open(read_data="50000")()
            else:
                return mock_open(read_data="")()

        with patch('builtins.open', mock_open_func):
            with patch('os.path.isfile') as mock_isfile:
                def isfile_side_effect(path):
                    return 'temperature/input' in path
                mock_isfile.side_effect = isfile_side_effect

                peripheral_module.monitor_asic_chipup_status(asic_config, None)

        # Verify
        for filename, content in file_contents.items():
            if 'asic_chipup_completed' in filename:
                self.assertIn("2", content, "Should count 2 unique physical ASICs")
                print(f"[VERIFY] asic_chipup_completed: {content.strip()}")
            if 'asics_init_done' in filename:
                self.assertIn("1", content, "Should be 1 when all ASICs ready (2 >= 2)")
                print(f"[VERIFY] asics_init_done: {content.strip()}")

        print("[PASS] Multi-ASIC chipup monitoring verified")

    def test_03_asic_not_ready(self):
        """
        Test monitor_asic_chipup_status when ASIC is not ready.

        Scenario: 1 ASIC configured, but temperature file not accessible
        Expected: asic_chipup_completed=0, asics_init_done=0
        """
        print("\n[TEST 3] ASIC not ready")

        peripheral_module = self._load_peripheral_module()
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        asic_config = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        file_contents = {}

        def mock_open_func(filename, mode='r', encoding=None):
            if 'asic_num' in filename:
                return mock_open(read_data="1\n")()
            elif 'asic_chipup_completed' in filename or 'asics_init_done' in filename:
                m = mock_open()()
                original_write = m.write

                def capturing_write(data):
                    file_contents[filename] = data
                    return original_write(data)
                m.write = capturing_write
                return m
            else:
                # Temperature file not readable - ASIC not ready
                raise OSError("ASIC not ready")

        with patch('builtins.open', mock_open_func):
            with patch('os.path.isfile', return_value=False):  # Temperature file doesn't exist
                peripheral_module.monitor_asic_chipup_status(asic_config, None)

        # Verify
        for filename, content in file_contents.items():
            if 'asic_chipup_completed' in filename:
                self.assertIn("0", content, "Should be 0 when no ASICs ready")
                print(f"[VERIFY] asic_chipup_completed: {content.strip()}")
            if 'asics_init_done' in filename:
                self.assertIn("0", content, "Should be 0 when ASICs not ready (0 < 1)")
                print(f"[VERIFY] asics_init_done: {content.strip()}")

        print("[PASS] ASIC not ready handling verified")

    def test_04_partial_asic_ready(self):
        """
        Test monitor_asic_chipup_status with partial ASIC initialization.

        Scenario: 3 ASICs configured, only 1 ready
        Expected: asic_chipup_completed=1, asics_init_done=0
        """
        print("\n[TEST 4] Partial ASIC initialization")

        peripheral_module = self._load_peripheral_module()
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        asic_config = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"},
            "asic1": {"fin": "/sys/module/sx_core/asic0/"},
            "asic2": {"fin": "/sys/module/sx_core/asic1/"},
            "asic3": {"fin": "/sys/module/sx_core/asic2/"}
        }

        file_contents = {}

        def mock_open_func(filename, mode='r', encoding=None):
            if 'asic_num' in filename:
                return mock_open(read_data="3\n")()
            elif 'asic_chipup_completed' in filename or 'asics_init_done' in filename:
                m = mock_open()()
                original_write = m.write

                def capturing_write(data):
                    file_contents[filename] = data
                    return original_write(data)
                m.write = capturing_write
                return m
            elif 'temperature/input' in filename:
                # Only asic0 is ready, asic1 and asic2 not ready
                if 'asic0' in filename:
                    return mock_open(read_data="50000")()
                else:
                    raise OSError("ASIC not ready")
            else:
                return mock_open(read_data="")()

        with patch('builtins.open', mock_open_func):
            with patch('os.path.isfile') as mock_isfile:
                def isfile_side_effect(path):
                    return 'asic0' in path and 'temperature/input' in path
                mock_isfile.side_effect = isfile_side_effect

                peripheral_module.monitor_asic_chipup_status(asic_config, None)

        # Verify
        for filename, content in file_contents.items():
            if 'asic_chipup_completed' in filename:
                self.assertIn("1", content, "Should count 1 ready ASIC")
                print(f"[VERIFY] asic_chipup_completed: {content.strip()}")
            if 'asics_init_done' in filename:
                self.assertIn("0", content, "Should be 0 when not all ASICs ready (1 < 3)")
                print(f"[VERIFY] asics_init_done: {content.strip()}")

        print("[PASS] Partial ASIC initialization verified")

    def test_05_independence_from_thermal_updater(self):
        """
        Test that monitor_asic_chipup_status works independently.

        This test verifies that chipup monitoring doesn't depend on thermal_updater
        functions and can run in peripheral_updater alone.
        """
        print("\n[TEST 5] Independence from thermal_updater")

        peripheral_module = self._load_peripheral_module()
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        asic_config = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        file_contents = {}

        def mock_open_func(filename, mode='r', encoding=None):
            if 'asic_num' in filename:
                return mock_open(read_data="1\n")()
            elif 'asic_chipup_completed' in filename or 'asics_init_done' in filename:
                m = mock_open()()
                original_write = m.write

                def capturing_write(data):
                    file_contents[filename] = data
                    return original_write(data)
                m.write = capturing_write
                return m
            elif 'temperature/input' in filename:
                return mock_open(read_data="50000")()
            else:
                return mock_open(read_data="")()

        # Ensure thermal_updater module is NOT imported
        if 'hw_management_thermal_updater' in sys.modules:
            del sys.modules['hw_management_thermal_updater']

        with patch('builtins.open', mock_open_func):
            with patch('os.path.isfile') as mock_isfile:
                def isfile_side_effect(path):
                    return 'temperature/input' in path
                mock_isfile.side_effect = isfile_side_effect

                # This should work without thermal_updater
                peripheral_module.monitor_asic_chipup_status(asic_config, None)

        # Verify it still works
        self.assertTrue(len(file_contents) > 0, "Chipup files should be written without thermal_updater")
        print("[PASS] monitor_asic_chipup_status works independently of thermal_updater")


if __name__ == '__main__':
    # Run tests with verbose output
    unittest.main(verbosity=2)
