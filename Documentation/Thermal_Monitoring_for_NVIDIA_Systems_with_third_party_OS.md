# Thermal Monitoring for NVIDIA Systems with Third Party OS

**Version:** 2.8  
**Last Updated:** September 2025  
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

| System | Thermal Zones | Sensors | Kernel Support | TC Version | Notes |
|--------|---------------|---------|----------------|------------|-------|
| **SN5610** | 12 | 36 | 6.1, 6.12 | **TC v2.5** | Production ready |
| **SN5640** | 10 | 30 | 6.1, 6.12 | **TC v2.5** | Production ready |
| **Q3401-RD** | 4 | 12 | 6.1, 6.12 | **TC v2.5** | Reference design |
| **QM3400** | 8 | 24 | 6.1, 6.12 | TC v2.0 | ES level |
| **QM3000** | 6 | 18 | 6.1, 6.12 | TC v2.0 | ES level |
| **SN4280** | 6 | 18 | 6.1, 6.12 | TC v2.0 | ES level |
| **Q3450** | 6 | 18 | 6.1, 6.12 | TC v2.0 | Production ready |
| **Q3451** | 6 | 18 | 6.1, 6.12 | TC v2.0 | Production ready |
| **N61XX_LD** | 8 | 24 | 6.1, 6.12 | TC v2.0 | Production ready |
| **N5500LD** | 4 | 12 | 6.1, 6.12 | TC v2.0 | Production ready |
| **XH3000** | 6 | 18 | 6.1, 6.12 | TC v2.0 | Production ready |

### Legacy Systems

| System | Thermal Zones | Sensors | Kernel Support | TC Version | Status |
|--------|---------------|---------|----------------|------------|--------|
| MSN2740 | 4 | 12 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN2100 | 3 | 9 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN2410 | 3 | 9 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN2700 | 4 | 12 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN3420 | 6 | 18 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN3700 | 8 | 24 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN3800 | 8 | 24 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN4410 | 10 | 30 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN4700 | 12 | 36 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN4800 | 12 | 36 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |
| MSN5600 | 12 | 36 | 5.10, 5.14, 6.1 | TC v2.0 | Supported |

---

## Thermal Architecture

### System Overview

The thermal management system consists of two main architectural layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    Data Collection Layer                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │            hw-management-sync Service                   │ │
│  │              (Data Collector)                          │ │
│  │  • Fan status monitoring                              │ │
│  │  • ASIC temperature collection                        │ │
│  │  • Module temperature monitoring                      │ │
│  │  • Power event detection                              │ │
│  │  • Leakage sensor monitoring                          │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Thermal Control Layer                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │        hw-management-thermal-control Service            │ │
│  │              (Core Engine)                             │ │
│  │  • PWM calculation algorithms                         │ │
│  │  • Multi-sensor fusion                                │ │
│  │  • Fan speed control                                  │ │
│  │  • Thermal policy enforcement                         │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                Hardware Control Interface                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                Sysfs Interface                         │ │
│  │  /var/run/hw-management/                              │ │
│  │  ├── environment/  (temperature sensors)              │ │
│  │  ├── config/       (thermal policies)                 │ │
│  │  └── thermal/      (thermal zones)                    │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### **Architectural Roles**

#### **Data Collection Layer (Sync Service)**
- **Role**: Data Collector
- **Purpose**: Gathers raw hardware data from various sources
- **Function**: Monitors sensors, detects changes, triggers events
- **Output**: Provides clean, processed data to thermal control

#### **Thermal Control Layer (Core Engine)**
- **Role**: Core Decision Engine
- **Purpose**: Makes intelligent decisions based on collected data
- **Function**: Calculates PWM, manages fan speeds, enforces policies
- **Input**: Uses data from sync service to make thermal decisions

### Thermal Control Algorithm

The thermal control system uses a sophisticated multi-sensor algorithm:

#### **Core Algorithm Components**

1. **Sensor Data Collection**
   - Polls temperature sensors at configurable intervals (3-60 seconds)
   - Applies smoothing filters to reduce noise
   - Implements hysteresis to prevent oscillation

2. **PWM Calculation**
   - **Basic Formula**: `PWM = pwm_min + ((temp - temp_min)/(temp_max - temp_min)) * (pwm_max - pwm_min)`
   - **Dynamic Adjustment**: TC v2.5 systems use adaptive PWM limits
   - **Integral Control**: Smooth transitions with I-term for stability

3. **Multi-Sensor Fusion**
   - Each sensor calculates its required PWM
   - System selects the **maximum PWM** from all sensors
   - Prevents thermal runaway by ensuring adequate cooling

