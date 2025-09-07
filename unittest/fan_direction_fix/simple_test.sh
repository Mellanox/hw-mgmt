#!/bin/bash
# Simple test to debug the fan direction fix

set -e

TEST_DIR="/tmp/simple_fan_test_$$"
CONFIG_PATH="$TEST_DIR/config"
THERMAL_PATH="$TEST_DIR/thermal"
SYSFS_PATH="$TEST_DIR/sysfs"

# Create test environment
mkdir -p "$CONFIG_PATH" "$THERMAL_PATH" "$SYSFS_PATH"
echo "4" > "$CONFIG_PATH/max_tachos"

# Create fan status files as regular files (for testing)
for i in {1..4}; do
    echo "1" > "$THERMAL_PATH/fan${i}_status"
    echo "Created fan status file: $THERMAL_PATH/fan${i}_status"
done

echo "Checking fan status files:"
ls -la "$THERMAL_PATH/"

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

# Create test script
cat > "$TEST_DIR/test.sh" << EOF
#!/bin/bash
thermal_path="$THERMAL_PATH"
config_path="$CONFIG_PATH"

# Initialize fan direction files for existing fans
if [ -f "$CONFIG_PATH/max_tachos" ]; then
    max_tachos=\$(< "$CONFIG_PATH/max_tachos")
    echo "Max tachos: \$max_tachos"
    for ((i=1; i<=max_tachos; i+=1)); do
        echo "Checking fan \$i..."
        if [ -f "$THERMAL_PATH/fan"\$i"_status" ]; then
            echo "Fan \$i status file exists"
            status=\$(< "$THERMAL_PATH/fan"\$i"_status")
            echo "Fan \$i status: \$status"
            if [ "\$status" -eq 1 ]; then
                echo "Creating fan direction file for fan \$i"
                source "$TEST_DIR/hw-management-chassis-events.sh"
                set_fan_direction fan"\$i" 1
            fi
        else
            echo "Fan \$i status file does not exist or is not a symlink"
        fi
    done
fi
EOF
chmod +x "$TEST_DIR/test.sh"

# Run the test
echo "Running test..."
"$TEST_DIR/test.sh"

# Check results
echo "Checking results..."
for i in {1..4}; do
    if [ -f "$THERMAL_PATH/fan${i}_dir" ]; then
        content=$(cat "$THERMAL_PATH/fan${i}_dir")
        echo "Fan $i direction file exists with content: $content"
    else
        echo "Fan $i direction file does not exist"
    fi
done

# Cleanup
rm -rf "$TEST_DIR"
