# Thermal Control Initialization Unit Tests

This directory contains comprehensive unit tests for the thermal control initialization and signal handling fixes implemented in the commit:

**"hw-mgmt: thermal: Fix TC init/close flow issue"**

## Problem Statement

The original issue was a critical race condition where the thermal control service could crash if stopped immediately after starting. This occurred because:

1. Signal handlers were registered before `sys_config` was fully initialized
2. The signal handler accessed `sys_config` during shutdown cleanup before it was ready
3. No proper error handling for configuration loading failures
4. Redundant `flush()` call in logger cleanup

## Test Coverage

### 1. Early Termination Scenarios
**File**: `test_thermal_init_and_signal_handling.py`
**Tests**: `test_early_termination_with_initialized_sys_config`

- Tests that signal handlers work correctly when `sys_config` is properly initialized
- Verifies signal handler registration happens after configuration loading
- Ensures no crashes when service is terminated immediately after start

### 2. Configuration Loading Failures  
**Tests**: `test_configuration_loading_failure_with_exception_handling`

- Tests various exception types during configuration loading:
  - `FileNotFoundError` - Config file missing
  - `PermissionError` - Permission denied reading config
  - `json.JSONDecodeError` - Invalid JSON format
  - `ValueError` - Invalid configuration values
  - `Exception` - Generic configuration errors
- Verifies proper error logging and graceful exit with code 1

### 3. Signal Handler Behavior with Uninitialized State
**Tests**: 
- `test_signal_handler_with_uninitialized_state_protection`
- `test_signal_handler_platform_support_check_with_initialized_config`
- `test_initialization_order_prevents_race_condition`

- Tests signal handler behavior in various initialization states
- Verifies proper platform support checking from initialized config
- Ensures initialization order prevents race conditions

### 4. Logger Close Optimization
**Tests**: `test_logger_close_tc_log_handler_optimization`

- Verifies that `flush()` is no longer called redundantly in `close_tc_log_handler()`
- Confirms that `close()` is still called (which internally calls `flush()`)
- Tests the performance optimization implemented in the fix

## Test Files

### Core Test Files
- `test_thermal_init_and_signal_handling.py` - Tests for `hw_management_thermal_control.py`
- `test_thermal_init_and_signal_handling_2_5.py` - Tests for `hw_management_thermal_control_2_5.py`

### Test Runner
- `run_thermal_init_tests.py` - Unified test runner for both versions

## Running the Tests

### Run All Tests
```bash
python3 run_thermal_init_tests.py
```

### Run Tests by Category
```bash
# Early termination scenarios
python3 run_thermal_init_tests.py --category early_termination

# Configuration loading failures
python3 run_thermal_init_tests.py --category config_failures

# Signal handler behavior
python3 run_thermal_init_tests.py --category signal_handler

# Logger optimization
python3 run_thermal_init_tests.py --category logger_optimization

# Integration tests
python3 run_thermal_init_tests.py --category integration
```

### List Available Tests
```bash
python3 run_thermal_init_tests.py --list-tests
```

### Run Individual Test Files
```bash
# Test main thermal control module
python3 test_thermal_init_and_signal_handling.py

# Test 2.5 version thermal control module  
python3 test_thermal_init_and_signal_handling_2_5.py
```

## Test Dependencies

The tests use Python's built-in `unittest` framework with the following key components:

- `unittest.mock` - For mocking system components and file operations
- `signal` - For testing signal handling behavior
- `tempfile` - For creating temporary test fixtures
- `threading.Event` - For testing race condition scenarios

## Key Test Techniques

### Mocking Strategy
- **File Operations**: Mock file reading/writing to avoid filesystem dependencies
- **Signal Registration**: Mock signal.signal() to track handler registration
- **Logger**: Mock logger to verify proper error handling and cleanup
- **Configuration Loading**: Mock to test various failure scenarios

### Race Condition Testing
- **Initialization Order Tracking**: Monitor the sequence of critical operations
- **Signal Handler Interception**: Capture and test signal handlers independently
- **State Verification**: Ensure objects are in valid states before signal registration

### Exception Handling Testing
- **Comprehensive Exception Coverage**: Test multiple exception types
- **Error Logging Verification**: Ensure errors are properly logged
- **Graceful Failure**: Verify proper exit codes and cleanup

## Expected Results

All tests should pass, demonstrating that:

1. **Race Condition Fixed**: Signal handlers can safely access `sys_config` at any time
2. **Proper Error Handling**: Configuration failures are handled gracefully  
3. **Initialization Safety**: `sys_config` is always in a valid state
4. **Performance Optimized**: Redundant flush() calls removed
5. **Consistent Behavior**: Both thermal control variants behave identically

## Integration with CI/CD

These tests can be integrated into continuous integration pipelines:

```bash
# Example CI command
python3 run_thermal_init_tests.py || exit 1
```

## Troubleshooting

### Common Issues

1. **Import Errors**: Ensure `usr/usr/bin` is in Python path
2. **Mock Failures**: Verify mock paths match actual module structure
3. **Signal Handling**: Some tests may need to handle `SystemExit` exceptions

### Debug Mode
For detailed test output, run with verbosity:
```bash
python3 -m unittest test_thermal_init_and_signal_handling -v
```

## Test Maintenance

When modifying the thermal control modules:

1. **Update Import Paths**: If module locations change
2. **Add New Test Cases**: For new initialization logic
3. **Update Mocks**: If internal APIs change
4. **Verify Coverage**: Ensure all critical paths are tested

## Related Files

- `usr/usr/bin/hw_management_thermal_control.py` - Main thermal control module
- `usr/usr/bin/hw_management_thermal_control_2_5.py` - 2.5 version variant
- `test_thermal_sensor_error_handling.py` - Related sensor error tests