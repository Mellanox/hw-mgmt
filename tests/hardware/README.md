# Hardware Integration Tests

This directory contains hardware integration tests that interact with real hardware and DVS (Data Vortex System).

## Overview

These tests verify the actual functionality of the hw-management services on real hardware:

- **test_thermal_updater_integration.py** - Tests thermal monitoring (ASIC and module temperatures)
- **test_peripheral_updater_integration.py** - Tests peripheral monitoring (fans, chipup status, leakage sensors)

## Prerequisites

### Required

1. **Hardware System**: Tests must run on actual hardware with hw-management installed
2. **DVS Tools**: `dvs_start.sh` and `dvs_stop.sh` must be in PATH
3. **Root Access**: Tests require sudo for service management
4. **Systemd Services**: 
   - hw-management-thermal-updater.service
   - hw-management-peripheral-updater.service

### System Paths Required

- `/var/run/hw-management/thermal/` - Thermal monitoring files
- `/var/run/hw-management/config/` - Configuration files
- `/lib/systemd/system/` - Service files

## Running the Tests

### SSH-Based Hardware Testing (Recommended)

Hardware tests automatically SSH to the target hardware, copy test files, and run them remotely:

```bash
# Run all hardware tests via SSH
python3 tests/test.py --hardware --host <hostname> --user <username> --password <password>

# Example
python3 tests/test.py --hardware --host 10.0.0.100 --user root --password mypassword
```

**Requirements for SSH-based testing:**
- `sshpass` installed on local machine: `sudo apt-get install sshpass`
- SSH access to hardware with provided credentials
- sudo/root access on hardware (tests run with sudo)

### Direct Hardware Testing (On Hardware)

If you're already on the hardware system, you can run tests directly:

```bash
# From repository root on hardware
sudo python3 -m pytest tests/hardware/ -v

# Or using unittest
sudo python3 -m unittest discover tests/hardware/ -v
```

### Run Specific Test Suite

```bash
# Thermal updater tests only (on hardware)
sudo python3 tests/hardware/test_thermal_updater_integration.py

# Peripheral updater tests only (on hardware)
sudo python3 tests/hardware/test_peripheral_updater_integration.py

# Via SSH (thermal only)
python3 tests/test.py --hardware --host 10.0.0.100 --user root --password pass
```

### Run Individual Test

```bash
# Run specific test case (on hardware)
sudo python3 -m pytest tests/hardware/test_thermal_updater_integration.py::ThermalUpdaterIntegrationTest::test_01_thermal_files_empty_without_dvs -v
```

## Test Scenarios

### Thermal Updater Tests

1. **test_01_thermal_files_empty_without_dvs**
   - Verifies thermal files are empty when DVS is not running
   - Tests file creation by updater service

2. **test_02_thermal_files_populated_with_dvs**
   - Starts DVS with `--sdk_bridge_mode=HYBRID`
   - Verifies ASIC and module temperature files get populated
   - Checks that values are read from hardware

3. **test_03_thermal_files_empty_after_dvs_stop**
   - Verifies files become empty when DVS stops
   - Tests cleanup behavior

4. **test_04_service_restart_persistence**
   - Tests service restart while DVS is running
   - Verifies monitoring resumes after restart

### Peripheral Updater Tests

1. **test_01_chipup_files_empty_without_dvs**
   - Checks ASIC chipup status files without DVS
   - Verifies initial state

2. **test_02_chipup_files_populated_with_dvs**
   - Starts DVS and monitors chipup status
   - Verifies chipup completion tracking

3. **test_03_fan_files_monitoring**
   - Verifies fan status files are monitored
   - Checks fan speed readings

4. **test_04_service_restart_persistence**
   - Tests peripheral service restart
   - Verifies continuous monitoring

5. **test_05_chipup_status_after_dvs_cycle**
   - Full DVS start/stop cycle
   - Monitors chipup status changes

## Known Limitations

### BMC Tests Skipped

