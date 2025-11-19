#!/usr/bin/env python3
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
