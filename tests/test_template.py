"""
Template for creating new pytest tests for hw-mgmt

This template provides a structure and examples for writing new tests.
Copy this file and rename it following the pattern: test_<module_name>.py

Usage:
    1. Copy this file: cp test_template.py test_my_feature.py
    2. Replace the class name and test descriptions
    3. Write your test cases
    4. Run with: pytest test_my_feature.py -v
"""
import pytest
import sys
import os
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Import the module you want to test
# Example: from hw_management_lib import HW_Mgmt_Logger


# Mark this entire module as offline tests (can also use @pytest.mark.hardware)
pytestmark = pytest.mark.offline


class TestModuleTemplate:
    """
    Test class template for a specific module or feature.
    
    Group related tests into classes for better organization.
    """
    
    def test_basic_functionality(self, temp_dir):
        """
        Test basic functionality of the module.
        
        Args:
            temp_dir: Fixture providing a temporary directory
        """
        # Arrange - Set up test data and conditions
        test_file = temp_dir / "test.txt"
        expected_content = "Hello, World!"
        
        # Act - Execute the code being tested
        test_file.write_text(expected_content)
        actual_content = test_file.read_text()
        
        # Assert - Verify the results
        assert actual_content == expected_content
        assert test_file.exists()
    
    def test_with_mock(self, hw_mgmt_logger):
        """
        Example test using mocks.
        
        Args:
            hw_mgmt_logger: Fixture providing HW_Mgmt_Logger class
        """
        # Mock external dependencies
        with patch('syslog.openlog') as mock_openlog:
            # Create instance with mocked dependencies
            # logger = hw_mgmt_logger(ident="test")
            
            # Verify mock was called
            # mock_openlog.assert_called_once()
            pass
    
    @pytest.mark.parametrize("input_value,expected_output", [
        (0, 0),
        (10, 1250),
        (100, 12500),
        (-10, 65526),
    ])
    def test_parametrized(self, input_value, expected_output):
        """
        Example of parametrized test - runs multiple times with different inputs.
        
        This test will run 4 times with different input/output pairs.
        """
        # Example: test temperature conversion
        # result = convert_temperature(input_value)
        # assert result == expected_output
        pass
    
    def test_error_handling(self):
        """Test that errors are handled correctly"""
        # Test that expected exceptions are raised
        with pytest.raises(ValueError):
            # Code that should raise ValueError
            raise ValueError("Expected error")
    
    def test_with_fixtures(self, temp_dir, mock_sysfs, hw_mgmt_assert):
        """
        Example using multiple fixtures.
        
        Args:
            temp_dir: Temporary directory fixture
            mock_sysfs: Mock sysfs structure
            hw_mgmt_assert: Custom assertion helpers
        """
        # Create a test file
        test_file = temp_dir / "test.txt"
        test_file.write_text("test content")
        
        # Use custom assertions
        hw_mgmt_assert.assert_file_exists(test_file)
        hw_mgmt_assert.assert_file_contains(test_file, "test")


class TestAnotherFeature:
    """Another test class for a different feature"""
    
    @pytest.mark.slow
    def test_slow_operation(self):
        """
        Mark tests that are slow running.
        
        Can be skipped with: pytest -m "not slow"
        """
        # Slow test code here
        pass
    
    @pytest.mark.skip(reason="Not implemented yet")
    def test_future_feature(self):
        """Test for a feature that's not implemented yet"""
        pass
    
    @pytest.mark.xfail(reason="Known bug #123")
    def test_known_issue(self):
        """Test for a known failing case"""
        assert False, "This is expected to fail"


# Test functions (not in a class)
def test_standalone_function():
    """Simple standalone test function"""
    assert True


def test_with_caplog(capture_logs):
    """Test that checks log messages"""
    import logging
    logger = logging.getLogger(__name__)
    
    logger.info("Test log message")
    
    # Check log was captured
    assert "Test log message" in capture_logs.text


@pytest.fixture
def custom_fixture():
    """
    Example of a test-specific fixture.
    
    Fixtures can also be defined in the test file itself.
    """
    # Setup
    data = {"key": "value"}
    
    yield data
    
    # Teardown (runs after test)
    data.clear()


def test_with_custom_fixture(custom_fixture):
    """Test using the custom fixture defined above"""
    assert custom_fixture["key"] == "value"


# Conditional tests
@pytest.mark.skipif(sys.version_info < (3, 8), reason="Requires Python 3.8+")
def test_python_version_specific():
    """Test that only runs on Python 3.8+"""
    pass


# Integration test example
@pytest.mark.integration
def test_integration_scenario(temp_dir, hw_mgmt_logger):
    """
    Integration test that tests multiple components together.
    
    Mark with @pytest.mark.integration to separate from unit tests.
    Run with: pytest -m integration
    """
    pass


if __name__ == "__main__":
    # Allow running tests directly with: python test_template.py
    pytest.main([__file__, "-v"])

