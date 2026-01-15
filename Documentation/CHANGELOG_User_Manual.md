# User Manual Changelog

**Document:** Chassis_Management_for_NVIDIA_Switch_Systems_with_Sysfs_rev.3.1.md  
**Last Updated:** January 14, 2026

---

## Change History

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
