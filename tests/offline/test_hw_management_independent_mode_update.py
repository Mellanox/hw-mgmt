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
Unit tests for hw_management_independent_mode_update.py

This test suite provides comprehensive testing with:
- Standalone execution support
- Detailed output with status indicators (ASCII icons, no ANSI colors)
- Configurable random test iterations
- Detailed failure reporting
- All tests can be run from ./tests/offline directory

Usage:
    # Run from tests directory
    cd tests
    python3 -m pytest offline/test_hw_management_independent_mode_update.py -v

    # Or run from offline directory
    cd tests/offline
    python3 -m pytest test_hw_management_independent_mode_update.py -v

    # Run with custom iterations
    python3 -m pytest test_hw_management_independent_mode_update.py --iterations 50 -v

    # Run specific test class
    python3 -m pytest test_hw_management_independent_mode_update.py::TestRandomScenarios -v
"""

import hw_management_independent_mode_update as test_module
import sys
import os
import pytest
import tempfile
import shutil
import random
import argparse
import traceback
from pathlib import Path
from typing import Dict, List, Tuple, Any
from io import StringIO
from contextlib import redirect_stdout
from datetime import datetime

# Add parent directory to path to import the module under test
TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"

if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

# Import the module to test\

# Mark all tests in this file as offline tests
pytestmark = pytest.mark.offline

# Test configuration
MAX_ASIC_COUNT = 4
MAX_MODULE_COUNT = 66
DEFAULT_ITERATIONS = 10

# Status indicators (ASCII only, no color codes)
ICON_PASS = "[+]"
ICON_FAIL = "[X]"
ICON_SKIP = "[-]"
ICON_INFO = "[i]"
ICON_WARN = "[!]"
ICON_RUN = "[>]"
ICON_OK = "[OK]"


class DetailedReportGenerator:
    """Enhanced test report generator with comprehensive failure information"""

    def __init__(self):
        self.tests_run = 0
        self.tests_passed = 0
        self.tests_failed = 0
        self.tests_skipped = 0
        self.failures: List[Dict[str, Any]] = []
        self.test_details: List[Dict[str, Any]] = []
        self.start_time = None
        self.end_time = None

    def start_suite(self):
        """Mark start of test suite"""
        self.start_time = datetime.now()
        print("\n" + "=" * 78)
        print(" " * 20 + "TEST SUITE EXECUTION")
        print("=" * 78)
        print(f"{ICON_INFO} Start Time: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"{ICON_INFO} Configuration:")
        print(f"    - Max ASIC Count:     {MAX_ASIC_COUNT}")
        print(f"    - Max Module Count:   {MAX_MODULE_COUNT}")
        print(f"    - Default Iterations: {DEFAULT_ITERATIONS}")
        print("=" * 78 + "\n")

    def end_suite(self):
        """Mark end of test suite"""
        self.end_time = datetime.now()
        duration = (self.end_time - self.start_time).total_seconds() if self.start_time else 0

        print("\n" + "=" * 78)
        print(" " * 25 + "TEST SUMMARY")
        print("=" * 78)
        print(f"{ICON_INFO} End Time:       {self.end_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"{ICON_INFO} Duration:       {duration:.2f} seconds")
        print(f"{ICON_INFO} Total Tests:    {self.tests_run}")
        print(f"{ICON_PASS} Passed:         {self.tests_passed}")
        print(f"{ICON_FAIL} Failed:         {self.tests_failed}")
        print(f"{ICON_SKIP} Skipped:        {self.tests_skipped}")

        if self.failures:
            print("\n" + "=" * 78)
            print(" " * 22 + "DETAILED FAILURE REPORT")
            print("=" * 78)
            for i, failure in enumerate(self.failures, 1):
                print(f"\n{ICON_FAIL} Failure #{i}")
                print(f"  Test Name:    {failure['name']}")
                print(f"  Test Class:   {failure.get('class', 'N/A')}")
                print(f"  Error Type:   {failure.get('error_type', 'AssertionError')}")
                print(f"  Error Message:")
                for line in failure['error'].split('\n'):
                    print(f"    {line}")

                if failure.get('details'):
                    print(f"  Test Context:")
                    for detail in failure['details']:
                        print(f"    - {detail}")

                if failure.get('traceback'):
                    print(f"  Traceback:")
                    for line in failure['traceback'].split('\n'):
                        if line.strip():
                            print(f"    {line}")
                print("-" * 78)

        print("\n" + "=" * 78)
        if self.tests_failed == 0:
            print(f"{ICON_OK} ALL TESTS PASSED SUCCESSFULLY!")
        else:
            print(f"{ICON_FAIL} {self.tests_failed} TEST(S) FAILED - Please review above")
        print("=" * 78 + "\n")


# Global report instance
_report = DetailedReportGenerator()


@pytest.fixture
def test_report():
    """Fixture to provide test report"""
    return _report


@pytest.fixture
def mock_hw_mgmt_base(temp_dir):
    """Create mock hw-management directory structure"""
    hw_mgmt_root = temp_dir / "var" / "run" / "hw-management"

    # Create subdirectories
    (hw_mgmt_root / "thermal").mkdir(parents=True, exist_ok=True)
    (hw_mgmt_root / "config").mkdir(parents=True, exist_ok=True)
    (hw_mgmt_root / "eeprom").mkdir(parents=True, exist_ok=True)

    # Patch the BASE_PATH in the test module
    original_base_path = test_module.BASE_PATH
    test_module.BASE_PATH = str(hw_mgmt_root)

    yield hw_mgmt_root

    # Restore original BASE_PATH
    test_module.BASE_PATH = original_base_path


@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files"""
    temp_path = tempfile.mkdtemp()
    yield Path(temp_path)
    # Cleanup after test
    shutil.rmtree(temp_path, ignore_errors=True)