#### **Algorithm Flow**

```
Sensor Reading → Smoothing Filter → Hysteresis Check → PWM Calculation
     ↓                    ↓                ↓                    ↓
Temperature → Moving Average → Trend Analysis → Linear Interpolation
     ↓                    ↓                ↓                    ↓
Value Update → Noise Reduction → Oscillation Prevention → Fan Speed
```

#### **Dynamic PWM Control (TC v2.5)**

For systems with TC v2.5, the algorithm includes advanced features:

- **Adaptive PWM Limits**: Dynamically adjusts maximum PWM based on temperature trends
- **Integral Term (I-term)**: Prevents temperature overshoot and undershoot
- **Threshold-based Control**: Different behavior for temperature increases vs decreases

```
Temperature Control Logic:
├── Above Upper Threshold → Increase PWM (with I-term)
├── Below Lower Threshold → Decrease PWM (with I-term)  
└── Within Range → Maintain Current PWM
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

### Thermal Control Versions

The hw-management package supports two versions of thermal control:

#### **TC v2.5 (New Generation)**
**Only 3 systems currently use TC v2.5:**
- **SN5610**
- **SN5640**  
- **Q3401-RD**

**Key Features:**
- Enhanced blacklist functionality
- Improved PWM calculations for multi-sensor systems
- Service reload on crash scenario
- Better multi-ASIC support
- Advanced thermal zone management

#### **TC v2.0 (Legacy)**
**All other systems use TC v2.0:**
- All MSN series (MSN2700, MSN3700, MSN4700, etc.)
- All MQM series (MQM8700, MQM9700, etc.)
- All other current and legacy systems

**Features:**
- Standard thermal control
- Basic fan management
- Traditional sensor monitoring

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

### Thermal Algorithm Parameters

#### **Core Parameters**

| Parameter | Description | Range | Default |
|-----------|-------------|-------|---------|
| **pwm_min** | Minimum fan speed (%) | 0-100 | 30 |
| **pwm_max** | Maximum fan speed (%) | 0-100 | 100 |
| **val_min** | Minimum temperature (°C) | -40 to 125 | 70°C |
| **val_max** | Maximum temperature (°C) | -40 to 125 | 105°C |
| **poll_time** | Sensor polling interval (seconds) | 1-60 | 3 |
| **input_smooth_level** | Smoothing filter level | 1-10 | 3 |
| **value_hyst** | Hysteresis threshold (°C) | 0-10 | 1 |

#### **Advanced Parameters (TC v2.5)**

| Parameter | Description | Range | Default |
|-----------|-------------|-------|---------|
| **increase_step** | PWM increase rate | 0.1-10 | 5 |
| **decrease_step** | PWM decrease rate | 0.1-10 | 0.1 |
| **val_up_trh** | Upper threshold (°C) | 0-5 | 1 |
| **val_down_trh** | Lower threshold (°C) | 1-10 | 3 |
| **Iterm_down_trh** | Integral term threshold | -20 to 0 | -10 |

#### **Error Handling Parameters**

| Parameter | Description | Range | Default |
|-----------|-------------|-------|---------|
| **sensor_read_error** | PWM on sensor error (%) | 0-100 | 100 |
| **fan_err** | PWM on fan error (%) | 0-100 | 30 |
| **psu_err** | PWM on PSU error (%) | 0-100 | 30 |
| **total_err_cnt** | Max errors before emergency | 1-10 | 2 |

### Thermal Policies

#### **Default Policy (TC v2.0)**

```json
{
  "thermal_policy": {
    "fan_min_speed": 30,
    "fan_max_speed": 100,
    "temp_critical": 105,
    "temp_high": 85,
    "temp_low": 70,
    "hysteresis": 1,
    "poll_time": 3
  }
}
```

#### **Advanced Policy (TC v2.5)**

```json
{
  "thermal_policy": {
    "fan_min_speed": 30,
    "fan_max_speed": 100,
    "temp_critical": 105,
    "temp_high": 85,
    "temp_low": 70,
    "hysteresis": 1,
    "poll_time": 3,
    "dynamic_pwm": true,
    "increase_step": 5,
    "decrease_step": 0.1,
    "val_up_trh": 1,
    "val_down_trh": 3
  }
}
```

#### **System-Specific Policies**

Different systems have optimized parameters:

- **High-performance systems**: Lower temperature thresholds, faster response
- **Quiet systems**: Higher temperature thresholds, slower fan response
- **Multi-ASIC systems**: Independent policies per ASIC
- **Module systems**: Special handling for optical modules with TEC cooling

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

## Thermal Algorithm Implementation

### **Algorithm Details**

#### **Sensor Data Processing**

1. **Value Smoothing**
   ```
   value_acc -= value_acc / smooth_level
   value_acc += raw_value
   smoothed_value = value_acc / smooth_level
   ```

2. **Hysteresis Implementation**
   ```
   if (current_value > previous_value + hysteresis) OR
      (trend_direction == current_trend):
       update_pwm()
   ```

3. **PWM Calculation Formula**
   ```
   PWM = pwm_min + ((temperature - temp_min) / (temp_max - temp_min)) * (pwm_max - pwm_min)
   ```

#### **Dynamic PWM Control (TC v2.5)**

The advanced algorithm includes integral control for smooth operation:

1. **Temperature Above Upper Threshold**
   ```
   temp_diff = current_temp - temp_max
   Iterm = temp_diff + 1
   pwm_max_dynamic += increase_step * Iterm
   ```

2. **Temperature Below Lower Threshold**
   ```
   Iterm -= (temp_max - current_temp - range)
   if Iterm < Iterm_down_trh:
       pwm_max_dynamic += decrease_step * Iterm
   ```

3. **Within Normal Range**
   ```
   Iterm = 0  // Reset integral term
   ```

#### **Error Handling**

The system implements comprehensive error handling:

1. **Sensor Read Errors**
   - Counts consecutive read failures
   - Sets PWM to maximum after threshold exceeded
   - Implements blacklist for faulty sensors

2. **Fan Errors**
   - Monitors fan tachometer readings
   - Detects missing or failed fans
   - Adjusts PWM based on available fans

3. **Emergency Conditions**
   - Triggers when total error count exceeds limit
   - Sets all fans to maximum speed
   - Logs emergency condition

#### **Multi-Sensor Fusion**

The system processes multiple sensors simultaneously:

1. **Individual PWM Calculation**
   - Each sensor calculates its required PWM
   - Based on temperature and configured parameters

2. **Maximum PWM Selection**
   - System selects highest PWM from all sensors
   - Ensures adequate cooling for hottest component

3. **Priority Handling**
   - Critical sensors (ASIC, CPU) have higher priority
   - Secondary sensors (ambient, modules) have lower priority

### **Performance Optimization**

#### **Polling Strategy**
- **Critical sensors**: 3-second intervals (ASIC, CPU)
- **Secondary sensors**: 20-60 second intervals (modules, ambient)
- **Adaptive polling**: Adjusts based on temperature trends

#### **Resource Management**
- **CPU usage**: Minimal impact with efficient algorithms
- **Memory usage**: Bounded by sensor count and history
- **I/O operations**: Optimized sysfs access patterns

## Hardware Management Sync Service

### **Service Overview**

The `hw-management-sync` service serves as the **data collection layer** of the thermal management system. It acts as a centralized data collector that continuously monitors hardware sensors and synchronizes sensor data across the system. This service provides the essential data foundation that the thermal control core engine relies upon for making intelligent thermal management decisions.

#### **Key Functions**

1. **Fan Status Synchronization**
   - Monitors fan presence and status
   - Updates thermal fan status files
   - Triggers chassis events for fan changes

2. **ASIC Temperature Management**
   - Populates ASIC temperature data
   - Handles ASIC readiness checks
   - Manages temperature thresholds and emergency states

3. **Module Temperature Monitoring**
   - Monitors optical module temperatures
   - Handles TEC (Thermo-Electric Cooler) cooling levels
   - Manages module presence detection

4. **Power Management Events**
   - Handles power button events
   - Manages graceful power-off requests
   - Triggers system shutdown procedures

5. **Leakage Detection**
   - Monitors liquid leakage sensors
   - Triggers chassis events for leakage detection
   - Provides early warning system

### **Service Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│                hw-management-sync Service                  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Fan       │    │   ASIC      │    │   Module    │     │
│  │   Sync      │    │   Temp      │    │   Temp      │     │
│  │             │    │   Populate  │    │   Populate  │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                   │                   │           │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Power     │    │   Leakage   │    │   Redfish   │     │
│  │   Events    │    │   Detection │    │   Sensors   │     │
│  │             │    │             │    │             │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                   │                   │           │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                Event Processing Loop                   │ │
│  │  • Polls sensors at configurable intervals            │ │
│  │  • Triggers chassis events on state changes          │ │
│  │  • Updates thermal management files                  │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### **Configuration Parameters**

#### **Polling Intervals**

| Component | Polling Interval | Description |
|-----------|------------------|-------------|
| **Fan Status** | 5 seconds | Fan presence and status monitoring |
| **ASIC Temperature** | 3 seconds | Critical temperature monitoring |
| **Module Temperature** | 20 seconds | Optical module temperature |
| **Power Events** | 1 second | Power button and shutdown events |
| **Leakage Detection** | 2 seconds | Liquid leakage sensor monitoring |
| **Redfish Sensors** | 30 seconds | BMC temperature via Redfish API |

#### **System-Specific Configuration**

The service uses different configurations based on system SKU:

- **HI162**: 6 fans, leakage detection, power events
- **HI163**: 6 fans, leakage detection, power events, ASIC temperature
- **HI164**: 6 fans, leakage detection, power events, ASIC temperature, modules
- **HI165**: 6 fans, leakage detection, power events, ASIC temperature, modules
- **Default**: Thermal enforcement monitoring

### **Event Processing**

#### **Fan Status Events**

```python
def sync_fan(fan_id, val):
    if int(val) == 0:
        status = 1  # Fan present
    else:
        status = 0  # Fan absent
    
    # Update thermal status file
    echo {status} > /var/run/hw-management/thermal/fan{fan_id}_status
    
    # Trigger chassis event
    hw-management-chassis-events.sh hotplug-event FAN{fan_id} {status}
