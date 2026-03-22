# SN6600_LD Hardware Interfaces Documentation

**Platform:** SN6600_LD  
**SKU:** HI193  
**Board Type:** VMOD0025 (`hw-management.sh` `check_system` branch)  
**ASIC count:** 1 (`set_asic_pci()` default branch for HI193 writes `asic_num` = 1)  
**ASIC PCI filter:** `lspci -nn` match `cf82|cf84` (`spc5_pci_id|spc6_pci_id` for HI193)  
**CPU Type:** AMD  
**System Type:** Liquid-Cooled  
**Document Version:** 1.2  
**Last Updated:** March 23, 2026

---

## Table of Contents

1. [Platform Overview](#platform-overview)
2. [System Configuration](#system-configuration)
3. [ASIC Voltage Monitors](#asic-voltage-monitors)
4. [COMEX Voltage Monitors](#comex-voltage-monitors)
5. [PDB Power Distribution](#pdb-power-distribution)
6. [Thermal Sensors](#thermal-sensors)
7. [Alarm Sensors](#alarm-sensors)
8. [System Control](#system-control)
9. [LEDs](#leds)
10. [JTAG](#jtag)
11. [EEPROM](#eeprom)
12. [Events](#events)
13. [Watchdog](#watchdog)
14. [Power Calculation](#power-calculation)
15. [Chip and Devtree Reference](#chip-and-devtree-reference)

---

## Platform Overview

The SN6600_LD liquid-cooled switch system has the following
characteristics (from `hw-management.sh` `sn66xxld_specific()` for SKU HI193 and
`tests/system_tree/hw-management-tree-SN6600_LD.txt`):

| Component | Value | Description |
|-----------|-------|-------------|
| ASICs | 1 | Single ASIC (`config/asic_num` = 1) |
| CPLDs | 4 | System control CPLDs (`config/cpld_num` = 4) |
| Leakage (`config/leakage_counter`) | 2 | `sn66xxld_specific()` sets `leakage_count=2`; `set_config_data()` writes it to `config/leakage_counter` |
| `system/leakage*` (tree sample) | 5 symlinks | `hw-management-thermal-events.sh` links each hwmon `leakageN` that exists, up to **8** (`max_leakage`); the captured tree lists `leakage1`..`leakage5` |
| Hot-plug PDBs | 2 | `config/hotplug_pdbs` = 2 |
| PSUs | 0 | No traditional PSUs (`hotplug_psus` = 0) |
| Fans | 0 | Liquid-cooled (`hotplug_fans` = 0) |
| ASIC voltage monitors (sysfs sample) | 19 | `voltmon1`-`14`, `voltmon16`-`20` (see [ASIC Voltage Monitors](#asic-voltage-monitors)) |
| COMEX voltage monitors | 2 | `comex_voltmon1`, `comex_voltmon2` |
| Power boards | 2 | `pwr_brd_num` = 2 for VMOD0025 / HI193 (`hw-management.sh`) |

---

## System Configuration

**Base Path:** `/var/run/hw-management/`

### Configuration Files

| Node | Description | Value (validated tree) |
|------|-------------|------------------------|
| `config/asic_num` | Number of ASICs | 1 |
| `config/cpld_num` | Number of CPLDs | 4 |
| `config/hotplug_pdbs` | Hot-plug PDB count | 2 |
| `config/hotplug_psus` | Hot-plug PSU count | 0 |
| `config/hotplug_fans` | Hot-plug fan count | 0 |
| `config/leakage_counter` | Leakage sensor count | 2 |
| `config/cpu_type` | CPU type | `0x1944` (AMD, tree sample) |
| `config/i2c_bus_offset` | I2C bus offset | 0 |
| `config/i2c_comex_mon_bus_default` | COMEX I2C bus index for udev filtering | `sn66xxld_specific()` writes **6** (`hw-management.sh`); validated tree shows COMEX PMICs under sysfs `i2c-5` (Linux adapter index can differ from this config token) |
| `config/lm_sensors_config` | Sensors file | `sn66xxld_sensors.conf` |
| `config/named_busses` | Logical bus map | From `sn66xxld_named_busses` in `hw-management.sh`: `asic1 5 pwr1 7 pwr2 8 vr1 16 vr2 17 vpd 1 cpu-vr 6` |

**Note:** `config/lm_sensors_config` is a symlink to
`/etc/hw-management-sensors/sn66xxld_sensors.conf` on the captured system.

**Note:** `sn66xxld_specific()` does **not** set `lm_sensors_labels` (unlike
`n61xxld_specific()` which sets `n61xxld_sensors_labels.json`). There is no
`sn66xxld_sensors_labels.json` in this repository tree.

### ASIC Configuration

| Node | Description |
|------|-------------|
| `config/asic1_pci_bus_id` | ASIC1 PCI bus ID |
| `config/asic_chipup_counter` | ASIC chip-up counter |

---

## ASIC Voltage Monitors

### Exposed indexes

The validated sysfs tree (`hw-management-tree-SN6600_LD.txt`) lists **19**
ASIC PMIC channels: `voltmon1` through `voltmon14` and `voltmon16` through
`voltmon20`. There is **no** `voltmon15` symlink in that capture.

**Repository devtree:** `hw-management-devtree.sh` arrays `sn66xxld_swb_alternatives`
and `sn66xxld_port_alternatives` define **voltmon1** through **voltmon20**
(including **voltmon15** at `mp29816 0x66 16 voltmon15` and Infineon
`xdpe1a2g7b` alternates at the same addresses). A missing `voltmon15` in a
tree dump is therefore a bring-up or capture artifact, not absence from the
product tables in code.

`sn66xxld_sensors.conf` lists **20** MP29816 ASIC PMIC chip sections (PMIC-1
through PMIC-20) on logical I2C buses **15** and **16**.

**Alternative VR:** same script arrays map **xdpe1a2g7b** at the same I2C
addresses as MP29816 for ASIC rails (primary MP29816 in `sn66xxld_sensors.conf`).

### Typical channel pattern (voltmon with dual outputs)

For PMICs with two regulated outputs, the virtual `environment` and `alarm`
nodes follow the usual PMBus-style mapping (example from tree: `curr2` maps to
chip `curr3`, `curr3` to chip `curr4`, and similarly for power). Use the
following pattern for each exposed `voltmon<N>`:

| Node pattern | Description | Unit |
|--------------|-------------|------|
| `environment/voltmon<N>_in1_input` | Input (PVIN) voltage | mV |
| `environment/voltmon<N>_in2_input` | Output 1 voltage | mV |
| `environment/voltmon<N>_in3_input` | Output 2 voltage | mV |
| `environment/voltmon<N>_curr1_input` | Input current | mA |
| `environment/voltmon<N>_curr2_input` | Output 1 current | mA |
| `environment/voltmon<N>_curr3_input` | Output 2 current | mA |
| `environment/voltmon<N>_power1_input` | Input power | µW |
| `environment/voltmon<N>_power2_input` | Output 1 power | µW |
| `environment/voltmon<N>_power3_input` | Output 2 power | µW |
| `environment/voltmon<N>_*_crit` / `_lcrit` / `_max` / `_min` | Thresholds | per channel |

**PMIC type (sensors.conf):** MP29816 on I2C buses **15** and **16** (see chip
entries `mp29816-i2c-15-*` and `mp29816-i2c-16-*` in `sn66xxld_sensors.conf`).

**voltmon1 (PMIC-1, VDD):** Single main output style (per labels in
`sn66xxld_sensors.conf`: PVIN1_VDD_ASIC, ASIC_VDD).

---

## COMEX Voltage Monitors

Symlinks under `environment/`, `thermal/`, and `alarm/` are created by
`hw-management-chassis-events.sh` using **label-based** mapping
(`find_sensor_by_label` and `VOLTMON_SENS_LABEL` / `CURR_SENS_LABEL` /
`POWER_SENS_LABEL`); virtual `in1`..`in3`, `curr1`..`curr3`, etc. are not
always equal to the hwmon attribute index. Use the tree targets when in doubt.

### comex_voltmon1 (CPU power)

**Chip:** `mp2845-i2c-*-69` in `sn66xxld_sensors.conf`; devtree
`sn66xxld_platform_alternatives`: `mp2845 0x69 5 comex_voltmon1`.

**Labels (sensors.conf):** `in0` VDDCR in, `in1` VDDCR_CPU (out1), `in3`
VDDCR_SOC (out2); `temp1` / `temp3` CPU / SOC phase temps; `curr1` / `curr3`
CPU / SOC currents.

| Node (present in tree sample) | Unit |
|-------------------------------|------|
| `environment/comex_voltmon1_in2_input`, `in3_input`, `curr2_input`, `curr3_input` | mV / mA |
| `thermal/comex_voltmon1_temp1_input` | m°C |

### comex_voltmon2 (DDR power)

**Chip:** `mp2975-i2c-*-6a`; devtree: `mp2975 0x6a 5 comex_voltmon2`.

**Labels (sensors.conf):** `in1` VDD_MEM in, `in2` VDD_MEMIO out1, `in3` VDD_MEM
out2; matching power and current labels.

| Node (present in tree sample) | Unit |
|-------------------------------|------|
| `environment/comex_voltmon2_in1_input` .. `in3_input`, `curr1_input` .. `curr3_input`, `power1_input` .. `power3_input` | mV / mA / µW |
| `thermal/comex_voltmon2_temp1_input`, `temp1_crit`, `temp1_max` | m°C |

---

## PDB Power Distribution

Two independent PDB domains: **PDB-1** on I2C bus **6**, **PDB-2** on I2C bus
**7** (see `sn66xxld_sensors.conf`).

### PDB hotswap (pdb_hotswap1, pdb_hotswap2)

**Chips:** LM5066i or MP5926 at **0x12** on buses **6** and **7** (per
`sn66xxld_sensors.conf`). Second PDB uses the same chip types on bus **7**
(tree sample).

Second power board instances follow `pwr_brd_num` / `pwr_brd_bus_offset` in
`hw-management.sh` (HI193: `pwr_brd_bus_offset` = 1); static
`sn66xxld_pwr_alternatives` in `hw-management-devtree.sh` lists bus **6**
entries only, with additional PDB devices supplied via SMBIOS / BOM mapping.

| Node pattern (from tree) | Unit |
|--------------------------|------|
| `environment/pdb_hotswap<N>_curr1_input`, `curr1_max` | mA |
| `environment/pdb_hotswap<N>_in1_input`, `in1_crit`, `in1_lcrit`, `in1_max`, `in1_min` | mV |
| `environment/pdb_hotswap<N>_in2_input`, `in2_lcrit`, `in2_min` | mV (Vout via driver `in3` sysfs) |
| `environment/pdb_hotswap<N>_power1_input`, `power1_max` | µW |

### PDB power converters (pdb_pwr_conv1, pdb_pwr_conv2)

**Chips:** RAA228004 at **0x60**, or MP29502 at **0x2e** (alternatives in
sensors.conf)

| Node pattern | Description | Unit |
|--------------|-------------|------|
| `environment/pdb_pwr_conv<N>_in1_input` | VinDC | mV |
| `environment/pdb_pwr_conv<N>_in2_input` | Vout | mV |
| `environment/pdb_pwr_conv<N>_curr1_input` | Input current | mA |
| `environment/pdb_pwr_conv<N>_curr2_input` | Output current | mA |
| `environment/pdb_pwr_conv<N>_power1_input` | Input power | µW |
| `environment/pdb_pwr_conv<N>_power2_input` | Output power | µW |

---

## Thermal Sensors

### ASIC PMIC temperatures

| Node pattern | Description | Unit |
|--------------|-------------|------|
| `thermal/voltmon<N>_temp1_input` | PMIC temperature | m°C |
| `thermal/voltmon<N>_temp1_crit` | Critical threshold | m°C |
| `thermal/voltmon<N>_temp1_max` | Maximum threshold | m°C |

(For each exposed `voltmon<N>` index in the tree.)

### COMEX temperatures

| Node | Description | Unit |
|------|-------------|------|
| `thermal/comex_voltmon1_temp1_input` | CPU PMIC (tree sample; no `temp1_crit` linked) | m°C |
| `thermal/comex_voltmon2_temp1_input` | DDR PMIC | m°C |
| `thermal/comex_voltmon2_temp1_crit` | DDR critical | m°C |
| `thermal/comex_voltmon2_temp1_max` | DDR max | m°C |

### PDB temperatures

| Node | Description | Unit |
|------|-------------|------|
| `thermal/pdb_hotswap1_temp1_input` | PDB1 hotswap temp | m°C |
| `thermal/pdb_hotswap2_temp1_input` | PDB2 hotswap temp | m°C |
| `thermal/pdb_pwr_conv1_temp1_input` | PDB1 converter temp | m°C |
| `thermal/pdb_pwr_conv2_temp1_input` | PDB2 converter temp | m°C |

**Note:** `sn66xxld_sensors.conf` also defines TMP451 PDB temp chips at **0x4c**
on buses **6** and **7**; the validated tree does not show separate
`pdb_mosfet_amb` style symlinks (PDB temp is carried on the hotswap /
converter channels above).

### CPU, SODIMM, storage

| Node | Description | Unit |
|------|-------------|------|
| `thermal/cpu_pack` | CPU package | m°C |
| `thermal/sodimm1_temp_input` | SODIMM 1 (tree: `10-0052`) | m°C |
| `thermal/sodimm2_temp_input` | SODIMM 2 (tree: `10-0053`) | m°C |
| `thermal/drivetemp` | NVMe temperature | m°C |
| `thermal/drivetemp_sensor1` | NVMe sensor 2 | m°C |
| `thermal/drivetemp_sensor2` | NVMe sensor 3 | m°C |

SODIMM sensors use **JC42** at **0x52** and **0x53** on I2C bus **10** per the
validated tree (see `jc42-i2c-*-52` / `*-53` in `sn66xxld_sensors.conf`).

---

## Alarm Sensors

### Voltmon alarms

| Node pattern | Description | Value |
|--------------|-------------|-------|
| `alarm/voltmon<N>_in<M>_alarm` | Voltage alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_curr<M>_alarm` | Current alarm | 0=clear, 1=alarm |
| `alarm/voltmon<N>_temp1_crit_alarm` | Critical temp | 0=clear, 1=alarm |
| `alarm/voltmon<N>_temp1_max_alarm` | Max temp | 0=clear, 1=alarm |

### COMEX alarms

`alarm/comex_voltmon1_*` and `alarm/comex_voltmon2_*` are created by the same
`hw-management-chassis-events.sh` voltmon path as ASIC voltmons (see tree
listing for the exact set on SN6600_LD).

### PDB alarms

| Node pattern | Description |
|--------------|-------------|
| `alarm/pdb_hotswap<N>_*` | Per-PDB hotswap alarms |
| `alarm/pdb_pwr_conv<N>_*` | Per-PDB converter alarms |

### SODIMM alarms

`thermal/sodimm<N>_temp_*_alarm` nodes (as in tree).

---

## System Control

Representative nodes present under `system/` in the validated tree:

| Node | Description | Access |
|------|-------------|--------|
| `system/asic_health` | ASIC health | RO |
| `system/asic_reset` | ASIC reset | RW |
| `system/asic_pg_fail` | ASIC power-good fail | RO |
| `system/pwr_cycle` / `pwr_down` | Power control | WO |
| `system/aux_pwr_cycle` | Aux power cycle | WO |
| `system/graceful_pwr_off` | Graceful power off | RW |
| `system/cpld1_version` ... `cpld4_version` | CPLD versions | RO |
| `system/leakage1` ... `system/leakage5` | Leakage GPIO / status | RO |
| `system/cpu_erot_present` | CPU eRoT presence | RO |
| `system/cpu_mctp_ready` | MCTP ready | RO |
| `system/bmc_present` | BMC presence | RO |
| `system/jtag_enable` | JTAG enable | RW |

**Note:** `config/leakage_counter` is **2** and matches event coverage:
`hw-management.sh` initializes `events/leakage1` and `events/leakage2` only
(indices 1..`leakage_count`). Extra `system/leakage3`..`leakage5` symlinks
appear when mlxreg-io exposes those hwmon attributes; they are still readable
under `system/` but are outside the `leakage_counter` / `events/leakage<N>`
contract unless platform init is extended.

---

## LEDs

Nodes under `led/` match `hw-management-tree-SN6600_LD.txt` (power / status /
UID, including `*_amber` / `*_green` / `*_blue` brightness, delays, triggers,
`led_*_capability`, `led_*_state`).

---

## JTAG

Per tree sample under `jtag/`:

| Node |
|------|
| `jtag/jtag_enable` |
| `jtag/jtag_tck`, `jtag_tdi`, `jtag_tdo`, `jtag_tms` |

Duplicate `system/jtag_enable` exists under `system/` in the same tree.

---

## EEPROM

| Node | Description |
|------|-------------|
| `eeprom/vpd_info` | Chassis VPD (tree: `1-0051`) |
| `eeprom/vpd_data` | Parsed VPD |
| `eeprom/swb_info` | Switch board (tree: `24-0051`) |
| `eeprom/swb_data` | Parsed SWB data |

---

## Events

| Node | Description | Values |
|------|-------------|--------|
| `events/pdb1` | PDB1 hot-plug | 0/1 |
| `events/pdb2` | PDB2 hot-plug | 0/1 |
| `events/leakage1` | Leakage 1 | 0=no leak, 1=leak |
| `events/leakage2` | Leakage 2 | 0=no leak, 1=leak |

**Note:** With `leakage_counter` = 2, only `events/leakage1` and
`events/leakage2` are created by `hw-management.sh`. There are no
`events/leakage3`..`5` in that configuration even if `system/leakage3`..`5`
exist.

---

## Watchdog

`hw-management-chassis-events.sh` (udev `add` for `watchdog`) reads
`.../identity`; for names `mlx-wdt-*` it sets `wd_sub` to the substring after
`mlx-wdt-` (`cut -c 9-`) and links attributes under
`$hw_management_path/watchdog/$wd_sub/`.

The SN6600_LD tree sample shows `watchdog/main/` and `watchdog/aux/`, matching
that rule for identities `mlx-wdt-main` and `mlx-wdt-aux`. Kernel device paths
under `/sys/devices/.../watchdog/watchdog1` are separate from these UI paths.

Each UI subdirectory contains: `identity`, `state`, `status`, `timeout`,
`timeleft` (if present), `nowayout`, `bootstatus`.

---

## Power Calculation

| Node | Description |
|------|-------------|
| `power/pwr_consum` | Symlink to `hw-management-power-helper.sh` (tree sample) |
| `power/pwr_sys` | Symlink to `hw-management-power-helper.sh` (tree sample) |

---

## Chip and Devtree Reference

| Item | Source |
|------|--------|
| Switch-board VR naming `voltmon1`..`20`, MP29816 / xdpe1a2g7b | `sn66xxld_swb_alternatives`, `sn66xxld_port_alternatives` in `hw-management-devtree.sh` |
| PDB1 PDB devices | `sn66xxld_pwr_alternatives` (bus 6); second PDB from `pwr_brd_*` config |
| Platform / COMEX / SODIMM / VPD | `sn66xxld_platform_alternatives` |
| LM sensors chip list | `usr/etc/hw-management-sensors/sn66xxld_sensors.conf` |
| Udev symlink creation | `usr/usr/bin/hw-management-chassis-events.sh` |
| COMEX bus filter | Same script uses `config/i2c_comex_mon_bus_default` + `i2c_bus_offset` |

---

## Source Files

- System tree:
  `tests/system_tree/hw-management-tree-SN6600_LD.txt`
- Sensors:
  `usr/etc/hw-management-sensors/sn66xxld_sensors.conf`
- Platform init:
  `usr/usr/bin/hw-management.sh` (`sn66xxld_specific`, `check_system` VMOD0025,
  `set_asic_pci` HI193, `set_cpu_type` / board helpers as applicable)
- Devtree / BOM mapping:
  `usr/usr/bin/hw-management-devtree.sh` (HI193 / `sn66xxld_*` alternatives)

---

**End of Document**
