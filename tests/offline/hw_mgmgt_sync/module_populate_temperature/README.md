# Unit Tests for module_temp_populate Function

This directory contains comprehensive unit tests for the `module_temp_populate` function from `hw_management_sync.py`.

## Overview

The `module_temp_populate` function is responsible for populating temperature attributes for hardware modules. These tests ensure the function works correctly under various conditions including normal operation, error scenarios, and edge cases.

## Test Configuration

### Basic Module Configuration
- **Argument List**: `{"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 36}`
- **Module Count**: 36 modules (indexed from 1 to 36)
- **Input Path Template**: `/sys/module/sx_core/asic0/module{}/`
- **Output Path**: `/var/run/hw-management/thermal/`

### Module Temperature Attributes

Each module can have the following temperature-related files:

#### Input Files (Source):
- `control` - Module control mode (0=FW_CONTROL, 1=SW_CONTROL)
- `present` - Module presence status (0=absent, 1=present)
- `temperature/input` - Main temperature reading
- `temperature/threshold_hi` - High threshold temperature
- `temperature/threshold_critical_hi` - Critical high threshold temperature
- `temperature/tec/cooling_level` - Current cooling level
- `temperature/tec/max_cooling_level` - Maximum cooling level

#### Output Files (Generated):
- `module{N}_temp_input` - Processed temperature value
- `module{N}_temp_crit` - Critical temperature threshold
- `module{N}_temp_emergency` - Emergency temperature threshold
- `module{N}_temp_fault` - Fault temperature value
- `module{N}_temp_trip_crit` - Trip critical temperature
- `module{N}_cooling_level_input` - Cooling level value
- `module{N}_max_cooling_level_input` - Maximum cooling level value
- `module{N}_status` - Module status (0=absent, 1=present)

## Test Scenarios

### 1. Normal Condition Testing
- **Test**: `test_normal_condition_all_files_present`
- **Description**: Tests normal operation when all temperature attribute files are present and readable
- **Expected**: All output files created with correct temperature values converted using `sdk_temp2degree()`

### 2. Input Read Error Testing
- **Test**: `test_input_read_error_default_values`
- **Description**: Tests behavior when the main temperature input file cannot be read
- **Expected**: All temperature values default to "0" (default temperature values)

### 3. Other Attributes Read Error Testing
- **Test**: `test_other_attributes_read_error`
- **Description**: Tests behavior when threshold or cooling level files cannot be read
- **Expected**: Input temperature is processed correctly, but failed attributes use default values

### 4. Error Handling Testing
- **Test**: `test_error_handling_no_crash`
- **Description**: Tests that the function doesn't crash under various error conditions
- **Expected**: Function completes without exceptions regardless of file read errors

### 5. Random Module Configuration Testing
- **Test**: `test_random_module_configuration`
- **Description**: Tests all 36 modules with randomized configurations
- **Expected**: Function handles all combinations of module states without issues

### 6. Software Control Mode Testing
- **Test**: `test_sw_control_mode_ignored`
- **Description**: Tests that modules in SW_CONTROL mode are properly ignored
- **Expected**: No output files are created for modules in SW_CONTROL mode

### 7. Temperature Conversion Testing
- **Test**: `test_sdk_temp2degree_function`
- **Description**: Tests the temperature conversion function
- **Expected**: Correct conversion from SDK temperature format to degrees

### 8. Argument Validation Testing
- **Test**: `test_module_count_argument_validation`
- **Description**: Tests that function arguments are properly validated
- **Expected**: Arguments match the specified configuration

## Test Implementation Details

### Mocking Strategy
The tests use Python's `unittest.mock` to:
- Redirect file operations to temporary directories
- Simulate various file read/write scenarios
- Create controlled test environments
- Avoid affecting the real filesystem

### Temperature Conversion
The `sdk_temp2degree()` function converts SDK temperature format:
- Positive values: `temperature = value * 125`
- Negative values: `temperature = 0xffff + value + 1`

### Error Simulation
Tests simulate various error conditions:
- Missing files
- Unreadable files
- Invalid file content
- Missing directories
- Permission errors

## Running the Tests

### Method 1: Using Shell Script (Recommended)
```bash
cd unittest/hw_mgmgt_sync/module_populate_temperature
./run_tests.sh
```

### Method 2: Using Python Test Runner
```bash
cd unittest/hw_mgmgt_sync/module_populate_temperature
python3 run_tests.py
```

### Method 3: Direct Test Execution
```bash
cd unittest/hw_mgmgt_sync/module_populate_temperature
python3 test_module_temp_populate.py
```

### Method 4: Using unittest module
```bash
cd unittest/hw_mgmgt_sync/module_populate_temperature
python3 -m unittest test_module_temp_populate.py -v
```

## Command Line Options

### Test Runner Options
```bash
python3 run_tests.py --help
```

Available options:
- `--verbose, -v` - Enable verbose test output
- `--hw-mgmt-path PATH` - Specify path to hw_management_sync.py
- `--test-file FILE` - Specify test file to run
- `--list-tests` - List available test methods

### Shell Script Options
```bash
./run_tests.sh --verbose
```

The shell script accepts the same options as the Python test runner.

## Expected Output

When tests pass, you should see output similar to:
```
================================================================================
🚀 COMPREHENSIVE MODULE_TEMP_POPULATE TEST SUITE
================================================================================
Python version: 3.x.x
Testing hw_management_sync.py from: /path/to/hw_management_sync.py
Test configuration: 36 modules, offset=1
================================================================================

🧪 Testing normal condition with all files present...
✅ Normal condition test passed

🧪 Testing default temperature values when input read error...
✅ Input read error test passed

🧪 Testing temperature values when other attributes read error...
✅ Other attributes read error test passed

🧪 Testing error handling - no crash conditions...
✅ Error handling test passed - no crashes occurred

🧪 Testing random configuration of all 36 modules...
✅ Random configuration test passed - processed X modules

🧪 Testing sdk_temp2degree function...
✅ sdk_temp2degree function test passed

🧪 Testing module_count argument validation...
✅ Module count argument validation test passed

🧪 Testing SW control mode modules are ignored...
✅ SW control mode ignored test passed

--------------------------------------------------------------------------------
Ran 8 tests in X.XXXs

OK
```

## Test Requirements Met

✅ **Basic Module Configuration**: Uses specified argument list with 36 modules  
✅ **Normal Condition Testing**: All files created and filled with values  
✅ **Input Read Error**: Default temperature values when input read fails  
✅ **Other Attributes Error**: Temperature values when other attributes fail  
✅ **Error Handling**: No-crash condition for all reading errors  
✅ **Random Testing**: Comprehensive testing of all module combinations  
✅ **Software Control**: Proper handling of SW_CONTROL mode modules  
✅ **Temperature Conversion**: Accurate sdk_temp2degree function testing  

## Dependencies

- Python 3.6+
- `unittest` (standard library)
- `unittest.mock` (standard library)
- `tempfile` (standard library)
- `shutil` (standard library)
- `random` (standard library)
- `importlib.util` (standard library)

## File Structure

```
unittest/hw_mgmgt_sync/module_populate_temperature/
├── README.md                       # This documentation
├── test_module_temp_populate.py    # Main test file
├── run_tests.py                    # Python test runner
└── run_tests.sh                    # Shell script test runner
```

## Notes

- Tests use temporary directories to avoid affecting the real system
- All file operations are mocked to prevent interference with actual hardware
- Random configurations ensure comprehensive coverage of edge cases
- Tests are designed to be run from any directory location
- Both positive and negative test cases are included for thorough validation
