#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#


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