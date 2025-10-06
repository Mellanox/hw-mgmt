"""
Pytest configuration and shared fixtures for hw-mgmt test suite
"""
import sys
import os
import pytest
import tempfile
import shutil
from pathlib import Path

# Add hw-mgmt bin directory to Python path
TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"

if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))


# Pytest configuration hooks
def pytest_configure(config):
    """Configure pytest with custom settings"""
    config.addinivalue_line(
        "markers", "offline: mark test as offline test that doesn't require hardware"
    )
    config.addinivalue_line(
        "markers", "hardware: mark test as hardware test that requires physical hardware"
    )


def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers based on file location"""
    for item in items:
        # Add offline marker to tests in offline directory
        if "offline" in str(item.fspath):
            item.add_marker(pytest.mark.offline)
        
        # Add hardware marker to tests in hardware directory
        if "hardware" in str(item.fspath):
            item.add_marker(pytest.mark.hardware)


# Shared fixtures
@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files"""
    temp_path = tempfile.mkdtemp()
    yield Path(temp_path)
    # Cleanup after test
    shutil.rmtree(temp_path, ignore_errors=True)


@pytest.fixture
def hw_mgmt_bin_path():
    """Return the path to hw-mgmt bin directory"""
    return HW_MGMT_BIN


@pytest.fixture
def project_root():
    """Return the project root directory"""
    return PROJECT_ROOT


@pytest.fixture
def mock_sysfs(temp_dir):
    """Create a mock sysfs directory structure"""
    sysfs_root = temp_dir / "sys"
    sysfs_root.mkdir(parents=True, exist_ok=True)
    
    # Create common sysfs paths
    thermal_dir = sysfs_root / "class" / "thermal"
    thermal_dir.mkdir(parents=True, exist_ok=True)
    
    hwmon_dir = sysfs_root / "class" / "hwmon"
    hwmon_dir.mkdir(parents=True, exist_ok=True)
    
    return sysfs_root


@pytest.fixture
def mock_hw_management_paths(temp_dir):
    """Create mock hw-management directory structure"""
    hw_mgmt_root = temp_dir / "var" / "run" / "hw-management"
    
    # Create subdirectories
    (hw_mgmt_root / "thermal").mkdir(parents=True, exist_ok=True)
    (hw_mgmt_root / "config").mkdir(parents=True, exist_ok=True)
    (hw_mgmt_root / "eeprom").mkdir(parents=True, exist_ok=True)
    (hw_mgmt_root / "led").mkdir(parents=True, exist_ok=True)
    (hw_mgmt_root / "power").mkdir(parents=True, exist_ok=True)
    
    return hw_mgmt_root


@pytest.fixture
def hw_mgmt_logger():
    """Import and return HW_Mgmt_Logger class"""
    try:
        from hw_management_lib import HW_Mgmt_Logger
        return HW_Mgmt_Logger
    except ImportError as e:
        pytest.skip(f"Cannot import HW_Mgmt_Logger: {e}")


@pytest.fixture
def hw_mgmt_sync():
    """Import and return hw_management_sync module"""
    try:
        import hw_management_sync
        return hw_management_sync
    except ImportError as e:
        pytest.skip(f"Cannot import hw_management_sync: {e}")


@pytest.fixture(autouse=True)
def reset_logging():
    """Reset logging configuration between tests"""
    import logging
    # Remove all handlers
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)
    # Reset level
    logging.root.setLevel(logging.WARNING)
    yield
    # Cleanup after test
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)


@pytest.fixture
def capture_logs(caplog):
    """Fixture to easily capture and check log messages"""
    import logging
    caplog.set_level(logging.DEBUG)
    return caplog


# Custom assertions
class HwMgmtAssertions:
    """Custom assertions for hw-mgmt tests"""
    
    @staticmethod
    def assert_file_exists(path, msg=None):
        """Assert that a file exists"""
        path = Path(path)
        assert path.exists(), msg or f"File does not exist: {path}"
    
    @staticmethod
    def assert_file_contains(path, content, msg=None):
        """Assert that a file contains specific content"""
        path = Path(path)
        assert path.exists(), f"File does not exist: {path}"
        text = path.read_text()
        assert content in text, msg or f"File {path} does not contain: {content}"
    
    @staticmethod
    def assert_sysfs_value(path, expected_value, msg=None):
        """Assert sysfs file has expected value"""
        path = Path(path)
        assert path.exists(), f"Sysfs file does not exist: {path}"
        actual = path.read_text().strip()
        assert actual == str(expected_value), msg or f"Expected {expected_value}, got {actual}"


@pytest.fixture
def hw_mgmt_assert():
    """Provide custom assertions for hw-mgmt tests"""
    return HwMgmtAssertions()

