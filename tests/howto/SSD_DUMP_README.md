# SSD dump collection (hw-management)

Unified NVMe nandlog collector. Vendor binaries are **not** in hw-mgmt;
NOS puts them on `PATH`.

Dump-tools (ELFs and SMI `smi/` tree, `tools/README.txt`):
`ssh://git@gitlab-master.nvidia.com:12051/nbu-sws/bsp/bsp_ssd_fw_update.git`

This package: https://github.com/Mellanox/hw-mgmt.git
(`tests/howto/SSD_DUMP_README.md` from the repo root;
`./howto/SSD_DUMP_README.md` if cwd is `tests/`).

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
`device_form` is `controller` (`nvme0n1` → `/dev/nvme0`). Phison
is `namespace` (`nvme0` → lowest `/dev/nvmeXnN`, usually `n1`).
Silicon Motion is also `namespace`. The mapped namespace node
must exist (char or block, not a symlink) or the collect is
**warning**.

`--verify` checks JSON, NVMe/sysfs model, vendor tool on PATH
(+x), free space, `--outdir` rules (protected / symlink in any
component / non-empty custom / not writable), and optional
`stage_from` (`Setting/` + cfg, no copy) without creating or
deleting that directory. It does **not** run the vendor tool or
write dump files. Prints status fields to stdout (rc 0 = ok or
skipped, 1 = warning).

`ssd-dump-tool.log` is the collector run log: WARNING/skipped/cmd
lines, and vendor stdout/stderr when the tool runs (work dir;
tarball after a successful pack). Vendor output is not copied to
the console. Collector warnings also go to **syslog `LOG_WARNING`**
(ident `hw-management-ssd-dump`): unsupported model, missing tool,
tool present but not executable (`chmod +x`).
Console always has **`SSD dump tool started`** then
**`SSD dump tool succeeded`**, **`SSD dump tool skipped`**, or
**`SSD dump tool failed: …`**
(even `--quiet`; generate-dump captures them). WARNING stays in
the log file and syslog, not duplicated on stderr.
`--verify` prints status fields on stdout. `--verify --quiet`
hides those fields (rc still 0/1). Syslog remains. No NVMe
is ignored (no syslog).

## NOS image contract

NOS must put the JSON `tool` name on `PATH` as-is
(`vtFA_RTK_5766_v2`,
`PCIETOOL08-6130_RD_Dump2_(Nvidia)_Linux_64bit_v2`,
`NVMe_Tool_SM2268XT2_Ferri_64_Z0717A`). SMI also needs the
cwd tree at `/usr/share/hw-management-ssd/smi/` (`Setting/` and
`one_button_NV.cfg`). That tree is **not** in the hw-mgmt RPM.
If the tool or `stage_from` is missing, the hw-mgmt dump is
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

## Phison

- JSON model key: **`ESLS080GTUE-A329IJ1-TYJN`**
- Tool: `PCIETOOL08-6130_RD_Dump2_(Nvidia)_Linux_64bit_v2 -device_index /dev/nvme0n1`
  (`/dev/nvme0` is invalid for this tool)
- Created files: `RD_Dump2_Header_*.bin`, `RD_Dump2_Data_*.bin` (gzipped)
- Timeout: 120 s (sample ~57 s on Juliet-128)

## Silicon Motion

- JSON model key: **`MD681GEEBC82`**
- Tool: `NVMe_Tool_SM2268XT2_Ferri_64_Z0717A /dev/nvme0n1 one_button`
- `stage_from`: `/usr/share/hw-management-ssd/smi` (copy `Setting/`
  and `one_button_NV.cfg` → cwd `one_button.cfg`; not packed)
- Pack only `one_button/` (gzip nested files). Drop `TestResult/`,
  `Display_*.log`, and staged cfg. generate-dump uses the NV cfg
  only, not `one_button_full.cfg`.
- Timeout: 120 s

## Artifacts

Work dir:

- Python CLI: packed and removed only when **`status: ok`**.
  Warning/skip leave the dir and do **not** replace the last good
  `.tar.gz`.
- generate-dump helper: does **not** delete `$SSD_TAR`. Python
  replaces it only on **`status: ok`**. Warning/skip leave the last
  good archive and leftover `$SSD_LOG_DIR`, copied as **`ssd-dump/`**.

- `ssd-dump-status.log` — status, model, `part`, tool, `tool_rc`,
  files (first 3 names, plus `(N in total)` if more), `config`
  path; `warning:` only on errors; last line
  `Status: Ok / succeeded`, `Status: skipped`, or `Status: error`
- `ssd-dump-tool.log` — collector WARNING/skipped/cmd lines, plus
  vendor stdout/stderr when the tool runs (written as `.txt` during
  the run, renamed to `.log` before pack)
- created dump files (`nandlog_*.bin.gz`, `RD_Dump2_*.bin.gz`,
  `one_button/...`, or uncompressed if gzip off / gzip failed)

Kept on disk after a successful CLI collect: **`ssd-dump.tar.gz`**.

generate-dump: Python runs. Helper copies `$SSD_TAR` if present
(last good or this ok run) and leftover **`ssd-dump/`** if the
work dir remains (warning/skip).

DUMP_FOLDER (`/tmp/hw-mgmt-dump`) must be a real directory owned
by the current uid (not a symlink). Root recreates a planted
path so collection cannot be blocked. generate-dump mkdir is
`0755`.

CLI and generate-dump share `/var/log/ssd-dump`. **Do not run them
in parallel** (no lock). Vendor timeout 90 s (Virtium) or 120 s
(Phison / SMI / defaults). JSON `timeout_sec` must be 1..120
(generate-dump wrapper is 195 s). Standalone `--timeout` may
be higher.

## Adding a vendor later

Add a `vendors.<Name>.models.<Key>` object (`Key` is the last Identify
token, including `-…`):
`tool`, `args` (`{device}`, `{outdir}`, `{model}`), `device_form`
(`controller` or `namespace`), optional `timeout_sec`, optional
JSON boolean `gzip` (overrides `defaults.gzip`; CLI `--no-gzip`
still wins). Optional absolute `stage_from`, `stage_cfg` (cwd
name `one_button.cfg`),
`keep_dirs` (default `["one_button"]` when staging). Do not ship
the vendor binary or `smi/` tree in hw-mgmt. RPM:
`%config(noreplace)` so a local JSON edit is kept on upgrade
(new file as `.rpmnew`). Debian: `/etc` is a conffile (local
kept; new as `.dpkg-dist`).

HLD / operator CLI are ECR notes (`SSD-dump-collector-HLD.md`,
`SSD-dump-collector-CLI.md`), not this package.
