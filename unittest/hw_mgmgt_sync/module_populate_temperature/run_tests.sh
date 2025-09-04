#!/bin/bash
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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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
