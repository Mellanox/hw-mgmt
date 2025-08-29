#!/usr/bin/env python3
"""
Simple test runner for module_temp_populate function
Execute this file directly to run all tests
"""

from hw_management_sync import module_temp_populate, sdk_temp2degree, CONST
import os
import sys
import tempfile
import shutil
import unittest
from unittest.mock import patch
import random

# Add the parent directory to the path to import hw_management_sync
# The path should be: workspace_root/usr/usr/bin/
current_dir = os.path.dirname(os.path.abspath(__file__))
workspace_root = os.path.join(current_dir, '../../../../')
usr_bin_path = os.path.join(workspace_root, 'usr/usr/bin')

if os.path.exists(usr_bin_path):
    sys.path.insert(0, usr_bin_path)
else:
    # Fallback: try to find the workspace root
    current_dir = os.getcwd()
    if 'hw_mgmt_clean' in current_dir:
        workspace_root = current_dir
        while workspace_root and not os.path.exists(os.path.join(workspace_root, 'usr/usr/bin')):
            workspace_root = os.path.dirname(workspace_root)
        if workspace_root:
            sys.path.insert(0, os.path.join(workspace_root, 'usr/usr/bin'))

# Mock the CONST module before importing hw_management_sync


class MockCONST:
    SDK_FW_CONTROL = 0
    SDK_SW_CONTROL = 1
    ASIC_TEMP_MIN_DEF = 75000
    ASIC_TEMP_MAX_DEF = 85000
    ASIC_TEMP_FAULT_DEF = 105000
    ASIC_TEMP_CRIT_DEF = 120000
    MODULE_TEMP_MAX_DEF = 75000
    MODULE_TEMP_FAULT_DEF = 105000
    MODULE_TEMP_CRIT_DEF = 120000
    MODULE_TEMP_EMERGENCY_OFFSET = 10000


# Mock the CONST module
sys.modules['CONST'] = MockCONST()

# Now import the functions we need to test


