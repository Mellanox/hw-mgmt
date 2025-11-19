# Thermal Module TEC Sensor Unittest - Version 2.5.0

Comprehensive unittest for `thermal_module_tec_sensor` class from `hw_management_thermal_control_2_5.py`.

## Overview

This test suite provides thorough testing of the `thermal_module_tec_sensor` class with:
- 🎯 **7 comprehensive test scenarios** covering all major functionality
- 🎨 **Beautiful colored output** with icons and progress indicators  
- 🔧 **Configurable test iterations** via command line arguments
- 📊 **Detailed error reporting** with stack traces and system context
- **Status print validation** after each test iteration
- 🧪 **Standalone execution** with no external dependencies

## Test Scenarios

### 1. Normal Condition Testing (configurable iterations)
- **Description**: Tests normal operation with random temperature and cooling level values
- **Input**: Random `module{N}_temp_input` (20-80°C, scaled by 1000) and `module{N}_cooling_level_{}` values
- **Expected**: PWM range 20-100, no sensor read errors
- **Status Print**: After each iteration

### 2. Sensor Missing File Error Testing (configurable iterations)  
- **Description**: Tests behavior when sensor files are missing
- **Input**: Randomly removes one of: `_temp_input`, `_cooling_level_input`, `_cooling_level_warning`
- **Expected**: PWM set according to thermal table, `SENSOR_READ_ERR` after 3 repeating errors
- **Status Print**: After each iteration

### 3. Sensor Invalid Value Error Testing (configurable iterations)
- **Description**: Tests behavior with non-integer/invalid sensor values
- **Input**: Random invalid values: "", "not_a_number", "12.5.7", "inf", "NaN", etc.
- **Expected**: PWM set according to thermal table, `SENSOR_READ_ERR` after 3 repeating errors  
- **Status Print**: After each iteration

### 4. Sensor Out-of-Range Error Testing (configurable iterations)
- **Description**: Tests behavior when cooling level values exceed lcrit/hcrit bounds
- **Input**: Random values outside range (below 0 or above 960)
- **Expected**: PWM set according to thermal table, `SENSOR_READ_ERR` after 3 repeating errors
- **Status Print**: After each iteration

### 5. Config Missing Parameters Testing (configurable iterations)
- **Description**: Tests robustness when configuration parameters are undefined
- **Input**: Missing parameters: "val_lcrit", "val_hcrit", "pwm_min", "pwm_max", "val_min", "val_max"
- **Expected**: Graceful handling with default values, no crashes
- **Status Print**: After each iteration

### 6. Error Handling Testing (configurable iterations)  
- **Description**: Tests that functions don't crash under various error conditions
- **Input**: Corrupted paths, non-existent directories, very long paths
- **Expected**: Function completes without exceptions regardless of file system errors
- **Status Print**: After each iteration

### 7. Status Print Summary and Validation
- **Description**: Summary validation of `__str__` function across different sensor states
- **Expected**: No crashes/errors, proper string formatting
- **Note**: Status print function (`__str__`) is called after each iteration of tests #1-#6

## Key Features

### Beautiful Output
- 🎨 **Colored terminal output** with ANSI color codes
- 🎯 **Unicode icons** for visual feedback (PASS/FAIL/WARN/INFO)
- 📊 **Progress indicators** and iteration counters
- 🏆 **Summary statistics** with pass/fail counts

### Detailed Error Reporting
The test suite includes comprehensive error reporting that captures:

#### Captured Information
- **Test Context**: Test method, class, and execution details
- **System Information**: Python version, platform, timestamp
- **Exception Details**: Full exception type, message, and stack trace  
- **Sensor State**: Current sensor configuration, PWM values, fault states
- **Environment**: Temporary directories, configuration keys

#### Visual Examples
```
🔧 Error Report #1
Test: TestThermalModuleTecSensor.test_03_sensor_invalid_value_error
Type: ERROR
Exception: ValueError: invalid literal for int() with base 10: 'not_a_number'
Timestamp: 2025-09-24T10:30:45.123456
Python: 3.8.10 on Linux-6.12.38+deb13-amd64
Context:
  sensor_name: module1
  sensor_type: TEC
  sensor_pwm: 100
  temp_directory: /tmp/tmpxyz123
```

