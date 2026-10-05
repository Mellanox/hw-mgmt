# Hardware Integration Tests

This directory contains hardware integration tests that interact with real hardware and DVS (Data Vortex System).

## Overview

These tests verify the actual functionality of the hw-management services on real hardware:

- **test_thermal_updater_integration.py** - Tests thermal monitoring (ASIC and module temperatures)
- **test_peripheral_updater_integration.py** - Tests peripheral monitoring (fans, chipup status, leakage sensors)
- **ssd_dump_lock_test.sh** - Tests the SSD dump lock (shell, no pytest, see [SSD dump lock test](#ssd-dump-lock-test))

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
python3 tests/test.py --hardware --host <hostname> --user <username> --password <credentials>

# Example
python3 tests/test.py --hardware --host 10.0.0.100 --user root --password ********
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
python3 tests/test.py --hardware --host 10.0.0.100 --user root --password ********
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

## SSD dump lock test

`ssd_dump_lock_test.sh` checks that only one SSD dump collection
runs at a time (`flock` on `/run/hw-management-ssd-dump.lock`,
exit code 3) — required both because the work dir is a single
fixed location and because a vendor dump tool supports only one
instance at a time — and that the lock covers the SSD dump
**only**, so a busy lock never costs you the rest of the hw-mgmt
dump. It is a plain shell script: no pytest, no Python test deps
on the target.

| # | Running | Called in parallel |
|---|---------|--------------------|
| 0 | - | baseline, one collect, no contention |
| 1 | `hw-management-ssd-dump.py` | `hw-management-ssd-dump.py` |
| 2 | `hw-management-ssd-dump.py` | `hw-management-ssd-dump.py --verify` |
| 3 | `hw-management-ssd-dump.py` | `hw-management-generate-dump.sh` |
| 4 | `hw-management-ssd-dump-collect.sh` | `hw-management-ssd-dump.py` |
| 5 | `hw-management-ssd-dump.py` | `hw-management-ssd-dump-collect.sh` |
| 6 | `hw-management-generate-dump.sh` | `hw-management-ssd-dump.py` |
| 7 | a collect that finishes mid-wait | `hw-management-ssd-dump-collect.sh` |
| 8 | `hw-management-ssd-dump-collect.sh` that finishes mid-wait | `hw-management-ssd-dump-collect.sh` |
| 9 | a `--no-tar` collect that finishes mid-wait | `hw-management-ssd-dump-collect.sh` |
| 10 | a collect into a custom `--outdir` that finishes mid-wait | `hw-management-ssd-dump-collect.sh` |

The two sides are asymmetric because the full system dump has
priority. Scenarios 1, 2, 4 and 6 call the **collector**, which
gives up at once: each asserts it exits 3, says
`SSD dump tool busy:` and names the holder's pid, claims no
success, and above all leaves the running collection's work
directory byte for byte intact.

Scenarios 5, 7, 8, 9 and 10 call the **helper**, which waits
instead.
Scenario 5 never frees the lock, so the helper must wait the
whole budget (measured, not assumed) and only then exit 3.
Scenarios 7, 8 and 9 free it mid-wait and check what the helper
does with the result the other run left: reuse
`/var/log/ssd-dump.tar.gz` (7), reuse a `--no-tar`
`/var/log/ssd-dump/` (9), or collect for itself when the other
run was another helper and so left nothing (8). The stub vendor
tool counts its own invocations, so "reused" means the SSD
really was not driven a second time rather than merely that a
log line was printed; 7 and 9 also assert the source is left
where its owner put it.

Scenario 10 is the other half of that: the holder collects into
its own `--outdir`, so an hour-old `/var/log/ssd-dump.tar.gz`
staged beforehand is still sitting there, `status: ok`, when the
lock frees. Reusing it would pack an hour-old dump into the
system dump and call it a success, so the helper must collect
instead, which again shows up as one more stub invocation.

Scenarios 3 and 6 are the two orderings of the same collision
and both unpack `/tmp/hw-mgmt-dump.tar.gz` to check the outcome.
In 3 generate-dump is the one refused, so the dump must still
contain its non-SSD sections with `ssd-dump/ssd-dump-status.log`
marked `locked: yes`. In 6 generate-dump got there first, so the
dump must contain a complete `status: ok` SSD section and the
standalone CLI is the one turned away. Scenario 6 waits for
generate-dump to reach its SSD step, which is near the end of a
full collection, and identifies the holder through `/proc`
because the lock is taken by the helper generate-dump spawns
rather than by generate-dump itself.

The process that holds the lock is a real collector run whose
vendor tool is replaced, through a generated `--config`, by a
stub that writes one dump file and then blocks until the test
releases it, so the hold is deterministic. Everything that
collects here goes through that config — the helper under test
too, via a `PATH` shim in front of `hw-management-ssd-dump.py` —
so the vendor package (`ssd-dump-tools`) does **not** need to be
installed and the test does not depend on which SSD the target
has. The scripts themselves are the real ones.

```bash
# All scenarios
sudo ./tests/hardware/ssd_dump_lock_test.sh

# One scenario, keeping the work dir for inspection
sudo ./tests/hardware/ssd_dump_lock_test.sh -k 5

# List the scenarios
./tests/hardware/ssd_dump_lock_test.sh -l
```

Scenario 0 runs first as an environment check; if a plain collect
cannot complete on this system the run stops there instead of
reporting that same failure in every scenario that follows.

Exit codes: `0` all checks passed, `1` a check failed, `2`
prerequisites not met (not root, no `flock`, scripts not on
`PATH`, no NVMe in `/sys/class/nvme`, or an SSD dump already
running).

The installed scripts have to be as new as the behaviour under
test, which on a target is easy to get wrong: a collector
without the lock, or a helper that still refuses a busy lock
instead of waiting for it, is reported once as a prerequisite
failure naming the file to update. Scenarios 3, 5, 7, 8, 9 and
10 are the ones that need the wait, so selecting only the others
still runs against an older helper.

**This test is destructive.** `/var/log/ssd-dump`,
`/var/log/ssd-dump.tar.gz`, `/tmp/hw-mgmt-dump` and
`/tmp/hw-mgmt-dump.tar.gz` are moved aside on start and restored
on exit, including on Ctrl-C. Do not run it while a dump you care
about is in progress; the script refuses to start in that case
anyway.

To exercise a build tree instead of the installed package, point
`SSD_DUMP_BIN_DIR` at it:

```bash
sudo SSD_DUMP_BIN_DIR=/path/to/hw-mgmt/usr/usr/bin \
	./tests/hardware/ssd_dump_lock_test.sh
```

Other variables: `GENERATE_DUMP_MODE` (argument passed to
generate-dump in scenarios 3 and 6, default `compact`),
`GENERATE_DUMP_WAIT` (seconds scenario 6 waits for generate-dump
to reach its SSD step, default 420), `HOLD_TIMEOUT` (cap on
how long a holder may block, default 600, which is also the
collector's `--timeout` maximum) and `LOCK_WAIT_SEC` (the
`timeout_sec` written into the generated config, which is the
budget the helper waits for a busy lock, default 20; in
production it comes from the real config and is up to 120).

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
sshpass -p '********' ssh <user>@<host> 'echo "Connection successful"'
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
python3 tests/test.py --hardware --host <host> --user root --password ********
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

