# Module Temperature Populate Tests

This directory contains comprehensive unit tests for the `module_temp_populate` function from `hw_management_sync.py`.

## Test Overview

The tests cover the following scenarios as specified in the requirements:

### 1. Basic Module Configuration
- **Argument List**: `{"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 36}`
- **Module Count**: 36 modules (indexed from 1 to 36)

### 2. Inserted Modules (module{}/present = 1)
- **Control Mode**: Can be 0 or 1
  - If control = 1: Module reading is ignored
  - If control = 0: Module reading proceeds normally
- **Temperature Input**: Random value in range (50000...70000)
- **Threshold High**: Fixed value 70000
- **Threshold Critical High**: Optional, if present = 80000
- **Cooling Level**: Optional, if present in range (100..800)
- **Max Cooling Level**: If cooling_level present, equals cooling_level + 5000

### 3. Not Inserted Modules (module{}/present = 0)
- Module reading is ignored
- Only status file is created with value 0

## Test Files

- **`test_runner.py`**: Main test file that can be executed directly
- **`run_all_tests.py`**: Comprehensive test suite with detailed mocking

## Running Tests

### Option 1: Run directly with Python
```bash
cd unittest/hw_mgmgt_sync/module_populate_1
python3 test_runner.py
```

### Option 2: Run with unittest module
```bash
cd unittest/hw_mgmgt_sync/module_populate_1
python3 -m unittest test_runner.py -v
```

### Option 3: Run specific test
```bash
cd unittest/hw_mgmgt_sync/module_populate_1
python3 -m unittest test_runner.TestModuleTempPopulate.test_inserted_module_with_all_features -v
```

## Test Cases

1. **`test_inserted_module_with_all_features`**: Tests a fully configured inserted module
2. **`test_inserted_module_control_mode_1_ignored`**: Tests that control mode 1 modules are ignored
3. **`test_not_inserted_module`**: Tests not inserted modules
4. **`test_module_without_critical_hi`**: Tests modules without critical threshold files
5. **`test_module_without_cooling_level`**: Tests modules without cooling level files
6. **`test_multiple_modules_different_configs`**: Tests multiple modules with different configurations
7. **`test_sdk_temp2degree`**: Tests the temperature conversion function

## Test Structure

Each test:
- Creates temporary directories and mock module files
- Mocks necessary system calls and file operations
- Executes the `module_temp_populate` function
- Verifies expected output files and values
- Cleans up temporary files

## Mocking Strategy

The tests use Python's `unittest.mock` to:
- Mock file system operations (`os.path.join`, `os.path.islink`)
- Create temporary test directories and files
- Simulate different module configurations
- Verify output without affecting the real system

## Expected Output

When tests pass, you should see:
```
Starting module_temp_populate tests...
==================================================
test_inserted_module_with_all_features (__main__.TestModuleTempPopulate) ... ok
test_inserted_module_control_mode_1_ignored (__main__.TestModuleTempPopulate) ... ok
test_not_inserted_module (__main__.TestModuleTempPopulate) ... ok
test_module_without_critical_hi (__main__.TestModuleTempPopulate) ... ok
test_module_without_cooling_level (__main__.TestModuleTempPopulate) ... ok
test_multiple_modules_different_configs (__main__.TestModuleTempPopulate) ... ok
test_sdk_temp2degree (__main__.TestModuleTempPopulate) ... ok

==================================================
Tests run: 7
Failures: 0
Errors: 0
```

## Requirements Met

✅ **Argument List**: Uses specified configuration with 36 modules  
✅ **Random Module Insertion**: Simulates random module states  
✅ **Control Mode Handling**: Tests both control=0 and control=1 scenarios  
✅ **Temperature Ranges**: Uses specified ranges (50000-70000, 70000, 80000)  
✅ **Cooling Level Ranges**: Uses specified ranges (100-800, +5000 offset)  
✅ **Optional Files**: Tests presence/absence of optional files  
✅ **Not Inserted Modules**: Handles modules with present=0  
✅ **Single Python File Execution**: All tests run from one file  

## Dependencies

- Python 3.6+
- `unittest` (standard library)
- `unittest.mock` (standard library)
- `tempfile` (standard library)
- `shutil` (standard library)
- `random` (standard library)
