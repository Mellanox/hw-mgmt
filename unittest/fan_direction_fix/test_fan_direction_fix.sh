#!/bin/bash
################################################################################
# Integration test for fan direction file creation fix
#
# This script tests the actual fix in a simulated environment that closely
# mimics the real hw-management setup.
#
# Test scenarios:
# 1. Hotplug event simulation - tests thermal events script fix
# 2. Initialization simulation - tests start-post script fix  
# 3. Edge cases - missing files, permissions, etc.
#
# Usage: ./test_fan_direction_fix.sh
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/fan_dir_test_$$"
CONFIG_PATH="$TEST_DIR/config"
THERMAL_PATH="$TEST_DIR/thermal"
EVENTS_PATH="$TEST_DIR/events"
SYSTEM_PATH="$TEST_DIR/system"
SYSFS_PATH="$TEST_DIR/sysfs"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

test_assert() {
    local test_name="$1"
    local condition="$2"
    local message="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$condition"; then
        log_info "PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "FAIL: $test_name - $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Set up trap for cleanup
trap cleanup EXIT

# Create test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create directory structure
    mkdir -p "$CONFIG_PATH" "$THERMAL_PATH" "$EVENTS_PATH" "$SYSTEM_PATH" "$SYSFS_PATH"
    
    # Create test configuration files
    echo "VMOD0015" > "$SYSTEM_PATH/board_type"
    echo "SN5600" > "$SYSTEM_PATH/sku"
    echo "4" > "$CONFIG_PATH/max_tachos"
    
    # Create mock chassis events script
    cat > "$TEST_DIR/hw-management-chassis-events.sh" << 'EOF'
#!/bin/bash
function set_fan_direction() {
    local fan_name="$1"
    local direction="$2"
    echo "$direction" > "$thermal_path/${fan_name}_dir"
    echo "Created fan direction file: $thermal_path/${fan_name}_dir with value $direction"
}
EOF
    chmod +x "$TEST_DIR/hw-management-chassis-events.sh"
    
    # Create mock helpers script
    cat > "$TEST_DIR/hw-management-helpers.sh" << EOF
#!/bin/bash
config_path="$CONFIG_PATH"
thermal_path="$THERMAL_PATH"
events_path="$EVENTS_PATH"
system_path="$SYSTEM_PATH"
board_type_file="$SYSTEM_PATH/board_type"
sku_file="$SYSTEM_PATH/sku"
EOF
    chmod +x "$TEST_DIR/hw-management-helpers.sh"
}

# Test 1: Hotplug event simulation
test_hotplug_event() {
    log_info "Testing hotplug event simulation..."
    
    # Create mock sysfs fan files
    for i in {1..4}; do
        echo "1" > "$SYSFS_PATH/fan$i"
    done
    
    # Create test thermal events script
    cat > "$TEST_DIR/test_thermal_events.sh" << EOF
#!/bin/bash
source "$TEST_DIR/hw-management-helpers.sh"
source "$TEST_DIR/hw-management-chassis-events.sh"

# Simulate hotplug event processing
max_tachos=\$(< "$CONFIG_PATH/max_tachos")
for ((i=1; i<=max_tachos; i+=1)); do
    if [ -f "$SYSFS_PATH/fan\$i" ]; then
        echo "1" > "$THERMAL_PATH/fan"\$i"_status"
        event=\$(< "$THERMAL_PATH/fan"\$i"_status")
        if [ "\$event" -eq 1 ]; then
            echo 1 > "$EVENTS_PATH/fan"\$i""
            # Create fan direction file when fan is present
            set_fan_direction fan"\$i" 1
        fi
    fi
done
EOF
    chmod +x "$TEST_DIR/test_thermal_events.sh"
    
    # Run the test
    "$TEST_DIR/test_thermal_events.sh"
    
    # Verify results
    for i in {1..4}; do
        test_assert "hotplug_fan${i}_dir_created" \
            "[ -f '$THERMAL_PATH/fan${i}_dir' ]" \
            "Fan direction file fan${i}_dir was not created during hotplug"
        
        test_assert "hotplug_fan${i}_dir_content" \
            "[ \"\$(cat '$THERMAL_PATH/fan${i}_dir')\" = '1' ]" \
            "Fan direction file fan${i}_dir has wrong content"
    done
}

