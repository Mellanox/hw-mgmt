<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# `bmc/examples/`

Reference material for SONiC BMC **hw-management-bmc** tooling: sample JSON and text descriptions of runtime sysfs layouts. These files are **not** installed automatically by the scripts under **`bmc/usr/`** unless your packaging explicitly copies them.

| File | Purpose |
|------|---------|
| [hw-management-bmc-a2d-leakage-config-example.json](hw-management-bmc-a2d-leakage-config-example.json) | A2D leakage config: field reference, example array, deploy notes → **`/etc/hw-management-bmc-a2d-leakage-config.json`**. |
| [hw-management-bmc-bom-example.json](hw-management-bmc-bom-example.json) | SMBIOS BOM alternate maps for **`hw-management-bmc-devtree.sh`**: **`swb`** / **`platform`** / **`pwr`** arrays → deploy as **`/etc/hw-management-bmc-bom.json`** (from **`usr/etc/<HID>/hw-management-bmc-bom.json`** on the image). Schema only; I2C bus numbers are platform-specific. |
| [hw-management-bmc-gpio-config-example.json](hw-management-bmc-gpio-config-example.json) | GPIO JSON for **`bmc_init_sysfs_gpio`**: **`field_reference`**, deployable **`example_platform`** → **`/etc/hw-management-bmc-gpio-pins.json`**. |
| [hw-management-bmc-leakage-sysfs.txt](hw-management-bmc-leakage-sysfs.txt) | **`/var/run/hw-management/leakage/`** tree (detectors, channels, **`type`**, **`ChnlNames`**, handler artifacts). |
| [hw-management-bmc-system-sysfs.txt](hw-management-bmc-system-sysfs.txt) | **`/var/run/hw-management/system/`**: mlxreg-io (**regio**) + mlxreg-hotplug labels from **`nvsw_bmc_hid189_*`** (kernel patch), udev **`5-hw-management-bmc-events.rules`**, GPIO symlinks from **`hw-management-bmc-gpio-pins.json`**. |
| [hw-management-bmc-eeprom-config.txt](hw-management-bmc-eeprom-config.txt) | **`/etc/hw-management-bmc-eeprom.conf`**: VPD EEPROM variables (**`eeprom_file`**, HID/BOM offsets); defaults in **`ready-common.sh`**, override via plat-specific **usr/etc/&lt;HID&gt;/**. |
| [hw-management-bmc-eeprom-sysfs.txt](hw-management-bmc-eeprom-sysfs.txt) | **`/var/run/hw-management/eeprom/`** symlinks (**`eeprom_system`**, **`eeprom_bmc`**). |
| [hw-management-bmc-thermal-sysfs.txt](hw-management-bmc-thermal-sysfs.txt) | **`/var/run/hw-management/thermal/`** symlinks (CPU/BMC hwmon). |
| [hw-management-bmc-boot-complete-config.txt](hw-management-bmc-boot-complete-config.txt) | **`/etc/hw-management-bmc-boot-complete.conf`**: minimum entry counts for **`system`**, **`thermal`**, **`eeprom`** runtime dirs; **`hw-management-bmc-boot-complete.sh`**. |

See the parent **[`../README.md`](../README.md)** § **Examples (`bmc/examples/`)** for the same summary in the main BMC document.
