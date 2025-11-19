# Thermal Module TEC Sensor Unit Tests

## Overview

This directory contains comprehensive unit tests for the `thermal_module_tec_sensor` class from the hardware management thermal control system.

## Features

- 🌡️ **Beautiful Colored Output**: Visual indicators with colors and icons
- 🎲 **Random Testing**: Comprehensive random value testing for robustness
- 💥 **Error Simulation**: Tests all error conditions and edge cases
- ⚙️ **Configuration Testing**: Tests missing and invalid configuration parameters
- 📁 **File System Mocking**: Simulates various file system states
- 🔥 **100% Standalone**: Self-contained with all dependencies mocked
- 🚨 **Detailed Error Reporting**: Comprehensive crash analysis with stack traces and context

## Test Scenarios

### 1. Normal Condition Testing (random)
- **Description**: Tests normal operation with random sensor values (configurable iterations)
- **Input**: Random temperature (20-80°C), cooling levels (0-960), flow directions
- **Expected**: PWM calculated correctly as `cooling_level_input/cooling_level_warning * 100%`
- **Range**: PWM should be between 20-100%

### 2. Sensor Missing File Error Testing
- **Description**: Tests behavior when sensor files are missing (configurable iterations)
- **Files Tested**: Randomly selects from:
  - `thermal/module{N}_temp_input`
  - `thermal/module{N}_cooling_level_input`
  - `thermal/module{N}_cooling_level_warning`
- **Random Parameters**: Flow direction, ambient temperature
- **Expected**: SENSOR_READ_ERR raised after 3+ repeated errors

### 3. Sensor Invalid Value Error Testing
- **Description**: Tests behavior with non-integer/invalid sensor values (configurable iterations)
- **Invalid Values**: Randomly selects from: `""`, `"abc"`, `"12.34.56"`, `"not_a_number"`, `" "`, `"\n"`, `"NaN"`, `"inf"`, `"-inf"`, `"123abc"`, `"++123"`
- **Random Selection**: File and invalid value combinations
- **Expected**: SENSOR_READ_ERR raised after 3+ repeated errors

### 4. Sensor Out-of-Range Error Testing
- **Description**: Tests behavior when cooling levels are outside lcrit/hcrit range (configurable iterations)
- **Test Cases**: Randomly generates values below lcrit (-100 to -1) and above hcrit (961 to 2000)
- **Random Parameters**: Flow direction, ambient temperature
- **Expected**: SENSOR_READ_ERR raised after 3+ repeated errors

### 5. Config Missing Parameters Testing
- **Description**: Tests behavior with missing configuration parameters (configurable iterations)
- **Parameters Tested**: Randomly selects from `val_lcrit`, `val_hcrit`, `pwm_min`, `pwm_max`, `val_min`, `val_max`
- **Random Parameters**: Flow direction, ambient temperature
- **Expected**: Sensor uses default values and continues operation

### 6. Error Handling Testing
- **Description**: Tests system robustness under various error conditions (configurable iterations)
- **Scenarios**: Randomly selects from invalid directories, permission errors, corrupted file system, non-existent paths, very long paths
- **Random Parameters**: Flow direction, ambient temperature
- **Expected**: No crashes, graceful error handling

