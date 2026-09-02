# SSD dump collection (hw-management)

Unified NVMe nandlog collector. Vendor binaries are **not** in hw-mgmt;
NOS puts them on `PATH`.

## Pieces

| Path | Role |
|------|------|
| `/usr/bin/hw-management-ssd-dump.py` | Collector CLI (`#!/usr/bin/env python3`; Debian `Depends: python3`) |
| `/etc/hw-management-ssd/ssd-dump-config.json` | Vendor / model / tool |
| `/var/log/ssd-dump/` | Work dir (removed only on `status: ok`; leftover copied into hw-mgmt dump) |
| `/var/log/ssd-dump.tar.gz` | Packed dump (Python replaces only on `status: ok`) |
| `/usr/bin/hw-management-ssd-dump-collect.sh` | generate-dump helper (via `dump_cmd`) |
| `hw-management-generate-dump.sh` | `dump_cmd` the helper; helper copies `$SSD_TAR` and leftover `$SSD_LOG_DIR` if either exists |

There is no separate `dump.sh`. `dump.sh` in older notes means
`hw-management-generate-dump.sh`.

## Restrictions

- **One caller at a time.** Do not run the CLI, `--verify`, and
  generate-dump together, and do not overlap two collects. There is
  **no lock**; overlapping runs can clobber `/var/log/ssd-dump`.
- **Real paths only.** `--outdir`, `--device`, `$DUMP_FOLDER`,
  `$SSD_LOG_DIR`, and `$SSD_TAR` must be real directories or device
  nodes. Symlinks (any path component) are refused.

## How to invoke

FAE / standalone (nandlog into `/var/log/ssd-dump.tar.gz`):

```bash
sudo hw-management-ssd-dump.py
sudo hw-management-ssd-dump.py --device /dev/nvme0
sudo hw-management-ssd-dump.py --verify
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
Refuse SSD_LOG_DIR / SSD_TAR if they are symlinks. `$DUMP_FOLDER`
must be a real directory owned by this uid. Root recreates it if
a local user planted `/tmp/hw-mgmt-dump` (unlink a symlink;
`rm -rf` only a real directory). Non-root still fails.
generate-dump mkdir is `0755`.

## FAE / standalone

```bash
sudo hw-management-ssd-dump.py
sudo hw-management-ssd-dump.py --device /dev/nvme0
```

Default `--outdir` is **`/var/log/ssd-dump`**. Each run **recreates**
that directory. If `status: ok`, the tool packs it to
**`/var/log/ssd-dump.tar.gz`** and **deletes** the directory.
`--device` must be a char or block node under `/dev` (`/dev/nvme0`
or `/dev/nvme0n1`), not a symlink or a regular file. A path
outside `/dev` or a missing node is a warning. Virtium
`device_form` is `controller`, so `nvme0n1` is mapped to
`/dev/nvme0` for the vendor tool.

`--verify` checks JSON, NVMe/sysfs model, vendor tool on PATH
(+x), free space, and `--outdir` rules (protected / symlink in any
component / non-empty custom / not writable) without creating or
deleting that directory. It does **not** run the vendor tool or
write dump files. Prints status fields to stdout (rc 0 = ok or
skipped, 1 = warning).

`ssd-dump-tool.log` is the collector run log: WARNING/skipped/cmd
lines, and vendor stdout/stderr when the tool runs (work dir;
tarball after a successful pack). Vendor output is not copied to
the console. Collector warnings also go to **syslog `LOG_WARNING`**
(ident `hw-management-ssd-dump`): unsupported model, missing tool,
tool present but not executable (`chmod +x`).
`--quiet` hides WARNING stderr. **Start** and **complete**
always go to stderr (so generate-dump's collect log has them).
With `--verify` it also hides the status fields on stdout
(rc still 0/1). Syslog remains. No NVMe is ignored (no syslog).

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
- generate-dump helper: does **not** delete `$SSD_TAR`. Python
  replaces it only on **`status: ok`**. Warning/skip leave the last
  good archive and leftover `$SSD_LOG_DIR`, copied as **`ssd-dump/`**.

- `ssd-dump-status.log` — status, model, `part`, tool, `tool_rc`,
  files, `config` path; `warning:` only on errors; last line
  `Status: Ok / succeeded` or `Status: error`
- `ssd-dump-tool.log` — collector WARNING/skipped/cmd lines, plus
  vendor stdout/stderr when the tool runs
- created dump files (`nandlog_*.bin.gz`, or uncompressed if gzip
  off / gzip failed)

Kept on disk after a successful CLI collect: **`ssd-dump.tar.gz`**.

generate-dump: Python runs. Helper copies `$SSD_TAR` if present
(last good or this ok run) and leftover **`ssd-dump/`** if the
work dir remains (warning/skip).

DUMP_FOLDER (`/tmp/hw-mgmt-dump`) must be a real directory owned
by the current uid (not a symlink). Root recreates a planted
path so collection cannot be blocked. generate-dump mkdir is
`0755`.

CLI and generate-dump share `/var/log/ssd-dump`. **Do not run them
in parallel** (no lock). Standalone Python timeout is 90 s (Virtium)
or 120 s default.

## Adding a vendor later

Add a `vendors.<Name>.models.<Key>` object (`Key` is the last Identify
token, including `-…`):
`tool`, `args` (`{device}`, `{outdir}`, `{model}`), `device_form`
(`controller` or `namespace`), optional `timeout_sec`. Do not ship the
vendor binary in hw-mgmt. RPM: `%config(noreplace)` so a local JSON
edit is kept on upgrade (new file as `.rpmnew`). Debian: `/etc` is a
conffile (local kept; new as `.dpkg-dist`).
