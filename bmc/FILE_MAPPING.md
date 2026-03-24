<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# OpenBMC → bmc/ file mapping

Use this as a checklist when copying or updating files from the OpenBMC meta-nvidia tree into `bmc/`.

**OpenBMC base:** `/hdd/build/vadimp/develop-new/openbmc`

**Naming:** For any file that does not already **start** with `hw-management`, add the prefix `hw-management-` (e.g. `bmc-health-monitor.service` → `hw-management-bmc-health-monitor.service`). Use `bmc/copy-from-openbmc.sh` to copy with this rule.

---

## 1. systemd units → `bmc/usr/lib/systemd/system/`

| Source file | Destination |
|-------------|--------------|
| meta-nvidia/meta-switch/recipes-nvidia/**health-monitor**/files/bmc-health-monitor.service | **hw-management-bmc-health-monitor.service** |
| meta-nvidia/meta-switch/recipes-nvidia/**health-monitor**/files/bmc-reset-cause-logger.service | **hw-management-bmc-reset-cause-logger.service** |
| meta-nvidia/meta-switch/recipes-nvidia/**bmc-post-boot-cfg**/files/bmc-boot-complete.service | **hw-management-bmc-boot-complete.service** |
| meta-nvidia/meta-switch/recipes-nvidia/**bmc-post-boot-cfg**/files/bmc-early-i2c-init.service | **hw-management-bmc-early-i2c-init.service** |
| meta-nvidia/meta-switch/recipes-nvidia/**bmc-post-boot-cfg**/files/bmc-i2c-slave-setup.service | **hw-management-bmc-i2c-slave-setup.service** |
| meta-nvidia/meta-switch/recipes-nvidia/**bmc-post-boot-cfg**/files/bmc-plat-specific-preps.service | **hw-management-bmc-plat-specific-preps.service** |
| meta-nvidia/meta-switch/recipes-nvidia/**bmc-post-boot-cfg**/files/bmc-recovery-handler.service | **hw-management-bmc-recovery-handler.service** |
| *(SONiC BMC only; not copied from OpenBMC by default)* | **hw-management-bmc-early-config.service** |
| ~~bmc-svn-update.service~~ | removed (Microsoft doesn't need) |

---

## 1b. systemd-networkd template → `bmc/usr/etc/systemd/network/`

| Source file | Destination | Notes |
|-------------|-------------|--------|
| meta-nvidia/meta-switch/meta-ast2700/recipes-nvidia/**nvidia-internal-network-config**/files/00-bmc-usb0.network | **usr/etc/systemd/network/00-hw-management-bmc-usb0.network** | **`copy-from-openbmc.sh`** rewrites **`Address=…`** to **`Address=__USB0_ADDRESS__`**. Package installs as **`/usr/etc/systemd/network/`**; **`hw-management-bmc-plat-specific-preps`** renders **`/etc/systemd/network/00-hw-management-bmc-usb0.network`** at boot using **`USB0_ADDRESS`** from **`/etc/hw-management-bmc-usb0.conf`**. |
| *(SONiC coexistence)* | **usr/lib/systemd/system/sonic-usb-network-init.service.d/10-hw-management-bmc.conf** | **`ConditionPathExists=!`** our static **`usb0`** **`.network`** so SONiC’s **`sonic-usb-network-init`** (typically **`dhclient usb0`**) does not run when **`hw-management-bmc`** owns **`usb0`** via **`systemd-networkd`**. |

---

## 2. udev rules (BMC)

| Source file | Repo destination | Runtime |
|-------------|------------------|---------|
| meta-nvidia/.../meta-**spc6-ast2700-a1**/.../files/71-hw-management-events.rules | **usr/etc/HI189/5-hw-management-bmc-events.rules** (repo path; package installs **`/etc/HI189/5-…`**) (SONiC-style **`5-`** prefix; OpenBMC uses **`71-`**) | **`hw-management-bmc-plat-specific-preps`** symlinks to **`/lib/udev/rules.d/`** at boot |

Optional MCTP rules live as **`usr/etc/<HID>/99-hw-management-bmc-mctp.rules`** (SONiC BMC reference only). **`hw-management-bmc-plat-specific-preps`** does **not** install that file to **`/lib/udev/rules.d/`**; copy it manually on images that need it.

---

## 3. Platform-specific (HI189 / SPC6 AST2700 A1) → `bmc/usr/etc/HI189/`

On the target system the **hw-management-bmc** Debian package installs this tree as **`/etc/HI189/`** (built from **`bmc/usr/etc/HI189/`** in this repository). At boot, `hw-management-bmc-plat-specific-preps` uses `/etc/<HID>/` (fallback `/usr/etc/<HID>/` on older images) and copies/symlinks into `/etc/`, **`/etc/modprobe.d/`** ( **`hw-management-bmc.conf`** ), `/usr/bin/`, and `/lib/udev/rules.d/` as needed.

| Source file | Destination |
|-------------|--------------|
| .../spc6-ast2700-a1/.../a2d_leakage_config.json | usr/etc/HI189/**hw-management-bmc-a2d-leakage-config.json** |
| .../spc6-ast2700-a1/.../platform_config | usr/etc/HI189/**hw-management-bmc-platform.conf** |
| .../spc6-ast2700-a1/.../spc6-bmc.conf | usr/etc/HI189/**hw-management-bmc.conf** (→ **`/etc/modprobe.d/hw-management-bmc.conf`** at boot) |
| *(maintain in repo per platform)* | usr/etc/HI189/**hw-management-bmc-network.conf** (→ **`/etc/hw-management-bmc-usb0.conf`**, drives **`usb0`** **`Address=`** in generated **`.network`**) |
| *(SONiC BMC; not from OpenBMC)* | usr/etc/HI189/**hw-management-bmc-boot-complete.conf** (→ **`/etc/hw-management-bmc-boot-complete.conf`** at boot; thresholds for **`hw-management-bmc-boot-complete.sh`**) |
| .../spc6-ast2700-a1/.../spc6-ast2700-a1-bmc/ (directory) | usr/etc/HI189/ |

---

## 4. Scripts → `bmc/usr/usr/bin/`

| Source file | Destination |
|-------------|--------------|
| .../health-monitor/files/bmc-health-monitor.sh | usr/usr/bin/ |
| .../health-monitor/files/bmc-reset-cause-logger.sh | usr/usr/bin/ |
| .../bmc-post-boot-cfg/files/bmc-early-i2c-init.sh | usr/usr/bin/ |
| .../bmc-post-boot-cfg/files/bmc-i2c-slave-setup.sh | usr/usr/bin/ |
| .../bmc-post-boot-cfg/files/bmc-recovery-handler.sh | usr/usr/bin/ |
| .../meta-ast2700/.../bmc-plat-specific-preps.service (script: bmc-plat-specific-preps.sh from spc6) | usr/usr/bin/ |
| .../spc6-ast2700-a1/.../bmc_ready_common.sh | usr/usr/bin/**hw-management-bmc-ready-common.sh** |
| .../spc6-ast2700-a1/.../spc6-ast2700-a1-bmc_ready.sh | usr/usr/bin/**hw-management-bmc-ready.sh** (common; not per-HID) |
| .../spc6-ast2700-a1/.../hw-management.sh | usr/usr/bin/**hw-management-bmc.sh** |
| .../spc6-ast2700-a1/.../hw-management-devtree-check.sh | usr/usr/bin/**hw-management-bmc-devtree-check.sh** |
| .../spc6-ast2700-a1/.../hw-management-devtree.sh | usr/usr/bin/**hw-management-bmc-devtree.sh** |
| .../bmc-post-boot-cfg/files/**switch_json_parser.sh** | usr/usr/bin/**hw-management-bmc-json-parser.sh** |
| .../bmc-post-boot-cfg/files/**hw-management-helpers-common.sh** | usr/usr/bin/**hw-management-bmc-helpers-common.sh** |
| .../spc6-ast2700-a1/.../hw-management-helpers.sh | usr/usr/bin/**hw-management-bmc-helpers.sh** |
| .../spc6-ast2700-a1/.../spc6-ast2700-a1-hw-management-events.sh | usr/etc/HI189/**hw-management-bmc-events.sh** |
| .../spc6-ast2700-a1/.../bmc_set_extra_params.sh | usr/usr/bin/**hw-management-bmc-set-extra-params.sh** |
| ~~ast2700-a1-spc6-switch-erots-info.sh~~ | removed (Microsoft doesn't need) |
| .../spc6-ast2700-a1/.../bmc-plat-specific-preps.sh | usr/usr/bin/**hw-management-bmc-plat-specific-preps.sh** |
| *(SONiC BMC; replaces OpenBMC i2c-boot-progress.sh)* | usr/usr/bin/**hw-management-bmc-boot-complete.sh** |
| .../spc6-ast2700-a1/.../i2c-slave-config.sh | usr/usr/bin/**hw-management-bmc-i2c-slave-config.sh** |
| ~~spc6-svn-check.sh~~ | removed (Microsoft doesn't need) |
| meta-nvidia/meta-switch/recipes-phosphor/**dump**/files/**cpld_dump.sh** + **dump_utils.sh** ( **`take_cpld_dump_internal`**, **`take_cpld_dump`** only) | usr/usr/bin/**hw-management-bmc-cpld-dump.sh** (merged SONiC script; no **`switch-erots-info`** / Phosphor **`add_copy_file`**; **`log_message`** + **`hw-management-bmc-platform.conf`** via **`helpers-common`**) |
| *(SONiC BMC; analogous to host **`usr/usr/bin/hw-management-generate-dump.sh`**) | usr/usr/bin/**hw-management-bmc-generate-dump.sh** — bundle: **`dmesg`**, **`/proc/interrupts`**, **`ifconfig`**, **`i2cdetect -y`** per non-mux bus (**`i2cdetect -l \| grep -v mux`**), CPLD (**`take_cpld_dump`**), **`systemctl`** (**`hw-management-bmc*`**), **`/var/run/hw-management`** (**`hexdump -C`** on EEPROM) → **`/tmp/hw-mgmt-bmc-dump.tar.gz`**. |

---

## Copy commands (skeleton)

From repo root `hw-mgmt`:

```bash
OPENBMC=/hdd/build/vadimp/develop-new/openbmc
S=meta-nvidia/meta-switch
A=meta-ast2700/meta-spc6-ast2700-a1/recipes-nvidia/bmc-post-boot-cfg/files

# systemd
cp "$OPENBMC/$S/recipes-nvidia/health-monitor/files/"*.service bmc/usr/lib/systemd/system/
cp "$OPENBMC/$S/recipes-nvidia/bmc-post-boot-cfg/files/"*.service bmc/usr/lib/systemd/system/
# bmc-svn-update.service removed (Microsoft doesn't need)

# systemd-networkd template (usb0 BMC↔CPU link)
mkdir -p bmc/usr/etc/systemd/network
NIC=meta-ast2700/recipes-nvidia/nvidia-internal-network-config/files
sed 's/^Address=.*/Address=__USB0_ADDRESS__/' \
  "$OPENBMC/$S/$NIC/00-bmc-usb0.network" \
  >bmc/usr/etc/systemd/network/00-hw-management-bmc-usb0.network

# udev
cp "$OPENBMC/$S/$A/71-hw-management-events.rules" bmc/usr/etc/HI189/5-hw-management-bmc-events.rules

# Platform HI189
cp "$OPENBMC/$S/$A/a2d_leakage_config.json" bmc/usr/etc/HI189/hw-management-bmc-a2d-leakage-config.json
cp "$OPENBMC/$S/$A/platform_config" bmc/usr/etc/HI189/hw-management-bmc-platform.conf
cp "$OPENBMC/$S/$A/spc6-bmc.conf" bmc/usr/etc/HI189/hw-management-bmc.conf
cp -a "$OPENBMC/$S/$A/spc6-ast2700-a1-bmc" bmc/usr/etc/HI189/
cp "$OPENBMC/$S/$A/spc6-ast2700-a1-bmc_ready.sh" bmc/usr/usr/bin/hw-management-bmc-ready.sh

# Scripts (expand as needed)
cp "$OPENBMC/$S/recipes-nvidia/health-monitor/files/"*.sh bmc/usr/usr/bin/
cp "$OPENBMC/$S/recipes-nvidia/bmc-post-boot-cfg/files/bmc-early-i2c-init.sh" bmc/usr/usr/bin/
cp "$OPENBMC/$S/recipes-nvidia/bmc-post-boot-cfg/files/hw-management-helpers-common.sh" bmc/usr/usr/bin/hw-management-bmc-helpers-common.sh
# ... etc.
```

Update this file as files are added or paths change.
