# Unit Tests for module_temp_populate Function

This directory contains comprehensive unit tests for the `module_temp_populate` function from `hw_management_sync.py`.

## Features

- **Path-agnostic**: Tests can be run from any directory
- **Randomized testing**: Each test run uses random module configurations (present/mode states)
- **Comprehensive coverage**: Tests all scenarios:
  - SDK_SW_CONTROL mode (should skip processing)
  - SDK_FW_CONTROL mode with present modules (should write actual values)
  - SDK_FW_CONTROL mode with absent modules (should write zeros)
- **Mock file system**: Uses temporary directories to avoid affecting real system files
- **Detailed verification**: Checks file creation, content, and proper temperature calculations

## Test Scenarios

### Module Configuration Parameters
- **module_count**: 5 modules (as requested)
- **present**: Randomly set to 0 (absent) or 1 (present) for each module
- **mode**: Randomly set to:
  - `CONST.SDK_FW_CONTROL` (0) - Firmware control mode
  - `CONST.SDK_SW_CONTROL` (1) - Software control mode

### Expected Behavior Testing

1. **SDK_SW_CONTROL mode**: 
   - No files should be created in `/var/run/hw-management/thermal/`
   - Function should skip processing these modules

2. **SDK_FW_CONTROL mode + present=0**:
   - Files should be created with zero values:
     - `module{X}_temp_input` = "0"
     - `module{X}_temp_crit` = "0"
     - `module{X}_temp_emergency` = "0"
     - `module{X}_temp_fault` = "0"
     - `module{X}_temp_trip_crit` = "0"

3. **SDK_FW_CONTROL mode + present=1**:
   - Files should be created with actual temperature values:
     - `module{X}_temp_input` = calculated temperature using `sdk_temp2degree()`
     - `module{X}_temp_crit` = calculated critical temperature
     - `module{X}_temp_emergency` = critical + 10000 (EMERGENCY_OFFSET)
     - `module{X}_temp_fault` = "0"
     - `module{X}_temp_trip_crit` = "120000" (CONST.MODULE_TEMP_CRIT_DEF)

## Usage

### Method 1: Using the shell script (Recommended)
```bash
./run_tests.sh <path_to_hw_management_sync.py> [--verbose]
```

**Examples:**
```bash
# Run tests with relative path
./run_tests.sh ./hw_management_sync.py

# Run tests with absolute path and verbose output
./run_tests.sh /full/path/to/hw_management_sync.py --verbose

# From any directory
/path/to/tests/run_tests.sh /path/to/hw_management_sync.py
```

### Method 2: Direct Python execution
```bash
python3 test_module_temp_populate.py <path_to_hw_management_sync.py> [--verbose]
```

## Test Output

The tests will show:
- Random module configurations generated for each test run
- Verification of file creation/non-creation based on module modes
- Verification of file contents (zeros vs actual values)
- Temperature calculation verification
- Module counter file verification

### Sample Output
```
Testing hw_management_sync.py from: /path/to/hw_management_sync.py
======================================================================
Module 1: present=1, mode=0, temp=25, threshold=70
Module 2: present=0, mode=0, temp=30, threshold=75
Module 3: present=1, mode=1, temp=35, threshold=80
Module 4: present=0, mode=1, temp=40, threshold=85
Module 5: present=1, mode=0, temp=45, threshold=90
======================================================================
[PASS] Module module1: FW control, present - actual values (temp=3125, crit=8750)
[PASS] Module module2: FW control, not present - zero values
[PASS] Module module3: SW control mode - no files created
[PASS] Module module4: SW control mode - no files created
[PASS] Module module5: FW control, present - actual values (temp=5625, crit=11250)
[PASS] Module counter file verified
.
----------------------------------------------------------------------
Ran 1 test in 0.XXXs

OK
```

## Files

- `test_module_temp_populate.py`: Main test file with comprehensive test cases
- `run_tests.sh`: Shell script wrapper for easy test execution
- `README_tests.md`: This documentation file

## Requirements

- Python 3.x
- Standard Python libraries (unittest, tempfile, random, etc.)
- The `hw_management_sync.py` file being tested

## Notes

- Tests use mocking to avoid requiring actual hardware or system files
- Each test run generates different random configurations for thorough testing
- Temporary directories are automatically cleaned up after tests
- Tests are designed to be completely isolated from the real file system 