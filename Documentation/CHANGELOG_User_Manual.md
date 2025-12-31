# User Manual Changelog - Chassis Management for NVIDIA Switch Systems with Sysfs

**Document:** Chassis_Management_for_NVIDIA_Switch_Systems_with_Sysfs_rev.3.0.md  
**Last Updated:** December 31, 2025

---

## Change History

### V.7.0050.3000 - December 31, 2025

#### Added: PDB Sensor Documentation for Liquid-Cooled Systems

**Affected Platforms:** SN58XX_LD family (SN5810_LD, SN5800_LD)  
**Platform SKUs:** HI181, HI182  
**Board Types:** VMOD0024  
**ASIC:** Spectrum-5 (SPC5)

**Overview:**  
Added comprehensive documentation for Power Distribution Board (PDB) sensors specific to liquid-cooled systems (SN58XX_LD family) where traditional PSUs and fans are not present, and power distribution is managed through hot-pluggable PDB modules.

---

## New APIs and Sysfs Attributes (V.7.0050.3000)

### 1. Environment Sensors - PDB Hotswap Controller

#### 1.1 Current Measurements
**Node:** `$bsp_path/environment/pdb_hotswap<index>_curr<index>_input`  
**Description:** Read PDB hot-swap controller current (input)  
**Data Type:** Integer (milliamps)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/environment/pdb_hotswap1_curr1_input
```

#### 1.2 Voltage Measurements
**Node:** `$bsp_path/environment/pdb_hotswap<index>_in<index>_input`  
**Description:** Read PDB hot-swap controller voltage (input/output)  
**Data Type:** Integer (millivolts)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/environment/pdb_hotswap1_in1_input
cat $bsp_path/environment/pdb_hotswap1_in2_input
```

#### 1.3 Power Measurements
**Node:** `$bsp_path/environment/pdb_hotswap<index>_power<index>_input`  
**Description:** Read PDB hot-swap controller power (input)  
**Data Type:** Integer (microwatts)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/environment/pdb_hotswap1_power1_input
```

#### 1.4 Thresholds
**Node:** `$bsp_path/environment/pdb_hotswap<index>_<sensor>_<threshold>`  
**Thresholds:** crit, lcrit, max, min  
**Description:** Read PDB hot-swap controller threshold values  
**Data Type:** Integer (varies by sensor type)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Examples:**
```bash
cat $bsp_path/environment/pdb_hotswap1_curr1_max
cat $bsp_path/environment/pdb_hotswap1_in1_crit
cat $bsp_path/environment/pdb_hotswap1_in1_lcrit
cat $bsp_path/environment/pdb_hotswap1_in1_max
cat $bsp_path/environment/pdb_hotswap1_in1_min
```

---

### 2. Environment Sensors - PDB Power Converter

#### 2.1 Current Measurements
**Node:** `$bsp_path/environment/pdb_pwr_conv<index>_curr<index>_input`  
**Description:** Read PDB power converter current (input/output)  
**Data Type:** Integer (milliamps)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/environment/pdb_pwr_conv1_curr1_input  # Input current
cat $bsp_path/environment/pdb_pwr_conv1_curr2_input  # Output current
```

#### 2.2 Voltage Measurements
**Node:** `$bsp_path/environment/pdb_pwr_conv<index>_in<index>_input`  
**Description:** Read PDB power converter voltage (input/output)  
**Data Type:** Integer (millivolts)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/environment/pdb_pwr_conv1_in1_input  # Input voltage (VinDC)
cat $bsp_path/environment/pdb_pwr_conv1_in2_input  # Output voltage (Vout)
```

#### 2.3 Power Measurements
**Node:** `$bsp_path/environment/pdb_pwr_conv<index>_power<index>_input`  
**Description:** Read PDB power converter power (input/output)  
**Data Type:** Integer (microwatts)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/environment/pdb_pwr_conv1_power1_input  # Input power
cat $bsp_path/environment/pdb_pwr_conv1_power2_input  # Output power
```

#### 2.4 Thresholds
**Node:** `$bsp_path/environment/pdb_pwr_conv<index>_<sensor>_<threshold>`  
**Thresholds:** crit, lcrit, max, min  
**Description:** Read PDB power converter threshold values  
**Data Type:** Integer (varies by sensor type)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Examples:**
```bash
cat $bsp_path/environment/pdb_pwr_conv1_curr1_crit
cat $bsp_path/environment/pdb_pwr_conv1_curr1_max
cat $bsp_path/environment/pdb_pwr_conv1_in1_crit
cat $bsp_path/environment/pdb_pwr_conv1_in1_lcrit
cat $bsp_path/environment/pdb_pwr_conv1_in1_max
cat $bsp_path/environment/pdb_pwr_conv1_in1_min
```

---

