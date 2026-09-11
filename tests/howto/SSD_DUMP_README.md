# SSD dump collection (hw-management)

Unified NVMe nandlog collector. Vendor binaries are **not** in hw-mgmt;
NOS puts them on `PATH`.

Dump-tools (NOS 1.0 ELFs + SMI `smi/`, `tools/README.txt`):
`ssh://git@gitlab-master.nvidia.com:12051/nbu-sws/bsp/bsp_ssd_fw_update.git`

This package: https://github.com/Mellanox/hw-mgmt.git
(`tests/howto/SSD_DUMP_README.md` from the repo root;
`./howto/SSD_DUMP_README.md` if cwd is `tests/`).

## Pieces

| Path | Role |
|------|------|
| `/usr/bin/hw-management-ssd-dump.py` | Collector CLI (`#!/usr/bin/env python3`; Debian `Depends: python3`) |
| `/etc/hw-management-tools/ssd-dump-config.json` | Vendor / model / tool |
| `/var/log/ssd-dump/` | Work dir (CLI pack removes it on `status: ok`; generate-dump copies then removes it) |
| `/var/log/ssd-dump.tar.gz` | Packed dump (standalone CLI only; replaced on `status: ok`) |
| `/usr/bin/hw-management-ssd-dump-collect.sh` | generate-dump helper (via `dump_cmd`) |
| `hw-management-generate-dump.sh` | `dump_cmd` the helper; helper copies leftover `$SSD_LOG_DIR` as `ssd-dump/` |

There is no separate `dump.sh`. `dump.sh` in older notes means
`hw-management-generate-dump.sh`.

## Restrictions

- **One caller at a time.** Do not run the CLI, `--verify`, and
  generate-dump together, and do not overlap two collects. There is
  **no lock**; overlapping runs can clobber `/var/log/ssd-dump`.
- **Real paths only.** `--outdir`, `--device`, `$DUMP_FOLDER`,
  `$SSD_LOG_DIR` must be real directories or device
  nodes. Symlinks (any path component) are refused.

## How to invoke

FAE / standalone (nandlog into `/var/log/ssd-dump.tar.gz`):

```bash
sudo hw-management-ssd-dump.py
sudo hw-management-ssd-dump.py --device /dev/nvme0
sudo hw-management-ssd-dump.py --verify
sudo hw-management-ssd-dump.py --help
```

Full hw-mgmt dump (includes `ssd-dump/` in the outer tar):

```bash
sudo hw-management-generate-dump.sh
```

generate-dump helper (not for FAE; called via `dump_cmd`):

```bash
hw-management-ssd-dump-collect.sh <DUMP_FOLDER> <SSD_LOG_DIR>
# example:
hw-management-ssd-dump-collect.sh /tmp/hw-mgmt-dump /var/log/ssd-dump
```

Only those two paths are accepted (`rm` is refused otherwise).
Refuse SSD_LOG_DIR if it is a symlink. `$DUMP_FOLDER`
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
that directory. The parent of `--outdir` must be writable
(rmtree + mkdir). On a sticky parent (`/tmp`), an existing
`--outdir` must be owned by this uid (non-root cannot rmtree
a foreign dir). If `status: ok` and **not** `--no-tar`, the tool
packs it to **`/var/log/ssd-dump.tar.gz`** and **deletes** the
directory. generate-dump passes `--no-tar`, copies the dir into
the hw-mgmt tar, then **removes** `/var/log/ssd-dump`.
`--device` must be a char or block node under `/dev` (`/dev/nvme0`
or `/dev/nvme0n1`), not a symlink or a regular file. A path
outside `/dev` or a missing node is a warning. Virtium
`device_form` is `controller` (`nvme0n1` → `/dev/nvme0`). Phison
is `namespace` (`nvme0` → lowest `/dev/nvmeXnN`, usually `n1`).
Silicon Motion is also `namespace`. The mapped namespace node
must exist (char or block, not a symlink) or the collect is
**warning**.

