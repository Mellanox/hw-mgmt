# SSD dump collection (hw-management)

Unified NVMe nandlog collector. Vendor binaries and
`ssd-dump-config.json` are **not** in hw-mgmt; the dump-tools
`.deb` puts tools on `PATH` and JSON under
`/usr/share/ssd-dump-tools/`.

Dump-tools (NOS 1.0 ELFs + SMI `smi/`, `tools/README.txt`):
`ssh://git@gitlab-master.nvidia.com:12051/nbu-sws/bsp/bsp_ssd_fw_update.git`

This package: https://github.com/Mellanox/hw-mgmt.git
(`tests/howto/SSD_DUMP_README.md` from the repo root;
`./howto/SSD_DUMP_README.md` if cwd is `tests/`).

## Pieces

| Path | Role |
|------|------|
| `/usr/bin/hw-management-ssd-dump.py` | Collector CLI (`#!/usr/bin/env python3`) |
| `/usr/share/ssd-dump-tools/ssd-dump-config.json` | Vendor / model / tool (dump-tools `.deb`) |
| `/var/log/ssd-dump/` | Work dir (collect always rmtree's it first; CLI pack removes it on `status: ok`; generate-dump copies then removes it) |
| `/var/log/ssd-dump.tar.gz` | Packed dump (standalone CLI; deleted at the start of every collect, then written on `status: ok`) |
| `/run/hw-management-ssd-dump.lock` | Exclusive `flock`; one SSD dump collection at a time. Holds the holder's pid |
| `/usr/bin/hw-management-ssd-dump-collect.sh` | generate-dump helper (via `dump_cmd`) |
| `hw-management-generate-dump.sh` | `dump_cmd` the helper; helper copies leftover `$SSD_LOG_DIR` as `ssd-dump/` |

There is no separate `dump.sh`. `dump.sh` in older notes means
`hw-management-generate-dump.sh`.

## Restrictions

- **One SSD dump collection at a time**, enforced by an
  exclusive `flock` on **`/run/hw-management-ssd-dump.lock`**
  (`/run`, not the world writable `/run/lock`, so a local user
  cannot hold it and block root). The lock covers **only the SSD
  dump**, never the rest of generate-dump: a busy lock skips the
  SSD section and the full hw-mgmt dump is still collected and
  packed. Collect and `--verify` both take it, so neither can
  clobber `/var/log/ssd-dump`. Two independent reasons to
  serialize: the work dir is one fixed location that every
  collect removes, **and a vendor dump tool supports only one
  instance at a time**, so the SSD must not be driven twice at
  once even if the results were kept apart.
  The only wait is the helper's, bounded above; how long the
  lock is *held* is bounded too. The vendor
  tool runs in its own session under `timeout_sec` (JSON 1..120,
  `--timeout` 1..600) and is killed with SIGTERM then SIGKILL on
  the whole process group. Under generate-dump the helper adds
  `timeout --kill-after=5 195`, so the lock cannot be held past
  ~200 s there; the copy that follows it runs under
  `timeout 25`, as does the whole reuse attempt before it, and
  `dump_cmd` allows **380** to cover all of them — reaching 380
  means the helper was wedged, not slow. The copy is bounded on
  its own because it is the last step: an overrun cut short by
  `dump_cmd` would pack a truncated SSD section with nothing to
  say so, where its own timeout reports `failed to copy`. The
  25 s is one budget for the whole reuse phase rather than one
  per source, so a reuse that spends it and still fails leaves
  the collect behind it inside what `dump_cmd` allows. The flock lives on the
  open file description, so it is released by the kernel on any
  exit, SIGKILL or crash included; there is no stale lock to
  clean up. The vendor binary never inherits the lock fd
  (`O_CLOEXEC` plus `Popen` default `close_fds`), so even a tool
  wedged in uninterruptible D state cannot hold it.
  **The full system dump has priority over a standalone SSD
  dump**, and the two sides behave differently because of it.
  The **collector** gives up at once on a busy lock, with
  **rc 3** and
  `SSD dump tool busy: another SSD dump collection is already
  running (pid N)` on stderr and in syslog. Whoever takes the
  lock, collector or helper, records its pid in the lock file
  and clears it on release, so the refusal always names the
  process to look at. Nothing is created or removed, so
  the running collection's work dir, status file and previous
  `ssd-dump.tar.gz` are left exactly as they were, and the
  refused caller may simply retry. `3` is distinct from `1`
  (dump failed) and `0` (ok / skipped); `2` stays the argparse
  usage error.
  The **generate-dump helper** instead **waits**:
  `SSD dump tool waiting: waiting up to Ns for another SSD dump
  collection to finish (pid N)`, retrying every **2 s**. `N` is
  the largest `timeout_sec` in
  `/usr/share/ssd-dump-tools/ssd-dump-config.json` — the longest
  the collection it is waiting for may legitimately take —
  clamped to 120, rounded up to one 2 s poll, and falling back
  to 120 when no `timeout_sec` can be read at all (unknown, not
  short). `SSD_DUMP_CONFIG` overrides the path for testing.
  When the lock frees, the collection it waited for may already
  have produced the dump. A finished one in the default
  location is **reused** rather than driving the SSD again:
  `/var/log/ssd-dump.tar.gz` is unpacked into
  `$DUMP_FOLDER/ssd-dump/` (never copied in as an archive), or
  `/var/log/ssd-dump/` from a `--no-tar` run is copied. Reuse is
  logged as `SSD dump tool reused:` and leaves the source where
  its owner put it.
  Four conditions, all required. Reuse happens **only after a
  wait**, since with a free lock there was no competing
  collection at all. Only `status: ok` counts, so a failed
  leftover is collected again. A result marked `verify: yes` is
  **not** a dump: `--verify` passes its checks without reading
  the SSD and still reports `status: ok` in the default
  location, so reusing one would pack a status file into the
  system dump as the current SSD state. And the result must be **newer
  than the moment the wait began**: the run that held the lock
  need not have written the default location at all — it may
  have been a `--verify`, or a collect with a custom `--outdir`,
  which removes its own tarball and leaves this one alone — so
  without the age check an `ssd-dump.tar.gz` from days ago would
  be packed into the system dump as the current SSD state.
  The helper holds the lock across its own
  `rm -rf` and copy and exports `HW_MGMT_SSD_DUMP_LOCK_HELD=1`,
  without which the collector it calls would refuse the very
  collect it was called to do. The collector does not take that
  variable's word for it: it tries the lock through a second
  file description first, and skips locking only because that
  attempt shows the lock really is held. A copy of the variable
  stranded in some other environment therefore buys nothing.
  `flock` is looked up with `command -v`, not assumed to be
  `/usr/bin/flock`.
  Only if the wait runs out does it write
  `status: warning` / `locked: yes` into
  `$DUMP_FOLDER/ssd-dump/ssd-dump-status.log`, leave
  `$SSD_LOG_DIR` alone and exit **3** — its only non-zero exit
  for a valid invoke, and generate-dump ignores it.
  If the lock file cannot be created or locked at all (non-root
  caller that cannot write `/run`), **a collect refuses**:
  `SSD dump tool failed: cannot create lock …; refusing to
  collect`, rc 1, nothing collected. Unlocked collection is not
  best effort — it is a second vendor tool instance on the same
  SSD. `--verify` drives nothing, so it still runs and reports
  the condition as a `lock_warning:` status field; that keeps it
  usable for a non-root caller checking config and tools. A
  permission denial stays out of syslog (the run already carries
  `uid_warning`), anything else is a syslog warning. The
  **helper refuses too**, and for the stronger reason: its
  first act on a collect is `rm -rf "$SSD_LOG_DIR"`, so going
  ahead unlocked would delete the work dir of a collection in
  progress. With no usable lock — no `flock` on `PATH`, or a
  lock file that cannot be created — it touches neither
  `$SSD_LOG_DIR` nor the SSD, reports `no usable SSD dump
  lock …; refusing to collect` as `status: warning` in
  `$DUMP_FOLDER` and exits **0**. That report carries no
  `locked: yes`: nothing was contended, the lock was missing.
- **Real paths only.** `--outdir` basename must be `ssd-dump`
  (default `/var/log/ssd-dump`). The leaf and its parent must not
  be symlinks. `--device`, `$DUMP_FOLDER`, `$SSD_LOG_DIR` must
  be real directories or device nodes (no symlink leaf).

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

Default `--outdir` is **`/var/log/ssd-dump`**. The basename must
be **`ssd-dump`** (so `--outdir /srv/data` is refused). Each
collect **removes** that directory **and** the adjacent
**`ssd-dump.tar.gz`** (operator copies old results if needed),
then recreates an empty dir. `--verify` does **not** wipe. The
parent of `--outdir` must be a real directory (no symlink
parent; the `ssd-dump` leaf must not be a symlink) and
writable. On a sticky parent (`/tmp`), an existing `--outdir`
must be owned by this uid. If `status: ok` and **not**
`--no-tar`, the tool packs it to **`/var/log/ssd-dump.tar.gz`**
and **deletes** the directory.
`--no-tar` still deletes a leftover tarball so dir and tar are
never both present. generate-dump passes `--no-tar`, copies the
dir into the hw-mgmt tar, then **removes** `/var/log/ssd-dump`.
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
(`/var/log/ssd-dump`; mkdir if needed; no rmtree), carrying
`verify: yes` so that nothing takes it for a collected dump. A custom
`--outdir` is checked only; status stays on stdout so a later
collect is not blocked. stdout omits `warning:` and the last
`Status:` line (reason is on stderr). It also reports a
collection already in progress: rc 3 and
`SSD dump tool busy: …`, without writing a status file into the
work dir that collection owns. rc 0 = ok or skipped,
1 = warning, 3 = lock busy.

`ssd-dump-tool.log` is the collector + vendor run log (cmd lines
and vendor stdout/stderr). It is omitted when the vendor binary
never ran (missing config/tool, skip, unsupported model). Vendor
output is not copied to the console. Collector warnings also go
to **syslog `LOG_WARNING`**
(ident `hw-management-ssd-dump`): unsupported model, missing tool,
tool present but not executable (`chmod +x`).
Cannot rename `ssd-dump-tool.txt` to `.log` is **warning** (no
success pack). Vendor timeout kills the process group. SMI
`stage_from` refuses nested symlinks under `Setting/`; staged
scratch is dropped after the tool even on failure (`one_button/`
kept).
Console always has **`SSD dump tool started`** then, on
**`status: ok`**, **`SSD dump tool results:`** (`…/ssd-dump.tar.gz`
or `…/ssd-dump/` with `--no-tar`) then
**`SSD dump tool succeeded`**, **`SSD dump tool skipped`**, or
**`SSD dump tool failed: …`**
(even `--quiet`; generate-dump captures them).
**`SSD dump tool succeeded` is only printed once the result in
the preceding `results:` line was confirmed on disk** —
`/var/log/ssd-dump.tar.gz` for a standalone collect (non-empty
file, checked after packing), the copied `ssd-dump/` for
generate-dump. A pack that leaves no archive is
**`SSD dump tool failed: archive not created: …`** with rc 1,
never `succeeded`; a `--no-tar` run, whose result is the work
dir itself, says **`work dir not created: …`** the same way. `--verify` creates nothing, so it reports
**`SSD dump tool verify passed`** or
**`SSD dump tool verify failed: …`** and never `succeeded`. A
busy lock reports **`SSD dump tool busy: …`** (not `failed`).
With
**`--quiet --no-tar`**, Python omits results/succeeded;
the generate-dump helper prints them after it copies
`ssd-dump/`. Copy failure prints **`SSD dump tool failed:`**.
WARNING stays in
the log file and syslog, not duplicated on stderr.
`--verify` prints status fields on stdout. `--verify --quiet`
hides those fields (rc still 0/1/3). Syslog remains. No NVMe
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

- Python CLI: every collect starts by deleting the work dir and
  `<outdir>.tar.gz`. Packed again only when **`status: ok`** and
  not `--no-tar`. Warning/skip leave the new dir and **no**
  previous tarball.
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

CLI and generate-dump share `/var/log/ssd-dump`; the `flock` in
**Restrictions** stops the second SSD dump collection from
wiping the directory, while the rest of generate-dump still
runs. The CLI is refused (rc 3); the helper waits, then reuses
or recollects. Vendor timeout 90 s (Virtium) or 120 s
(Phison / defaults). JSON `timeout_sec`, in `defaults` and per
model alike, must be **1..120** — stricter than `--timeout` on
purpose, because the JSON budget is what runs under the
generate-dump helper's `timeout 195`; a larger value would risk
being killed mid-collect in the normal path. Over 120 is
`invalid config: …timeout_sec (must be 1..120)` and the config
is refused outright.
Standalone `--timeout` is the FAE override and has no 195 s
wrapper above it, so it may be higher, but is capped at
**600 s (10 min)**: it also decides how long the SSD dump lock
is held, so a typo must not lock out generate-dump for hours.
Outside 1..600 is the usage error (rc 2), before anything is
collected. Raising the JSON cap towards 600 would mean raising
the helper's 195 and `dump_cmd`'s 380 with it, and a full
system dump could then stall for over ten minutes on the SSD
section alone.

## Testing the lock on a target

`tests/hardware/ssd_dump_lock_test.sh` (root, destructive,
restores what it moves aside) runs the parallel-call
combinations of the CLI, `--verify`, the generate-dump helper and
generate-dump itself, in both orderings. It checks both sides of
the asymmetry: that the CLI is refused with rc 3 and the busy
message while the running collection's work dir survives byte
for byte, and that the helper waits, then either reuses the dump
the other run finished — counting stub invocations, so reuse
means the SSD really was not driven twice — or collects for
itself when there is nothing to reuse. It does not need the
dump-tools `.deb`: it generates a config pointing at a stub
vendor tool, which is also what makes the lock holder
deterministic. See `tests/hardware/README.md`.

## Adding a vendor later

Add a `vendors.<Name>.models.<Key>` object (`Key` is the last Identify
token, including `-…`):
`tool`, optional `tool_alt` (old vendor basename on PATH), `args` (`{device}`, `{outdir}`, `{model}`), `device_form`
(`controller` or `namespace`), optional `timeout_sec`.
Optional absolute `stage_from`, `stage_cfg` (cwd
name `one_button.cfg`),
`keep_dirs` (default `["one_button"]` when staging). Do not ship
the vendor binary, `smi/` tree, or JSON in hw-mgmt. Missing
`/usr/share/ssd-dump-tools/ssd-dump-config.json` is a
**warning**. JSON lives in the dump-tools `.deb`.

HLD / operator CLI are ECR notes (`SSD-dump-collector-HLD.md`,
`SSD-dump-collector-CLI.md`), not this package.