### 3. Thermal Sensors - PDB

#### 3.1 PDB Hotswap Controller Temperature
**Node:** `$bsp_path/thermal/pdb_hotswap<index>_temp<index>_input`  
**Description:** Read PDB hot-swap controller temperature  
**Data Type:** Integer (millidegrees Celsius)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/thermal/pdb_hotswap1_temp1_input
```

#### 3.2 PDB Hotswap Temperature Thresholds
**Node:** `$bsp_path/thermal/pdb_hotswap<index>_temp<index>_crit`  
**Node:** `$bsp_path/thermal/pdb_hotswap<index>_temp<index>_max`  
**Description:** Read PDB hot-swap controller temperature thresholds  
**Data Type:** Integer (millidegrees Celsius)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/thermal/pdb_hotswap1_temp1_crit
cat $bsp_path/thermal/pdb_hotswap1_temp1_max
```

#### 3.3 PDB Power Converter Temperature
**Node:** `$bsp_path/thermal/pdb_pwr_conv<index>_temp<index>_input`  
**Description:** Read PDB power converter temperature  
**Data Type:** Integer (millidegrees Celsius)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/thermal/pdb_pwr_conv1_temp1_input
```

#### 3.4 PDB Power Converter Temperature Thresholds
**Node:** `$bsp_path/thermal/pdb_pwr_conv<index>_temp<index>_crit`  
**Node:** `$bsp_path/thermal/pdb_pwr_conv<index>_temp<index>_lcrit`  
**Node:** `$bsp_path/thermal/pdb_pwr_conv<index>_temp<index>_max`  
**Description:** Read PDB power converter temperature thresholds  
**Data Type:** Integer (millidegrees Celsius)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/thermal/pdb_pwr_conv1_temp1_crit
cat $bsp_path/thermal/pdb_pwr_conv1_temp1_lcrit
cat $bsp_path/thermal/pdb_pwr_conv1_temp1_max
```

#### 3.5 PDB MOSFET Ambient Temperature
**Node:** `$bsp_path/thermal/pdb_mosfet_amb<index>`  
**Description:** Read PDB MOSFET ambient temperature sensor  
**Data Type:** Integer (millidegrees Celsius)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/thermal/pdb_mosfet_amb1
```

---

### 4. Alarm Sensors - PDB

#### 4.1 PDB Hotswap Controller Alarms
**Node:** `$bsp_path/alarm/pdb_hotswap<index>_<sensor_name>_alarm`  
**Sensor Types:** in (voltage), curr (current), power, temp (temperature)  
**Description:** Read PDB hot-swap controller alarm status  
**Data Type:** Integer (0 = clear, 1 = alarm set)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Examples:**
```bash
cat $bsp_path/alarm/pdb_hotswap1_curr1_alarm
cat $bsp_path/alarm/pdb_hotswap1_in1_alarm
cat $bsp_path/alarm/pdb_hotswap1_in2_alarm
cat $bsp_path/alarm/pdb_hotswap1_power1_alarm
cat $bsp_path/alarm/pdb_hotswap1_temp1_crit_alarm
cat $bsp_path/alarm/pdb_hotswap1_temp1_max_alarm
```

#### 4.2 PDB Power Converter Alarms
**Node:** `$bsp_path/alarm/pdb_pwr_conv<index>_<sensor_name>_alarm`  
**Sensor Types:** in (voltage), curr (current), power, temp (temperature)  
**Description:** Read PDB power converter alarm status  
**Data Type:** Integer (0 = clear, 1 = alarm set)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Examples:**
```bash
cat $bsp_path/alarm/pdb_pwr_conv1_curr1_alarm
cat $bsp_path/alarm/pdb_pwr_conv1_curr2_alarm
cat $bsp_path/alarm/pdb_pwr_conv1_in1_alarm
cat $bsp_path/alarm/pdb_pwr_conv1_in2_alarm
cat $bsp_path/alarm/pdb_pwr_conv1_power1_alarm
cat $bsp_path/alarm/pdb_pwr_conv1_temp1_crit_alarm
cat $bsp_path/alarm/pdb_pwr_conv1_temp1_max_alarm
```

---

### 5. Events - PDB Hot-plug

**Node:** `$bsp_path/events/pdb<index>`  
**Description:** Get hot-plug event status of Power Distribution Board  
**Data Type:** Integer (0 = removed, 1 = inserted)  
**Access:** Read-only  
**Release Version:** V.7.0050.3000  
**Example:**
```bash
cat $bsp_path/events/pdb1
```

**Related Config Node:** `$bsp_path/config/hotplug_pdbs`  
**Description:** Get the number of hot-pluggable PDBs in the system  
**Example:**
```bash
cat $bsp_path/config/hotplug_pdbs
```

---

## Updated Sections (V.7.0050.3000)

### Configuration Control

**Section 3.1.11: Get Hot-plug PDB Number**
- **Updated:** Added comprehensive description explaining PDB role in liquid-cooled systems
- **Added Note:** Clarified this attribute is primarily for liquid-cooled systems (SN58XX_LD family)
- **Added Details:** Explained PDBs manage power distribution where traditional PSUs are not present

---

## Hardware Details (V.7.0050.3000)

### Liquid-Cooled System Characteristics (SN58XX_LD Family)

| Component | SN5810_LD | SN5800_LD | Notes |
|-----------|-----------|-----------|-------|
| **Model** | SN5810_LD | SN5800_LD | Liquid-cooled systems |
| **SKU** | HI181 | HI182 | Hardware identification |
| **Board Type** | VMOD0024 | VMOD0024 | Platform board designation |
| **ASIC** | Spectrum-5 (SPC5) | Spectrum-5 (SPC5) | Switch ASIC |
| **CPLDs** | 4 | 10 | System control CPLDs |
| **Leakage Sensors** | 2 | 5 | Liquid leak detection |
| **Hot-plug PDBs** | 1 | 4 | Power distribution boards |
| **PSUs** | 0 | 0 | No traditional power supplies |
| **Fans** | 0 | 0 | Liquid-cooled, no air fans |
| **Voltage Monitors** | 11 | Multiple | Main system voltage monitors |
| **COMEX Voltage Monitors** | 2 | 2 | CPU module voltage monitors |

### PDB Hardware Components

| Component | Chip | I2C Address | Description |
|-----------|------|-------------|-------------|
| **PDB Hotswap Controller** | LM5066i / MP5926 | 0x12 | Hot-swap power management |
| **PDB Power Converter** | RAA228004 / MP29502 | 0x60 | DC-DC power conversion |
| **PDB Temperature Sensor** | TMP451 | 0x4E | MOSFET ambient temperature |

---

## Code References (V.7.0050.3000)

### Configuration Files

#### hw-management.sh
```bash
# Line 2695-2713: SN58XX_LD platform-specific configuration
sn58xxld_specific()
{
    case $sku in
    # SN5810_LD
    HI181)
        cpld_num=4
        leakage_count=2
        i2c_asic_bus_default=6
        hotplug_pdbs=1
        ;;
    # SN5800_LD
    HI182)
        cpld_num=10
        leakage_count=5
        asic_i2c_buses=(6 22 38 54)
        hotplug_pdbs=4
        ;;