`--verify` checks JSON, NVMe/sysfs model, vendor tool on PATH
(+x), free space, `--outdir` rules, and optional `stage_from`
without running the vendor tool or writing dump files. It does
write `ssd-dump-status.log` only for the default `--outdir`
(`/var/log/ssd-dump`; mkdir if needed; no rmtree). A custom
`--outdir` is checked only; status stays on stdout so a later
collect is not blocked. stdout omits `warning:` and the last
`Status:` line (reason is on stderr). rc 0 = ok or skipped,
1 = warning.

`ssd-dump-tool.log` is the collector + vendor run log (cmd lines
and vendor stdout/stderr). It is omitted when the vendor binary
never ran (missing config/tool, skip, unsupported model). Vendor
output is not copied to the console. Collector warnings also go
to **syslog `LOG_WARNING`**
(ident `hw-management-ssd-dump`): unsupported model, missing tool,
tool present but not executable (`chmod +x`).
Console always has **`SSD dump tool started`** then, on
**`status: ok`**, **`SSD dump tool results:`** (`…/ssd-dump.tar.gz`
or `…/ssd-dump/` with `--no-tar`) then
**`SSD dump tool succeeded`**, **`SSD dump tool skipped`**, or
**`SSD dump tool failed: …`**
(even `--quiet`; generate-dump captures them). With
**`--quiet --no-tar`**, Python omits results/succeeded;
the generate-dump helper prints them after it copies
`ssd-dump/`. Copy failure prints **`SSD dump tool failed:`**.
WARNING stays in
the log file and syslog, not duplicated on stderr.
`--verify` prints status fields on stdout. `--verify --quiet`
hides those fields (rc still 0/1). Syslog remains. No NVMe
is ignored (no syslog).

## NOS image contract

NOS must put a JSON `tool` or `tool_alt` name on `PATH`.
Preferred NOS names: `virtium_nvme_dump_v2`, `phison_nvme_dump_v2`,
`smi_nvme_dump_v1`. If those are missing, the collector tries
vendor originals (`vtFA_RTK_5766_v2`,
`PCIETOOL08-6130_RD_Dump2_(Nvidia)_Linux_64bit_v2`,
`NVMe_Tool_SM2268XT2_Ferri_64_Z0717A`). Dump-tools 1.0
(`bsp_ssd_dump_tools_1.0`) is Virtium, Phison, and Silicon
Motion. SMI `smi/` tree goes to
`/usr/share/hw-management-tools/smi`. If neither name is on PATH,
the hw-mgmt dump is still created; `ssd-dump-status.log` has a
warning. Later NOS may install `virtium_nvme_dump_v2` (etc.) as
a symlink to the vendor basename; `tool` then matches and
`tool_alt` is unused.

One NVMe: first controller whose sysfs model is in JSON. Model/fw
from sysfs (`/sys/class/nvme/...`). Not the `nvme` CLI.

## Virtium

- JSON model key: **`VTPM24CEXI080-BM110006`** (last token of Identify,
  keep `-…`; `Virtium VTPM24CEXI080-BM110006` → `VTPM24CEXI080-BM110006`)
- Tool: `virtium_nvme_dump_v2 /dev/nvme0`
- Created files stay as the vendor wrote them (no per-file gzip)
- Timeout: 90 s (default 120 s)

## Phison

- JSON model key: **`ESLS080GTUE-A329IJ1-TYJN`**
- Tool: `phison_nvme_dump_v2 -device_index /dev/nvme0n1`
  (`/dev/nvme0` is invalid for this tool)
- Created files: `RD_Dump2_Header_*.bin`, `RD_Dump2_Data_*.bin`
- Timeout: 120 s (sample ~57 s on Juliet-128)

## Silicon Motion

- JSON model key: **`MD681GEEBC82`**
- Tool: `smi_nvme_dump_v1 /dev/nvme0n1 one_button`
  (vendor original `NVMe_Tool_SM2268XT2_Ferri_64_Z0717A`;
  dump-tools ships `smi_nvme_dump_v1.gz`)
