# Module Temperature Populate Test Suite

Comprehensive unit tests for the `module_temp_populate` function from `hw_management_sync.py`.

## Overview

This test suite validates the module temperature population functionality that manages thermal monitoring for hardware modules. The tests cover all critical scenarios including normal operation, error handling, and edge cases.

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
- `temperature/tec/warning_cooling_level` - Maximum cooling level

#### Output Files (Generated):
- `module{N}_temp_input` - Processed temperature value
- `module{N}_temp_crit` - Critical temperature threshold
- `module{N}_temp_emergency` - Emergency temperature threshold
- `module{N}_temp_fault` - Fault temperature value
- `module{N}_temp_trip_crit` - Trip critical temperature
- `module{N}_cooling_level_input` - Cooling level value
- `module{N}_cooling_level_warning` - Maximum cooling level value
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
- **Description**: Tests all 36 modules with randomized configurations. Module temp can be in range (0..800)
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

## Usage

### Running Tests

#### Method 1: Using the standalone test runner (Recommended)
```bash
cd unittest/hw_mgmgt_sync/module_populate_temperature_2
./run_tests.py
```

#### Method 2: Direct execution of test file
```bash
cd unittest/hw_mgmgt_sync/module_populate_temperature_2
./test_module_temp_populate.py
```

#### Method 3: Using Python directly
```bash
cd unittest/hw_mgmgt_sync/module_populate_temperature_2
python3 run_tests.py
```

### Expected Output

The test runner provides:
- Detailed test execution output
- Progress indicators for each test
- Summary of results (passed/failed/errors)
- Return code: 0 for success, 1 for failure

Example output:
```
======================================================================
NVIDIA HW Management Sync - Module Temperature Populate Tests
======================================================================

Testing normal condition with all files present...
✓ Normal condition test passed
Testing input read error with default values...
✓ Input read error test passed
...

======================================================================
TEST SUMMARY
======================================================================
Tests run: 10
Failures: 0
Errors: 0

🎉 ALL TESTS PASSED!
```

## Files

- `test_module_temp_populate.py` - Main test suite with comprehensive test cases
- `run_tests.py` - Standalone test runner with environment setup
- `README.md` - This documentation file

## Dependencies

- Python 3.x
- unittest (standard library)
- unittest.mock (standard library)
- Access to `hw_management_sync.py` module

## Test Architecture

The tests use comprehensive mocking to simulate:
- File system operations (reading from sysfs)
- File existence checks
- Permission errors and I/O failures
- Various module configurations

This approach ensures:
- Tests don't require actual hardware
- Consistent test environment
- Full coverage of error conditions
- Isolation from system state

## Continuous Integration

The test suite is designed for automated testing and provides:
- Clear pass/fail indicators
- Appropriate exit codes
- Detailed error reporting
- Standalone execution capability

## Contributing

When adding new tests:
1. Follow the existing naming convention
2. Include descriptive docstrings
3. Use appropriate mocking for isolation
4. Update this README with new test scenarios
5. Ensure tests pass in isolation and as part of the suite
