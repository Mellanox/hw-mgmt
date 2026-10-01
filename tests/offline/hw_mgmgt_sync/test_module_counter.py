#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Suite for module_counter functionality
#
# Verifies that module_counter is written correctly by peripheral_updater
# even when thermal_updater is disabled or unavailable.
########################################################################

import os
import sys
import unittest
import tempfile
import shutil
from unittest.mock import patch, MagicMock
import importlib.util


class TestModuleCounterReliability(unittest.TestCase):
    """
    Test suite to verify module_counter writing reliability.

    Critical Requirements:
    1. module_counter must be written by peripheral_updater
    2. module_counter must be available even if thermal_updater is disabled
    3. module_counter must contain correct platform-specific count
    """

    @classmethod
    def setUpClass(cls):
        """Set up test class - load hw_management modules"""
        # Find the hw_management modules
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # Go up to repo root: test_module_counter.py -> hw_mgmgt_sync -> offline -> tests -> repo_root
        repo_root = os.path.join(script_dir, '..', '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)

        if hw_mgmt_dir not in sys.path:
            sys.path.insert(0, hw_mgmt_dir)

        print(f"\n[INFO] Loading modules from: {hw_mgmt_dir}")

        # Verify files exist
        peripheral_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')
        thermal_path = os.path.join(hw_mgmt_dir, 'hw_management_thermal_updater.py')

        if not os.path.exists(peripheral_path):
            raise FileNotFoundError(f"Cannot find hw_management_peripheral_updater.py in {hw_mgmt_dir}")
        if not os.path.exists(thermal_path):
            raise FileNotFoundError(f"Cannot find hw_management_thermal_updater.py in {hw_mgmt_dir}")

    def setUp(self):
        """Set up before each test"""
        # Create temporary directory for test files
        self.test_dir = tempfile.mkdtemp(prefix='module_counter_test_')
        self.config_dir = os.path.join(self.test_dir, 'config')
        os.makedirs(self.config_dir, exist_ok=True)
        self.module_counter_path = os.path.join(self.config_dir, 'module_counter')

        print(f"\n[TEST] Test directory: {self.test_dir}")

    def tearDown(self):
        """Clean up after each test"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _load_peripheral_module(self):
        """Load peripheral_updater module dynamically"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')

        # Load platform_config first (real module, not mocked)
        platform_config_path = os.path.join(hw_mgmt_dir, 'hw_management_platform_config.py')
        platform_spec = importlib.util.spec_from_file_location("hw_management_platform_config", platform_config_path)
        platform_module = importlib.util.module_from_spec(platform_spec)
        sys.modules["hw_management_platform_config"] = platform_module
        platform_spec.loader.exec_module(platform_module)

        spec = importlib.util.spec_from_file_location("hw_management_peripheral_updater", hw_mgmt_path)
        module = importlib.util.module_from_spec(spec)

        # Mock dependencies
        sys.modules["hw_management_redfish_client"] = MagicMock()
        sys.modules["hw_management_lib"] = MagicMock()

        spec.loader.exec_module(module)
        return module

    def _notice_messages(self, mock_logger):
        """Return string messages passed to LOGGER.notice."""
        messages = []
        for call in mock_logger.notice.call_args_list:
            if call[0] and isinstance(call[0][0], str):
                messages.append(call[0][0])
        return messages

    def test_01_module_counter_written_by_peripheral_updater(self):
        """
        Test that peripheral_updater writes module_counter from the poll arg.

        A missing file is created with the configured module count.
        """
        print("\n[TEST 1] Testing module_counter writing by peripheral_updater")

        peripheral_module = self._load_peripheral_module()

        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        with patch('os.path.isfile', return_value=False), \
                patch('builtins.open', create=True) as mock_open:
            mock_file = MagicMock()
            mock_open.return_value.__enter__.return_value = mock_file

            peripheral_module.module_temp_populate({"module_count": 36}, None)

            mock_open.assert_called_once_with(
                "/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")
            mock_file.write.assert_called_once_with("36\n")
            self.assertIn("Module count updated to 36", self._notice_messages(mock_logger))

        print("[PASS] module_counter written correctly by peripheral_updater")

    def test_02_module_counter_zero_for_platform_without_modules(self):
        """
        Test that module_counter is written as 0 when the poll arg has no modules.
        """
        print("\n[TEST 2] Testing module_counter=0 for platforms without modules")

        peripheral_module = self._load_peripheral_module()

        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        with patch('os.path.isfile', return_value=False), \
                patch('builtins.open', create=True) as mock_open:
            mock_file = MagicMock()
            mock_open.return_value.__enter__.return_value = mock_file

            peripheral_module.module_temp_populate({"module_count": 0}, None)

            mock_open.assert_called_once_with(
                "/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")
            mock_file.write.assert_called_once_with("0\n")
            self.assertIn("Module count updated to 0", self._notice_messages(mock_logger))

        print("[PASS] module_counter=0 written for platforms without modules")

    def test_02b_module_counter_refreshed_after_reset(self):
        """
        A later reset of module_counter (for example to 0) is corrected on the next poll.
        """
        print("\n[TEST 2b] Testing module_counter refresh after an external reset")

        peripheral_module = self._load_peripheral_module()
        peripheral_module.LOGGER = MagicMock()

        with patch('os.path.isfile', return_value=True), \
                patch('builtins.open', unittest.mock.mock_open(read_data="0\n")) as mock_open:
            peripheral_module.module_temp_populate({"module_count": 36}, None)
            mock_open().write.assert_called_with("36\n")

        print("[PASS] stale module_counter refreshed to the configured count")

    def test_03_module_counter_with_thermal_updater_disabled(self):
        """
        Thermal updater disabled: peripheral_updater still refreshes module_counter.
        """
        print("\n[TEST 3] Testing module_counter when thermal_updater is DISABLED")
        print("[INFO] Simulating customer disabling thermal_updater service...")

        if 'hw_management_thermal_updater' in sys.modules:
            del sys.modules['hw_management_thermal_updater']

        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')

        spec = importlib.util.spec_from_file_location("hw_management_peripheral_updater_test", hw_mgmt_path)
        peripheral_module = importlib.util.module_from_spec(spec)

        sys.modules["hw_management_redfish_client"] = MagicMock()
        sys.modules["hw_management_lib"] = MagicMock()

        mock_platform_config = MagicMock()
        mock_platform_config.get_platform_config = MagicMock(return_value=[])
        saved_platform_config = sys.modules.get("hw_management_platform_config")
        sys.modules["hw_management_platform_config"] = mock_platform_config

        try:
            spec.loader.exec_module(peripheral_module)
            print("[PASS] peripheral_updater loaded successfully without thermal_updater")
        except ImportError as e:
            self.fail(f"peripheral_updater should handle missing dependencies gracefully: {e}")
        finally:
            if saved_platform_config is None:
                sys.modules.pop("hw_management_platform_config", None)
            else:
                sys.modules["hw_management_platform_config"] = saved_platform_config

        self.assertTrue(hasattr(peripheral_module, 'module_temp_populate'))
        self.assertTrue(callable(peripheral_module.module_temp_populate))
        self.assertFalse(hasattr(peripheral_module, 'get_module_count'))

        peripheral_module.LOGGER = MagicMock()

        with patch('os.path.isfile', return_value=False), \
                patch('builtins.open', create=True) as mock_open:
            mock_file = MagicMock()
            mock_open.return_value.__enter__.return_value = mock_file

            peripheral_module.module_temp_populate({"module_count": 36}, None)

            mock_open.assert_called_once_with(
                "/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")
            mock_file.write.assert_called_once_with("36\n")

        print("[PASS] CRITICAL: module_counter still written when thermal_updater is disabled")

    def test_04_module_counter_error_handling(self):
        """
        module_temp_populate logs a warning and does not raise on filesystem errors.
        """
        print("\n[TEST 4] Testing module_counter error handling")

        peripheral_module = self._load_peripheral_module()

        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        with patch('os.path.isfile', return_value=False), \
                patch('builtins.open', side_effect=OSError("Permission denied")):
            try:
                peripheral_module.module_temp_populate({"module_count": 36}, None)
                print("[PASS] Handled permission error gracefully")
            except Exception as e:
                self.fail(f"module_temp_populate should handle errors gracefully: {e}")

            mock_logger.warning.assert_called()
            warning_message = mock_logger.warning.call_args[0][0]
            self.assertIn("/var/run/hw-management/config/module_counter", warning_message)
            self.assertIn("Permission denied", warning_message)

        print("[PASS] Error handling works correctly")

    def test_05_module_counter_integration_peripheral_always_runs(self):
        """
        module_counter refresh lives on peripheral_updater, which keeps running
        when thermal_updater is disabled.
        """
        print("\n[TEST 5] Integration test - architectural validation")

        peripheral_module = self._load_peripheral_module()

        self.assertTrue(hasattr(peripheral_module, 'module_temp_populate'))
        self.assertTrue(callable(peripheral_module.module_temp_populate))
        self.assertFalse(hasattr(peripheral_module, 'write_module_counter'))

        docstring = peripheral_module.module_temp_populate.__doc__
        self.assertIsNotNone(docstring)
        self.assertIn("module counter", docstring.lower())

        print("[PASS] Architectural decision validated")
        print("[INFO] module_counter refresh lives in peripheral_updater")


def main():
    """Main test runner"""
    print("=" * 80)
    print("MODULE_COUNTER RELIABILITY TEST SUITE")
    print("=" * 80)
    print("\nPurpose: Verify module_counter is always written by peripheral_updater")
    print("Critical Scenario: Thermal updater disabled by customer")
    print("=" * 80)

    # Run tests with verbose output
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestModuleCounterReliability)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("\n" + "=" * 80)
    if result.wasSuccessful():
        print("[SUCCESS] All module_counter reliability tests PASSED")
        print("[INFO] Stakeholders protected from thermal_updater failures")
    else:
        print("[FAILURE] Some tests failed")
        print(f"[INFO] Failures: {len(result.failures)}, Errors: {len(result.errors)}")
    print("=" * 80)

    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
