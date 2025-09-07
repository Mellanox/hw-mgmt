# Fan Direction File Creation Fix - Test Suite

This test suite validates the fix for the `FileNotFoundError` bug where the thermal control daemon (`pmon#thermalctld`) fails to read `/var/run/hw-management/thermal/fan<X>_dir` files.

## Bug Description

**Error**: `FileNotFoundError(2, 'No such file or directory')` when reading fan direction files
**Root Cause**: Fan direction files are not created during initialization for existing fans
**Impact**: Thermal control daemon fails to start properly, causing system instability

## Fix Overview

The fix consists of two parts:

1. **Hotplug Event Fix** (`hw-management-thermal-events.sh`):
   - Added `source hw-management-chassis-events.sh` to make `set_fan_direction` available
   - Added `set_fan_direction fan"$i" 1` call during fan hotplug events

2. **Initialization Fix** (`hw-management-start-post.sh`):
   - Added fan direction file creation for existing fans during startup
   - Loops through all existing fans and creates direction files if they're present

## Test Files

### `test_fan_direction_fix.py`
Python unit tests that test individual components in isolation:
- Hotplug event handling
- Initialization handling  
- Edge cases (missing files, zero fans, etc.)
- Error handling

### `test_fan_direction_fix.sh`
Shell integration tests that simulate the actual environment:
- Complete hotplug event simulation
- Complete initialization simulation
- Integration test reproducing the exact bug scenario
- Edge case testing

## Running the Tests

### Python Tests
```bash
cd unittest/fan_direction_fix
python3 test_fan_direction_fix.py
```

### Shell Tests
```bash
cd unittest/fan_direction_fix
chmod +x test_fan_direction_fix.sh
./test_fan_direction_fix.sh
```

## Test Scenarios

### 1. Hotplug Event Simulation
- Creates mock sysfs fan files
- Simulates thermal events script processing
- Verifies fan direction files are created
- Tests the fix in `hw-management-thermal-events.sh`

### 2. Initialization Simulation  
- Creates existing fan status files
- Simulates start-post script processing
- Verifies fan direction files are created
- Tests the fix in `hw-management-start-post.sh`

### 3. Edge Cases
- **Missing fan status files**: Only some fans present
- **Zero fans**: System with no fans
- **Missing chassis events script**: Graceful degradation
- **Permission issues**: File creation failures

### 4. Integration Test
- Reproduces the exact scenario from engineer's logs
- Simulates system boot with existing fans
- Verifies thermal control daemon can read files after fix
- Tests end-to-end functionality

## Expected Results

All tests should pass, demonstrating that:
- Fan direction files are created during hotplug events
- Fan direction files are created during initialization for existing fans
- The fix handles edge cases gracefully
- The thermal control daemon can successfully read fan direction files
- The FileNotFoundError is eliminated

## Test Environment

The tests create a temporary directory structure that mimics the real hw-management setup:
```
/tmp/fan_dir_test_*/
├── config/
│   └── max_tachos
├── thermal/
│   ├── fan1_status
│   ├── fan1_dir (created by fix)
│   └── ...
├── events/
├── system/
│   ├── board_type
│   └── sku
└── sysfs/
    └── fan1, fan2, ...
```

## Validation

The tests validate:
- ✅ File creation: `fanX_dir` files are created
- ✅ File content: Files contain correct values
- ✅ File permissions: Files are readable
- ✅ Error handling: Graceful degradation on failures
- ✅ Edge cases: Zero fans, missing files, etc.
- ✅ Integration: End-to-end functionality

## Bug Reference

This fix addresses the FileNotFoundError reported in:
- Test case: `test_fwutil_install_url[BIOS-...]`
- System: ACS-SN5600 (r-moose-02)
- Error: `Failed to read from file /var/run/hw-management/thermal/fan<X>_dir`
- Timeline: 34-second gap between hw-management init and first error