```

#### sn58xxld_sensors.conf
```bash
# Line 367-412: PDB sensor configuration
# PDB Hotswap controllers
chip "lm5066i-i2c-*-12"
chip "mp5926-i2c-*-12"

# PDB Power converters
chip "raa228004-i2c-*-60"
chip "mp29502-i2c-*-60"

# PDB temperature sensors
chip "tmp451-i2c-*-4e"
```

---

## Testing and Validation (V.7.0050.3000)

### Verification Steps

1. **System Tree Validation:**
   - Verified against: `tests/system_tree/hw-management-tree-sn5810.txt`
   - All documented sensors present in system tree
   - All symlinks correctly point to hardware sensors

2. **Code Correlation:**
   - Platform detection: ✅ Verified in `hw-management.sh`
   - Sensor configuration: ✅ Verified in `sn58xxld_sensors.conf`
   - Event handling: ✅ Verified in `hw_management_platform_config.py`
   - Thermal control: Not applicable (liquid-cooled, no thermal control)

3. **Hardware Correspondence:**
   - PDB hotswap sensors: ✅ LM5066i/MP5926 at i2c address 0x12
   - PDB power converter: ✅ RAA228004/MP29502 at i2c address 0x60
   - PDB temperature: ✅ TMP451 at i2c address 0x4E

---

## Platform Applicability (V.7.0050.3000)

### Liquid-Cooled Systems (SN58XX_LD Family)

| Platform | SKU | PDB Support | Status |
|----------|-----|-------------|--------|
| **SN5810_LD** | HI181 | Yes (1 PDB) | ✅ Documented |
| **SN5800_LD** | HI182 | Yes (4 PDBs) | ✅ Code present |

### Traditional Air-Cooled Systems

| Platform Family | PDB Support | Notes |
|----------------|-------------|-------|
| SN2xxx | No | Uses traditional PSUs |
| SN3xxx | No | Uses traditional PSUs |
| SN4xxx | No | Uses traditional PSUs |
| SN5xxx (non-LD) | No | Uses traditional PSUs |
| MSNxxx | No | Uses traditional PSUs |
| QMxxx | No | Uses traditional PSUs |
| Nxxxx (non-LD) | No | Uses traditional PSUs |

---

## Migration Notes for Existing Scripts (V.7.0050.3000)

### Key Differences from Traditional Systems

1. **No PSU Sensors:**
   - Traditional: `/var/run/hw-management/thermal/psu<N>_*`
   - Liquid-cooled: PDB sensors replace PSU sensors
   - Action: Check `$bsp_path/config/hotplug_pdbs` instead of `hotplug_psus`

2. **No Fan Sensors:**
   - Traditional: `/var/run/hw-management/thermal/fan<N>_*`
   - Liquid-cooled: No fan sensors (liquid-cooled)
   - Action: Check for leakage sensors instead

3. **New Event Monitoring:**
   - Add monitoring for: `$bsp_path/events/pdb<N>`
   - Add monitoring for: `$bsp_path/system/leakage<N>`

### Example Detection Script

```bash
#!/bin/bash