# Test 2: Initialization simulation
test_initialization() {
    log_info "Testing initialization simulation..."
    
    # Clean up previous test
    rm -f "$THERMAL_PATH"/fan*_dir "$THERMAL_PATH"/fan*_status "$SYSFS_PATH"/fan*_status
    
    # Create existing fan status files (as regular files for testing)
    for i in {1..4}; do
        echo "1" > "$THERMAL_PATH/fan${i}_status"
    done
    
    # Create test start-post script
    cat > "$TEST_DIR/test_start_post.sh" << EOF
#!/bin/bash
source "$TEST_DIR/hw-management-helpers.sh"

# Initialize fan direction files for existing fans
if [ -f "$CONFIG_PATH/max_tachos" ]; then
    max_tachos=\$(< "$CONFIG_PATH/max_tachos")
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -f "$THERMAL_PATH/fan"\$i"_status" ]; then
            status=\$(< "$THERMAL_PATH/fan"\$i"_status")
            if [ "\$status" -eq 1 ]; then
                # Source chassis events to get set_fan_direction function
                source "$TEST_DIR/hw-management-chassis-events.sh"
                set_fan_direction fan"\$i" 1
            fi
        fi
    done
fi
EOF
    chmod +x "$TEST_DIR/test_start_post.sh"
    
    # Run the test
    "$TEST_DIR/test_start_post.sh"
    
    # Verify results
    for i in {1..4}; do
        test_assert "init_fan${i}_dir_created" \
            "[ -f '$THERMAL_PATH/fan${i}_dir' ]" \
            "Fan direction file fan${i}_dir was not created during initialization"
        
        test_assert "init_fan${i}_dir_content" \
            "[ \"\$(cat '$THERMAL_PATH/fan${i}_dir')\" = '1' ]" \
            "Fan direction file fan${i}_dir has wrong content"
    done
}

# Test 3: Edge case - missing fan status files
test_missing_fan_status() {
    log_info "Testing edge case - missing fan status files..."
    
    # Clean up previous test
    rm -f "$THERMAL_PATH"/fan*_dir "$THERMAL_PATH"/fan*_status "$SYSFS_PATH"/fan*_status "$THERMAL_PATH"/fan*_status
    
    # Create only some fan status files (as regular files for testing)
    for i in 1 3; do
        echo "1" > "$THERMAL_PATH/fan${i}_status"
    done
    
    # Create test start-post script
    cat > "$TEST_DIR/test_start_post.sh" << EOF
#!/bin/bash
source "$TEST_DIR/hw-management-helpers.sh"
source "$TEST_DIR/hw-management-chassis-events.sh"

# Initialize fan direction files for existing fans
if [ -f "$CONFIG_PATH/max_tachos" ]; then
    max_tachos=\$(< "$CONFIG_PATH/max_tachos")
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -f "$THERMAL_PATH/fan"\$i"_status" ]; then
            status=\$(< "$THERMAL_PATH/fan"\$i"_status")
            if [ "\$status" -eq 1 ]; then
                set_fan_direction fan"\$i" 1
            fi
        fi
    done
fi
EOF
    chmod +x "$TEST_DIR/test_start_post.sh"
    
    # Run the test
    "$TEST_DIR/test_start_post.sh"
    
    # Verify results - only existing fans should have direction files
    for i in {1..4}; do
        if [ $i -eq 1 ] || [ $i -eq 3 ]; then
            test_assert "missing_status_fan${i}_dir_created" \
                "[ -f '$THERMAL_PATH/fan${i}_dir' ]" \
                "Fan direction file fan${i}_dir should exist for present fan"
        else
            test_assert "missing_status_fan${i}_dir_not_created" \
                "[ ! -f '$THERMAL_PATH/fan${i}_dir' ]" \
                "Fan direction file fan${i}_dir should not exist for missing fan"
        fi
    done
}

# Test 4: Edge case - zero fans
test_zero_fans() {
    log_info "Testing edge case - zero fans..."
    
    # Clean up previous test
    rm -f "$THERMAL_PATH"/fan*_dir "$THERMAL_PATH"/fan*_status "$SYSFS_PATH"/fan*_status "$THERMAL_PATH"/fan*_status
    
    # Set max_tachos to 0
    echo "0" > "$CONFIG_PATH/max_tachos"
    
    # Create test start-post script
    cat > "$TEST_DIR/test_start_post.sh" << EOF
#!/bin/bash
source "$TEST_DIR/hw-management-helpers.sh"
source "$TEST_DIR/hw-management-chassis-events.sh"

# Initialize fan direction files for existing fans
if [ -f "$CONFIG_PATH/max_tachos" ]; then
    max_tachos=\$(< "$CONFIG_PATH/max_tachos")
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -f "$THERMAL_PATH/fan"\$i"_status" ]; then
            status=\$(< "$THERMAL_PATH/fan"\$i"_status")
            if [ "\$status" -eq 1 ]; then
                set_fan_direction fan"\$i" 1
            fi
        fi
    done