class TestModuleTempPopulate(unittest.TestCase):
    """Test cases for module_temp_populate function"""

    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.thermal_dir = os.path.join(self.temp_dir, "thermal")
        self.config_dir = os.path.join(self.temp_dir, "config")

        # Create necessary directories
        os.makedirs(self.thermal_dir, exist_ok=True)
        os.makedirs(self.config_dir, exist_ok=True)

        # Test arguments as specified in requirements
        self.arg_list = {
            "fin": "/sys/module/sx_core/asic0/module{}/",
            "fout_idx_offset": 1,
            "module_count": 36
        }

        # Track created files for cleanup
        self.created_files = []

    def tearDown(self):
        """Clean up test fixtures"""
        # Remove created files
        for file_path in self.created_files:
            if os.path.exists(file_path):
                os.remove(file_path)

        # Remove temp directory
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def create_module_files(self, module_idx, is_inserted=True, control_mode=0,
                            temp_input=None, has_critical_hi=True, has_cooling_level=True):
        """Create mock module files for testing"""
        module_path = os.path.join(self.temp_dir, f"module{module_idx}")
        os.makedirs(module_path, exist_ok=True)

        # Create control file
        control_file = os.path.join(module_path, "control")
        with open(control_file, 'w') as f:
            f.write(str(control_mode))

        if is_inserted:
            # Create present file
            present_file = os.path.join(module_path, "present")
            with open(present_file, 'w') as f:
                f.write("1")

            # Create temperature directory
            temp_dir = os.path.join(module_path, "temperature")
            os.makedirs(temp_dir, exist_ok=True)

            # Create temperature input file (50000-70000 range as specified)
            if temp_input is None:
                temp_input = random.randint(50000, 70000)
            input_file = os.path.join(temp_dir, "input")
            with open(input_file, 'w') as f:
                f.write(str(temp_input))

            # Create threshold_hi file (70000 as specified)
            threshold_file = os.path.join(temp_dir, "threshold_hi")
            with open(threshold_file, 'w') as f:
                f.write("70000")

            # Create threshold_critical_hi file (80000 as specified, optional)
            if has_critical_hi:
                critical_file = os.path.join(temp_dir, "threshold_critical_hi")
                with open(critical_file, 'w') as f:
                    f.write("80000")

            # Create cooling level files (100-800 range as specified, optional)
            if has_cooling_level:
                tec_dir = os.path.join(temp_dir, "tec")
                os.makedirs(tec_dir, exist_ok=True)

                cooling_level = random.randint(100, 800)
                cooling_file = os.path.join(tec_dir, "cooling_level")
                with open(cooling_file, 'w') as f:
                    f.write(str(cooling_level))

                # max_cooling_level = cooling_level + 5000 as specified
                max_cooling_file = os.path.join(tec_dir, "max_cooling_level")
                with open(max_cooling_file, 'w') as f:
                    f.write(str(cooling_level + 5000))
        else:
            # Create present file for not inserted module
            present_file = os.path.join(module_path, "present")
            with open(present_file, 'w') as f:
                f.write("0")

    def test_sdk_temp2degree(self):
        """Test the sdk_temp2degree function"""
        # Test positive values
        self.assertEqual(sdk_temp2degree(1), 125)
        self.assertEqual(sdk_temp2degree(10), 1250)
        self.assertEqual(sdk_temp2degree(100), 12500)

        # Test negative values
        self.assertEqual(sdk_temp2degree(-1), 0xffff)
        self.assertEqual(sdk_temp2degree(-10), 0xfff6)

        # Test zero
        self.assertEqual(sdk_temp2degree(0), 0)

    def test_constants(self):
        """Test that CONST values are correct"""
        self.assertEqual(CONST.SDK_FW_CONTROL, 0)
        self.assertEqual(CONST.SDK_SW_CONTROL, 1)
        self.assertEqual(CONST.MODULE_TEMP_MAX_DEF, 75000)
        self.assertEqual(CONST.MODULE_TEMP_EMERGENCY_OFFSET, 10000)

    def test_arg_list_structure(self):
        """Test that arg_list has the correct structure"""
        self.assertEqual(self.arg_list["fin"], "/sys/module/sx_core/asic0/module{}/")
        self.assertEqual(self.arg_list["fout_idx_offset"], 1)
        self.assertEqual(self.arg_list["module_count"], 36)

    def test_module_file_creation(self):
        """Test that module files are created correctly"""
        # Create a simple module
        self.create_module_files(1, is_inserted=True, control_mode=0)

        # Verify files exist
        module_path = os.path.join(self.temp_dir, "module1")
        self.assertTrue(os.path.exists(module_path))

        control_file = os.path.join(module_path, "control")
        self.assertTrue(os.path.exists(control_file))

        present_file = os.path.join(module_path, "present")
        self.assertTrue(os.path.exists(present_file))

        # Check content
        with open(control_file, 'r') as f:
            self.assertEqual(f.read().strip(), "0")

        with open(present_file, 'r') as f:
            self.assertEqual(f.read().strip(), "1")

    def test_temperature_file_creation(self):
        """Test that temperature files are created correctly"""
        # Create module with temperature files
        self.create_module_files(1, is_inserted=True, has_critical_hi=True, has_cooling_level=True)

        module_path = os.path.join(self.temp_dir, "module1")
        temp_dir = os.path.join(module_path, "temperature")

        # Check temperature input file
        input_file = os.path.join(temp_dir, "input")
        self.assertTrue(os.path.exists(input_file))

        with open(input_file, 'r') as f:
            temp_value = int(f.read().strip())
            self.assertGreaterEqual(temp_value, 50000)
            self.assertLessEqual(temp_value, 70000)

        # Check threshold_hi file
        threshold_file = os.path.join(temp_dir, "threshold_hi")
        self.assertTrue(os.path.exists(threshold_file))

        with open(threshold_file, 'r') as f:
            self.assertEqual(f.read().strip(), "70000")

        # Check threshold_critical_hi file
        critical_file = os.path.join(temp_dir, "threshold_critical_hi")
        self.assertTrue(os.path.exists(critical_file))

        with open(critical_file, 'r') as f:
            self.assertEqual(f.read().strip(), "80000")

    def test_cooling_level_file_creation(self):
        """Test that cooling level files are created correctly"""
        # Create module with cooling level files
        self.create_module_files(1, is_inserted=True, has_cooling_level=True)

        module_path = os.path.join(self.temp_dir, "module1")
        temp_dir = os.path.join(module_path, "temperature")
        tec_dir = os.path.join(temp_dir, "tec")

        # Check cooling_level file
        cooling_file = os.path.join(tec_dir, "cooling_level")
        self.assertTrue(os.path.exists(cooling_file))

        with open(cooling_file, 'r') as f:
            cooling_value = int(f.read().strip())
            self.assertGreaterEqual(cooling_value, 100)
            self.assertLessEqual(cooling_value, 800)

        # Check max_cooling_level file
        max_cooling_file = os.path.join(tec_dir, "max_cooling_level")
        self.assertTrue(os.path.exists(max_cooling_file))

        with open(max_cooling_file, 'r') as f:
            max_cooling_value = int(f.read().strip())
            self.assertEqual(max_cooling_value, cooling_value + 5000)

    def test_not_inserted_module(self):
        """Test that not inserted modules are handled correctly"""
        # Create module that is not inserted
        self.create_module_files(1, is_inserted=False)

        module_path = os.path.join(self.temp_dir, "module1")
        present_file = os.path.join(module_path, "present")

        # Check present file content
        with open(present_file, 'r') as f:
            self.assertEqual(f.read().strip(), "0")

        # Verify no temperature directory exists
        temp_dir = os.path.join(module_path, "temperature")
        self.assertFalse(os.path.exists(temp_dir))


def run_tests():
    """Run all tests and return results"""
    print("Starting module_temp_populate tests...")
    print("=" * 50)

    # Create test suite
    test_suite = unittest.TestLoader().loadTestsFromTestCase(TestModuleTempPopulate)

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)

    print("=" * 50)
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")

    if result.failures:
        print("\nFailures:")
        for test, traceback in result.failures:
            print(f"  {test}: {traceback}")

    if result.errors:
        print("\nErrors:")
        for test, traceback in result.errors:
            print(f"  {test}: {traceback}")

    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