# Detect if system has PDBs (liquid-cooled) or PSUs (air-cooled)
if [ -f /var/run/hw-management/config/hotplug_pdbs ]; then
    pdb_count=$(cat /var/run/hw-management/config/hotplug_pdbs)
    if [ "$pdb_count" -gt 0 ]; then
        echo "Liquid-cooled system with $pdb_count PDB(s)"
        # Use PDB sensors
        for i in $(seq 1 $pdb_count); do
            cat /var/run/hw-management/thermal/pdb_hotswap${i}_temp1_input
            cat /var/run/hw-management/thermal/pdb_pwr_conv${i}_temp1_input
        done
    else
        echo "Traditional air-cooled system"
        # Use PSU sensors
        psu_count=$(cat /var/run/hw-management/config/hotplug_psus)
        for i in $(seq 1 $psu_count); do
            cat /var/run/hw-management/thermal/psu${i}_temp_input
        done
    fi
fi
```

---

## Summary of Changes (V.7.0050.3000)

### New API Sections Added: 15

1. Get PDB Hotswap Controller Current
2. Get PDB Hotswap Controller Voltage
3. Get PDB Hotswap Controller Power
4. Get PDB Hotswap Controller Thresholds
5. Get PDB Power Converter Current
6. Get PDB Power Converter Voltage
7. Get PDB Power Converter Power
8. Get PDB Power Converter Thresholds
9. Read PDB Hotswap Controller Temperature
10. Read PDB Hotswap Controller Temperature Thresholds
11. Read PDB Power Converter Temperature
12. Read PDB Power Converter Temperature Thresholds
13. Read PDB MOSFET Ambient Temperature
14. Get PDB Hotswap Controller alarm status
15. Get PDB Power Converter alarm status

### Updated API Sections: 1

1. Get Hot-plug PDB Number (Section 3.1.11) - Enhanced description for liquid-cooled systems

### New Event Sections: 1

1. PDB hot-plug event status (Section 3.5.4)

---

## Documentation Files Modified (V.7.0050.3000)

| File | Changes |
|------|---------|
| `Chassis_Management_for_NVIDIA_Switch_Systems_with_Sysfs_rev.3.0.md` | 15 new sections, 1 updated section, 1 new event section |
| `CHANGELOG_User_Manual.md` | Initial creation with V.7.0050.3000 changes |

---

## Total New sysfs Nodes Documented (V.7.0050.3000)

### Environment Sensors: 60+ nodes

- **PDB Hotswap (per PDB):**
  - Current: 1 input, 1 alarm, 1 max
  - Voltage: 2 inputs, 2 alarms, 2 crit, 2 lcrit, 2 max, 2 min
  - Power: 1 input, 1 alarm, 1 max
  - **Total per PDB: ~16 nodes**

- **PDB Power Converter (per PDB):**
  - Current: 2 inputs, 2 alarms, 2 crit, 2 max
  - Voltage: 2 inputs, 2 alarms, 2 crit, 2 lcrit, 2 max, 2 min
  - Power: 2 inputs, 1 alarm
  - **Total per PDB: ~21 nodes**

### Thermal Sensors: 15+ nodes

- PDB Hotswap temperature: 3 nodes per PDB (input, crit, max)
- PDB Power Converter temperature: 4 nodes per PDB (input, crit, lcrit, max)
- PDB MOSFET ambient: 1 node per PDB

### Event Sensors: 1+ node

- PDB hot-plug event: 1 node per PDB

### Configuration: 1 node

- hotplug_pdbs count

---

## Instructions for Future Updates

This changelog should be updated whenever changes are made to the User Manual. Follow this format:

1. Add a new version section at the top with date
2. List all new/modified/removed API sections
3. Include platform applicability
4. Provide code references
5. Document validation steps
6. Update summary of changes

---

## Contact and Support

For questions or issues related to User Manual documentation, please contact:
- Hardware Management Team
- Platform Engineering Team
- Documentation Team

---

**End of Changelog**

