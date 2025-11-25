#!/usr/bin/env python3
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
Test platform_config regex matching functionality

This test verifies that get_platform_config() and get_module_count()
correctly handle regex patterns in PLATFORM_CONFIG keys.

Bug: Previously, these functions used simple .get() which failed to match
     regex keys like "HI144|HI174". This test ensures the fix works.
"""

from hw_management_platform_config import (
    get_platform_config,
    get_module_count,
    PLATFORM_CONFIG
)
import sys
import os

# Add the usr/usr/bin directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../usr/usr/bin'))


def test_get_platform_config_exact_match():
    """Test exact match (non-regex keys like 'def', 'test')"""
    config = get_platform_config("def")
    assert config is not None, "Should find 'def' config"
    assert isinstance(config, list), "Config should be a list"


def test_get_platform_config_regex_match():
    """Test regex match for keys like 'HI144|HI174'"""
    # Test HI144 (first part of regex)
    config = get_platform_config("HI144")
    assert config is not None, "Should find config for HI144 via regex 'HI144|HI174'"
    assert isinstance(config, list), "Config should be a list"

    # Test HI174 (second part of regex)
    config = get_platform_config("HI174")
    assert config is not None, "Should find config for HI174 via regex 'HI144|HI174'"
    assert isinstance(config, list), "Config should be a list"


def test_get_platform_config_multiple_regex():
    """Test multiple regex patterns"""
    test_cases = [
        ("HI112", "HI112|HI116|HI136|MSN3700|MSN3700C"),
        ("HI116", "HI112|HI116|HI136|MSN3700|MSN3700C"),
        ("MSN3700", "HI112|HI116|HI136|MSN3700|MSN3700C"),
        ("HI122", "HI122|HI156|MSN4700"),
        ("MSN4700", "HI122|HI156|MSN4700"),
        ("HI123", "HI123|HI124"),
        ("HI124", "HI123|HI124"),
    ]

    for sku, expected_key in test_cases:
        config = get_platform_config(sku)
        assert config is not None, f"Should find config for {sku} via regex '{expected_key}'"
        assert isinstance(config, list), f"Config for {sku} should be a list"

        # Verify it matches the expected key's config
        expected_config = PLATFORM_CONFIG.get(expected_key)
        assert config == expected_config, f"Config for {sku} should match '{expected_key}'"


def test_get_platform_config_not_found():
    """Test that non-existent SKU returns empty list"""
    config = get_platform_config("NONEXISTENT_SKU_12345")
    assert config == [], "Should return empty list for non-existent SKU"


def test_get_module_count_regex():
    """Test get_module_count with regex keys"""
    # HI144|HI174 should have 65 modules
    count = get_module_count("HI144")
    assert count == 65, f"HI144 should have 65 modules, got {count}"

    count = get_module_count("HI174")
    assert count == 65, f"HI174 should have 65 modules, got {count}"

    # HI123|HI124 should have 64 modules
    count = get_module_count("HI123")
    assert count == 64, f"HI123 should have 64 modules, got {count}"

    count = get_module_count("HI124")
    assert count == 64, f"HI124 should have 64 modules, got {count}"


def test_get_module_count_single_key():
    """Test get_module_count with non-regex keys"""
    # HI120 should have 60 modules
    count = get_module_count("HI120")
    assert count == 60, f"HI120 should have 60 modules, got {count}"

    # HI121 should have 54 modules
    count = get_module_count("HI121")
    assert count == 54, f"HI121 should have 54 modules, got {count}"


def test_get_module_count_not_found():
    """Test get_module_count returns 0 for non-existent SKU"""
    count = get_module_count("NONEXISTENT_SKU_12345")
    assert count == 0, f"Should return 0 for non-existent SKU, got {count}"


if __name__ == "__main__":
    print("Running platform_config regex matching tests...")

    test_get_platform_config_exact_match()
    print("  PASS: test_get_platform_config_exact_match")

    test_get_platform_config_regex_match()
    print("  PASS: test_get_platform_config_regex_match")

    test_get_platform_config_multiple_regex()
    print("  PASS: test_get_platform_config_multiple_regex")

    test_get_platform_config_not_found()
    print("  PASS: test_get_platform_config_not_found")

    test_get_module_count_regex()
    print("  PASS: test_get_module_count_regex")

    test_get_module_count_single_key()
    print("  PASS: test_get_module_count_single_key")

    test_get_module_count_not_found()
    print("  PASS: test_get_module_count_not_found")

    print("\nAll tests passed!")