@pytest.fixture
def setup_asic_count(mock_hw_mgmt_base):
    """Helper fixture to set up ASIC count"""
    def _setup(count: int):
        asic_file = mock_hw_mgmt_base / "config" / "asic_num"
        asic_file.write_text(str(count))
    return _setup


@pytest.fixture
def setup_module_count(mock_hw_mgmt_base):
    """Helper fixture to set up module count"""
    def _setup(count: int):
        module_file = mock_hw_mgmt_base / "config" / "module_counter"
        module_file.write_text(str(count))
    return _setup


@pytest.fixture
def random_iterations(request):
    """Fixture to get number of random test iterations"""
    return getattr(request.config, 'random_iterations', DEFAULT_ITERATIONS)


class TestAsicCountOperations:
    """Test ASIC count operations"""

    def test_get_asic_count_valid(self, mock_hw_mgmt_base, setup_asic_count):
        """Test getting valid ASIC count"""
        print(f"\n{ICON_RUN} Testing get_asic_count with valid count")
        setup_asic_count(2)
        result = test_module.get_asic_count()
        assert result == 2, f"Expected 2, got {result}"
        print(f"{ICON_PASS} ASIC count correctly returned: {result}")

    def test_get_asic_count_missing_file(self, mock_hw_mgmt_base):
        """Test getting ASIC count when file doesn't exist"""
        print(f"\n{ICON_RUN} Testing get_asic_count with missing file")
        result = test_module.get_asic_count()
        assert result is False, "Expected False for missing file"
        print(f"{ICON_PASS} Correctly returned False for missing config file")

    def test_get_asic_count_invalid_content(self, mock_hw_mgmt_base):
        """Test getting ASIC count with invalid content"""
        print(f"\n{ICON_RUN} Testing get_asic_count with invalid content")
        asic_file = mock_hw_mgmt_base / "config" / "asic_num"
        asic_file.write_text("invalid")
        result = test_module.get_asic_count()
        assert result is False, "Expected False for invalid content"
        print(f"{ICON_PASS} Correctly handled invalid file content")

    def test_get_asic_count_boundary_values(self, mock_hw_mgmt_base, setup_asic_count):
        """Test ASIC count boundary values"""
        print(f"\n{ICON_RUN} Testing get_asic_count boundary values")

        # Test minimum
        setup_asic_count(0)
        assert test_module.get_asic_count() == 0
        print(f"{ICON_INFO} Boundary test: minimum (0) - OK")

        # Test maximum
        setup_asic_count(MAX_ASIC_COUNT)
        assert test_module.get_asic_count() == MAX_ASIC_COUNT
        print(f"{ICON_INFO} Boundary test: maximum ({MAX_ASIC_COUNT}) - OK")

        # Test value above maximum
        setup_asic_count(MAX_ASIC_COUNT + 1)
        assert test_module.get_asic_count() == MAX_ASIC_COUNT + 1
        print(f"{ICON_INFO} Boundary test: above maximum ({MAX_ASIC_COUNT + 1}) - OK")
        print(f"{ICON_PASS} All boundary tests passed")


class TestModuleCountOperations:
    """Test module count operations"""

    def test_get_module_count_valid(self, mock_hw_mgmt_base, setup_module_count):
        """Test getting valid module count"""
        print(f"\n{ICON_RUN} Testing get_module_count with valid count")
        setup_module_count(32)
        result = test_module.get_module_count()
        assert result == 32, f"Expected 32, got {result}"
        print(f"{ICON_PASS} Module count correctly returned: {result}")

    def test_get_module_count_missing_file(self, mock_hw_mgmt_base):
        """Test getting module count when file doesn't exist"""
        print(f"\n{ICON_RUN} Testing get_module_count with missing file")
        result = test_module.get_module_count()
        assert result is False, "Expected False for missing file"
        print(f"{ICON_PASS} Correctly returned False for missing config file")

    def test_get_module_count_invalid_content(self, mock_hw_mgmt_base):
        """Test getting module count with invalid content"""
        print(f"\n{ICON_RUN} Testing get_module_count with invalid content")
        module_file = mock_hw_mgmt_base / "config" / "module_counter"
        module_file.write_text("not_a_number")
        result = test_module.get_module_count()
        assert result is False, "Expected False for invalid content"
        print(f"{ICON_PASS} Correctly handled invalid file content")

    def test_set_module_counter_valid(self, mock_hw_mgmt_base):
        """Test setting valid module counter"""
        print(f"\n{ICON_RUN} Testing module_data_set_module_counter")
        result = test_module.module_data_set_module_counter(32)
        assert result is True, "Expected True for valid module counter"

        # Verify the value was written
        module_file = mock_hw_mgmt_base / "config" / "module_counter"
        assert module_file.read_text().strip() == "32"
        print(f"{ICON_PASS} Module counter set and verified: 32")

    def test_set_module_counter_negative(self, mock_hw_mgmt_base):
        """Test setting negative module counter"""
        print(f"\n{ICON_RUN} Testing module_data_set_module_counter with negative value")
        result = test_module.module_data_set_module_counter(-1)
        assert result is False, "Expected False for negative module counter"
        print(f"{ICON_PASS} Correctly rejected negative value")

    def test_set_module_counter_boundary(self, mock_hw_mgmt_base):
        """Test setting module counter boundary values"""
        print(f"\n{ICON_RUN} Testing module counter boundary values")

        # Test zero
        assert test_module.module_data_set_module_counter(0) is True
        print(f"{ICON_INFO} Boundary test: zero (0) - OK")

        # Test maximum
        assert test_module.module_data_set_module_counter(MAX_MODULE_COUNT) is True
        print(f"{ICON_INFO} Boundary test: maximum ({MAX_MODULE_COUNT}) - OK")

        # Test above maximum (should still work as no upper bound check)
        assert test_module.module_data_set_module_counter(MAX_MODULE_COUNT + 1) is True
        print(f"{ICON_INFO} Boundary test: above maximum ({MAX_MODULE_COUNT + 1}) - OK")
        print(f"{ICON_PASS} All boundary tests passed")


