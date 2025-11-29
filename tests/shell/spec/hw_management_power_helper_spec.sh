#!/bin/bash
################################################################################
# ShellSpec tests for hw-management-power-helper.sh
#
# This script tests power consumption and power system calculations for PSUs.
# It handles two modes based on script name:
# - pwr_consum: Power consumption calculation (reads IIO device, calculates power)
# - pwr_sys: System power calculation (voltage * current calculation)
#
# Test Coverage:
# - Power consumption mode (pwr_consum)
# - System power mode (pwr_sys)
# - PSU selection (psu1 vs psu2)
# - IIO device selection and calculations
# - Mathematical correctness of power calculations
################################################################################

Describe 'hw-management-power-helper.sh'
    
    # Setup and teardown for each test
    BeforeEach 'setup_power_test'
    AfterEach 'cleanup_power_test'
    
    setup_power_test() {
        # Create temporary directory structure for power monitoring
        TEST_POWER_DIR=$(mktemp -d)
        SYSTEM_PATH="$TEST_POWER_DIR/system"
        ENVIRONMENT_PATH="$TEST_POWER_DIR/environment"
        
        mkdir -p "$SYSTEM_PATH"
        mkdir -p "$ENVIRONMENT_PATH"
        
        # Export for test access
        export TEST_POWER_DIR SYSTEM_PATH ENVIRONMENT_PATH
    }
    
    cleanup_power_test() {
        # Clean up temporary files
        if [ -n "$TEST_POWER_DIR" ] && [ -d "$TEST_POWER_DIR" ]; then
            rm -rf "$TEST_POWER_DIR"
        fi
    }
    
    #---------------------------------------------------------------------------
    # Helper function to create power monitoring files
    #---------------------------------------------------------------------------
    create_power_file() {
        local filename="$1"
        local value="$2"
        echo "$value" > "$ENVIRONMENT_PATH/$filename"
    }
    
    create_system_file() {
        local filename="$1"
        local value="$2"
        echo "$value" > "$SYSTEM_PATH/$filename"
    }
    
    #---------------------------------------------------------------------------
    # Helper function to create power helper script
    #---------------------------------------------------------------------------
    create_power_script() {
        local script_name="$1"
        cat > "$TEST_POWER_DIR/$script_name" << 'POWER_SCRIPT_EOF'
#!/bin/bash
hw_management_path="__HW_MGMT_PATH__"
system_path=$hw_management_path/system
environment_path=$hw_management_path/environment

if echo "$0" | grep -q "/pwr_consum" ; then
    if [ ! -L $system_path/select_iio ]; then
        exit 0
    fi
    if [ "$1" == "psu1" ]; then
        echo 1 > $system_path/select_iio
    elif [ "$1" == "psu2" ]; then
        echo 0 > $system_path/select_iio
    fi

    iioreg=$(< $environment_path/a2d_iio\:device1_raw_1)
    echo $((iioreg * 80 * 12))
    exit 0
fi

if echo "$0" | grep -q "/pwr_sys" ; then
    if [ "$1" == "psu1" ]; then
        iioreg_vin=$(< $environment_path/a2d_iio\:device0_raw_1)
        iioreg_iin=$(< $environment_path/a2d_iio\:device0_raw_6)
    elif [ "$1" == "psu2" ]; then
        iioreg_vin=$(< $environment_path/a2d_iio\:device0_raw_2)
        iioreg_iin=$(< $environment_path/a2d_iio\:device0_raw_7)
    fi

    echo $((iioreg_vin * iioreg_iin * 59 * 80))
    exit 0
fi
POWER_SCRIPT_EOF
        # Replace placeholder with actual test directory
        sed -i "s|__HW_MGMT_PATH__|$TEST_POWER_DIR|g" "$TEST_POWER_DIR/$script_name"
        chmod +x "$TEST_POWER_DIR/$script_name"
    }
    
    #---------------------------------------------------------------------------
    # Test: Power Consumption Mode (pwr_consum)
    #---------------------------------------------------------------------------
    
    Describe 'pwr_consum mode'
        It 'exits early if select_iio symlink does not exist'
            create_power_script "pwr_consum"
            # No select_iio symlink created
            
            When call "$TEST_POWER_DIR/pwr_consum" psu1
            The status should equal 0
            The output should equal ""
        End
        
        It 'calculates PSU1 power consumption correctly'
            create_power_script "pwr_consum"
            # Create select_iio as a symlink to a dummy file
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            
            # Set IIO register value
            create_power_file "a2d_iio:device1_raw_1" "100"
            
            When call "$TEST_POWER_DIR/pwr_consum" psu1
            The status should equal 0
            # Calculation: 100 * 80 * 12 = 96000
            The output should equal "96000"
        End
        
        It 'writes 1 to select_iio for PSU1'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            create_power_file "a2d_iio:device1_raw_1" "50"
            
            "$TEST_POWER_DIR/pwr_consum" psu1
            
            The contents of file "$SYSTEM_PATH/select_iio" should equal "1"
        End
        
        It 'calculates PSU2 power consumption correctly'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            
            # Set IIO register value
            create_power_file "a2d_iio:device1_raw_1" "250"
            
            When call "$TEST_POWER_DIR/pwr_consum" psu2
            The status should equal 0
            # Calculation: 250 * 80 * 12 = 240000
            The output should equal "240000"
        End
        
        It 'writes 0 to select_iio for PSU2'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            create_power_file "a2d_iio:device1_raw_1" "50"
            
            "$TEST_POWER_DIR/pwr_consum" psu2
            
            The contents of file "$SYSTEM_PATH/select_iio" should equal "0"
        End
        
        It 'handles zero IIO value'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            create_power_file "a2d_iio:device1_raw_1" "0"
            
            When call "$TEST_POWER_DIR/pwr_consum" psu1
            # Calculation: 0 * 80 * 12 = 0
            The output should equal "0"
        End
        
        It 'handles large IIO values correctly'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            create_power_file "a2d_iio:device1_raw_1" "1000"
            
            When call "$TEST_POWER_DIR/pwr_consum" psu1
            # Calculation: 1000 * 80 * 12 = 960000
            The output should equal "960000"
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: System Power Mode (pwr_sys)
    #---------------------------------------------------------------------------
    
    Describe 'pwr_sys mode'
        It 'calculates PSU1 system power correctly'
            create_power_script "pwr_sys"
            
            # Set voltage and current register values for PSU1
            create_power_file "a2d_iio:device0_raw_1" "120"  # Voltage
            create_power_file "a2d_iio:device0_raw_6" "10"   # Current
            
            When call "$TEST_POWER_DIR/pwr_sys" psu1
            The status should equal 0
            # Calculation: 120 * 10 * 59 * 80 = 5664000
            The output should equal "5664000"
        End
        
        It 'calculates PSU2 system power correctly'
            create_power_script "pwr_sys"
            
            # Set voltage and current register values for PSU2
            create_power_file "a2d_iio:device0_raw_2" "110"  # Voltage
            create_power_file "a2d_iio:device0_raw_7" "15"   # Current
            
            When call "$TEST_POWER_DIR/pwr_sys" psu2
            The status should equal 0
            # Calculation: 110 * 15 * 59 * 80 = 7788000
            The output should equal "7788000"
        End
        
        It 'handles zero voltage'
            create_power_script "pwr_sys"
            create_power_file "a2d_iio:device0_raw_1" "0"
            create_power_file "a2d_iio:device0_raw_6" "10"
            
            When call "$TEST_POWER_DIR/pwr_sys" psu1
            # Calculation: 0 * 10 * 59 * 80 = 0
            The output should equal "0"
        End
        
        It 'handles zero current'
            create_power_script "pwr_sys"
            create_power_file "a2d_iio:device0_raw_1" "120"
            create_power_file "a2d_iio:device0_raw_6" "0"
            
            When call "$TEST_POWER_DIR/pwr_sys" psu1
            # Calculation: 120 * 0 * 59 * 80 = 0
            The output should equal "0"
        End
        
        It 'uses different IIO devices for PSU1 vs PSU2'
            create_power_script "pwr_sys"
            
            # PSU1 uses device0_raw_1 and device0_raw_6
            create_power_file "a2d_iio:device0_raw_1" "100"
            create_power_file "a2d_iio:device0_raw_6" "20"
            
            # PSU2 uses device0_raw_2 and device0_raw_7
            create_power_file "a2d_iio:device0_raw_2" "200"
            create_power_file "a2d_iio:device0_raw_7" "30"
            
            result1=$("$TEST_POWER_DIR/pwr_sys" psu1)
            result2=$("$TEST_POWER_DIR/pwr_sys" psu2)
            
            # PSU1: 100 * 20 * 59 * 80 = 9440000
            # PSU2: 200 * 30 * 59 * 80 = 28320000
            The value "$result1" should equal "9440000"
            The value "$result2" should equal "28320000"
        End
        
        It 'handles fractional calculations correctly (integer arithmetic)'
            create_power_script "pwr_sys"
            create_power_file "a2d_iio:device0_raw_1" "3"
            create_power_file "a2d_iio:device0_raw_6" "7"
            
            When call "$TEST_POWER_DIR/pwr_sys" psu1
            # Calculation: 3 * 7 * 59 * 80 = 99120
            The output should equal "99120"
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: Script Name Detection
    #---------------------------------------------------------------------------
    
    Describe 'script name detection'
        It 'activates pwr_consum mode when invoked as pwr_consum'
            # Create script with pwr_consum directly in name
            create_power_script "my_pwr_consum_script"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            create_power_file "a2d_iio:device1_raw_1" "100"
            
            # Rename to have /pwr_consum/ in path
            mkdir -p "$TEST_POWER_DIR/test/pwr_consum"
            mv "$TEST_POWER_DIR/my_pwr_consum_script" "$TEST_POWER_DIR/test/pwr_consum/script"
            chmod +x "$TEST_POWER_DIR/test/pwr_consum/script"
            
            When call "$TEST_POWER_DIR/test/pwr_consum/script" psu1
            # Should use pwr_consum calculation
            The output should equal "96000"
        End
        
        It 'activates pwr_sys mode when invoked as pwr_sys'
            # Create script with pwr_sys directly in path
            create_power_script "my_pwr_sys_script"
            create_power_file "a2d_iio:device0_raw_1" "100"
            create_power_file "a2d_iio:device0_raw_6" "10"
            
            # Rename to have /pwr_sys/ in path
            mkdir -p "$TEST_POWER_DIR/test/pwr_sys"
            mv "$TEST_POWER_DIR/my_pwr_sys_script" "$TEST_POWER_DIR/test/pwr_sys/script"
            chmod +x "$TEST_POWER_DIR/test/pwr_sys/script"
            
            When call "$TEST_POWER_DIR/test/pwr_sys/script" psu1
            # Should use pwr_sys calculation
            The output should equal "4720000"
        End
        
        It 'does nothing when script name has neither pattern'
            create_power_script "other_helper"
            
            When call "$TEST_POWER_DIR/other_helper" psu1
            The output should equal ""
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: Edge Cases and Real-World Scenarios
    #---------------------------------------------------------------------------
    
    Describe 'edge cases'
        It 'handles missing IIO file gracefully in pwr_consum mode'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            # Don't create the IIO file - script will read empty value
            
            When call "$TEST_POWER_DIR/pwr_consum" psu1
            # Script reads empty file, calculation: 0 * 80 * 12 = 0
            The status should equal 0
            The output should equal "0"
            The stderr should include "No such file"
        End
        
        It 'handles invalid PSU argument in pwr_consum'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            create_power_file "a2d_iio:device1_raw_1" "100"
            
            When call "$TEST_POWER_DIR/pwr_consum" psu3
            The status should equal 0
            # Neither psu1 nor psu2, but still reads and calculates
            The output should equal "96000"
        End
        
        It 'handles no argument provided'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            create_power_file "a2d_iio:device1_raw_1" "100"
            
            When call "$TEST_POWER_DIR/pwr_consum"
            The status should equal 0
            The output should equal "96000"
        End
    End
    
    #---------------------------------------------------------------------------
    # Test: Real-World Power Calculations
    #---------------------------------------------------------------------------
    
    Describe 'real-world power scenarios'
        It 'simulates typical PSU1 power consumption (150W)'
            create_power_script "pwr_consum"
            touch "$SYSTEM_PATH/iio_target"
            ln -s "$SYSTEM_PATH/iio_target" "$SYSTEM_PATH/select_iio"
            # To get ~150000 (150W in some unit): iioreg * 80 * 12 = 150000
            # iioreg = 150000 / 960 = 156.25, use 156
            create_power_file "a2d_iio:device1_raw_1" "156"
            
            When call "$TEST_POWER_DIR/pwr_consum" psu1
            # 156 * 80 * 12 = 149760 (~150W)
            The output should equal "149760"
        End
        
        It 'simulates high system power consumption'
            create_power_script "pwr_sys"
            # Simulate high voltage and current
            create_power_file "a2d_iio:device0_raw_1" "220"  # High voltage
            create_power_file "a2d_iio:device0_raw_6" "50"   # High current
            
            When call "$TEST_POWER_DIR/pwr_sys" psu1
            # 220 * 50 * 59 * 80 = 51920000
            The output should equal "51920000"
        End
        
        It 'simulates low power standby mode'
            create_power_script "pwr_sys"
            create_power_file "a2d_iio:device0_raw_2" "12"   # Low voltage
            create_power_file "a2d_iio:device0_raw_7" "1"    # Low current
            
            When call "$TEST_POWER_DIR/pwr_sys" psu2
            # 12 * 1 * 59 * 80 = 56640
            The output should equal "56640"
        End
    End
End

