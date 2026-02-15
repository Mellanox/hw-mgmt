# hw-management BMC (SONiC BMC / Microsoft Sonic BMC OS)

This directory contains the BMC-side components for building the **hw-management** Debian package for systems using **AST2700** with **Microsoft Sonic BMC OS** (instead of OpenBMC).

The layout mirrors the main `hw-mgmt` tree so the same packaging approach (e.g. `debian/rules` copying from `usr/`) can be used when building the BMC variant of the package.

## Directory layout

```
bmc/
├── recipes-kernel/
│   ├── linux/linux-6.12/              # BMC kernel patches (from OpenBMC ast2700 + spc6-ast2700-a1)
│   └── u-boot/<version>/              # U-Boot DTS and config per version (e.g. 2023.10)
├── usr/
│   ├── etc/                    # Config and platform-specific data
│   │   └── HI193/              # Platform: SPC6 AST2700 A1 (Spectrum-6)
│   │       # Config: a2d_leakage_config.json, platform_config, spc6-bmc.conf
│   │       # Platform scripts: hw-management-spc6-ast2700-a1-bmc_ready.sh,
│   │       #   hw-management-spc6-ast2700-a1-hw-management-events.sh
│   │       # At boot, hw-management-early-config.service (before kernel modules)
│   │       # copies these from /etc/<HID>/ to /etc/hw-management-bmc/ and /usr/bin/.
│   ├── lib/
│   │   ├── systemd/system/     # systemd unit files (.service)
│   │   └── udev/rules.d/       # udev rules (e.g. 71-hw-management-events.rules)
│   └── usr/bin/               # Scripts (hw-management.sh, bmc_ready_common.sh, etc.)
└── README.md                  # This file
```

- **Platform-specific content** lives under `usr/etc/<PLATFORM_ID>/`, where `<PLATFORM_ID>` is the system hardware ID (e.g. **HI193** for SPC6 AST2700 A1). Additional platforms can use other IDs (e.g. HI162, HI176, HI180, HI185).
- **Shared** scripts, udev rules, and systemd units live under `usr/lib/` and `usr/usr/bin/`.

### Early config service (`hw-management-early-config`)

Runs **before** kernel modules load (`Before=systemd-modules-load.service`). It copies files from `/etc/<HID>/` (package-installed) to their runtime locations:

| Source under `/etc/<HID>/` | Runtime location |
|----------------------------|------------------|
| hw-management-a2d_leakage_config.json | /etc/hw-management-bmc/a2d_leakage_config.json |
| hw-management-platform_config | /etc/hw-management-bmc/platform_config |
| hw-management-spc6-bmc.conf | /etc/hw-management-bmc/spc6-bmc.conf |
| hw-management-spc6-ast2700-a1-bmc/bmc-early-i2c-devices.json | /etc/bmc-early-i2c-devices.json |
| hw-management-spc6-ast2700-a1-bmc_ready.sh | /usr/bin/ |
| hw-management-spc6-ast2700-a1-hw-management-events.sh | /usr/bin/ |

**HID** defaults to **HI193**; override with env `HID=<id>`. Later: detect HID from BMC system EEPROM.

### Power control (`hw-management-powerctrl.sh`)

Host/board power actions (power_on, power_off, reset, reset_board, grace_off, grace_reset) via sysfs. No dependency on phosphor or bmc-boot-complete. Host state D-Bus updates (when available) go through `hw-management-dbus-if.sh`.

### D-Bus abstraction (`hw-management-dbus-if.sh`)

All D-Bus (busctl/dbus-send) usage in bmc is centralized here so the backend can be swapped for SONiC BMC or other stacks. Commands: `host_state_off` / `host_state_on`, `requested_host_transition_on` / `requested_host_transition_off`, `power_restore_delay` / `power_restore_policy`, `chassis_power_state_on`, `software_settings_set_write_protect_init`, `user_manager_get_groups` / `user_manager_set_groups` / `user_manager_create_user`, `syslog_config_get_address` / `syslog_config_get_port` / `syslog_config_enable`, `logging_create_resource_corrected` / `logging_create_resource_detected` / `logging_create_reboot_reason` / `logging_create_resource_warning`, `factory_reset`. Run with no args for usage.

## Source mapping (OpenBMC → bmc/)

| OpenBMC path | bmc/ destination |
|--------------|-------------------|
| meta-nvidia/meta-switch/recipes-nvidia/**health-monitor**/files/*.service | usr/lib/systemd/system/ |
| meta-nvidia/meta-switch/recipes-nvidia/**bmc-post-boot-cfg**/files/*.service | usr/lib/systemd/system/ |
| meta-nvidia/meta-switch/meta-ast2700/meta-**spc6-ast2700-a1**/.../71-hw-management-events.rules | usr/lib/udev/rules.d/ |
| meta-nvidia/meta-switch/meta-ast2700/meta-**spc6-ast2700-a1**/.../a2d_leakage_config.json, platform_config, spc6-bmc.conf, spc6-ast2700-a1-bmc/ | usr/etc/HI193/ |
| meta-nvidia/.../bmc-post-boot-cfg/files/*.sh, spc6-ast2700-a1/.../*.sh, hw-management*.sh, etc. | usr/usr/bin/ |

See **FILE_MAPPING.md** in this directory for the full list and copy/update steps.

## Related deliverables (for Microsoft SONiC BMC)

- Platform-specific kernel patches  
- DTS (device tree)  
- Low-level Debian package (this tree)  
- Leakage detection service  
- Power control  
- Networking: USB host–BMC interface  
- MCTP: MCTP over I3C to Spectrum-6 ASICs, MCTP over IRoT for BMC  

See **doc/SONiC_BMC_NVIDIA_Deliverables.md** in the repo for the high-level doc aimed at the Microsoft team.
