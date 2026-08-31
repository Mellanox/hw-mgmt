# User Manual Changelog

**Document:** Chassis_Management_for_NVIDIA_Switch_Systems_with_Sysfs_rev.3.2.md  
**Last Updated:** June 30, 2026

---

## Change History

### Rev. 3.2.6 - June 30, 2026

#### Added: V.7.0070.1000 sysfs and platform documentation

**Affected platforms:** SN6600_LD (HI193); N6300_LD (HI185); AST2700 BMC stack (HI189); SN7170_LD virtual (HI194, SimX only).

**User manual updates:**

| Area | Change |
|------|--------|
| §2.2 | BMC peripheral table: `leakage/<N>/<j>/…` tree, `$bsp_path/bmc/` reset-cause subtree; example `hw-management-bmc-leakage-sysfs.txt` |
| §3.1.59 | **`config/pdb_hotswap_scale`** (SN6600_LD, value 5.333) |
| §3.4 | **`environment/pdb_hotswap<N>_power1_scale`** and **`_curr1_scale`** (lm5066i only) |
| §3.18 | **`cpu_shutdown_req`**: hw-mgmt polls this node via `hw_management_platform_config.py` (HI176–HI185, …) |
| §3.24 | **BMC reset cause** (AST2700): primary `reset_pwr_cycle` / `reset_soft_reboot` / `reset_unknown`; `bmc/domains/reset_*`; raw SCU logs |
| §3.25 | **BMC leakage A2D tree** under `$bsp_path/leakage/` (ADS1015, ADS7924, MAX1363 per JSON) |
| N61XX_LD notes | Extended cartridge / PDB / leakage applicability to **N6300_LD** (HI185): `cartridge_counter`=4, `hotplug_pdbs`=2, `cpld_num`=3 |

**Validation source:** `bmc/usr/usr/bin/hw-management-bmc-get-reset-cause.sh`,
`bmc/examples/hw-management-bmc-leakage-sysfs.txt`, `usr/usr/bin/hw-management.sh` (HI185, HI193),
`usr/usr/bin/hw-management-chassis-events.sh`, `usr/etc/hw-management-sensors/sn66xxld_sensors.conf`,
`usr/usr/bin/hw_management_platform_config.py`.

---

### Rev. 3.2.5 - June 3, 2026

#### Added: BMC EEPROM, BMC status, and stack alignment

**User manual updates:**

| Area | Change |
|------|--------|
| §2.2 | HI189 BMC peripheral table (thermal, eeprom, system/regio, leakage); host-side BMC-related nodes |
| §3.3.7–§3.3.8 | **Read system EEPROM** and **Read BMC board EEPROM** (BMC stack, HI189 I2C evidence) |
| §3.20 | **Stack: BMC** tags on BMC ambient/crit/min; host CPU thermal on BMC stack cross-refs |
| §3.23.1–§3.23.5 | BMC status section bodies: `bmc_present`, `bmc_to_cpu_ctrl`, MCTP config/ready |

**Validation source:** `bmc/usr/etc/HI189/5-hw-management-bmc-events.rules`, `bmc/examples/hw-management-bmc-system-sysfs.txt`.

---

### Rev. 3.2.4 - June 3, 2026

#### Added: Host vs BMC stack reference (§2.2)

**User manual updates:**

| Area | Change |
|------|--------|
| §2.2 | New section: host (`usr/`, `hw-management`) vs BMC (`bmc/usr/`, `hw-management-bmc`) — packages, install paths, handlers, examples |
| §2.4 | Clarified host-only init file list; pointer to BMC README |
| §3 intro | Stack applicability note for §3.x nodes |
| §3.20 | Thermal reference line for host vs BMC event scripts and example paths |

**Cross-references:** `README.md`, `bmc/README.md`, `bmc/DEVELOPER_GUIDE.md`, `bmc/examples/`.

---

### Rev. 3.2.3 - June 3, 2026

#### Fixed: §3.20 thermal TOC/body alignment and BMC per-HID examples

**Affected platforms:** All (user manual); BMC thermal stack HI189 / SN6600 (`lm75`).

**User manual updates (§3.20 Thermal):**

| Area | Change |
|------|--------|
| §3.20.1, §3.20.8 | Added **Ambient sensors** and **MNG Temperature** bodies |
| §3.20.9–§3.20.12 | BMC temperature: `bmc_temp_input`, `bmc_temp`; §3.20.11–12 document crit/min as N/A on `lm75` |
| §3.20.13–§3.20.16 | TOC titles aligned with PDB hotswap/converter section bodies |
| §3.20.18 | **Cooling Name** body added |
| §3.20.30–§3.20.31 | **Set Fan Speed** and thermal **Fan Speed Tolerance** bodies added |
| §3.20.35–§3.20.37 | **Comex Voltmon** temperature bodies added |
| §3.20.60–§3.20.65 | SODIMM TOC titles aligned with existing section bodies |
| §3.20.69–§3.20.73 | **SWB ASIC** and **Drive** temperature bodies added |

