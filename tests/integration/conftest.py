"""
Pytest fixtures for integration tests.

Integration tests verify end-to-end functionality and service interactions.
"""
import pytest
import subprocess
import time
from pathlib import Path

# Mark all tests in this directory as integration
pytestmark = pytest.mark.integration

@pytest.fixture(scope="session")
def hw_mgmt_services():
    """
    Manage hw-mgmt services for integration testing.
    
    This fixture can start/stop services as needed for integration tests.
    """
    services_started = []
    
    def start_service(service_name):
        """Start a hw-mgmt service for testing."""
        try:
            subprocess.run(["systemctl", "start", service_name], check=True, capture_output=True)
            services_started.append(service_name)
            time.sleep(2)  # Give service time to start
            return True
        except subprocess.CalledProcessError:
            return False
    
    def stop_service(service_name):
        """Stop a hw-mgmt service."""
        try:
            subprocess.run(["systemctl", "stop", service_name], check=True, capture_output=True)
            return True
        except subprocess.CalledProcessError:
            return False
    
    yield {"start": start_service, "stop": stop_service}
    
    # Cleanup: stop all started services
    for service in services_started:
        stop_service(service)

@pytest.fixture
def hw_mgmt_config_backup():
    """Backup and restore hw-mgmt configuration files during tests."""
    import shutil
    import tempfile
    
    config_paths = [
        "/etc/hw-management-thermal/",
        "/etc/hw-management-sensors/"
    ]
    
    backups = {}
    
    # Create backups
    for config_path in config_paths:
        path = Path(config_path)
        if path.exists():
            backup_path = Path(tempfile.mkdtemp()) / path.name
            shutil.copytree(path, backup_path)
            backups[config_path] = backup_path
    
    yield
    
    # Restore backups
    for original_path, backup_path in backups.items():
        if Path(backup_path).exists():
            if Path(original_path).exists():
                shutil.rmtree(original_path)
            shutil.copytree(backup_path, original_path)
            shutil.rmtree(backup_path)

@pytest.fixture
def sysfs_environment():
    """Mock or verify sysfs environment for integration tests."""
    # This could mock sysfs entries or verify they exist
    # depending on the test environment
    yield

@pytest.fixture
def integration_timeout():
    """Timeout for integration test operations."""
    return 60  # seconds for longer integration operations
