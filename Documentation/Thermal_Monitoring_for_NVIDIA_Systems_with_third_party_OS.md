# Thermal Monitoring for NVIDIA Systems with Third Party OS

**Version:** 2.8  
**Last Updated:** September 2024  
**Document Type:** Technical Documentation

---

## Table of Contents

1. [Introduction](#introduction)
2. [Supported Systems](#supported-systems)
3. [Thermal Architecture](#thermal-architecture)
4. [Sensor Types and Calibrations](#sensor-types-and-calibrations)
5. [Thermal Control Service](#thermal-control-service)
6. [Multi-ASIC Systems](#multi-asic-systems)
7. [Configuration Files](#configuration-files)
8. [Troubleshooting](#troubleshooting)
9. [API Reference](#api-reference)
10. [Changelog](#changelog)

---

## Introduction

This document provides comprehensive guidance for thermal monitoring and management on NVIDIA switch systems running third-party operating systems. The thermal management system uses sysfs interfaces to provide real-time monitoring and control of system temperatures, fan speeds, and thermal zones.

### Key Features

- **Real-time thermal monitoring** via sysfs interfaces
- **Automatic fan control** based on temperature thresholds
- **Multi-ASIC system support** with independent thermal zones
- **Configurable thermal policies** for different system types
- **Integration with third-party OS** thermal management tools

### Prerequisites

- Supported NVIDIA switch system
- Compatible kernel version (5.10, 5.14, 6.1, or 6.12)
- hw-management package installed
- Root or appropriate permissions for thermal control

---

## Supported Systems

### Current Generation Systems

| System | Thermal Zones | Sensors | Kernel Support | Notes |
|--------|---------------|---------|----------------|-------|
| **QM3400** | 8 | 24 | 6.1, 6.12 | Blackmamba - ES level |
| **QM3000** | 6 | 18 | 6.1, 6.12 | ES level quality |
| **SN4280** | 6 | 18 | 6.1, 6.12 | SmartSwitch Bobcat - ES level |
| **SN5610** | 12 | 36 | 6.1, 6.12 | Production ready |
| **SN5640** | 10 | 30 | 6.1, 6.12 | Production ready |
| **Q3401-RD** | 4 | 12 | 6.1, 6.12 | Reference design |
| **Q3450** | 6 | 18 | 6.1, 6.12 | Production ready |
| **Q3451** | 6 | 18 | 6.1, 6.12 | Production ready |
| **N61XX_LD** | 8 | 24 | 6.1, 6.12 | Juliet Scaleout PO + TTM |
| **GB300** | 4 | 12 | 6.1, 6.12 | Production ready |
| **XH3000** | 6 | 18 | 6.1, 6.12 | Production ready |

### Legacy Systems

| System | Thermal Zones | Sensors | Kernel Support | Status |
|--------|---------------|---------|----------------|--------|
| MSN2740 | 4 | 12 | 5.10, 5.14, 6.1 | Supported |
| MSN2100 | 3 | 9 | 5.10, 5.14, 6.1 | Supported |
| MSN2410 | 3 | 9 | 5.10, 5.14, 6.1 | Supported |
| MSN2700 | 4 | 12 | 5.10, 5.14, 6.1 | Supported |
| MSN3420 | 6 | 18 | 5.10, 5.14, 6.1 | Supported |
| MSN3700 | 8 | 24 | 5.10, 5.14, 6.1 | Supported |
| MSN3800 | 8 | 24 | 5.10, 5.14, 6.1 | Supported |
| MSN4410 | 10 | 30 | 5.10, 5.14, 6.1 | Supported |
| MSN4700 | 12 | 36 | 5.10, 5.14, 6.1 | Supported |
| MSN4800 | 12 | 36 | 5.10, 5.14, 6.1 | Supported |
| MSN5600 | 12 | 36 | 5.10, 5.14, 6.1 | Supported |

---

## Thermal Architecture

### System Overview

The thermal management system consists of several key components:

```
┌─────────────────────────────────────────────────────────────┐
│                    Thermal Management System                │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Sensors   │    │ Thermal     │    │ Fan Control │     │
│  │             │    │ Control     │    │             │     │
│  │ • Temperature│    │ Service     │    │ • PWM Control│    │
│  │ • Voltage   │    │ (TC v2.5)   │    │ • Speed     │     │
│  │ • Current   │    │             │    │ • Direction │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                   │                   │           │
│         └───────────────────┼───────────────────┘           │
│                             │                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                Sysfs Interface                         │ │
│  │  /var/run/hw-management/                              │ │
│  │  ├── environment/  (temperature sensors)              │ │
│  │  ├── config/       (thermal policies)                 │ │
│  │  └── thermal/      (thermal zones)                    │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Thermal Zones

Each system is divided into thermal zones that group related sensors:

- **ASIC Zone**: CPU and ASIC temperatures
- **Ambient Zone**: Environmental temperatures
- **PSU Zone**: Power supply unit temperatures
- **Fan Zone**: Fan-related sensors
- **Gearbox Zone**: Optical module temperatures

### Sensor Hierarchy

```
Thermal Zone
├── Primary Sensors (Critical)
│   ├── ASIC temperature
│   ├── Ambient temperature
│   └── PSU temperature
├── Secondary Sensors (Warning)
│   ├── Fan speed
│   ├── Voltage levels
│   └── Current levels
└── Tertiary Sensors (Monitoring)
    ├── Gearbox temperature
    ├── Module temperature
    └── Board temperature
```

---

## Sensor Types and Calibrations

### Standard Sensors

| Sensor Type | Purpose | Range | Critical Threshold |
|-------------|---------|-------|-------------------|
| **temp1_input** | ASIC temperature | -40°C to +125°C | 105°C |
| **temp2_input** | Ambient temperature | -40°C to +85°C | 75°C |
| **temp3_input** | PSU temperature | -40°C to +125°C | 100°C |
| **temp4_input** | Gearbox temperature | -40°C to +125°C | 95°C |

### New Sensors (V.7.0030.2000+)

| Sensor Type | Purpose | System Support | Notes |
|-------------|---------|----------------|-------|
| **drivetemp** | SSD temperature | SN5600 | New calibration for SSD monitoring |
| **ibc** | Power convertor | SN5600 | IBC (Intermediate Bus Converter) monitoring |

### Sensor Calibration

Sensors are calibrated using system-specific parameters:

```bash
# Example sensor calibration file
cat /usr/etc/hw-management-sensors/sn5600.conf

# ASIC temperature calibration
temp1_input:
  min: -40
  max: 125
  critical: 105
  hysteresis: 5

# Ambient temperature calibration  
temp2_input:
  min: -40
  max: 85
  critical: 75
  hysteresis: 3
```

---

## Thermal Control Service

### TC v2.5 Features

The Thermal Control service (TC) provides intelligent thermal management:

#### Core Features

- **Automatic fan control** based on temperature thresholds
- **Service reload on crash** scenario
- **Enhanced blacklist functionality** for sensor management
- **Improved PWM calculations** for multi-sensor systems
- **Multi-ASIC support** with independent thermal zones

#### Service Management

```bash
# Check service status
systemctl status hw-management-tc

# Start/stop service
systemctl start hw-management-tc
systemctl stop hw-management-tc

# Restart service
systemctl restart hw-management-tc

# Enable/disable service
systemctl enable hw-management-tc
systemctl disable hw-management-tc
```

#### Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| **thermal.json** | Thermal policies | `/usr/etc/hw-management-thermal/` |
| **sensors.conf** | Sensor calibration | `/usr/etc/hw-management-sensors/` |
| **fast_sysfs_labels.json** | Fast monitoring | `/usr/etc/hw-management-fast-sysfs-monitor/` |

### Thermal Policies

#### Default Policy

```json
{
  "thermal_policy": {
    "fan_min_speed": 25,
    "fan_max_speed": 100,
    "temp_critical": 105,
    "temp_high": 85,
    "temp_low": 45,
    "hysteresis": 5
  }
}
```

#### Custom Policies

Systems can have custom thermal policies based on their specific requirements:

- **High-performance systems**: Lower temperature thresholds
- **Quiet systems**: Higher temperature thresholds with slower fan response
- **Multi-ASIC systems**: Independent policies per ASIC

---

## Multi-ASIC Systems

### Initialization Process

Multi-ASIC systems require special handling for thermal management:

#### Initialization Indicators

- **`asics_init_done`**: Indicates all ASICs are initialized
- **`asic_chipup_completed`**: Counter of completed ASIC initialization

#### Thermal Zone Management

Each ASIC has its own thermal zone with independent control:

```bash
# Check ASIC initialization status
cat /var/run/hw-management/thermal/asics_init_done

# Check ASIC count
cat /var/run/hw-management/thermal/asic_chipup_completed

# List ASIC thermal zones
ls /var/run/hw-management/thermal/asic*
```

### Multi-ASIC Configuration

```json
{
  "multi_asic": {
    "asic_count": 2,
    "independent_zones": true,
    "sync_policy": "independent",
    "failover_mode": "graceful"
  }
}
```

---

## Configuration Files

### Thermal Configuration

#### Main Thermal Config (`thermal.json`)

```json
{
  "system_type": "sn5600",
  "thermal_zones": [
    {
      "name": "asic_zone",
      "sensors": ["temp1_input", "temp2_input"],
      "critical_temp": 105,
      "high_temp": 85,
      "fan_control": true
    },
    {
      "name": "ambient_zone", 
      "sensors": ["temp3_input"],
      "critical_temp": 75,
      "high_temp": 65,
      "fan_control": false
    }
  ],
  "fan_control": {
    "min_speed": 25,
    "max_speed": 100,
    "response_time": 5,
    "hysteresis": 3
  }
}
```

#### Sensor Configuration (`sensors.conf`)

```ini
# SN5600 Sensor Configuration
[temp1_input]
label=ASIC Temperature
min=-40
max=125
critical=105
hysteresis=5

[temp2_input]
label=Ambient Temperature  
min=-40
max=85
critical=75
hysteresis=3

[fan1_input]
label=Fan 1 Speed
min=0
max=15000
critical=5000
hysteresis=1000
```

### Fast Sysfs Monitoring

For high-frequency monitoring, use the fast sysfs monitor:

```json
{
  "fast_monitoring": {
    "enabled": true,
    "interval_ms": 100,
    "sensors": [
      "temp1_input",
      "temp2_input", 
      "fan1_input"
    ]
  }
}
```

---

## Troubleshooting

### Common Issues

#### Thermal Overload

**Symptoms:**
- System shuts down with "Thermal Overload" message
- Fans running at maximum speed
- High temperature readings

**Solutions:**
1. Check sensor readings:
   ```bash
   cat /var/run/hw-management/environment/temp*_input
   ```

2. Verify fan operation:
   ```bash
   cat /var/run/hw-management/environment/fan*_input
   ```

3. Check thermal service:
   ```bash
   systemctl status hw-management-tc
   journalctl -u hw-management-tc
   ```

#### Blacklist Malfunctions

**Symptoms:**
- Sensors showing incorrect readings
- Thermal control not responding
- Service errors in logs

**Solutions:**
1. Check blacklist status:
   ```bash
   cat /var/run/hw-management/config/blacklist
   ```

2. Reset blacklist:
   ```bash
   echo "" > /var/run/hw-management/config/blacklist
   systemctl restart hw-management-tc
   ```

#### PWM Calculation Errors

**Symptoms:**
- Fans not responding to temperature changes
- Incorrect fan speed calculations
- Service errors

**Solutions:**
1. Check PWM configuration:
   ```bash
   cat /var/run/hw-management/config/fan*_pwm
   ```

2. Verify sensor count:
   ```bash
   ls /var/run/hw-management/environment/temp*_input | wc -l
   ```

### Debug Commands

```bash
# Check all thermal sensors
for sensor in /var/run/hw-management/environment/temp*_input; do
  echo "$(basename $sensor): $(cat $sensor)"
done

# Check fan status
for fan in /var/run/hw-management/environment/fan*_input; do
  echo "$(basename $fan): $(cat $fan) RPM"
done

# Check thermal zones
ls -la /var/run/hw-management/thermal/

# Check service logs
journalctl -u hw-management-tc --since "1 hour ago"
```

---

## API Reference

### Sysfs Attributes

#### Temperature Sensors

| Attribute | Purpose | Example | Notes |
|-----------|---------|---------|-------|
| `/environment/temp1_input` | ASIC temperature | 45°C | Primary sensor |
| `/environment/temp2_input` | Ambient temperature | 35°C | Environmental |
| `/environment/temp3_input` | PSU temperature | 50°C | Power supply |
| `/environment/temp4_input` | Gearbox temperature | 40°C | Optical modules |

#### Fan Control

| Attribute | Purpose | Example | Notes |
|-----------|---------|---------|-------|
| `/environment/fan1_input` | Fan 1 speed | 3000 RPM | Primary fan |
| `/environment/fan2_input` | Fan 2 speed | 3000 RPM | Secondary fan |
| `/config/fan_min` | Minimum fan speed | 25% | Configuration |
| `/config/fan_max` | Maximum fan speed | 100% | Configuration |
| `/thermal/fan1_dir` | Fan 1 direction | 1 | 1=forward, 0=reverse |

#### Thermal Zones

| Attribute | Purpose | Example | Notes |
|-----------|---------|---------|-------|
| `/thermal/thermal_zone1` | Zone 1 status | active | ASIC zone |
| `/thermal/thermal_zone2` | Zone 2 status | active | Ambient zone |
| `/thermal/asics_init_done` | ASIC initialization | 1 | Multi-ASIC systems |
| `/thermal/asic_chipup_completed` | ASIC count | 2 | Multi-ASIC systems |

#### Configuration

| Attribute | Purpose | Example | Notes |
|-----------|---------|---------|-------|
| `/config/temp_critical` | Critical temperature | 105°C | System threshold |
| `/config/temp_high` | High temperature | 85°C | Warning threshold |
| `/config/temp_low` | Low temperature | 45°C | Normal threshold |
| `/config/blacklist` | Blacklisted sensors | temp4_input | Excluded sensors |

### Programming Interface

#### C API Example

```c
#include <stdio.h>
#include <stdlib.h>

int read_temperature(const char* sensor_path) {
    FILE *fp = fopen(sensor_path, "r");
    if (fp == NULL) {
        return -1;
    }
    
    int temp;
    fscanf(fp, "%d", &temp);
    fclose(fp);
    
    return temp;
}

int main() {
    int asic_temp = read_temperature("/var/run/hw-management/environment/temp1_input");
    printf("ASIC Temperature: %d°C\n", asic_temp);
    return 0;
}
```

#### Python API Example

```python
import os

def read_temperature(sensor_path):
    """Read temperature from sysfs sensor"""
    try:
        with open(sensor_path, 'r') as f:
            return int(f.read().strip())
    except (IOError, ValueError):
        return None

def get_thermal_status():
    """Get complete thermal status"""
    status = {}
    
    # Read temperatures
    for i in range(1, 5):
        sensor = f"/var/run/hw-management/environment/temp{i}_input"
        temp = read_temperature(sensor)
        if temp is not None:
            status[f"temp{i}"] = temp
    
    # Read fan speeds
    for i in range(1, 5):
        fan = f"/var/run/hw-management/environment/fan{i}_input"
        speed = read_temperature(fan)
        if speed is not None:
            status[f"fan{i}"] = speed
    
    return status

if __name__ == "__main__":
    status = get_thermal_status()
    for sensor, value in status.items():
        print(f"{sensor}: {value}")
```

---

## Changelog

### Version 2.8 (September 2024)

#### New Features
- **New system support**: QM3400, QM3000, SN4280, SN5610, SN5640, Q3401-RD, Q3450, Q3451, N61XX_LD, GB300, XH3000
- **Kernel 6.12.38 support** added
- **New sensor types**: drivetemp (SSD), ibc (power convertor) for SN5600
- **Enhanced multi-ASIC support** with `asics_init_done` and `asic_chipup_completed` indicators

#### Improvements
- **TC service reload** on crash scenario
- **Enhanced blacklist functionality** for better sensor management
- **Improved PWM calculations** for systems with varying ambient sensor counts
- **Better thermal zone detection** moved to kernel driver

#### Bug Fixes
- **Thermal overload fixes** for SN4700 systems
- **Blacklist malfunction fixes** in thermal algorithm
- **PWM minimum speed adjustments** (20%→25% for SN3420)
- **Multi-ASIC thermal management** improvements

### Version 2.7 (June 2024)

#### New Features
- **QM3400 Blackmamba** support (ES level)
- **SN4280 SmartSwitch Bobcat** support (ES level)
- **N5110_LD Juliet Scaleout** support (ES level)
- **VPD parser** support for System VPD vendor specific SSD SED PSID block

#### Bug Fixes
- **SN4700 thermal overload** fixes
- **Thermal control blacklist** malfunction fixes
- **SN3420 PWM minimum speed** increase (20%→25%)
- **Multi-ASIC PWM calculation** fixes

### Version 2.6 (September 2023)

#### New Features
- **BF3 ARM COMex carrier** support over MQM9700 and SN4700
- **Kernel 6.1.38** support
- **TC service reload** on crash scenario
- **New sensor calibrations**: drivetemp (SSD), ibc (power convertor) for SN5600
- **Multi-ASIC init done indication** with `asics_init_done` and `asic_chipup_completed`

#### Improvements
- **Enhanced deployment tool** with CPU architecture-specific Kconfig flags
- **Improved thermal zone detection** in kernel driver
- **Better sensor calibration** management

---

## Support and Resources

### Documentation
- [Chassis Management for NVIDIA Switch Systems](Chassis_Management_for_NVIDIA_Switch_Systems_with_Sysfs_rev.2.8.pdf)
- [README.md](../README.md) - Package overview and installation
- [Release Notes](../debian/Release.txt) - Detailed changelog

### Contact Information
- **Technical Support**: [NVIDIA Support Portal](https://support.nvidia.com)
- **Documentation**: [NVIDIA Documentation](https://docs.nvidia.com)
- **Community**: [NVIDIA Developer Forums](https://forums.developer.nvidia.com)

### License
This documentation is provided under the GNU General Public License Version 2.

---

*© 2024 NVIDIA Corporation. All rights reserved. NVIDIA, the NVIDIA logo, and other NVIDIA marks are trademarks and/or registered trademarks of NVIDIA Corporation in the United States and other countries.*