### Configurable Iterations
```bash
# Default 10 iterations
python test_thermal_module_tec_sensor.py

# Custom iteration count
python test_thermal_module_tec_sensor.py --iterations 20
python test_thermal_module_tec_sensor.py -i 5
```

### Status Print Output
Each test iteration displays the sensor status, showing:
```
ℹ️ Status [normal_test_1]: "module1  " temp:32.0, cooling_lvl:465.0, cooling_lvl_max:555.0, faults:[], pwm: 86.0, STOPPED
ℹ️ Status [missing_file_1]: "module1  " temp:0.0, cooling_lvl:0.0, cooling_lvl_max:0.0, faults:[sensor_read_error], pwm: 100.0, STOPPED  
ℹ️ Status [out_of_range_1]: "module1  " temp:45.0, cooling_lvl:-86.0, cooling_lvl_max:100.0, faults:[sensor_read_error], pwm: 100.0, STOPPED
```

## Usage

### Basic Execution
```bash
cd /auto/mtrsysgwork/oleksandrs/hw-managment/hw_mgmt_clean/unittest/hw_mgmt_thermal_control_250/module_tec_4359937/
python test_thermal_module_tec_sensor.py
```

### With Custom Iterations  
```bash
python test_thermal_module_tec_sensor.py --iterations 15
python test_thermal_module_tec_sensor.py -i 25
```

### Direct Execution
```bash
./test_thermal_module_tec_sensor.py
./test_thermal_module_tec_sensor.py --iterations 30
```

## Requirements

- Python 3.6+
- Access to `hw_management_thermal_control_2_5.py` source file
- Write permissions for temporary test directories
- Linux/Unix environment (for colored output)

## Output Examples

### Successful Test Run
```
🚀 THERMAL MODULE TEC SENSOR UNITTEST - VERSION 2.5.0
===============================================================================
Testing: thermal_module_tec_sensor from hw_management_thermal_control_2_5.py

🎲 Testing normal operation with random values (10 iterations)...
  ⚙️ Iteration 1: temp=32°C, cooling_level=465, warning=555
    ℹ️ Status [normal_test_1]: "module1  " temp:32.0, cooling_lvl:465.0, cooling_lvl_max:555.0, faults:[], pwm: 86.0, STOPPED
PASS TestThermalModuleTecSensor.test_01_normal_condition_random

TEST SUMMARY
===============================================================================
Passed: 7
Failed: 0  
💥 Errors: 0
📊 Total: 7

🎉 ALL TESTS PASSED! 🎉
```

## Error Reporting Features

- **System Context**: Captures Python version, platform info, and timestamps
- **Test State**: Records sensor configuration, PWM values, and fault conditions  
- **Exception Tracking**: Full stack traces with file locations and line numbers
- **Environment Info**: Temporary directory paths and configuration details
- **Visual Formatting**: Color-coded output with clear section separation

## Technical Details

### Version Information
- **Source**: `hw_management_thermal_control_2_5.py` (Version 2.5.0)
- **Test Version**: 2.5.0  
- **Location**: `/auto/mtrsysgwork/oleksandrs/hw-managment/hw_mgmt_clean/unittest/hw_mgmt_thermal_control_250/module_tec_4359937/`

### Key Classes Tested
- `thermal_module_tec_sensor`: Main TEC sensor control class
- `CONST`: Constants and configuration definitions
- `DMIN_TABLE_DEFAULT`: Default thermal response table

### Mock Framework
- **File System Simulation**: Creates temporary sensor files
- **Configuration Mocking**: Simulates system configuration dictionaries
- **Error Injection**: Controlled failure simulation for robustness testing
- **Clean Test Isolation**: Each iteration starts with cleared fault states

## Validation Criteria

- **PWM Range**: 20-100% for normal conditions  
- **Error Response**: `SENSOR_READ_ERR` after 3 consecutive failures  
- **Fault Isolation**: Clean fault state before each iteration  
- **Exception Handling**: No crashes under error conditions  
- **Status Output**: Valid string representation of sensor state  
- **Configuration Flexibility**: Graceful handling of missing parameters
