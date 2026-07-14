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
| [vr_dpc_update_example.json](vr_dpc_update_example.json) | VR DPC bulk-update config for **`hw-management-vr-dpc-update-all.sh`**: **`System HID`**, **`Devices`** array (type, bus, addr, config files). |
| [vr_dpc_update_nn5500ld.json](vr_dpc_update_nn5500ld.json) | Platform-specific VR DPC update example (N5110 LD). |
| [pmbus_devices_example.json](pmbus_devices_example.json) | PMBus device list schema (**`devices`**: name, bus, slave address, pages). |
| [src/iorw/](src/iorw/) | Sample **iorw** userspace tool sources (LPC/I2C access). |
| [src/ev_hndl/](src/ev_hndl/) | Sample line-card / event-handler sources (C and Python). |

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
