# HW-MGMT Test Suite

Comprehensive test suite for the NVIDIA hw-mgmt project.

## Overview

This directory contains all tests for hw-mgmt, organized into two main categories:

- **Offline Tests** (`offline/`) - Tests that don't require physical hardware
- **Hardware Tests** (`hardware/`) - Tests that require actual hardware

The test suite supports two testing frameworks:
1. **Standalone tests** - Original test scripts with custom runners
2. **Pytest** - Modern pytest-based tests with rich fixtures and features

## Quick Start

### Running All Tests

```bash
# Using the test.py runner (runs standalone tests)
python3 test.py --offline

# Using pytest (runs pytest-style tests)
pytest -m offline

# Run all tests (both runners)
python3 test.py --all
pytest
```

### Running Specific Tests

```bash
# Specific standalone test
cd offline/hw_management_lib/HW_Mgmt_Logger
python3 test_hw_mgmt_logger.py -v

# Specific pytest test
pytest offline/test_example_pytest.py -v

# By marker
pytest -m "offline and quick"
```

## Test Organization

```
tests/
├── README.md                    # This file
├── PYTEST_GUIDE.md              # Detailed pytest documentation
├── test.py                      # Main test runner for standalone tests
├── pytest.ini                   # Pytest configuration
├── conftest.py                  # Shared pytest fixtures
│
├── offline/                     # Offline tests (no hardware required)
│   ├── test_example_pytest.py   # Example pytest tests (use as template)
│   ├── test_hw_management_lib.py  # Comprehensive hw_management_lib tests (55+ tests)
│   │
│   ├── hw_management_lib/       # hw_management_lib.py tests
│   │   └── HW_Mgmt_Logger/
│   │       ├── test_hw_mgmt_logger.py
│   │       ├── advanced_tests.py
│   │       └── run_tests.py
│   │
│   └── hw_mgmgt_sync/           # hw_management_sync.py tests
│       ├── asic_populate_temperature/
│       ├── module_populate/
│       └── module_populate_temperature/
│
├── hardware/                    # Hardware tests (requires physical hardware)
│   └── hw_management_bmcaccessor_login_test.py
│
└── tools/                       # Test utilities
    └── bom_decoder_cli.py
```

## Test Runners

### 1. Standalone Test Runner (test.py)

The `test.py` runner executes the original standalone test scripts:

```bash
# Run offline tests
python3 test.py --offline

# Run hardware tests
python3 test.py --hardware

# Run all tests
python3 test.py --all

# Verbose output
python3 test.py --offline -v
```

**Features:**
- Executes existing test scripts
- Colored output with pass/fail indicators
- Test summary with statistics
- Automatic cache cleanup
- Timeout protection (5 minutes per test)

**Test Coverage:**
- hw_management_lib.py (comprehensive pytest suite + legacy unittest suites)
- hw_management_sync.py (ASIC and module population tests)
- BMC accessor tests
- Thermal control tests

### 2. Pytest Runner

Modern pytest-based testing with rich features:

```bash
# Run all pytest tests
pytest

# Run with verbose output
pytest -v

# Run specific test file
pytest offline/test_example_pytest.py

# Run by marker
pytest -m offline
pytest -m "quick and not slow"

# Show test durations
pytest --durations=10

# Parallel execution (requires pytest-xdist)
pytest -n auto
```

## Creating New Tests

### Option 1: Standalone Test

Create a new Python script following existing patterns:

```python
#!/usr/bin/env python3
import unittest

class TestMyFeature(unittest.TestCase):
    def test_something(self):
        self.assertTrue(True)

if __name__ == '__main__':
    unittest.main()
```

Add it to `test.py` to include in the test suite.

### Option 2: Pytest Test (Recommended for New Tests)

Use the pytest example as a template:

```bash
cd tests/offline
cp test_example_pytest.py test_my_feature.py
# Edit test_my_feature.py - remove examples, add your tests
pytest test_my_feature.py -v
```

Example pytest test:

```python
import pytest

class TestMyFeature:
    def test_basic(self, temp_dir):
        """Test with temporary directory fixture"""
        test_file = temp_dir / "test.txt"
        test_file.write_text("data")
        assert test_file.read_text() == "data"
    
    @pytest.mark.parametrize("input,expected", [
        (0, 0),
        (10, 100),
    ])
    def test_with_params(self, input, expected):
        """Parametrized test"""
        assert input ** 2 == expected
```

## Pytest Guide

### Available Fixtures

Fixtures are reusable test components defined in `conftest.py`:

#### Basic Fixtures

- **`temp_dir`** - Temporary directory (auto-cleaned)
- **`hw_mgmt_bin_path`** - Path to hw-mgmt bin directory
- **`project_root`** - Project root directory

#### Mock Fixtures

- **`mock_sysfs`** - Mock sysfs directory structure
- **`mock_hw_management_paths`** - Mock hw-management directories

#### Module Fixtures

- **`hw_mgmt_logger`** - HW_Mgmt_Logger class
- **`hw_mgmt_sync`** - hw_management_sync module

#### Utility Fixtures

- **`capture_logs`** - Capture log output
- **`hw_mgmt_assert`** - Custom assertions (assert_file_exists, etc.)

### Test Markers

Mark tests for categorization:

- `@pytest.mark.offline` - No hardware required (auto-added for offline/)
- `@pytest.mark.hardware` - Requires hardware (auto-added for hardware/)
- `@pytest.mark.unit` - Unit test
- `@pytest.mark.integration` - Integration test
- `@pytest.mark.slow` - Slow-running test
- `@pytest.mark.quick` - Quick test
- `@pytest.mark.hw_mgmt_lib` - hw_management_lib.py tests
- `@pytest.mark.hw_mgmt_sync` - hw_management_sync.py tests

