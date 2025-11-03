#!/usr/bin/env python3
# pylint: disable=line-too-long
# pylint: disable=C0103
# pylint: disable=W0718
"""
Comprehensive unit tests for hw_management_independent_mode_update.py

This test suite provides detailed testing with beautiful colored output
and comprehensive failure reporting.
"""

import os
import sys
import unittest
import tempfile
import shutil
import argparse
import random
import time
from io import StringIO
from contextlib import contextmanager

# Import the module to test
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hw_management_independent_mode_update as target_module


# ANSI Color codes (using standard ASCII)
class Colors:
    """Color definitions for terminal output."""
    RESET = '\033[0m'
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'


# Icons using ASCII characters only (no unicode)
class Icons:
    """ASCII icons for test output."""
    PASS = '[PASS]'
    FAIL = '[FAIL]'
    SKIP = '[SKIP]'
    INFO = '[INFO]'
    WARN = '[WARN]'
    ERROR = '[ERROR]'
    SUCCESS = '[OK]'
    RUNNING = '[RUN]'
    SUMMARY = '[====]'


class TestResult:
    """Container for detailed test results."""
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.errors = []
        self.start_time = time.time()
        
    def add_pass(self):
        """Add a passed test."""
        self.passed += 1
        
    def add_fail(self, test_name, error_msg, details=None):
        """Add a failed test with details."""
        self.failed += 1
        self.errors.append({
            'test': test_name,
            'error': error_msg,
            'details': details or {}
        })
        
    def add_skip(self):
        """Add a skipped test."""
        self.skipped += 1
        
    def get_duration(self):
        """Get test duration in seconds."""
        return time.time() - self.start_time
        
    def print_summary(self):
        """Print detailed test summary."""
        duration = self.get_duration()
        total = self.passed + self.failed + self.skipped
        
        print(f"\n{Colors.BOLD}{Icons.SUMMARY} TEST SUMMARY {Icons.SUMMARY}{Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 70}{Colors.RESET}")
        print(f"{Colors.GREEN}{Icons.SUCCESS} Passed:  {self.passed:3d} / {total}{Colors.RESET}")
        print(f"{Colors.RED}{Icons.FAIL} Failed:  {self.failed:3d} / {total}{Colors.RESET}")
        print(f"{Colors.YELLOW}{Icons.SKIP} Skipped: {self.skipped:3d} / {total}{Colors.RESET}")
        print(f"{Colors.CYAN}Duration: {duration:.2f} seconds{Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 70}{Colors.RESET}")
        
        if self.failed > 0:
            print(f"\n{Colors.RED}{Colors.BOLD}{Icons.ERROR} FAILURE DETAILS:{Colors.RESET}")
            print(f"{Colors.RED}{'=' * 70}{Colors.RESET}")
            for i, error in enumerate(self.errors, 1):
                print(f"\n{Colors.RED}{Icons.FAIL} Failure #{i}: {error['test']}{Colors.RESET}")
                print(f"{Colors.YELLOW}Error Message:{Colors.RESET} {error['error']}")
                if error['details']:
                    print(f"{Colors.YELLOW}Details:{Colors.RESET}")
                    for key, value in error['details'].items():
                        print(f"  - {key}: {value}")
            print(f"{Colors.RED}{'=' * 70}{Colors.RESET}")


@contextmanager
def capture_stdout():
    """Context manager to capture stdout."""
    old_stdout = sys.stdout
    sys.stdout = captured_output = StringIO()
    try:
        yield captured_output
    finally:
        sys.stdout = old_stdout


