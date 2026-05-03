<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# Cartridge identity → switch-board CPLD (`hw-management-bmc-copy-cartridge-data.sh`)

## Purpose

On **systems equipped with removable cartridges**, the switch ASIC side expects rack and slot context (rack ID, topology ID, switch tray ID, slot index) in the **switch-board CPLD** register bank. That data lives in the **cartridge FRU EEPROM** (I2C). This helper **reads the leftmost (primary) cartridge EEPROM** and **programs the CPLD** so the values match the physically installed cartridge after power cycle or BMC-initiated re-sync.

Platforms **without** cartridges do not use this path; leaving the JSON config **uninstalled** is correct and keeps the script a no-op.

## When it runs (integration)

The script is **not** tied to a dedicated `systemd` unit in the `hw-management-bmc` package. It is meant to be **sourced** from the BMC boot path (for example **`hw-management-bmc-ready.sh`** or a platform-specific **`bmc_ready`** / post-I2C hook) **only on SKUs that have cartridges**, after cartridge and switch-board I2C buses are reachable.

Suggested pattern:

1. Install **`/usr/bin/hw-management-bmc-copy-cartridge-data.sh`** (ships under **`bmc/usr/usr/bin/`** with other BMC helpers).
2. On **cartridge SKUs only**, install **`/etc/hw-mgmt-bmc-copy-cartridge-data.json`** (see **`bmc/examples/hw-mgmt-bmc-copy-cartridge-data.json`** for field names and example values). Override the path with **`HW_MGMT_BMC_CARTRIDGE_CFG`** if needed.
3. In the ready script (or equivalent), after I2C is up:

   ```bash
   # shellcheck source=/dev/null
   [ -f /usr/bin/hw-management-bmc-copy-cartridge-data.sh ] &&
     . /usr/bin/hw-management-bmc-copy-cartridge-data.sh
   hw_mgmt_bmc_copy_cartridge_data
   ```

If the JSON file is **missing**, **`hw_mgmt_bmc_copy_cartridge_data`** returns **0** immediately (no error) so shared `bmc_ready` code can stay unconditional; only cartridge images ship the JSON.

## Configuration and dependencies

| Item | Notes |
|------|--------|
| **JSON** | **`/etc/hw-mgmt-bmc-copy-cartridge-data.json`** — buses, EEPROM address, CPLD bank offsets, **`PhysicalAccess`** (**`I2C`** today; **`USB`** reserved). |
| **`CartridgeRackIdSize`** | Decimal **byte count** for the rack id read from the cartridge FRU **board serial** location (after FRU parse). It drives the EEPROM **`i2ctransfer … rN`**, the CPLD **write** length, and the **readback verify** **`rN`**. Must match how many bytes your platform stores and how many the CPLD returns for that register block. If the key is missing, non-numeric, or outside **1–64**, the script defaults to **13** (historical GBCDB-style length). When **2 + CartridgeRackIdSize** is below **16**, the CPLD write is **padded with `0x00`** up to **16** bytes total payload (register select + data) to preserve legacy fixed-width CPLD behavior; longer rack ids use a larger **`wN@`** (no padding). |
| **JSON parser** | When the JSON file **is** present, **`/usr/bin/switch_json_parser.sh`** must exist on the image (**`json_get_string`** / **`json_get_number`**). The script fails fast with a clear message if it is missing. |
| **I2C tools** | Uses **`i2cget`** / **`i2ctransfer`** for EEPROM and CPLD access. |

## Reserved / unused JSON fields

Some keys in the example JSON (for example topology-specific rack offsets or alternate cartridge buses) are **not read by the current I2C implementation**; they are **reserved** for future topology-specific or multi-cartridge paths. They may remain in the example for schema stability and forward compatibility.

**Active keys (not reserved):** **`CartridgeRackIdSize`** is consumed by the script (see table above). The optional **`deployment_note`** string in **`bmc/examples/hw-mgmt-bmc-copy-cartridge-data.json`** is human documentation only and is **ignored** by the shell logic.

## Related files

| Path | Role |
|------|------|
| **`bmc/usr/usr/bin/hw-management-bmc-copy-cartridge-data.sh`** | Implementation: FRU parse, EEPROM reads, CPLD writes with verification. |
| **`bmc/examples/hw-mgmt-bmc-copy-cartridge-data.json`** | Example / reference config (not installed unless packaging copies it to **`/etc/`**). |
| **`bmc/README.md`** | Main BMC package documentation (building, boot order, other helpers). |

For questions about CPLD register layout or platform constants, coordinate with the platform / switch-BMC owner for your HID.
