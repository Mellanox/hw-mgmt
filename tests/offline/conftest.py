"""
Pytest fixtures for offline tests.

Offline tests should not require any special hardware and should run
in CI/CD environments.
"""
import pytest
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, patch

# Mark all tests in this directory as offline
pytestmark = pytest.mark.offline

@pytest.fixture
def temp_dir():
    """Provides a temporary directory for tests and cleans it up."""
    path = Path(tempfile.mkdtemp())
    yield path
    shutil.rmtree(path)

@pytest.fixture
def temp_log_file():
    """Provides a path to a temporary log file in the logs directory."""
    from pathlib import Path
    import tempfile
    import os
    
    # Use the logs directory for better organization
    logs_dir = Path(__file__).parent.parent / "logs"
    logs_dir.mkdir(exist_ok=True)
    
    # Create a unique temporary file in logs directory
    fd, temp_path = tempfile.mkstemp(suffix='.log', prefix='test_', dir=logs_dir)
    os.close(fd)  # Close the file descriptor
    
    temp_file = Path(temp_path)
    yield temp_file
    
    # Cleanup after test
    if temp_file.exists():
        temp_file.unlink()

@pytest.fixture(autouse=True)
def mock_syslog_module():
    """Mocks the syslog module for offline tests."""
    with patch('syslog.openlog'), \
         patch('syslog.syslog'), \
         patch('syslog.closelog'):
        yield

@pytest.fixture
def sample_bom_strings():
    """Provides sample BOM strings for testing."""
    return {
        "switch_board": "V0-C*EiRaA0-K*G0EgEgJa-S*GbGbTbTbRgRgJ0J0RgRgRgRg-F*Tb-L*GcNaEi-P*PaPa-O*Tb",
        "cpu_board": "V0-C*EiRaA0",
        "fan_board": "V0-F*Tb", 
        "power_board": "V0-P*PaPa",
        "invalid": "INVALID_BOM_STRING"
    }

@pytest.fixture
def mock_hw_mgmt_paths():
    """Mock hardware management file system paths for testing."""
    with patch('os.path.exists') as mock_exists:
        mock_exists.return_value = True
        yield mock_exists

@pytest.fixture
def hw_mgmt_logger():
    """Fixture to provide a HW_Mgmt_Logger factory function for tests."""
    from hw_management_lib import HW_Mgmt_Logger
    
    def logger_factory(**kwargs):
        """Factory function to create logger instances with custom parameters."""
        return HW_Mgmt_Logger(**kwargs)
    
    # Add all class attributes to the factory for test compatibility
    logger_factory.DEBUG = HW_Mgmt_Logger.DEBUG
    logger_factory.INFO = HW_Mgmt_Logger.INFO
    logger_factory.NOTICE = getattr(HW_Mgmt_Logger, 'NOTICE', HW_Mgmt_Logger.INFO + 5)
    logger_factory.WARNING = HW_Mgmt_Logger.WARNING
    logger_factory.ERROR = HW_Mgmt_Logger.ERROR
    logger_factory.CRITICAL = HW_Mgmt_Logger.CRITICAL
    
    # Add any other attributes from the actual class
    for attr_name in dir(HW_Mgmt_Logger):
        if not attr_name.startswith('_') and not hasattr(logger_factory, attr_name):
            attr_value = getattr(HW_Mgmt_Logger, attr_name)
            if not callable(attr_value):  # Only copy non-method attributes
                setattr(logger_factory, attr_name, attr_value)
    
    return logger_factory

@pytest.fixture
def hw_mgmt_dir():
    """Fixture to provide the hw-mgmt binary directory path."""
    from pathlib import Path
    return Path(__file__).parent.parent.parent / "usr" / "usr" / "bin"

@pytest.fixture
def bom_decoder_module():
    """Fixture to import and provide the BOM decoder CLI module."""
    import sys
    from pathlib import Path
    
    # Add the tools directory to Python path to import bom_decoder_cli
    tools_dir = Path(__file__).parent.parent / "tools"
    if str(tools_dir) not in sys.path:
        sys.path.insert(0, str(tools_dir))
        
    try:
        import bom_decoder_cli
        return bom_decoder_cli
    except ImportError:
        pytest.skip("BOM decoder CLI module not available")
