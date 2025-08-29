#!/usr/bin/env python3
"""
Test runner for module_temp_populate function
Tests various scenarios including inserted/not inserted modules with different configurations
"""

from hw_management_sync import module_temp_populate, sdk_temp2degree, CONST
import os
import sys
import tempfile
import shutil
import unittest
from unittest.mock import patch, mock_open, MagicMock
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

        # Mock the output directory paths
        self.original_thermal_path = "/var/run/hw-management/thermal"
        self.original_config_path = "/var/run/hw-management/config"

        # Test arguments
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

            # Create temperature input file
            if temp_input is None:
                temp_input = random.randint(50000, 70000)
            input_file = os.path.join(temp_dir, "input")
            with open(input_file, 'w') as f:
                f.write(str(temp_input))

            # Create threshold_hi file
            threshold_file = os.path.join(temp_dir, "threshold_hi")
            with open(threshold_file, 'w') as f:
                f.write("70000")

            # Create threshold_critical_hi file (optional)
            if has_critical_hi:
                critical_file = os.path.join(temp_dir, "threshold_critical_hi")
                with open(critical_file, 'w') as f:
                    f.write("80000")

            # Create cooling level files (optional)
            if has_cooling_level:
                tec_dir = os.path.join(temp_dir, "tec")
                os.makedirs(tec_dir, exist_ok=True)

                cooling_level = random.randint(100, 800)
                cooling_file = os.path.join(tec_dir, "cooling_level")
                with open(cooling_file, 'w') as f:
                    f.write(str(cooling_level))

                max_cooling_file = os.path.join(tec_dir, "max_cooling_level")
                with open(max_cooling_file, 'w') as f:
                    f.write(str(cooling_level + 5000))
        else:
            # Create present file for not inserted module
            present_file = os.path.join(module_path, "present")
            with open(present_file, 'w') as f:
                f.write("0")

    @patch('os.path.islink')
    @patch('os.path.join')
    @patch('os.makedirs')
    @patch('builtins.open', new_callable=mock_open)
    def test_module_temp_populate_basic(self, mock_file, mock_makedirs, mock_join, mock_islink):
        """Test basic module temperature population"""
        # Mock os.path.islink to return False (no existing links)
        mock_islink.return_value = False

        # Mock os.path.join to return our test paths
        def mock_join_side_effect(*args):
            if args[0] == "/var/run/hw-management/thermal":
                return os.path.join(self.thermal_dir, args[1])
            elif args[0] == "/var/run/hw-management/config":
                return os.path.join(self.config_dir, args[1])
            else:
                return os.path.join(*args)

        mock_join.side_effect = mock_join_side_effect

        # Create test module files
        self.create_module_files(1, is_inserted=True, control_mode=0)

        # Mock the module path
        with patch('hw_management_sync.os.path.join') as mock_path_join:
            def mock_path_join_side_effect(*args):
                if args[0] == "/sys/module/sx_core/asic0/module{}":
                    return os.path.join(self.temp_dir, f"module{args[1]}")
                else:
                    return os.path.join(*args)

            mock_path_join.side_effect = mock_path_join_side_effect

            # Call the function
            module_temp_populate(self.arg_list, None)

            # Verify that output files were created
            expected_files = [
                "module1_temp_input",
                "module1_temp_crit",
                "module1_temp_emergency",
                "module1_temp_fault",
                "module1_temp_trip_crit",
                "module1_cooling_level_input",
                "module1_max_cooling_level_input",
                "module1_status"
            ]

            for filename in expected_files:
                file_path = os.path.join(self.thermal_dir, filename)
                self.assertTrue(os.path.exists(file_path), f"File {filename} should exist")
                self.created_files.append(file_path)

    @patch('os.path.islink')
    @patch('os.path.join')
    @patch('os.makedirs')
    @patch('builtins.open', new_callable=mock_open)
    def test_module_temp_populate_control_mode_1(self, mock_file, mock_makedirs, mock_join, mock_islink):
        """Test that modules with control mode 1 are ignored"""
        # Mock os.path.islink to return False
        mock_islink.return_value = False

        # Mock os.path.join
        def mock_join_side_effect(*args):
            if args[0] == "/var/run/hw-management/thermal":
                return os.path.join(self.thermal_dir, args[1])
            elif args[0] == "/var/run/hw-management/config":
                return os.path.join(self.config_dir, args[1])
            else:
                return os.path.join(*args)

        mock_join.side_effect = mock_join_side_effect

        # Create test module with control mode 1
        self.create_module_files(1, is_inserted=True, control_mode=1)

        # Mock the module path
        with patch('hw_management_sync.os.path.join') as mock_path_join:
            def mock_path_join_side_effect(*args):
                if args[0] == "/sys/module/sx_core/asic0/module{}":
                    return os.path.join(self.temp_dir, f"module{args[1]}")
                else:
                    return os.path.join(*args)

            mock_path_join.side_effect = mock_path_join_side_effect

            # Call the function
            module_temp_populate(self.arg_list, None)

            # Verify that no output files were created for control mode 1
            for filename in ["module1_temp_input", "module1_status"]:
                file_path = os.path.join(self.thermal_dir, filename)
                self.assertFalse(os.path.exists(file_path), f"File {filename} should not exist for control mode 1")

    @patch('os.path.islink')
    @patch('os.path.join')
    @patch('os.makedirs')
    @patch('builtins.open', new_callable=mock_open)
    def test_module_temp_populate_not_inserted(self, mock_file, mock_makedirs, mock_join, mock_islink):
        """Test that not inserted modules are handled correctly"""
        # Mock os.path.islink to return False
        mock_islink.return_value = False

        # Mock os.path.join
        def mock_join_side_effect(*args):
            if args[0] == "/var/run/hw-management/thermal":
                return os.path.join(self.thermal_dir, args[1])
            elif args[0] == "/var/run/hw-management/config":
                return os.path.join(self.config_dir, args[1])
            else:
                return os.path.join(*args)

        mock_join.side_effect = mock_join_side_effect

        # Create test module that is not inserted
        self.create_module_files(1, is_inserted=False)

        # Mock the module path
        with patch('hw_management_sync.os.path.join') as mock_path_join:
            def mock_path_join_side_effect(*args):
                if args[0] == "/sys/module/sx_core/asic0/module{}":
                    return os.path.join(self.temp_dir, f"module{args[1]}")
                else:
                    return os.path.join(*args)

            mock_path_join.side_effect = mock_path_join_side_effect

            # Call the function
            module_temp_populate(self.arg_list, None)

            # Verify that status file was created with 0
            status_file = os.path.join(self.thermal_dir, "module1_status")
            self.assertTrue(os.path.exists(status_file), "Status file should exist")

            with open(status_file, 'r') as f:
                status = f.read().strip()
                self.assertEqual(status, "0", "Status should be 0 for not inserted module")

            self.created_files.append(status_file)

    @patch('os.path.islink')
    @patch('os.path.join')
    @patch('os.makedirs')
    @patch('builtins.open', new_callable=mock_open)
    def test_module_temp_populate_without_critical_hi(self, mock_file, mock_makedirs, mock_join, mock_islink):
        """Test module without threshold_critical_hi file"""
        # Mock os.path.islink to return False
        mock_islink.return_value = False

        # Mock os.path.join
        def mock_join_side_effect(*args):
            if args[0] == "/var/run/hw-management/thermal":
                return os.path.join(self.thermal_dir, args[1])
            elif args[0] == "/var/run/hw-management/config":
                return os.path.join(self.config_dir, args[1])
            else:
                return os.path.join(*args)

        mock_join.side_effect = mock_join_side_effect

        # Create test module without critical_hi file
        self.create_module_files(1, is_inserted=True, has_critical_hi=False)

        # Mock the module path
        with patch('hw_management_sync.os.path.join') as mock_path_join:
            def mock_path_join_side_effect(*args):
                if args[0] == "/sys/module/sx_core/asic0/module{}":
                    return os.path.join(self.temp_dir, f"module{args[1]}")
                else:
                    return os.path.join(*args)

            mock_path_join.side_effect = mock_path_join_side_effect

            # Call the function
            module_temp_populate(self.arg_list, None)

            # Verify that emergency temperature uses calculated value
            emergency_file = os.path.join(self.thermal_dir, "module1_temp_emergency")
            self.assertTrue(os.path.exists(emergency_file), "Emergency temperature file should exist")

            with open(emergency_file, 'r') as f:
                emergency_temp = f.read().strip()
                # Should be threshold_hi + emergency_offset
                expected_temp = str(70000 + CONST.MODULE_TEMP_EMERGENCY_OFFSET)
                self.assertEqual(emergency_temp, expected_temp)

            self.created_files.append(emergency_file)

    @patch('os.path.islink')
    @patch('os.path.join')
    @patch('os.makedirs')
    @patch('builtins.open', new_callable=mock_open)
    def test_module_temp_populate_without_cooling_level(self, mock_file, mock_makedirs, mock_join, mock_islink):
        """Test module without cooling level files"""
        # Mock os.path.islink to return False
        mock_islink.return_value = False

        # Mock os.path.join
        def mock_join_side_effect(*args):
            if args[0] == "/var/run/hw-management/thermal":
                return os.path.join(self.thermal_dir, args[1])
            elif args[0] == "/var/run/hw-management/config":
                return os.path.join(self.config_dir, args[1])
            else:
                return os.path.join(*args)

        mock_join.side_effect = mock_join_side_effect

        # Create test module without cooling level files
        self.create_module_files(1, is_inserted=True, has_cooling_level=False)

        # Mock the module path
        with patch('hw_management_sync.os.path.join') as mock_path_join:
            def mock_path_join_side_effect(*args):
                if args[0] == "/sys/module/sx_core/asic0/module{}":
                    return os.path.join(self.temp_dir, f"module{args[1]}")
                else:
                    return os.path.join(*args)

            mock_path_join.side_effect = mock_path_join_side_effect

            # Call the function
            module_temp_populate(self.arg_list, None)

            # Verify that cooling level files were not created
            cooling_file = os.path.join(self.thermal_dir, "module1_cooling_level_input")
            max_cooling_file = os.path.join(self.thermal_dir, "module1_max_cooling_level")

            self.assertFalse(os.path.exists(cooling_file), "Cooling level file should not exist")
            self.assertFalse(os.path.exists(max_cooling_file), "Max cooling level file should not exist")

    @patch('os.path.islink')
    @patch('os.path.join')
    @patch('os.makedirs')
    @patch('builtins.open', new_callable=mock_open)
    def test_module_temp_populate_multiple_modules(self, mock_file, mock_makedirs, mock_join, mock_islink):
        """Test multiple modules with different configurations"""
        # Mock os.path.islink to return False
        mock_islink.return_value = False

        # Mock os.path.join
        def mock_join_side_effect(*args):
            if args[0] == "/var/run/hw-management/thermal":
                return os.path.join(self.thermal_dir, args[1])
            elif args[0] == "/var/run/hw-management/config":
                return os.path.join(self.config_dir, args[1])
            else:
                return os.path.join(*args)

        mock_join.side_effect = mock_join_side_effect

        # Create multiple test modules with different configurations
        # Module 1: Inserted, control mode 0, with all features
        self.create_module_files(1, is_inserted=True, control_mode=0, has_critical_hi=True, has_cooling_level=True)

        # Module 2: Inserted, control mode 1 (should be ignored)
        self.create_module_files(2, is_inserted=True, control_mode=1, has_critical_hi=True, has_cooling_level=True)

        # Module 3: Not inserted
        self.create_module_files(3, is_inserted=False)

        # Module 4: Inserted, control mode 0, without critical_hi
        self.create_module_files(4, is_inserted=True, control_mode=0, has_critical_hi=False, has_cooling_level=True)

        # Mock the module path
        with patch('hw_management_sync.os.path.join') as mock_path_join:
            def mock_path_join_side_effect(*args):
                if args[0] == "/sys/module/sx_core/asic0/module{}":
                    return os.path.join(self.temp_dir, f"module{args[1]}")
                else:
                    return os.path.join(*args)

            mock_path_join.side_effect = mock_path_join_side_effect

            # Call the function
            module_temp_populate(self.arg_list, None)

            # Verify module 1 files exist
            for suffix in ["_temp_input", "_temp_crit", "_temp_emergency", "_status"]:
                file_path = os.path.join(self.thermal_dir, f"module1{suffix}")
                self.assertTrue(os.path.exists(file_path), f"Module 1 file module1{suffix} should exist")
                self.created_files.append(file_path)

            # Verify module 2 files don't exist (control mode 1)
            for suffix in ["_temp_input", "_status"]:
                file_path = os.path.join(self.thermal_dir, f"module2{suffix}")
                self.assertFalse(os.path.exists(file_path), f"Module 2 file module2{suffix} should not exist (control mode 1)")

            # Verify module 3 status file exists with 0
            status_file = os.path.join(self.thermal_dir, "module3_status")
            self.assertTrue(os.path.exists(status_file), "Module 3 status file should exist")
            with open(status_file, 'r') as f:
                status = f.read().strip()
                self.assertEqual(status, "0", "Module 3 status should be 0")
            self.created_files.append(status_file)

            # Verify module 4 files exist
            for suffix in ["_temp_input", "_temp_crit", "_status"]:
                file_path = os.path.join(self.thermal_dir, f"module4{suffix}")
                self.assertTrue(os.path.exists(file_path), f"Module 4 file module4{suffix} should exist")
                self.created_files.append(file_path)

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


if __name__ == '__main__':
    # Create test suite
    test_suite = unittest.TestLoader().loadTestsFromTestCase(TestModuleTempPopulate)

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)

    # Exit with appropriate code
    sys.exit(not result.wasSuccessful())