### Running Tests by Marker

```bash
# Only offline tests
pytest -m offline

# Quick tests only
pytest -m quick

# Exclude slow tests
pytest -m "not slow"

# Combine markers
pytest -m "offline and quick"
```

### Parametrized Tests

Run same test with different inputs:

```python
@pytest.mark.parametrize("input,expected", [
    (0, 0),
    (10, 100),
    (20, 400),
])
def test_square(input, expected):
    assert input ** 2 == expected
```

### Mocking

```python
from unittest.mock import patch, Mock

def test_with_mock():
    with patch('module.function') as mock_func:
        mock_func.return_value = 42
        result = module.function()
        assert result == 42
```

### Custom Assertions

```python
def test_file_operations(temp_dir, hw_mgmt_assert):
    file = temp_dir / "test.txt"
    file.write_text("content")
    
    hw_mgmt_assert.assert_file_exists(file)
    hw_mgmt_assert.assert_file_contains(file, "content")
```

## Test Configuration

### pytest.ini

Configuration file for pytest:
- Test discovery patterns
- Default options
- Markers
- Timeout settings (300 seconds)
- Logging configuration

### conftest.py

Shared fixtures and configuration:
- Fixture definitions
- Test hooks
- Auto-marking based on directory
- Custom assertions

## Best Practices

### General

1. **Keep tests independent** - Each test should run in isolation
2. **Use descriptive names** - `test_logger_handles_invalid_file_path`
3. **One logical assertion per test** - Makes failures clear
4. **Clean up resources** - Use fixtures for setup/teardown
5. **Mock external dependencies** - Network, hardware, filesystem

### Pytest Specific

1. **Use fixtures** - Avoid repetitive setup code
2. **Mark appropriately** - Use markers for organization
3. **Parametrize similar tests** - Reduce duplication
4. **Follow Arrange-Act-Assert pattern**:
   ```python
   def test_something():
       # Arrange - setup
       data = create_data()
       
       # Act - execute
       result = process(data)
       
       # Assert - verify
       assert result == expected
   ```

### Standalone Tests

1. **Use unittest framework** - For consistency
2. **Add docstrings** - Explain what the test does
3. **Group related tests** - Use test classes
4. **Handle cleanup** - Use setUp/tearDown methods

## Running Tests in CI/CD

### Pre-commit Hook

The pre-commit hook automatically runs offline tests:
- Located in `.git/hooks/pre-commit`
- Runs `python3 test.py --offline`
- Prevents commit if tests fail

### Manual CI Integration

```bash
# Install dependencies
pip install -r tests/requirements.txt

# Run all tests
cd tests
python3 test.py --all
pytest

# Generate coverage report (if pytest-cov installed)
pytest --cov=../usr/usr/bin --cov-report=html --cov-report=term
```

## Test Development Workflow

### Adding a New Feature Test

1. **Write the test first** (TDD approach):
   ```bash
   cd tests/offline
   cp test_template.py test_my_feature.py
   # Write failing test
   pytest test_my_feature.py -v
   ```

2. **Implement the feature** in the main codebase

3. **Run tests until they pass**:
   ```bash
   pytest test_my_feature.py -v
   ```

4. **Add to test.py if needed** (for standalone tests)

5. **Commit tests with the feature**

### Debugging Failed Tests

```bash
# Run with verbose output
pytest test_file.py -v

# Show local variables on failure
pytest test_file.py -l

# Drop into debugger on failure
pytest test_file.py --pdb

# Show print statements
pytest test_file.py -s

# Run specific test
pytest test_file.py::TestClass::test_method -v
```

## Dependencies

Required:
- Python 3.8+
- Standard library modules

Optional (for pytest):
- `pytest` - Test framework
- `pytest-xdist` - Parallel execution
- `pytest-cov` - Coverage reporting
- `pytest-timeout` - Test timeouts
- `pytest-sugar` - Better output

Install with:
```bash
pip install pytest pytest-xdist pytest-cov pytest-timeout
```

## Coverage Reporting

Generate test coverage reports:

```bash
# Run tests with coverage
pytest --cov=../usr/usr/bin --cov-report=html --cov-report=term

# View HTML report
firefox htmlcov/index.html
```

## Troubleshooting

### Tests Fail with Import Errors

- Check Python path: `sys.path` should include `usr/usr/bin`
- Fixtures in `conftest.py` handle this automatically for pytest
- Standalone tests use `sys.path.insert()`

### Tests Pass Locally but Fail in CI

- Check for hardcoded paths
- Ensure tests are independent (no shared state)
- Verify dependencies are installed
- Check file permissions

### Pytest Not Finding Tests

- Ensure filenames match patterns: `test_*.py` or `*_test.py`
- Test functions must start with `test_`
- Test classes must start with `Test`
- Check `pytest.ini` for configuration

### Cache Issues

The test runner automatically cleans Python cache:
- Removes `__pycache__` directories
- Deletes `.pyc` files
- Run manually: `python3 test.py --offline` (cache cleanup is automatic)

## Additional Resources

- **test_example_pytest.py** - Working examples and template for new tests
- [Pytest Documentation](https://docs.pytest.org/)
- [unittest Documentation](https://docs.python.org/3/library/unittest.html)

## Contact

For questions or issues with the test suite, please contact the hw-mgmt development team.

---

**Happy Testing!**

