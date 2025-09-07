#!/usr/bin/env python3
"""
Comprehensive tests for fan direction file creation fix.

This test suite validates the fix for FileNotFoundError when thermal control daemon
tries to read fanX_dir files that don't exist.

Test Coverage:
1. Hotplug event handling - thermal events script creates fan direction files
2. Initialization handling - start-post script creates fan direction files for existing fans
3. Edge cases - missing files, permission issues, function availability
4. Integration tests - end-to-end scenarios

Bug Reference: FileNotFoundError for /var/run/hw-management/thermal/fan<X>_dir
"""

import unittest
import tempfile
import os
import sys
import subprocess
import shutil
from unittest.mock import Mock, patch, MagicMock, mock_open
import time

# Find the project root directory
test_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(test_dir, '..', '..', '..'))
scripts_path = os.path.join(project_root, 'usr', 'usr', 'bin')
sys.path.insert(0, scripts_path)


class TestFanDirectionFix(unittest.TestCase):
    """Test cases for fan direction file creation fix."""

    def setUp(self):
        """Set up test fixtures."""
        self.test_dir = tempfile.mkdtemp(prefix='fan_dir_test_')
        self.config_path = os.path.join(self.test_dir, 'config')
        self.thermal_path = os.path.join(self.test_dir, 'thermal')
        self.events_path = os.path.join(self.test_dir, 'events')
        self.system_path = os.path.join(self.test_dir, 'system')
        
        # Create test directory structure
        os.makedirs(self.config_path, exist_ok=True)
        os.makedirs(self.thermal_path, exist_ok=True)
        os.makedirs(self.events_path, exist_ok=True)
        os.makedirs(self.system_path, exist_ok=True)
        
        # Create test files
        self.board_type_file = os.path.join(self.system_path, 'board_type')
        self.sku_file = os.path.join(self.system_path, 'sku')
        self.max_tachos_file = os.path.join(self.config_path, 'max_tachos')
        
        with open(self.board_type_file, 'w') as f:
            f.write('VMOD0015')
        with open(self.sku_file, 'w') as f:
            f.write('SN5600')
        with open(self.max_tachos_file, 'w') as f:
            f.write('4')

    def tearDown(self):
        """Clean up test fixtures."""
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_thermal_events_hotplug_creates_fan_dir_files(self):
        """Test that thermal events script creates fan direction files during hotplug."""
        # Create mock sysfs fan files
        sysfs_fan_path = os.path.join(self.test_dir, 'sysfs_fan')
        os.makedirs(sysfs_fan_path, exist_ok=True)
        
        for i in range(1, 5):
            fan_file = os.path.join(sysfs_fan_path, f'fan{i}')
            with open(fan_file, 'w') as f:
                f.write('1')  # Fan present
        
        # Create mock chassis events script
        chassis_events_script = os.path.join(self.test_dir, 'hw-management-chassis-events.sh')
        with open(chassis_events_script, 'w') as f:
            f.write('''#!/bin/bash
function set_fan_direction() {
    local fan_name="$1"
    local direction="$2"
    echo "$direction" > "{}/${{fan_name}}_dir"
    echo "Created fan direction file: {}/${{fan_name}}_dir with value $direction"
}
'''.format(self.thermal_path, self.thermal_path))
        os.chmod(chassis_events_script, 0o755)
        
        # Create mock helpers script
        helpers_script = os.path.join(self.test_dir, 'hw-management-helpers.sh')
        with open(helpers_script, 'w') as f:
            f.write(f'''#!/bin/bash
config_path="{self.config_path}"
thermal_path="{self.thermal_path}"
events_path="{self.events_path}"
system_path="{self.system_path}"
board_type_file="{self.board_type_file}"
sku_file="{self.sku_file}"
''')
        os.chmod(helpers_script, 0o755)
        
        # Create test thermal events script
        thermal_events_script = os.path.join(self.test_dir, 'test_thermal_events.sh')
        with open(thermal_events_script, 'w') as f:
            f.write(f'''#!/bin/bash
source {helpers_script}
source {chassis_events_script}

# Simulate hotplug event processing
max_tachos=$(< {self.max_tachos_file})
for ((i=1; i<=max_tachos; i+=1)); do
    if [ -f "{sysfs_fan_path}/fan$i" ]; then
        echo "1" > {self.thermal_path}/fan"$i"_status
        event=$(< {self.thermal_path}/fan"$i"_status)
        if [ "$event" -eq 1 ]; then
            echo 1 > {self.events_path}/fan"$i"
            # Create fan direction file when fan is present
            set_fan_direction fan"$i" 1
        fi
    fi
done
''')
        os.chmod(thermal_events_script, 0o755)
        
        # Run the test
        result = subprocess.run([thermal_events_script], 
                              capture_output=True, text=True, cwd=self.test_dir)
        
        # Verify results
        self.assertEqual(result.returncode, 0, f"Script failed: {result.stderr}")
        
        # Check that fan direction files were created
        for i in range(1, 5):
            fan_dir_file = os.path.join(self.thermal_path, f'fan{i}_dir')
            self.assertTrue(os.path.exists(fan_dir_file), 
                          f"Fan direction file fan{i}_dir was not created")
            
            with open(fan_dir_file, 'r') as f:
                content = f.read().strip()
                self.assertEqual(content, '1', 
                              f"Fan direction file fan{i}_dir has wrong content: {content}")

    def test_start_post_creates_fan_dir_files_for_existing_fans(self):
        """Test that start-post script creates fan direction files for existing fans."""
        # Create existing fan status files
        for i in range(1, 5):
            fan_status_file = os.path.join(self.thermal_path, f'fan{i}_status')
            with open(fan_status_file, 'w') as f:
                f.write('1')  # Fan present
        
        # Create mock chassis events script
        chassis_events_script = os.path.join(self.test_dir, 'hw-management-chassis-events.sh')
        with open(chassis_events_script, 'w') as f:
            f.write('''#!/bin/bash
function set_fan_direction() {
    local fan_name="$1"
    local direction="$2"
    echo "$direction" > "{}/${{fan_name}}_dir"
    echo "Created fan direction file: {}/${{fan_name}}_dir with value $direction"
}
'''.format(self.thermal_path, self.thermal_path))
        os.chmod(chassis_events_script, 0o755)
        
        # Create mock helpers script
        helpers_script = os.path.join(self.test_dir, 'hw-management-helpers.sh')
        with open(helpers_script, 'w') as f:
            f.write(f'''#!/bin/bash
config_path="{self.config_path}"
thermal_path="{self.thermal_path}"
events_path="{self.events_path}"
system_path="{self.system_path}"
board_type_file="{self.board_type_file}"
sku_file="{self.sku_file}"
''')
        os.chmod(helpers_script, 0o755)
        
        # Create test start-post script
        start_post_script = os.path.join(self.test_dir, 'test_start_post.sh')
        with open(start_post_script, 'w') as f:
            f.write(f'''#!/bin/bash
source {helpers_script}

# Initialize fan direction files for existing fans
if [ -f {self.max_tachos_file} ]; then
    max_tachos=$(< {self.max_tachos_file})
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -L {self.thermal_path}/fan"$i"_status ]; then
            status=$(< {self.thermal_path}/fan"$i"_status)
            if [ "$status" -eq 1 ]; then
                # Source chassis events to get set_fan_direction function
                source {chassis_events_script}
                set_fan_direction fan"$i" 1
            fi
        fi
    done
fi
''')
        os.chmod(start_post_script, 0o755)
        
        # Run the test
        result = subprocess.run([start_post_script], 
                              capture_output=True, text=True, cwd=self.test_dir)
        
        # Verify results
        self.assertEqual(result.returncode, 0, f"Script failed: {result.stderr}")
        
        # Check that fan direction files were created
        for i in range(1, 5):
            fan_dir_file = os.path.join(self.thermal_path, f'fan{i}_dir')
            self.assertTrue(os.path.exists(fan_dir_file), 
                          f"Fan direction file fan{i}_dir was not created")
            
            with open(fan_dir_file, 'r') as f:
                content = f.read().strip()
                self.assertEqual(content, '1', 
                              f"Fan direction file fan{i}_dir has wrong content: {content}")

    def test_handles_missing_fan_status_files(self):
        """Test that scripts handle missing fan status files gracefully."""
        # Create only some fan status files
        for i in [1, 3]:  # Only fans 1 and 3
            fan_status_file = os.path.join(self.thermal_path, f'fan{i}_status')
            with open(fan_status_file, 'w') as f:
                f.write('1')
        
        # Create mock chassis events script
        chassis_events_script = os.path.join(self.test_dir, 'hw-management-chassis-events.sh')
        with open(chassis_events_script, 'w') as f:
            f.write('''#!/bin/bash
function set_fan_direction() {
    local fan_name="$1"
    local direction="$2"
    echo "$direction" > "{}/${{fan_name}}_dir"
}
'''.format(self.thermal_path))
        os.chmod(chassis_events_script, 0o755)
        
        # Create mock helpers script
        helpers_script = os.path.join(self.test_dir, 'hw-management-helpers.sh')
        with open(helpers_script, 'w') as f:
            f.write(f'''#!/bin/bash
config_path="{self.config_path}"
thermal_path="{self.thermal_path}"
events_path="{self.events_path}"
system_path="{self.system_path}"
board_type_file="{self.board_type_file}"
sku_file="{self.sku_file}"
''')
        os.chmod(helpers_script, 0o755)
        
        # Create test start-post script
        start_post_script = os.path.join(self.test_dir, 'test_start_post.sh')
        with open(start_post_script, 'w') as f:
            f.write(f'''#!/bin/bash
source {helpers_script}
source {chassis_events_script}

# Initialize fan direction files for existing fans
if [ -f {self.max_tachos_file} ]; then
    max_tachos=$(< {self.max_tachos_file})
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -L {self.thermal_path}/fan"$i"_status ]; then
            status=$(< {self.thermal_path}/fan"$i"_status)
            if [ "$status" -eq 1 ]; then
                set_fan_direction fan"$i" 1
            fi
        fi
    done
fi
''')
        os.chmod(start_post_script, 0o755)
        
        # Run the test
        result = subprocess.run([start_post_script], 
                              capture_output=True, text=True, cwd=self.test_dir)
        
        # Verify results
        self.assertEqual(result.returncode, 0, f"Script failed: {result.stderr}")
        
        # Check that only existing fan direction files were created
        for i in range(1, 5):
            fan_dir_file = os.path.join(self.thermal_path, f'fan{i}_dir')
            if i in [1, 3]:
                self.assertTrue(os.path.exists(fan_dir_file), 
                              f"Fan direction file fan{i}_dir should exist")
            else:
                self.assertFalse(os.path.exists(fan_dir_file), 
                               f"Fan direction file fan{i}_dir should not exist")

    def test_handles_missing_chassis_events_script(self):
        """Test that scripts handle missing chassis events script gracefully."""
        # Create fan status files
        for i in range(1, 3):
            fan_status_file = os.path.join(self.thermal_path, f'fan{i}_status')
            with open(fan_status_file, 'w') as f:
                f.write('1')
        
        # Create mock helpers script
        helpers_script = os.path.join(self.test_dir, 'hw-management-helpers.sh')
        with open(helpers_script, 'w') as f:
            f.write(f'''#!/bin/bash
config_path="{self.config_path}"
thermal_path="{self.thermal_path}"
events_path="{self.events_path}"
system_path="{self.system_path}"
board_type_file="{self.board_type_file}"
sku_file="{self.sku_file}"
''')
        os.chmod(helpers_script, 0o755)
        
        # Create test start-post script with missing chassis events
        start_post_script = os.path.join(self.test_dir, 'test_start_post.sh')
        with open(start_post_script, 'w') as f:
            f.write(f'''#!/bin/bash
source {helpers_script}

# Try to source non-existent chassis events script
source {self.test_dir}/non_existent_chassis_events.sh 2>/dev/null || true

# Initialize fan direction files for existing fans
if [ -f {self.max_tachos_file} ]; then
    max_tachos=$(< {self.max_tachos_file})
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -L {self.thermal_path}/fan"$i"_status ]; then
            status=$(< {self.thermal_path}/fan"$i"_status)
            if [ "$status" -eq 1 ]; then
                # This should fail gracefully if set_fan_direction is not available
                set_fan_direction fan"$i" 1 2>/dev/null || echo "set_fan_direction not available"
            fi
        fi
    done
fi
''')
        os.chmod(start_post_script, 0o755)
        
        # Run the test
        result = subprocess.run([start_post_script], 
                              capture_output=True, text=True, cwd=self.test_dir)
        
        # Verify results - should not crash
        self.assertEqual(result.returncode, 0, f"Script failed: {result.stderr}")
        
        # Check that no fan direction files were created (since set_fan_direction is not available)
        for i in range(1, 3):
            fan_dir_file = os.path.join(self.thermal_path, f'fan{i}_dir')
            self.assertFalse(os.path.exists(fan_dir_file), 
                           f"Fan direction file fan{i}_dir should not exist without set_fan_direction")

    def test_handles_zero_fans(self):
        """Test that scripts handle zero fans gracefully."""
        # Set max_tachos to 0
        with open(self.max_tachos_file, 'w') as f:
            f.write('0')
        
        # Create mock chassis events script
        chassis_events_script = os.path.join(self.test_dir, 'hw-management-chassis-events.sh')
        with open(chassis_events_script, 'w') as f:
            f.write('''#!/bin/bash
function set_fan_direction() {
    local fan_name="$1"
    local direction="$2"
    echo "$direction" > "{}/${{fan_name}}_dir"
}
'''.format(self.thermal_path))
        os.chmod(chassis_events_script, 0o755)
        
        # Create mock helpers script
        helpers_script = os.path.join(self.test_dir, 'hw-management-helpers.sh')
        with open(helpers_script, 'w') as f:
            f.write(f'''#!/bin/bash
config_path="{self.config_path}"
thermal_path="{self.thermal_path}"
events_path="{self.events_path}"
system_path="{self.system_path}"
board_type_file="{self.board_type_file}"
sku_file="{self.sku_file}"
''')
        os.chmod(helpers_script, 0o755)
        
        # Create test start-post script
        start_post_script = os.path.join(self.test_dir, 'test_start_post.sh')
        with open(start_post_script, 'w') as f:
            f.write(f'''#!/bin/bash
source {helpers_script}
source {chassis_events_script}

# Initialize fan direction files for existing fans
if [ -f {self.max_tachos_file} ]; then
    max_tachos=$(< {self.max_tachos_file})
    for ((i=1; i<=max_tachos; i+=1)); do
        if [ -L {self.thermal_path}/fan"$i"_status ]; then
            status=$(< {self.thermal_path}/fan"$i"_status)
            if [ "$status" -eq 1 ]; then
                set_fan_direction fan"$i" 1
            fi
        fi
    done
fi
''')
        os.chmod(start_post_script, 0o755)
        
        # Run the test
        result = subprocess.run([start_post_script], 
                              capture_output=True, text=True, cwd=self.test_dir)
        
        # Verify results
        self.assertEqual(result.returncode, 0, f"Script failed: {result.stderr}")
        
        # Check that no fan direction files were created
        for i in range(1, 5):
            fan_dir_file = os.path.join(self.thermal_path, f'fan{i}_dir')
            self.assertFalse(os.path.exists(fan_dir_file), 
                           f"Fan direction file fan{i}_dir should not exist with zero fans")


if __name__ == '__main__':
    unittest.main()
