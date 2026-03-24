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

## 2. udev rules (BMC)

| Source file | Repo destination | Runtime |
|-------------|------------------|---------|
| meta-nvidia/.../meta-**spc6-ast2700-a1**/.../files/71-hw-management-events.rules | **usr/etc/HI193/** | **`hw-management-bmc-plat-specific-preps`** copies to **`/lib/udev/rules.d/`** at boot |

Shared (non-platform) BMC udev snippets may live under `bmc/usr/lib/udev/rules.d/` (e.g. `99-mctp.rules` today—**subject to removal**), installed by the package to `/lib/udev/rules.d/` when present.

---

## 3. Platform-specific (HI193 / SPC6 AST2700 A1) → `bmc/usr/etc/HI193/`

On the target system the **hw-management-bmc** Debian package installs this tree as **`/usr/etc/HI193/`** (not under `/etc/`). At boot, `hw-management-bmc-plat-specific-preps` copies from `/usr/etc/<HID>/` into `/etc/`, **`/etc/modprobe.d/`** ( **`hw-management-bmc.conf`** ), `/usr/bin/`, and `/lib/udev/rules.d/` as needed.

| Source file | Destination |
|-------------|--------------|
| .../spc6-ast2700-a1/.../a2d_leakage_config.json | usr/etc/HI193/**hw-management-a2d-leakage-config.json** |
| .../spc6-ast2700-a1/.../platform_config | usr/etc/HI193/**hw-management-platform.conf** |
| .../spc6-ast2700-a1/.../spc6-bmc.conf | usr/etc/HI193/**hw-management-bmc.conf** (→ **`/etc/modprobe.d/hw-management-bmc.conf`** at boot) |
| .../spc6-ast2700-a1/.../spc6-ast2700-a1-bmc/ (directory) | usr/etc/HI193/ |

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
| .../spc6-ast2700-a1/.../spc6-ast2700-a1-bmc_ready.sh | usr/etc/HI193/ (platform-specific) |
| .../spc6-ast2700-a1/.../hw-management.sh | usr/usr/bin/**hw-management-bmc.sh** |
| .../spc6-ast2700-a1/.../hw-management-devtree-check.sh | usr/usr/bin/**hw-management-bmc-devtree-check.sh** |
| .../spc6-ast2700-a1/.../hw-management-devtree.sh | usr/usr/bin/**hw-management-bmc-devtree.sh** |
| .../spc6-ast2700-a1/.../hw-management-helpers.sh | usr/usr/bin/**hw-management-bmc-helpers.sh** |
| .../spc6-ast2700-a1/.../spc6-ast2700-a1-hw-management-events.sh | usr/etc/HI193/ (platform-specific) |
| .../spc6-ast2700-a1/.../bmc_set_extra_params.sh | usr/usr/bin/**hw-management-bmc-set-extra-params.sh** |
| ~~ast2700-a1-spc6-switch-erots-info.sh~~ | removed (Microsoft doesn't need) |
| .../spc6-ast2700-a1/.../bmc-plat-specific-preps.sh | usr/usr/bin/**hw-management-bmc-plat-specific-preps.sh** |
| .../spc6-ast2700-a1/.../i2c-boot-progress.sh | usr/usr/bin/**hw-management-bmc-i2c-boot-progress.sh** |
| .../spc6-ast2700-a1/.../i2c-slave-config.sh | usr/usr/bin/**hw-management-bmc-i2c-slave-config.sh** |
| ~~spc6-svn-check.sh~~ | removed (Microsoft doesn't need) |

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

# udev
cp "$OPENBMC/$S/$A/71-hw-management-events.rules" bmc/usr/etc/HI193/

# Platform HI193
cp "$OPENBMC/$S/$A/a2d_leakage_config.json" bmc/usr/etc/HI193/hw-management-a2d-leakage-config.json
cp "$OPENBMC/$S/$A/platform_config" bmc/usr/etc/HI193/hw-management-platform.conf
cp "$OPENBMC/$S/$A/spc6-bmc.conf" bmc/usr/etc/HI193/hw-management-bmc.conf
cp -a "$OPENBMC/$S/$A/spc6-ast2700-a1-bmc" bmc/usr/etc/HI193/

# Scripts (expand as needed)
cp "$OPENBMC/$S/recipes-nvidia/health-monitor/files/"*.sh bmc/usr/usr/bin/
cp "$OPENBMC/$S/recipes-nvidia/bmc-post-boot-cfg/files/bmc-early-i2c-init.sh" bmc/usr/usr/bin/
# ... etc.
```

Update this file as files are added or paths change.
