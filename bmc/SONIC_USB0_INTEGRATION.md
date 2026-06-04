# SONiC integration: usb0 (BMC ↔ host CPU)

This document describes what **SONiC** must provide on the **host CPU** and **BMC**
so the NOS owns **usb0** IP assignment. **hw-management-bmc** and **hw-management**
stay out of addressing when the opt-in flag (BMC) or SONiC detection (host) apply.

For implementation details in this package, see **`bmc/README.md`** (section *BMC usb0 /
systemd-networkd*).

### Config file naming

| Where | Path | Notes |
|-------|------|--------|
| **SONiC BMC image (runtime)** | **`/etc/bmc-network-sonic.conf`** | **Preferred** well-known path; SONiC installs content here. |
| **SONiC BMC image (runtime, alt)** | **`/etc/bmc-usb-network.conf`** | Optional alias if SONiC prefers a shorter name (checked if primary is absent). |
| **hw-management runtime** | **`/etc/hw-management-bmc-usb0.conf`** | Written at boot by plat-specific-preps (copy of NOS file or HID platform file). |
| **Non-SONiC BMC (HID platform)** | **`/etc/<HID>/hw-management-bmc-network.conf`** | Legacy static **`USB0_ADDRESS`** path when no NOS file is present. |
| **hw-mgmt repo (reference)** | **`usr/etc/<HID>/hw-management-bmc-network-sonic.conf.example`** | Example content only; not read from the package path at runtime. |

**To agree with SONiC:** source filename and recipe layout in the SONiC tree are
**SONiC’s choice**. The **runtime contract** is: install **`USB0_MANAGED_BY_NOS=1`** at
**`/etc/bmc-network-sonic.conf`** (or **`/etc/bmc-usb-network.conf`**). No rename into
**`/etc/<HID>/`** is required.

**SONiC deliverable:** ship a file on the BMC rootfs with:

```bash
USB0_MANAGED_BY_NOS=1
```

at **`/etc/bmc-network-sonic.conf`** (preferred). Do **not** set **`USB0_ADDRESS`** there.

---

## Overview

| Side | hw-management role | SONiC role |
|------|------------------|------------|
| **BMC** | Link up (`g_ether`); no static IP, no `.network` unit | Configure **usb0** (e.g. `sonic-usb-network-init`) |
| **Host CPU** | No `ifup usb0` on SONiC | Configure **usb0** via SONiC networking |

**Rule:** Only one stack must assign **usb0** on each side. Do not combine hw-management
static **`USB0_ADDRESS`** / **systemd-networkd** with SONiC **`dhclient`** on the same
interface.

---

## BMC (SONiC BMC image)

### Image / BSP requirements