- `stage_from`: `/usr/share/hw-management-tools/smi` (copy `Setting/`
  and `one_button_NV.cfg` → cwd `one_button.cfg`; not packed)
- Pack only `one_button/` (vendor files as written). Drop `TestResult/`,
  `Display_*.log`, and staged cfg. generate-dump uses the NV cfg
  only, not `one_button_full.cfg`.
- Timeout: 120 s

## Artifacts

Work dir:

- Python CLI: packed and removed only when **`status: ok`** and
  not `--no-tar`. Warning/skip leave the dir and do **not**
  replace the last good `.tar.gz`.
- generate-dump helper: runs Python `--quiet --no-tar`. Copies
  leftover `$SSD_LOG_DIR` as **`ssd-dump/`**, then removes
  `/var/log/ssd-dump`. Does **not** put `ssd-dump.tar.gz` inside
  the hw-mgmt tar. Python does not print succeeded until the
  helper copies; after a good copy the helper writes results
  and succeeded to stderr. If the copy fails (full filesystem),
  stderr (ssd-dump-collect.log) gets **`SSD dump tool failed:`**,
  status is rewritten to warning, `$SSD_LOG_DIR` is kept, and a
  stub `ssd-dump/` with the status file is left in DUMP_FOLDER.
  Helper still exits 0 so the rest of generate-dump is packed.

- `ssd-dump-status.log` — status, model, `part`, tool, `tool_rc`,
  files (first 3 names, comma-space; then `(N in total, 12M)`
  for all dump files: count and ceil K or M), `config`
  path; `warning:` only on errors; last line
  `Status: Ok / succeeded`, `Status: skipped`, or `Status: error`
- `ssd-dump-tool.log` — vendor stdout/stderr plus collector cmd
  lines when the vendor binary ran (written as `.txt` during
  the run, renamed to `.log` before pack). Omitted if the
  vendor tool never started.
- created dump files (`nandlog_*.bin`, `RD_Dump2_*.bin`,
  `one_button/...`)

Kept on disk after a successful CLI collect (no `--no-tar`):
**`ssd-dump.tar.gz`**. generate-dump does **not** leave
**`/var/log/ssd-dump/`** after a successful copy.

generate-dump: Python `--no-tar`. Helper copies leftover
**`ssd-dump/`**, then removes `$SSD_LOG_DIR`.

DUMP_FOLDER (`/tmp/hw-mgmt-dump`) must be a real directory owned
by the current uid (not a symlink). Root recreates a planted
path so collection cannot be blocked. generate-dump mkdir is
`0755`.

CLI and generate-dump share `/var/log/ssd-dump`. **Do not run them
in parallel** (no lock). Vendor timeout 90 s (Virtium) or 120 s
(Phison / defaults). JSON `timeout_sec` must be 1..120
(generate-dump wrapper is 195 s). Standalone `--timeout` may
be higher.

## Adding a vendor later

Add a `vendors.<Name>.models.<Key>` object (`Key` is the last Identify
token, including `-…`):
`tool`, optional `tool_alt` (old vendor basename on PATH), `args` (`{device}`, `{outdir}`, `{model}`), `device_form`
(`controller` or `namespace`), optional `timeout_sec`.
Optional absolute `stage_from`, `stage_cfg` (cwd
name `one_button.cfg`),
`keep_dirs` (default `["one_button"]` when staging). Do not ship
the vendor binary or `smi/` tree in hw-mgmt. RPM:
`%config(noreplace)` so a local JSON edit is kept on upgrade
(new file as `.rpmnew`). Debian: `/etc` is a conffile (local
kept; new as `.dpkg-dist`).

HLD / operator CLI are ECR notes (`SSD-dump-collector-HLD.md`,
`SSD-dump-collector-CLI.md`), not this package.