### 7. Status Print Testing
- **Description**: Run print status function (__str__) after each iteration of previous tests (#1-#6)
- **Implementation**: Status print called after every iteration in tests 1-6
- **Coverage**: Total status print calls = iteration_count × 6 tests
- **Output**: Status strings displayed in test logs with full sensor state
- **Validation**: Test 7 provides summary and final validation
- **Expected**: No crashes/errors regardless of sensor state

## Usage

### Run All Tests (Default: 10 iterations)
```bash
cd ./unittest/hw_mgmt_thermal_control_2_0/module_tec_4359937/
python3 test_thermal_module_tec_sensor.py
```

### Run as Executable
```bash
./test_thermal_module_tec_sensor.py
```

### Configurable Iterations
The number of random test iterations can be customized using command line arguments:

```bash
# Quick test with minimal iterations
python3 test_thermal_module_tec_sensor.py --iterations 1

# Moderate testing (5 iterations)
python3 test_thermal_module_tec_sensor.py -i 5

# Extensive testing (25 iterations)
python3 test_thermal_module_tec_sensor.py --iterations 25

# Default behavior (10 iterations)
python3 test_thermal_module_tec_sensor.py
```

### Command Line Options
```bash
python3 test_thermal_module_tec_sensor.py --help
```

**Available Options:**
- `-i, --iterations N`: Number of iterations for random tests (default: 10, minimum: 1)
- `--version`: Show program version
- `-h, --help`: Show help message

## Output Examples

### Successful Test Run
```
================================================================================
                    THERMAL MODULE TEC SENSOR UNIT TESTS                     
                           Beautiful Test Suite                              
================================================================================

🌡️ THERMAL MODULE TEC SENSOR UNIT TESTS

⚙️ Setting up test environment...

🎲 Testing normal operation with random values...
  🌡️ Test 1: temp=45°C, cooling=50/100, PWM=50%, flow=C2P
    ℹ️ Status [normal_test_1]: "module1 " temp:45  , cooling_lvl:50 , cooling_lvl_max:100, faults:[], pwm: 50, STOPPED
  🌡️ Test 2: temp=65°C, cooling=80/160, PWM=50%, flow=P2C
    ℹ️ Status [normal_test_2]: "module1 " temp:65  , cooling_lvl:80 , cooling_lvl_max:160, faults:[], pwm: 50, STOPPED
  ...

PASS TestThermalModuleTecSensor.test_01_normal_condition_random

📁 Testing missing sensor files...
  💥 Iteration 1: Testing missing file: thermal/module1_cooling_level_warning
    ℹ️ Status [missing_file_1]: "module1 " temp:0   , cooling_lvl:50 , cooling_lvl_max:0  , faults:[sensor_read_error], pwm: 100, STOPPED
  💥 Iteration 2: Testing missing file: thermal/module1_cooling_level_input
    ℹ️ Status [missing_file_2]: "module1 " temp:0   , cooling_lvl:0  , cooling_lvl_max:100, faults:[sensor_read_error], pwm: 100, STOPPED
  ...

PASS TestThermalModuleTecSensor.test_02_sensor_missing_file_error

...

================================================================================
⚙️ TEST SUMMARY
================================================================================
ℹ️ Total Tests: 7
✅ Passed: 7
❌ Failed: 0
⏭️ Skipped: 0

🔥 ALL TESTS PASSED! 🔥
================================================================================
Total Random Iterations Executed: 70

### Error Reporting Example

When tests fail, detailed error reports are automatically generated:

```
================================================================================
💥 DETAILED ERROR REPORTS
================================================================================

┌─ ERROR REPORT #1 ─────────────────────────────────────────────────────┐
│ ℹ️ SYSTEM INFORMATION
├─────────────────────────────────────────────────────────────────────────────────┤
│ Timestamp: 2025-09-24T13:43:07.908298
│ Platform: Linux-6.12.38+deb13-amd64-x86_64-with-glibc2.41
│ Python Version: 3.13.5
│ Test Class: TestThermalModuleTecSensor
│ Test Method: test_01_normal_condition_random
│ Error Type: FAILURE
│ Exception: AssertionError: PWM value out of expected range

├─────────────────────────────────────────────────────────────────────────────────┤
│ ⚙️ TEST CONTEXT
├─────────────────────────────────────────────────────────────────────────────────┤
│ Sensor Name: module1
│ Sensor Type: TEC
│ PWM Value: 150
│ Temperature: 45°C
│ Cooling Level: 80
│ Cooling Max: 100
│ Fault List: []
│ Temp Directory: /tmp/tmpXXXXXX

├─────────────────────────────────────────────────────────────────────────────────┤
│ 💥 STACK TRACE
├─────────────────────────────────────────────────────────────────────────────────┤
│ File "test_thermal_module_tec_sensor.py", line 275, in test_01_normal_condition_random
│     self.assertLessEqual(self.sensor.pwm, 100)
│ AssertionError: PWM value out of expected range
└─────────────────────────────────────────────────────────────────────────────────┘
```
```

## Test Architecture

### Mock Components
- **MockThermalSensor**: Simulates hardware sensor files
- **Temporary File System**: Creates isolated test environment
- **Mock Logger**: Captures logging without actual output
- **Mock Configuration**: Provides controlled test configurations

### Color Scheme
- 🟢 **Green**: Successful operations
- 🔴 **Red**: Failures and errors
- 🟡 **Yellow**: Warnings and test descriptions
- 🔵 **Blue**: Headers and information
- 🟣 **Magenta**: Special formatting

## Files

- `test_thermal_module_tec_sensor.py` - Main test suite (executable)
- `test_error_demo.py` - Error reporting demonstration script
- `README.md` - This documentation

## Error Reporting Features

### 🚨 **Comprehensive Crash Analysis**
- **System Information**: Timestamp, platform, Python version, test details
- **Test Context**: Sensor state, configuration, file system status
- **Beautiful Stack Traces**: Color-coded and properly formatted
- **Debugging Context**: Additional state information for troubleshooting

### 🔍 **Captured Information**
- **Sensor State**: Name, type, PWM, temperature, cooling levels, fault list
- **System State**: Temporary directories, file existence, configuration keys
- **Exception Details**: Full exception chain with context
- **Test Parameters**: Iteration number, test description, overrides

### 🎨 **Visual Error Reports**
- **Bordered Reports**: Clear separation between error sections
- **Color Coding**: Different colors for files, exceptions, warnings
- **Structured Layout**: Organized information hierarchy
- **Easy Debugging**: All context needed to reproduce and fix issues

## Dependencies

The test suite is completely standalone and includes all necessary mocking. It only requires:
- Python 3.6+
- Standard library modules: `unittest`, `tempfile`, `random`, `json`, `os`, `sys`

## Technical Details

### PWM Calculation Formula
```
PWM = cooling_level_input / cooling_level_warning * 100%
```

### Temperature Scaling
- Input files store temperature in millidegrees (1°C = 1000 units)
- Tests verify proper scaling (division by 1000)

### Error Thresholds
- File read errors trigger after 3+ consecutive failures
- Error counter resets on successful reads

### Configuration Defaults
- `pwm_min`: 20%
- `pwm_max`: 100%
- `val_lcrit`: 0
- `val_hcrit`: 960
- Temperature range: 20-80°C for testing

## Author

Created by AI Assistant for comprehensive thermal control system testing.
