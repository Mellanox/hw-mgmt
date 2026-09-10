#!/usr/bin/env python3
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
##################################################################################
# Unified SSD dump collector. Vendor tools stay on PATH (NOS image).
# Called from hw-management-generate-dump.sh (best-effort) or standalone.
##################################################################################

from __future__ import print_function

import argparse
import fnmatch
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import syslog
import tarfile

DEFAULT_CONFIG = "/etc/hw-management-ssd/ssd-dump-config.json"
DEFAULT_OUTDIR = "/var/log/ssd-dump"
# generate-dump helper timeout is 195 s; JSON vendor budget <= this.
TIMEOUT_SEC_JSON_MAX = 120
STATUS_NAME = "ssd-dump-status.log"
LOG_NAME = "ssd-dump-tool.log"
# Live collector/vendor log during the run; renamed to LOG_NAME after.
LOG_TMP_NAME = "ssd-dump-tool.txt"
FILES_FIELD_MAX = 3
SYSLOG_IDENT = "hw-management-ssd-dump"
PROTECTED_OUTDIRS = frozenset(("/", "/var", "/var/log", "/tmp", "/usr", "/etc"))
NVME_CTL_RE = re.compile(r"^nvme(\d+)$")
NVME_DEV_RE = re.compile(r"^nvme(\d+)(n\d+)?$")


class DumpError(Exception):
    """Expected failure; message is written as a warning."""


class DumpSkip(Exception):
    """Quiet skip (no NVMe / no model); not a warning."""


def syslog_warn(msg):
    """LOG_WARNING so rsyslog/journal show it; not printk/dmesg."""
    try:
        syslog.syslog(syslog.LOG_WARNING, msg)
    except Exception:
        pass


MSG_STARTED = "SSD dump tool started"
MSG_RESULTS = "SSD dump tool results: "


def emit_always(msg):
    """Stderr even with --quiet (generate-dump still captures it)."""
    line = msg if msg.endswith("\n") else msg + "\n"
    sys.stderr.write(line)
    sys.stderr.flush()


def completion_message(fields):
    status = fields.get("status")
    if status == "warning":
        err = (fields.get("warning") or "").strip() or "error"
        return "SSD dump tool failed: %s" % err
    if status == "skipped":
        return "SSD dump tool skipped"
    return "SSD dump tool succeeded"


def results_message(outdir, no_tar):
    """Where the operator looks after a successful collect."""
    outdir = os.path.abspath(outdir)
    if no_tar:
        return "%s%s/" % (MSG_RESULTS, outdir.rstrip("/"))
    return "%s%s.tar.gz" % (MSG_RESULTS, outdir)


def append_log(log_path, msg):
    if not log_path or not os.path.isfile(log_path):
        return
    try:
        with open(log_path, "a") as f:
            f.write(msg if msg.endswith("\n") else msg + "\n")
    except OSError:
        pass


def drop_trailing_success_line(log_path):
    """Remove a premature 'succeeded' (and results) line if packing failed."""
    marker = "SSD dump tool succeeded\n"
    if not log_path or not os.path.isfile(log_path):
        return
    try:
        with open(log_path, "r") as f:
            text = f.read()
        if text.endswith(marker):
            text = text[: -len(marker)]
        body = text[:-1] if text.endswith("\n") else text
        idx = body.rfind("\n")
        last = body[idx + 1:] if idx >= 0 else body
        if last.startswith(MSG_RESULTS):
            text = body[: idx + 1] if idx >= 0 else ""
        with open(log_path, "w") as f:
            f.write(text)
    except OSError:
        pass


def log_print(logf, msg, echo=False):
    """Write to ssd-dump-tool.log. echo=True also copies to stderr.

    Vendor tool output stays in the log file only (thousands of
    segment lines). generate-dump.sh uses --quiet so even WARNING is
    not printed; it is still in the log and status files.
    """
    line = msg if msg.endswith("\n") else msg + "\n"
    if logf:
        logf.write(line)
        logf.flush()
    if echo:
        sys.stderr.write(line)


def write_status(outdir, fields):
    path = os.path.join(outdir, STATUS_NAME)
    with open(path, "w") as f:
        f.write(format_status_fields(fields))
    return path