```

#### **ASIC Temperature Population**

```python
def asic_temp_populate(asic_list, _dummy):
    for asic_name, asic_attr in asic_list.items():
        if is_asic_ready(asic_name, asic_attr):
            # Read temperature from ASIC
            # Update thermal files
            # Set thresholds and emergency values
        else:
            # Reset to default values
            asic_temp_reset(asic_name, asic_attr["fin"])
```

#### **Module Temperature Management**

```python
def module_temp_populate(module_config, _dummy):
    for module_idx in range(module_count):
        module_name = "module{}".format(module_idx + offset)
        
        if is_module_host_management_mode(module_path):
            continue  # Skip independent mode modules
        
        if module_present:
            # Read temperature and cooling levels
            # Update thermal files
            # Handle TEC cooling
        else:
            # Set default values
```

### **Service Management**

#### **Systemd Integration**

```ini
[Unit]
Description=Hw-management events sync service of Nvidia systems
After=hw-management.service
Requires=hw-management.service
PartOf=hw-management.service

[Service]
ExecStart=/bin/sh -c "/usr/bin/hw_management_sync.py"
Restart=on-failure
RestartSec=10s
```

#### **Service Control**

```bash
# Start service
systemctl start hw-management-sync

# Stop service
systemctl stop hw-management-sync

