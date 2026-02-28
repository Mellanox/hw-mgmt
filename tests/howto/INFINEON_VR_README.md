# Infineon XDPE1x2xx Voltage Regulator Flash Tools

This directory contains tools for programming and managing Infineon XDPE1x2xx series voltage regulators via I2C/PMBus interface.

## Overview

The tools are based on Infineon's AN001-XDPE1x2xx Programming Guide and provide:
- Configuration flashing to OTP (One-Time Programmable) memory
- Device discovery and identification
- Register monitoring and diagnostics
- Configuration file analysis

## Files

- `flash-infineon-xdpe.sh` - Main flashing tool
- `infineon-vr-tools.sh` - Utility tools for diagnostics and monitoring
- `AN001-XDPE1x2xx_programming Guide 1.pdf` - Reference documentation

## Prerequisites

### Required Packages

```bash
# Debian/Ubuntu
sudo apt-get install i2c-tools

# RHEL/CentOS
sudo yum install i2c-tools
```

### Kernel Modules

Ensure I2C dev interface is loaded:
```bash
sudo modprobe i2c-dev
```

### Permissions

Add your user to the i2c group or run with sudo:
```bash
sudo usermod -a -G i2c $USER
```

## Quick Start

### 1. Scan for Devices

```bash
# Scan I2C bus 2 for Infineon devices
./infineon-vr-tools.sh scan 2
```

### 2. Check Device Info

```bash
# Read device information from address 0x40 on bus 2
./infineon-vr-tools.sh info 2 0x40
```

### 3. Analyze Configuration File

```bash
# Parse configuration file before flashing
./infineon-vr-tools.sh parse vr_config.bin
```

### 4. Flash Device (Dry Run First!)

```bash
# Dry run to verify commands
./flash-infineon-xdpe.sh -b 2 -a 0x40 -f vr_config.bin -n -d

# Actual flash (WARNING: This writes to OTP!)
./flash-infineon-xdpe.sh -b 2 -a 0x40 -f vr_config.bin
```

## Detailed Usage

### Flash Tool (`flash-infineon-xdpe.sh`)

#### Syntax
```bash
./flash-infineon-xdpe.sh -b <bus> -a <address> -f <config_file> [options]
```

#### Required Parameters
- `-b <bus>` - I2C bus number (e.g., 0, 1, 2)
- `-a <addr>` - Device I2C address in hex (e.g., 0x40)
- `-f <file>` - Configuration file path

