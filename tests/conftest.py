"""
Global pytest configuration and fixtures for NVIDIA HW-MGMT test suite.
"""
import pytest
import sys
import os
from pathlib import Path

# Add hw-mgmt modules to Python path for all tests  
def setup_python_path():
    """Ensure hw-mgmt modules are in PYTHONPATH for tests."""
    # Get paths relative to tests directory
    tests_dir = Path(__file__).parent
    base_dir = tests_dir.parent  # hw-mgmt root
    hw_mgmt_bin_dir = base_dir / "usr" / "usr" / "bin"
    
    paths_to_add = [
        str(hw_mgmt_bin_dir),
        str(tests_dir),  # tests directory
        str(tests_dir / "offline"),
        str(tests_dir / "hardware"),
        str(tests_dir / "integration")
    ]
    
    for path in paths_to_add:
        if path not in sys.path:
            sys.path.insert(0, path)
    
    # Set PYTHONPATH environment variable for subprocess calls
    current_pythonpath = os.environ.get('PYTHONPATH', '')
    new_pythonpath = ':'.join(paths_to_add)
    if current_pythonpath:
        os.environ['PYTHONPATH'] = f"{new_pythonpath}:{current_pythonpath}"
    else:
        os.environ['PYTHONPATH'] = new_pythonpath
        
# Call setup immediately when conftest is loaded
setup_python_path()

@pytest.fixture(scope="session")
def hw_mgmt_root():
    """Path to hw-mgmt repository root."""
    return Path(__file__).parent.parent

@pytest.fixture(scope="session") 
def hw_mgmt_bin_dir(hw_mgmt_root):
    """Path to hw-mgmt binary directory."""
    return hw_mgmt_root / "usr" / "usr" / "bin"

@pytest.fixture(scope="session")
def hw_mgmt_config_dir(hw_mgmt_root):
    """Path to hw-mgmt configuration directory.""" 
    return hw_mgmt_root / "usr" / "etc"

@pytest.fixture
def test_data_dir():
    """Path to test data directory."""
    return Path(__file__).parent / "test_data"

# Custom pytest command line options
def pytest_addoption(parser):
    """Add custom command line options."""
    parser.addoption(
        "--bmc-ip",
        action="store", 
        default="192.168.1.100",
        help="BMC IP address for hardware tests"
    )
    parser.addoption(
        "--hardware",
        action="store_true",
        default=False,
        help="Force hardware tests to run (sets PYTEST_HARDWARE=1)"
    )

@pytest.fixture
def bmc_ip(request):
    """Get BMC IP from command line."""
    return request.config.getoption("--bmc-ip")

def pytest_configure(config):
    """Configure pytest based on command line options."""
    # Set hardware environment variable if --hardware flag is used
    if config.getoption("--hardware"):
        os.environ["PYTEST_HARDWARE"] = "1"
    
    # Register custom markers
    for marker in [
        "offline: Tests that require no special hardware", 
        "hardware: Tests that require real hardware components",
        "integration: End-to-end integration tests",
        "slow: Tests that take >5 seconds", 
        "bmc: BMC communication tests",
        "logger: Logging functionality tests",
        "thermal: Thermal control tests",
        "sensors: Hardware sensor tests",
        "sync: Data synchronization tests", 
        "cli: Command-line interface tests"
    ]:
        config.addinivalue_line("markers", marker)

def pytest_collection_modifyitems(config, items):
    """Modify test collection based on markers and options."""
    # Skip hardware tests if hardware is not available and not forced
    if not os.environ.get("PYTEST_HARDWARE") and not config.getoption("--hardware"):
        skip_hardware = pytest.mark.skip(reason="Hardware tests skipped (use --hardware to force)")
        for item in items:
            if "hardware" in item.keywords:
                item.add_marker(skip_hardware)

def pytest_runtest_setup(item):
    """Setup hook for each test."""
    # Add any per-test setup logic here
    pass

def pytest_runtest_teardown(item):
    """Teardown hook for each test.""" 
    # Add any per-test cleanup logic here
    pass