<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# BMC platform bring-up: supporting a new `HINNN` (e.g. HI189 → HI162)

This guide lists what a developer must add so **SONiC BMC** **hw-management-bmc** can deploy a new hardware ID (**`HINNN`**) alongside the existing reference **HI189** tree under **`bmc/usr/etc/`**.

## HID mapping (runtime)

- At boot, **`hw-management-bmc-plat-specific-preps.sh`** discovers **`hidNNN`** from device-tree (directory names like **`nvsw_bmc_hid189@31`**).
- It maps **`hidNNN` → `HINNN`** by replacing the `hid` prefix with **`HI`** (e.g. **`hid189`** → **`HI189`**).
- Packaged content is expected under **`/etc/HINNN/`** on the image (installed from **`bmc/usr/etc/HINNN/`** in this repository), with fallback **`/usr/etc/HINNN/`** on older layouts.
- Debug override: **`HW_MANAGEMENT_BMC_HID_OVERRIDE=hidNNN`** (see **`bmc/README.md`**).

If the kernel does not expose a matching **`nvsw_bmc_hid…`** node for the new BMC SKU, HID detection fails and platform deploy is skipped until DT and packaging exist.

## 1. Platform directory: `bmc/usr/etc/HINNN/`

Create **`bmc/usr/etc/HINNN/`** and ship the same *kinds* of artifacts as **HI189**. Below: **mandatory** vs **optional** for a typical Mellanox BMC platform using the full init stack.

| File | Required | Notes |
|------|----------|--------|
| **`5-hw-management-bmc-events.rules`** | **Yes** | Udev rules that drive **`hw-management-bmc-events.sh`** and populate **`/var/run/hw-management/system`**, **thermal**, **eeprom**. Without them, **`hw-management-bmc-boot-complete`** may never satisfy its counters. |
| **`hw-management-bmc-events.sh`** | **Yes** | Invoked from udev **`RUN`**; plat-specific-preps symlinks **`*.sh`** into **`/usr/bin/`**. |
| **`hw-management-bmc.conf`** | **Yes** | Modprobe snippet; symlinked to **`/etc/modprobe.d/hw-management-bmc.conf`**. |
| **`hw-management-bmc-gpio-pins.json`** | **Yes** (for GPIO-based bring-up) | Consumed by **`hw-management-bmc-gpio-set.sh`** during **`hw-management-bmc-ready.sh`**. If missing, GPIO init is skipped and standby / symlink setup may not match hardware. |
| **`hw-management-bmc-early-i2c-devices.json`** | **Yes** (when early I2C is used) | Copied by **`hw-management-bmc-early-config.sh`** to **`/etc/hw-management-bmc-early-i2c-devices.json`** for **`hw-management-bmc-early-i2c-init`**. Provide at least a valid minimal array if the service is enabled. |
| **`hw-management-bmc-platform.conf`** | Recommended | Power policy (**`POWER_ON_POLICY`**, **`POWER_POLICY_DELAY`**), **`MGMT_IF_NUM`**, **`CPLD_I2C_BUS`**, etc. Copied to **`/etc/hw-management-bmc-platform.conf`** when present. |
| **`hw-management-bmc-eeprom.conf`** | Optional | Overrides VPD EEPROM path and field layout in **`hw-management-bmc-ready-common.sh`** when installed to **`/etc/hw-management-bmc-eeprom.conf`**. |
| **`hw-management-bmc-boot-complete.conf`** | Optional | Minimum sysfs entry counts for **`hw-management-bmc-boot-complete.sh`**. |
| **`hw-management-bmc-bom.json`** | Optional | SMBIOS BOM alternate maps for **`hw-management-bmc-devtree.sh`** when copied to **`/etc/hw-management-bmc-bom.json`**. |
| **`hw-management-bmc-a2d-leakage-config.json`** | Optional | Only if the board uses the A2D leakage stack; otherwise omit or ship an empty / no-op policy per tooling expectations. |
| **`hw-management-bmc-network.conf`** | Optional | **`USB0_ADDRESS=…`** for BMC↔host **`usb0`**; defaults exist in plat-specific-preps when this file is absent. |
| **`99-hw-management-bmc-mctp.rules`** | Optional | IRoT MCTP (**`mctpirot*`**). Omit if the SKU has no such net devices. |

