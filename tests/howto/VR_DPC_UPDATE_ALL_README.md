# Voltage Regulator DPC Batch Update Tool

## Overview

The `hw-management-vr-dpc-update-all.sh` script provides batch updating for voltage regulator (VR) devices from a JSON configuration file. It supports both **MPS** and **Infineon** voltage regulators with automatic vendor detection.

## Supported Devices

### MPS Devices
- **Device Type Prefix**: `mp*` (e.g., mp2975, mp2971, mp2891)
- **Update Script**: `hw-management-vr-dpc-update.sh`
- **Required Fields**:
  - `DeviceType` - Device model (e.g., "mp2975")
  - `Bus` - I2C bus number
  - `ConfigFile` - Path to CSV configuration file
  - `CrcFile` - Path to CRC file
  - `DeviceConfigFile` - Path to device configuration file

### Infineon Devices
- **Device Type Prefix**: `xdpe*` (e.g., xdpe12284, xdpe132g5c)
- **Update Script**: `hw-management-vr-dpc-infineon-update.sh`
- **Required Fields**:
  - `DeviceType` - Device model (e.g., "xdpe12284")
  - `Bus` - I2C bus number
  - `Addr` - I2C device address (e.g., "0x40")
  - `ConfigFile` - Path to binary configuration file

## Usage

### Basic Syntax
```bash
hw-management-vr-dpc-update-all.sh <json_config_file>
```

### Validation Mode
```bash
hw-management-vr-dpc-update-all.sh --validate-json <json_config_file>
```

### Display Help
```bash
hw-management-vr-dpc-update-all.sh --help
```

## JSON Configuration Format

### Complete Example
```json
{
  "System HID": "HI180",
  "Devices": [
    {
      "DeviceType": "mp2975",
      "Bus": 12,
      "ConfigFile": "/var/run/hw-management/config/mp2975_config.csv",
      "CrcFile": "/var/run/hw-management/config/mp2975_crc.txt",
      "DeviceConfigFile": "/var/run/hw-management/config/mp2975_device.conf"
    },
    {
      "DeviceType": "xdpe12284",
      "Bus": 2,
      "Addr": "0x40",
      "ConfigFile": "/var/run/hw-management/config/xdpe12284_config.bin"
    },
    {
      "DeviceType": "xdpe132g5c",
      "Bus": 3,
      "Addr": "0x44",
      "ConfigFile": "/var/run/hw-management/config/xdpe132g5c_config.bin"
    }
  ]
}
```

### Field Descriptions