**BMC examples layout:**

| Path | Purpose |
|------|---------|
| `bmc/examples/hw-management-bmc-thermal-sysfs.txt` | Delivered BMC thermal sysfs example (HI189) |
| `bmc/examples/HIxxx/examples/` | Template for per-HID example layout on new platforms |
| `bmc/examples/HIxxx/examples/` | Template for next HID |

**Validation source:** `bmc/usr/etc/HI189/hw-management-bmc-events.sh`, `bmc/examples/hw-management-bmc-thermal-sysfs.txt`.

---

### Rev. 3.2.2 - June 3, 2026

#### Fixed: BMC thermal sysfs documentation (HI189 / lm75)

**Affected platforms:** Systems with hw-mgmt BMC thermal stack (for example HI189 /
SN6600 BMC ambient sensor on I2C `4-0048`, `lm75` driver).

**User manual updates:**

| Area | Change |
|------|--------|
| §3.20.9 | Document `thermal/bmc_temp_input` (was missing; rev 2.8 used obsolete `thermal/bmc`) |
| §3.20.10 | Document `thermal/bmc_temp` as BMC max/limit (replaces obsolete `bmc_crit` / `bmc_max` names) |
| BMC example | Aligned with `bmc/examples/hw-management-bmc-thermal-sysfs.txt` |

**Validation source:** `bmc/usr/etc/HI189/hw-management-bmc-events.sh`, mainline
`drivers/hwmon/lm75.c` (`HWMON_T_MIN` not registered).

---

### Rev. 3.2.1 - May 31, 2026

#### Fixed: N51XX_LD reset-cause documentation (#5014001)

**Affected platforms:** N51XX_LD platform family, including GB200 systems such as N5110_LD and N5500_LD.

**Overview:**  
Aligned the user manual with N51XX_LD CPLD-supported reset causes. The following are not supported by the N51XX_LD CPLD and must not be documented as available sysfs attributes: `reset_ac_pwr_fail`, `reset_aux_pwr_or_ref`, `reset_from_asic`, `reset_reload_bios`.

**User manual updates:**

| Area | Change |
|------|--------|
| Get Reset Cause (3.18.39) | Added N51XX_LD platform family table with 22 supported reset causes |
| Get Reset Cause (3.18.39) | Documented unsupported legacy causes for N51XX_LD |
| Config | Referenced `reset_attr_num` = 22 for N51XX_LD |

**Validation source:**

- `recipes-kernel/linux/linux-6.12/9007-platform-mellanox-Downstream-Introduce-support-of-Nv.patch`
- `usr/usr/bin/hw-management.sh` (`n51xx_reset_attr_num`)

---

### Rev. 3.2 (SN66XX_LD) - March 22, 2026

#### Added: SN6600_LD platform documentation

**Affected platforms:** SN66XX_LD family (SN6600_LD)  
**Platform SKU:** HI193 (`hw-management.sh` `sn66xxld_specific`)  
**ASIC:** 1 (single ASIC, `config/asic_num` = 1 on validated tree)  
**CPU type:** AMD

**Overview:**  
Documented the SN6600_LD liquid-cooled switch: dual hot-plug PDBs
(`pdb_hotswap1/2`, `pdb_pwr_conv1/2`), 19 ASIC `voltmon` sysfs indexes on the
captured tree (`voltmon1`-`14`, `voltmon16`-`20`; no `voltmon15` symlink),
SODIMM JC42 sensors at **0x52** and **0x53** on I2C bus **10**, PDB events
`pdb1`/`pdb2`, watchdog layout under `watchdog/main/` and `watchdog/aux/`, and
how `config/leakage_counter` (**2**) relates to optional extra `system/leakage*`
symlinks in the validated tree.

**User manual updates (cross-cutting):**

| Area | Change |
|------|--------|
| Liquid-cooled applicability | Extended notes to include SN66XX_LD / SN6600_LD |
| `config/hotplug_pdbs` | Documented SN6600_LD = 2 and `events/pdb1` / `pdb2` |
| PDB power converter sections | SN6600_LD examples using `pdb_pwr_conv1` and `pdb_pwr_conv2` |
| SODIMM thermal | SN6600_LD I2C bus 10, addresses 0x52 / 0x53 |
| ASIC health | Note single-ASIC SN6600_LD (no `asic2_health`..`asic4_health`) |
| Watchdog | Note `watchdog/main` and `watchdog/aux` paths for SN6600_LD |

**Validation source:**

- `usr/etc/hw-management-sensors/sn66xxld_sensors.conf`
- `usr/usr/bin/hw-management.sh` (`sn66xxld_specific`)

---

### Rev. 3.1 (V.7.0060.1000) - January 14, 2026

#### Added: N6100_LD Platform Documentation for Liquid-Cooled Multi-ASIC Systems

