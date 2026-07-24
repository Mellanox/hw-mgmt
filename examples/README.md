<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# `examples/`

Reference material for host CPU **hw-management** tooling: sample JSON,
schema notes, and small source examples. These files are **not** installed
automatically by the scripts under **`usr/`** unless your packaging explicitly
copies them.

| File | Purpose |
|------|---------|
| [hw-management-platform-example.json](hw-management-platform-example.json) | Platform bring-up JSON for **`check_system_json()`**: **`system`**, **`variables`**, **`board`**, **`pci`**, **`config`**, **`connection`**, **`psu_i2c`**, **`asic_i2c_buses`**, **`actions`** → deploy as **`/etc/hw-management-cfg/<HID>/platform.json`** (from **`usr/etc/hw-management-cfg/<HID>/`** on the image). Used by new platforms instead of a new **`*_specific()`** function in **`hw-management.sh`**. Parsed by **`hw-management-platform-json.sh`**. |
| [hw-management-exec-example.json](hw-management-exec-example.json) | Per-platform exec attributes (I2C/sysfs actions) for **`hw-management-exec-parser.sh`**: shared **`hids`** list or per-HID override → **`/etc/<HID>/hw-management-exec.json`** or **`/etc/hw-management-exec/*.json`**. |
| [hw-management-exec.md](hw-management-exec.md) | Host exec-attribute schema, config lookup order, dispatcher layout, and bring-up notes for **`hw-management-exec`**. |
| [hw-management-led-sysfs.txt](hw-management-led-sysfs.txt) | **`/var/run/hw-management/led/`** symlinks (fan/PSU/status/UID); CPLD ownership notes. See also **`Documentation/LED_Control_API.md`**. |
| [vr_dpc_update_example.json](vr_dpc_update_example.json) | VR DPC bulk-update config for **`hw-management-vr-dpc-update-all.sh`**: **`System HID`**, **`Devices`** array (type, bus, addr, config files). MPS devices use **`CrcFile`** and **`DeviceConfigFile`**; Infineon **`xdpe*`** and Renesas **`raa*`**/**`rrv*`** devices use **`Addr`** and **`ConfigFile`**. |
| [vr_dpc_update_nn5500ld.json](vr_dpc_update_nn5500ld.json) | Platform-specific VR DPC update example (N5110 LD). |
| [pmbus_devices_example.json](pmbus_devices_example.json) | PMBus device list schema (**`devices`**: name, bus, slave address, pages). |
| [src/iorw/](src/iorw/) | Sample **iorw** userspace tool sources (LPC/I2C access). |
| [src/ev_hndl/](src/ev_hndl/) | Sample line-card / event-handler sources (C and Python). |

## VR DPC updater notes

**`hw-management-vr-dpc-renesas-update.sh`** is the direct Renesas VR DPC
updater. Use it for Renesas Gen3.5 `.hex` files with an explicit I2C bus and
device address:

```sh
hw-management-vr-dpc-renesas-update.sh verify -b <bus> -a <addr> -f <file.hex>
hw-management-vr-dpc-renesas-update.sh flash -y -b <bus> -a <addr> -f <file.hex>
```

`verify` is read-only and checks the target device ID plus the live
`CONFIG_CRC`; `flash` programs the configuration and skips an already
programmed device unless forced by the updater options.

### Renesas DPC model and revision

For **`raa228942`**, **`raa228943`**, and **`rrv*`** devices, package
model/revision are stored in user-data PMBus registers (PowerNavigator
**MFR_DATA0** / **MFR_DATA1**):

| Register     | PMBus  | Meaning      | Example                  |
|--------------|--------|--------------|--------------------------|
| USER_DATA_02 | `0xB2` | DPC number   | `0x0565` for DPC000565   |
| USER_DATA_03 | `0xB3` | DPC revision | `0x0002` for REV0002     |

**`hw-management-read-vr-model-version.sh`** reads **`0xB2`** / **`0xB3`**
(page 0) for these device types. **`hw-management-dpc-update.sh --verify`**
compares current vs target values derived from the Renesas **`.hex`**
filename (`DPC######`, `REV####`) or from **`0xB2`** / **`0xB3`** write
records in the file body.

**`IC_DEVICE_ID`** / **`IC_DEVICE_REV`** (`0xAD` / `0xAE`) identify the
silicon and are used only by **`hw-management-vr-dpc-renesas-update.sh`**
for file/device compatibility, not for package version compare.

### Combined multi-vendor packages (`hw-management-dpc-update.sh`)

**`hw-management-dpc-update.sh`** is the installed entrypoint for packaged
VR DPC updates (`.tar.gz` with JSON and config files inside):

```sh
hw-management-dpc-update.sh --show [--json]
hw-management-dpc-update.sh --verify <dpc_pkg.tar.gz>
hw-management-dpc-update.sh [--force] <dpc_pkg.tar.gz>
```

A combined package may list devices for more than one vendor (e.g. MPS plus
Renesas on the same Rosalind bus/address map). The script matches live
hardware by **bus + I2C address**, then compares **`DeviceType`**:

| Situation | Action |
|-----------|--------|
| Live device type differs from JSON entry | **Skip** (vendor mismatch; no flash) |
| Types match, model/revision match package | **Skip** (up-to-date; no flash) |
| Types match, model/revision differ | **Update** that device |

On a Renesas-only system with a combined MPS+Renesas tarball, MPS entries
are skipped and Renesas entries are updated only when needed. **`--verify`**
reports **`SKIP_VND`**, **`OK`**, **`DIFF`**, etc. per entry.

Manual check on target:

```sh
i2cset -y -f <bus> <addr> 0x00 0
i2cget -y -f <bus> <addr> 0xB2 w   # DPC number, e.g. 0x0565
i2cget -y -f <bus> <addr> 0xB3 w   # revision, e.g. 0x0002
```

## Platform JSON quick reference

For a **new HID**, ship **`usr/etc/hw-management-cfg/<HID>/platform.json`**. At
runtime **`check_system()`** applies it when the file exists under
**`/etc/hw-management-cfg/<HID>/`**; otherwise the legacy **`check_system_internal()`** path
runs. Invalid JSON aborts **`do_start()`**.

See **`hw-management-platform-example.json`** for all supported sections and
field names. The optional **`system`** section describes platform traits
(**`bmc`**, **`cooling`**, **`power_supply`**, **`power_source`**, **`ssd`**,
**`tpm`**, **`security`**, **`type`**, etc.) and writes validated values under
**`/var/run/hw-management/config/`**. Use **`_comment_<field>`** keys in the
example JSON to document allowed values; they are ignored at runtime. The optional
**`pci`** section sets **`asic_pci_id`**, **`dpu_pci_id`**, and **`dpu_pci_addr`**
for **`set_asic_pci_id()`** / **`set_dpu_pci_id()`** on JSON platforms (replacing
per-SKU PCI ID variables in **`hw-management.sh`**). The optional **`board`**
section writes devtree topology keys (**`cpu_brd_bus_offset`**, **`swb_brd_num`**,
**`pwr_brd_num`**, offsets, VR/hotswap counts, etc.) and replaces
**`pre_devtr_init()`** SKU dispatch when platform JSON is present.

On new platforms the I2C connection table is built from **devtree**; the
**`connection`** section supplies **`named_busses`** (inline name/bus pairs) and
optional COMEx named-bus offsets. Use **`base_tables`**, **`dynamic_tables`**, or
inline **`base_connect`** / **`dynamic_connect`** only when devtree is absent.
**`named_busses_table`** (shell-array reference) and inline **`named_busses`**
are mutually exclusive. Mistyped values abort boot.
