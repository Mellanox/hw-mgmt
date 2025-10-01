# HW_Mgmt_Logger Test Suite 🧪

A comprehensive, beautiful, and robust test suite for the `HW_Mgmt_Logger` class with colorful output, detailed error reporting, and randomized testing capabilities.

## 🚀 Features

- **Comprehensive Coverage**: Tests all aspects of the HW_Mgmt_Logger class
- **Beautiful Output**: Colorful terminal output with icons and formatting
- **Detailed Error Reporting**: Complete error details with input parameters
- **Randomized Testing**: Configurable random iterations for stress testing
- **Thread Safety Testing**: Multi-threaded logging verification
- **Resource Management**: Proper cleanup and resource leak detection
- **Standalone Executable**: Can be run directly without external dependencies

## 📁 Files

- `test_hw_mgmt_logger.py` - Main comprehensive test suite
- `run_tests.py` - Easy-to-use test runner with predefined configurations
- `README.md` - This documentation file

## 🎯 Test Categories

### Functional Tests
- Basic logger initialization
- File logging (regular files, stdout, stderr)
- Syslog logging functionality
- Log level filtering
- Message repeat/collapse functionality
- Parameter validation
- Unicode and special character handling
- Resource cleanup verification

### Stress Tests
- Thread safety verification
- Randomized message generation
- Random repeat patterns
- Edge case handling

### Edge Cases
- None and empty messages
- Invalid parameters
- Directory validation
- Memory and resource limits

## 🏃‍♂️ Quick Start

### Method 1: Using the Test Runner (Recommended)
```bash
# Quick test (5 random iterations)
./run_tests.py --quick

# Standard test (10 random iterations) - DEFAULT
./run_tests.py --standard

# Thorough test (25 random iterations)
./run_tests.py --thorough

# Stress test (100 random iterations)
./run_tests.py --stress

# Custom configuration
./run_tests.py -r 50 -v 2
```

### Method 2: Direct Execution
```bash
# Run with default settings (10 random iterations)
./test_hw_mgmt_logger.py

# Custom random iterations
./test_hw_mgmt_logger.py -r 25

# Quiet output
./test_hw_mgmt_logger.py -v 0

# Help
./test_hw_mgmt_logger.py --help
```

### Method 3: Python Module
```bash
python3 test_hw_mgmt_logger.py --random-iterations 20 --verbosity 2
python3 -m unittest test_hw_mgmt_logger -v
```

## 📊 Output Examples

### ✅ Successful Test Run
```
================================================================================
📝 HW_Mgmt_Logger Comprehensive Test Suite
================================================================================
ℹ️ Random iterations: 10
ℹ️ Test verbosity: 2

ℹ️ Running: TestHWMgmtLogger.test_basic_initialization
✅ test_basic_initialization PASSED

ℹ️ Running: TestHWMgmtLogger.test_file_logging_initialization
✅ test_file_logging_initialization PASSED

🎲 Random test iteration 1/10
🎲 Random test iteration 2/10
...

================================================================================
📝 Test Results Summary
================================================================================
✅ Passed: 45
❌ Failed: 0
❌ Errors: 0
⏭️ Skipped: 0
ℹ️ Total: 45
ℹ️ Time: 12.34s

✅ ALL TESTS PASSED! 🎉
```

### ❌ Failed Test with Detailed Error Report
```
❌ test_parameter_validation FAILED

============================================================
FAILURE DETAILS
============================================================
Test: TestHWMgmtLogger.test_parameter_validation
Input Parameters:
  log_repeat: -1
  log_file: '/tmp/test.log'
  log_level: 20
Error Type: AssertionError  
Error Message: ValueError not raised
Traceback:
  File "test_hw_mgmt_logger.py", line 245, in test_parameter_validation
    with self.assertRaises(ValueError):
  File "contextlib.py", line 88, in __exit__
    next(self.gen)
============================================================
```

## 🔧 Configuration Options

### Command Line Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `-r, --random-iterations` | Number of randomized test iterations | 10 |
| `-v, --verbosity` | Test output verbosity (0=quiet, 1=normal, 2=verbose) | 2 |

### Test Runner Presets

| Preset | Iterations | Use Case |
|--------|------------|----------|
| `--quick` | 5 | Fast development testing |
| `--standard` | 10 | Regular CI/CD testing |
| `--thorough` | 25 | Pre-release validation |
| `--stress` | 100 | Performance and stability testing |

## 🧪 Test Coverage

The test suite covers the following areas:

### Core Functionality ✅
- [x] Logger initialization with various parameters
- [x] File logging (files, stdout, stderr)
- [x] Syslog integration
- [x] Log level management
- [x] Message formatting and encoding

### Advanced Features ✅
- [x] Message repeat/collapse functionality
- [x] Thread safety
- [x] Resource management and cleanup
- [x] Unicode and special character support
- [x] Parameter validation

### Error Handling ✅
- [x] Invalid parameter detection
- [x] File system error handling
- [x] Syslog error handling
- [x] Memory and resource limits

### Randomized Testing ✅
- [x] Random message generation
- [x] Random parameter combinations
- [x] Random repeat patterns
- [x] Stress testing scenarios

## 🐛 Troubleshooting

### Common Issues

**Import Error**: `Failed to import HW_Mgmt_Logger`
- Ensure `hw_management_lib.py` is in the correct path
- Check Python path and module structure

**Permission Error**: Tests fail with permission issues
- Ensure write permissions in temp directory
- Run with appropriate user privileges for syslog testing

**Syslog Tests Fail**: Syslog-related tests don't work
- Syslog daemon may not be running
- Check system syslog configuration
- May require root privileges on some systems

### Debug Mode
Run tests with maximum verbosity to see detailed output:
```bash
./test_hw_mgmt_logger.py -v 2 -r 1
```

## 🔄 Continuous Integration

Example CI configuration:

### GitHub Actions
```yaml
- name: Run HW_Mgmt_Logger Tests
  run: |
    cd unittest/hw_management_lib/HW_Mgmt_Logger
    ./run_tests.py --thorough
```

### Jenkins
```groovy
stage('HW_Mgmt_Logger Tests') {
    steps {
        dir('unittest/hw_management_lib/HW_Mgmt_Logger') {
            sh './run_tests.py --standard'
        }
    }
}
```

## 📈 Performance Benchmarks

Typical execution times on modern hardware:

| Test Type | Iterations | Duration | Tests Run |
|-----------|------------|----------|-----------|
| Quick | 5 | ~5s | ~25 tests |
| Standard | 10 | ~10s | ~35 tests |
| Thorough | 25 | ~25s | ~55 tests |
| Stress | 100 | ~90s | ~155 tests |

## 🤝 Contributing

To add new tests:

1. Add test methods to existing test classes
2. Follow naming convention: `test_descriptive_name`
3. Use `_store_test_params()` for error reporting
4. Include both positive and negative test cases
5. Add appropriate assertions and cleanup

## 📄 License

Same license as the parent project - Dual BSD/GPL License.

---

*Created with ❤️ for robust hardware management logging testing*