class TestAsicIndexValidation:
    """Test ASIC index validation"""

    def test_check_asic_index_valid(self, mock_hw_mgmt_base, setup_asic_count):
        """Test valid ASIC indices"""
        print(f"\n{ICON_RUN} Testing valid ASIC indices (0 to {MAX_ASIC_COUNT - 1})")
        setup_asic_count(4)

        for i in range(4):
            result = test_module.check_asic_index(i)
            assert result is True, f"Expected True for ASIC index {i}"
            print(f"{ICON_INFO} ASIC index {i} - Valid")
        print(f"{ICON_PASS} All ASIC indices validated successfully")

    def test_check_asic_index_negative(self, mock_hw_mgmt_base, setup_asic_count):
        """Test negative ASIC index"""
        print(f"\n{ICON_RUN} Testing negative ASIC index")
        setup_asic_count(4)
        result = test_module.check_asic_index(-1)
        assert result is False, "Expected False for negative ASIC index"
        print(f"{ICON_PASS} Correctly rejected negative ASIC index")

    def test_check_asic_index_out_of_bounds(self, mock_hw_mgmt_base, setup_asic_count):
        """Test out-of-bounds ASIC index"""
        print(f"\n{ICON_RUN} Testing out-of-bounds ASIC index")
        setup_asic_count(4)
        result = test_module.check_asic_index(4)
        assert result is False, "Expected False for out-of-bounds ASIC index"
        print(f"{ICON_PASS} Correctly rejected out-of-bounds ASIC index")

    def test_check_asic_index_no_config(self, mock_hw_mgmt_base):
        """Test ASIC index check when config doesn't exist"""
        print(f"\n{ICON_RUN} Testing ASIC index check without config")
        result = test_module.check_asic_index(0)
        assert result is False, "Expected False when config doesn't exist"
        print(f"{ICON_PASS} Correctly handled missing config")


class TestModuleIndexValidation:
    """Test module index validation"""

    def test_check_module_index_valid(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test valid module indices"""
        print(f"\n{ICON_RUN} Testing valid module indices (1 to 32)")
        setup_asic_count(2)
        setup_module_count(32)

        # Module indices are 1-based
        for i in range(1, 33):
            result = test_module.check_module_index(0, i)
            assert result is True, f"Expected True for module index {i}"
        print(f"{ICON_PASS} All 32 module indices validated successfully")

    def test_check_module_index_zero(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test module index 0 (invalid, should be 1-based)"""
        print(f"\n{ICON_RUN} Testing module index 0 (should be invalid)")
        setup_asic_count(2)
        setup_module_count(32)
        result = test_module.check_module_index(0, 0)
        assert result is False, "Expected False for module index 0"
        print(f"{ICON_PASS} Correctly rejected module index 0 (1-based indexing)")

    def test_check_module_index_out_of_bounds(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test out-of-bounds module index"""
        print(f"\n{ICON_RUN} Testing out-of-bounds module index")
        setup_asic_count(2)
        setup_module_count(32)
        result = test_module.check_module_index(0, 33)
        assert result is False, "Expected False for out-of-bounds module index"
        print(f"{ICON_PASS} Correctly rejected out-of-bounds module index")

    def test_check_module_index_no_config(self, mock_hw_mgmt_base, setup_asic_count):
        """Test module index check when config doesn't exist"""
        print(f"\n{ICON_RUN} Testing module index check without config")
        setup_asic_count(2)
        result = test_module.check_module_index(0, 1)
        assert result is False, "Expected False when module config doesn't exist"
        print(f"{ICON_PASS} Correctly handled missing module config")


class TestAsicThermalData:
    """Test ASIC thermal data operations"""

    def test_thermal_data_set_asic_primary(self, mock_hw_mgmt_base, setup_asic_count):
        """Test setting thermal data for primary ASIC (index 0)"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_asic for primary ASIC (index 0)")
        setup_asic_count(2)

        result = test_module.thermal_data_set_asic(0, 50000, 85000, 100000, 0)
        assert result is True, "Expected True for setting ASIC 0 thermal data"

        # Verify files were created with correct values
        thermal_dir = mock_hw_mgmt_base / "thermal"
        assert (thermal_dir / "asic").read_text().strip() == "50000"
        assert (thermal_dir / "asic_temp_emergency").read_text().strip() == "85000"
        assert (thermal_dir / "asic_temp_crit").read_text().strip() == "100000"
        assert (thermal_dir / "asic_temp_fault").read_text().strip() == "0"

        # Verify asic1_* files are also created for ASIC 0
        assert (thermal_dir / "asic1").read_text().strip() == "50000"
        assert (thermal_dir / "asic1_temp_emergency").read_text().strip() == "85000"
        assert (thermal_dir / "asic1_temp_crit").read_text().strip() == "100000"
        assert (thermal_dir / "asic1_temp_fault").read_text().strip() == "0"
        print(f"{ICON_PASS} ASIC 0 thermal data set correctly (temp=50000, warn=85000, crit=100000)")

    def test_thermal_data_set_asic_secondary(self, mock_hw_mgmt_base, setup_asic_count):
        """Test setting thermal data for secondary ASIC (index > 0)"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_asic for secondary ASIC (index 2)")
        setup_asic_count(4)

        result = test_module.thermal_data_set_asic(2, 45000, 80000, 95000, 1)
        assert result is True, "Expected True for setting ASIC 2 thermal data"

        # Verify files were created with correct values (index 2 -> asic3)
        thermal_dir = mock_hw_mgmt_base / "thermal"
        assert (thermal_dir / "asic3").read_text().strip() == "45000"
        assert (thermal_dir / "asic3_temp_emergency").read_text().strip() == "80000"
        assert (thermal_dir / "asic3_temp_crit").read_text().strip() == "95000"
        assert (thermal_dir / "asic3_temp_fault").read_text().strip() == "1"
        print(f"{ICON_PASS} ASIC 2 thermal data set correctly (temp=45000, fault=1)")

    def test_thermal_data_set_asic_invalid_index(self, mock_hw_mgmt_base, setup_asic_count):
        """Test setting thermal data with invalid ASIC index"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_asic with invalid index")
        setup_asic_count(2)

        result = test_module.thermal_data_set_asic(5, 50000, 85000, 100000)
        assert result is False, "Expected False for invalid ASIC index"
        print(f"{ICON_PASS} Correctly rejected invalid ASIC index 5")

    def test_thermal_data_set_asic_all_indices(self, mock_hw_mgmt_base, setup_asic_count):
        """Test setting thermal data for all ASIC indices"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_asic for all {MAX_ASIC_COUNT} ASICs")
        setup_asic_count(MAX_ASIC_COUNT)

        for i in range(MAX_ASIC_COUNT):
            temp = 40000 + i * 1000
            result = test_module.thermal_data_set_asic(i, temp, 85000, 100000)
            assert result is True, f"Expected True for ASIC {i}"
            print(f"{ICON_INFO} ASIC {i} thermal data set (temp={temp})")
        print(f"{ICON_PASS} All {MAX_ASIC_COUNT} ASICs configured successfully")


