#!/bin/bash
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


#
# Simple shell script to run module_temp_populate tests
# This script automatically finds the hw_management_sync.py file and runs tests
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🚀 MODULE_TEMP_POPULATE TEST RUNNER${NC}"
echo -e "${BLUE}========================================${NC}"

# Find hw_management_sync.py
HW_MGMT_PATH="$PROJECT_ROOT/usr/usr/bin/hw_management_sync.py"

if [ ! -f "$HW_MGMT_PATH" ]; then
    echo -e "${RED}❌ Could not find hw_management_sync.py at: $HW_MGMT_PATH${NC}"
    echo -e "${YELLOW}Please ensure you're running this from the correct directory${NC}"
    exit 1
fi

echo -e "${GREEN}📁 Found hw_management_sync.py: $HW_MGMT_PATH${NC}"
echo -e "${GREEN}📁 Test directory: $SCRIPT_DIR${NC}"

# Change to test directory
cd "$SCRIPT_DIR"

# Check if test file exists
if [ ! -f "test_module_temp_populate.py" ]; then
    echo -e "${RED}❌ Test file not found: test_module_temp_populate.py${NC}"
    exit 1
fi

# Run tests
echo -e "${BLUE}🧪 Running tests...${NC}"
echo ""

if python3 run_tests.py --hw-mgmt-path "$HW_MGMT_PATH" "$@"; then
    echo ""
    echo -e "${GREEN}✅ All tests completed successfully!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some tests failed!${NC}"
    exit 1
fi
