# SN6600 Hardware Interfaces Documentation

**Platform:** SN6600  
**SKU:** HI186  
**Board Type:** VMOD0025 (`hw-management.sh` `check_system` branch)  
**ASIC count:** 1 (`set_asic_pci()` default branch for HI186 writes `asic_num` = 1)  
**ASIC PCI filter:** `lspci -nn` match `cf82|cf84` (`spc5_pci_id|spc6_pci_id` for HI186)  
**CPU Type:** AMD  
**System Type:** Air-Cooled  
**Document Version:** 1.0  
**Last Updated:** June 9, 2026

---

## Table of Contents

1. [Platform Overview](#platform-overview)
2. [System Configuration](#system-configuration)
3. [ASIC Voltage Monitors](#asic-voltage-monitors)
4. [COMEX Voltage Monitors](#comex-voltage-monitors)
5. [PSU Power Supplies](#psu-power-supplies)
6. [Fan Modules](#fan-modules)
7. [Thermal Sensors](#thermal-sensors)
8. [Alarm Sensors](#alarm-sensors)
9. [System Control](#system-control)
10. [LEDs](#leds)
11. [JTAG](#jtag)
12. [EEPROM](#eeprom)
13. [Events](#events)
14. [Watchdog](#watchdog)
15. [Power Calculation](#power-calculation)
16. [Thermal Control](#thermal-control)
17. [Chip and Devtree Reference](#chip-and-devtree-reference)

---

## Platform Overview

The SN6600 air-cooled switch system has the following characteristics
(from `hw-management.sh` `sn66xx_specific()` for SKU HI186, kernel platform
data in `0069-platform-mellanox-Add-support-for-new-SN6600-Nvidia-.patch`, and
`usr/etc/hw-management-sensors/sn66xxld_sensors.conf`):

| Component | Value | Description |
|-----------|-------|-------------|
| ASICs | 1 | Single SPC-6 ASIC (`config/asic_num` = 1) |
| CPLDs | 4 | System control CPLDs (`config/cpld_num` = 4) |
| Fan modules | 5 | Hot-plug fan drawers (`hotplug_fans` = 5, `max_fans` = 5) |
| Fan tachometers | 10 | Two tachos per drawer (front + rear) in `sn66xxld_sensors.conf`; kernel fan CPLD exposes up to **10** tacho registers |
| PSUs | 4 | 2+2 redundant 2700 W supplies (`hotplug_psus` = 4, `psu_count` = 4) |
| AC input cables | 4 | Hot-plug PWR cable presence (`hotplug_pwrs` = 4) |
| PDBs | 0 | No liquid-cooled PDB (`hotplug_pdbs` = 0) |
| Power boards | 0 | No separate PWR board (`pwr_brd_num` not set for HI186) |
| Leakage sensors | 0 | Air-cooled (`config/leakage_counter` = 0) |
| ASIC voltage monitors | up to 20 | `voltmon1`..`voltmon20` (same SWB / port VR map as SN6600_LD) |
| COMEX voltage monitors | 2 | `comex_voltmon1`, `comex_voltmon2` |
| Airflow | C2P | `config/system_flow_capability` = `C2P` (chassis-to-port) |

**Compared to SN6600_LD (HI193):** HI186 shares the same switch-board VR and
COMEX monitoring (`sn66xxld_sensors.conf`, `sn66xxld_*` devtree tables) but
replaces liquid-cooled PDB / leakage infrastructure with **5 fan drawers** and
**4 PSUs**. There is **no** hot-plug PDB, **no** `pwr_brd_num` power-board
domain, and **no** leakage monitoring.

---

## System Configuration

**Base Path:** `/var/run/hw-management/`

### Configuration Files

| Node | Description | Value (HI186 init) |
|------|-------------|-------------------|
| `config/asic_num` | Number of ASICs | 1 |
| `config/cpld_num` | Number of CPLDs | 4 |
| `config/hotplug_fans` | Hot-plug fan drawer count | 5 |
| `config/hotplug_psus` | Hot-plug PSU count | 4 |
| `config/hotplug_pwrs` | Hot-plug AC PWR cable count | 4 |
| `config/hotplug_pdbs` | Hot-plug PDB count | 0 |
| `config/leakage_counter` | Leakage sensor count | 0 |
| `config/psu_count` | PSU instances | 4 |
| `config/cpu_type` | CPU type | AMD (same family as SN6600_LD) |
| `config/i2c_bus_offset` | I2C bus offset | 0 |
| `config/i2c_comex_mon_bus_default` | COMEX I2C bus index for udev filtering | **6** (`sn66xx_specific()`) |
| `config/lm_sensors_config` | Sensors file | `sn66xxld_sensors.conf` |
| `config/named_busses` | Logical bus map | From `sn66xxld_named_busses`: `asic1 5 pwr1 7 pwr2 8 vr1 16 vr2 17 vpd 1 cpu-vr 6` |
| `config/system_flow_capability` | Chassis airflow direction | `C2P` |
| `config/fan_drwr_num` | Fan drawer count (runtime) | **0** at init; updated by `hw-management-thermal-events.sh` when mlxreg fan hwmon appears |
| `config/fan_max_speed` | Global fan max RPM reference | 18700 |
| `config/fan_min_speed` | Global fan min RPM reference | 3650 |
| `config/fan_front_max_speed` | Front (inlet) fan max RPM | 18700 |
| `config/fan_front_min_speed` | Front (inlet) fan min RPM | 4500 |
| `config/fan_rear_max_speed` | Rear (outlet) fan max RPM | 15100 |
| `config/fan_rear_min_speed` | Rear (outlet) fan min RPM | 3650 |
| `config/psu_fan_max` | PSU internal fan max RPM | 27500 |
| `config/psu_fan_min` | PSU internal fan min RPM (20% of max) | 5500 |
| `config/tc_config.json` | Thermal control policy | Copied from `tc_config_sn6600.json` at init (see [Thermal Control](#thermal-control)) |

**Note:** `config/lm_sensors_config` is a symlink to
`/etc/hw-management-sensors/sn66xxld_sensors.conf`.

### PSU I2C Configuration

Written by `set_config_data()` from `sn66xx_specific()` HI186 branch:

| Node | I2C bus | Address (hex) | Devtree chip |
|------|---------|---------------|--------------|
| `config/psu1_i2c_bus` / `config/psu1_i2c_addr` | 4 | 0x59 | `dps460` → `psu1` |
| `config/psu2_i2c_bus` / `config/psu2_i2c_addr` | 4 | 0x58 | `dps460` → `psu2` |
| `config/psu3_i2c_bus` / `config/psu3_i2c_addr` | 4 | 0x5b | `dps460` → `psu3` |
| `config/psu4_i2c_bus` / `config/psu4_i2c_addr` | 4 | 0x5a | `dps460` → `psu4` |

PSU devtree entries are appended at runtime if not already present in the SMBIOS
devtree file.

### ASIC Configuration

| Node | Description |
|------|-------------|
| `config/asic1_pci_bus_id` | ASIC1 PCI bus ID |
| `config/asic_chipup_counter` | ASIC chip-up counter |

---

## ASIC Voltage Monitors

HI186 uses the same switch-board PMIC map as SN6600_LD.

**Repository devtree:** `sn66xxld_swb_alternatives` and
`sn66xxld_port_alternatives` in `hw-management-devtree.sh` define **voltmon1**
through **voltmon20** (MP29816 primary, `xdpe1a2g7b` alternates at the same
addresses).

`sn66xxld_sensors.conf` lists **20** MP29816 ASIC PMIC chip sections (PMIC-1
through PMIC-20) on logical I2C buses **15** and **16**.

### Typical channel pattern (voltmon with dual outputs)

For PMICs with two regulated outputs, the virtual `environment` and `alarm`
nodes follow the usual PMBus-style mapping (example: `curr2` maps to chip
`curr3`, `curr3` to chip `curr4`, and similarly for power). Use the following
pattern for each exposed `voltmon<N>`:

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

**PMIC type (sensors.conf):** MP29816 on I2C buses **15** and **16**.

**voltmon1 (PMIC-1, VDD):** Single main output style (PVIN1_VDD_ASIC,
ASIC_VDD).

---

## COMEX Voltage Monitors

Symlinks under `environment/`, `thermal/`, and `alarm/` are created by
`hw-management-chassis-events.sh` using **label-based** mapping
(`find_sensor_by_label` and `VOLTMON_SENS_LABEL` / `CURR_SENS_LABEL` /
`POWER_SENS_LABEL`).

### comex_voltmon1 (CPU power)

**Chip:** `mp2845-i2c-*-69`; devtree `sn66xxld_platform_alternatives`:
`mp2845 0x69 5 comex_voltmon1`.

**Labels (sensors.conf):** VDDCR in/out rails, CPU / SOC phase temps and
currents.

| Node pattern | Unit |
|--------------|------|
| `environment/comex_voltmon1_in2_input`, `in3_input`, `curr2_input`, `curr3_input` | mV / mA |
| `thermal/comex_voltmon1_temp1_input` | m°C |

### comex_voltmon2 (DDR power)

**Chip:** `mp2975-i2c-*-6a`; devtree: `mp2975 0x6a 5 comex_voltmon2`.

| Node pattern | Unit |
|--------------|------|
| `environment/comex_voltmon2_in1_input` .. `in3_input`, `curr1_input` .. `curr3_input`, `power1_input` .. `power3_input` | mV / mA / µW |
| `thermal/comex_voltmon2_temp1_input`, `temp1_crit`, `temp1_max` | m°C |

---

## PSU Power Supplies

Four hot-plug **DPS460** PSUs on I2C bus **4** (see [PSU I2C Configuration](#psu-i2c-configuration)).
There is **no** separate power-board (`pwr_brd_num`) or PDB converter monitoring
on HI186.

### PSU environment and thermal nodes

Created by `hw-management-chassis-events.sh` from `dps460` hwmon attributes
using labels in `sn66xxld_sensors.conf`:

| Node pattern | Description | Unit |
|--------------|-------------|------|
| `environment/psu<N>_in1_input` | AC input voltage (220 V rail) | mV |
| `environment/psu<N>_in3_input` | DC output voltage (12 V rail) | mV |
| `environment/psu<N>_curr1_input` | AC input current | mA |
| `environment/psu<N>_curr2_input` | DC output current | mA |
| `environment/psu<N>_power1_input` | AC input power | µW |
| `environment/psu<N>_power2_input` | DC output power | µW |
| `thermal/psu<N>_temp1_input` .. `temp3_input` | PSU temperatures | m°C |
| `thermal/psu<N>_fan1_input` | PSU internal fan speed | RPM |
| `thermal/psu<N>_status` | PSU module presence | 0/1 |
| `thermal/psu<N>_pwr_status` | AC PWR cable presence (from mlxreg-io `pwr<N>`) | 0/1 |

**PSU labels (sensors.conf):** PSU-1(L) .. PSU-4(R) on addresses **0x59**,
**0x58**, **0x5b**, **0x5a** (logical numbering; runtime `config/psuX_i2c_addr`
values come from platform init).

### PSU EEPROM

| Node | Description |
|------|-------------|
| `eeprom/psu1_info` .. `eeprom/psu4_info` | PSU FRU EEPROM |
| `eeprom/psu1_data` .. `eeprom/psu4_data` | Parsed PSU FRU data |

PSU EEPROMs are on I2C bus **4** (`i2c_bus_def_off_eeprom_psu` in
`hw-management-chassis-events.sh`).

---

## Fan Modules

Five hot-plug fan **drawers**. Each drawer carries two tachometer channels
(inlet + outlet).

### Fan drawer hot-plug

Kernel mlxreg-io exposes raw drawer presence bits as `fan1`..`fan8`; HI186
platform monitoring uses the first five (`fan1`..`fan5`). These drive:

| Node | Description | Values |
|------|-------------|--------|
| `events/fan<N>` | Fan drawer `<N>` hot-plug | 0=removed, 1=inserted |
| `thermal/fan<N>_status` | Fan drawer presence status | 0/1 |
| `thermal/fan<N>_dir` | Fan airflow direction | per VPD / platform config |

### Fan speed monitoring and control

Fan tachos and PWM are provided by the mlxreg **fan** CPLD device
(`mlxreg_fan-isa-*` in sensors.conf, **10** labeled channels):

| sensors.conf label | Drawer | Role |
|--------------------|--------|------|
| `fan1`, `fan2` | Drawer 1 | Tach 1 (front), Tach 2 (rear) |
| `fan3`, `fan4` | Drawer 2 | Tach 1, Tach 2 |
| … | … | … |
| `fan9`, `fan10` | Drawer 5 | Tach 1, Tach 2 |

**Thermal sysfs (via `hw-management-thermal-events.sh`):**

| Node pattern | Description |
|--------------|-------------|
| `thermal/fan<N>_speed_get` | Tachometer RPM readback |
| `thermal/fan<N>_speed_set` | PWM / speed control (links to fan CPLD `pwm1`) |
| `thermal/fan<N>_min` | Min speed (front or rear limit via `set_fan_speed_limits()`) |
| `thermal/fan<N>_max` | Max speed (front or rear limit) |
| `thermal/fan<N>_fault` | Fan fault indicator |
| `thermal/fan<N>_speed_tolerance` | Speed tolerance (±30%, from `config/fan_speed_tolerance`) |
| `thermal/pwm1` | System fan PWM level |

**Speed limits:** Odd-indexed tachos within each drawer pair use
`config/fan_front_*`; even-indexed use `config/fan_rear_*` (see
`set_fan_speed_limits()` in `hw-management-helpers.sh`).

**Kernel note:** `nvsw_host_cpld_hid186_fan_data[]` registers **10** tacho
channels (`tacho1`..`tacho10`); `config/max_tachos` is populated at runtime
when fan hwmon channels appear.

---

## Thermal Sensors

### ASIC and COMEX

Same patterns as [SN6600_LD Hardware Interfaces](SN6600_LD_Hardware_Interfaces.md):
`thermal/voltmon<N>_temp1_*`, COMEX PMIC temps, `thermal/cpu_pack`, etc.

### Ambient sensors

HI186 devtree adds `fan_type0_alternatives` (fan-board ambient at I2C bus **7**).
When present, labels resolve to:

| Node | Description | Unit |
|------|-------------|------|
| `thermal/fan_amb` | Fan-side ambient | m°C |
| `thermal/port_amb` | Port-side ambient (port board TMP102/ADT75/STTS751) | m°C |
| `thermal/asic_amb` | ASIC ambient (when exposed) | m°C |
| `thermal/sensor_amb` | System ambient (thermal policy sensor) | m°C |

### CPU, SODIMM, storage

| Node | Description | Unit |
|------|-------------|------|
| `thermal/cpu_pack` | CPU package | m°C |
| `thermal/sodimm1_temp_input` | SODIMM 1 (JC42 **0x52**, bus **10**) | m°C |
| `thermal/sodimm2_temp_input` | SODIMM 2 (JC42 **0x53**, bus **10**) | m°C |
| `thermal/drivetemp` | NVMe temperature | m°C |

### PSU and fan temperatures

See [PSU Power Supplies](#psu-power-supplies) and [Fan Modules](#fan-modules).

**Not present on HI186:** PDB hotswap/converter temperatures (`pdb_hotswap*`,
`pdb_pwr_conv*`), leakage sensors.

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

`alarm/comex_voltmon1_*` and `alarm/comex_voltmon2_*` follow the same
chassis-events voltmont path as ASIC voltmons.

### PSU alarms

| Node pattern | Description |
|--------------|-------------|
| `alarm/psu<N>_*` | Per-PSU voltage, current, temperature, fan alarms |
| `thermal/psu<N>_alarm` | Aggregated PSU alarm status |

### SODIMM alarms

`thermal/sodimm<N>_temp_*_alarm` nodes when JC42 sensors are present.

---

## System Control

Representative nodes under `system/` (shared SN6600 / VMOD0025 register map;
HI186 uses `nvsw_host_spc6_hid186_regs_io`):

| Node | Description | Access |
|------|-------------|--------|
| `system/asic_health` | ASIC health | RO |
| `system/asic_reset` | ASIC reset | RW |
| `system/asic_pg_fail` | ASIC power-good fail | RO |
| `system/pwr_cycle` / `pwr_down` | Power control | WO |
| `system/aux_pwr_cycle` | Aux power cycle | WO |
| `system/graceful_pwr_off` | Graceful power off | RW |
| `system/cpld1_version` ... `cpld4_version` | CPLD versions | RO |
| `system/cpu_erot_present` | CPU eRoT presence | RO |
| `system/cpu_mctp_ready` | MCTP ready | RO |
| `system/bmc_present` | BMC presence | RO |
| `system/jtag_enable` | JTAG enable | RW |
| `system/pwr_converter_prog_en` | Power converter program enable | RW |

**Not present on HI186:** `system/leakage*`, PDB-specific controls.

---

## LEDs

HI186 uses the SN6600 platform LED map (kernel `nvsw_led_data`; air-cooled SKU
does not select the liquid-cooled `nvsw_host_spc6_lc_led` variant).

Nodes under `led/` include power / status / UID brightness, delays, triggers,
`led_*_capability`, and `led_*_state` (same hierarchy pattern as SN6600_LD).

---

## JTAG

| Node |
|------|
| `jtag/jtag_enable` |
| `jtag/jtag_tck`, `jtag_tdi`, `jtag_tdo`, `jtag_tms` |

Duplicate `system/jtag_enable` may also exist under `system/`.

---

## EEPROM

| Node | Description |
|------|-------------|
| `eeprom/vpd_info` | Chassis VPD |
| `eeprom/vpd_data` | Parsed VPD |
| `eeprom/swb_info` | Switch board |
| `eeprom/swb_data` | Parsed SWB data |
| `eeprom/psu1_info` .. `eeprom/psu4_info` | PSU FRU (see [PSU Power Supplies](#psu-power-supplies)) |

---

## Events

| Node | Description | Values |
|------|-------------|--------|
| `events/fan1` .. `events/fan5` | Fan drawer hot-plug | 0=removed, 1=inserted |
| `events/psu1` .. `events/psu4` | PSU module hot-plug | 0=removed, 1=inserted |
| `events/pwr1` .. `events/pwr4` | AC input hot-plug | 0=unplugged, 1=plugged |

**Note:** `events/pwr<N>` reflects AC power presence
(`NVSW_REG_PWR_OFFSET` bits in kernel), not a power-board hot-plug event.
HI186 has **no** `events/pdb*` or `events/leakage*`.

Platform monitoring (`hw_management_platform_config.py` SKU **HI186**) polls
mlxreg-io `fan1`..`fan5`, `psu1`..`psu4`, `pwr1`..`pwr4`, and ASIC chip-up
status.

### Hot-plug Event Register Handling

`hw_management_peripheral_updater.py` processes software hot-plug events from
the mlxreg-io event register configured for the monitored device group. The
handler reads the event register once at the beginning of each polling pass and
uses that snapshot to decide which masked bits require event dispatch.

Mask strings are interpreted MSB-first: the rightmost mask bit is device index
0, so event bit `0` maps to the first name in the configured `name_list`.

After a device event is dispatched, the handler acknowledges only the processed
bit. It rereads the current hardware event register immediately before the
write-back and clears only that bit from the fresh value. This preserves any
new event bits that hardware may set while the current polling pass is still
processing earlier events; those preserved bits are handled on the next poll.

---

## Watchdog

`hw-management-chassis-events.sh` creates `watchdog/<sub>/` for identities
`mlx-wdt-*` (typically `watchdog/main/` and `watchdog/aux/` on SN6600 platforms).

Each subdirectory contains: `identity`, `state`, `status`, `timeout`,
`timeleft` (if present), `nowayout`, `bootstatus`.

---

## Power Calculation

| Node | Description |
|------|-------------|
| `power/pwr_consum` | Symlink to `hw-management-power-helper.sh` |
| `power/pwr_sys` | Symlink to `hw-management-power-helper.sh` |

On air-cooled SN6600, PSU input power from `environment/psu<N>_power1_input`
contributes to system power aggregation when PSUs are present.

---

## Thermal Control

HI186 enables thermal control (unlike SN6600_LD which uses
`tc_config_not_supported.json`).

| Item | Source |
|------|--------|
| Init target | `thermal_control_config="$thermal_control_configs_path/tc_config_sn6600.json"` |
| Runtime config | `config/tc_config.json` |
| Policy content (repository) | `usr/etc/hw-management-thermal/tc_config_sn6600.json` |

**Policy highlights (`tc_config_sn6600.json`):**

| Parameter | Value |
|-----------|-------|
| Airflow profile | `C2P` |
| Fan drawers in sensor list | `drwr1`..`drwr5` |
| PSUs in sensor list | `psu1`..`psu4` |
| Front fan RPM range | 4500 – 18700 |
| Rear fan RPM range | 3650 – 15100 |
| PWM floor | 30% |

Thermal daemon maps fan tachometers to logical drawers (`drwr<N>`) for fan
error detection and PWM tuning.

---

## Chip and Devtree Reference

| Item | Source |
|------|--------|
| Switch-board VR `voltmon1`..`20`, MP29816 / xdpe1a2g7b | `sn66xxld_swb_alternatives`, `sn66xxld_port_alternatives` |
| Platform / COMEX / SODIMM / VPD | `sn66xxld_platform_alternatives` |
| PSU `dps460` on bus 4 | Runtime append in `sn66xx_specific()` HI186; static entries in `sn66xxld_pwr_alternatives` |
| Fan ambient | `fan_type0_alternatives` (HI186 devtree branch) |
| Fan drawer / tacho CPLD | Kernel `nvsw_host_spc6_hid186_fan_data[]` |
| Hot-plug presence (fan, psu, pwr) | Kernel `nvsw_host_spc6_hid186_regs_io_data[]` |
| LM sensors chip list | `usr/etc/hw-management-sensors/sn66xxld_sensors.conf` |
| Udev symlink creation | `usr/usr/bin/hw-management-chassis-events.sh` |
| Fan / PSU thermal symlinks | `usr/usr/bin/hw-management-thermal-events.sh` |
| Platform hot-plug polling | `usr/usr/bin/hw_management_platform_config.py` (`HI186`) |

---

## Source Files

- Sensors:
  `usr/etc/hw-management-sensors/sn66xxld_sensors.conf`
- Thermal policy:
  `usr/etc/hw-management-thermal/tc_config_sn6600.json`
- Platform init:
  `usr/usr/bin/hw-management.sh` (`sn66xx_specific` HI186 branch,
  `check_system` VMOD0025, `set_asic_pci` HI186)
- Devtree / BOM mapping:
  `usr/usr/bin/hw-management-devtree.sh` (HI186 / `sn66xxld_*` +
  `fan_type0_alternatives`)
- Kernel platform:
  `recipes-kernel/linux/linux-6.12/0069-platform-mellanox-Add-support-for-new-SN6600-Nvidia-.patch`
- Liquid-cooled sibling reference:
  `Documentation/SN6600_LD_Hardware_Interfaces.md`

**Note:** A validated runtime tree capture
(`tests/system_tree/hw-management-tree-SN6600.txt`) is not yet present in this
repository. SIMX emulation uses `/etc/hw-management-virtual/hwmgmt_HI186.tgz`
when available.

---

**End of Document**
