"""
Example pytest test to demonstrate the pytest infrastructure.

This file shows how to write pytest tests for hw-mgmt.
Run with: pytest test_example_pytest.py -v
"""
import pytest
from pathlib import Path

# Mark all tests in this file as offline tests
pytestmark = pytest.mark.offline


class TestExampleBasic:
    """Example basic test class"""
    
    def test_simple_assertion(self):
        """Test simple assertion"""
        assert 1 + 1 == 2
    
    def test_with_temp_dir(self, temp_dir):
        """Test using temp_dir fixture"""
        # Create a file in temp directory
        test_file = temp_dir / "example.txt"
        test_file.write_text("Hello, pytest!")
        
        # Verify file exists and has correct content
        assert test_file.exists()
        assert test_file.read_text() == "Hello, pytest!"
    
    def test_path_fixture(self, hw_mgmt_bin_path, project_root):
        """Test path fixtures"""
        assert hw_mgmt_bin_path.exists()
        assert project_root.exists()
        assert (project_root / "usr" / "usr" / "bin").exists()


class TestExampleMocking:
    """Example tests using mocking"""
    
    def test_mock_sysfs(self, mock_sysfs):
        """Test mock sysfs structure"""
        thermal_dir = mock_sysfs / "class" / "thermal"
        assert thermal_dir.exists()
        
        # Create a mock thermal zone
        tz0 = thermal_dir / "thermal_zone0"
        tz0.mkdir()
        (tz0 / "temp").write_text("45000")
        
        assert (tz0 / "temp").read_text() == "45000"
    
    def test_mock_hw_management(self, mock_hw_management_paths):
        """Test mock hw-management paths"""
        thermal_dir = mock_hw_management_paths / "thermal"
        assert thermal_dir.exists()
        
        # Create a mock temperature file
        temp_file = thermal_dir / "asic"
        temp_file.write_text("50000")
        
        assert temp_file.read_text() == "50000"


class TestExampleParametrized:
    """Example parametrized tests"""
    
    @pytest.mark.parametrize("value,expected", [
        (0, True),
        (1, False),
        (2, True),
        (3, False),
    ])
    def test_even_numbers(self, value, expected):
        """Test if number is even"""
        assert (value % 2 == 0) == expected
    
    @pytest.mark.parametrize("temp_c,temp_f", [
        (0, 32),
        (100, 212),
        (-40, -40),
    ])
    def test_temperature_conversion(self, temp_c, temp_f):
        """Test Celsius to Fahrenheit conversion"""
        result = (temp_c * 9/5) + 32
        assert abs(result - temp_f) < 0.01


class TestExampleCustomAssertions:
    """Example using custom assertions"""
    
    def test_file_assertions(self, temp_dir, hw_mgmt_assert):
        """Test custom file assertions"""
        test_file = temp_dir / "test.txt"
        test_file.write_text("This is test content")
        
        # Use custom assertions
        hw_mgmt_assert.assert_file_exists(test_file)
        hw_mgmt_assert.assert_file_contains(test_file, "test content")
    
    def test_sysfs_assertions(self, mock_sysfs, hw_mgmt_assert):
        """Test sysfs value assertions"""
        temp_file = mock_sysfs / "temp"
        temp_file.write_text("42000")
        
        hw_mgmt_assert.assert_sysfs_value(temp_file, "42000")


class TestExampleMarkers:
    """Example using different markers"""
    
    @pytest.mark.quick
    def test_quick_operation(self):
        """Quick test"""
        assert True
    
    @pytest.mark.slow
    def test_slow_operation(self):
        """Slow test (can be skipped with: pytest -m "not slow")"""
        import time
        time.sleep(0.1)
        assert True
    
    @pytest.mark.unit
    def test_unit_level(self):
        """Unit level test"""
        assert True


def test_standalone_function():
    """Example standalone test function"""
    result = sum([1, 2, 3, 4])
    assert result == 10


@pytest.mark.skipif(False, reason="Example of conditional skip")
def test_conditional():
    """This test runs because condition is False"""
    assert True


if __name__ == "__main__":
    # Allow running tests directly
    pytest.main([__file__, "-v"])