BMC (Redfish) sensor tests are currently skipped because:
- BMC is not available on the test system
- Redfish endpoint not accessible

To enable BMC tests in the future:
1. Ensure BMC is configured and accessible
2. Add BMC-specific test cases
3. Update service configuration with BMC credentials

### Test Timing

- DVS startup: ~30 seconds
- File population: ~10 seconds
- Service restart: ~2-5 seconds

These timeouts are configurable in the test classes.

## Test Output

Tests produce detailed output including:
- Service status
- File states (empty/populated)
- Sample file contents
- DVS start/stop status

Example output:
```
======================================================================
THERMAL UPDATER HARDWARE INTEGRATION TESTS
======================================================================
Stopping DVS before tests...

----------------------------------------------------------------------
TEST 1: Thermal files empty without DVS
----------------------------------------------------------------------
Cleaning thermal files in /var/run/hw-management/thermal...
  Cleaned: asic
  Cleaned: asic1
  Cleaned: module1_temp_input
  ...
Cleaned 15 files
Starting service: hw-management-thermal-updater
Found 5 ASIC files
Found 10 module files
PASS: All thermal files are empty without DVS
```

## Troubleshooting

### SSH Connection Issues

If SSH-based tests fail to connect:

```bash
# Test SSH connectivity manually
ssh <user>@<host>

# Check if sshpass is installed
which sshpass

# Install sshpass if missing
sudo apt-get install sshpass

# Verify credentials are correct
sshpass -p '<password>' ssh <user>@<host> 'echo "Connection successful"'
```

### Tests Fail to Start Services (On Hardware)

Check service status:
```bash
systemctl status hw-management-thermal-updater
systemctl status hw-management-peripheral-updater
```

View service logs:
```bash
journalctl -u hw-management-thermal-updater -n 50
journalctl -u hw-management-peripheral-updater -n 50
```

### DVS Not Found

Ensure DVS tools are in PATH on the hardware:
```bash
# On hardware
which dvs_start.sh
which dvs_stop.sh

# Add to PATH if needed
export PATH=$PATH:/path/to/dvs/tools
```

### Permission Denied

Tests require root access on hardware:
```bash
# Direct on hardware
sudo python3 tests/hardware/test_thermal_updater_integration.py

# Via SSH (automatically uses sudo)
python3 tests/test.py --hardware --host <host> --user root --password <pass>
```

### Files Not Created

Check hw-management installation on hardware:
```bash
ls -la /var/run/hw-management/
systemctl status hw-management.service
```

### Test Files Not Copied via SSH

Check remote directory permissions:
```bash
# SSH and check /tmp permissions
ssh <user>@<host> 'ls -la /tmp'

# Tests use /tmp/hw_mgmt_hardware_tests directory
# Ensure /tmp is writable
```

## Cleanup

Tests automatically cleanup:
- Stop DVS after completion
- Stop updater services
- Leave files in place (for debugging)

Manual cleanup if needed:
```bash
# Stop services
sudo systemctl stop hw-management-thermal-updater
sudo systemctl stop hw-management-peripheral-updater

# Stop DVS
dvs_stop.sh

# Clean thermal files
sudo rm -f /var/run/hw-management/thermal/asic*
sudo rm -f /var/run/hw-management/thermal/module*
```

## Integration with Main Test Suite

The main test runner (`tests/test.py`) can run hardware tests:

```bash
# Run with hardware tests included
sudo python3 tests/test.py --hardware

# Run offline tests only (default)
python3 tests/test.py --offline
```

## Contributing

When adding new hardware tests:

1. Follow existing test structure
2. Include cleanup in tearDown/tearDownClass
3. Handle missing hardware gracefully (skipTest)
4. Add clear docstrings explaining test purpose
5. Update this README with new test descriptions
6. Consider test timing and timeouts

## Support

For issues or questions:
- Check systemd logs for service errors
- Verify hardware prerequisites
- Review test output for specific failures
- Ensure DVS is properly configured

