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

################################################################################
# ShellSpec tests for hw-management-led-state-conversion.sh
#
# This script tests LED state conversion logic which reads LED control files
# and determines the current LED state (color, blinking, etc.)
#
# Test Coverage:
# - LED state detection (on, off, blinking)
# - Color parsing (red, green, amber, blue, etc.)
# - Blink detection (delay_on, delay_off)
# - File parsing and state conversion
################################################################################

Describe 'hw-management-led-state-conversion.sh'
    
    # Setup and teardown for each test
    BeforeEach 'setup_led_test'
    AfterEach 'cleanup_led_test'
    
    setup_led_test() {
        # Create temporary directory structure for LED files
        TEST_LED_DIR=$(mktemp -d)
        LED_NAME="led_status"

        # Export for test access
        export TEST_LED_DIR LED_NAME
    }

    cleanup_led_test() {
        # Clean up temporary LED files
        if [ -n "$TEST_LED_DIR" ] && [ -d "$TEST_LED_DIR" ]; then
            rm -rf "$TEST_LED_DIR"
        fi
    }

    #---------------------------------------------------------------------------
    # Helper function to create LED file
    #---------------------------------------------------------------------------
    create_led_file() {
        local filename="$1"
        local value="$2"
        echo "$value" > "$TEST_LED_DIR/$filename"
    }

    #---------------------------------------------------------------------------
    # Path to the real script under test (resolved once at Describe scope)
    #---------------------------------------------------------------------------
    REAL_LED_SCRIPT="$(readlink -f "${SHELLSPEC_SPECDIR}/../../../usr/usr/bin/hw-management-led-state-conversion.sh")"

    #---------------------------------------------------------------------------
    # Helper function to run the script in test environment
    #
    # hw-management-led-state-conversion.sh derives both DNAME and LED_NAME
    # from $0, so $0 must look like: <led-dir>/led_status_state
    #   DNAME   = $TEST_LED_DIR   (where LED sysfs files live)
    #   LED_NAME = led_status     (basename split by '_', first 2 fields)
    #
    # We create a symlink at $TEST_LED_DIR/led_status_state → real script,
    # then exec that symlink directly.  kcov tracks coverage via ptrace on
    # the exec'd process (following the symlink to the real file), so the
    # real script path appears in the coverage report.
    #---------------------------------------------------------------------------
    run_led_conversion() {
        ln -sf "$REAL_LED_SCRIPT" "$TEST_LED_DIR/led_status_state"
        "$TEST_LED_DIR/led_status_state"
    }
    
    #---------------------------------------------------------------------------
    # Test: LED Off State (all zeros)
    #---------------------------------------------------------------------------
    
    Describe 'LED off state detection'
        It 'detects LED off when all values are zero'
            create_led_file "${LED_NAME}_red" "0"
            create_led_file "${LED_NAME}_green" "0"
            
            When call run_led_conversion
            The path "$TEST_LED_DIR/$LED_NAME" should be exist
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "none"
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: LED Solid Color State
    #---------------------------------------------------------------------------
    
    Describe 'LED solid color detection'
        It 'detects solid red LED'
            create_led_file "${LED_NAME}_red" "255"
            create_led_file "${LED_NAME}_green" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "red"
        End
        
        It 'detects solid green LED'
            create_led_file "${LED_NAME}_red" "0"
            create_led_file "${LED_NAME}_green" "255"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "green"
        End
        
        It 'detects solid blue LED'
            create_led_file "${LED_NAME}_blue" "1"
            create_led_file "${LED_NAME}_red" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "blue"
        End
        
        It 'detects solid amber LED'
            create_led_file "${LED_NAME}_amber" "100"
            create_led_file "${LED_NAME}_red" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "amber"
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: LED Blinking State
    #---------------------------------------------------------------------------
    
    Describe 'LED blinking detection'
        It 'detects red blinking LED'
            create_led_file "${LED_NAME}_red" "255"
            create_led_file "${LED_NAME}_red_delay_on" "500"
            create_led_file "${LED_NAME}_red_delay_off" "500"
            create_led_file "${LED_NAME}_green" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "red_blink"
        End
        
        It 'detects green blinking LED'
            create_led_file "${LED_NAME}_green" "255"
            create_led_file "${LED_NAME}_green_delay_on" "200"
            create_led_file "${LED_NAME}_green_delay_off" "200"
            create_led_file "${LED_NAME}_red" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "green_blink"
        End
        
        It 'does not detect blink when delay_on is zero'
            create_led_file "${LED_NAME}_red" "255"
            create_led_file "${LED_NAME}_red_delay_on" "0"
            create_led_file "${LED_NAME}_red_delay_off" "500"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "red"
        End
        
        It 'does not detect blink when delay_off is zero'
            create_led_file "${LED_NAME}_red" "255"
            create_led_file "${LED_NAME}_red_delay_on" "500"
            create_led_file "${LED_NAME}_red_delay_off" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "red"
        End
        
        It 'does not detect blink when brightness is zero'
            create_led_file "${LED_NAME}_red" "0"
            create_led_file "${LED_NAME}_red_delay_on" "500"
            create_led_file "${LED_NAME}_red_delay_off" "500"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "none"
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: Multiple LED Files (priority/precedence)
    #---------------------------------------------------------------------------
    
    Describe 'multiple LED color handling'
        It 'handles multiple colors with one active'
            create_led_file "${LED_NAME}_red" "0"
            create_led_file "${LED_NAME}_green" "255"
            create_led_file "${LED_NAME}_blue" "0"
            create_led_file "${LED_NAME}_amber" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "green"
        End
        
        It 'returns first active LED when multiple are on'
            # This tests the script's actual behavior (first found wins)
            create_led_file "${LED_NAME}_amber" "100"
            create_led_file "${LED_NAME}_green" "200"
            create_led_file "${LED_NAME}_red" "0"
            
            When call run_led_conversion
            # Result depends on file ordering
            The path "$TEST_LED_DIR/$LED_NAME" should be exist
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: Edge Cases
    #---------------------------------------------------------------------------
    
    Describe 'edge cases'
        It 'handles missing LED files gracefully'
            # No LED files created
            When call run_led_conversion
            The path "$TEST_LED_DIR/$LED_NAME" should be exist
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "none"
        End
        
        It 'ignores _state and _capability files'
            create_led_file "${LED_NAME}_state" "some_state"
            create_led_file "${LED_NAME}_capability" "capability_info"
            create_led_file "${LED_NAME}_red" "255"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "red"
        End
        
        It 'handles non-numeric brightness values'
            # Create file with invalid value (script treats as string comparison)
            create_led_file "${LED_NAME}_red" "invalid"
            
            When call run_led_conversion
            # Script compares string "invalid" != "0", so treats as "on"
            The path "$TEST_LED_DIR/$LED_NAME" should be exist
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: Real-world LED Patterns
    #---------------------------------------------------------------------------
    
    Describe 'real-world LED patterns'
        It 'simulates system health: green solid = healthy'
            create_led_file "${LED_NAME}_red" "0"
            create_led_file "${LED_NAME}_green" "255"
            create_led_file "${LED_NAME}_green_delay_on" "0"
            create_led_file "${LED_NAME}_green_delay_off" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "green"
        End
        
        It 'simulates system warning: amber blinking'
            create_led_file "${LED_NAME}_amber" "200"
            create_led_file "${LED_NAME}_amber_delay_on" "1000"
            create_led_file "${LED_NAME}_amber_delay_off" "1000"
            create_led_file "${LED_NAME}_red" "0"
            create_led_file "${LED_NAME}_green" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "amber_blink"
        End
        
        It 'simulates system error: red blinking'
            create_led_file "${LED_NAME}_red" "255"
            create_led_file "${LED_NAME}_red_delay_on" "250"
            create_led_file "${LED_NAME}_red_delay_off" "250"
            create_led_file "${LED_NAME}_green" "0"
            
            When call run_led_conversion
            The contents of file "$TEST_LED_DIR/$LED_NAME" should equal "red_blink"
        End
    End
End

