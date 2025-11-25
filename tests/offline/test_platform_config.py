#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Suite for platform_config module and refactored architecture
#
# Validates:
# - PLATFORM_CONFIG structure and data integrity
# - _build_thermal_config() filtering logic
# - Helper functions (get_platform_config, get_module_count, etc.)
# - Architecture independence (thermal_updater can be disabled)
#
########################################################################

import os
import sys
import unittest
from unittest.mock import MagicMock, patch
import importlib.util


class TestPlatformConfigStructure(unittest.TestCase):
    """
    Test suite to validate PLATFORM_CONFIG structure.

    Ensures the raw platform configuration data has proper structure
    and all required fields.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test class - load platform_config module"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)

        if hw_mgmt_dir not in sys.path:
            sys.path.insert(0, hw_mgmt_dir)

        print(f"\n[INFO] Loading platform_config from: {hw_mgmt_dir}")

        # Load platform_config module
        config_path = os.path.join(hw_mgmt_dir, 'hw_management_platform_config.py')
        if not os.path.exists(config_path):
            raise FileNotFoundError(f"Cannot find hw_management_platform_config.py in {hw_mgmt_dir}")

        spec = importlib.util.spec_from_file_location("hw_management_platform_config", config_path)
        cls.config_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.config_module)

        cls.PLATFORM_CONFIG = cls.config_module.PLATFORM_CONFIG

        print(f"[INFO] Loaded PLATFORM_CONFIG with {len(cls.PLATFORM_CONFIG)} platform entries")

    def test_01_platform_config_is_dict(self):
        """Test that PLATFORM_CONFIG is a dictionary."""
        print("\n[TEST 1] Validating PLATFORM_CONFIG is a dictionary")

        self.assertIsInstance(self.PLATFORM_CONFIG, dict,
                              "PLATFORM_CONFIG must be a dictionary")
        self.assertGreater(len(self.PLATFORM_CONFIG), 0,
                           "PLATFORM_CONFIG must not be empty")

        print(f"[PASS] PLATFORM_CONFIG is dict with {len(self.PLATFORM_CONFIG)} entries")

    def test_02_platform_config_has_expected_skus(self):
        """Test that PLATFORM_CONFIG contains expected SKUs."""
        print("\n[TEST 2] Validating PLATFORM_CONFIG has expected SKUs")

        # Check for some known platforms
        expected_skus = ["HI162", "def"]

        for sku in expected_skus:
            self.assertIn(sku, self.PLATFORM_CONFIG,
                          f"PLATFORM_CONFIG must contain '{sku}' entry")
            print(f"  ✓ Found SKU: {sku}")

        print(f"[PASS] All expected SKUs present")

    def test_03_each_platform_entry_is_list(self):
        """Test that each platform entry is a list of monitoring configs."""
        print("\n[TEST 3] Validating each platform entry is a list")

        for sku, entries in self.PLATFORM_CONFIG.items():
            self.assertIsInstance(entries, list,
                                  f"Entry for '{sku}' must be a list")
            print(f"  ✓ {sku}: {len(entries)} monitoring entries")

        print(f"[PASS] All platform entries are lists")

    def test_04_monitoring_entries_have_required_fields(self):
        """Test that each monitoring entry has required fields."""
        print("\n[TEST 4] Validating monitoring entries have required fields")

        required_fields = ["fn", "arg", "poll", "ts"]

        for sku, entries in self.PLATFORM_CONFIG.items():
            for i, entry in enumerate(entries):
                self.assertIsInstance(entry, dict,
                                      f"{sku}[{i}] must be a dictionary")

                for field in required_fields:
                    self.assertIn(field, entry,
                                  f"{sku}[{i}] must have '{field}' field")

                # Validate field types
                self.assertIsInstance(entry["fn"], str, f"{sku}[{i}]['fn'] must be string")
                self.assertIsInstance(entry["poll"], (int, float),
                                      f"{sku}[{i}]['poll'] must be numeric")
                self.assertIsInstance(entry["ts"], (int, float),
                                      f"{sku}[{i}]['ts'] must be numeric")

        print(f"[PASS] All monitoring entries have required fields")

    def test_05_platform_config_has_function_types(self):
        """Test that PLATFORM_CONFIG contains expected function types."""
        print("\n[TEST 5] Validating PLATFORM_CONFIG has expected function types")

        # Collect all function names
        all_functions = set()
        for entries in self.PLATFORM_CONFIG.values():
            for entry in entries:
                all_functions.add(entry["fn"])

        # Expected function categories
        expected_thermal_functions = {"asic_temp_populate", "module_temp_populate"}
        expected_peripheral_functions = {"sync_fan", "run_cmd", "run_power_button_event"}

        # Check thermal functions exist
        for fn in expected_thermal_functions:
            self.assertIn(fn, all_functions,
                          f"PLATFORM_CONFIG should contain '{fn}' function")
            print(f"  ✓ Found thermal function: {fn}")

        # Check peripheral functions exist
        for fn in expected_peripheral_functions:
            if fn in all_functions:
                print(f"  ✓ Found peripheral function: {fn}")

        print(f"[PASS] PLATFORM_CONFIG contains expected function types")
        print(f"[INFO] Total unique functions: {len(all_functions)}")


class TestThermalConfigFiltering(unittest.TestCase):
    """
    Test suite to validate _build_thermal_config() filtering logic.

    Ensures that thermal_updater correctly filters PLATFORM_CONFIG to
    include only thermal-related functions.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test class - load thermal_updater module"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)

        if hw_mgmt_dir not in sys.path:
            sys.path.insert(0, hw_mgmt_dir)

        print(f"\n[INFO] Loading thermal_updater from: {hw_mgmt_dir}")

        # Load thermal_updater module
        thermal_path = os.path.join(hw_mgmt_dir, 'hw_management_thermal_updater.py')
        if not os.path.exists(thermal_path):
            raise FileNotFoundError(f"Cannot find hw_management_thermal_updater.py in {hw_mgmt_dir}")

        spec = importlib.util.spec_from_file_location("hw_management_thermal_updater", thermal_path)
        cls.thermal_module = importlib.util.module_from_spec(spec)

        # Mock dependencies
        sys.modules["hw_management_lib"] = MagicMock()

        spec.loader.exec_module(cls.thermal_module)
        cls.thermal_config = cls.thermal_module.thermal_config

        # Also load platform_config for comparison
        config_path = os.path.join(hw_mgmt_dir, 'hw_management_platform_config.py')
        spec2 = importlib.util.spec_from_file_location("hw_management_platform_config", config_path)
        cls.config_module = importlib.util.module_from_spec(spec2)
        spec2.loader.exec_module(cls.config_module)
        cls.PLATFORM_CONFIG = cls.config_module.PLATFORM_CONFIG

        print(f"[INFO] Loaded thermal_config with {len(cls.thermal_config)} entries")

    def test_01_thermal_config_only_has_thermal_functions(self):
        """Test that thermal_config only contains thermal-related functions."""
        print("\n[TEST 1] Validating thermal_config contains only thermal functions")

        thermal_functions = {"asic_temp_populate", "module_temp_populate"}

        for sku, entries in self.thermal_config.items():
            if sku == "def":
                continue

            for entry in entries:
                fn = entry.get("fn")
                self.assertIn(fn, thermal_functions,
                              f"thermal_config[{sku}] contains non-thermal function: {fn}")

        print(f"[PASS] thermal_config contains only thermal functions")

    def test_02_thermal_config_excludes_peripheral_functions(self):
        """Test that thermal_config excludes peripheral functions."""
        print("\n[TEST 2] Validating thermal_config excludes peripheral functions")

        peripheral_functions = {"sync_fan", "run_cmd", "run_power_button_event",
                                "redfish_get_sensor"}

        for sku, entries in self.thermal_config.items():
            if sku == "def":
                continue

            for entry in entries:
                fn = entry.get("fn")
                self.assertNotIn(fn, peripheral_functions,
                                 f"thermal_config[{sku}] should not contain peripheral function: {fn}")

        print(f"[PASS] thermal_config excludes all peripheral functions")

    def test_03_thermal_config_has_def_key(self):
        """Test that thermal_config has 'def' key."""
        print("\n[TEST 3] Validating thermal_config has 'def' key")

        self.assertIn("def", self.thermal_config,
                      "thermal_config must have 'def' key for default config")
        self.assertIsInstance(self.thermal_config["def"], list,
                              "thermal_config['def'] must be a list")

        print(f"[PASS] thermal_config has 'def' key")

    def test_04_filtering_preserves_entry_structure(self):
        """Test that filtering preserves entry structure (fn, arg, poll, ts)."""
        print("\n[TEST 4] Validating filtering preserves entry structure")

        required_fields = ["fn", "arg", "poll", "ts"]

        for sku, entries in self.thermal_config.items():
            if sku == "def":
                continue

            for entry in entries:
                for field in required_fields:
                    self.assertIn(field, entry,
                                  f"thermal_config[{sku}] entry missing field: {field}")

        print(f"[PASS] Filtering preserves entry structure")

    def test_05_thermal_config_count_vs_platform_config(self):
        """Test that thermal_config has fewer entries than PLATFORM_CONFIG."""
        print("\n[TEST 5] Comparing thermal_config vs PLATFORM_CONFIG counts")

        # For platforms with both thermal and peripheral functions,
        # thermal_config should have fewer entries
        for sku in self.PLATFORM_CONFIG.keys():
            if sku == "def" or sku == "test":
                continue

            if sku in self.thermal_config:
                platform_count = len(self.PLATFORM_CONFIG[sku])
                thermal_count = len(self.thermal_config[sku])

                # thermal_config should have <= entries (after filtering)
                self.assertLessEqual(thermal_count, platform_count,
                                     f"{sku}: thermal_config should have <= entries than PLATFORM_CONFIG")

                print(f"  ✓ {sku}: {platform_count} total → {thermal_count} thermal")

        print(f"[PASS] thermal_config properly filtered from PLATFORM_CONFIG")


