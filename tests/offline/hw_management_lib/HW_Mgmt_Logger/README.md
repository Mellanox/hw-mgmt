# HW_Mgmt_Logger Unit Tests

Comprehensive unit tests for the `HW_Mgmt_Logger` class from `hw_management_lib.py`.

## Features

- ✓ **Standalone Execution**: Can be run directly without test framework
- ✓ **Beautiful Output**: Colorful output with icons for better readability
- ✓ **Random Test Iterations**: Configurable N iterations for random tests
- ✓ **Detailed Error Reports**: Comprehensive error information with hash dumps
- ✓ **Thread Safety Tests**: Validates concurrent access patterns
- ✓ **Edge Case Coverage**: Tests special characters, unicode, long messages, etc.

## Test Coverage

### Basic Functionality (tests 01-07)
- Logger initialization with various parameters
- stdout/stderr redirection
- Invalid parameter handling
- Permission checks

### Logging Levels (tests 10-16)
- All log levels: DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL
- Log level filtering
- Level-specific message routing

### Message Repeat & Hash Management (tests 20-25)
- Message repeat with ID-based collapsing
- Hash garbage collection (size and timeout based)
- Finalization messages
- Hash collision handling

### Suspend/Resume (tests 30-31)
- Logging suspension and resumption
- Multiple suspend/resume cycles

### Syslog Integration (tests 40-44)
- Syslog initialization and configuration
- CRITICAL messages always logged to syslog
- Level-based filtering
- Unicode message handling
- Proper cleanup

### Parameter Management (tests 50-53)
- Dynamic parameter changes via set_param
- Parameter validation
- Log file switching

### Thread Safety (tests 60-61)
- Lock verification
- Concurrent hash access

### Edge Cases (tests 70-79)
- Empty and None messages
- Non-string message types
- Very long messages
- Special characters and unicode
- Non-hashable IDs
- Cleanup and destruction

### Random Tests (tests 80-84)
- Random log levels (N iterations)
- Random repeat values (N iterations)
- Random message lengths (N iterations)
- Random suspend/resume (N iterations)
- Random hash operations (N iterations)

### File Rotation (test 90)
- Log file rotation when size limit exceeded

### Utility Functions (test 95)
- current_milli_time() function

## Usage

### Run all tests with default settings
```bash
cd tests/offline/hw_management_lib/HW_Mgmt_Logger
./test_hw_mgmt_logger.py
```

### Run with custom number of random iterations
```bash
./test_hw_mgmt_logger.py --random-iterations 50
# Or use short form
./test_hw_mgmt_logger.py -n 50
```

### Run specific test
```bash
./test_hw_mgmt_logger.py __main__.TestHWMgmtLogger.test_01_basic_initialization
```

### Run with different verbosity levels
```bash
# Quiet mode - only summary
./test_hw_mgmt_logger.py --verbosity 0

# Normal mode - beautiful colored output (default)
./test_hw_mgmt_logger.py --verbosity 1

# Verbose mode - detailed unittest output
./test_hw_mgmt_logger.py --verbosity 2
```

### Run from any directory
```bash
python3 tests/offline/hw_management_lib/HW_Mgmt_Logger/test_hw_mgmt_logger.py --random-iterations 100
```

## Command Line Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--random-iterations` | `-n` | Number of iterations for random tests | 10 |
| `--verbosity` | | Verbosity level: 0=quiet, 1=normal, 2=verbose | 1 |
| `tests` | | Specific tests to run (positional) | All tests |

## Test Output

The test suite provides beautiful, colored output with:

- 📝 **Logger icon** - Test suite header
- ✓ **Green checkmark** - Passed tests
- ✗ **Red X** - Failed tests
- ⚠ **Warning icon** - Warnings
- ℹ **Info icon** - Information messages
- 🎲 **Dice icon** - Random test iterations
- 🧹 **Broom icon** - Cleanup operations
- 🔁 **Repeat icon** - Repeat test indicators
- # **Hash icon** - Hash information

### Sample Output
```
================================================================================
📝 HW_Mgmt_Logger Unit Tests
================================================================================
Platform: Linux-6.12.38-x86_64-with-glibc2.36
Python: 3.11.2
Start Time: 2025-10-13 10:30:45
================================================================================

ℹ Running: Test basic logger initialization with default parameters
✓ PASSED: Test basic logger initialization with default parameters (0.015s)

ℹ Running: Test logger initialization with log file
✓ PASSED: Test logger initialization with log file (0.023s)

...

================================================================================
✔ TEST SUMMARY
================================================================================
✓ Passed: 45
✗ Failed: 0
❌ Errors: 0
⊘ Skipped: 0
Total Tests: 45

✓ ALL TESTS PASSED!
================================================================================
```

## Error Reporting

When a test fails, detailed information is provided:

```
================================================================================
❌ DETAILED ERROR REPORT
================================================================================

Test: Test message repeat with ID
Error Type: AssertionError
Error Message: 2 != 1

Traceback:
  File "test_hw_mgmt_logger.py", line 432, in test_21_message_repeat_with_id
    self.assertEqual(msg_count, 2)

# Hash Information:
log_hash: {
  "123456789": {
    "count": 5,
    "msg": "Repeated message",
    "ts": 1697198445123,
    "repeat": 2
  }
}
syslog_hash: {}
================================================================================
```

## Requirements

- Python 3.6+
- hw_management_lib.py (from usr/usr/bin/)
- No additional dependencies required

## Notes

- All tests clean up after themselves (temporary files, logger instances)
- Each random test iteration clears logger state (hashes) before running
- Tests use temporary directories that are automatically cleaned up
- Thread safety is validated with concurrent access patterns
- Syslog tests use mocking to avoid requiring actual syslog access

## Integration with Test Suite

These tests can also be run as part of the main test suite:

```bash
cd tests
python3 test.py --offline
```

## Troubleshooting

### Permission Errors
If you encounter permission errors, ensure the test directory is writable:
```bash
ls -la tests/offline/hw_management_lib/HW_Mgmt_Logger/
```

### Import Errors
If the hw_management_lib module cannot be imported, verify the path:
```bash
ls -la usr/usr/bin/hw_management_lib.py
```

### Syslog Tests Failing
If syslog tests fail, ensure the unittest.mock module is available (Python 3.3+).

## Contributing

When adding new tests:
1. Follow the existing naming convention (test_XX_description)
2. Group related tests in numbered ranges (e.g., 01-09 for initialization)
3. Clean up logger state in tearDown
4. Use _clean_logger_state() for random test iterations
5. Add appropriate icons and colors for output
6. Document the test purpose in the docstring

## License

Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
See LICENSE file for details.