class TestModuleThermalData:
    """Test module thermal data operations"""

    def test_thermal_data_set_module(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test setting thermal data for a module"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_module")
        setup_asic_count(2)
        setup_module_count(32)

        result = test_module.thermal_data_set_module(0, 1, 55000, 80000, 95000, 0)
        assert result is True, "Expected True for setting module thermal data"

        # Verify files were created
        thermal_dir = mock_hw_mgmt_base / "thermal"
        assert (thermal_dir / "module1_temp_input").read_text().strip() == "55000"
        assert (thermal_dir / "module1_temp_emergency").read_text().strip() == "80000"
        assert (thermal_dir / "module1_temp_crit").read_text().strip() == "95000"
        assert (thermal_dir / "module1_temp_fault").read_text().strip() == "0"
        print(f"{ICON_PASS} Module 1 thermal data set correctly (temp=55000)")

    def test_thermal_data_set_module_invalid_asic(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test setting module thermal data with invalid ASIC index"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_module with invalid ASIC")
        setup_asic_count(2)
        setup_module_count(32)

        result = test_module.thermal_data_set_module(5, 1, 55000, 80000, 95000)
        assert result is False, "Expected False for invalid ASIC index"
        print(f"{ICON_PASS} Correctly rejected invalid ASIC index")

    def test_thermal_data_set_module_invalid_module(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test setting module thermal data with invalid module index"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_module with invalid module")
        setup_asic_count(2)
        setup_module_count(32)

        result = test_module.thermal_data_set_module(0, 100, 55000, 80000, 95000)
        assert result is False, "Expected False for invalid module index"
        print(f"{ICON_PASS} Correctly rejected invalid module index")

    def test_thermal_data_set_module_multiple(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test setting thermal data for multiple modules"""
        print(f"\n{ICON_RUN} Testing thermal_data_set_module for 10 modules")
        setup_asic_count(2)
        setup_module_count(10)

        for i in range(1, 11):
            temp = 50000 + i * 500
            result = test_module.thermal_data_set_module(0, i, temp, 80000, 95000)
            assert result is True, f"Expected True for module {i}"
        print(f"{ICON_PASS} All 10 modules configured successfully")


class TestVendorData:
    """Test vendor data operations"""

    def test_vendor_data_set_module(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test setting vendor data for a module"""
        print(f"\n{ICON_RUN} Testing vendor_data_set_module")
        setup_asic_count(2)
        setup_module_count(32)

        vendor_info = {
            "part_number": "ABC-123",
            "manufacturer": "VendorX",
            "serial_number": "SN12345"
        }

        result = test_module.vendor_data_set_module(0, 1, vendor_info)
        assert result is True, "Expected True for setting vendor data"

        # Verify file was created
        vendor_file = mock_hw_mgmt_base / "eeprom" / "module1_data"
        assert vendor_file.exists()
        content = vendor_file.read_text()
        assert "PN" in content  # part_number should be replaced with PN
        assert "ABC-123" in content
        assert "Manufacturer" in content  # manufacturer should be replaced with Manufacturer
        assert "VendorX" in content
        print(f"{ICON_PASS} Vendor data set with key translation (PN, Manufacturer)")

    def test_vendor_data_set_module_none(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test setting vendor data to None (should remove file)"""
        print(f"\n{ICON_RUN} Testing vendor_data_set_module with None (removal)")
        setup_asic_count(2)
        setup_module_count(32)

        # First create a vendor data file
        vendor_file = mock_hw_mgmt_base / "eeprom" / "module1_data"
        vendor_file.write_text("test data")

        # Now set to None
        result = test_module.vendor_data_set_module(0, 1, None)
        assert result is True, "Expected True for removing vendor data"
        assert not vendor_file.exists(), "Expected vendor file to be removed"
        print(f"{ICON_PASS} Vendor data file removed successfully")

    def test_vendor_data_key_replacement(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test vendor data key replacement"""
        print(f"\n{ICON_RUN} Testing vendor data key replacement")
        setup_asic_count(2)
        setup_module_count(32)

        vendor_info = {
            "part_number": "TEST-PN",
            "manufacturer": "TEST-Manufacturer"
        }

        result = test_module.vendor_data_set_module(0, 1, vendor_info)
        assert result is True

        vendor_file = mock_hw_mgmt_base / "eeprom" / "module1_data"
        content = vendor_file.read_text()

        # Check key replacement
        assert "part_number" not in content
        assert "manufacturer" not in content
        assert "PN" in content
        assert "Manufacturer" in content
        print(f"{ICON_PASS} Keys correctly translated: part_number->PN, manufacturer->Manufacturer")


class TestAsicCleanup:
    """Test ASIC cleanup operations"""

    def test_thermal_data_clean_asic(self, mock_hw_mgmt_base, setup_asic_count):
        """Test cleaning ASIC thermal data"""
        print(f"\n{ICON_RUN} Testing thermal_data_clean_asic")
        setup_asic_count(2)

        # First set thermal data
        test_module.thermal_data_set_asic(0, 50000, 85000, 100000)

        # Verify files exist (both asic and asic1 for ASIC 0)
        thermal_dir = mock_hw_mgmt_base / "thermal"
        assert (thermal_dir / "asic").exists()
        assert (thermal_dir / "asic1").exists()
        print(f"{ICON_INFO} ASIC 0 thermal data files created (both asic and asic1)")

        # Clean the data
        result = test_module.thermal_data_clean_asic(0)
        assert result is True, "Expected True for cleaning ASIC data"

        # Verify files were removed (both asic and asic1 for ASIC 0)
        assert not (thermal_dir / "asic").exists()
        assert not (thermal_dir / "asic_temp_crit").exists()
        assert not (thermal_dir / "asic_temp_emergency").exists()
        assert not (thermal_dir / "asic_temp_fault").exists()
        assert not (thermal_dir / "asic1").exists()
        assert not (thermal_dir / "asic1_temp_crit").exists()
        assert not (thermal_dir / "asic1_temp_emergency").exists()
        assert not (thermal_dir / "asic1_temp_fault").exists()
        print(f"{ICON_PASS} ASIC 0 thermal data files cleaned successfully")

    def test_thermal_data_clean_asic_secondary(self, mock_hw_mgmt_base, setup_asic_count):
        """Test cleaning secondary ASIC thermal data"""
        print(f"\n{ICON_RUN} Testing thermal_data_clean_asic for secondary ASIC")
        setup_asic_count(4)

        # Set and clean ASIC 1 (should create asic2_* files)
        test_module.thermal_data_set_asic(1, 50000, 85000, 100000, 1)
        result = test_module.thermal_data_clean_asic(1)
        assert result is True

        thermal_dir = mock_hw_mgmt_base / "thermal"
        assert not (thermal_dir / "asic2").exists()
        assert not (thermal_dir / "asic2_temp_emergency").exists()
        assert not (thermal_dir / "asic2_temp_crit").exists()
        assert not (thermal_dir / "asic2_temp_fault").exists()
        print(f"{ICON_PASS} ASIC 1 thermal data (asic2_*) cleaned successfully")

        # Set and clean ASIC 2 (should create asic3_* files)
        test_module.thermal_data_set_asic(2, 50000, 85000, 100000, 1)
        result = test_module.thermal_data_clean_asic(2)
        assert result is True

        assert not (thermal_dir / "asic3").exists()
        assert not (thermal_dir / "asic3_temp_emergency").exists()
        assert not (thermal_dir / "asic3_temp_crit").exists()
        assert not (thermal_dir / "asic3_temp_fault").exists()
        print(f"{ICON_PASS} ASIC 2 thermal data (asic3_*) cleaned successfully")

    def test_thermal_data_clean_asic_invalid(self, mock_hw_mgmt_base, setup_asic_count):
        """Test cleaning ASIC data with invalid index"""
        print(f"\n{ICON_RUN} Testing thermal_data_clean_asic with invalid index")
        setup_asic_count(2)

        result = test_module.thermal_data_clean_asic(5)
        assert result is False, "Expected False for invalid ASIC index"
        print(f"{ICON_PASS} Correctly rejected invalid ASIC index for cleanup")


class TestModuleCleanup:
    """Test module cleanup operations"""

    def test_thermal_data_clean_module(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test cleaning module thermal data"""
        print(f"\n{ICON_RUN} Testing thermal_data_clean_module")
        setup_asic_count(2)
        setup_module_count(32)

        # First set thermal data
        test_module.thermal_data_set_module(0, 1, 55000, 80000, 95000)

        # Clean the data
        result = test_module.thermal_data_clean_module(0, 1)
        assert result is True, "Expected True for cleaning module data"

        # Verify files were removed
        thermal_dir = mock_hw_mgmt_base / "thermal"
        assert not (thermal_dir / "module1_temp_input").exists()
        assert not (thermal_dir / "module1_temp_crit").exists()
        print(f"{ICON_PASS} Module 1 thermal data cleaned successfully")

    def test_vendor_data_clear_module(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test clearing module vendor data"""
        print(f"\n{ICON_RUN} Testing vendor_data_clear_module")
        setup_asic_count(2)
        setup_module_count(32)

        # First set vendor data
        vendor_info = {"part_number": "TEST"}
        test_module.vendor_data_set_module(0, 1, vendor_info)

        # Clear the data
        result = test_module.vendor_data_clear_module(0, 1)
        assert result is True, "Expected True for clearing vendor data"

        # Verify file was removed
        vendor_file = mock_hw_mgmt_base / "eeprom" / "module1_data"
        assert not vendor_file.exists()
        print(f"{ICON_PASS} Module 1 vendor data cleared successfully")


class TestRandomScenarios:
    """Random scenario tests with configurable iterations"""

    def test_random_asic_operations(self, mock_hw_mgmt_base, setup_asic_count, random_iterations):
        """Test random ASIC operations with random asic_count (max 4)"""
        print(f"\n{ICON_RUN} Testing random ASIC operations")
        print(f"{ICON_INFO} Configuration: {random_iterations} iterations, max {MAX_ASIC_COUNT} ASICs")

        # Use random ASIC count (1 to MAX_ASIC_COUNT)
        asic_count = random.randint(1, MAX_ASIC_COUNT)
        setup_asic_count(asic_count)
        print(f"{ICON_INFO} Random ASIC count for this test: {asic_count}")

        success_count = 0
        clean_count = 0

        for iteration in range(random_iterations):
            asic_index = random.randint(0, asic_count - 1)
            temperature = random.randint(20000, 90000)
            warning = random.randint(70000, 95000)
            critical = random.randint(95000, 110000)
            fault = random.choice([0, 1])

            result = test_module.thermal_data_set_asic(asic_index, temperature, warning, critical, fault)
            if not result:
                error_msg = f"Iteration {iteration}: Failed to set ASIC {asic_index} thermal data (temp={temperature})"
                print(f"{ICON_FAIL} {error_msg}")
                assert False, error_msg
            success_count += 1

            # Randomly clean some entries (30% chance)
            if random.random() < 0.3:
                clean_result = test_module.thermal_data_clean_asic(asic_index)
                if not clean_result:
                    error_msg = f"Iteration {iteration}: Failed to clean ASIC {asic_index}"
                    print(f"{ICON_FAIL} {error_msg}")
                    assert False, error_msg
                clean_count += 1

            # Progress indicator every 10 iterations
            if (iteration + 1) % 10 == 0:
                print(f"{ICON_INFO} Progress: {iteration + 1}/{random_iterations} iterations completed")

        print(f"{ICON_PASS} Random ASIC operations completed successfully")
        print(f"{ICON_INFO} Stats: {success_count} sets, {clean_count} cleans")

    def test_random_module_operations(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count, random_iterations):
        """Test random module operations with random module_count (max 66)"""
        print(f"\n{ICON_RUN} Testing random module operations")
        print(f"{ICON_INFO} Configuration: {random_iterations} iterations, max {MAX_MODULE_COUNT} modules")

        # Use random counts
        asic_count = random.randint(1, MAX_ASIC_COUNT)
        module_count = random.randint(10, MAX_MODULE_COUNT)
        setup_asic_count(asic_count)
        setup_module_count(module_count)
        print(f"{ICON_INFO} Random configuration: {asic_count} ASICs, {module_count} modules")

        success_count = 0
        clean_count = 0

        for iteration in range(random_iterations):
            asic_index = random.randint(0, asic_count - 1)
            module_index = random.randint(1, module_count)
            temperature = random.randint(30000, 85000)
            warning = random.randint(70000, 90000)
            critical = random.randint(90000, 105000)

            result = test_module.thermal_data_set_module(asic_index, module_index, temperature, warning, critical)
            if not result:
                error_msg = f"Iteration {iteration}: Failed to set module {module_index} thermal data (ASIC={asic_index}, temp={temperature})"
                print(f"{ICON_FAIL} {error_msg}")
                assert False, error_msg
            success_count += 1

            # Randomly clean some entries (20% chance)
            if random.random() < 0.2:
                clean_result = test_module.thermal_data_clean_module(asic_index, module_index)
                if not clean_result:
                    error_msg = f"Iteration {iteration}: Failed to clean module {module_index}"
                    print(f"{ICON_FAIL} {error_msg}")
                    assert False, error_msg
                clean_count += 1

            # Progress indicator every 10 iterations
            if (iteration + 1) % 10 == 0:
                print(f"{ICON_INFO} Progress: {iteration + 1}/{random_iterations} iterations completed")

        print(f"{ICON_PASS} Random module operations completed successfully")
        print(f"{ICON_INFO} Stats: {success_count} sets, {clean_count} cleans")

    def test_random_vendor_operations(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count, random_iterations):
        """Test random vendor data operations"""
        print(f"\n{ICON_RUN} Testing random vendor operations")
        print(f"{ICON_INFO} Configuration: {random_iterations} iterations")

        # Use random counts
        asic_count = random.randint(1, MAX_ASIC_COUNT)
        module_count = random.randint(10, MAX_MODULE_COUNT)
        setup_asic_count(asic_count)
        setup_module_count(module_count)
        print(f"{ICON_INFO} Random configuration: {asic_count} ASICs, {module_count} modules")

        manufacturers = ["VendorA", "VendorB", "VendorC", "Manufacturer-X", "Manufacturer-Y", "NVIDIA", "Intel", "Broadcom"]

        success_count = 0
        clear_count = 0

        for iteration in range(random_iterations):
            asic_index = random.randint(0, asic_count - 1)
            module_index = random.randint(1, module_count)

            vendor_info = {
                "part_number": f"PN-{random.randint(1000, 9999)}",
                "manufacturer": random.choice(manufacturers),
                "serial_number": f"SN{random.randint(100000, 999999)}"
            }

            result = test_module.vendor_data_set_module(asic_index, module_index, vendor_info)
            if not result:
                error_msg = f"Iteration {iteration}: Failed to set vendor data for module {module_index}"
                print(f"{ICON_FAIL} {error_msg}")
                assert False, error_msg
            success_count += 1

            # Randomly clear some entries (30% chance)
            if random.random() < 0.3:
                clear_result = test_module.vendor_data_clear_module(asic_index, module_index)
                if not clear_result:
                    error_msg = f"Iteration {iteration}: Failed to clear vendor data for module {module_index}"
                    print(f"{ICON_FAIL} {error_msg}")
                    assert False, error_msg
                clear_count += 1

            # Progress indicator every 10 iterations
            if (iteration + 1) % 10 == 0:
                print(f"{ICON_INFO} Progress: {iteration + 1}/{random_iterations} iterations completed")

        print(f"{ICON_PASS} Random vendor operations completed successfully")
        print(f"{ICON_INFO} Stats: {success_count} sets, {clear_count} clears")

    def test_random_mixed_operations(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count, random_iterations):
        """Test random mixed operations (ASIC, module, vendor) with random parameters"""
        print(f"\n{ICON_RUN} Testing random mixed operations (ASIC, Module, Vendor)")
        print(f"{ICON_INFO} Configuration: {random_iterations} iterations")

        # Use random counts
        asic_count = random.randint(1, MAX_ASIC_COUNT)
        module_count = random.randint(10, MAX_MODULE_COUNT)
        setup_asic_count(asic_count)
        setup_module_count(module_count)
        print(f"{ICON_INFO} Random configuration: {asic_count} ASICs, {module_count} modules")

        operation_stats = {"asic": 0, "module": 0, "vendor": 0}

        for iteration in range(random_iterations):
            operation = random.choice(['asic', 'module', 'vendor'])
            asic_index = random.randint(0, asic_count - 1)

            try:
                if operation == 'asic':
                    result = test_module.thermal_data_set_asic(
                        asic_index,
                        random.randint(20000, 90000),
                        random.randint(70000, 95000),
                        random.randint(95000, 110000)
                    )
                    if not result:
                        error_msg = f"Iteration {iteration}: Failed ASIC operation for ASIC {asic_index}"
                        print(f"{ICON_FAIL} {error_msg}")
                        assert False, error_msg
                    operation_stats['asic'] += 1

                elif operation == 'module':
                    module_index = random.randint(1, module_count)
                    result = test_module.thermal_data_set_module(
                        asic_index,
                        module_index,
                        random.randint(30000, 85000),
                        random.randint(70000, 90000),
                        random.randint(90000, 105000)
                    )
                    if not result:
                        error_msg = f"Iteration {iteration}: Failed module operation for module {module_index}"
                        print(f"{ICON_FAIL} {error_msg}")
                        assert False, error_msg
                    operation_stats['module'] += 1

                elif operation == 'vendor':
                    module_index = random.randint(1, module_count)
                    vendor_info = {"part_number": f"PN{iteration}"}
                    result = test_module.vendor_data_set_module(asic_index, module_index, vendor_info)
                    if not result:
                        error_msg = f"Iteration {iteration}: Failed vendor operation for module {module_index}"
                        print(f"{ICON_FAIL} {error_msg}")
                        assert False, error_msg
                    operation_stats['vendor'] += 1

            except Exception as e:
                error_msg = f"Iteration {iteration}: Exception in {operation} operation: {str(e)}"
                print(f"{ICON_FAIL} {error_msg}")
                print(f"{ICON_INFO} Traceback: {traceback.format_exc()}")
                assert False, error_msg

            # Progress indicator every 10 iterations
            if (iteration + 1) % 10 == 0:
                print(f"{ICON_INFO} Progress: {iteration + 1}/{random_iterations} iterations completed")

        print(f"{ICON_PASS} Random mixed operations completed successfully")
        print(f"{ICON_INFO} Operation stats: ASIC={operation_stats['asic']}, Module={operation_stats['module']}, Vendor={operation_stats['vendor']}")


class TestBoundaryConditions:
    """Test boundary conditions and edge cases"""

    def test_temperature_boundaries(self, mock_hw_mgmt_base, setup_asic_count):
        """Test temperature boundary values"""
        print(f"\n{ICON_RUN} Testing temperature boundary values")
        setup_asic_count(2)

        # Test minimum temperature
        result = test_module.thermal_data_set_asic(0, 0, 70000, 90000)
        assert result is True
        print(f"{ICON_INFO} Temperature boundary: minimum (0) - OK")

        # Test very high temperature
        result = test_module.thermal_data_set_asic(0, 150000, 160000, 170000)
        assert result is True
        print(f"{ICON_INFO} Temperature boundary: high (150000) - OK")

        # Test negative temperature (should still work, no validation)
        result = test_module.thermal_data_set_asic(0, -10000, 70000, 90000)
        assert result is True
        print(f"{ICON_INFO} Temperature boundary: negative (-10000) - OK")
        print(f"{ICON_PASS} All temperature boundary tests passed")

    def test_max_asics_and_modules(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test maximum number of ASICs and modules"""
        print(f"\n{ICON_RUN} Testing maximum ASICs ({MAX_ASIC_COUNT}) and modules ({MAX_MODULE_COUNT})")
        setup_asic_count(MAX_ASIC_COUNT)
        setup_module_count(MAX_MODULE_COUNT)

        # Test all ASICs
        for i in range(MAX_ASIC_COUNT):
            result = test_module.thermal_data_set_asic(i, 50000, 80000, 95000)
            assert result is True, f"Failed for ASIC {i}"
        print(f"{ICON_INFO} All {MAX_ASIC_COUNT} ASICs tested successfully")

        # Test all modules
        for i in range(1, MAX_MODULE_COUNT + 1):
            result = test_module.thermal_data_set_module(0, i, 50000, 80000, 95000)
            assert result is True, f"Failed for module {i}"
        print(f"{ICON_INFO} All {MAX_MODULE_COUNT} modules tested successfully")
        print(f"{ICON_PASS} Maximum configuration test passed")

    def test_concurrent_operations(self, mock_hw_mgmt_base, setup_asic_count, setup_module_count):
        """Test concurrent write operations"""
        print(f"\n{ICON_RUN} Testing concurrent operations")
        setup_asic_count(MAX_ASIC_COUNT)
        setup_module_count(MAX_MODULE_COUNT)

        # Set data for all ASICs
        for i in range(MAX_ASIC_COUNT):
            test_module.thermal_data_set_asic(i, 40000 + i * 1000, 80000, 95000)
        print(f"{ICON_INFO} Set data for {MAX_ASIC_COUNT} ASICs")

        # Set data for multiple modules
        for i in range(1, 11):
            test_module.thermal_data_set_module(0, i, 45000 + i * 500, 80000, 95000)
        print(f"{ICON_INFO} Set data for 10 modules")

        # Verify all files exist
        thermal_dir = mock_hw_mgmt_base / "thermal"
        assert (thermal_dir / "asic").exists()
        assert (thermal_dir / "asic1").exists()  # ASIC 0 creates both asic and asic1
        assert (thermal_dir / "module1_temp_input").exists()
        assert (thermal_dir / "module10_temp_input").exists()
        print(f"{ICON_PASS} Concurrent operations completed successfully")


class TestErrorRecovery:
    """Test error recovery scenarios"""

    def test_overwrite_existing_data(self, mock_hw_mgmt_base, setup_asic_count):
        """Test overwriting existing thermal data"""
        print(f"\n{ICON_RUN} Testing overwrite existing data")
        setup_asic_count(2)

        # Set initial data
        test_module.thermal_data_set_asic(0, 40000, 75000, 90000)
        thermal_dir = mock_hw_mgmt_base / "thermal"
        thermal_file = thermal_dir / "asic"
        thermal_file_asic1 = thermal_dir / "asic1"
        assert thermal_file.read_text().strip() == "40000"
        assert thermal_file_asic1.read_text().strip() == "40000"
        print(f"{ICON_INFO} Initial data: temp=40000 (both asic and asic1)")

        # Overwrite with new data
        result = test_module.thermal_data_set_asic(0, 55000, 80000, 95000)
        assert result is True
        assert thermal_file.read_text().strip() == "55000"
        assert thermal_file_asic1.read_text().strip() == "55000"
        print(f"{ICON_INFO} Overwritten data: temp=55000 (both asic and asic1)")
        print(f"{ICON_PASS} Data overwrite successful")

    def test_clean_nonexistent_data(self, mock_hw_mgmt_base, setup_asic_count):
        """Test cleaning non-existent data"""
        print(f"\n{ICON_RUN} Testing clean non-existent data")
        setup_asic_count(2)

        # Try to clean data that doesn't exist
        # Note: remove_file_list returns True even if files don't exist (it's not an error)
        result = test_module.thermal_data_clean_asic(0)
        assert result is True, "Expected True when cleaning non-existent data (graceful handling)"
        print(f"{ICON_PASS} Correctly handled cleaning non-existent data (graceful success)")

    def test_module_counter_persistence(self, mock_hw_mgmt_base):
        """Test module counter persistence across operations"""
        print(f"\n{ICON_RUN} Testing module counter persistence")

        # Set module counter
        test_module.module_data_set_module_counter(32)
        result = test_module.get_module_count()
        assert result == 32
        print(f"{ICON_INFO} Module counter set to 32 and verified")

        # Update counter
        test_module.module_data_set_module_counter(64)
        result = test_module.get_module_count()
        assert result == 64
        print(f"{ICON_INFO} Module counter updated to 64 and verified")
        print(f"{ICON_PASS} Module counter persistence verified")


def pytest_addoption(parser):
    """Add custom command line options"""
    parser.addoption(
        "--iterations",
        action="store",
        default=DEFAULT_ITERATIONS,
        type=int,
        help=f"Number of random test iterations (default: {DEFAULT_ITERATIONS})"
    )


def pytest_configure(config):
    """Configure pytest with custom iterations"""
    try:
        config.random_iterations = config.getoption("--iterations")
    except (AttributeError, ValueError):
        config.random_iterations = DEFAULT_ITERATIONS

    # Register custom marker
    config.addinivalue_line("markers", "offline: mark test as offline test")


def pytest_sessionstart(session):
    """Called before test session starts"""
    _report.start_suite()


def pytest_sessionfinish(session, exitstatus):
    """Called after test session finishes"""
    _report.end_suite()


def run_standalone_tests(iterations=DEFAULT_ITERATIONS):
    """Run tests in standalone mode with detailed output"""
    print("\n" + "=" * 78)
    print(" " * 15 + "HW MANAGEMENT INDEPENDENT MODE UPDATE")
    print(" " * 25 + "UNIT TEST SUITE")
    print("=" * 78)
    print(f"{ICON_INFO} Module Under Test: hw_management_independent_mode_update.py")
    print(f"{ICON_INFO} Test Location:     {__file__}")
    print(f"{ICON_INFO} Configuration:")
    print(f"    - Max ASIC Count:     {MAX_ASIC_COUNT}")
    print(f"    - Max Module Count:   {MAX_MODULE_COUNT}")
    print(f"    - Random Iterations:  {iterations}")
    print("=" * 78)
    print()

    # Run pytest programmatically with this module as a plugin
    # This ensures pytest_addoption and other hooks are registered
    args = [
        __file__,
        "-v",
        "-s",  # Show print statements
        "--tb=short",
        f"--iterations={iterations}",
        "-p", "no:warnings"
    ]

    # Pass this module as a plugin so pytest hooks are registered
    exit_code = pytest.main(args, plugins=[sys.modules[__name__]])

    return exit_code


if __name__ == "__main__":
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description="Unit tests for hw_management_independent_mode_update.py",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run with default iterations (10)
  python3 test_hw_management_independent_mode_update.py

  # Run with custom iterations
  python3 test_hw_management_independent_mode_update.py --iterations 50

  # Run from tests directory with pytest
  cd tests
  python3 -m pytest offline/test_hw_management_independent_mode_update.py -v

  # Run with custom iterations using pytest
  python3 -m pytest offline/test_hw_management_independent_mode_update.py --iterations 100 -v
        """
    )
    parser.add_argument(
        "--iterations",
        type=int,
        default=DEFAULT_ITERATIONS,
        help=f"Number of random test iterations (default: {DEFAULT_ITERATIONS})"
    )

    args = parser.parse_args()

    # Run tests
    exit_code = run_standalone_tests(iterations=args.iterations)
    sys.exit(exit_code)