**Affected Platforms:** N61XX_LD family (N6100_LD)  
**Platform SKU:** HI180  
**ASIC:** 4x Spectrum-X (Multi-ASIC configuration)  
**CPU Type:** AMD

**Overview:**  
Added comprehensive documentation for the N6100_LD liquid-cooled multi-ASIC platform. This system features 4 ASICs with 16 ASIC Power Management ICs (4 per ASIC), PDB power distribution, cable cartridge EEPROMs, eRoT support, and SODIMM temperature monitoring.

**New Sections Added to User Manual:**

| Section | Node | Description |
|---------|------|-------------|
| 3.1.27 | `config/cartridge_counter` | Number of cable cartridges |
| 3.3.6 | `eeprom/cable_cartridge<N>_eeprom` | Cable cartridge EEPROM data |
| 3.5.7-8 | `events/erot<N>_*` | eRoT events (updated with N6100_LD) |
| 3.18.53 | `system/cartridge<N>` | Cartridge status |
| 3.18.54 | `system/asic_pg_fail` | ASIC PG failure |
| 3.18 | `system/asic_health` | Get ASIC Health (updated for multi-ASIC) |
| 3.18 | `system/mcu<N>_reset` | MCU reset control |
| 3.19.1 | `system/leakage<N>` | Leakage sensors |
| 3.20.60-68 | `thermal/sodimm<N>_temp_*` | SODIMM temperature sensors (updated to include both platforms) |

**Updated Sections:**

| Section | Change |
|---------|--------|
| 3.4 | Power converters: Added `pwr_conv` naming for N6100_LD (vs `pdb_pwr_conv` for SN58XX_LD) |
| 3.6 | Updated all liquid-cooled references to include N61XX_LD family |
| Multiple | Extended voltmon support documentation for 16 PMICs (voltmon1-16) |

**Key Differences from SN58XX_LD:**

| Feature | N6100_LD | SN5810_LD |
|---------|----------|-----------|
| ASICs | 4 | 1 |
| ASIC Voltage Monitors | 16 | 11 |
| Cable Cartridges | 4 | 0 |
| Hot-plug PDBs | 0 (non-hotplug) | 1 |
| Power Converters | `pwr_conv1/2` | `pdb_pwr_conv1` |
| eRoT | 1 | 0 |
| SODIMM Sensors | 2 | 2 |
| CPU Type | AMD | AMD |

---

### Rev. 3.0 (V.7.0050.3000) - December 31, 2025

#### Added: PDB Sensor Documentation for Liquid-Cooled Systems

**Affected Platforms:** SN58XX_LD family (SN5810_LD, SN5800_LD)  
**Platform SKUs:** HI181, HI182

**Overview:**  
Added comprehensive documentation for Power Distribution Board (PDB) sensors specific to liquid-cooled systems where traditional PSUs and fans are not present.

**New Sections Added to User Manual:**

| Section | Node Category | Description |
|---------|---------------|-------------|
| 3.4 | `environment/pdb_hotswap<N>_*` | PDB hotswap current/voltage/power |
| 3.4 | `environment/pdb_pwr_conv<N>_*` | PDB power converter measurements |
| 3.6 | `alarm/pdb_hotswap<N>_*` | PDB hotswap alarms |
| 3.6 | `alarm/pdb_pwr_conv<N>_*` | PDB power converter alarms |
| 3.20 | `thermal/pdb_hotswap<N>_temp*` | PDB hotswap temperature |
| 3.20 | `thermal/pdb_pwr_conv<N>_temp*` | PDB power converter temperature |
| 3.5 | `events/pdb<N>` | PDB hot-plug events |

**Updated Sections:**

| Section | Change |
|---------|--------|
| 3.1.11 | Enhanced description for `hotplug_pdbs` attribute |

---

## Previous Revisions

| Revision | Date | Description |
|----------|------|-------------|
| 2.8 | April 2024 | Added temperature, BMC and power related attributes |
| 2.6 | July 2024 | Added DPU related attributes |
| 2.4 | Aug 2023 | Adding asics_init_done and asic_chipup_completed |
| 2.3 | July 2023 | Update LEDs colors for FAN LED, PSU LED and status LED |
| 2.2 | Feb 2022 | Add SN4800 related attributes, PSU FW version |
| 2.1 | Sept 2021 | Add PSU MIN/MAX fan speed, PSU sensor sections |
| 2.0 | May 2021 | Edit reset causes, Add Spectrum-3 |
| 1.9 | Dec 2020 | Added updates for Fan Direction JTAG |
| 1.8 | July 2020 | Added PSU VPD, hot-plug numbers, events, fan speeds |
| 1.7 | Apr 2020 | Added SFP/module counters, CPLD versions |
| 1.6-1.0 | 2015-2020 | Initial releases and updates |

---

## Instructions for Future Updates

When updating the User Manual:

1. Add a new revision section at the top with version and date
2. List all new sections added (with section numbers and node paths)
3. List sections that were updated
4. Note platform applicability
5. Reference the system tree file used for validation

---

**End of Changelog**
