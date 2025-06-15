#!/bin/bash

# Test runner script for module_temp_populate unit tests
# Usage: ./run_tests.sh <path_to_hw_management_sync.py> [--verbose]

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path_to_hw_management_sync.py> [--verbose]"
    echo "Example: $0 ./bin/hw_management_sync.py --verbose"
    exit 1
fi

HW_MGMT_PATH="$1"
VERBOSE_FLAG="$2"

# Check if the file exists
if [ ! -f "$HW_MGMT_PATH" ]; then
    echo "Error: File $HW_MGMT_PATH does not exist"
    exit 1
fi

# Run the tests
echo "Running unit tests for module_temp_populate function..."
echo "Using hw_management_sync.py from: $HW_MGMT_PATH"
echo "=========================================="

if [ "$VERBOSE_FLAG" = "--verbose" ] || [ "$VERBOSE_FLAG" = "-v" ]; then
    python3 test_module_temp_populate.py "$HW_MGMT_PATH" --verbose
else
    python3 test_module_temp_populate.py "$HW_MGMT_PATH"
fi 