class TestHwManagementIndependentModeUpdate(unittest.TestCase):
    """Main test class for hw_management_independent_mode_update module."""
    
    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests."""
        cls.test_result = TestResult()
        cls.random_iterations = getattr(cls, 'random_iterations', 10)
        print(f"\n{Colors.BOLD}{Colors.CYAN}{Icons.INFO} Starting Test Suite{Colors.RESET}")
        print(f"{Colors.CYAN}Random test iterations: {cls.random_iterations}{Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 70}{Colors.RESET}\n")
        
    @classmethod
    def tearDownClass(cls):
        """Clean up and print summary after all tests."""
        cls.test_result.print_summary()
        
    def setUp(self):
        """Set up test environment before each test."""
        # Create temporary directory structure
        self.temp_dir = tempfile.mkdtemp()
        self.original_base_path = target_module.BASE_PATH
        target_module.BASE_PATH = self.temp_dir
        
        # Create required directory structure
        os.makedirs(os.path.join(self.temp_dir, "config"), exist_ok=True)
        os.makedirs(os.path.join(self.temp_dir, "thermal"), exist_ok=True)
        os.makedirs(os.path.join(self.temp_dir, "eeprom"), exist_ok=True)
        
        # Default configuration
        self.default_asic_count = 2
        self.default_module_count = 32
        self._create_config_files()
        
    def tearDown(self):
        """Clean up test environment after each test."""
        # Restore original base path
        target_module.BASE_PATH = self.original_base_path
        
        # Remove temporary directory
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)
            
    def _create_config_files(self):
        """Create configuration files for testing."""
        asic_file = os.path.join(self.temp_dir, "config", "asic_num")
        module_file = os.path.join(self.temp_dir, "config", "module_counter")
        
        with open(asic_file, 'w', encoding='utf-8') as f:
            f.write(str(self.default_asic_count))
            
        with open(module_file, 'w', encoding='utf-8') as f:
            f.write(str(self.default_module_count))
            
    def _print_test_start(self, test_name):
        """Print test start message."""
        print(f"{Colors.BLUE}{Icons.RUNNING} {test_name}{Colors.RESET}")
        
    def _print_test_pass(self, test_name):
        """Print test pass message."""
        print(f"{Colors.GREEN}{Icons.PASS} {test_name}{Colors.RESET}")
        self.test_result.add_pass()
        
    def _print_test_fail(self, test_name, error_msg, details=None):
        """Print test fail message."""
        print(f"{Colors.RED}{Icons.FAIL} {test_name}{Colors.RESET}")
        print(f"{Colors.RED}  Error: {error_msg}{Colors.RESET}")
        self.test_result.add_fail(test_name, error_msg, details)
        
    # ========================================================================
    # Test: get_asic_count
    # ========================================================================
    
    def test_get_asic_count_success(self):
        """Test successful retrieval of ASIC count."""
        test_name = "test_get_asic_count_success"
        self._print_test_start(test_name)
        
        try:
            result = target_module.get_asic_count()
            self.assertEqual(result, self.default_asic_count)
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'expected': self.default_asic_count,
                'actual': result if 'result' in locals() else 'N/A'
            })
            raise
            
    def test_get_asic_count_file_missing(self):
        """Test ASIC count retrieval when file is missing."""
        test_name = "test_get_asic_count_file_missing"
        self._print_test_start(test_name)
        
        try:
            # Remove the asic_num file
            asic_file = os.path.join(self.temp_dir, "config", "asic_num")
            os.remove(asic_file)
            
            with capture_stdout() as output:
                result = target_module.get_asic_count()
                
            self.assertFalse(result)
            self.assertIn("Could not read ASIC count", output.getvalue())
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'expected': False,
                'actual': result if 'result' in locals() else 'N/A'
            })
            raise
            
    def test_get_asic_count_invalid_content(self):
        """Test ASIC count retrieval with invalid file content."""
        test_name = "test_get_asic_count_invalid_content"
        self._print_test_start(test_name)
        
        try:
            # Write invalid content
            asic_file = os.path.join(self.temp_dir, "config", "asic_num")
            with open(asic_file, 'w', encoding='utf-8') as f:
                f.write("invalid")
                
            with capture_stdout() as output:
                result = target_module.get_asic_count()
                
            self.assertFalse(result)
            self.assertIn("Error reading asic count", output.getvalue())
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'expected': False,
                'actual': result if 'result' in locals() else 'N/A'
            })
            raise
            
    # ========================================================================
    # Test: get_module_count
    # ========================================================================
    
    def test_get_module_count_success(self):
        """Test successful retrieval of module count."""
        test_name = "test_get_module_count_success"
        self._print_test_start(test_name)
        
        try:
            result = target_module.get_module_count()
            self.assertEqual(result, self.default_module_count)
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'expected': self.default_module_count,
                'actual': result if 'result' in locals() else 'N/A'
            })
            raise
            
    def test_get_module_count_file_missing(self):
        """Test module count retrieval when file is missing."""
        test_name = "test_get_module_count_file_missing"
        self._print_test_start(test_name)
        
        try:
            # Remove the module_counter file
            module_file = os.path.join(self.temp_dir, "config", "module_counter")
            os.remove(module_file)
            
            with capture_stdout() as output:
                result = target_module.get_module_count()
                
            self.assertFalse(result)
            self.assertIn("Could not read module count", output.getvalue())
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'expected': False,
                'actual': result if 'result' in locals() else 'N/A'
            })
            raise
            
    # ========================================================================
    # Test: check_asic_index
    # ========================================================================
    
    def test_check_asic_index_valid(self):
        """Test ASIC index validation with valid indices."""
        test_name = "test_check_asic_index_valid"
        self._print_test_start(test_name)
        
        try:
            for i in range(self.default_asic_count):
                result = target_module.check_asic_index(i)
                self.assertTrue(result, f"Index {i} should be valid")
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'asic_count': self.default_asic_count,
                'tested_index': i if 'i' in locals() else 'N/A'
            })
            raise
            
    def test_check_asic_index_invalid(self):
        """Test ASIC index validation with invalid indices."""
        test_name = "test_check_asic_index_invalid"
        self._print_test_start(test_name)
        
        try:
            invalid_indices = [-1, self.default_asic_count, self.default_asic_count + 1, 100]
            for idx in invalid_indices:
                with capture_stdout():
                    result = target_module.check_asic_index(idx)
                self.assertFalse(result, f"Index {idx} should be invalid")
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'asic_count': self.default_asic_count,
                'tested_invalid_indices': invalid_indices
            })
            raise
            
    # ========================================================================
    # Test: check_module_index
    # ========================================================================
    
    def test_check_module_index_valid(self):
        """Test module index validation with valid indices."""
        test_name = "test_check_module_index_valid"
        self._print_test_start(test_name)
        
        try:
            for i in range(1, self.default_module_count + 1):
                result = target_module.check_module_index(0, i)
                self.assertTrue(result, f"Index {i} should be valid")
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_count': self.default_module_count,
                'tested_index': i if 'i' in locals() else 'N/A'
            })
            raise
            
    def test_check_module_index_invalid(self):
        """Test module index validation with invalid indices."""
        test_name = "test_check_module_index_invalid"
        self._print_test_start(test_name)
        
        try:
            invalid_indices = [-1, 0, self.default_module_count + 1, self.default_module_count + 10]
            for idx in invalid_indices:
                with capture_stdout():
                    result = target_module.check_module_index(0, idx)
                self.assertFalse(result, f"Index {idx} should be invalid")
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_count': self.default_module_count,
                'tested_invalid_indices': invalid_indices
            })
            raise
            
    # ========================================================================
    # Test: module_data_set_module_counter
    # ========================================================================
    
    def test_module_data_set_module_counter_success(self):
        """Test setting module counter successfully."""
        test_name = "test_module_data_set_module_counter_success"
        self._print_test_start(test_name)
        
        try:
            new_count = 64
            result = target_module.module_data_set_module_counter(new_count)
            self.assertTrue(result)
            
            # Verify the value was written
            written_count = target_module.get_module_count()
            self.assertEqual(written_count, new_count)
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'expected_count': new_count,
                'actual_count': written_count if 'written_count' in locals() else 'N/A'
            })
            raise
            
    def test_module_data_set_module_counter_negative(self):
        """Test setting module counter with negative value."""
        test_name = "test_module_data_set_module_counter_negative"
        self._print_test_start(test_name)
        
        try:
            with capture_stdout() as output:
                result = target_module.module_data_set_module_counter(-1)
                
            self.assertFalse(result)
            self.assertIn("Could not set module count", output.getvalue())
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'input_value': -1,
                'expected_result': False
            })
            raise
            
    # ========================================================================
    # Test: thermal_data_set_asic
    # ========================================================================
    
    def test_thermal_data_set_asic_index_0(self):
        """Test setting thermal data for ASIC index 0."""
        test_name = "test_thermal_data_set_asic_index_0"
        self._print_test_start(test_name)
        
        try:
            temp = 55000
            warn = 85000
            crit = 95000
            fault = 0
            
            result = target_module.thermal_data_set_asic(0, temp, warn, crit, fault)
            self.assertTrue(result)
            
            # Verify files were created with correct values
            thermal_dir = os.path.join(self.temp_dir, "thermal")
            
            with open(os.path.join(thermal_dir, "asic"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(temp))
            with open(os.path.join(thermal_dir, "asic_temp_emergency"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(warn))
            with open(os.path.join(thermal_dir, "asic_temp_crit"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(crit))
            with open(os.path.join(thermal_dir, "asic_temp_fault"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(fault))
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'asic_index': 0,
                'temperature': temp,
                'warning': warn,
                'critical': crit
            })
            raise
            
    def test_thermal_data_set_asic_index_1(self):
        """Test setting thermal data for ASIC index 1."""
        test_name = "test_thermal_data_set_asic_index_1"
        self._print_test_start(test_name)
        
        try:
            temp = 60000
            warn = 85000
            crit = 95000
            
            result = target_module.thermal_data_set_asic(1, temp, warn, crit)
            self.assertTrue(result)
            
            # Verify files were created with correct values
            thermal_dir = os.path.join(self.temp_dir, "thermal")
            
            with open(os.path.join(thermal_dir, "asic2"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(temp))
            with open(os.path.join(thermal_dir, "asic2_temp_emergency"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(warn))
            with open(os.path.join(thermal_dir, "asic2_temp_crit"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(crit))
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'asic_index': 1,
                'temperature': temp,
                'warning': warn,
                'critical': crit
            })
            raise
            
    def test_thermal_data_set_asic_invalid_index(self):
        """Test setting thermal data with invalid ASIC index."""
        test_name = "test_thermal_data_set_asic_invalid_index"
        self._print_test_start(test_name)
        
        try:
            with capture_stdout():
                result = target_module.thermal_data_set_asic(99, 50000, 85000, 95000)
            self.assertFalse(result)
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'asic_index': 99,
                'expected_result': False
            })
            raise
            
    # ========================================================================
    # Test: thermal_data_set_module
    # ========================================================================
    
    def test_thermal_data_set_module_success(self):
        """Test setting thermal data for module."""
        test_name = "test_thermal_data_set_module_success"
        self._print_test_start(test_name)
        
        try:
            module_idx = 1
            temp = 45000
            warn = 75000
            crit = 85000
            
            result = target_module.thermal_data_set_module(0, module_idx, temp, warn, crit)
            self.assertTrue(result)
            
            # Verify files were created
            thermal_dir = os.path.join(self.temp_dir, "thermal")
            
            with open(os.path.join(thermal_dir, f"module{module_idx}_temp_input"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(temp))
            with open(os.path.join(thermal_dir, f"module{module_idx}_temp_emergency"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(warn))
            with open(os.path.join(thermal_dir, f"module{module_idx}_temp_crit"), 'r', encoding='utf-8') as f:
                self.assertEqual(f.read(), str(crit))
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_index': module_idx,
                'temperature': temp,
                'warning': warn,
                'critical': crit
            })
            raise
            
    def test_thermal_data_set_module_invalid_index(self):
        """Test setting thermal data with invalid module index."""
        test_name = "test_thermal_data_set_module_invalid_index"
        self._print_test_start(test_name)
        
        try:
            with capture_stdout():
                result = target_module.thermal_data_set_module(0, 0, 50000, 75000, 85000)
            self.assertFalse(result)
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_index': 0,
                'expected_result': False
            })
            raise
            
    # ========================================================================
    # Test: vendor_data_set_module
    # ========================================================================
    
    def test_vendor_data_set_module_with_data(self):
        """Test setting vendor data for module."""
        test_name = "test_vendor_data_set_module_with_data"
        self._print_test_start(test_name)
        
        try:
            module_idx = 1
            vendor_info = {
                "part_number": "PN12345",
                "manufacturer": "ACME Corp",
                "serial": "SN67890"
            }
            
            result = target_module.vendor_data_set_module(0, module_idx, vendor_info)
            self.assertTrue(result)
            
            # Verify file was created
            vendor_file = os.path.join(self.temp_dir, "eeprom", f"module{module_idx}_data")
            self.assertTrue(os.path.exists(vendor_file))
            
            with open(vendor_file, 'r', encoding='utf-8') as f:
                content = f.read()
                self.assertIn("PN", content)
                self.assertIn("PN12345", content)
                self.assertIn("MFG", content)
                self.assertIn("ACME Corp", content)
                self.assertIn("serial", content)
                self.assertIn("SN67890", content)
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_index': module_idx,
                'vendor_info': vendor_info
            })
            raise
            
    def test_vendor_data_set_module_clear(self):
        """Test clearing vendor data for module."""
        test_name = "test_vendor_data_set_module_clear"
        self._print_test_start(test_name)
        
        try:
            module_idx = 1
            vendor_file = os.path.join(self.temp_dir, "eeprom", f"module{module_idx}_data")
            
            # Create a file first
            with open(vendor_file, 'w', encoding='utf-8') as f:
                f.write("test data")
                
            # Clear it by passing None
            result = target_module.vendor_data_set_module(0, module_idx, None)
            self.assertTrue(result)
            
            # Verify file was removed
            self.assertFalse(os.path.exists(vendor_file))
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_index': module_idx,
                'operation': 'clear'
            })
            raise
            
    # ========================================================================
    # Test: thermal_data_clean_asic
    # ========================================================================
    
    def test_thermal_data_clean_asic_success(self):
        """Test cleaning thermal data for ASIC."""
        test_name = "test_thermal_data_clean_asic_success"
        self._print_test_start(test_name)
        
        try:
            asic_idx = 0
            
            # Create thermal data first
            target_module.thermal_data_set_asic(asic_idx, 50000, 85000, 95000)
            
            # Clean it
            result = target_module.thermal_data_clean_asic(asic_idx)
            self.assertTrue(result)
            
            # Verify files were removed
            thermal_dir = os.path.join(self.temp_dir, "thermal")
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, "asic")))
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, "asic_temp_crit")))
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, "asic_temp_emergency")))
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, "asic_temp_fault")))
            
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'asic_index': asic_idx
            })
            raise
            
    # ========================================================================
    # Test: thermal_data_clean_module
    # ========================================================================
    
    def test_thermal_data_clean_module_success(self):
        """Test cleaning thermal data for module."""
        test_name = "test_thermal_data_clean_module_success"
        self._print_test_start(test_name)
        
        try:
            module_idx = 1
            
            # Create thermal data first
            target_module.thermal_data_set_module(0, module_idx, 50000, 75000, 85000)
            
            # Clean it
            result = target_module.thermal_data_clean_module(0, module_idx)
            self.assertTrue(result)
            
            # Verify files were removed
            thermal_dir = os.path.join(self.temp_dir, "thermal")
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, f"module{module_idx}_temp_input")))
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, f"module{module_idx}_temp_crit")))
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, f"module{module_idx}_temp_emergency")))
            self.assertFalse(os.path.exists(os.path.join(thermal_dir, f"module{module_idx}_temp_fault")))
            
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_index': module_idx
            })
            raise
            
    # ========================================================================
    # Test: vendor_data_clear_module
    # ========================================================================
    
    def test_vendor_data_clear_module_success(self):
        """Test clearing vendor data for module."""
        test_name = "test_vendor_data_clear_module_success"
        self._print_test_start(test_name)
        
        try:
            module_idx = 1
            
            # Create vendor data first
            vendor_info = {"part_number": "PN12345"}
            target_module.vendor_data_set_module(0, module_idx, vendor_info)
            
            # Clear it
            result = target_module.vendor_data_clear_module(0, module_idx)
            self.assertTrue(result)
            
            # Verify file was removed
            vendor_file = os.path.join(self.temp_dir, "eeprom", f"module{module_idx}_data")
            self.assertFalse(os.path.exists(vendor_file))
            
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'module_index': module_idx
            })
            raise
            
    # ========================================================================
    # Random Tests - Run multiple iterations with random data
    # ========================================================================
    
    def test_random_asic_thermal_operations(self):
        """Test random ASIC thermal operations with multiple iterations."""
        test_name = f"test_random_asic_thermal_operations (N={self.random_iterations})"
        self._print_test_start(test_name)
        
        try:
            for iteration in range(self.random_iterations):
                asic_idx = random.randint(0, self.default_asic_count - 1)
                temp = random.randint(20000, 100000)
                warn = random.randint(temp, 110000)
                crit = random.randint(warn, 120000)
                fault = random.choice([0, 1])
                
                # Set thermal data
                result = target_module.thermal_data_set_asic(asic_idx, temp, warn, crit, fault)
                self.assertTrue(result, f"Iteration {iteration}: Failed to set thermal data")
                
                # Verify data
                thermal_dir = os.path.join(self.temp_dir, "thermal")
                if asic_idx == 0:
                    temp_file = os.path.join(thermal_dir, "asic")
                else:
                    temp_file = os.path.join(thermal_dir, f"asic{asic_idx + 1}")
                    
                with open(temp_file, 'r', encoding='utf-8') as f:
                    read_temp = int(f.read())
                    self.assertEqual(read_temp, temp, 
                                     f"Iteration {iteration}: Temperature mismatch")
                
                # Clean data
                result = target_module.thermal_data_clean_asic(asic_idx)
                self.assertTrue(result, f"Iteration {iteration}: Failed to clean thermal data")
                self.assertFalse(os.path.exists(temp_file), 
                                 f"Iteration {iteration}: File still exists after cleanup")
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'iteration': iteration if 'iteration' in locals() else 'N/A',
                'asic_index': asic_idx if 'asic_idx' in locals() else 'N/A',
                'temperature': temp if 'temp' in locals() else 'N/A',
                'total_iterations': self.random_iterations
            })
            raise
            
    def test_random_module_thermal_operations(self):
        """Test random module thermal operations with multiple iterations."""
        test_name = f"test_random_module_thermal_operations (N={self.random_iterations})"
        self._print_test_start(test_name)
        
        try:
            for iteration in range(self.random_iterations):
                module_idx = random.randint(1, self.default_module_count)
                temp = random.randint(20000, 90000)
                warn = random.randint(temp, 100000)
                crit = random.randint(warn, 110000)
                
                # Set thermal data
                result = target_module.thermal_data_set_module(0, module_idx, temp, warn, crit)
                self.assertTrue(result, f"Iteration {iteration}: Failed to set thermal data")
                
                # Verify data
                thermal_dir = os.path.join(self.temp_dir, "thermal")
                temp_file = os.path.join(thermal_dir, f"module{module_idx}_temp_input")
                    
                with open(temp_file, 'r', encoding='utf-8') as f:
                    read_temp = int(f.read())
                    self.assertEqual(read_temp, temp, 
                                     f"Iteration {iteration}: Temperature mismatch")
                
                # Clean data
                result = target_module.thermal_data_clean_module(0, module_idx)
                self.assertTrue(result, f"Iteration {iteration}: Failed to clean thermal data")
                self.assertFalse(os.path.exists(temp_file), 
                                 f"Iteration {iteration}: File still exists after cleanup")
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'iteration': iteration if 'iteration' in locals() else 'N/A',
                'module_index': module_idx if 'module_idx' in locals() else 'N/A',
                'temperature': temp if 'temp' in locals() else 'N/A',
                'total_iterations': self.random_iterations
            })
            raise
            
    def test_random_vendor_data_operations(self):
        """Test random vendor data operations with multiple iterations."""
        test_name = f"test_random_vendor_data_operations (N={self.random_iterations})"
        self._print_test_start(test_name)
        
        try:
            manufacturers = ["NVIDIA", "Mellanox", "ACME Corp", "Test Inc", "Vendor Co"]
            
            for iteration in range(self.random_iterations):
                module_idx = random.randint(1, self.default_module_count)
                
                # Generate random vendor info
                vendor_info = {
                    "part_number": f"PN{random.randint(10000, 99999)}",
                    "manufacturer": random.choice(manufacturers),
                    "serial": f"SN{random.randint(100000, 999999)}",
                    "revision": f"Rev{random.randint(1, 10)}"
                }
                
                # Set vendor data
                result = target_module.vendor_data_set_module(0, module_idx, vendor_info)
                self.assertTrue(result, f"Iteration {iteration}: Failed to set vendor data")
                
                # Verify file exists
                vendor_file = os.path.join(self.temp_dir, "eeprom", f"module{module_idx}_data")
                self.assertTrue(os.path.exists(vendor_file), 
                                f"Iteration {iteration}: Vendor file not created")
                
                # Clear data
                result = target_module.vendor_data_clear_module(0, module_idx)
                self.assertTrue(result, f"Iteration {iteration}: Failed to clear vendor data")
                self.assertFalse(os.path.exists(vendor_file), 
                                 f"Iteration {iteration}: File still exists after cleanup")
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'iteration': iteration if 'iteration' in locals() else 'N/A',
                'module_index': module_idx if 'module_idx' in locals() else 'N/A',
                'vendor_info': vendor_info if 'vendor_info' in locals() else 'N/A',
                'total_iterations': self.random_iterations
            })
            raise
            
    def test_random_module_counter_operations(self):
        """Test random module counter operations with multiple iterations."""
        test_name = f"test_random_module_counter_operations (N={self.random_iterations})"
        self._print_test_start(test_name)
        
        try:
            for iteration in range(self.random_iterations):
                new_count = random.randint(1, 128)
                
                # Set module counter
                result = target_module.module_data_set_module_counter(new_count)
                self.assertTrue(result, f"Iteration {iteration}: Failed to set module counter")
                
                # Verify it was set correctly
                read_count = target_module.get_module_count()
                self.assertEqual(read_count, new_count, 
                                 f"Iteration {iteration}: Module count mismatch")
                
            self._print_test_pass(test_name)
        except Exception as e:
            self._print_test_fail(test_name, str(e), {
                'iteration': iteration if 'iteration' in locals() else 'N/A',
                'new_count': new_count if 'new_count' in locals() else 'N/A',
                'read_count': read_count if 'read_count' in locals() else 'N/A',
                'total_iterations': self.random_iterations
            })
            raise


def main():
    """Main entry point for the test suite."""
    parser = argparse.ArgumentParser(
        description='Unit tests for hw_management_independent_mode_update.py',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Run with default 10 iterations
  %(prog)s -n 50              # Run with 50 random iterations
  %(prog)s --verbose          # Run with verbose output
  %(prog)s -n 100 -v          # Run with 100 iterations and verbose output
        """
    )
    
    parser.add_argument(
        '-n', '--iterations',
        type=int,
        default=10,
        help='Number of iterations for random tests (default: 10)'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Verbose output'
    )
    
    args = parser.parse_args()
    
    # Set random iterations on the test class
    TestHwManagementIndependentModeUpdate.random_iterations = args.iterations
    
    # Print header
    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("=" * 70)
    print("  HW Management Independent Mode Update - Unit Test Suite")
    print("=" * 70)
    print(f"{Colors.RESET}")
    print(f"{Colors.CYAN}{Icons.INFO} Test Configuration:{Colors.RESET}")
    print(f"  - Random test iterations: {args.iterations}")
    print(f"  - Verbose mode: {'Enabled' if args.verbose else 'Disabled'}")
    print()
    
    # Run tests
    verbosity = 2 if args.verbose else 1
    
    # Create test suite
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestHwManagementIndependentModeUpdate)
    
    # Run tests with custom result class
    runner = unittest.TextTestRunner(verbosity=verbosity, stream=sys.stdout)
    result = runner.run(suite)
    
    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == '__main__':
    main()

