# Pytest Guide for hw-mgmt Tests

This guide explains how to write and run pytest-based tests for the hw-mgmt project.

## Quick Start

### Running Tests

```bash
# Run all pytest tests
pytest

# Run specific test file
pytest test_my_module.py

# Run tests with verbose output
pytest -v

# Run only offline tests
pytest -m offline

# Run only hardware tests
pytest -m hardware

# Run tests matching a pattern
pytest -k "test_logger"

# Show test durations
pytest --durations=10

# Run tests in parallel (requires pytest-xdist)
pytest -n auto
```

### Creating New Tests

1. **Copy the template:**
   ```bash
   cp test_template.py test_my_feature.py
   ```

2. **Follow the naming convention:**
   - File: `test_<module>.py` or `<module>_test.py`
   - Class: `Test<Feature>`
   - Function: `test_<description>`

3. **Write your tests:**
   ```python
   import pytest
   
   class TestMyFeature:
       def test_basic_functionality(self):
           assert True
   ```

4. **Run your tests:**
   ```bash
   pytest test_my_feature.py -v
   ```

## Test Organization

```
tests/
├── conftest.py              # Shared fixtures and configuration
├── pytest.ini               # Pytest configuration
├── test_template.py         # Template for new tests
├── PYTEST_GUIDE.md          # This file
├── offline/                 # Offline tests (no hardware needed)
│   └── test_*.py
└── hardware/                # Hardware tests (requires physical hardware)
    └── test_*.py
```

## Available Fixtures

Fixtures are reusable test components defined in `conftest.py`:

### Basic Fixtures

- **`temp_dir`** - Provides a temporary directory, auto-cleaned after test
  ```python
  def test_with_temp(temp_dir):
      file = temp_dir / "test.txt"
      file.write_text("data")
  ```

- **`hw_mgmt_bin_path`** - Path to hw-mgmt bin directory
- **`project_root`** - Path to project root directory

### Mock Fixtures

- **`mock_sysfs`** - Mock sysfs directory structure
  ```python
  def test_sysfs(mock_sysfs):
      thermal = mock_sysfs / "class" / "thermal"
      assert thermal.exists()
  ```

- **`mock_hw_management_paths`** - Mock hw-management directory structure
  ```python
  def test_hw_mgmt(mock_hw_management_paths):
      thermal_dir = mock_hw_management_paths / "thermal"
      assert thermal_dir.exists()
  ```

### Module Fixtures

- **`hw_mgmt_logger`** - Import HW_Mgmt_Logger class
  ```python
  def test_logger(hw_mgmt_logger):
      logger = hw_mgmt_logger(ident="test")
      logger.info("test message")
  ```

- **`hw_mgmt_sync`** - Import hw_management_sync module
  ```python
  def test_sync(hw_mgmt_sync):
      result = hw_mgmt_sync.some_function()
  ```

### Utility Fixtures

- **`capture_logs`** - Capture log output
  ```python
  def test_logging(capture_logs):
      import logging
      logging.info("test")
      assert "test" in capture_logs.text
  ```

- **`hw_mgmt_assert`** - Custom assertions
  ```python
  def test_file(temp_dir, hw_mgmt_assert):
      file = temp_dir / "test.txt"
      file.write_text("data")
      hw_mgmt_assert.assert_file_exists(file)
      hw_mgmt_assert.assert_file_contains(file, "data")
  ```

## Test Markers

Mark tests for categorization and selective execution:

### Built-in Markers

- **`@pytest.mark.offline`** - Test doesn't require hardware (auto-added for offline/)
- **`@pytest.mark.hardware`** - Test requires hardware (auto-added for hardware/)
- **`@pytest.mark.unit`** - Unit test
- **`@pytest.mark.integration`** - Integration test
- **`@pytest.mark.slow`** - Slow-running test
- **`@pytest.mark.quick`** - Quick test

### Module-specific Markers

- **`@pytest.mark.hw_mgmt_lib`** - Tests for hw_management_lib.py
- **`@pytest.mark.hw_mgmt_sync`** - Tests for hw_management_sync.py
- **`@pytest.mark.thermal`** - Thermal control tests
- **`@pytest.mark.bmc`** - BMC accessor tests

### Usage Examples