#### System-Level Fields
- **System HID** (required): System hardware identifier (format: HI### or hi###)

#### Device-Level Fields (Common)
- **DeviceType** (required): Device model identifier
- **Bus** (required): I2C bus number (integer)
- **ConfigFile** (required): Full path to configuration file

#### MPS-Specific Fields
- **CrcFile** (required for MPS): Full path to CRC file
- **DeviceConfigFile** (required for MPS): Full path to device configuration file

#### Infineon-Specific Fields
- **Addr** (required for Infineon): I2C device address (hex format: "0x40")

## Vendor Detection Logic

The script automatically detects the device vendor based on the `DeviceType` prefix:

- **MPS**: DeviceType starts with `mp` → uses `hw-management-vr-dpc-update.sh`
- **Infineon**: DeviceType starts with `xdpe` → uses `hw-management-vr-dpc-infineon-update.sh`

## Examples

### Example 1: Validate Configuration
```bash
hw-management-vr-dpc-update-all.sh --validate-json /etc/vr_config.json
```

Output:
```
Validating JSON configuration: /etc/vr_config.json
==========================================
Checking JSON syntax... OK
Checking System HID... OK (System HID: HI180)
Checking Devices array... OK (3 device(s) found)

Validating devices:
-------------------
Device 1:
  DeviceType: mp2975
  Vendor: MPS
  Bus: 12
  ConfigFile: /var/run/hw-management/config/mp2975_config.csv
  CrcFile: /var/run/hw-management/config/mp2975_crc.txt
  DeviceConfigFile: /var/run/hw-management/config/mp2975_device.conf

Device 2:
  DeviceType: xdpe12284
  Vendor: Infineon
  Bus: 2
  Addr: 0x40
  ConfigFile: /var/run/hw-management/config/xdpe12284_config.bin

Device 3:
  DeviceType: xdpe132g5c
  Vendor: Infineon
  Bus: 3
  Addr: 0x44
  ConfigFile: /var/run/hw-management/config/xdpe132g5c_config.bin

==========================================
Validation: PASSED
JSON configuration is valid and ready to use.
```

### Example 2: Perform Batch Update
```bash
hw-management-vr-dpc-update-all.sh /etc/vr_config.json
```

Output:
```
[info] Voltage Regulator DPC Batch Update Started
[info] Processing JSON configuration: /etc/vr_config.json
[info] Processing System HID: HI180 with 3 device(s)
[info] Device 1: Type=mp2975, Bus=12
[info] Detected MPS device: mp2975
[info] Executing: /usr/bin/hw-management-vr-dpc-update.sh 12 mp2975 hi180 ...
[info] Successfully updated device: mp2975 on bus 12
[info] Device 2: Type=xdpe12284, Bus=2
[info] Detected Infineon device: xdpe12284
[info] Infineon device at address 0x40
[info] Executing: /usr/bin/hw-management-vr-dpc-infineon-update.sh flash -b 2 -a 0x40 -f ...
[info] Successfully updated device: xdpe12284 on bus 2
[info] Device 3: Type=xdpe132g5c, Bus=3
[info] Detected Infineon device: xdpe132g5c
[info] Infineon device at address 0x44
[info] Executing: /usr/bin/hw-management-vr-dpc-infineon-update.sh flash -b 3 -a 0x44 -f ...
[info] Successfully updated device: xdpe132g5c on bus 3
[info] ======================================
[info] Batch Update Summary:
[info]   System HID:        HI180
[info]   Total Devices:     3
[info]   Successful:        3
[info]   Failed:            0
[info] ======================================
[info] Voltage Regulator DPC Batch Update Completed Successfully
```

## Error Handling

### Missing Required Fields

**For MPS devices:**
```json
{
  "DeviceType": "mp2975",
  "Bus": 12,
  "ConfigFile": "/path/to/config.csv"
  // Missing: CrcFile and DeviceConfigFile
}
```
Error: "Missing CrcFile (required for MPS devices)"

**For Infineon devices:**
```json
{
  "DeviceType": "xdpe12284",
  "Bus": 2,
  "ConfigFile": "/path/to/config.bin"
  // Missing: Addr
}
```
Error: "Missing 'Addr' (required for Infineon devices)"

### Invalid Device Type Prefix
```json
{
  "DeviceType": "unknown123",
  "Bus": 2,
  ...
}
```
Warning: "Unknown device type prefix (expected 'mp' or 'xdpe')"

### Missing Configuration Files
If any specified configuration file doesn't exist:
```
[WARNING] File does not exist
```

## Dependencies

### Required Commands
- `jq` - JSON parser (for parsing configuration file)
- `hw-management-vr-dpc-update.sh` - MPS VR update script
- `hw-management-vr-dpc-infineon-update.sh` - Infineon VR update script

### Installation
```bash
# Install jq
apt-get install jq  # Debian/Ubuntu
yum install jq      # RHEL/CentOS

# Verify scripts are executable
chmod +x /usr/bin/hw-management-vr-dpc-update.sh
chmod +x /usr/bin/hw-management-vr-dpc-infineon-update.sh
```

## Logging

All operations are logged to syslog with tag `vr_dpc_update_all`:

```bash
# View logs
journalctl -t vr_dpc_update_all

# Follow logs in real-time
journalctl -t vr_dpc_update_all -f
```

## Best Practices

1. **Always validate first:**
   ```bash
   hw-management-vr-dpc-update-all.sh --validate-json config.json
   ```

2. **Test individual devices:**
   Before batch update, test each device individually:
   ```bash
   # MPS device
   hw-management-vr-dpc-update.sh 12 mp2975 hi180 config.csv crc.txt device.conf

   # Infineon device
   hw-management-vr-dpc-infineon-update.sh flash -b 2 -a 0x40 -f config.bin
   ```

3. **Backup configurations:**
   Keep backup copies of all configuration files before updates.

4. **Check logs:**
   Review logs after batch update to verify all devices updated successfully.

5. **Dry-run for Infineon:**
   For Infineon devices, you can test without programming:
   ```bash
   hw-management-vr-dpc-infineon-update.sh flash -b 2 -a 0x40 -f config.bin -n
   ```

## Troubleshooting

### Device Not Detected
```
[ERROR] Device not detected at address 0x40 on bus 2
```
**Solution:** Verify I2C bus and address with:
```bash
i2cdetect -y 2
hw-management-vr-dpc-infineon-update.sh scan -b 2
```

### Script Not Found
```
[ERROR] Infineon DPC update script not found or not executable
```
**Solution:** Verify script installation:
```bash
ls -l /usr/bin/hw-management-vr-dpc-infineon-update.sh
chmod +x /usr/bin/hw-management-vr-dpc-infineon-update.sh
```

### JSON Syntax Error
```
[ERROR] Invalid JSON syntax in file
```
**Solution:** Validate JSON syntax:
```bash
jq empty config.json
```

### Permission Denied
```
[ERROR] Failed to write to device
```
**Solution:** Run with elevated privileges:
```bash
sudo hw-management-vr-dpc-update-all.sh config.json
```

## Migration from Old Format

### Old Format (MPS only)
```json
{
  "System HID": "HI180",
  "Devices": [
    {
      "DeviceType": "mp2975",
      "Bus": 12,
      "ConfigFile": "/path/to/config.csv",
      "CrcFile": "/path/to/crc.txt",
      "DeviceConfigFile": "/path/to/device.conf"
    }
  ]
}
```
**Status:** ✅ Still fully supported (no changes needed)

### New Format (with Infineon support)
```json
{
  "System HID": "HI180",
  "Devices": [
    {
      "DeviceType": "mp2975",
      "Bus": 12,
      "ConfigFile": "/path/to/config.csv",
      "CrcFile": "/path/to/crc.txt",
      "DeviceConfigFile": "/path/to/device.conf"
    },
    {
      "DeviceType": "xdpe12284",
      "Bus": 2,
      "Addr": "0x40",
      "ConfigFile": "/path/to/config.bin"
    }
  ]
}
```
**Status:** ✅ Backward compatible - existing MPS configurations work unchanged

## Version History

### Version 2.0 (2026-01-20)
- Added support for Infineon XDPE devices
- Automatic vendor detection based on DeviceType prefix
- Optional `Addr` field for Infineon devices
- Enhanced validation for both MPS and Infineon devices
- Backward compatible with existing MPS-only configurations

### Version 1.0
- Initial release
- MPS device support only

## See Also

- `hw-management-vr-dpc-update.sh` - MPS VR update tool
- `hw-management-vr-dpc-infineon-update.sh` - Infineon VR update tool
- `INFINEON_VR_README.md` - Infineon VR tool documentation
