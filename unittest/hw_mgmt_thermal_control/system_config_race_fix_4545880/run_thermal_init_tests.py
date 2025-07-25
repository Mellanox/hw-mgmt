#!/usr/bin/env python3
"""
Test runner for thermal control initialization and signal handling unit tests.
Runs tests for both hw_management_thermal_control.py and hw_management_thermal_control_2_5.py variants.

This script tests the fixes implemented in commit:
"hw-mgmt: thermal: Fix TC init/close flow issue"
"""

import test_thermal_init_and_signal_handling_2_5
import test_thermal_init_and_signal_handling
import unittest
import sys
import os

# Add the test directory to Python path
test_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, test_dir)

# Import test modules


def run_tests():
    """Run all thermal initialization and signal handling tests."""

    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add test cases from all modules
    suite.addTests(loader.loadTestsFromModule(test_thermal_init_and_signal_handling))
    suite.addTests(loader.loadTestsFromModule(test_thermal_init_and_signal_handling_2_5))
    suite.addTests(loader.loadTestsFromModule(test_simple_race_condition_fix))

    # Run tests with detailed output
    runner = unittest.TextTestRunner(verbosity=2, stream=sys.stdout, buffer=True)
    result = runner.run(suite)

    # Print summary
    print("\n" + "=" * 80)
    print("THERMAL CONTROL INITIALIZATION TESTS SUMMARY")
    print("=" * 80)
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Skipped: {len(result.skipped) if hasattr(result, 'skipped') else 0}")

    if result.failures:
        print("\nFAILURES:")
        for test, traceback in result.failures:
            print(f"- {test}: {traceback}")

    if result.errors:
        print("\nERRORS:")
        for test, traceback in result.errors:
            print(f"- {test}: {traceback}")

    # Return exit code
    return 0 if result.wasSuccessful() else 1


def run_specific_test_category(category):
    """Run tests for a specific category."""

    if category == "early_termination":
        test_pattern = "*early_termination*"
    elif category == "config_failures":
        test_pattern = "*configuration_loading_failure*"
    elif category == "signal_handler":
        test_pattern = "*signal_handler*"
    elif category == "logger_optimization":
        test_pattern = "*logger_close*"
    elif category == "integration":
        test_pattern = "*integration*"
    else:
        print(f"Unknown test category: {category}")
        print("Available categories: early_termination, config_failures, signal_handler, logger_optimization, integration")
        return 1

    # Discover and run matching tests
    loader = unittest.TestLoader()
    suite = loader.discover(test_dir, pattern=test_pattern)

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Run thermal control initialization tests')
    parser.add_argument('--category', '-c',
                        help='Run tests for specific category: early_termination, config_failures, signal_handler, logger_optimization, integration')
    parser.add_argument('--list-tests', '-l', action='store_true',
                        help='List all available tests')

    args = parser.parse_args()

    if args.list_tests:
        # List all test methods
        loader = unittest.TestLoader()
        suite = unittest.TestSuite()
        suite.addTests(loader.loadTestsFromModule(test_thermal_init_and_signal_handling))
        suite.addTests(loader.loadTestsFromModule(test_thermal_init_and_signal_handling_2_5))

        print("Available Tests:")
        print("=" * 50)
        for test_group in suite:
            for test in test_group:
                print(f"- {test._testMethodName}")
        sys.exit(0)

    if args.category:
        exit_code = run_specific_test_category(args.category)
    else:
        exit_code = run_tests()

    sys.exit(exit_code)