```python
import pytest

# Mark entire module
pytestmark = pytest.mark.offline

# Mark individual test
@pytest.mark.slow
def test_long_running():
    pass

# Multiple markers
@pytest.mark.offline
@pytest.mark.unit
def test_something():
    pass
```

### Running by Marker

```bash
# Run only offline tests
pytest -m offline

# Run only quick tests
pytest -m quick

# Run offline but not slow tests
pytest -m "offline and not slow"

# Run hardware or integration tests
pytest -m "hardware or integration"
```

## Parametrized Tests

Run the same test with different inputs:

```python
@pytest.mark.parametrize("input,expected", [
    (0, 0),
    (10, 100),
    (20, 400),
])
def test_square(input, expected):
    assert input ** 2 == expected
```

## Mocking

Use mocks to isolate code under test:

```python
from unittest.mock import Mock, patch, MagicMock

def test_with_mock():
    # Mock a function
    with patch('module.function') as mock_func:
        mock_func.return_value = 42
        result = module.function()
        assert result == 42
        mock_func.assert_called_once()

def test_with_mock_object():
    # Create a mock object
    mock_obj = Mock()
    mock_obj.method.return_value = "result"
    assert mock_obj.method() == "result"
```

## Test Fixtures (Setup/Teardown)

```python
import pytest

@pytest.fixture
def resource():
    # Setup
    r = create_resource()
    
    yield r  # Provide to test
    
    # Teardown
    r.cleanup()

def test_with_resource(resource):
    resource.use()
```

## Assertions

### Standard Assertions
```python
assert value == expected
assert value is not None
assert "substring" in string
assert value > 10
```

### Exception Assertions
```python
# Assert exception is raised
with pytest.raises(ValueError):
    raise ValueError("error")

# Check exception message
with pytest.raises(ValueError, match="specific error"):
    raise ValueError("specific error message")
```

### Custom Assertions (hw_mgmt_assert)
```python
def test_custom(hw_mgmt_assert):
    hw_mgmt_assert.assert_file_exists(path)
    hw_mgmt_assert.assert_file_contains(path, "content")
    hw_mgmt_assert.assert_sysfs_value(path, "expected")
```

## Skip and XFail

```python
# Skip test
@pytest.mark.skip(reason="Not ready yet")
def test_future():
    pass

# Skip conditionally
@pytest.mark.skipif(sys.version_info < (3, 8), reason="Requires Python 3.8+")
def test_new_feature():
    pass

# Expected to fail (won't fail the test suite)
@pytest.mark.xfail(reason="Known bug #123")
def test_known_bug():
    assert False
```

## Best Practices

1. **One assertion per test** (when possible)
2. **Use descriptive test names** - `test_logger_handles_invalid_file_path`
3. **Arrange-Act-Assert pattern**:
   ```python
   def test_something():
       # Arrange - setup
       data = setup_data()
       
       # Act - execute
       result = process(data)
       
       # Assert - verify
       assert result == expected
   ```
4. **Use fixtures for setup/teardown** - avoid repetitive setup code
5. **Mark tests appropriately** - use markers for categorization
6. **Keep tests independent** - each test should run in isolation
7. **Use parametrize for similar tests** - avoid code duplication
8. **Mock external dependencies** - network, filesystem, hardware

## Configuration

Edit `pytest.ini` to customize:

- Test discovery patterns
- Default command-line options
- Markers
- Logging configuration
- Coverage settings

## Integration with test.py

The existing `test.py` runner can coexist with pytest:

- **test.py**: Runs existing standalone test scripts
- **pytest**: Runs pytest-style tests

Both can be used together or separately.

## Dependencies

Optional pytest plugins to enhance functionality:

```bash
# Parallel execution
pip install pytest-xdist

# Coverage reporting
pip install pytest-cov

# Test ordering
pip install pytest-ordering

# Timeout for tests
pip install pytest-timeout

# Better output
pip install pytest-sugar
```

## Examples

See `test_template.py` for comprehensive examples of:
- Basic tests
- Parametrized tests
- Mocking
- Fixtures
- Markers
- Error handling
- And more!

## Getting Help

```bash
# Show available fixtures
pytest --fixtures

# Show available markers
pytest --markers

# Show pytest help
pytest --help
```

