#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

        spec = importlib.util.spec_from_file_location("hw_management_peripheral_updater", hw_mgmt_path)
        module = importlib.util.module_from_spec(spec)

        # Mock dependencies
        sys.modules["hw_management_redfish_client"] = MagicMock()
        sys.modules["hw_management_lib"] = MagicMock()

        spec.loader.exec_module(module)
        return module

    def test_01_module_counter_written_by_peripheral_updater(self):
        """
        Test that peripheral_updater writes module_counter correctly.

        Critical Test: Verifies the core functionality.
        """
        print("\n[TEST 1] Testing module_counter writing by peripheral_updater")

        peripheral_module = self._load_peripheral_module()

        # Mock LOGGER to avoid initialization issues
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        # Test with a platform that has modules (simulate HI162 with 36 modules)
        with patch('builtins.open', create=True) as mock_open:
            mock_file = MagicMock()
            mock_open.return_value.__enter__.return_value = mock_file

            # Call write_module_counter with HI162 SKU (has 36 modules)
            peripheral_module.write_module_counter("HI162")

            # Verify file was opened for writing
            mock_open.assert_called_once_with("/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")

            # Verify correct count was written (HI162 has 36 modules in thermal_config)
            mock_file.write.assert_called_once()
            written_value = mock_file.write.call_args[0][0]

            # HI162 should have modules
            self.assertIn("36", written_value, "HI162 platform should write 36 modules")

            # Verify logger was called
            mock_logger.notice.assert_called()
            log_message = mock_logger.notice.call_args[0][0]
            self.assertIn("module_counter initialized", log_message)

        print("[PASS] module_counter written correctly by peripheral_updater")

    def test_02_module_counter_zero_for_platform_without_modules(self):
        """
        Test that module_counter is written as 0 for platforms without modules.

        Critical Test: Ensures file is always created even with 0 modules.
        """
        print("\n[TEST 2] Testing module_counter=0 for platforms without modules")

        peripheral_module = self._load_peripheral_module()

        # Mock LOGGER
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        # Test with unknown platform (should write 0)
        with patch('builtins.open', create=True) as mock_open:
            mock_file = MagicMock()
            mock_open.return_value.__enter__.return_value = mock_file

            # Call write_module_counter with unknown SKU
            peripheral_module.write_module_counter("UNKNOWN_PLATFORM")

            # Verify file was opened for writing
            mock_open.assert_called_once_with("/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")

            # Verify 0 was written
            mock_file.write.assert_called_once_with("0\n")

            # Verify logger message mentions 0 modules
            mock_logger.notice.assert_called()
            log_message = mock_logger.notice.call_args[0][0]
            self.assertIn("0 - no modules", log_message)

        print("[PASS] module_counter=0 written for platforms without modules")

    def test_03_module_counter_with_thermal_updater_disabled(self):
        """
        TEST CRITICAL SCENARIO: Thermal updater is disabled/killed by customer.

        This test simulates a customer disabling hw_management_thermal_updater.
        The peripheral_updater must still write module_counter correctly.

        Stakeholder Protection: Ensures dependent services still work.
        """
        print("\n[TEST 3] Testing module_counter when thermal_updater is DISABLED")
        print("[INFO] Simulating customer disabling thermal_updater service...")

        # Remove thermal_updater from sys.modules to simulate it being unavailable
        if 'hw_management_thermal_updater' in sys.modules:
            del sys.modules['hw_management_thermal_updater']

        # Reload peripheral_updater module to verify it works independently
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')

        spec = importlib.util.spec_from_file_location("hw_management_peripheral_updater_test", hw_mgmt_path)
        peripheral_module = importlib.util.module_from_spec(spec)

        # Mock dependencies
        sys.modules["hw_management_redfish_client"] = MagicMock()
        sys.modules["hw_management_lib"] = MagicMock()

        # Mock platform_config module with proper return values
        mock_platform_config = MagicMock()
        mock_platform_config.get_module_count = MagicMock(return_value=0)  # Return actual int
        mock_platform_config.get_platform_config = MagicMock(return_value=None)
        sys.modules["hw_management_platform_config"] = mock_platform_config

        # This should NOT raise an error
        try:
            spec.loader.exec_module(peripheral_module)
            print("[PASS] peripheral_updater loaded successfully without thermal_updater")
        except ImportError as e:
            self.fail(f"peripheral_updater should handle missing dependencies gracefully: {e}")

        # Verify platform config functions are available (new architecture)
        self.assertTrue(hasattr(peripheral_module, 'get_module_count'))
        self.assertTrue(callable(peripheral_module.get_module_count))

        # Mock LOGGER
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        # Test write_module_counter still works
        with patch('builtins.open', create=True) as mock_open:
            mock_file = MagicMock()
            mock_open.return_value.__enter__.return_value = mock_file

            # Call write_module_counter - should work with platform config
            peripheral_module.write_module_counter("ANY_PLATFORM")

            # Verify file was opened for writing
            mock_open.assert_called_once_with("/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")

            # Verify something was written (at least 0)
            mock_file.write.assert_called_once()
            written_value = mock_file.write.call_args[0][0]
            self.assertIn("\n", written_value, "Should write newline-terminated value")

        print("[PASS] CRITICAL: module_counter still written when platform config is used")
        print("[INFO] All stakeholders protected - using centralized platform configuration")

    def test_04_module_counter_error_handling(self):
        """
        Test that write_module_counter handles errors gracefully.

        Critical Test: Ensures daemon doesn't crash on filesystem errors.
        """
        print("\n[TEST 4] Testing module_counter error handling")

        peripheral_module = self._load_peripheral_module()

        # Mock LOGGER
        mock_logger = MagicMock()
        peripheral_module.LOGGER = mock_logger

        # Test with file write error (permission denied)
        with patch('builtins.open', side_effect=OSError("Permission denied")):
            # Should not raise exception
            try:
                peripheral_module.write_module_counter("HI162")
                print("[PASS] Handled permission error gracefully")
            except Exception as e:
                self.fail(f"write_module_counter should handle errors gracefully: {e}")

            # Verify warning was logged
            mock_logger.warning.assert_called()
            warning_message = mock_logger.warning.call_args[0][0]
            self.assertIn("Failed to write module_counter", warning_message)

        print("[PASS] Error handling works correctly")

    def test_05_module_counter_integration_peripheral_always_runs(self):
        """
        Integration test: Verify peripheral_updater is the right place for module_counter.

        Validates architectural decision:
        - peripheral_updater runs core services (fans, BMC, etc.)
        - Customer less likely to disable it
        - Therefore module_counter is more reliable here
        """
        print("\n[TEST 5] Integration test - architectural validation")

        peripheral_module = self._load_peripheral_module()

        # Verify write_module_counter exists in peripheral_updater
        self.assertTrue(hasattr(peripheral_module, 'write_module_counter'))
        self.assertTrue(callable(peripheral_module.write_module_counter))

        # Verify it's documented
        docstring = peripheral_module.write_module_counter.__doc__
        self.assertIsNotNone(docstring)
        self.assertIn("peripheral_updater", docstring.lower())
        self.assertIn("thermal_updater is disabled", docstring.lower())

        print("[PASS] Architectural decision validated")
        print("[INFO] module_counter correctly placed in peripheral_updater")


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
