<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# HIxxx platform examples (template)

Copy this directory to `bmc/examples/<HID>/examples/` when adding BMC stack support for a new platform.

Replace `HIxxx` with the hardware ID (for example `HI195`).

## Checklist for a new HID

1. Add `usr/etc/<HID>/` packaging (rules, events, GPIO JSON, early I2C map).
2. Copy [hw-management-bmc-thermal-sysfs.txt](../../hw-management-bmc-thermal-sysfs.txt) into this directory and update:
   - I2C addresses / DEVPATH globs in udev rules
   - Driver notes (`sbtsi`, `lm75`, etc.) and which `temp1_*` attributes exist
3. Add HID-specific example files here (thermal, leakage, system sysfs) as needed.
4. Update [../../README.md](../../README.md) and the user manual §3.20 BMC thermal sections if node names differ.

## Files typically placed here

| File | Purpose |
|------|---------|
| `hw-management-bmc-thermal-sysfs.txt` | `/var/run/hw-management/thermal/` runtime symlinks |
| (optional) `hw-management-bmc-system-sysfs.txt` | `/var/run/hw-management/system/` layout |
| (optional) `hw-management-bmc-leakage-sysfs.txt` | `/var/run/hw-management/leakage/` layout |

Leave this template directory unchanged; platform content lives only under `bmc/examples/<HID>/examples/`.
