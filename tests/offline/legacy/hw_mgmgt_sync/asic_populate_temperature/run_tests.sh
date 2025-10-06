#!/bin/bash
# ASIC Temperature Populate Test Runner
# Simple wrapper script for easy test execution
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Set up Python path for hw_management_sync module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
HW_MGMT_BIN_DIR="$PROJECT_ROOT/usr/usr/bin"

# Run the test with all provided arguments
echo "[INFO] Running ASIC Temperature Populate tests..."
echo "-------------------------------------------------------"

PYTHONPATH="$HW_MGMT_BIN_DIR:$PYTHONPATH" python3 "$TEST_SCRIPT" "$@"
exit_code=$?

echo ""
echo "======================================================="
if [[ $exit_code -eq 0 ]]; then
    echo "[PASS] All tests completed successfully!"
else
    echo "[FAIL] Some tests failed. Check output above for details."
fi

exit $exit_code
