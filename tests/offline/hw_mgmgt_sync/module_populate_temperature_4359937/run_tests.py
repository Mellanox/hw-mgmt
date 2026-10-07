#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

"""
Standalone test runner for module_temp_populate function tests

This script can be executed directly to run all tests for the module temperature
population functionality in hw_management_sync.py.

Usage:
    python3 run_tests.py
    or
    ./run_tests.py

The script will:
1. Set up the Python path to find the hw_management_sync module
2. Import and run all test cases
3. Provide detailed output and summary
4. Exit with appropriate return code (0 for success, 1 for failure)
"""

import os
import sys
import argparse
import importlib.util


def setup_environment():
    """Set up the test environment and Python path"""
    # Get the current script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Add the hw_management_sync module directory to Python path
    sync_module_path = os.path.join(script_dir, '..', '..', '..', '..', 'usr', 'usr', 'bin')
    abs_sync_path = os.path.abspath(sync_module_path)

    if abs_sync_path not in sys.path:
        sys.path.insert(0, abs_sync_path)

    print(f"[PYTHON] Added to Python path: {abs_sync_path}")

    # Verify the module can be imported
    try:
        import hw_management_thermal_updater
        print(f"[OK] Successfully imported hw_management_thermal_updater from {hw_management_thermal_updater.__file__}")
        return True
    except ImportError as e:
        print(f"[ERROR] Failed to import hw_management_sync: {e}")
        return False


def load_test_module():
    """Dynamically load the test module"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    test_file_path = os.path.join(script_dir, 'test_module_temp_populate.py')

    if not os.path.exists(test_file_path):
        print(f"[ERROR] Test file not found: {test_file_path}")
        return None

    spec = importlib.util.spec_from_file_location("test_module_temp_populate", test_file_path)
    test_module = importlib.util.module_from_spec(spec)

    try:
        spec.loader.exec_module(test_module)
        print(f"[OK] Successfully loaded test module from {test_file_path}")
        return test_module
    except Exception as e:
        print(f"[ERROR] Failed to load test module: {e}")
        return None


def main():
    """Main function to run all tests"""
    parser = argparse.ArgumentParser(
        description='Run module temperature populate tests',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    ./run_tests.py              # Run all tests
    python3 run_tests.py        # Run all tests with python3

Test Configuration:
    The tests validate the module_temp_populate function with:
    - 36 modules (indexed from 1 to 36)
    - Input path: /sys/module/sx_core/asic0/module{}/
    - Output path: /var/run/hw-management/thermal/

Test Scenarios:
    1. Normal condition with all files present
    2. Input read error with default values
    3. Other attributes read error
    4. Error handling without crashes
    5. Random module configuration testing (temp range: 0-800)
    6. Software control mode handling
    7. Temperature conversion function
    8. Argument validation
        """
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )

    args = parser.parse_args()

    print()
    print("+" + "=" * 68 + "+")
    print("|" + " " * 68 + "|")
    print("|" + "  NVIDIA HW Management Sync - Module Temperature Tests  ".center(68) + "|")
    print("|" + " " * 68 + "|")
    print("|" + " Standalone Test Runner ".center(68) + "|")
    print("|" + " " * 68 + "|")
    print("+" + "=" * 68 + "+")
    print()

    # Set up environment
    if not setup_environment():
        print("Environment setup failed!")
        return 1

    # Load test module
    test_module = load_test_module()
    if not test_module:
        print("Test module loading failed!")
        return 1

    print("+" + "-" * 66 + "+")
    print("|" + " Starting test execution... ".center(66) + "|")
    print("+" + "-" * 66 + "+")
    print()

    # Run tests
    try:
        success = test_module.run_tests()
        return 0 if success else 1
    except Exception as e:
        print(f"Test execution failed with exception: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    exit_code = main()
    sys.exit(exit_code)
