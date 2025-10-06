"""
Pytest fixtures for hardware-dependent tests.

Hardware tests require actual hardware components and should be run
only in appropriate test environments.
"""
import pytest
from unittest.mock import patch

# Mark all tests in this directory as hardware
pytestmark = pytest.mark.hardware

@pytest.fixture(autouse=True)
def skip_if_no_hardware(request):
    """
    Fixture to skip hardware tests if no hardware is detected.
    
    This can be overridden by setting PYTEST_HARDWARE=1 environment variable.
    """
    import os
    
    # Allow forcing hardware tests via environment variable
    if os.environ.get("PYTEST_HARDWARE") == "1":
        return
    
    if not _is_hardware_present():
        pytest.skip("Skipping hardware test: No hardware detected. Set PYTEST_HARDWARE=1 to force.")

def _is_hardware_present():
    """
    Check for presence of required hardware.
    
    In a real scenario, this would check for:
    - Specific sysfs entries
    - BMC accessibility 
    - TPM availability
    - Required kernel modules
    """
    import os
    
    # Check for common hardware indicators
    hardware_indicators = [
        "/sys/class/thermal",
        "/sys/class/hwmon", 
        "/dev/tpm0",
        "/sys/bus/i2c"
    ]
    
    return any(os.path.exists(path) for path in hardware_indicators)

@pytest.fixture
def bmc_ip():
    """Provides BMC IP from environment or uses default."""
    import os
    return os.environ.get("BMC_IP", "192.168.1.100")

@pytest.fixture
def hardware_timeout():
    """Provides timeout for hardware operations."""
    return 30  # seconds

@pytest.fixture
def tpm_available():
    """Check if TPM hardware is available."""
    import os
    return os.path.exists("/dev/tpm0")

@pytest.fixture(autouse=True)
def hardware_cleanup():
    """Cleanup any hardware state after each test."""
    yield
    # Add cleanup logic here if needed
    # e.g., reset fan speeds, clear sensor caches, etc.
    pass