#### Optional Parameters
- `-v` - Verify only (don't program)
- `-n` - Dry run (show commands without executing)
- `-t <sec>` - Timeout for operations (default: 30 seconds)
- `-d` - Debug mode (verbose output)
- `-h` - Show help

#### Examples

**Dry run with debug output:**
```bash
./flash-infineon-xdpe.sh -b 2 -a 0x40 -f config.bin -n -d
```

**Verify existing configuration:**
```bash
./flash-infineon-xdpe.sh -b 2 -a 0x40 -f config.bin -v
```

**Flash with extended timeout:**
```bash
./flash-infineon-xdpe.sh -b 2 -a 0x40 -f config.bin -t 60
```

### Utility Tools (`infineon-vr-tools.sh`)

#### Parse Configuration File
Analyze configuration file structure and checksums:
```bash
./infineon-vr-tools.sh parse vr_config.bin
```

#### Scan I2C Bus
Find all Infineon devices on a bus:
```bash
./infineon-vr-tools.sh scan 2
```

#### Read Device Information
Display device ID and PMBus registers:
```bash
./infineon-vr-tools.sh info 2 0x40
```

#### Monitor Telemetry
Real-time monitoring of voltage, current, temperature:
```bash
# Update every 1 second (default)
./infineon-vr-tools.sh monitor 2 0x40

# Update every 2 seconds
./infineon-vr-tools.sh monitor 2 0x40 2
```

#### Dump Registers
Save all readable registers to file:
```bash
# Display to console
./infineon-vr-tools.sh dump 2 0x40

# Save to file
./infineon-vr-tools.sh dump 2 0x40 register_dump.txt
```

#### Compare Configuration Files
Compare two configuration files:
```bash
./infineon-vr-tools.sh compare config_old.bin config_new.bin
```

## Programming Flow

The flash tool follows this sequence:

1. **Device Detection** - Verify device presence on I2C bus
2. **Device Identification** - Read manufacturer ID, model, revision
3. **Clear Faults** - Clear any existing fault conditions
4. **Disable Write Protection** - Allow OTP programming
5. **Check OTP Space** - Verify sufficient OTP space available
6. **Invalidate Existing OTP** - Erase current configuration (requires user confirmation)
7. **Write to Scratchpad** - Transfer configuration to scratchpad memory
8. **Upload to OTP** - Commit scratchpad data to OTP (irreversible!)
9. **Verification** - Read back and verify programmed data
10. **Enable Write Protection** - Re-enable write protection
11. **Reset Device** - Reset to load new configuration

## Important Notes

### ⚠️ WARNING: OTP Memory

**One-Time Programmable (OTP) memory can only be written ONCE!**

- Once programmed, OTP cannot be erased or modified
- Limited number of programming cycles available
- Always verify configuration file before flashing
- Use dry-run mode (`-n`) first to test the process
- Keep backup of working configurations

### Best Practices

1. **Always dry-run first:**
   ```bash
   ./flash-infineon-xdpe.sh -b 2 -a 0x40 -f config.bin -n -d
   ```

2. **Verify configuration file:**
   ```bash
   ./infineon-vr-tools.sh parse config.bin
   ```

3. **Check device info before flashing:**
   ```bash
   ./infineon-vr-tools.sh info 2 0x40
   ```

4. **Monitor device after flashing:**
   ```bash
   ./infineon-vr-tools.sh monitor 2 0x40
   ```

5. **Save register dumps before/after:**
   ```bash
   ./infineon-vr-tools.sh dump 2 0x40 before.txt
   # ...flash...
   ./infineon-vr-tools.sh dump 2 0x40 after.txt
   ```

### Common I2C Addresses

Infineon XDPE devices typically use:
- **0x40-0x4F** - Primary address range
- **0x10-0x1F** - Alternative range (device dependent)

Check your hardware schematic for exact address.

### Troubleshooting

#### Device Not Detected
```bash
# Check if I2C bus exists
ls /dev/i2c-*

# Scan entire bus
i2cdetect -y 2

# Check kernel messages
dmesg | grep i2c
```

#### Permission Denied
```bash
# Run with sudo
sudo ./flash-infineon-xdpe.sh -b 2 -a 0x40 -f config.bin

# Or add user to i2c group
sudo usermod -a -G i2c $USER
# Log out and back in
```

#### Timeout During Upload
```bash
# Increase timeout to 60 seconds
./flash-infineon-xdpe.sh -b 2 -a 0x40 -f config.bin -t 60
```

#### OTP Space Full
```bash
# Check OTP space usage
./infineon-vr-tools.sh info 2 0x40

# Device may need replacement if OTP is exhausted
```

## PMBus Register Reference

### Standard PMBus Commands
| Register | Name | Description |
|----------|------|-------------|
| 0x00 | PAGE | Page selection |
| 0x01 | OPERATION | Unit on/off control |
| 0x03 | CLEAR_FAULTS | Clear fault conditions |
| 0x10 | WRITE_PROTECT | Write protection control |
| 0x78 | STATUS_BYTE | Status summary |
| 0x79 | STATUS_WORD | Detailed status |
| 0x8B | READ_VOUT | Output voltage |
| 0x8C | READ_IOUT | Output current |
| 0x8D | READ_TEMPERATURE_1 | Temperature sensor 1 |
| 0x96 | READ_POUT | Output power |

### Manufacturer Specific Commands
| Register | Name | Description |
|----------|------|-------------|
| 0x99 | MFR_ID | Manufacturer ID |
| 0x9A | MFR_MODEL | Device model |
| 0x9B | MFR_REVISION | Firmware revision |
| 0xAD | MFR_DEVICE_ID | Unique device ID |
| 0xD0 | MFR_SPECIFIC_00 | Scratchpad access |
| 0xFE | MFR_FW_COMMAND | Firmware commands |

## Configuration File Format

Configuration files for XDPE devices contain:

1. **File Header** - Creation info, metadata
2. **Device Information** - Model, variant, rail count
3. **Rail Information** - Per-rail configuration
4. **Configuration Sections** - Register values and settings
5. **Checksums** - CRC32 for validation

See `AN001-XDPE1x2xx_programming Guide 1.pdf` Chapter 4 for detailed format specification.

## Safety Considerations

1. **Power Supply Stability** - Ensure stable power during programming
2. **I2C Bus Integrity** - Verify clean I2C signals, no errors
3. **Configuration Validation** - Always validate config before flashing
4. **Backup Configs** - Keep known-good configurations backed up
5. **Test Environment** - Test on non-production hardware first

## Support and References

- **Programming Guide**: `AN001-XDPE1x2xx_programming Guide 1.pdf`
- **PMBus Specification**: [PMBus.org](https://pmbus.org)
- **Infineon Product Page**: [Infineon XDPE Series](https://www.infineon.com)

## License

These tools are provided as-is for use with Infineon XDPE devices.
See project LICENSE file for details.

## Changelog

### Version 1.0 (2026-01-20)
- Initial release
- Basic flash functionality
- Utility tools for diagnostics
- Dry-run and verification modes
