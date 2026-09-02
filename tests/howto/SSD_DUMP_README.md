# SSD dump collection (hw-management)

Unified NVMe nandlog collector. Vendor binaries are **not** in hw-mgmt;
NOS puts them on `PATH`.

## Pieces

| Path | Role |
|------|------|
| `/usr/bin/hw-management-ssd-dump.py` | Collector CLI (`#!/usr/bin/env python3`; Debian `Depends: python3`) |
| `/etc/hw-management-ssd/ssd-dump-config.json` | Vendor / model / tool |
| `/var/log/ssd-dump/` | Work dir (CLI removes only on `status: ok`; helper also removes after a successful fallback tar) |
| `/var/log/ssd-dump.tar.gz` | Packed dump (kept when inner tar succeeds) |
| `/usr/bin/hw-management-ssd-dump-collect.sh` | generate-dump helper (via `dump_cmd`) |
| `hw-management-generate-dump.sh` | `dump_cmd` the helper; helper copies `$SSD_TAR` and leftover `$SSD_LOG_DIR` if either exists |

There is no separate `dump.sh`. `dump.sh` in older notes means
`hw-management-generate-dump.sh`.

## How to invoke

FAE / standalone (nandlog into `/var/log/ssd-dump.tar.gz`):

```bash
sudo hw-management-ssd-dump.py
sudo hw-management-ssd-dump.py --device /dev/nvme0
sudo hw-management-ssd-dump.py --help
```

Full hw-mgmt dump (includes the SSD tarball):

```bash
sudo hw-management-generate-dump.sh
```

generate-dump helper (not for FAE; called via `dump_cmd`):

```bash
hw-management-ssd-dump-collect.sh <DUMP_FOLDER> <SSD_LOG_DIR> <SSD_TAR>
# example:
hw-management-ssd-dump-collect.sh /tmp/hw-mgmt-dump \
  /var/log/ssd-dump /var/log/ssd-dump.tar.gz
```

Only those three paths are accepted (`rm` is refused otherwise).
Refuse them if they are symlinks. `$DUMP_FOLDER` must be a real
directory owned by the current uid, mode `0700`.

## FAE / standalone

```bash
sudo hw-management-ssd-dump.py
sudo hw-management-ssd-dump.py --device /dev/nvme0
```

Default `--outdir` is **`/var/log/ssd-dump`**. Each run **recreates**
that directory. If `status: ok`, the tool packs it to
**`/var/log/ssd-dump.tar.gz`** and **deletes** the directory.
`--device` may be `/dev/nvme0` or `/dev/nvme0n1`. Virtium
`device_form` is `controller`, so `nvme0n1` is mapped to
`/dev/nvme0`.

Vendor stdout goes only to `ssd-dump-tool.log` (in the work dir;
in the tarball after a successful pack).
Warnings also go to **syslog `LOG_WARNING`** (ident
`hw-management-ssd-dump`): unsupported model, missing tool, tool
present but not executable (`chmod +x`).
`--quiet` still hides stderr; syslog remains. No NVMe is ignored
(no syslog).

## NOS image contract

NOS must put the JSON `tool` name on `PATH` as-is
(`vtFA_RTK_5766_v2`). If the tool is missing, the hw-mgmt dump is
still created; `ssd-dump-status.log` has a warning.

One NVMe: first controller whose sysfs model is in JSON. Model/fw
from sysfs (`/sys/class/nvme/...`). Not the `nvme` CLI.

## Virtium

- JSON model key: **`VTPM24CEXI080-BM110006`** (last token of Identify,
  keep `-…`; `Virtium VTPM24CEXI080-BM110006` → `VTPM24CEXI080-BM110006`)
- Tool: `vtFA_RTK_5766_v2 /dev/nvme0`
- Created files in the work dir are gzipped (no `output_globs`)
- Timeout: 90 s (default 120 s)
- gzip level 5 of created files; original removed after a successful
  `.gz`. If gzip fails, the original is kept.
- `ssd-dump-tool.log` and `ssd-dump-status.log` are never gzipped.

## Artifacts

Work dir:

- Python CLI: packed and removed only when **`status: ok`**.
  Warning/skip leave the dir and do **not** replace the last good
  `.tar.gz`.
- generate-dump helper: if Python did not pack, fallback-tars leftover
  `$SSD_LOG_DIR` into `$SSD_TAR`. If that tar succeeds, the helper
  **removes** the work dir (including on warning). If tar fails, the
  dir is copied into the hw-mgmt dump as **`ssd-dump/`**.

- `ssd-dump-status.log` — status, model, `part`, tool, rc, files,
  warning, `config` path
- `ssd-dump-tool.log` — vendor stdout/stderr
- created dump files (`nandlog_*.bin.gz`, or uncompressed if gzip
  off / gzip failed)

Kept on disk after a successful CLI collect: **`ssd-dump.tar.gz`**.

generate-dump: collect helper `rm`s the previous tar, then Python
runs. Helper copies `$SSD_TAR` if present. If both the tarball and
the leftover dir exist (`rm` after tar failed), both are copied.

DUMP_FOLDER (`/tmp/hw-mgmt-dump`) must be a real directory owned by
the current uid, mode `0700` (not a symlink).

CLI and generate-dump share `/var/log/ssd-dump`. A lock file
(`/run/hw-management-ssd-dump.lock`, else `/var/lock/…`) serializes
runs. The helper takes it non-blocking (skip SSD dump if FAE is
already collecting). Standalone Python waits up to 200 s.

## Adding a vendor later

Add a `vendors.<Name>.models.<Key>` object (`Key` is the last Identify
token, including `-…`):
`tool`, `args` (`{device}`, `{outdir}`, `{model}`), `device_form`
(`controller` or `namespace`), optional `timeout_sec`. Do not ship the
vendor binary in hw-mgmt. RPM: `%config(noreplace)` so a local JSON
edit is kept on upgrade (new file as `.rpmnew`). Debian: `/etc` is a
conffile (local kept; new as `.dpkg-dist`).
