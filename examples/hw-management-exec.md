<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->
<!-- Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved. -->
<!--
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the names of the copyright holders nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

Alternatively, this software may be distributed under the terms of the
GNU General Public License ("GPL") version 2 as published by the Free
Software Foundation.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
-->

# Host hw-management executable attributes

Platform-specific helpers are defined in JSON and exposed at runtime in
**BusyBox applet style**: one dispatcher script and symlinks per attribute
(I2C bit set/clear, CPLD/sysfs actions, GPIO, and so on) without hard-coding
those commands in **`hw-management.sh`**.

This document describes the **host CPU** package only (`hw-management`, not BMC).

## Components

| Item | Installed path | Role |
|------|----------------|------|
| [hw-management-exec](../usr/usr/bin/hw-management-exec) | `/usr/bin/hw-management-exec` | Dispatcher (symlink target; must not live under `/var/run` if that mount is `noexec`) |
| [hw-management-exec-parser.sh](../usr/usr/bin/hw-management-exec-parser.sh) | `/usr/bin/hw-management-exec-parser.sh` | Reads JSON, creates symlinks + `.env` fragments |
| [hw-management-json-parser.sh](../usr/usr/bin/hw-management-json-parser.sh) | `/usr/bin/hw-management-json-parser.sh` | JSON helpers using **`jq`** (host CPU) |
| Shared config | `/etc/hw-management-exec/*.json` | One file can list many HIDs in a `"hids"` array |
| Per-HID override | `/etc/<HID>/hw-management-exec.json` | Optional; wins over shared configs |
| Example JSON | [hw-management-exec-example.json](hw-management-exec-example.json) | Full schema example (I2C + sysfs) |
| GB200 platforms | [hw-management-exec-gb200.json](../usr/etc/hw-management-exec/hw-management-exec-gb200.json) | Shipped for HI162, HI166, HI167, HI169, HI170 |

## Lifecycle

- **`hw-management start`** — at the end of **`do_start()`**, runs **`hw-management-exec-parser.sh`** after **`/var/run/hw-management`** exists.
- **`hw-management stop`** — at the start of **`do_stop()`**, removes **`/var/run/hw-management/exec.d/`** (and any legacy **`/var/run/hw-management/exec`** copy); the full **`/var/run/hw-management`** tree is removed afterward.

If no config matches the system HID, the parser exits silently (no error).

## Runtime layout (BusyBox-style)

After **`hw-management start`**:

```text
/usr/bin/hw-management-exec                 # dispatcher (installed by package)
/var/run/hw-management/exec.d/
    hotplug_irq_mask_set -> /usr/bin/hw-management-exec
    hotplug_irq_mask_set.env                # variables + action (sourced by dispatcher)
    hotplug_irq_mask_clear -> /usr/bin/hw-management-exec
    hotplug_irq_mask_clear.env
```

Invoking a symlink runs **`hw-management-exec`**; the attribute name is taken from **`basename "$0"`** (like **`cp`** → **`busybox`**). Symlinks must not point at a binary under **`/var/run`**: many systems mount **`/run`** or **`/var`** with **`noexec`**, which yields **Permission denied** even for root.

After upgrading, re-run **`hw-management restart`** (or **`hw-management-exec-parser.sh`**) so symlinks are recreated.

## Config resolution (first match wins)

1. **`/etc/<HID>/hw-management-exec.json`** (or **`/usr/etc/<HID>/...`**)
2. Any **`/etc/hw-management-exec/*.json`** (or **`/usr/etc/hw-management-exec/*.json`**) whose **`"hids"`** array contains the current HID

HID is taken from, in order: environment variable **`HID`**, **`/var/run/hw-management/config/hid`**, then DMI **`product_sku`**.

## JSON schema

Top-level object:

| Field | Required | Description |
|-------|----------|-------------|
| `hids` | For shared files | List of SKUs (e.g. `"HI162"`) that use this file |
| `bus` | No | Default I2C bus for attributes that define I2C fields but omit `bus` |
| `attributes` | Yes | Array of attribute objects |

Each **attribute** object:

