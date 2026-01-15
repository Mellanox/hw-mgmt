# SN5810_LD Hardware Interfaces Documentation

**Platform:** SN5810_LD  
**SKU:** HI181  
**Board Type:** VMOD0024  
**ASIC:** Spectrum-5 (SPC5)  
**System Type:** Liquid-Cooled  
**Document Version:** 1.0  
**Last Updated:** January 14, 2026

---

## Table of Contents

1. [Platform Overview](#platform-overview)
2. [System Configuration](#system-configuration)
3. [Voltage Monitors](#voltage-monitors)
4. [PDB Power Distribution](#pdb-power-distribution)
5. [Thermal Sensors](#thermal-sensors)
6. [Alarm Sensors](#alarm-sensors)
7. [System Control](#system-control)
8. [LEDs](#leds)
9. [EEPROM](#eeprom)
10. [Events](#events)
11. [Watchdog](#watchdog)

---

## Platform Overview

The SN5810_LD is a liquid-cooled switch system with the following characteristics:

| Component | Value | Description |
|-----------|-------|-------------|
| CPLDs | 4 | System control CPLDs |
| Leakage Sensors | 2 | Liquid leak detection |
| Hot-plug PDBs | 1 | Power Distribution Board |
| PSUs | 0 | No traditional power supplies |
| Fans | 0 | Liquid-cooled, no air fans |
| ASIC Voltage Monitors | 11 | Main system voltage monitors |
| COMEX Voltage Monitors | 2 | CPU module voltage monitors |

---

## System Configuration

**Base Path:** `/var/run/hw-management/`

### Configuration Files

| Node | Description | Value |
|------|-------------|-------|
| `config/asic_num` | Number of ASICs | 1 |
| `config/cpld_num` | Number of CPLDs | 4 |
| `config/hotplug_pdbs` | Number of hot-plug PDBs | 1 |
| `config/hotplug_psus` | Number of hot-plug PSUs | 0 |
| `config/hotplug_fans` | Number of hot-plug fans | 0 |
| `config/leakage_counter` | Number of leakage sensors | 2 |
| `config/cpu_type` | CPU type | AMD |
| `config/lm_sensors_config` | Sensors configuration file | sn58xxld_sensors.conf |
| `config/lm_sensors_labels` | Sensors labels file | sn58xxld_sensors_labels.json |

---

## Voltage Monitors

### ASIC Voltage Monitors (voltmon1-11)

**Chips:** MP2962, MP2891, MP2985, MP2975

#### Voltage Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_in1_input` | Input voltage | mV |
| `environment/voltmon<N>_in2_input` | Output voltage 1 | mV |
| `environment/voltmon<N>_in3_input` | Output voltage 2 | mV |

#### Current Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_curr1_input` | Input current | mA |
| `environment/voltmon<N>_curr2_input` | Output current 1 | mA |
| `environment/voltmon<N>_curr3_input` | Output current 2 | mA |

#### Power Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_power1_input` | Input power | µW |
| `environment/voltmon<N>_power2_input` | Output power 1 | µW |
| `environment/voltmon<N>_power3_input` | Output power 2 | µW |

#### Thresholds

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_in<M>_crit` | Critical voltage threshold | mV |
| `environment/voltmon<N>_in<M>_lcrit` | Low critical voltage threshold | mV |
| `environment/voltmon<N>_curr<M>_crit` | Critical current threshold | mA |
| `environment/voltmon<N>_curr<M>_max` | Maximum current threshold | mA |

### COMEX Voltage Monitors (comex_voltmon1-2)

**Chips:** MP2855 (CPU), MP2975 (DDR)

#### comex_voltmon1 (CPU Power Controller)

| Node | Description | Unit |
|------|-------------|------|
| `environment/comex_voltmon1_in1_input` | Input voltage | mV |
| `environment/comex_voltmon1_in2_input` | VDDCR_CPU voltage | mV |
| `environment/comex_voltmon1_in3_input` | VDDCR_SOC voltage | mV |
| `environment/comex_voltmon1_curr2_input` | VDDCR_CPU current | mA |
| `environment/comex_voltmon1_curr3_input` | VDDCR_SOC current | mA |

#### comex_voltmon2 (DDR Power Controller)

| Node | Description | Unit |
|------|-------------|------|
| `environment/comex_voltmon2_in1_input` | VDD_MEM input voltage | mV |
| `environment/comex_voltmon2_in2_input` | VDD_MEM output voltage | mV |
| `environment/comex_voltmon2_curr1_input` | VDD_MEM input current | mA |
| `environment/comex_voltmon2_curr2_input` | VDD_MEM output current | mA |
| `environment/comex_voltmon2_power1_input` | VDD_MEM input power | µW |
| `environment/comex_voltmon2_power2_input` | VDD_MEM output power | µW |

---

## PDB Power Distribution

### PDB Hotswap Controller (pdb_hotswap1)

**Chip:** LM5066i or MP5926  
**I2C Address:** 0x12

#### Current Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_hotswap1_curr1_input` | VinDC current (in) | mA |
| `environment/pdb_hotswap1_curr1_max` | Maximum current threshold | mA |

#### Voltage Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_hotswap1_in1_input` | VinDC voltage (in) | mV |
| `environment/pdb_hotswap1_in2_input` | Vout voltage (out) | mV |
| `environment/pdb_hotswap1_in1_crit` | Critical voltage threshold | mV |
| `environment/pdb_hotswap1_in1_lcrit` | Low critical voltage threshold | mV |
| `environment/pdb_hotswap1_in1_max` | Maximum voltage threshold | mV |
| `environment/pdb_hotswap1_in1_min` | Minimum voltage threshold | mV |

#### Power Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_hotswap1_power1_input` | VinDC power (in) | µW |
| `environment/pdb_hotswap1_power1_max` | Maximum power threshold | µW |

### PDB Power Converter (pdb_pwr_conv1)

**Chip:** RAA228004 or MP29502  
**I2C Address:** 0x60

#### Current Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_pwr_conv1_curr1_input` | Input current | mA |
| `environment/pdb_pwr_conv1_curr2_input` | Output current | mA |
| `environment/pdb_pwr_conv1_curr1_crit` | Critical current threshold | mA |
| `environment/pdb_pwr_conv1_curr1_max` | Maximum current threshold | mA |

#### Voltage Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_pwr_conv1_in1_input` | VinDC voltage (in) | mV |
| `environment/pdb_pwr_conv1_in2_input` | Vout voltage (out) | mV |
| `environment/pdb_pwr_conv1_in1_crit` | Critical voltage threshold | mV |
| `environment/pdb_pwr_conv1_in1_lcrit` | Low critical voltage threshold | mV |

#### Power Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_pwr_conv1_power1_input` | Input power | µW |
| `environment/pdb_pwr_conv1_power2_input` | Output power | µW |

---

## Thermal Sensors

### ASIC Voltage Monitor Temperatures

| Node | Description | Unit |
|------|-------------|------|
| `thermal/voltmon<N>_temp1_input` | PMIC temperature | m°C |
| `thermal/voltmon<N>_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/voltmon<N>_temp1_max` | Maximum temperature threshold | m°C |

### COMEX Voltage Monitor Temperatures

| Node | Description | Unit |
|------|-------------|------|
| `thermal/comex_voltmon1_temp1_input` | CPU PMIC temperature | m°C |
| `thermal/comex_voltmon1_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/comex_voltmon2_temp1_input` | DDR PMIC temperature | m°C |
| `thermal/comex_voltmon2_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/comex_voltmon2_temp1_max` | Maximum temperature threshold | m°C |

### PDB Temperatures

| Node | Description | Unit |
|------|-------------|------|
| `thermal/pdb_hotswap1_temp1_input` | PDB hotswap controller temperature | m°C |
| `thermal/pdb_hotswap1_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/pdb_hotswap1_temp1_max` | Maximum temperature threshold | m°C |
| `thermal/pdb_pwr_conv1_temp1_input` | PDB power converter temperature | m°C |
| `thermal/pdb_pwr_conv1_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/pdb_pwr_conv1_temp1_lcrit` | Low critical temperature threshold | m°C |
| `thermal/pdb_pwr_conv1_temp1_max` | Maximum temperature threshold | m°C |

### PDB MOSFET Ambient Temperature

| Node | Description | Unit |
|------|-------------|------|
| `thermal/pdb_mosfet_amb1` | PDB MOSFET ambient temperature | m°C |

### CPU Temperature

| Node | Description | Unit |
|------|-------------|------|
| `thermal/cpu_pack` | CPU package temperature | m°C |
| `thermal/cpu_pack_crit` | Critical temperature threshold | m°C |
| `thermal/cpu_pack_max` | Maximum temperature threshold | m°C |

### Drive Temperature

| Node | Description | Unit |
|------|-------------|------|
| `thermal/drivetemp` | SSD temperature | m°C |
| `thermal/drivetemp_crit` | Critical temperature threshold | m°C |
| `thermal/drivetemp_max` | Maximum temperature threshold | m°C |

---

## Alarm Sensors

### Voltage Monitor Alarms

| Node | Description | Value |
|------|-------------|-------|
| `alarm/voltmon<N>_in<M>_alarm` | Voltage alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_curr<M>_alarm` | Current alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_temp1_crit_alarm` | Critical temperature alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_temp1_max_alarm` | Max temperature alarm | 0=clear, 1=alarm |

### COMEX Voltage Monitor Alarms

| Node | Description | Value |
|------|-------------|-------|
| `alarm/comex_voltmon1_curr<N>_alarm` | CPU PMIC current alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon1_in<N>_alarm` | CPU PMIC voltage alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon1_temp1_crit_alarm` | CPU PMIC critical temp alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_curr<N>_alarm` | DDR PMIC current alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_in<N>_alarm` | DDR PMIC voltage alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_power1_alarm` | DDR PMIC power alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_temp1_crit_alarm` | DDR PMIC critical temp alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_temp1_max_alarm` | DDR PMIC max temp alarm | 0=clear, 1=alarm |

### PDB Alarms

| Node | Description | Value |
|------|-------------|-------|
| `alarm/pdb_hotswap1_curr1_alarm` | PDB hotswap current alarm | 0=clear, 1=alarm |
| `alarm/pdb_hotswap1_in1_alarm` | PDB hotswap input voltage alarm | 0=clear, 1=alarm |
| `alarm/pdb_hotswap1_in2_alarm` | PDB hotswap output voltage alarm | 0=clear, 1=alarm |
| `alarm/pdb_hotswap1_power1_alarm` | PDB hotswap power alarm | 0=clear, 1=alarm |
| `alarm/pdb_hotswap1_temp1_crit_alarm` | PDB hotswap critical temp alarm | 0=clear, 1=alarm |
| `alarm/pdb_hotswap1_temp1_max_alarm` | PDB hotswap max temp alarm | 0=clear, 1=alarm |
| `alarm/pdb_pwr_conv1_curr<N>_alarm` | PDB power converter current alarm | 0=clear, 1=alarm |
| `alarm/pdb_pwr_conv1_in<N>_alarm` | PDB power converter voltage alarm | 0=clear, 1=alarm |
| `alarm/pdb_pwr_conv1_power1_alarm` | PDB power converter power alarm | 0=clear, 1=alarm |
| `alarm/pdb_pwr_conv1_temp1_crit_alarm` | PDB converter critical temp alarm | 0=clear, 1=alarm |
| `alarm/pdb_pwr_conv1_temp1_max_alarm` | PDB converter max temp alarm | 0=clear, 1=alarm |

---

## System Control

### ASIC Control

| Node | Description | Access |
|------|-------------|--------|
| `system/asic_health` | ASIC health status | RO |
| `system/asic_reset` | ASIC reset control | RW |
| `system/asic1_pg_fail` | ASIC1 power good fail | RO |
| `system/asic1_reset` | ASIC1 reset control | RW |

### Power Control

| Node | Description | Access |
|------|-------------|--------|
| `system/pwr_cycle` | System power cycle | WO |
| `system/pwr_down` | System power down | WO |
| `system/aux_pwr_cycle` | Auxiliary power cycle | WO |
| `system/graceful_pwr_off` | Graceful power off | RW |

### CPLD Information

| Node | Description | Access |
|------|-------------|--------|
| `system/cpld1_version` | CPLD1 version | RO |
| `system/cpld1_version_min` | CPLD1 minimum version | RO |
| `system/cpld1_pn` | CPLD1 part number | RO |
| `system/cpld2_version` | CPLD2 version | RO |
| `system/cpld2_version_min` | CPLD2 minimum version | RO |
| `system/cpld2_pn` | CPLD2 part number | RO |
| `system/cpld3_version` | CPLD3 version | RO |
| `system/cpld3_version_min` | CPLD3 minimum version | RO |
| `system/cpld3_pn` | CPLD3 part number | RO |
| `system/cpld4_version` | CPLD4 version | RO |
| `system/cpld4_version_min` | CPLD4 minimum version | RO |
| `system/cpld4_pn` | CPLD4 part number | RO |

### Leakage Detection

| Node | Description | Access |
|------|-------------|--------|
| `system/leakage1` | Leakage sensor 1 status | RO |
| `system/leakage2` | Leakage sensor 2 status | RO |

### BMC Interface

| Node | Description | Access |
|------|-------------|--------|
| `system/bmc_present` | BMC presence | RO |
| `system/bmc_to_cpu_ctrl` | BMC to CPU control | RW |

### JTAG

| Node | Description | Access |
|------|-------------|--------|
| `system/jtag_enable` | JTAG enable | RW |
| `system/jtag_cap` | JTAG capability | RO |
| `jtag/jtag_enable` | JTAG enable (alternative) | RW |

---

## LEDs

### Power LED

| Node | Description | Access |
|------|-------------|--------|
| `led/led_power` | Power LED state | RW |
| `led/led_power_amber` | Power LED amber brightness | RW |
| `led/led_power_green` | Power LED green brightness | RW |
| `led/led_power_capability` | Power LED capabilities | RO |
| `led/led_power_state` | Power LED state conversion | RO |

### Status LED

| Node | Description | Access |
|------|-------------|--------|
| `led/led_status` | Status LED state | RW |
| `led/led_status_amber` | Status LED amber brightness | RW |
| `led/led_status_green` | Status LED green brightness | RW |
| `led/led_status_capability` | Status LED capabilities | RO |
| `led/led_status_state` | Status LED state conversion | RO |

### UID LED

| Node | Description | Access |
|------|-------------|--------|
| `led/led_uid` | UID LED state | RW |
| `led/led_uid_blue` | UID LED blue brightness | RW |
| `led/led_uid_capability` | UID LED capabilities | RO |
| `led/led_uid_state` | UID LED state conversion | RO |

---

## EEPROM

### VPD (Vital Product Data)

| Node | Description | Access |
|------|-------------|--------|
| `eeprom/vpd_info` | VPD EEPROM device | RO |
| `eeprom/vpd_data` | VPD parsed data | RO |

### CPU Information

| Node | Description | Access |
|------|-------------|--------|
| `eeprom/cpu_info` | CPU EEPROM device | RO |
| `eeprom/cpu_data` | CPU parsed data | RO |

---

## Events

### PDB Hot-plug Event

| Node | Description | Value |
|------|-------------|-------|
| `events/pdb1` | PDB1 hot-plug status | 0=removed, 1=inserted |

### Leakage Events

| Node | Description | Value |
|------|-------------|-------|
| `events/leakage1` | Leakage sensor 1 event | 0=no leak, 1=leak |
| `events/leakage2` | Leakage sensor 2 event | 0=no leak, 1=leak |

---

## Watchdog

| Node | Description | Access |
|------|-------------|--------|
| `watchdog/watchdog1/identity` | Watchdog identity | RO |
| `watchdog/watchdog1/state` | Watchdog state | RO |
| `watchdog/watchdog1/status` | Watchdog status | RO |
| `watchdog/watchdog1/timeout` | Watchdog timeout | RW |
| `watchdog/watchdog2/identity` | Watchdog 2 identity | RO |
| `watchdog/watchdog2/state` | Watchdog 2 state | RO |
| `watchdog/watchdog2/status` | Watchdog 2 status | RO |
| `watchdog/watchdog2/timeout` | Watchdog 2 timeout | RW |

---

## Power Calculation

| Node | Description | Access |
|------|-------------|--------|
| `power/pwr_consum` | System power consumption | RO |
| `power/pwr_sys` | System power | RO |

---

## Hardware Component Summary

### Power Management ICs (PMICs) - ASIC

| Component | Chip | Vendor | I2C Address | Linux Driver | Description |
|-----------|------|--------|-------------|--------------|-------------|
| PMIC-1 | MP2891 | MPS | 0x62 | mp2891 | VDD_M (main ASIC power) |
| PMIC-2 | MP2891 | MPS | 0x63 | mp2891 | VDD_T0/VDD_T1 (tiles 0-1) |
| PMIC-3 | MP2891 | MPS | 0x64 | mp2891 | VDD_T2/VDD_T3 (tiles 2-3) |
| PMIC-4 | MP2891 | MPS | 0x65 | mp2891 | VDD_T4/VDD_T5 (tiles 4-5) |
| PMIC-5 | MP2891 | MPS | 0x66 | mp2891 | VDD_T6/VDD_T7 (tiles 6-7) |
| PMIC-6 | MP2891 | MPS | 0x67 | mp2891 | DVDD_T0/DVDD_T1 |
| PMIC-7 | MP2891 | MPS | 0x68 | mp2891 | DVDD_T2/DVDD_T3 |
| PMIC-8 | MP2891 | MPS | 0x69 | mp2891 | DVDD_T4/DVDD_T5 |
| PMIC-9 | MP2891 | MPS | 0x6a | mp2891 | DVDD_T6/DVDD_T7 |
| PMIC-10 | MP2891 | MPS | 0x6c | mp2891 | HVDD_T03/HVDD_T47 |
| PMIC-11 | MP2891 | MPS | 0x6e | mp2891 | VDDSCC/DVDD_M |

**Alternative ASIC PMICs:** XDPE1A2G7 (Infineon) at same addresses - driver: xdpe1a2g7

### Power Management ICs (PMICs) - COMEX

| Component | Chip | Vendor | I2C Address | Linux Driver | Description |
|-----------|------|--------|-------------|--------------|-------------|
| PMIC-12 (CPU) | MP2855 | MPS | 0x69 (bus 69) | mp2855 | VDDCR_CPU/VDDCR_SOC |
| PMIC-13 (DDR) | MP2975 | MPS | 0x6a (bus 69) | mp2975 | VDD_MEM |

### Power Distribution Board (PDB)

| Component | Chip | Vendor | I2C Address | Linux Driver | Description |
|-----------|------|--------|-------------|--------------|-------------|
| PDB Hotswap | LM5066I | Texas Instruments | 0x12 | lm5066i | Hot-swap controller |
| PDB Converter | RAA228004 | Renesas | 0x60 | raa228004 | 48V to 12V DC-DC converter |
| PDB Temp Sensor | TMP451 | Texas Instruments | 0x4e | tmp451 | MOSFET ambient temperature |

**Alternative Components:**
- PDB Hotswap: MP5926 (MPS) - driver: mp5926
- PDB Converter: MP29502 (MPS) - driver: mp29502

### Temperature Sensors

| Component | Chip | Vendor | I2C Address | Linux Driver | Description |
|-----------|------|--------|-------------|--------------|-------------|
| SODIMM 1 Temp | JC42.4 | JEDEC | 0x1a | jc42 | DDR SODIMM temperature |
| SODIMM 2 Temp | JC42.4 | JEDEC | 0x1b | jc42 | DDR SODIMM temperature |
| SODIMM 3 Temp | JC42.4 | JEDEC | 0x1e | jc42 | DDR SODIMM temperature |
| SODIMM 4 Temp | JC42.4 | JEDEC | 0x1f | jc42 | DDR SODIMM temperature |
| CPU Temp | K10Temp | AMD | PCI | k10temp | CPU package temperature |
| SSD Temp | NVMe | - | PCI | nvme | NVMe SSD temperature |

---

## Chip Details from sensors.conf

The following chip configurations are defined in `sn58xxld_sensors.conf`:

### ASIC Power Controllers

#### MP2891 (MPS) - Primary

| Chip Pattern | I2C Address | Function |
|--------------|-------------|----------|
| `mp2891-i2c-*-62` | 0x62 | PMIC-1: VDD_M (main ASIC power) |
| `mp2891-i2c-*-63` | 0x63 | PMIC-2: VDD_T0/VDD_T1 (tiles 0-1) |
| `mp2891-i2c-*-64` | 0x64 | PMIC-3: VDD_T2/VDD_T3 (tiles 2-3) |
| `mp2891-i2c-*-65` | 0x65 | PMIC-4: VDD_T4/VDD_T5 (tiles 4-5) |
| `mp2891-i2c-*-66` | 0x66 | PMIC-5: VDD_T6/VDD_T7 (tiles 6-7) |
| `mp2891-i2c-*-67` | 0x67 | PMIC-6: DVDD_T0/DVDD_T1 |
| `mp2891-i2c-*-68` | 0x68 | PMIC-7: DVDD_T2/DVDD_T3 |
| `mp2891-i2c-*-69` | 0x69 | PMIC-8: DVDD_T4/DVDD_T5 |
| `mp2891-i2c-*-6a` | 0x6a | PMIC-9: DVDD_T6/DVDD_T7 |
| `mp2891-i2c-*-6c` | 0x6c | PMIC-10: HVDD_T03/HVDD_T47 |
| `mp2891-i2c-*-6e` | 0x6e | PMIC-11: VDDSCC/DVDD_M |

#### XDPE1A2G7 (Infineon) - Alternative

| Chip Pattern | I2C Address | Function |
|--------------|-------------|----------|
| `xdpe1a2g7-i2c-*-62` | 0x62 | PMIC-1: VDD_M (main ASIC power) |
| `xdpe1a2g7-i2c-*-63` | 0x63 | PMIC-2: VDD_T0/VDD_T1 (tiles 0-1) |
| `xdpe1a2g7-i2c-*-64` | 0x64 | PMIC-3: VDD_T2/VDD_T3 (tiles 2-3) |
| `xdpe1a2g7-i2c-*-65` | 0x65 | PMIC-4: VDD_T4/VDD_T5 (tiles 4-5) |
| `xdpe1a2g7-i2c-*-66` | 0x66 | PMIC-5: VDD_T6/VDD_T7 (tiles 6-7) |
| `xdpe1a2g7-i2c-*-67` | 0x67 | PMIC-6: DVDD_T0/DVDD_T1 |
| `xdpe1a2g7-i2c-*-68` | 0x68 | PMIC-7: DVDD_T2/DVDD_T3 |
| `xdpe1a2g7-i2c-*-69` | 0x69 | PMIC-8: DVDD_T4/DVDD_T5 |
| `xdpe1a2g7-i2c-*-6a` | 0x6a | PMIC-9: DVDD_T6/DVDD_T7 |
| `xdpe1a2g7-i2c-*-6c` | 0x6c | PMIC-10: HVDD_T03/HVDD_T47 |
| `xdpe1a2g7-i2c-*-6e` | 0x6e | PMIC-11: VDDSCC/DVDD_M |

### PMIC Register Mapping

#### PMIC-1 (VDD_M) Registers

| Register | Label |
|----------|-------|
| `in1` | PSU 12V Rail (in1) |
| `in2` | VDD_M ADJ Rail (out1) |
| `temp1` | VDD_M ADJ Temp 1 |
| `power1` | 12V VDD_M (in) |
| `power2` | VDD_M Rail Pwr (out1) |
| `curr1` | 12V VDD_M Rail Curr (in1) |
| `curr2` | VDD_M Rail Curr (out1) |

#### PMIC-2 to PMIC-5 (VDD_Tx) Registers

| Register | Label |
|----------|-------|
| `in1` | PSU 12V Rail (in1) |
| `in2` | VDD_Tx ADJ Rail (out1) |
| `in3` | VDD_Ty ADJ Rail (out2) |
| `temp1` | VDD_Tx ADJ Temp 1 |
| `power1` | 12V VDD_Tx VDD_Ty (in) |
| `power2` | VDD_Tx Rail Pwr (out1) |
| `power3` | VDD_Ty Rail Pwr (out2) |
| `curr1` | 12V VDD_Tx VDD_Ty Rail Curr (in1) |
| `curr2` | VDD_Tx Rail Curr (out1) |
| `curr3` | VDD_Ty Rail Curr (out2) |

#### PMIC-6 to PMIC-9 (DVDD_Tx) Registers

| Register | Label |
|----------|-------|
| `in1` | PSU 12V Rail (in1) |
| `in2` | DVDD_Tx ADJ Rail (out1) |
| `in3` | DVDD_Ty ADJ Rail (out2) |
| `temp1` | DVDD_Tx ADJ Temp 1 |
| `power1` | 12V DVDD_Tx DVDD_Ty (in) |
| `power2` | DVDD_Tx Rail Pwr (out1) |
| `power3` | DVDD_Ty Rail Pwr (out2) |
| `curr1` | 12V DVDD_Tx DVDD_Ty Rail Curr (in1) |
| `curr2` | DVDD_Tx Rail Curr (out1) |
| `curr3` | DVDD_Ty Rail Curr (out2) |

#### PMIC-10 (HVDD) Registers

| Register | Label |
|----------|-------|
| `in1` | PSU 12V Rail (in1) |
| `in2` | HVDD_T03 1V2 Rail (out1) |
| `in3` | HVDD_T47 1V2 Rail (out2) |
| `temp1` | HVDD_T03 1V2 Temp 1 |
| `power1` | 12V HVDD_T03 HVDD_T47 (in) |
| `power2` | HVDD_T03 Rail Pwr (out1) |
| `power3` | HVDD_T47 Rail Pwr (out2) |
| `curr1` | 12V HVDD_T03 HVDD_T47 Rail Curr (in1) |
| `curr2` | HVDD_T03 Rail Curr (out1) |
| `curr3` | HVDD_T47 Rail Curr (out2) |

#### PMIC-11 (VDDSCC/DVDD_M) Registers

| Register | Label |
|----------|-------|
| `in1` | PSU 12V Rail (in1) |
| `in2` | VDDSCC 0V75 Rail (out1) |
| `in3` | DVDD_M ADJ Rail (out2) |
| `temp1` | VDDSCC 1V2 Temp 1 |
| `power1` | 12V VDDSCC DVDD_M (in) |
| `power2` | VDDSCC Rail Pwr (out1) |
| `power3` | DVDD_M Rail Pwr (out2) |
| `curr1` | 12V VDDSCC DVDD_M Rail Curr (in1) |
| `curr2` | DVDD_M Rail Curr (out1) |
| `curr3` | VDDSCC Rail Curr (out2) |

### PDB Hotswap Controllers

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `lm5066i-i2c-*-12` | 0x12 | Texas Instruments | HSC VinDC |
| `mp5926-i2c-*-12` | 0x12 | MPS | HSC VinDC (alternative) |

**Registers:**
- `in1`: HSC VinDC Volt (in)
- `in3`: HSC Vout Volt (out)
- `power1`: HSC VinDC Pwr (in)
- `curr1`: HSC VinDC Curr (in)
- `temp1`: HSC Temp

### PDB Power Converters

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `raa228004-i2c-*-60` | 0x60 | Renesas | PWR_CONV (48V to 12V) |
| `mp29502-i2c-*-60` | 0x60 | MPS | PWR_CONV (alternative) |

**Registers:**
- `in1`: PWR_CONV VinDC Volt (in)
- `in3`: PWR_CONV Vout Volt (out)
- `power1`: PWR_CONV VinDC Pwr (in)
- `power2`: PWR_CONV Pwr (out)
- `curr1`: PWR_CONV VinDC Curr (in)
- `curr2`: PWR_CONV Curr (out)
- `temp2`: PWR_CONV Temp

### PDB Temperature Sensors

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `tmp451-i2c-*-4e` | 0x4e | Texas Instruments | PDB Mosfet Temp |

### AMD COMEX CPU Power Controller

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `mp2855-i2c-*-69` | 0x69 | MPS | COMEX VDDCR_CPU/VDDCR_SOC |

**Registers:**
- `in1`: COMEX (in) VDDCR INPUT VOLT
- `in2`: COMEX (out) VDDCR_CPU VOLT
- `in3`: COMEX (out2) VDDCR_SOC VOLT
- `temp1`: COMEX VDDCR_CPU PHASE TEMP
- `temp2`: COMEX VDDCR_SOC PHASE TEMP
- `curr1`: COMEX VDDCR_CPU CURR
- `curr2`: COMEX VDDCR_SOC CURR

### AMD COMEX DDR Power Controller

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `mp2975-i2c-*-6a` | 0x6a | MPS | COMEX VDD_MEM |

**Registers:**
- `in1`: COMEX VDD_MEM INPUT VOLT
- `in2`: COMEX VDD_MEM OUTPUT VOLT
- `temp1`: COMEX VDD_MEM PHASE TEMP
- `curr1`: COMEX VDD_MEM INPUT CURR
- `curr2`: COMEX VDD_MEM OUTPUT CURR
- `power1`: COMEX VDD_MEM INPUT POWER
- `power2`: COMEX VDD_MEM OUTPUT POWER

### AMD COMEX SODIMM Temperature Sensors

| Chip Pattern | I2C Address | Function |
|--------------|-------------|----------|
| `jc42-i2c-*-1a` | 0x1a | SODIMM1 Temp |
| `jc42-i2c-*-1b` | 0x1b | SODIMM2 Temp |
| `jc42-i2c-*-1e` | 0x1e | SODIMM3 Temp |
| `jc42-i2c-*-1f` | 0x1f | SODIMM4 Temp |

### AMD COMEX CPU Temperature Sensor

| Chip Pattern | Vendor | Function |
|--------------|--------|----------|
| `k10temp-pci-*` | AMD | CPU Package Temp, CPU Die0 Temp |

### NVMe SSD Temperature Sensor

| Chip Pattern | Function |
|--------------|----------|
| `nvme-pci-*` | SSD Temp |

### Ethernet PHY Temperature Sensor

| Chip Pattern | Function |
|--------------|----------|
| `*-mdio-*` | PHY Temp (ignored) |

---

**Source Files:**
- Configuration: `usr/etc/hw-management-sensors/sn58xxld_sensors.conf`
- Labels: `usr/etc/hw-management-sensors/sn58xxld_sensors_labels.json`

---

**End of Document**
