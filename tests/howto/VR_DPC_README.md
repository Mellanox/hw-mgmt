# Voltage regulator DPC tooling (hw-management)

Overview of in-tree VR / DPC update and readback scripts shipped with
hw-management. Detailed JSON batch and Infineon topics live in sibling
READMEs (linked below).

**Branch note (V.7.0040.4500_BR / Juliet):** Userland tools below support
**MPS** (`mp*`) and **Infineon** (`xdpe*`) power-converter DPC on GB200/GB300
Juliet (HI176/HI177). Kernel `xdpe1a2g7b` support is in the `0106`-named
6.1/nvos patches on that branch.

## Scripts (installed under `/usr/bin/`)

| Script | Role |
|--------|------|
| `hw-management-dpc-update.sh` | Apply a **DPC package** (`*.tar.gz` with JSON + configs); default skips when model/revision already match |
| `hw-management-vr-dpc-update-all.sh` | Batch update from a **JSON file** (MPS + Infineon, vendor auto-detect) |
| `hw-management-vr-dpc-update.sh` | Flash one **MPS** device (`i2c_bus`, `device_type`, `hid`, CSV/CRC/conf) |
| `hw-management-vr-dpc-infineon-update.sh` | Flash/diagnose one **Infineon** device (`.txt`/`.mic`/`.bin`) |
| `hw-management-vr-dpc-bulk-update.sh` | Legacy: scan **devtree** + `/var/run/hw-management/firmware/<hid>/` |
| `hw-management-vr-dpc-update-activator.sh` | Service hook: reads HID from helpers, runs bulk-update |
| `hw-management-read-vr-model-version.sh` | Read model/revision (`--show`, `--show --json`) |

## Typical flows

### DPC package (tar.gz) — preferred for mixed MPS + Infineon packages

```bash
# Verify package layout, scripts, I2C, and target vs current versions (no flash)
hw-management-dpc-update.sh --verify /path/to/dpc_pkg.tar.gz

# Update only if package targets differ (default); skip when already current
hw-management-dpc-update.sh /path/to/dpc_pkg.tar.gz

# Force flash even when skip-identical would skip
hw-management-dpc-update.sh --force /path/to/dpc_pkg.tar.gz

# Current VR versions on the system
hw-management-dpc-update.sh --show
hw-management-dpc-update.sh --show --json
```

Package JSON uses the same device fields as
`hw-management-vr-dpc-update-all.sh` (MPS: `CrcFile` + `DeviceConfigFile`;
Infineon: `Addr`, no MPS-only fields). Infineon entries are flashed via
`hw-management-vr-dpc-infineon-update.sh flash -y`.

**Skip-identical / verify targets:** MPS expected model/revision come from CSV +
device `.conf`. Infineon expected values are taken from the GUI export
`[User Data]` lines `Loop A USER_DATA_01` (model) and `Loop A USER_DATA_00`
(revision) in each `.txt`/`.mic`, with `Addr` from JSON (or `PMBus Address` in
the file header).

### JSON batch (explicit config path)

```bash
hw-management-vr-dpc-update-all.sh --validate-json /etc/vr_dpc.json
hw-management-vr-dpc-update-all.sh /etc/vr_dpc.json
```

See [VR_DPC_UPDATE_ALL_README.md](VR_DPC_UPDATE_ALL_README.md).

### Legacy HID bulk (firmware directory layout)

```bash
hw-management-vr-dpc-update-activator.sh          # service integration
hw-management-vr-dpc-bulk-update.sh hid176          # direct
```

Activator **sources** `hw-management-helpers.sh` (defines `log_info`). Bulk-update
runs as its **own process** and defines a `log_info` fallback via `logger` if
helpers were not sourced.

Devtree matches are returned as `device<TAB>bus` lines (one device per line).

### Single-device (debug)

```bash
hw-management-vr-dpc-update.sh <bus> <type> <hid> [csv] [crc] [conf]
hw-management-vr-dpc-infineon-update.sh flash -y -b <bus> -a <addr> -f <file>
```

## `hw-management-read-vr-model-version.sh`

- Table: `hw-management-read-vr-model-version.sh --show`
- JSON (one array element per devtree VR): `--show --json`
- **xdpe1a2g7b:** reads PMBUS MFR model/revision (`0x9a` / `0x9b`, page 0,
  SMBus block byte offset 1) via `i2ctransfer` — not plain `i2cget word`.
- JSON `bus` is the **absolute** I2C bus (devtree bus + `i2c_bus_offset` when
  configured). Match DPC JSON / verify output using `bus`, `device_name`, and
  `address`.

I2C page changes use direct `i2cset` argv (no `eval`).

## Environment / debug

| Variable | Used by | Purpose |
|----------|---------|---------|
| `DPC_DEBUG=1` | `hw-management-dpc-update.sh` | Debug on stderr only |
| `DPC_TOOLS_PATHS` | `hw-management-dpc-update.sh` | Extra directories to find updater scripts |
| `DPC_DEVTREE_PATH` | `hw-management-dpc-update.sh` | Devtree for I2C verify |
| `DEVTREE_FILE` | `read-vr-model-version.sh` | Override devtree path |

## Dependencies

- **Common:** `bash`, `i2c-tools` (`i2cget`, `i2cset`, `i2ctransfer` for xdpe)
- **JSON paths:** `jq`
- **DPC package path:** `tar`
- **Infineon partial CRC (optional):** `crc32` in `PATH` for HC `0x0B` expected
  CRC when flashing from `.txt`/`.mic`

`hw-management-vr-dpc-update-all.sh` and `hw-management-dpc-update.sh` require
the Infineon updater only when the JSON lists `xdpe*` devices; MPS-only JSON does
not require `hw-management-vr-dpc-infineon-update.sh` at validate time.

## See also

- [VR_DPC_UPDATE_ALL_README.md](VR_DPC_UPDATE_ALL_README.md) — JSON batch format
- [INFINEON_VR_README.md](INFINEON_VR_README.md) — Infineon flash/diagnostic modes
- `examples/vr_dpc_update_nn5500ld.json` — mixed MPS + xdpe1a2g7b (Juliet)

## Changelog (this README)

- **2026-06:** Initial overview for V.7.0040.4500_BR VR port (package entrypoint,
  skip-identical Infineon targets, tool chain, read-vr JSON bus).
