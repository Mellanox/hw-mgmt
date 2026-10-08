#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test_asic_temp_populate.py"

echo "[GEAR] ASIC Temperature Populate Test Runner [GEAR]"
echo "======================================================="

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -i NUM     Number of iterations for ALL tests (default: 5)"
    echo "  -v         Verbose output"
    echo "  -s         Simple basic reporting (detailed is default)"
    echo "  --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Run with default 5 iterations (detailed reporting)"
    echo "  $0 -i 10        # Run with 10 iterations (detailed reporting)"
    echo "  $0 -i 3 -v      # Run with 3 iterations and verbose output"
    echo "  $0 -i 5 -s      # Run with 5 iterations and simple reporting"
    echo "  $0 -i 2 -v -s   # Run with 2 iterations, verbose, and simple reporting"
    exit 0
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "[FAIL] Python 3 is not installed or not in PATH"
    exit 1
fi

# Check if test script exists
if [[ ! -f "$TEST_SCRIPT" ]]; then
    echo "[FAIL] Test script not found: $TEST_SCRIPT"
    exit 1
fi

# Make sure test script is executable
chmod +x "$TEST_SCRIPT"

# Run the test with all provided arguments
echo "[INFO] Running ASIC Temperature Populate tests..."
echo "-------------------------------------------------------"

python3 "$TEST_SCRIPT" "$@"
exit_code=$?

echo ""
echo "======================================================="
if [[ $exit_code -eq 0 ]]; then
    echo "[PASS] All tests completed successfully!"
else
    echo "[FAIL] Some tests failed. Check output above for details."
fi

exit $exit_code