def format_status_fields(fields):
    lines = []
    for key in sorted(fields.keys()):
        val = fields[key]
        if key == "warning" and not val:
            continue
        if val is None:
            val = ""
        lines.append("%s: %s\n" % (key, val))
    if fields.get("status") == "warning":
        lines.append("Status: error\n")
    elif fields.get("status") == "skipped":
        lines.append("Status: skipped\n")
    else:
        lines.append("Status: Ok / succeeded\n")
    return "".join(lines)


def format_bytes_km(nbytes):
    """Ceil dump size to K or M (1024). Zero bytes is 0K."""
    try:
        n = int(nbytes)
    except (TypeError, ValueError):
        n = 0
    if n <= 0:
        return "0K"
    mb = 1024 * 1024
    if n >= mb:
        return "%dM" % ((n + mb - 1) // mb)
    return "%dK" % ((n + 1023) // 1024)


def created_files_total_bytes(paths):
    total = 0
    for path in paths:
        try:
            total += os.path.getsize(path)
        except OSError:
            pass
    return total


def format_files_field(relpaths, total_bytes, limit=FILES_FIELD_MAX):
    """First names (comma-space), then count and K/M size of all files."""
    names = list(relpaths)
    n = len(names)
    shown = ", ".join(names[:limit] if n > limit else names)
    return "%s (%d in total, %s)" % (shown, n, format_bytes_km(total_bytes))


def promote_tool_log(outdir):
    """Rename live .txt log to ssd-dump-tool.log for the tarball."""
    src = os.path.join(outdir, LOG_TMP_NAME)
    dst = os.path.join(outdir, LOG_NAME)
    if os.path.isfile(src):
        os.replace(src, dst)
    return dst


def load_config(path):
    try:
        with open(path, "r") as f:
            cfg = json.load(f)
    except OSError as exc:
        raise DumpError("cannot read config %s: %s" % (path, exc))
    except ValueError as exc:
        raise DumpError("invalid config %s: %s" % (path, exc))
    if not isinstance(cfg, dict):
        raise DumpError("invalid config: not an object")
    _validate_config_shape(cfg)
    return cfg


def _require_dict(obj, what):
    if obj is None:
        return
    if not isinstance(obj, dict):
        raise DumpError("invalid config: %s is not an object" % what)


def _require_int(obj, what, min_value=None, max_value=None):
    if isinstance(obj, bool):
        raise DumpError("invalid config: %s" % what)
    try:
        value = int(obj)
    except (TypeError, ValueError):
        raise DumpError("invalid config: %s" % what)
    if min_value is not None and value < min_value:
        raise DumpError(_config_int_range_msg(what, min_value, max_value))
    if max_value is not None and value > max_value:
        raise DumpError(_config_int_range_msg(what, min_value, max_value))
    return value


def _config_int_range_msg(what, min_value, max_value):
    if min_value is not None and max_value is not None:
        return "invalid config: %s (must be %s..%s)" % (
            what,
            min_value,
            max_value,
        )
    if min_value is not None:
        return "invalid config: %s (must be >= %s)" % (what, min_value)
    return "invalid config: %s (must be <= %s)" % (what, max_value)


def _require_string(obj, what):
    if not isinstance(obj, str) or not obj:
        raise DumpError("invalid config: %s" % what)


def _require_rel_name(obj, what):
    _require_string(obj, what)
    if obj in (".", "..") or "/" in obj or obj.startswith("\\"):
        raise DumpError("invalid config: %s" % what)


def _require_string_list(obj, what):
    if obj is None:
        raise DumpError("invalid config: %s" % what)
    if not isinstance(obj, list) or any(not isinstance(item, str) for item in obj):
        raise DumpError("invalid config: %s" % what)


def _validate_config_shape(cfg):
    defaults = cfg.get("defaults")
    _require_dict(defaults, "defaults")
    if defaults:
        if "timeout_sec" in defaults:
            _require_int(
                defaults["timeout_sec"],
                "defaults.timeout_sec",
                min_value=1,
                max_value=TIMEOUT_SEC_JSON_MAX,
            )
        if "min_free_mb" in defaults:
            _require_int(
                defaults["min_free_mb"], "defaults.min_free_mb", min_value=0
            )
    vendors = cfg.get("vendors")
    _require_dict(vendors, "vendors")
    for vname, vdata in (vendors or {}).items():
        _require_dict(vdata, "vendors.%s" % vname)
        models = None if vdata is None else vdata.get("models")
        _require_dict(models, "vendors.%s.models" % vname)
        for mkey, mcfg in (models or {}).items():
            _require_dict(mcfg, "vendors.%s.models.%s" % (vname, mkey))
            if not mcfg or "tool" not in mcfg:
                raise DumpError(
                    "invalid config: vendors.%s.models.%s.tool" % (vname, mkey)
                )
            _require_string(
                mcfg["tool"], "vendors.%s.models.%s.tool" % (vname, mkey)
            )
            if mcfg.get("tool_alt"):
                _require_string(
                    mcfg["tool_alt"],
                    "vendors.%s.models.%s.tool_alt" % (vname, mkey),
                )
            if "args" not in mcfg:
                raise DumpError(
                    "invalid config: vendors.%s.models.%s.args" % (vname, mkey)
                )
            _require_string_list(
                mcfg["args"], "vendors.%s.models.%s.args" % (vname, mkey)
            )
            form = None if not mcfg else mcfg.get("device_form")
            if form not in ("controller", "namespace"):
                raise DumpError(
                    "invalid config: vendors.%s.models.%s.device_form"
                    % (vname, mkey)
                )
            if mcfg and "timeout_sec" in mcfg:
                _require_int(
                    mcfg["timeout_sec"],
                    "vendors.%s.models.%s.timeout_sec" % (vname, mkey),
                    min_value=1,
                    max_value=TIMEOUT_SEC_JSON_MAX,
                )
            if mcfg and "stage_from" in mcfg:
                _require_string(
                    mcfg["stage_from"],
                    "vendors.%s.models.%s.stage_from" % (vname, mkey),
                )
                sp = mcfg["stage_from"]
                if not os.path.isabs(sp):
                    raise DumpError(
                        "invalid config: vendors.%s.models.%s.stage_from"
                        % (vname, mkey)
                    )
            if mcfg and "stage_cfg" in mcfg:
                _require_rel_name(
                    mcfg["stage_cfg"],
                    "vendors.%s.models.%s.stage_cfg" % (vname, mkey),
                )
            if mcfg and "keep_dirs" in mcfg:
                _require_string_list(
                    mcfg["keep_dirs"],
                    "vendors.%s.models.%s.keep_dirs" % (vname, mkey),
                )
                if not mcfg["keep_dirs"]:
                    raise DumpError(
                        "invalid config: vendors.%s.models.%s.keep_dirs"
                        % (vname, mkey)
                    )
                for dname in mcfg["keep_dirs"]:
                    _require_rel_name(
                        dname,
                        "vendors.%s.models.%s.keep_dirs" % (vname, mkey),
                    )


def defaults_of(cfg):
    d = cfg.get("defaults") or {}
    return {
        "timeout_sec": int(d.get("timeout_sec", 120)),
        "min_free_mb": int(d.get("min_free_mb", 64)),
    }


def list_nvme_controllers(dev_dir="/dev"):
    if not os.path.isdir(dev_dir):
        return []
    found = []
    for name in os.listdir(dev_dir):
        if NVME_CTL_RE.match(name):
            found.append(os.path.join(dev_dir, name))

    def _key(p):
        m = NVME_CTL_RE.match(os.path.basename(p))
        return int(m.group(1)) if m else 0

    return sorted(found, key=_key)


def list_nvme_namespaces(ctl, dev_dir="/dev"):
    """Namespace nodes /dev/<ctl>nN, sorted by N."""
    if not os.path.isdir(dev_dir):
        return []
    found = []
    prefix = ctl + "n"
    for name in os.listdir(dev_dir):
        if not name.startswith(prefix):
            continue
        rest = name[len(prefix):]
        if rest.isdigit():
            found.append((int(rest), os.path.join(dev_dir, name)))
    found.sort()
    return [p for _n, p in found]


def parse_nvme_name(dev):
    base = os.path.basename(dev.rstrip("/"))
    m = NVME_DEV_RE.match(base)
    if not m:
        return None, None
    ctl = "nvme%s" % m.group(1)
    ns = m.group(2)
    return ctl, ns


def map_device(dev, device_form):
    ctl, ns = parse_nvme_name(dev)
    if ctl is None:
        raise DumpError("not an NVMe device: %s" % dev)
    form = (device_form or "controller").strip().lower()
    if form == "controller":
        return "/dev/%s" % ctl
    if form == "namespace":
        if ns:
            return "/dev/%s%s" % (ctl, ns)
        nss = list_nvme_namespaces(ctl)
        if not nss:
            raise DumpError("NVMe namespace not found for /dev/%s" % ctl)
        return nss[0]
    raise DumpError("unsupported device_form: %s" % device_form)


def check_nvme_node(path):
    """Char/block NVMe node; no symlink. Used after map_device."""
    try:
        st = os.lstat(path)
    except OSError:
        raise DumpError("NVMe device not found: %s" % path)
    if stat.S_ISLNK(st.st_mode):
        raise DumpError("refusing NVMe device symlink: %s" % path)
    if not (stat.S_ISBLK(st.st_mode) or stat.S_ISCHR(st.st_mode)):
        raise DumpError("not an NVMe device node: %s" % path)


def check_stage_from(stage_from, stage_cfg):
    """Read-only vendor cwd tree (Setting/ + cfg). No symlinks."""
    path = os.path.abspath(stage_from)
    if os.path.realpath(path) != path:
        raise DumpError("refusing stage_from with symlink component: %s" % path)
    if not os.path.isdir(path) or os.path.islink(path):
        raise DumpError("SSD dump stage_from not found: %s" % path)
    setting = os.path.join(path, "Setting")
    if not os.path.isdir(setting) or os.path.islink(setting):
        raise DumpError("SSD dump stage_from missing Setting/: %s" % path)
    cfg_src = os.path.join(path, stage_cfg)
    if not os.path.isfile(cfg_src) or os.path.islink(cfg_src):
        raise DumpError("SSD dump stage_from missing %s: %s" % (stage_cfg, path))
    return path, cfg_src


def stage_vendor_cwd(outdir, stage_from, stage_cfg):
    src_root, cfg_src = check_stage_from(stage_from, stage_cfg)
    dest_setting = os.path.join(outdir, "Setting")
    shutil.copytree(os.path.join(src_root, "Setting"), dest_setting, symlinks=False)
    shutil.copy2(cfg_src, os.path.join(outdir, "one_button.cfg"))


def strip_workdir(outdir, keep_dirs):
    """Drop staged cwd and vendor scratch; keep dump dirs + status/log."""
    keep = set(keep_dirs or [])
    keep.update((STATUS_NAME, LOG_NAME, LOG_TMP_NAME))
    for name in os.listdir(outdir):
        if name in keep:
            continue
        p = os.path.join(outdir, name)
        try:
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p)
            else:
                os.remove(p)
        except OSError:
            raise DumpError("cannot drop staged file %s" % p)


def read_sysfs_nvme(ctl, sys_class="/sys/class/nvme"):
    model = ""
    fw = ""
    base = os.path.join(sys_class, ctl)
    mpath = os.path.join(base, "model")
    fpath = os.path.join(base, "firmware_rev")
    if os.path.isfile(mpath):
        with open(mpath, "r") as f:
            model = f.read().strip()
    if os.path.isfile(fpath):
        with open(fpath, "r") as f:
            fw = f.read().strip()
    return model, fw


def part_name_from_model(model_str):
    # SpellCheck-ignoreBlockStart
    """JSON key: last token of Identify, keep '-' suffix
    (Virtium VTPM24CEXI080-BM110006 -> VTPM24CEXI080-BM110006)."""
    # SpellCheck-ignoreBlockEnd
    s = (model_str or "").strip()
    if not s:
        return ""
    return s.split()[-1]


def model_match_keys(model_str):
    s = (model_str or "").strip()
    keys = []
    if s:
        keys.append(s)
        last = s.split()[-1]
        if last not in keys:
            keys.append(last)
    return keys


def find_model_config(cfg, model_str):
    vendors = cfg.get("vendors") or {}
    keys = model_match_keys(model_str)
    for vname, vdata in vendors.items():
        models = (vdata or {}).get("models") or {}
        for mkey, mcfg in models.items():
            for cand in keys:
                if cand == mkey or cand.endswith(mkey):
                    return vname, mkey, mcfg or {}
            for cand in keys:
                if fnmatch.fnmatch(cand, mkey):
                    return vname, mkey, mcfg or {}
    return None, None, None


def free_mb(path):
    probe = os.path.abspath(path)
    while probe and not os.path.exists(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            break
        probe = parent
    st = os.statvfs(probe)
    return int((st.f_bavail * st.f_frsize) / (1024 * 1024))


def expand_args(args, mapping):
    out = []
    for a in args or []:
        s = str(a)
        for k, v in mapping.items():
            s = s.replace("{%s}" % k, v)
        out.append(s)
    return out


def list_created_files(outdir, skip_names):
    """Regular files in outdir except skip_names (status/log)."""
    skip = set(skip_names)
    found = []
    for dirpath, _dirs, names in os.walk(outdir):
        for name in names:
            if name in skip:
                continue
            p = os.path.join(dirpath, name)
            if os.path.isfile(p) and not os.path.islink(p):
                found.append(p)
    return sorted(found)


def check_outdir(path):
    """Same refusals as recreate_outdir, without creating or deleting."""
    path = os.path.abspath(path)
    if os.path.realpath(path) != path:
        raise DumpError(
            "refusing to recreate path with symlink component: %s" % path
        )
    if path in PROTECTED_OUTDIRS:
        raise DumpError("refusing to recreate protected path: %s" % path)
    if os.path.islink(path):
        raise DumpError("refusing to recreate symlink path: %s" % path)
    if os.path.isdir(path):
        default = os.path.abspath(DEFAULT_OUTDIR)
        if path != default and os.listdir(path):
            raise DumpError(
                "refusing to recreate non-empty directory: %s" % path
            )
        if not os.access(path, os.W_OK | os.X_OK):
            raise DumpError("outdir not writable: %s" % path)
        return path
    if os.path.exists(path):
        raise DumpError("refusing to recreate non-directory path: %s" % path)
    parent = os.path.dirname(path) or "/"
    if not os.path.isdir(parent):
        raise DumpError("cannot create outdir %s: parent missing" % path)
    if not os.access(parent, os.W_OK | os.X_OK):
        raise DumpError("cannot create outdir %s: parent not writable" % path)
    return path


def recreate_outdir(path):
    path = check_outdir(path)
    if os.path.isdir(path):
        shutil.rmtree(path)
    os.makedirs(path)
    return path


def pack_outdir(outdir):
    """Tar outdir to <outdir>.tar.gz and remove the directory.

    Write a .tmp archive first and replace the previous .tar.gz
    only after success. On tar failure, drop the .tmp; keep the old
    archive and the leftover dir. After os.replace the new archive
    is committed: rmtree failure does not roll it back or change
    status to warning.
    """
    outdir = os.path.abspath(outdir)
    tar_path = outdir + ".tar.gz"
    tmp_tar_path = tar_path + ".tmp"
    if os.path.exists(tmp_tar_path):
        os.remove(tmp_tar_path)
    try:
        with tarfile.open(tmp_tar_path, "w:gz") as tar:
            tar.add(outdir, arcname=os.path.basename(outdir))
    except Exception:
        if os.path.isfile(tmp_tar_path):
            try:
                os.remove(tmp_tar_path)
            except OSError:
                pass
        raise
    os.replace(tmp_tar_path, tar_path)
    try:
        shutil.rmtree(outdir)
    except OSError as exc:
        syslog_warn("packed %s; leftover dir %s: %s" % (tar_path, outdir, exc))
    return tar_path


def resolve_device(explicit, cfg=None, dev_dir="/dev"):
    if explicit:
        explicit = os.path.abspath(explicit)
        dev_dir = os.path.abspath(dev_dir)
        if os.path.dirname(explicit) != dev_dir:
            raise DumpError("not an NVMe device: %s" % explicit)
        ctl, _ns = parse_nvme_name(explicit)
        if ctl is None:
            raise DumpError("not an NVMe device: %s" % explicit)
        check_nvme_node(explicit)
        return explicit
    ctrls = list_nvme_controllers(dev_dir)
    if not ctrls:
        raise DumpSkip("no NVMe controller found")
    first_with_model = None
    for p in ctrls:
        ctl, _ns = parse_nvme_name(p)
        if ctl is None:
            continue
        model, _fw = read_sysfs_nvme(ctl)
        if not model:
            continue
        if first_with_model is None:
            first_with_model = p
        if cfg is not None:
            _v, _k, mcfg = find_model_config(cfg, model)
            if mcfg:
                return p
    if first_with_model:
        return first_with_model
    raise DumpSkip("no NVMe model in sysfs")


def find_tool(name):
    """Locate JSON `tool` on PATH (or as an absolute path).

    shutil.which() skips non-executable files, so a present but
    chmod -x binary looked like "not found". Search PATH ourselves:
    executable match wins; else a non-executable file -> that warning.
    """
    if not name:
        raise DumpError("SSD dump tool not found on PATH: %s" % name)
    if os.path.isabs(name):
        if os.path.isfile(name):
            if os.access(name, os.X_OK):
                return name
            raise DumpError("SSD dump tool not executable: %s" % name)
        raise DumpError("SSD dump tool not found on PATH: %s" % name)

    found_nonexec = None
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if not d:
            continue
        p = os.path.join(d, name)
        if not os.path.isfile(p):
            continue
        if os.access(p, os.X_OK):
            return p
        if found_nonexec is None:
            found_nonexec = p
    if found_nonexec:
        raise DumpError("SSD dump tool not executable: %s" % found_nonexec)
    raise DumpError("SSD dump tool not found on PATH: %s" % name)


def tool_candidates(mcfg):
    """JSON `tool` then optional `tool_alt` (old vendor basename)."""
    names = []
    for key in ("tool", "tool_alt"):
        val = (mcfg.get(key) or "") if mcfg else ""
        if val and val not in names:
            names.append(val)
    return names


def resolve_tool(mcfg):
    """First executable JSON tool name; basename used is fields['tool']."""
    names = tool_candidates(mcfg)
    if not names:
        raise DumpError("SSD dump tool not found on PATH: ")
    nonexec = None
    for name in names:
        try:
            return find_tool(name), name
        except DumpError as exc:
            if "not executable" in str(exc) and nonexec is None:
                nonexec = exc
    if nonexec is not None:
        raise nonexec
    raise DumpError("SSD dump tool not found on PATH: %s" % ", ".join(names))


def run_collect(args, logf, fields):
    cfg_path = os.path.abspath(args.config)
    fields["config"] = cfg_path
    cfg = load_config(args.config)
    defs = defaults_of(cfg)
    timeout_sec = args.timeout if args.timeout is not None else defs["timeout_sec"]
    fields["min_free_mb"] = str(defs["min_free_mb"])

    outdir = os.path.abspath(args.outdir)
    fields["outdir"] = outdir

    device = resolve_device(args.device, cfg)
    fields["device_in"] = device
    ctl, _ns = parse_nvme_name(device)
    model, fw = read_sysfs_nvme(ctl)
    fields["model"] = model
    fields["fw"] = fw
    fields["part"] = part_name_from_model(model)
    if not model:
        if args.device:
            raise DumpError("unable to read NVMe model from sysfs")
        raise DumpSkip("no NVMe model in sysfs")

    vendor, mkey, mcfg = find_model_config(cfg, model)
    if not mcfg:
        raise DumpError(
            'unsupported SSD model "%s" for the SSD dump tool'
            % model
        )
    fields["vendor"] = vendor
    fields["json_model"] = mkey

    timeout_sec = int(mcfg.get("timeout_sec", timeout_sec))
    if args.timeout is not None:
        timeout_sec = args.timeout
    fields["timeout_sec"] = str(timeout_sec)

    run_dev = map_device(device, mcfg.get("device_form", "controller"))
    check_nvme_node(run_dev)
    fields["device"] = run_dev
    fields["device_form"] = mcfg.get("device_form", "controller")

    tool_path, tool = resolve_tool(mcfg)
    fields["tool"] = tool
    fields["tool_path"] = tool_path

    stage_from = mcfg.get("stage_from") or ""
    stage_cfg = mcfg.get("stage_cfg") or "one_button_NV.cfg"
    keep_dirs = mcfg.get("keep_dirs")
    if stage_from and keep_dirs is None:
        keep_dirs = ["one_button"]
    if stage_from:
        fields["stage_from"] = stage_from
        check_stage_from(stage_from, stage_cfg)

    avail = free_mb(outdir)
    fields["free_mb"] = str(avail)
    if avail < defs["min_free_mb"]:
        raise DumpError(
            "not enough free space: %s MB < min_free_mb %s"
            % (avail, defs["min_free_mb"])
        )

    mapping = {
        "device": run_dev,
        "outdir": outdir,
        "model": mkey,
    }
    cmd = [tool_path] + expand_args(mcfg.get("args") or [], mapping)
    fields["cmd"] = " ".join(cmd)
    if args.verify:
        fields["status"] = "ok"
        fields["warning"] = ""
        fields["verify"] = "yes"
        log_print(logf, "verify ok: %s" % fields["cmd"])
        return 0

    if stage_from:
        log_print(logf, "stage_from: %s cfg=%s" % (stage_from, stage_cfg))
        stage_vendor_cwd(outdir, stage_from, stage_cfg)

    log_print(logf, "running: %s (cwd=%s timeout=%ss)" % (fields["cmd"], outdir, timeout_sec))
    logf.flush()

    try:
        proc = subprocess.run(
            cmd,
            cwd=outdir,
            stdout=logf,
            stderr=subprocess.STDOUT,
            timeout=timeout_sec,
            universal_newlines=True,
        )
        logf.flush()
        fields["tool_rc"] = str(proc.returncode)
        if proc.returncode != 0:
            raise DumpError("vendor tool exit %s" % proc.returncode)
    except subprocess.TimeoutExpired:
        logf.flush()
        fields["tool_rc"] = "timeout"
        raise DumpError("vendor tool timeout after %s s" % timeout_sec)
    except OSError as exc:
        fields["tool_rc"] = "exec_error"
        raise DumpError("vendor tool exec failed: %s" % exc)

    if keep_dirs:
        strip_workdir(outdir, keep_dirs)

    skip = {STATUS_NAME, LOG_NAME, LOG_TMP_NAME}
    matched = list_created_files(outdir, skip)
    if not matched:
        raise DumpError("vendor tool produced no dump files")

    fields["files"] = format_files_field(
        (os.path.relpath(p, outdir) for p in matched),
        created_files_total_bytes(matched),
    )
    fields["status"] = "ok"
    fields["warning"] = ""
    return 0


def _positive_int(value):
    ivalue = int(value)
    if ivalue <= 0:
        raise argparse.ArgumentTypeError("must be > 0")
    return ivalue


def parse_args(argv):
    p = argparse.ArgumentParser(
        description="Collect vendor SSD dump logs (nandlog) into an output directory."
    )
    p.add_argument("--device", help="NVMe device (/dev/nvme0 or /dev/nvme0n1)")
    p.add_argument(
        "--outdir",
        default=DEFAULT_OUTDIR,
        help="directory for dump files (default: %s)" % DEFAULT_OUTDIR,
    )
    p.add_argument(
        "--config",
        default=DEFAULT_CONFIG,
        help="JSON config (default: %s)" % DEFAULT_CONFIG,
    )
    p.add_argument(
        "--timeout",
        type=_positive_int,
        default=None,
        help="override tool timeout seconds (must be > 0)",
    )
    p.add_argument(
        "--quiet",
        action="store_true",
        help="hide status fields on --verify stdout; start/fail still print",
    )
    p.add_argument(
        "--no-tar",
        action="store_true",
        help="do not pack <outdir>.tar.gz (leave the work directory)",
    )
    p.add_argument(
        "--verify",
        action="store_true",
        help="check SSD, JSON, tool, free space; do not run the vendor tool",
    )
    return p.parse_args(argv)


def run_verify(args):
    """Preflight: same checks as collect, no vendor tool, no dump files."""
    fields = {
        "status": "warning",
        "warning": "",
        "verify": "yes",
    }
    if os.geteuid() != 0:
        fields["uid_warning"] = "not root (uid=%s); vendor tools may fail" % os.geteuid()
    logf = io.StringIO()
    rc = 1
    try:
        check_outdir(args.outdir)
        if not os.path.isfile(args.config):
            raise DumpError("config not found: %s" % args.config)
        rc = run_collect(args, logf, fields)
    except DumpSkip as exc:
        fields["status"] = "skipped"
        fields["warning"] = ""
        log_print(logf, "skipped: %s" % exc)
        rc = 0
    except DumpError as exc:
        fields["status"] = "warning"
        fields["warning"] = str(exc)
        log_print(logf, "WARNING: %s" % exc, echo=False)
        syslog_warn(str(exc))
        rc = 1
    except Exception as exc:
        fields["status"] = "warning"
        fields["warning"] = "internal: %s" % exc
        log_print(logf, "WARNING: internal: %s" % exc, echo=False)
        syslog_warn("internal: %s" % exc)
        rc = 1
    emit_always(completion_message(fields))
    if not args.quiet:
        sys.stdout.write(format_status_fields(fields))
    return rc


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        syslog.openlog(SYSLOG_IDENT, syslog.LOG_PID | syslog.LOG_CONS, syslog.LOG_USER)
    except Exception:
        pass
    emit_always(MSG_STARTED)
    if args.verify:
        return run_verify(args)
    return run_dump(args)


def run_dump(args):
    outdir = os.path.abspath(args.outdir)
    fields = {
        "status": "warning",
        "warning": "",
    }
    log_path = None
    rc = 1
    try:
        try:
            recreate_outdir(outdir)
        except DumpError as exc:
            msg = str(exc)
            fields["warning"] = msg
            syslog_warn(msg)
            rc = 1
            return 1
        except OSError as exc:
            msg = "cannot create outdir %s: %s" % (outdir, exc)
            fields["warning"] = msg
            syslog_warn(msg)
            rc = 1
            return 1

        if os.geteuid() != 0:
            fields["uid_warning"] = (
                "not root (uid=%s); vendor tools may fail" % os.geteuid()
            )

        log_path = os.path.join(outdir, LOG_NAME)
        log_tmp = os.path.join(outdir, LOG_TMP_NAME)
        try:
            with open(log_tmp, "w") as logf:
                log_print(logf, MSG_STARTED, echo=False)
                try:
                    if not os.path.isfile(args.config):
                        raise DumpError("config not found: %s" % args.config)
                    rc = run_collect(args, logf, fields)
                except DumpSkip as exc:
                    fields["status"] = "skipped"
                    fields["warning"] = ""
                    log_print(logf, "skipped: %s" % exc)
                    rc = 0
                except DumpError as exc:
                    fields["status"] = "warning"
                    fields["warning"] = str(exc)
                    log_print(logf, "WARNING: %s" % exc, echo=False)
                    syslog_warn(str(exc))
                    rc = 1
                except Exception as exc:
                    fields["status"] = "warning"
                    fields["warning"] = "internal: %s" % exc
                    log_print(logf, "WARNING: internal: %s" % exc, echo=False)
                    syslog_warn("internal: %s" % exc)
                    rc = 1
        except OSError as exc:
            fields["warning"] = "cannot write log: %s" % exc
            syslog_warn(fields["warning"])
            rc = 1

        try:
            promote_tool_log(outdir)
        except OSError as exc:
            fields["warning"] = "cannot write log: %s" % exc
            syslog_warn(fields["warning"])
            rc = 1

        try:
            write_status(outdir, fields)
        except OSError as exc:
            msg = "cannot write status: %s" % exc
            fields["warning"] = msg
            fields["status"] = "warning"
            syslog_warn(msg)
            rc = 1
            return 1

        if fields.get("status") != "ok":
            return rc
        append_log(log_path, results_message(outdir, args.no_tar))
        append_log(log_path, completion_message(fields))
        if args.no_tar:
            log_path = None
            return rc
        try:
            pack_outdir(outdir)
        except (OSError, tarfile.TarError) as exc:
            msg = "cannot pack outdir %s: %s" % (outdir, exc)
            fields["status"] = "warning"
            fields["warning"] = msg
            drop_trailing_success_line(log_path)
            try:
                write_status(outdir, fields)
            except OSError as status_exc:
                syslog_warn("cannot write status: %s" % status_exc)
            syslog_warn(msg)
            rc = 1
            return 1
        log_path = None
        return rc
    finally:
        append_log(log_path, completion_message(fields))
        if fields.get("status") == "ok":
            emit_always(results_message(outdir, args.no_tar))
        emit_always(completion_message(fields))


if __name__ == "__main__":
    sys.exit(main())
