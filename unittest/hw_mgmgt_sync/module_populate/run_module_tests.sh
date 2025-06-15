#!/bin/bash

# Module Temperature Unit Test Runner
# This script runs the comprehensive unit tests for module_temp_populate function

echo "==================================="
echo "Module Temperature Unit Test Runner"
echo "==================================="
echo

# Check if test file exists
if [ ! -f "test_module_temp_populate.py" ]; then
    echo "Error: test_module_temp_populate.py not found!"
    echo "Please ensure you're running this script from the correct directory."
    exit 1
fi

# Check if main module exists
if [ ! -f "hw_management_sync.py" ]; then
    echo "Error: hw_management_sync.py not found!"
    echo "Please ensure you're running this script from the correct directory."
    exit 1
fi

echo "Running all module temperature tests..."
echo

# Run all tests with verbose output
python3 -m unittest test_module_temp_populate -v

TEST_RESULT=$?

echo
echo "==================================="

if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ All tests PASSED!"
    echo
    echo "Test Coverage Summary:"
    echo "- SW mode behavior (no thermal file modifications)"
    echo "- FW mode with non-present modules (zeros in thermal files)"
    echo "- FW mode with present modules (actual temperature values)"
    echo "- Random combinations of all scenarios"
    echo "- Helper function validation"
    echo "- Constants validation"
else
    echo "❌ Some tests FAILED!"
    echo
    echo "Please check the test output above for details."
fi

echo "==================================="
exit $TEST_RESULT 