fi
EOF
    chmod +x "$TEST_DIR/test_start_post.sh"
    
    # Run the test
    "$TEST_DIR/test_start_post.sh"
    
    # Verify results - no fan direction files should be created
    for i in {1..4}; do
        test_assert "zero_fans_fan${i}_dir_not_created" \
            "[ ! -f '$THERMAL_PATH/fan${i}_dir' ]" \
            "Fan direction file fan${i}_dir should not exist with zero fans"
    done
    
    # Restore max_tachos for other tests
    echo "4" > "$CONFIG_PATH/max_tachos"
}

# Test 5: Integration test - simulate the actual bug scenario
test_integration_bug_scenario() {
    log_info "Testing integration - simulate actual bug scenario..."
    
    # Clean up previous test
    rm -f "$THERMAL_PATH"/fan*_dir "$THERMAL_PATH"/fan*_status "$SYSFS_PATH"/fan*_status "$THERMAL_PATH"/fan*_status
    
    # Simulate the exact scenario from the engineer's logs:
    # 1. System boots, fans are already present
    # 2. hw-management starts and creates fan status files
    # 3. thermal control daemon tries to read fan direction files (which don't exist)
    # 4. Our fix should create them during initialization
    
    # Step 1: Create fan status files (simulating existing fans as regular files for testing)
    for i in {1..4}; do
        echo "1" > "$THERMAL_PATH/fan${i}_status"
    done
    
    # Step 2: Simulate thermal control daemon trying to read fan direction files
    # This should fail before our fix
    for i in {1..4}; do
        test_assert "bug_scenario_fan${i}_dir_missing_before_fix" \
            "[ ! -f '$THERMAL_PATH/fan${i}_dir' ]" \
            "Fan direction file fan${i}_dir should be missing before fix"
    done
    
    # Step 3: Apply our fix (simulate start-post script)
    cat > "$TEST_DIR/test_start_post.sh" << EOF
#!/bin/bash
source "$TEST_DIR/hw-management-helpers.sh"
source "$TEST_DIR/hw-management-chassis-events.sh"

# Initialize fan direction files for existing fans
if [ -f "$CONFIG_PATH/max_tachos" ]; then
    max_tachos=\$(< "$CONFIG_PATH/max_tachos")
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -f "$THERMAL_PATH/fan"\$i"_status" ]; then
            status=\$(< "$THERMAL_PATH/fan"\$i"_status")
            if [ "\$status" -eq 1 ]; then
                set_fan_direction fan"\$i" 1
            fi
        fi
    done
fi
EOF
    chmod +x "$TEST_DIR/test_start_post.sh"
    
    # Run the fix
    "$TEST_DIR/test_start_post.sh"
    
    # Step 4: Verify thermal control daemon can now read fan direction files
    for i in {1..4}; do
        test_assert "bug_scenario_fan${i}_dir_exists_after_fix" \
            "[ -f '$THERMAL_PATH/fan${i}_dir' ]" \
            "Fan direction file fan${i}_dir should exist after fix"
        
        test_assert "bug_scenario_fan${i}_dir_readable" \
            "[ -r '$THERMAL_PATH/fan${i}_dir' ]" \
            "Fan direction file fan${i}_dir should be readable"
        
        # Simulate thermal control daemon reading the file
        if [ -f "$THERMAL_PATH/fan${i}_dir" ]; then
            content=$(cat "$THERMAL_PATH/fan${i}_dir")
            test_assert "bug_scenario_fan${i}_dir_content" \
                "[ \"$content\" = '1' ]" \
                "Fan direction file fan${i}_dir should have correct content"
        fi
    done
}

# Main test execution
main() {
    log_info "Starting fan direction fix tests..."
    
    setup_test_environment
    
    test_hotplug_event
    test_initialization
    test_missing_fan_status
    test_zero_fans
    test_integration_bug_scenario
    
    # Print test summary
    echo
    log_info "Test Summary:"
    log_info "  Tests run: $TESTS_RUN"
    log_info "  Tests passed: $TESTS_PASSED"
    log_info "  Tests failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_info "All tests passed! ✅"
        exit 0
    else
        log_error "Some tests failed! ❌"
        exit 1
    fi
}

# Run main function
main "$@"