class TestPlatformConfigHelperFunctions(unittest.TestCase):
    """
    Test suite for platform_config helper functions.

    Tests get_platform_config(), get_module_count(), get_all_platform_skus()
    including edge cases.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test class - load platform_config module"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)

        if hw_mgmt_dir not in sys.path:
            sys.path.insert(0, hw_mgmt_dir)

        print(f"\n[INFO] Loading platform_config from: {hw_mgmt_dir}")

        # Load platform_config module
        config_path = os.path.join(hw_mgmt_dir, 'hw_management_platform_config.py')
        spec = importlib.util.spec_from_file_location("hw_management_platform_config", config_path)
        cls.config_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.config_module)

        print(f"[INFO] Loaded platform_config module")

    def test_01_get_platform_config_valid_sku(self):
        """Test get_platform_config() with valid SKU."""
        print("\n[TEST 1] Testing get_platform_config() with valid SKU")

        result = self.config_module.get_platform_config("HI162")

        self.assertIsNotNone(result, "get_platform_config('HI162') should return data")
        self.assertIsInstance(result, list, "get_platform_config() should return a list")
        self.assertGreater(len(result), 0, "HI162 should have monitoring entries")

        print(f"[PASS] get_platform_config('HI162') returns {len(result)} entries")

    def test_02_get_platform_config_invalid_sku(self):
        """Test get_platform_config() with invalid SKU."""
        print("\n[TEST 2] Testing get_platform_config() with invalid SKU")

        result = self.config_module.get_platform_config("INVALID_SKU_99999")

        self.assertEqual(result, [], "get_platform_config() should return empty list for invalid SKU")

        print(f"[PASS] get_platform_config('INVALID_SKU') returns empty list")

    def test_03_get_module_count_valid_sku(self):
        """Test get_module_count() with valid SKU."""
        print("\n[TEST 3] Testing get_module_count() with valid SKU")

        result = self.config_module.get_module_count("HI162")

        self.assertIsInstance(result, int, "get_module_count() should return integer")
        self.assertEqual(result, 36, "HI162 should have 36 modules")

        print(f"[PASS] get_module_count('HI162') returns {result}")

    def test_04_get_module_count_unknown_sku(self):
        """Test get_module_count() with unknown SKU."""
        print("\n[TEST 4] Testing get_module_count() with unknown SKU")

        result = self.config_module.get_module_count("UNKNOWN_SKU")

        self.assertIsInstance(result, int, "get_module_count() should return integer")
        self.assertEqual(result, 0, "Unknown SKU should return 0 modules")

        print(f"[PASS] get_module_count('UNKNOWN_SKU') returns 0")

    def test_05_get_all_platform_skus(self):
        """Test get_all_platform_skus() returns all SKUs."""
        print("\n[TEST 5] Testing get_all_platform_skus()")

        result = self.config_module.get_all_platform_skus()

        self.assertIsInstance(result, list, "get_all_platform_skus() should return list")
        self.assertGreater(len(result), 0, "Should return at least one SKU")

        # Check that known SKUs are present
        self.assertIn("HI162", result, "Should include HI162")
        self.assertIn("def", result, "Should include 'def'")

        print(f"[PASS] get_all_platform_skus() returns {len(result)} SKUs")

    def test_06_get_module_count_edge_cases(self):
        """Test get_module_count() with various edge cases."""
        print("\n[TEST 6] Testing get_module_count() edge cases")

        # Test with different platforms
        test_cases = [
            ("HI162", 36, "Platform with modules"),
            ("def", 0, "Default platform"),
        ]

        for sku, expected_count, description in test_cases:
            result = self.config_module.get_module_count(sku)
            self.assertEqual(result, expected_count,
                             f"{description}: get_module_count('{sku}') should return {expected_count}")
            print(f"  ✓ {description}: {sku} → {result} modules")

        print(f"[PASS] All edge cases handled correctly")


class TestArchitectureIndependence(unittest.TestCase):
    """
    Test suite to validate architecture independence.

    Ensures peripheral_updater can work without thermal_updater,
    and validates clean dependency separation.
    """

    def test_01_peripheral_updater_imports_without_thermal(self):
        """Test that peripheral_updater can import without thermal_updater."""
        print("\n[TEST 1] Testing peripheral_updater imports without thermal_updater")

        # Remove thermal_updater from sys.modules to simulate it being absent
        if 'hw_management_thermal_updater' in sys.modules:
            del sys.modules['hw_management_thermal_updater']

        # Load peripheral_updater
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        peripheral_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')

        spec = importlib.util.spec_from_file_location("hw_management_peripheral_updater_test",
                                                      peripheral_path)
        peripheral_module = importlib.util.module_from_spec(spec)

        # Mock dependencies
        sys.modules["hw_management_redfish_client"] = MagicMock()
        sys.modules["hw_management_lib"] = MagicMock()

        # This should NOT raise ImportError
        try:
            spec.loader.exec_module(peripheral_module)
            print(f"[PASS] peripheral_updater imports successfully without thermal_updater")
        except ImportError as e:
            self.fail(f"peripheral_updater should not depend on thermal_updater: {e}")

    def test_02_platform_config_is_independent(self):
        """Test that platform_config is independent (doesn't import other hw modules)."""
        print("\n[TEST 2] Testing platform_config is independent")

        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        config_path = os.path.join(hw_mgmt_dir, 'hw_management_platform_config.py')

        # Read the file and check for actual import statements (not in docstrings/comments)
        with open(config_path, 'r') as f:
            lines = f.readlines()

        # Check for problematic imports (imports of other hw_management modules)
        problematic_modules = ['peripheral_updater', 'thermal_updater', 'hw_management_lib']
        bad_imports = []

        in_docstring = False
        for line in lines:
            # Track docstrings
            if '"""' in line:
                in_docstring = not in_docstring
                continue

            # Skip if in docstring or comment
            if in_docstring or line.strip().startswith('#'):
                continue

            # Check for actual import statements
            for module in problematic_modules:
                if f'import {module}' in line or f'from hw_management_{module}' in line:
                    bad_imports.append(line.strip())

        self.assertEqual(len(bad_imports), 0,
                         f"platform_config should be a pure data module. Found imports: {bad_imports}")

        print(f"[PASS] platform_config is independent (no hw_management imports)")


def main():
    """Main test runner"""
    print("=" * 80)
    print("PLATFORM_CONFIG AND REFACTORED ARCHITECTURE TEST SUITE")
    print("=" * 80)
    print("\nPurpose: Validate refactored architecture and platform_config module")
    print("Tests: PLATFORM_CONFIG structure, filtering logic, helper functions")
    print("=" * 80)

    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestPlatformConfigStructure))
    suite.addTests(loader.loadTestsFromTestCase(TestThermalConfigFiltering))
    suite.addTests(loader.loadTestsFromTestCase(TestPlatformConfigHelperFunctions))
    suite.addTests(loader.loadTestsFromTestCase(TestArchitectureIndependence))

    # Run tests with verbose output
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("\n" + "=" * 80)
    if result.wasSuccessful():
        print("[SUCCESS] All platform_config tests PASSED")
        print("[INFO] Refactored architecture validated")
    else:
        print("[FAILURE] Some tests failed")
        print(f"[INFO] Failures: {len(result.failures)}, Errors: {len(result.errors)}")
    print("=" * 80)

    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