All **`*.json`** files in the directory are **copied** to **`/etc/`** at boot (plat-specific-preps). All **`*.rules`** are **symlinked** into **`/lib/udev/rules.d/`**.

Deploy behavior is implemented in **`bmc/usr/usr/bin/hw-management-bmc-plat-specific-preps.sh`** and **`bmc/usr/usr/bin/hw-management-bmc-early-config.sh`**; read those scripts when in doubt.

## 2. Kernel / device-tree (platform driver)

The userspace package assumes a **Mellanox `nvsw_bmc` platform** driver exposes the expected **mlxreg-io / mlxreg-hotplug** sysfs layout and (where applicable) the **CPLD / I2C** topology your **HI** JSON and rules reference.

For **Linux 6.12** BMC kernels in this tree, new **`HINNN` / `hidNNN`** support is normally developed **on top of** the existing downstream platform series, including at least:

- **`recipes-kernel/linux/linux-6.12/0046-platform-mellanox-nvsw-bmc-Add-system-control-and-mo.patch`**
- **`recipes-kernel/linux/linux-6.12/0060-platform-mellanox-nvsw-bmc-Downstream-Add-protection.patch`**

If your branch carries **renumbered or merged** equivalents of those changes, base your new HID work on the **effective baseline** that already contains the same functionality (system control / protection paths), then add a **follow-on patch** (or DTS-only delta) that:

- Introduces or extends the **`nvsw_bmc_hidNNN@…`** compatible / board data expected by userspace, and
- Keeps attribute names and parents aligned with what **`5-hw-management-bmc-events.rules`** and **`hw-management-bmc-events.sh`** expect (compare to **HI189**).

Use **`recipes-kernel/linux/deploy_kernel_patches.py`** and the appropriate **`Patch_Status_Table.txt`** / **`Patch_BMC_Status_Table.txt`** flow (see **`bmc/README.md`** § *Deployment of BMC kernel patches*).

## 3. Debian packaging

**`debian/rules`** must install the new tree into the **`hw-management-bmc`** package, mirroring **HI189**. Today the pattern is:

```makefile
dh_installdirs -p$(pname_bmc) etc/HI189
cp -a bmc/usr/etc/HI189/* debian/$(pname_bmc)/etc/HI189/
```

For **`HINNN`**, add parallel **`dh_installdirs`** and **`cp -a bmc/usr/etc/HINNN/ …`** lines (and update **`debian/control`** description if you document supported platforms there).

## 4. Validation checklist

- [ ] **`bmc/usr/etc/HINNN/`** present with mandatory files for your SKU.
- [ ] **`debian/rules`** installs **`/etc/HINNN/`** on the image.
- [ ] Device-tree exposes **`nvsw*hidNNN*`** so plat-specific-preps resolves **`sku`**.
- [ ] Kernel patches / DTS applied; **`mlxreg-io`** / **`mlxreg-hotplug`** nodes match rules and **`hw-management-bmc-gpio-pins.json`**.
- [ ] Boot: **`journalctl -b -u hw-management-bmc-plat-specific-preps`**, **`-u hw-management-bmc-init`**, **`udevadm verify`** / rules under **`/lib/udev/rules.d/`**.

## 5. Further reading

- **`bmc/README.md`** — package layout, systemd units, USB0, examples index.
- **`bmc/FILE_MAPPING.md`** — OpenBMC → SONiC BMC path mapping.
- **`bmc/examples/`** — reference configs (**`hw-management-bmc-platform-config.txt`**, eeprom, GPIO, boot-complete, …).
