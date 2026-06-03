# SONiC integration: usb0 (BMC ↔ host CPU)

This document describes what **SONiC** must provide on the **host CPU** and **BMC**
so the NOS owns **usb0** IP assignment. **hw-management-bmc** and **hw-management**
stay out of addressing when the opt-in flag (BMC) or SONiC detection (host) apply.

For implementation details in this package, see **`bmc/README.md`** (section *BMC usb0 /
systemd-networkd*).

### Config file naming

| Where | Filename | Notes |
|-------|----------|--------|
| **SONiC BMC image build** (SONiC tree) | **`bmc-network-sonic.conf`** | Source file **provided by SONiC**; content sets **`USB0_MANAGED_BY_NOS=1`**. |
| **BMC rootfs** (runtime) | **`/etc/<HID>/hw-management-bmc-network.conf`** | **Required** name for **hw-management-bmc**; install by copying/renaming from **`bmc-network-sonic.conf`**. |
| **hw-mgmt repo** (reference only) | **`usr/etc/<HID>/hw-management-bmc-network-sonic.conf.example`** | Example template shipped with **hw-management-bmc**; not a separate runtime file. |

SONiC does **not** ship a file called **`hw-management-bmc-network-sonic.conf`** on the
device. The long **`.example`** name in hw-mgmt is only a package reference; in the SONiC
repo use **`bmc-network-sonic.conf`** (or your layout) and deploy as
**`hw-management-bmc-network.conf`**.

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

1. **Release usb0 to SONiC** — in the **SONiC BMC image recipe**, install network
   config as **`/etc/<HID>/hw-management-bmc-network.conf`** (see [Config file naming](#config-file-naming)).
   Typical flow: maintain **`bmc-network-sonic.conf`** in the SONiC tree, then install it
   under the hw-management platform path at image build time.

   ```bash
   # Content (in bmc-network-sonic.conf or equivalent):
   USB0_MANAGED_BY_NOS=1
   ```

   At boot, **hw-management-bmc-plat-specific-preps** copies that file to
   **`/etc/hw-management-bmc-usb0.conf`**. Do **not** set **`USB0_ADDRESS=…`** on SONiC
   BMC images.

   Reference template in hw-mgmt:
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
   hw-management uses this to detect SONiC and **skip** **`ifup usb0`** from udev
   (**`hw-management-ifupdown.sh`**).

2. **Host usb0 configuration** — SONiC must configure **usb0** (platform recipe,
   networkd, init script, CONFIG_DB, etc.). Do **not** rely on **`/etc/network/interfaces`**
   + hw-management udev **`ifup`** on SONiC.

3. **BMC communication** — on SONiC, hw-management does **not** drive CPU↔BMC Redfish /
   password sync; SONiC owns that path. **usb0** must be reachable using SONiC’s
   addressing plan.

### What hw-management does on the host

- May rename the USB NIC to **usb0** (udev), where applicable.
- On SONiC: **does not** call **`ifup usb0`**.
- Does **not** assign a host **usb0** IP on SONiC.

### Host verification

```bash
test -f /etc/sonic/sonic_version.yml
ip link show usb0
ip -4 addr show dev usb0
```

---

## Integrator checklist

| Item | BMC SONiC image | Host SONiC image |
|------|-----------------|------------------|
| **`bmc-network-sonic.conf`** → **`hw-management-bmc-network.conf`** on BMC image | Required | N/A |
| **`USB0_MANAGED_BY_NOS=1`** in that config | Required | N/A (auto via **`sonic_version.yml`**) |
| No **`USB0_ADDRESS`** in hw-mgmt BMC config | Required | N/A |
| No **`00-hw-management-bmc-usb0.network`** at boot | Expected | N/A |
| **`sonic-usb-network-init`** (or equivalent) runs on BMC | Required | N/A |
| SONiC configures **usb0** IP | Required | Required |
| No static **usb0** for hw-mgmt **`ifup`** on host | N/A | Required |
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
| **`bmc/usr/etc/<HID>/hw-management-bmc-network-sonic.conf.example`** | hw-mgmt reference template (SONiC: use **`bmc-network-sonic.conf`** → install as **`hw-management-bmc-network.conf`**) |
| **`bmc/usr/etc/<HID>/hw-management-bmc-network.conf`** | Default non-SONiC platform config (**`USB0_ADDRESS`**) |
| **`bmc/usr/usr/bin/hw-management-bmc-usb0-common.sh`** | **`USB0_MANAGED_BY_NOS`** parser |
| **`bmc/usr/usr/bin/hw-management-bmc-plat-specific-preps.sh`** | Renders or skips **`.network`** unit |
| **`bmc/usr/usr/bin/hw-management-bmc-ready-common.sh`** | **`usb_net_config()`** |
| **`usr/usr/bin/hw-management-ifupdown.sh`** | Host udev **`ifup`** (skips **usb0** on SONiC) |
| **`usr/usr/bin/hw_management_sonic_check.py`** | SONiC host detection |
| **`bmc/README.md`** | Full BMC package and **usb0** documentation |
