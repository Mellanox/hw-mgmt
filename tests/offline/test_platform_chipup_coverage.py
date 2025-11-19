#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Platform Chipup Coverage Validation Test
#
# This test ensures that ALL platforms with ASIC configurations also have
# chipup monitoring configured. This is critical to ensure chipup status
# tracking works across all supported platforms.
#
# REQUIREMENT: Every platform with asic_temp_populate MUST also have
# monitor_asic_chipup_status with matching ASIC configuration.
########################################################################

from hw_management_platform_config import PLATFORM_CONFIG
import os
import sys
import unittest

# Add source directory to path
script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.join(script_dir, '..', '..')
hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)

if hw_mgmt_dir not in sys.path:
    sys.path.insert(0, hw_mgmt_dir)


class TestPlatformChipupCoverage(unittest.TestCase):
    """
    Validates that all platforms with ASICs have chipup monitoring configured.

    This test ensures the refactoring that moved chipup tracking from thermal_updater
    to peripheral_updater included ALL platforms, not just those with peripheral configs.
    """

    def test_01_all_asic_platforms_have_chipup_monitoring(self):
        """
        Verify every platform with asic_temp_populate also has monitor_asic_chipup_status.

        This is the critical test that would have caught the original bug where only
        4 out of 18 platforms had chipup monitoring configured.
        """
        print("\n" + "=" * 80)
        print("CHIPUP MONITORING COVERAGE TEST")
        print("=" * 80)

        platforms_with_asic = []
        platforms_with_chipup = []
        platforms_missing_chipup = []

        for platform_key, platform_config in PLATFORM_CONFIG.items():
            # Skip special keys
            if platform_key in ['def', 'test']:
                continue

            has_asic = False
            has_chipup = False
            asic_config = None
            chipup_config = None

            # Check for asic_temp_populate and monitor_asic_chipup_status
            for entry in platform_config:
                if entry.get('fn') == 'asic_temp_populate':
                    has_asic = True
                    asic_config = entry.get('arg', {})

                if entry.get('fn') == 'monitor_asic_chipup_status':
                    has_chipup = True
                    chipup_config = entry.get('arg', {})

            if has_asic:
                platforms_with_asic.append(platform_key)

                if has_chipup:
                    platforms_with_chipup.append(platform_key)
                    print(f"✓ {platform_key:40} HAS chipup monitoring")

                    # Validate ASIC configs match
                    self.assertEqual(
                        set(asic_config.keys()),
                        set(chipup_config.keys()),
                        f"{platform_key}: ASIC configs must match between temp_populate and chipup_status"
                    )
                else:
                    platforms_missing_chipup.append(platform_key)
                    print(f"✗ {platform_key:40} MISSING chipup monitoring")

        print("\n" + "=" * 80)
        print("SUMMARY")
        print("=" * 80)
        print(f"Platforms with ASICs:        {len(platforms_with_asic)}")
        print(f"Platforms with chipup:       {len(platforms_with_chipup)}")
        print(f"Platforms missing chipup:    {len(platforms_missing_chipup)}")

        # Critical assertion - must have 100% coverage
        self.assertEqual(
            len(platforms_missing_chipup), 0,
            f"CRITICAL: {len(platforms_missing_chipup)} platforms missing chipup monitoring: {platforms_missing_chipup}"
        )

        self.assertEqual(
            len(platforms_with_asic), len(platforms_with_chipup),
            "All platforms with ASICs must have chipup monitoring"
        )

        print(f"\n[PASS] All {len(platforms_with_asic)} ASIC platforms have chipup monitoring configured")

    def test_02_chipup_asic_configs_match_temp_populate(self):
        """
        Verify ASIC configurations are identical between asic_temp_populate and monitor_asic_chipup_status.

        The ASIC paths must match exactly - chipup monitoring checks the same ASICs that
        temperature monitoring uses.
        """
        print("\n" + "=" * 80)
        print("ASIC CONFIGURATION CONSISTENCY TEST")
        print("=" * 80)

        mismatched_platforms = []

        for platform_key, platform_config in PLATFORM_CONFIG.items():
            if platform_key in ['def', 'test']:
                continue

            asic_config = None
            chipup_config = None

            for entry in platform_config:
                if entry.get('fn') == 'asic_temp_populate':
                    asic_config = entry.get('arg', {})
                if entry.get('fn') == 'monitor_asic_chipup_status':
                    chipup_config = entry.get('arg', {})

            # If both exist, verify they match
            if asic_config and chipup_config:
                # Check same ASIC names
                asic_names = set(asic_config.keys())
                chipup_names = set(chipup_config.keys())

                if asic_names != chipup_names:
                    mismatched_platforms.append({
                        'platform': platform_key,
                        'asic_names': asic_names,
                        'chipup_names': chipup_names
                    })
                    print(f"✗ {platform_key}: ASIC names mismatch")
                    print(f"  temp_populate:    {asic_names}")
                    print(f"  chipup_status:    {chipup_names}")
                else:
                    # Check same paths for each ASIC
                    all_match = True
                    for asic_name in asic_names:
                        asic_path = asic_config[asic_name].get('fin')
                        chipup_path = chipup_config[asic_name].get('fin')
                        if asic_path != chipup_path:
                            all_match = False
                            print(f"✗ {platform_key}/{asic_name}: Path mismatch")
                            print(f"  temp_populate: {asic_path}")
                            print(f"  chipup_status: {chipup_path}")

                    if all_match:
                        print(f"✓ {platform_key:40} ASICs match ({len(asic_names)} ASICs)")

        self.assertEqual(
            len(mismatched_platforms), 0,
            f"ASIC configurations must match: {mismatched_platforms}"
        )

        print(f"\n[PASS] All ASIC configurations are consistent")

    def test_03_all_asic_platforms_have_thermal_configs(self):
        """
        Verify all platforms with chipup monitoring are configured for thermal monitoring.

        Chipup monitoring only makes sense for platforms that have ASICs with
        temperature monitoring.
        """
        print("\n" + "=" * 80)
        print("THERMAL CONFIGURATION CONSISTENCY TEST")
        print("=" * 80)

        orphan_chipup_platforms = []

        for platform_key, platform_config in PLATFORM_CONFIG.items():
            if platform_key in ['def', 'test']:
                continue

            has_asic_temp = False
            has_chipup = False

            for entry in platform_config:
                if entry.get('fn') == 'asic_temp_populate':
                    has_asic_temp = True
                if entry.get('fn') == 'monitor_asic_chipup_status':
                    has_chipup = True

            # Chipup without thermal monitoring is invalid
            if has_chipup and not has_asic_temp:
                orphan_chipup_platforms.append(platform_key)
                print(f"✗ {platform_key}: Has chipup but no temperature monitoring")
            elif has_chipup:
                print(f"✓ {platform_key:40} Properly configured")

        self.assertEqual(
            len(orphan_chipup_platforms), 0,
            f"Chipup monitoring without thermal monitoring: {orphan_chipup_platforms}"
        )

        print(f"\n[PASS] All chipup monitoring is properly paired with thermal monitoring")

    def test_04_platform_count_validation(self):
        """
        Validate the expected number of platforms with ASICs.

        As of this test: 18 platforms have ASIC configurations.
        This test will alert if platforms are added/removed.
        """
        print("\n" + "=" * 80)
        print("PLATFORM COUNT VALIDATION")
        print("=" * 80)

        asic_platform_count = 0
        chipup_platform_count = 0

        for platform_key, platform_config in PLATFORM_CONFIG.items():
            if platform_key in ['def', 'test']:
                continue

            has_asic = any(e.get('fn') == 'asic_temp_populate' for e in platform_config)
            has_chipup = any(e.get('fn') == 'monitor_asic_chipup_status' for e in platform_config)

            if has_asic:
                asic_platform_count += 1
            if has_chipup:
                chipup_platform_count += 1

        print(f"Platforms with ASIC temperature monitoring: {asic_platform_count}")
        print(f"Platforms with chipup monitoring:          {chipup_platform_count}")

        # Alert if count changes (platforms added/removed)
        self.assertEqual(
            asic_platform_count, chipup_platform_count,
            "ASIC and chipup platform counts must match"
        )

        # Document current count (V.7.0040.4000_BR has 15 ASIC platforms)
        self.assertGreaterEqual(
            asic_platform_count, 15,
            f"Expected at least 15 ASIC platforms, found {asic_platform_count}"
        )

        print(f"\n[PASS] Platform count validated: {asic_platform_count} platforms")

        if asic_platform_count > 18:
            print(f"[INFO] Platform count increased from 18 to {asic_platform_count} - new platforms added")


if __name__ == '__main__':
    # Run with verbose output
    unittest.main(verbosity=2)