| Field | Required | Description |
|-------|----------|-------------|
| `AttributeName` | Yes | Symlink name under `exec.d/` (also `attribute_name`) |
| `action` | Yes | Shell snippet executed when the helper is run (may use variables below) |
| `description` | No | Comment in the `.env` fragment |
| `bus` | No | I2C bus number |
| `address` | No | I2C address (hex, e.g. `0x16`) |
| `offset` | No | Register offset (hex) |
| `size` | No | Register size in bytes |
| `mask` | No | Bit(s) to change (hex); **set** forces them to 1, **clear** forces them to 0 |
| `retry` | No | Max attempts for I2C write + readback verify (`retry=N` in `.env`) |

**Only `AttributeName` and `action` are required.** Omit all I2C fields for pure shell/sysfs/CPLD actions.

### I2C attributes

When any of `address`, `offset`, or `mask` is set, the parser may apply the top-level default **`bus`** if the attribute does not define **`bus`**. It writes optional variables into the **`.env`** fragment before **`action`**:

```sh
bus=12
address=0x16
offset=0xd7
mask=0x20
```

The **`action`** field should reference those variables (see the example file). For GB200 hotplug IRQ, **`mask`** is **`0x20`** (one interrupt bit), not a register-wide value like **`0xdf`**.

### I2C write with readback and retry

Set **`retry`** (e.g. `5`) and use a loop in **`action`** that:

1. Reads the register (`i2cget`)
2. Computes the new value and writes it (`i2cset`)
3. Reads back (`i2cget`) and compares masked bits
4. Exits `0` on match, otherwise increments **`attempt`** until **`retry`** is reached, then exits `1`

GB200 hotplug IRQ helpers use masked compare: **set** checks `(rb & mask) == (new & mask)`; **clear** checks `(rb & mask) == 0`. See [hw-management-exec-gb200.json](../usr/etc/hw-management-exec/hw-management-exec-gb200.json).

### Non-I2C attributes (CPLD, sysfs, GPIO)

Define only **`AttributeName`**, **`action`**, and optionally **`description`**. No `bus`/`address`/`offset`/`mask` lines are emitted.

Example:

```json
{
    "AttributeName": "aux_pwr_cycle",
    "action": "echo 1 > /var/run/hw-management/system/aux_pwr_cycle",
    "description": "Trigger auxiliary power cycle via hw-management sysfs"
}
```

## Usage

After **`hw-management start`**:

```sh
/var/run/hw-management/exec.d/hotplug_irq_mask_set
/var/run/hw-management/exec.d/aux_pwr_cycle
```

Symlinks and `.env` fragments are recreated on each start; do not edit them by hand.

## Adding a new platform

**Same behavior as an existing group (e.g. GB200):** add the HID to the **`"hids"`** array in the appropriate file under **`usr/etc/hw-management-exec/`**.

**Different behavior:**

- Add **`usr/etc/hw-management-exec/hw-management-exec-<name>.json`** with its own **`hids`** list, or
- Ship **`/etc/<HID>/hw-management-exec.json`** for a single-SKU override.

Rebuild/install the **`hw-management`** package; **`debian/rules`** installs **`etc/hw-management-exec/`** from **`usr/etc/hw-management-exec/`**.

## Safety and portability

- **`address`**, **`offset`**, and **`mask`** are sanitized to hex digits (and `x`) before being written into `.env` fragments.
- **`bus`** and **`size`** must be numeric.
- **`AttributeName`** is restricted to alphanumeric characters, `_`, and `-`.
- **`description`** is stripped to safe comment characters.
- Parser and library use **`#!/bin/sh`** and **`jq`**; load the JSON library with **`. /usr/bin/hw-management-json-parser.sh`**.
- Simple string fields use **`json_get_string`**; **`action`** and **`description`** use **`json_get_escaped_string`** (supports `\"` and common escapes).

## See also

- [hw-management-exec-example.json](hw-management-exec-example.json) — copy/paste starting point
- [hw-management.sh](../usr/usr/bin/hw-management.sh) — **`do_start()`** / **`do_stop()`** integration