1. **Release usb0 to SONiC** — install **`/etc/bmc-network-sonic.conf`** on the SONiC BMC
   image (see [Config file naming](#config-file-naming)). Source name in the SONiC git tree
   is flexible; only the **runtime path** on the BMC must match the contract.

   ```bash
   # /etc/bmc-network-sonic.conf (on BMC rootfs)
   USB0_MANAGED_BY_NOS=1
   ```

   At boot, **hw-management-bmc-plat-specific-preps** copies that file to
   **`/etc/hw-management-bmc-usb0.conf`** only when **`USB0_MANAGED_BY_NOS=1`** is set
   there.    A NOS path without the flag is ignored and the HID static config is used
   instead. Stale **`/etc/hw-management-bmc-usb0.conf`** from an earlier SONiC boot
   is not honored unless a live NOS or HID source sets the flag again this boot.
   Do **not** set **`USB0_ADDRESS=…`** on SONiC BMC images.

   Reference content in hw-mgmt:
   **`usr/etc/<HID>/hw-management-bmc-network-sonic.conf.example`**.

2. **SONiC BMC usb0 init** — **`sonic-usb-network-init.service`** must be present and
   allowed to run:
   - With **`USB0_MANAGED_BY_NOS=1`**, hw-management does **not** create
     **`/etc/systemd/network/00-hw-management-bmc-usb0.network`**.
   - Without that file, the hw-management drop-in
     (**`sonic-usb-network-init.service.d/10-hw-management-bmc.conf`**) does **not**
     block SONiC; **`sonic-usb-network-init`** may run (typically **`dhclient usb0`**).

3. **Addressing policy** — SONiC defines how **usb0** gets an address on the BMC
   (DHCP, static from CONFIG_DB / template / script, etc.). Agree with platform/BSP on
   BMC vs host addresses (e.g. link-local **`169.254.0.0/16`**, who is **`.1`** / **`.2`**).

### What hw-management-bmc still does

- Loads **`g_ether`** and brings **usb0** up (no static **`ip addr`**, no static
  **systemd-networkd** unit for addressing).
- Does **not** assign an IP when **`USB0_MANAGED_BY_NOS=1`**.

### BMC verification

```bash
grep USB0 /etc/hw-management-bmc-usb0.conf
test ! -f /etc/systemd/network/00-hw-management-bmc-usb0.network
systemctl status sonic-usb-network-init
ip -4 addr show dev usb0
```

---

## Host CPU (SONiC switch / NOS)

### Image / recipe requirements

1. **SONiC identity** — host image includes **`/etc/sonic/sonic_version.yml`**.

2. **Host NOS contract (aligned with BMC)** — when both sides use NOS-owned **usb0**,
   the **SONiC host** image must also ship **`/etc/bmc-network-sonic.conf`** (or
   **`/etc/bmc-usb-network.conf`**). **`hw-management-ifupdown.sh`** skips **`ifup
   usb0`** only when SONiC **and** that file exists. If the host is SONiC but the
   file is missing (BMC still on static **usb0**), the host keeps the normal **ifup**
   path so **usb0** can be configured on both sides.

3. **Host usb0 configuration** — when the contract file is present, SONiC must
   configure **usb0** (platform recipe,
   networkd, init script, CONFIG_DB, etc.). Do **not** rely on **`/etc/network/interfaces`**
   + hw-management udev **`ifup`** on SONiC.

4. **BMC communication** — on SONiC, hw-management does **not** drive CPU↔BMC Redfish /
   password sync; SONiC owns that path. **usb0** must be reachable using SONiC’s
   addressing plan.

### What hw-management does on the host

- May rename the USB NIC to **usb0** (udev), where applicable.
- On SONiC **with** **`/etc/bmc-network-sonic.conf`** (or alt): **does not** call
  **`ifup usb0`**. Without that file, **ifup** runs (misaligned / static-BMC case).
- Other interfaces / missing **`/etc/network/interfaces`**: unchanged defensive behavior
  (silent **exit 0**, auto/hotplug class guard via **`ifquery -l`**).
- Does **not** assign a host **usb0** IP when the NOS contract file is present (SONiC owns it).

### Host verification

```bash
test -f /etc/sonic/sonic_version.yml
test -f /etc/bmc-network-sonic.conf || test -f /etc/bmc-usb-network.conf
ip link show usb0
ip -4 addr show dev usb0
```

---

## Integrator checklist

| Item | BMC SONiC image | Host SONiC image |
|------|-----------------|------------------|
| **`/etc/bmc-network-sonic.conf`** (or **`/etc/bmc-usb-network.conf`**) on BMC image | Required | N/A |
| **`USB0_MANAGED_BY_NOS=1`** in that config | Required | N/A (auto via **`sonic_version.yml`**) |
| No **`USB0_ADDRESS`** in hw-mgmt BMC config | Required | N/A |
| No **`00-hw-management-bmc-usb0.network`** at boot | Expected | N/A |
| **`sonic-usb-network-init`** (or equivalent) runs on BMC | Required | N/A |
| SONiC configures **usb0** IP | Required | Required (when contract file present) |
| **`/etc/bmc-network-sonic.conf`** (or alt) on **host** when using NOS mode | N/A | Required |
| No static **usb0** for hw-mgmt **`ifup`** on host | N/A | Only when host contract file present |
| Agreed BMC / host IP plan | Required | Required |

---

## Non-SONiC (unchanged)

Without **`USB0_MANAGED_BY_NOS=1`** on the BMC and without SONiC on the host,
hw-management keeps the legacy path: **`USB0_ADDRESS`** + **systemd-networkd** on the
BMC, **`ifup`** on the host where **`/etc/network/interfaces`** defines **usb0**.

---

## Related files in this repository

| Path | Purpose |
|------|---------|
| **`bmc/usr/etc/<HID>/hw-management-bmc-network-sonic.conf.example`** | Example content for **`/etc/bmc-network-sonic.conf`** |
| **`bmc/usr/usr/bin/hw-management-bmc-usb0-common.sh`** | NOS well-known paths + **`USB0_MANAGED_BY_NOS`** parser |
| **`bmc/usr/etc/<HID>/hw-management-bmc-network.conf`** | Default non-SONiC platform config (**`USB0_ADDRESS`**) |
| **`bmc/usr/usr/bin/hw-management-bmc-plat-specific-preps.sh`** | Renders or skips **`.network`** unit |
| **`bmc/usr/usr/bin/hw-management-bmc-ready-common.sh`** | **`usb_net_config()`** |
| **`usr/usr/bin/hw-management-ifupdown.sh`** | Host udev **`ifup`** (skips **usb0** when SONiC + contract file) |
| **`usr/usr/bin/hw-management-helpers.sh`** | **`check_host_usb0_managed_by_nos()`** |
| **`usr/usr/bin/hw_management_sonic_check.py`** | SONiC host detection |
| **`bmc/README.md`** | Full BMC package and **usb0** documentation |
