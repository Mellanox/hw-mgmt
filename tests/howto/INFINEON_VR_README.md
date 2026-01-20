# Infineon XDPE1x2xx VR management (hw-management)

This document describes the **in-tree** script shipped with hw-management:

- **Path (source):** `usr/usr/bin/hw-management-vr-dpc-infineon-update.sh`
- **Typical install:** `/usr/bin/hw-management-vr-dpc-infineon-update.sh`

It implements flash and diagnostics for Infineon XDPE1x2xx devices over I2C/PMBus,
based on **AN001-XDPE1x2xx_programming Guide 2** (section references live in source
comments, not in every log line).

## Overview

- Flash **`.bin`**, **`.txt`**, or **`.mic`** configuration data to OTP (with
  section-by-section flow for `.txt`/`.mic`).
- **Driver unbind/rebind** around raw I2C access when a kernel driver (e.g.
  `xdpe1a2g7b`) holds the address.
- **Parse**, **readback**, **compare**, **scan**, **info**, **monitor**, **dump**,
  and helper modes (`unbind`, `rebind`, `scpad-addr`).

## Prerequisites

- **Packages:** `i2c-tools` (provides `i2cdetect`, `i2cget`, `i2cset`,
  `i2ctransfer`) and common userspace utilities: `cmp`, `hexdump`, `awk`, `tail`,
  `dd`, `head`, `tr` (BusyBox or util-linux builds are fine).
- **Optional:** `crc32` (or compatible) for expected-CRC handling on Partial PMBus
  (HC `0x0B`) when flashing from `.txt`/`.mic`; `md5sum` / `sha256sum` for
  `compare` extras.
- **Kernel:** `i2c-dev` / adapter usable from userspace; **block** I2C read/write
  needed for OTP **readback** on some paths.

## Help

```bash
hw-management-vr-dpc-infineon-update.sh -h
# same as:  ... --help   or   ... help
```

With **no** arguments, **`main()`** is not run and **`usage()`** is not called — only
**`Use: <scriptname> -h to get help`** on stderr, then **`exit 0`** (subprocess) or **`return 0`**
(**`source`**). Full help is **`-h`**, **`--help`**, or **`help`**. When **sourced**, **`usage`**
**`return`s** instead of **`exit`** for those help paths. Prefer **`./…`** or **`bash …`** for
device work; failure paths may still **`exit`** if **sourced**.

## Modes (first argument)

| Mode | Purpose |
|------|---------|
| `flash` | Program device from `-f` config |
| `verify` | Detect device and read MFR ID (no full STORE_CONFIG verify) |
| `scan` | Scan bus for Infineon-range addresses |
| `info` | Read device / telemetry-style info |
| `monitor` | Poll telemetry (`-i` interval) |
| `dump` | Dump registers (optional `-o` file) |
| `unbind` / `rebind` | Sysfs unbind driver for raw I2C; `rebind` restores last unbind |
| `scpad-addr` | Read scratchpad address (CMD `0x2e`) |
| `parse` | `.txt`/`.mic` → `.bin` and/or dump section layout; `.bin` → section list |
| `readback` | Read OTP sections to files; optional `-f` `.txt` to compare |
| `readback-all` | Dump full 32 KiB OTP |
| `compare` | Compare two config files (`-f` / `-c`) |

## Flash mode

```bash
hw-management-vr-dpc-infineon-update.sh flash -b <bus> -a <addr> -f <file> [options]
```

**Required:** `-b`, `-a`, `-f`

**Common options:**

- **`-n`** — Dry run: scratchpad write/readback only; no OTP upload, no finalize.
- **`-y`** — Do not prompt before OTP-changing steps (for automation / batch).
- **`-s <hc>`** — Only flash section(s) with that header code (e.g. `-s 0x0B`).
- **`-P0` / `-P1`** — SMBus PEC off/on for `i2ctransfer` helpers (default on).
- **`-v` / `-vv`** — Verbose / debug.

**Behavior notes (summary):**

- **Full `.txt`/`.mic`:** Sections not present in the file (from a fixed HC list)
  may be invalidated; each section that is **uploaded** is **invalidated
  immediately before** scratchpad programming for that slot. Sections whose OTP
  CRC already matches the parsed expected value may be **skipped** (no upload).
- **`.bin`:** Single scratchpad programming + upload path (no per-section
  `.txt`parse).
- After programming, **reset** or **post-flash ID read** failures are treated as
  **non-fatal** for exit status where documented in source (batch JSON must not
  stop on transient I2C after reset); **write protect** failure remains fatal.

**Examples:**

```bash
hw-management-vr-dpc-infineon-update.sh flash -b 29 -a 0x68 -f config.txt -n
hw-management-vr-dpc-infineon-update.sh flash -y -b 29 -a 0x68 -f config.txt
hw-management-vr-dpc-infineon-update.sh flash -b 29 -a 0x68 -f config.txt -s 0x0B
```

## Other modes (minimal)

```bash
hw-management-vr-dpc-infineon-update.sh scan -b 29
hw-management-vr-dpc-infineon-update.sh info -b 29 -a 0x68
hw-management-vr-dpc-infineon-update.sh verify -b 29 -a 0x68
hw-management-vr-dpc-infineon-update.sh parse -f config.bin
hw-management-vr-dpc-infineon-update.sh parse -f config.txt -o out.bin
hw-management-vr-dpc-infineon-update.sh readback-all -b 29 -a 0x68 -o ./otp_dump
```

**Readback with `-f` `.txt` / `.mic`:** Parsed per-section binaries and
`section_list` are written under **`<config_basename>_flash_work/`** (same
layout as **flash**). After a **successful** run that directory is **left in
place** on purpose so you can inspect or diff intermediates; remove it yourself
when you no longer need it (repeated runs reuse/overwrite the same tree but may
leave stale files if the config changes). Device captures go to **`-o`**
(default current directory) as `read_*_hc_*.bin`.

## Safety

- OTP programming is **irreversible**; use **`-n`** first when experimenting.
- Prefer **known-good** configs from Infineon GUI / DPC exports.
- If the kernel driver is bound, the script **unbinds** for the operation and
  attempts **rebind** on exit (see logs if rebind fails).

## References

- Infineon **AN001-XDPE1x2xx_programming Guide 2** (vendor collateral).
- PMBus specification — [pmbus.org](https://pmbus.org).

## License

SPDX header in the script matches other hw-management tools (NVIDIA CORPORATION &
AFFILIATES; BSD-3-Clause / GPL-2.0 alternative).

## Changelog (this README)

- **2026-04:** Rewritten for `hw-management-vr-dpc-infineon-update.sh` (replaces
  obsolete `flash-infineon-xdpe.sh` / `infineon-vr-tools.sh` examples).
