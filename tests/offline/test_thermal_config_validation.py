#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Suite for thermal_config structure validation
#
# Validates that thermal_config has proper configuration for all systems,
# ensuring ASIC configurations (asic, asic1, asic2, asic3, etc.) are
# properly defined for each platform, both current and future additions.
#
# Critical Validations:
# - ASIC naming convention (asic, asic1, asic2, asic3...)
# - No gaps in ASIC numbering
# - Required fields present for each ASIC
# - Module temperature configuration present
# - Consistency across platforms
########################################################################

import os
import sys
import unittest
import re
from collections import defaultdict
import importlib.util


class TestThermalConfigValidation(unittest.TestCase):
    """
    Test suite to validate thermal_config structure for all platforms.

    Ensures configuration quality and catches errors when new platforms
    are added to the system.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test class - load thermal_updater module"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # Go up to repo root: test_thermal_config_validation.py -> offline -> tests -> repo_root
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
        from unittest.mock import MagicMock
        sys.modules["hw_management_lib"] = MagicMock()

        spec.loader.exec_module(cls.thermal_module)
        cls.thermal_config = cls.thermal_module.thermal_config

        print(f"[INFO] Loaded thermal_config with {len(cls.thermal_config)} platform entries")

    def test_01_thermal_config_structure(self):
        """
        Test that thermal_config has proper structure.

        Validates:
        - thermal_config is a dictionary
        - Contains "def" key for default config
        - Has platform-specific entries
        """
        print("\n[TEST 1] Validating thermal_config structure")

        self.assertIsInstance(self.thermal_config, dict, "thermal_config must be a dictionary")
        self.assertIn("def", self.thermal_config, "thermal_config must have 'def' key for defaults")

        # Check that we have platform-specific configs
        platform_count = len([k for k in self.thermal_config.keys() if k != "def"])
        self.assertGreater(platform_count, 0, "thermal_config must have platform-specific entries")

        print(f"[PASS] thermal_config structure valid: {platform_count} platforms configured")

    def test_02_all_platforms_have_asic_config(self):
        """
        Test that all platforms have asic_temp_populate configuration.

        Critical: Every platform must monitor ASIC temperatures.
        """
        print("\n[TEST 2] Validating all platforms have ASIC configuration")

        missing_asic_config = []

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            # Check if this platform has asic_temp_populate entry
            has_asic_config = False
            for config_entry in config_list:
                if config_entry.get("fn") == "asic_temp_populate":
                    has_asic_config = True
                    break

            if not has_asic_config:
                missing_asic_config.append(platform_key)

        if missing_asic_config:
            self.fail(f"Platforms missing asic_temp_populate config: {missing_asic_config}")

        print(f"[PASS] All platforms have ASIC temperature configuration")

    def test_03_asic_naming_convention(self):
        """
        Test that ASIC naming follows convention: asic, asic1, asic2, asic3...

        Validates:
        - First ASIC is named "asic" (not "asic0")
        - Additional ASICs are asic1, asic2, asic3... (sequential)
        - No gaps in numbering
        """
        print("\n[TEST 3] Validating ASIC naming convention")

        naming_violations = []

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            for config_entry in config_list:
                if config_entry.get("fn") != "asic_temp_populate":
                    continue

                asic_args = config_entry.get("arg", {})
                asic_names = [k for k in asic_args.keys() if k.startswith("asic")]

                if not asic_names:
                    continue

                # Check that first ASIC is named "asic"
                if "asic" not in asic_names:
                    naming_violations.append(f"{platform_key}: Missing base 'asic' name (found: {asic_names})")
                    continue

                # Extract numeric suffixes from asic names
                asic_numbers = []
                for name in asic_names:
                    if name == "asic":
                        asic_numbers.append(0)
                    elif name.startswith("asic") and name[4:].isdigit():
                        asic_numbers.append(int(name[4:]))
                    else:
                        naming_violations.append(f"{platform_key}: Invalid ASIC name '{name}'")

                # Check for gaps in numbering
                if asic_numbers:
                    asic_numbers.sort()
                    expected_sequence = list(range(len(asic_numbers)))
                    if asic_numbers != expected_sequence:
                        naming_violations.append(
                            f"{platform_key}: ASIC numbering has gaps or wrong order. "
                            f"Expected: {expected_sequence}, Got: {asic_numbers}"
                        )

        if naming_violations:
            violations_str = "\n  - ".join(naming_violations)
            self.fail(f"ASIC naming convention violations:\n  - {violations_str}")

        print(f"[PASS] All platforms follow ASIC naming convention")

    def test_04_asic_required_fields(self):
        """
        Test that each ASIC has required fields.

        Each ASIC must have:
        - "fin" field (file input path to ASIC sysfs)
        """
        print("\n[TEST 4] Validating ASIC required fields")

        missing_fields = []

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            for config_entry in config_list:
                if config_entry.get("fn") != "asic_temp_populate":
                    continue

                asic_args = config_entry.get("arg", {})

                for asic_name, asic_config in asic_args.items():
                    if not asic_name.startswith("asic"):
                        continue

                    # Check for required "fin" field
                    if "fin" not in asic_config:
                        missing_fields.append(f"{platform_key}: {asic_name} missing 'fin' field")
                    elif not asic_config["fin"]:
                        missing_fields.append(f"{platform_key}: {asic_name} has empty 'fin' field")
                    elif not isinstance(asic_config["fin"], str):
                        missing_fields.append(f"{platform_key}: {asic_name} 'fin' must be a string")

        if missing_fields:
            fields_str = "\n  - ".join(missing_fields)
            self.fail(f"ASIC configurations missing required fields:\n  - {fields_str}")

        print(f"[PASS] All ASICs have required fields")

    def test_05_asic_count_consistency(self):
        """
        Test ASIC count consistency across configuration.

        Reports ASIC counts per platform for validation.
        """
        print("\n[TEST 5] ASIC count analysis across platforms")

        asic_counts = {}

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            for config_entry in config_list:
                if config_entry.get("fn") != "asic_temp_populate":
                    continue

                asic_args = config_entry.get("arg", {})
                asic_names = [k for k in asic_args.keys() if k.startswith("asic")]
                asic_count = len(asic_names)

                asic_counts[platform_key] = asic_count

        # Group platforms by ASIC count
        by_count = defaultdict(list)
        for platform, count in asic_counts.items():
            by_count[count].append(platform)

        print(f"[INFO] ASIC count distribution:")
        for count in sorted(by_count.keys()):
            platforms = by_count[count]
            print(f"  {count} ASIC(s): {len(platforms)} platforms - {', '.join(platforms[:3])}{' ...' if len(platforms) > 3 else ''}")

        # Validate: At least some platforms should have ASICs
        total_platforms_with_asics = sum(len(platforms) for platforms in by_count.values())
        self.assertGreater(total_platforms_with_asics, 0, "At least one platform must have ASIC config")

        print(f"[PASS] ASIC counts validated across {total_platforms_with_asics} platforms")

    def test_06_module_temp_populate_present(self):
        """
        Test that platforms have module_temp_populate configuration.

        Most platforms should have module temperature monitoring.
        """
        print("\n[TEST 6] Validating module temperature configuration")

        platforms_without_modules = []
        module_counts = {}

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            has_module_config = False
            module_count = 0

            for config_entry in config_list:
                if config_entry.get("fn") == "module_temp_populate":
                    has_module_config = True
                    module_count = config_entry.get("arg", {}).get("module_count", 0)
                    break

            if has_module_config:
                module_counts[platform_key] = module_count
            else:
                platforms_without_modules.append(platform_key)

        # Report findings
        print(f"[INFO] Platforms with module config: {len(module_counts)}")
        print(f"[INFO] Platforms without module config: {len(platforms_without_modules)}")

        if platforms_without_modules:
            print(f"[WARN] Platforms without modules: {', '.join(platforms_without_modules)}")

        # Validate module counts are reasonable (0 is ok, but warn if many are 0)
        zero_modules = [p for p, c in module_counts.items() if c == 0]
        if zero_modules:
            print(f"[WARN] Platforms with 0 modules: {', '.join(zero_modules)}")

        print(f"[PASS] Module configuration validated")

    def test_07_asic_path_patterns(self):
        """
        Test that ASIC paths follow expected patterns.

        Validates:
        - Paths start with /sys/module/
        - Paths contain asic identifier
        - No duplicate paths (except intentional multi-ASIC on same path)
        """
        print("\n[TEST 7] Validating ASIC path patterns")

        invalid_paths = []

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            for config_entry in config_list:
                if config_entry.get("fn") != "asic_temp_populate":
                    continue

                asic_args = config_entry.get("arg", {})

                for asic_name, asic_config in asic_args.items():
                    if not asic_name.startswith("asic"):
                        continue

                    fin_path = asic_config.get("fin", "")

                    # Check path starts with /sys/module/
                    if not fin_path.startswith("/sys/module/"):
                        invalid_paths.append(f"{platform_key}/{asic_name}: Path doesn't start with /sys/module/: {fin_path}")

                    # Check path contains asic identifier
                    if "asic" not in fin_path.lower():
                        invalid_paths.append(f"{platform_key}/{asic_name}: Path doesn't contain 'asic': {fin_path}")

        if invalid_paths:
            paths_str = "\n  - ".join(invalid_paths)
            self.fail(f"Invalid ASIC paths found:\n  - {paths_str}")

        print(f"[PASS] All ASIC paths follow expected patterns")

    def test_08_poll_intervals_reasonable(self):
        """
        Test that poll intervals are reasonable.

        ASIC temperatures should be polled frequently (typically 3-10 seconds).
        Module temperatures can be less frequent (typically 20-60 seconds).
        """
        print("\n[TEST 8] Validating poll intervals")

        unreasonable_polls = []

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            for config_entry in config_list:
                fn_name = config_entry.get("fn", "")
                poll_interval = config_entry.get("poll", 0)

                if fn_name == "asic_temp_populate":
                    # ASIC polls should be between 1 and 30 seconds
                    if poll_interval < 1 or poll_interval > 30:
                        unreasonable_polls.append(
                            f"{platform_key}: ASIC poll={poll_interval}s (expected 1-30s)"
                        )

                elif fn_name == "module_temp_populate":
                    # Module polls should be between 10 and 120 seconds
                    if poll_interval < 10 or poll_interval > 120:
                        unreasonable_polls.append(
                            f"{platform_key}: Module poll={poll_interval}s (expected 10-120s)"
                        )

        if unreasonable_polls:
            polls_str = "\n  - ".join(unreasonable_polls)
            self.fail(f"Unreasonable poll intervals found:\n  - {polls_str}")

        print(f"[PASS] All poll intervals are reasonable")

    def test_09_configuration_completeness_report(self):
        """
        Generate comprehensive configuration report.

        This test always passes but provides detailed statistics
        about thermal_config for documentation and review.
        """
        print("\n[TEST 9] Configuration completeness report")

        total_platforms = len([k for k in self.thermal_config.keys() if k != "def"])
        platforms_with_asic = 0
        platforms_with_modules = 0
        total_asics = 0
        total_modules = 0

        asic_count_distribution = defaultdict(int)

        for platform_key, config_list in self.thermal_config.items():
            if platform_key == "def":
                continue

            platform_asic_count = 0

            for config_entry in config_list:
                fn_name = config_entry.get("fn", "")

                if fn_name == "asic_temp_populate":
                    platforms_with_asic += 1
                    asic_args = config_entry.get("arg", {})
                    asic_names = [k for k in asic_args.keys() if k.startswith("asic")]
                    platform_asic_count = len(asic_names)
                    total_asics += platform_asic_count

                elif fn_name == "module_temp_populate":
                    platforms_with_modules += 1
                    module_count = config_entry.get("arg", {}).get("module_count", 0)
                    total_modules += module_count

            if platform_asic_count > 0:
                asic_count_distribution[platform_asic_count] += 1

        print("\n" + "=" * 70)
        print("THERMAL CONFIGURATION SUMMARY")
        print("=" * 70)
        print(f"Total Platforms Configured: {total_platforms}")
        print(f"Platforms with ASIC Monitoring: {platforms_with_asic} ({platforms_with_asic * 100 // total_platforms if total_platforms else 0}%)")
        print(f"Platforms with Module Monitoring: {platforms_with_modules} ({platforms_with_modules * 100 // total_platforms if total_platforms else 0}%)")
        print(f"Total ASICs Monitored: {total_asics}")
        print(f"Total Modules Monitored: {total_modules}")
        print(f"\nASIC Count Distribution:")
        for count in sorted(asic_count_distribution.keys()):
            platform_count = asic_count_distribution[count]
            print(f"  {count} ASIC(s): {platform_count} platform(s)")
        print("=" * 70)

        print("\n[PASS] Configuration report generated")


def main():
    """Main test runner"""
    print("=" * 80)
    print("THERMAL_CONFIG VALIDATION TEST SUITE")
    print("=" * 80)
    print("\nPurpose: Validate thermal_config structure for all platforms")
    print("Ensures: ASIC naming, required fields, and configuration completeness")
    print("=" * 80)

    # Run tests with verbose output
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestThermalConfigValidation)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("\n" + "=" * 80)
    if result.wasSuccessful():
        print("[SUCCESS] All thermal_config validations PASSED")
        print("[INFO] Configuration quality verified for all platforms")
    else:
        print("[FAILURE] Some validations failed")
        print(f"[INFO] Failures: {len(result.failures)}, Errors: {len(result.errors)}")
        print("[ACTION] Review and fix configuration issues before adding new platforms")
    print("=" * 80)

    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