# Check status
systemctl status hw-management-sync

# View logs
journalctl -u hw-management-sync -f
```

### **Error Handling**

The service implements robust error handling:

1. **File Access Errors**: Gracefully handles missing files
2. **Permission Errors**: Continues operation with reduced functionality
3. **Service Restart**: Automatic restart on failure with exponential backoff
4. **Logging**: Comprehensive logging for troubleshooting

### **Data Flow Integration**

#### **Data Collection → Thermal Control Flow**

```
┌─────────────────────────────────────────────────────────────┐
│                    Data Collection Process                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │            hw-management-sync Service                   │ │
│  │              (Data Collector)                          │ │
│  │                                                         │ │
│  │  1. Polls hardware sensors (fans, ASIC, modules)       │ │
│  │  2. Detects state changes and events                   │ │
│  │  3. Updates thermal status files                       │ │
│  │  4. Triggers chassis events                            │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Thermal Control Process                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │        hw-management-thermal-control Service            │ │
│  │              (Core Engine)                             │ │
│  │                                                         │ │
│  │  1. Reads updated sensor data from sync service        │ │
│  │  2. Applies thermal algorithms and policies            │ │
│  │  3. Calculates required PWM for each sensor            │ │
│  │  4. Selects maximum PWM and controls fan speeds        │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

#### **Integration Points**

- **Thermal Control**: Provides temperature data for thermal management
- **Chassis Events**: Triggers hardware change notifications
- **Power Management**: Handles system shutdown requests
- **BMC Integration**: Communicates with BMC via Redfish API

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

### Version 2.8 (September 2025)

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
- **QM3400** support (ES level)
- **SN4280** support (ES level)
- **N5110_LD** support (ES level)
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

*© 2025 NVIDIA Corporation. All rights reserved. NVIDIA, the NVIDIA logo, and other NVIDIA marks are trademarks and/or registered trademarks of NVIDIA Corporation in the United States and other countries.*
