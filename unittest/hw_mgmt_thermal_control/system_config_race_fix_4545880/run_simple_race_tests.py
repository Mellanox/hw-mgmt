#!/usr/bin/env python3
"""
Simple test runner for race condition fix validation (Bug 4545880).
Runs focused tests that validate the thermal control race condition fixes.

This script tests the fixes implemented in commit:
"hw-mgmt: thermal: Fix TC init/close flow issue"
"""

import test_simple_race_condition_fix
import unittest
import sys
import os

# Add the test directory to Python path and ensure thermal control modules can be found
test_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(test_dir, '..', '..', '..'))
thermal_control_path = os.path.join(project_root, 'usr', 'usr', 'bin')
sys.path.insert(0, test_dir)
sys.path.insert(0, thermal_control_path)

# Import test modules


def run_tests():
    """Run all race condition fix tests."""

    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add test cases from simple race condition tests
    suite.addTests(loader.loadTestsFromModule(test_simple_race_condition_fix))

    # Run tests with detailed output
    runner = unittest.TextTestRunner(verbosity=2, stream=sys.stdout, buffer=True)
    result = runner.run(suite)

    # Print summary
    print("\n" + "=" * 80)
    print("RACE CONDITION FIX TESTS SUMMARY")
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

    if category == "logger_optimization":
        test_patterns = ["logger_close_optimization"]
    elif category == "early_termination":
        test_patterns = ["sys_config_early_initialization"]
    elif category == "config_failures":
        test_patterns = ["configuration_loading_exception"]
    elif category == "signal_handler":
        test_patterns = ["signal_handler_platform_support"]
    elif category == "integration":
        test_patterns = ["load_configuration_returns"]
    else:
        print(f"Unknown test category: {category}")
        print("Available categories: logger_optimization, early_termination, config_failures, signal_handler, integration")
        return 1

    # Load tests from module and filter by pattern
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(test_simple_race_condition_fix)

    # Filter tests by pattern
    filtered_suite = unittest.TestSuite()

    def iterate_tests(test_suite):
        """Recursively iterate through test suite to find individual test cases."""
        for test in test_suite:
            if isinstance(test, unittest.TestSuite):
                yield from iterate_tests(test)
            else:
                yield test

    for test_case in iterate_tests(suite):
        if hasattr(test_case, '_testMethodName'):
            method_name = test_case._testMethodName
            matches = any(pattern in method_name for pattern in test_patterns)
            if matches:
                filtered_suite.addTest(test_case)

    if filtered_suite.countTestCases() == 0:
        print(f"No tests found matching category: {category}")
        return 1

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(filtered_suite)

    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Run race condition fix tests')
    parser.add_argument('--category', '-c',
                        help='Run tests for specific category: logger_optimization, early_termination, config_failures, signal_handler, integration')
    parser.add_argument('--list-tests', '-l', action='store_true',
                        help='List all available tests')

    args = parser.parse_args()

    if args.list_tests:
        # List all test methods
        loader = unittest.TestLoader()
        suite = loader.loadTestsFromModule(test_simple_race_condition_fix)

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
