# N6100_LD Hardware Interfaces Documentation

**Platform:** N6100_LD  
**SKU:** HI180  
**ASIC:** 4x Spectrum-X (Multi-ASIC)  
**CPU Type:** AMD  
**System Type:** Liquid-Cooled  
**Document Version:** 1.0  
**Last Updated:** January 14, 2026

---

## Table of Contents

1. [Platform Overview](#platform-overview)
2. [System Configuration](#system-configuration)
3. [Multi-ASIC Voltage Monitors](#multi-asic-voltage-monitors)
4. [COMEX Voltage Monitors](#comex-voltage-monitors)
5. [PDB Power Distribution](#pdb-power-distribution)
6. [Thermal Sensors](#thermal-sensors)
7. [Alarm Sensors](#alarm-sensors)
8. [System Control](#system-control)
9. [LEDs](#leds)
10. [EEPROM](#eeprom)
11. [Events](#events)
12. [Watchdog](#watchdog)

---

## Platform Overview

The N6100_LD is a liquid-cooled multi-ASIC switch system with the following characteristics:

| Component | Value | Description |
|-----------|-------|-------------|
| ASICs | 4 | Multi-ASIC Spectrum-X configuration |
| CPLDs | 2 | System control CPLDs |
| Leakage Sensors | 2 | Liquid leak detection |
| Hot-plug PDBs | 0 | PDB not hot-pluggable |
| PSUs | 0 | No traditional power supplies |
| Fans | 0 | Liquid-cooled, no air fans |
| Cable Cartridges | 4 | Cable cartridge EEPROMs |
| eRoT | 1 | External Root of Trust |
| ASIC Voltage Monitors | 16 | 4 PMICs per ASIC |
| COMEX Voltage Monitors | 2 | CPU and DDR power controllers |
| Power Converters | 2 | DC-DC converters |
| SODIMM Sensors | 2 | DDR module temperature |

---

## System Configuration

**Base Path:** `/var/run/hw-management/`

### Configuration Files

| Node | Description | Value |
|------|-------------|-------|
| `config/asic_num` | Number of ASICs | 4 |
| `config/cpld_num` | Number of CPLDs | 2 |
| `config/cartridge_counter` | Number of cable cartridges | 4 |
| `config/leakage_counter` | Number of leakage sensors | 2 |
| `config/hotplug_pdbs` | Number of hot-plug PDBs | 0 |
| `config/hotplug_psus` | Number of hot-plug PSUs | 0 |
| `config/hotplug_fans` | Number of hot-plug fans | 0 |
| `config/fan_drwr_num` | Number of fan drawers | 0 |
| `config/cpu_type` | CPU type | AMD |
| `config/i2c_bus_offset` | I2C bus offset | 0 |
| `config/i2c_comex_mon_bus_default` | COMEX monitor I2C bus | 6 |
| `config/lm_sensors_config` | Sensors configuration file | n61xxld_sensors.conf |
| `config/lm_sensors_labels` | Sensors labels file | n61xxld_sensors_labels.json |

### ASIC Configuration

| Node | Description |
|------|-------------|
| `config/asic1_pci_bus_id` | ASIC1 PCI bus ID |
| `config/asic2_pci_bus_id` | ASIC2 PCI bus ID |
| `config/asic3_pci_bus_id` | ASIC3 PCI bus ID |
| `config/asic4_pci_bus_id` | ASIC4 PCI bus ID |
| `config/asic1_ready` | ASIC1 readiness status |
| `config/asic2_ready` | ASIC2 readiness status |
| `config/asic3_ready` | ASIC3 readiness status |
| `config/asic4_ready` | ASIC4 readiness status |
| `config/asic_ready` | Overall ASIC readiness |
| `config/asic_chipup_counter` | ASIC chip-up counter |

---

## Multi-ASIC Voltage Monitors

### ASIC to Voltage Monitor Mapping

| ASIC | I2C Bus | Voltage Monitors | PMIC Functions |
|------|---------|------------------|----------------|
| ASIC1 | 8 | voltmon1-4 | VDD, AVDD/DVDD PL0, AVDD/DVDD PL1, AVCC/HVDD |
| ASIC2 | 24 | voltmon5-8 | VDD, AVDD/DVDD PL0, AVDD/DVDD PL1, AVCC/HVDD |
| ASIC3 | 40 | voltmon9-12 | VDD, AVDD/DVDD PL0, AVDD/DVDD PL1, AVCC/HVDD |
| ASIC4 | 56 | voltmon13-16 | VDD, AVDD/DVDD PL0, AVDD/DVDD PL1, AVCC/HVDD |

### PMIC Chip Types

**Chips:** MP29816 or XDPE1A2G7  
**I2C Addresses:** 0x66, 0x68, 0x6c, 0x6e (per ASIC I2C bus)

### voltmon1, voltmon5, voltmon9, voltmon13 (VDD Controllers)

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_in1_input` | PVIN1_VDD_ASIC Volt (in) | mV |
| `environment/voltmon<N>_in2_input` | ASIC_VDD Volt (out1) | mV |
| `environment/voltmon<N>_curr1_input` | PVIN1_VDD_ASIC Curr (in) | mA |
| `environment/voltmon<N>_curr3_input` | ASIC_VDD Curr (out1) | mA |
| `environment/voltmon<N>_power1_input` | PVIN1_VDD_ASIC Pwr (in) | µW |
| `environment/voltmon<N>_power3_input` | ASIC_VDD Pwr (out1) | µW |

### voltmon2, voltmon6, voltmon10, voltmon14 (AVDD/DVDD PL0 Controllers)

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_in1_input` | PVIN1_AVDD_DVDD_ASIC Volt (in) | mV |
| `environment/voltmon<N>_in2_input` | ASIC_AVDD_PL0 Volt (out1) | mV |
| `environment/voltmon<N>_in3_input` | ASIC_DVDD_PL0 Volt (out2) | mV |
| `environment/voltmon<N>_curr1_input` | PVIN1_AVDD_DVDD_ASIC Curr (in1) | mA |
| `environment/voltmon<N>_curr2_input` | PVIN1_DVDD_ASIC Curr (in2) | mA |
| `environment/voltmon<N>_curr3_input` | ASIC_AVDD_PL0 Curr (out1) | mA |
| `environment/voltmon<N>_curr4_input` | ASIC_DVDD_PL0 Curr (out2) | mA |
| `environment/voltmon<N>_power1_input` | PVIN1_AVDD_ASIC Pwr (in1) | µW |
| `environment/voltmon<N>_power2_input` | PVIN1_DVDD_ASIC Pwr (in2) | µW |
| `environment/voltmon<N>_power3_input` | ASIC_AVDD_PL0 Pwr (out1) | µW |
| `environment/voltmon<N>_power4_input` | ASIC_DVDD_PL0 Pwr (out2) | µW |

### voltmon3, voltmon7, voltmon11, voltmon15 (AVDD/DVDD PL1 Controllers)

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_in1_input` | PVIN1_AVDD_DVDD_ASIC Volt (in) | mV |
| `environment/voltmon<N>_in2_input` | ASIC_AVDD_PL1 Volt (out1) | mV |
| `environment/voltmon<N>_in3_input` | ASIC_DVDD_PL1 Volt (out2) | mV |
| `environment/voltmon<N>_curr1_input` | PVIN1_AVDD_ASIC Curr (in1) | mA |
| `environment/voltmon<N>_curr2_input` | PVIN1_DVDD_ASIC Curr (in2) | mA |
| `environment/voltmon<N>_curr3_input` | ASIC_AVDD_PL1 Curr (out1) | mA |
| `environment/voltmon<N>_curr4_input` | ASIC_DVDD_PL1 Curr (out2) | mA |

### voltmon4, voltmon8, voltmon12, voltmon16 (AVCC/HVDD Controllers)

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_in1_input` | PVIN1_AVCC_HVDD_ASIC Volt (in) | mV |
| `environment/voltmon<N>_in2_input` | ASIC_AVCC_PL0_PL1 Volt (out1) | mV |
| `environment/voltmon<N>_in3_input` | ASIC_HVDD_PL0_PL1 Volt (out2) | mV |
| `environment/voltmon<N>_curr1_input` | PVIN1_AVCC_ASIC Curr (in1) | mA |
| `environment/voltmon<N>_curr2_input` | PVIN1_HVDD_ASIC Curr (in2) | mA |
| `environment/voltmon<N>_curr3_input` | ASIC_AVCC_PL0_PL1 Curr (out1) | mA |
| `environment/voltmon<N>_curr4_input` | ASIC_HVDD_PL0_PL1 Curr (out2) | mA |

### Voltage Monitor Thresholds

| Node | Description | Unit |
|------|-------------|------|
| `environment/voltmon<N>_in<M>_crit` | Critical voltage threshold | mV |
| `environment/voltmon<N>_in<M>_lcrit` | Low critical voltage threshold | mV |
| `environment/voltmon<N>_in<M>_min` | Minimum voltage threshold | mV |
| `environment/voltmon<N>_curr<M>_crit` | Critical current threshold | mA |
| `environment/voltmon<N>_curr<M>_max` | Maximum current threshold | mA |
| `environment/voltmon<N>_power<M>_max` | Maximum power threshold | µW |

---

## COMEX Voltage Monitors

### comex_voltmon1 (CPU Power Controller)

**Chip:** MP2855  
**I2C Address:** 0x69 on bus 6

| Node | Description | Unit |
|------|-------------|------|
| `environment/comex_voltmon1_in1_input` | VDDCR INPUT VOLT | mV |
| `environment/comex_voltmon1_in2_input` | VDDCR_CPU VOLT | mV |
| `environment/comex_voltmon1_in3_input` | VDDCR_SOC VOLT | mV |
| `environment/comex_voltmon1_in2_crit` | VDDCR_CPU critical threshold | mV |
| `environment/comex_voltmon1_in2_lcrit` | VDDCR_CPU low critical threshold | mV |
| `environment/comex_voltmon1_in3_crit` | VDDCR_SOC critical threshold | mV |
| `environment/comex_voltmon1_in3_lcrit` | VDDCR_SOC low critical threshold | mV |
| `environment/comex_voltmon1_curr2_input` | VDDCR_CPU CURR | mA |
| `environment/comex_voltmon1_curr3_input` | VDDCR_SOC CURR | mA |
| `thermal/comex_voltmon1_temp1_input` | VDDCR_CPU PHASE TEMP | m°C |
| `thermal/comex_voltmon1_temp1_crit` | Critical temperature threshold | m°C |

### comex_voltmon2 (DDR Power Controller)

**Chip:** MP2975  
**I2C Address:** 0x6a on bus 6

| Node | Description | Unit |
|------|-------------|------|
| `environment/comex_voltmon2_in1_input` | VDD_MEM INPUT VOLT | mV |
| `environment/comex_voltmon2_in2_input` | VDD_MEM OUTPUT VOLT | mV |
| `environment/comex_voltmon2_in1_crit` | VDD_MEM input critical threshold | mV |
| `environment/comex_voltmon2_in2_crit` | VDD_MEM output critical threshold | mV |
| `environment/comex_voltmon2_in2_lcrit` | VDD_MEM output low critical threshold | mV |
| `environment/comex_voltmon2_curr1_input` | VDD_MEM INPUT CURR | mA |
| `environment/comex_voltmon2_curr2_input` | VDD_MEM OUTPUT CURR | mA |
| `environment/comex_voltmon2_power1_input` | VDD_MEM INPUT POWER | µW |
| `environment/comex_voltmon2_power2_input` | VDD_MEM OUTPUT POWER | µW |
| `thermal/comex_voltmon2_temp1_input` | VDD_MEM PHASE TEMP | m°C |
| `thermal/comex_voltmon2_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/comex_voltmon2_temp1_max` | Maximum temperature threshold | m°C |

---

## PDB Power Distribution

**Note:** On N6100_LD, PDB is NOT hot-pluggable (hotplug_pdbs=0)

### PDB Hotswap Controller (pdb_hotswap1)

**Chip:** LM5066i or MP5926  
**I2C Address:** 0x12 on bus 7

#### Current Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_hotswap1_curr1_input` | VinDC Curr (in) | mA |
| `environment/pdb_hotswap1_curr1_max` | Maximum current threshold | mA |

#### Voltage Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_hotswap1_in1_input` | VinDC Volt (in) | mV |
| `environment/pdb_hotswap1_in2_input` | Vout Volt (out) | mV |
| `environment/pdb_hotswap1_in1_crit` | Critical voltage threshold | mV |
| `environment/pdb_hotswap1_in1_lcrit` | Low critical voltage threshold | mV |
| `environment/pdb_hotswap1_in1_max` | Maximum voltage threshold | mV |
| `environment/pdb_hotswap1_in1_min` | Minimum voltage threshold | mV |
| `environment/pdb_hotswap1_in2_lcrit` | Output low critical threshold | mV |
| `environment/pdb_hotswap1_in2_min` | Output minimum threshold | mV |

#### Power Measurements

| Node | Description | Unit |
|------|-------------|------|
| `environment/pdb_hotswap1_power1_input` | VinDC Pwr (in) | µW |
| `environment/pdb_hotswap1_power1_max` | Maximum power threshold | µW |

### Power Converter 1 (pwr_conv1)

**Chip:** RAA228004 or MP29502  
**I2C Address:** 0x60 on bus 7

| Node | Description | Unit |
|------|-------------|------|
| `environment/pwr_conv1_in1_input` | VinDC Volt (in) | mV |
| `environment/pwr_conv1_in2_input` | Vout Volt (out) | mV |
| `environment/pwr_conv1_in1_crit` | Critical input voltage threshold | mV |
| `environment/pwr_conv1_in1_lcrit` | Low critical input voltage threshold | mV |
| `environment/pwr_conv1_in1_max` | Maximum input voltage threshold | mV |
| `environment/pwr_conv1_in1_min` | Minimum input voltage threshold | mV |
| `environment/pwr_conv1_in2_crit` | Critical output voltage threshold | mV |
| `environment/pwr_conv1_in2_lcrit` | Low critical output voltage threshold | mV |
| `environment/pwr_conv1_curr1_input` | Input current | mA |
| `environment/pwr_conv1_curr2_input` | Output current | mA |
| `environment/pwr_conv1_curr1_crit` | Critical input current threshold | mA |
| `environment/pwr_conv1_curr1_max` | Maximum input current threshold | mA |
| `environment/pwr_conv1_curr2_crit` | Critical output current threshold | mA |
| `environment/pwr_conv1_curr2_max` | Maximum output current threshold | mA |
| `environment/pwr_conv1_power1_input` | Input power | µW |
| `environment/pwr_conv1_power2_input` | Output power | µW |

### Power Converter 2 (pwr_conv2)

**Chip:** RAA228004 or MP29502  
**I2C Address:** 0x61 on bus 7

| Node | Description | Unit |
|------|-------------|------|
| `environment/pwr_conv2_in1_input` | VinDC Volt (in) | mV |
| `environment/pwr_conv2_in2_input` | Vout Volt (out) | mV |
| `environment/pwr_conv2_in1_crit` | Critical input voltage threshold | mV |
| `environment/pwr_conv2_in1_lcrit` | Low critical input voltage threshold | mV |
| `environment/pwr_conv2_in1_max` | Maximum input voltage threshold | mV |
| `environment/pwr_conv2_in1_min` | Minimum input voltage threshold | mV |
| `environment/pwr_conv2_in2_crit` | Critical output voltage threshold | mV |
| `environment/pwr_conv2_in2_lcrit` | Low critical output voltage threshold | mV |
| `environment/pwr_conv2_curr1_input` | Input current | mA |
| `environment/pwr_conv2_curr2_input` | Output current | mA |
| `environment/pwr_conv2_curr1_crit` | Critical input current threshold | mA |
| `environment/pwr_conv2_curr1_max` | Maximum input current threshold | mA |
| `environment/pwr_conv2_curr2_crit` | Critical output current threshold | mA |
| `environment/pwr_conv2_curr2_max` | Maximum output current threshold | mA |
| `environment/pwr_conv2_power1_input` | Input power | µW |
| `environment/pwr_conv2_power2_input` | Output power | µW |

---

## Thermal Sensors

### ASIC Voltage Monitor Temperatures (voltmon1-16)

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
| `thermal/pwr_conv1_temp1_input` | Power converter 1 temperature | m°C |
| `thermal/pwr_conv1_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/pwr_conv1_temp1_lcrit` | Low critical temperature threshold | m°C |
| `thermal/pwr_conv1_temp1_max` | Maximum temperature threshold | m°C |
| `thermal/pwr_conv2_temp1_input` | Power converter 2 temperature | m°C |
| `thermal/pwr_conv2_temp1_crit` | Critical temperature threshold | m°C |
| `thermal/pwr_conv2_temp1_lcrit` | Low critical temperature threshold | m°C |
| `thermal/pwr_conv2_temp1_max` | Maximum temperature threshold | m°C |

### CPU Temperature

| Node | Description | Unit |
|------|-------------|------|
| `thermal/cpu_pack` | CPU package temperature | m°C |
| `thermal/cpu_pack_crit` | Critical temperature threshold | m°C |
| `thermal/cpu_pack_max` | Maximum temperature threshold | m°C |

### SODIMM Temperatures

| Node | Description | Unit |
|------|-------------|------|
| `thermal/sodimm1_temp_input` | SODIMM 1 temperature | m°C |
| `thermal/sodimm1_temp_crit` | SODIMM 1 critical threshold | m°C |
| `thermal/sodimm1_temp_crit_hyst` | SODIMM 1 critical hysteresis | m°C |
| `thermal/sodimm1_temp_max` | SODIMM 1 maximum threshold | m°C |
| `thermal/sodimm1_temp_max_hyst` | SODIMM 1 maximum hysteresis | m°C |
| `thermal/sodimm1_temp_min` | SODIMM 1 minimum threshold | m°C |
| `thermal/sodimm2_temp_input` | SODIMM 2 temperature | m°C |
| `thermal/sodimm2_temp_crit` | SODIMM 2 critical threshold | m°C |
| `thermal/sodimm2_temp_crit_hyst` | SODIMM 2 critical hysteresis | m°C |
| `thermal/sodimm2_temp_max` | SODIMM 2 maximum threshold | m°C |
| `thermal/sodimm2_temp_max_hyst` | SODIMM 2 maximum hysteresis | m°C |
| `thermal/sodimm2_temp_min` | SODIMM 2 minimum threshold | m°C |

### Drive Temperature

| Node | Description | Unit |
|------|-------------|------|
| `thermal/drivetemp` | NVMe SSD temperature | m°C |
| `thermal/drivetemp_crit` | Critical temperature threshold | m°C |
| `thermal/drivetemp_max` | Maximum temperature threshold | m°C |
| `thermal/drivetemp_min` | Minimum temperature threshold | m°C |
| `thermal/drivetemp_sensor2` | SSD sensor 2 temperature | m°C |

---

## Alarm Sensors

### Voltage Monitor Alarms (voltmon1-16)

| Node | Description | Value |
|------|-------------|-------|
| `alarm/voltmon<N>_in<M>_alarm` | Voltage alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_curr<M>_alarm` | Current alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_temp1_crit_alarm` | Critical temperature alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_temp1_max_alarm` | Max temperature alarm | 0=clear, 1=alarm |

### COMEX Voltage Monitor Alarms

| Node | Description | Value |
|------|-------------|-------|
| `alarm/comex_voltmon1_curr2_alarm` | CPU PMIC VDDCR_CPU current alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon1_curr3_alarm` | CPU PMIC VDDCR_SOC current alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon1_in1_alarm` | CPU PMIC input voltage alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon1_in2_alarm` | CPU PMIC VDDCR_CPU voltage alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon1_in3_alarm` | CPU PMIC VDDCR_SOC voltage alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon1_temp1_crit_alarm` | CPU PMIC critical temp alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_curr1_alarm` | DDR PMIC input current alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_curr2_alarm` | DDR PMIC output current alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_in1_alarm` | DDR PMIC input voltage alarm | 0=clear, 1=alarm |
| `alarm/comex_voltmon2_in2_alarm` | DDR PMIC output voltage alarm | 0=clear, 1=alarm |
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
| `alarm/pwr_conv1_curr1_alarm` | Power converter 1 input current alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv1_curr2_alarm` | Power converter 1 output current alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv1_in1_alarm` | Power converter 1 input voltage alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv1_in2_alarm` | Power converter 1 output voltage alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv1_power1_alarm` | Power converter 1 power alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv1_temp1_crit_alarm` | Power converter 1 critical temp alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv1_temp1_max_alarm` | Power converter 1 max temp alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv2_curr1_alarm` | Power converter 2 input current alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv2_curr2_alarm` | Power converter 2 output current alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv2_in1_alarm` | Power converter 2 input voltage alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv2_in2_alarm` | Power converter 2 output voltage alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv2_power1_alarm` | Power converter 2 power alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv2_temp1_crit_alarm` | Power converter 2 critical temp alarm | 0=clear, 1=alarm |
| `alarm/pwr_conv2_temp1_max_alarm` | Power converter 2 max temp alarm | 0=clear, 1=alarm |

### SODIMM Alarms

| Node | Description | Value |
|------|-------------|-------|
| `thermal/sodimm1_temp_crit_alarm` | SODIMM 1 critical temp alarm | 0=clear, 1=alarm |
| `thermal/sodimm1_temp_max_alarm` | SODIMM 1 max temp alarm | 0=clear, 1=alarm |
| `thermal/sodimm1_temp_min_alarm` | SODIMM 1 min temp alarm | 0=clear, 1=alarm |
| `thermal/sodimm2_temp_crit_alarm` | SODIMM 2 critical temp alarm | 0=clear, 1=alarm |
| `thermal/sodimm2_temp_max_alarm` | SODIMM 2 max temp alarm | 0=clear, 1=alarm |
| `thermal/sodimm2_temp_min_alarm` | SODIMM 2 min temp alarm | 0=clear, 1=alarm |

---

## System Control

### Multi-ASIC Health and Control

| Node | Description | Access |
|------|-------------|--------|
| `system/asic_health` | ASIC1 health status | RO |
| `system/asic2_health` | ASIC2 health status | RO |
| `system/asic3_health` | ASIC3 health status | RO |
| `system/asic4_health` | ASIC4 health status | RO |
| `system/asic_reset` | ASIC reset control | RW |
| `system/asic_pg_fail` | ASIC power good fail | RO |
| `system/reset_asic_thermal` | Thermal ASIC reset | RW |

### Power Control

| Node | Description | Access |
|------|-------------|--------|
| `system/pwr_cycle` | System power cycle | WO |
| `system/pwr_down` | System power down | WO |
| `system/aux_pwr_cycle` | Auxiliary power cycle | WO |
| `system/graceful_pwr_off` | Graceful power off | RW |
| `system/pwr_converter_prog_en` | Power converter programming enable | RW |
| `system/hotswap_alert` | Hotswap alert status | RO |

### CPLD Information

| Node | Description | Access |
|------|-------------|--------|
| `system/cpld1_version` | CPLD1 version | RO |
| `system/cpld1_version_min` | CPLD1 minimum version | RO |
| `system/cpld1_pn` | CPLD1 part number | RO |
| `system/cpld2_version` | CPLD2 version | RO |
| `system/cpld2_version_min` | CPLD2 minimum version | RO |
| `system/cpld2_pn` | CPLD2 part number | RO |

### Leakage Detection

| Node | Description | Access |
|------|-------------|--------|
| `system/leakage1` | Leakage sensor 1 status | RO |
| `system/leakage2` | Leakage sensor 2 status | RO |

### Cable Cartridge Status

| Node | Description | Access |
|------|-------------|--------|
| `system/cartridge1` | Cartridge 1 status | RO |
| `system/cartridge2` | Cartridge 2 status | RO |
| `system/cartridge3` | Cartridge 3 status | RO |
| `system/cartridge4` | Cartridge 4 status | RO |

### BMC Interface

| Node | Description | Access |
|------|-------------|--------|
| `system/bmc_present` | BMC presence | RO |
| `system/bmc_to_cpu_ctrl` | BMC to CPU control | RW |
| `system/boot_completed` | Boot completed status | RO |

### eRoT (External Root of Trust)

| Node | Description | Access |
|------|-------------|--------|
| `system/cpu_erot_present` | CPU eRoT presence | RO |
| `system/cpu_erot_reset` | CPU eRoT reset control | RW |
| `system/cpu_mctp_ready` | CPU MCTP ready status | RO |
| `system/reset_cpu_erot` | Reset CPU eRoT | WO |

### CPU Control

| Node | Description | Access |
|------|-------------|--------|
| `system/cpu_power_off_ready` | CPU power off ready | RO |
| `system/cpu_shutdown_req` | CPU shutdown request | RW |

### MCU Reset

| Node | Description | Access |
|------|-------------|--------|
| `system/mcu1_reset` | MCU1 reset control | RW |
| `system/mcu2_reset` | MCU2 reset control | RW |

### BIOS Status

| Node | Description | Access |
|------|-------------|--------|
| `system/bios_active_image` | Active BIOS image | RO |
| `system/bios_start_retry` | BIOS start retry | RO |
| `system/bios_status` | BIOS status | RO |
| `system/port80` | Port 80 POST code | RO |

### JTAG

| Node | Description | Access |
|------|-------------|--------|
| `system/jtag_enable` | JTAG enable | RW |
| `system/jtag_cap` | JTAG capability | RO |
| `jtag/jtag_enable` | JTAG enable (alternative) | RW |

### NVMe

| Node | Description | Access |
|------|-------------|--------|
| `system/nvme_present` | NVMe SSD presence | RO |

### Reset Attributes

| Node | Description | Access |
|------|-------------|--------|
| `system/reset_aux_pwr_or_reload` | Reset cause: aux power or reload | RO |

---

## LEDs

### Power LED

| Node | Description | Access |
|------|-------------|--------|
| `led/led_power` | Power LED state | RW |
| `led/led_power_amber` | Power LED amber brightness | RW |
| `led/led_power_amber_delay_off` | Amber LED delay off (blink) | RW |
| `led/led_power_amber_delay_on` | Amber LED delay on (blink) | RW |
| `led/led_power_amber_trigger` | Amber LED trigger | RW |
| `led/led_power_green` | Power LED green brightness | RW |
| `led/led_power_green_delay_off` | Green LED delay off (blink) | RW |
| `led/led_power_green_delay_on` | Green LED delay on (blink) | RW |
| `led/led_power_green_trigger` | Green LED trigger | RW |
| `led/led_power_capability` | Power LED capabilities | RO |
| `led/led_power_state` | Power LED state conversion | RO |

### Status LED

| Node | Description | Access |
|------|-------------|--------|
| `led/led_status` | Status LED state | RW |
| `led/led_status_amber` | Status LED amber brightness | RW |
| `led/led_status_amber_delay_off` | Amber LED delay off (blink) | RW |
| `led/led_status_amber_delay_on` | Amber LED delay on (blink) | RW |
| `led/led_status_amber_trigger` | Amber LED trigger | RW |
| `led/led_status_green` | Status LED green brightness | RW |
| `led/led_status_green_delay_off` | Green LED delay off (blink) | RW |
| `led/led_status_green_delay_on` | Green LED delay on (blink) | RW |
| `led/led_status_green_trigger` | Green LED trigger | RW |
| `led/led_status_capability` | Status LED capabilities | RO |
| `led/led_status_state` | Status LED state conversion | RO |

### UID LED

| Node | Description | Access |
|------|-------------|--------|
| `led/led_uid` | UID LED state | RW |
| `led/led_uid_blue` | UID LED blue brightness | RW |
| `led/led_uid_blue_delay_off` | Blue LED delay off (blink) | RW |
| `led/led_uid_blue_delay_on` | Blue LED delay on (blink) | RW |
| `led/led_uid_blue_trigger` | Blue LED trigger | RW |
| `led/led_uid_capability` | UID LED capabilities | RO |
| `led/led_uid_state` | UID LED state conversion | RO |

---

## EEPROM

### VPD (Vital Product Data)

| Node | Description | Access |
|------|-------------|--------|
| `eeprom/vpd_info` | VPD EEPROM device (I2C 1-0051) | RO |
| `eeprom/vpd_data` | VPD parsed data | RO |

### Switch Board (SWB)

| Node | Description | Access |
|------|-------------|--------|
| `eeprom/swb_info` | SWB EEPROM device (I2C 14-0051) | RO |
| `eeprom/swb_data` | SWB parsed data | RO |

### Cable Cartridge EEPROMs

| Node | Description | I2C Bus |
|------|-------------|---------|
| `eeprom/cable_cartridge1_eeprom` | Cartridge 1 EEPROM device | 68-0050 |
| `eeprom/cable_cartridge1_eeprom_data` | Cartridge 1 parsed data | |
| `eeprom/cable_cartridge2_eeprom` | Cartridge 2 EEPROM device | 69-0050 |
| `eeprom/cable_cartridge2_eeprom_data` | Cartridge 2 parsed data | |
| `eeprom/cable_cartridge3_eeprom` | Cartridge 3 EEPROM device | 70-0050 |
| `eeprom/cable_cartridge3_eeprom_data` | Cartridge 3 parsed data | |
| `eeprom/cable_cartridge4_eeprom` | Cartridge 4 EEPROM device | 71-0050 |
| `eeprom/cable_cartridge4_eeprom_data` | Cartridge 4 parsed data | |

---

## Events

### eRoT Events

| Node | Description | Value |
|------|-------------|-------|
| `events/erot1_ap` | eRoT AP status | Event status |
| `events/erot1_error` | eRoT error event | Error status |

### Leakage Events

| Node | Description | Value |
|------|-------------|-------|
| `events/leakage1` | Leakage sensor 1 event | 0=no leak, 1=leak |
| `events/leakage2` | Leakage sensor 2 event | 0=no leak, 1=leak |

### Power Events

| Node | Description | Value |
|------|-------------|-------|
| `events/graceful_pwr_off` | Graceful power off event | Event status |
| `events/power_button` | Power button press event | Event status |

**Note:** Unlike SN5810_LD, N6100_LD does NOT have PDB hot-plug events (no `events/pdb<N>`)

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

### Power Management ICs (PMICs)

| Component | Chip | Vendor | I2C Address | I2C Bus | Linux Driver | Description |
|-----------|------|--------|-------------|---------|--------------|-------------|
| ASIC PMIC (VDD) | MP29816 | MPS | 0x66 | 8, 24, 40, 56 | mp29816 | ASIC VDD power |
| ASIC PMIC (AVDD/DVDD PL0) | MP29816 | MPS | 0x68 | 8, 24, 40, 56 | mp29816 | ASIC AVDD/DVDD PL0 power |
| ASIC PMIC (AVDD/DVDD PL1) | MP29816 | MPS | 0x6c | 8, 24, 40, 56 | mp29816 | ASIC AVDD/DVDD PL1 power |
| ASIC PMIC (AVCC/HVDD) | MP29816 | MPS | 0x6e | 8, 24, 40, 56 | mp29816 | ASIC AVCC/HVDD power |
| CPU PMIC | MP2855 | MPS | 0x69 | 6 | mp2855 | CPU VDDCR_CPU/VDDCR_SOC power |
| DDR PMIC | MP2975 | MPS | 0x6a | 6 | mp2975 | DDR VDD_MEM power |

**Alternative ASIC PMIC:** XDPE1A2G7 (Infineon) at same addresses - driver: xdpe1a2g7

### Power Distribution Board (PDB)

| Component | Chip | Vendor | I2C Address | I2C Bus | Linux Driver | Description |
|-----------|------|--------|-------------|---------|--------------|-------------|
| PDB Hotswap | LM5066I | Texas Instruments | 0x12 | 7 | lm5066i | Hot-swap controller |
| Power Converter 1 | RAA228004 | Renesas | 0x60 | 7 | raa228004 | 48V to 12V DC-DC converter |
| Power Converter 2 | RAA228004 | Renesas | 0x61 | 7 | raa228004 | 48V to 12V DC-DC converter |

**Alternative Components:**
- PDB Hotswap: MP5926 (MPS) - driver: mp5926
- Power Converters: MP29502 (MPS) - driver: mp29502

### Temperature Sensors

| Component | Chip | Vendor | I2C Address | I2C Bus | Linux Driver | Description |
|-----------|------|--------|-------------|---------|--------------|-------------|
| SODIMM 1 Temp | JC42.4 | JEDEC | 0x1a | 2 | jc42 | DDR SODIMM temperature |
| SODIMM 2 Temp | JC42.4 | JEDEC | 0x1b | 2 | jc42 | DDR SODIMM temperature |
| CPU Temp | K10Temp | AMD | PCI | - | k10temp | CPU package temperature |
| SSD Temp | NVMe | - | PCI | - | nvme | NVMe SSD temperature |

### EEPROM Devices

| Component | Chip | I2C Address | I2C Bus | Linux Driver | Description |
|-----------|------|-------------|---------|--------------|-------------|
| VPD EEPROM | 24C512 | 0x51 | 1 | at24 | 64KB Vital Product Data |
| SWB EEPROM | 24C512 | 0x51 | 14 | at24 | 64KB Switch Board data |
| Cable Cartridge 1 | 24C02 | 0x50 | 68 | at24 | 256B Cartridge VPD |
| Cable Cartridge 2 | 24C02 | 0x50 | 69 | at24 | 256B Cartridge VPD |
| Cable Cartridge 3 | 24C02 | 0x50 | 70 | at24 | 256B Cartridge VPD |
| Cable Cartridge 4 | 24C02 | 0x50 | 71 | at24 | 256B Cartridge VPD |

---

## Chip Details from sensors.conf

The following chip configurations are defined in `n61xxld_sensors.conf`:

### ASIC Power Controllers

#### MP29816 (MPS) - Primary

| Chip Pattern | I2C Address | Function |
|--------------|-------------|----------|
| `mp29816-i2c-*-66` | 0x66 | PMIC-1: VDD_ASIC power |
| `mp29816-i2c-*-68` | 0x68 | PMIC-2: AVDD/DVDD PL0 power |
| `mp29816-i2c-*-6c` | 0x6c | PMIC-3: AVDD/DVDD PL1 power |
| `mp29816-i2c-*-6e` | 0x6e | PMIC-4: AVCC/HVDD power |

#### XDPE1A2G7 (Infineon) - Alternative

| Chip Pattern | I2C Address | Function |
|--------------|-------------|----------|
| `xdpe1a2g7-i2c-*-66` | 0x66 | PMIC-1: VDD_ASIC power |
| `xdpe1a2g7-i2c-*-68` | 0x68 | PMIC-2: AVDD/DVDD PL0 power |
| `xdpe1a2g7-i2c-*-6c` | 0x6c | PMIC-3: AVDD/DVDD PL1 power |
| `xdpe1a2g7-i2c-*-6e` | 0x6e | PMIC-4: AVCC/HVDD power |

### Hot Swap Controllers

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `lm5066i-i2c-*-12` | 0x12 | Texas Instruments | PDB HSC VinDC |
| `mp5926-i2c-*-12` | 0x12 | MPS | PDB HSC VinDC (alternative) |

### Power Converters

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `raa228004-i2c-*-60` | 0x60 | Renesas | PDB-1 Conv (48V to 12V) |
| `raa228004-i2c-*-61` | 0x61 | Renesas | PDB-2 Conv (48V to 12V) |
| `mp29502-i2c-*-60` | 0x60 | MPS | PDB-1 Conv (alternative) |
| `mp29502-i2c-*-61` | 0x61 | MPS | PDB-2 Conv (alternative) |

### CPU Power Controller

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `mp2855-i2c-*-69` | 0x69 | MPS | CPU VDDCR_CPU/VDDCR_SOC |

**Registers:**
- `in1`: VDDCR INPUT VOLT
- `in2`: VDDCR_CPU VOLT (out)
- `in3`: VDDCR_SOC VOLT (out2)
- `temp1`: VDDCR_CPU PHASE TEMP
- `temp2`: VDDCR_SOC PHASE TEMP
- `curr1`: VDDCR_CPU CURR
- `curr2`: VDDCR_SOC CURR

### DDR Power Controller

| Chip Pattern | I2C Address | Vendor | Function |
|--------------|-------------|--------|----------|
| `mp2975-i2c-*-6a` | 0x6a | MPS | DDR VDD_MEM |

**Registers:**
- `in1`: VDD_MEM INPUT VOLT
- `in2`: VDD_MEM OUTPUT VOLT
- `temp1`: VDD_MEM PHASE TEMP
- `curr1`: VDD_MEM INPUT CURR
- `curr2`: VDD_MEM OUTPUT CURR
- `power1`: VDD_MEM INPUT POWER
- `power2`: VDD_MEM OUTPUT POWER

### CPU Temperature Sensor

| Chip Pattern | Vendor | Function |
|--------------|--------|----------|
| `k10temp-pci-*` | AMD | CPU PACKAGE TEMP, CPU DIE0 TEMP |

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
- Configuration: `usr/etc/hw-management-sensors/n61xxld_sensors.conf`
- Labels: `usr/etc/hw-management-sensors/n61xxld_sensors_labels.json`

---

**End of Document**
