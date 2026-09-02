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
import fcntl
import fnmatch
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import syslog
import tarfile
import time

DEFAULT_CONFIG = "/etc/hw-management-ssd/ssd-dump-config.json"
DEFAULT_OUTDIR = "/var/log/ssd-dump"
STATUS_NAME = "ssd-dump-status.log"
LOG_NAME = "ssd-dump-tool.log"
SYSLOG_IDENT = "hw-management-ssd-dump"
LOCKED_ENV = "HW_MGMT_SSD_DUMP_LOCKED"
LOCK_PATHS = (
    "/run/hw-management-ssd-dump.lock",
    "/var/lock/hw-management-ssd-dump.lock",
)
LOCK_WAIT_SEC = 200
PROTECTED_OUTDIRS = frozenset(("/", "/var", "/var/log", "/tmp", "/usr", "/etc"))
NVME_CTL_RE = re.compile(r"^nvme(\d+)$")
NVME_DEV_RE = re.compile(r"^nvme(\d+)(n\d+)?$")


class DumpError(Exception):
    """Expected failure; message is written as a warning."""


class DumpSkip(Exception):
    """Quiet skip (no NVMe / no model); not a warning."""


def acquire_run_lock(wait_sec=None):
    """Exclusive lock so two collectors cannot share /var/log/ssd-dump.

    collect.sh holds the same lock and sets HW_MGMT_SSD_DUMP_LOCKED=1
    so this process does not flock again (parent+child deadlock).
    """
    if os.environ.get(LOCKED_ENV) == "1":
        return None
    if wait_sec is None:
        wait_sec = LOCK_WAIT_SEC
    last_err = None
    fd = None
    for path in LOCK_PATHS:
        try:
            fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o644)
            break
        except OSError as exc:
            last_err = exc
            fd = None
    if fd is None:
        raise DumpError("cannot create ssd-dump lock: %s" % last_err)
    deadline = time.monotonic() + wait_sec
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BlockingIOError:
            if time.monotonic() >= deadline:
                try:
                    os.close(fd)
                except OSError:
                    pass
                raise DumpError("another ssd-dump is running")
            time.sleep(0.2)
        except OSError as exc:
            try:
                os.close(fd)
            except OSError:
                pass
            raise DumpError("cannot flock ssd-dump lock: %s" % exc)


def release_run_lock(lock_fd):
    if lock_fd is None:
        return
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
    except OSError:
        pass
    try:
        os.close(lock_fd)
    except OSError:
        pass


def syslog_warn(msg):
    """LOG_WARNING so rsyslog/journal show it; not printk/dmesg."""
    try:
        syslog.syslog(syslog.LOG_WARNING, msg)
    except Exception:
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
        for key in sorted(fields.keys()):
            val = fields[key]
            if val is None:
                val = ""
            f.write("%s: %s\n" % (key, val))
    return path


def load_config(path):
    with open(path, "r") as f:
        cfg = json.load(f)
    if not isinstance(cfg, dict):
        raise DumpError("invalid config: not an object")
    return cfg


def defaults_of(cfg):
    d = cfg.get("defaults") or {}
    return {
        "timeout_sec": int(d.get("timeout_sec", 120)),
        "gzip": bool(d.get("gzip", True)),
        "gzip_level": int(d.get("gzip_level", 5)),
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
        return "/dev/%sn1" % ctl
    raise DumpError("unsupported device_form: %s" % device_form)


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
    """JSON key: last token of Identify, keep '-' suffix
    (Virtium VTPM24CEXI080-BM110006 -> VTPM24CEXI080-BM110006)."""
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
    st = os.statvfs(path)
    return int((st.f_bavail * st.f_frsize) / (1024 * 1024))


def expand_args(args, mapping):
    out = []
    for a in args or []:
        s = str(a)
        for k, v in mapping.items():
            s = s.replace("{%s}" % k, v)
        out.append(s)
    return out


def gzip_file(path, level):
    gz_path = path + ".gz"
    try:
        with open(path, "rb") as f_in:
            with gzip.open(gz_path, "wb", compresslevel=level) as f_out:
                shutil.copyfileobj(f_in, f_out)
        os.remove(path)
        return gz_path, None
    except Exception as exc:
        if os.path.isfile(gz_path):
            try:
                os.remove(gz_path)
            except OSError:
                pass
        return path, str(exc)


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


def recreate_outdir(path):
    path = os.path.abspath(path)
    if path in PROTECTED_OUTDIRS:
        raise DumpError("refusing to recreate protected path: %s" % path)
    if os.path.isdir(path):
        default = os.path.abspath(DEFAULT_OUTDIR)
        if path != default and os.listdir(path):
            raise DumpError(
                "refusing to recreate non-empty directory: %s" % path
            )
        shutil.rmtree(path)
    elif os.path.exists(path):
        raise DumpError("refusing to recreate non-directory path: %s" % path)
    os.makedirs(path)
    return path


def pack_outdir(outdir):
    """Tar outdir to <outdir>.tar.gz and remove the directory.

    Write a .tmp archive first and replace the previous .tar.gz
    only after success. On failure, drop the .tmp; keep the old
    archive and the leftover dir.
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
    shutil.rmtree(outdir)
    return tar_path


def resolve_device(explicit, cfg=None, dev_dir="/dev"):
    if explicit:
        ctl, _ns = parse_nvme_name(explicit)
        if ctl is None:
            raise DumpError("not an NVMe device: %s" % explicit)
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


def run_collect(args, logf, fields):
    cfg_path = os.path.abspath(args.config)
    fields["config"] = cfg_path
    cfg = load_config(args.config)
    defs = defaults_of(cfg)
    gzip_on = defs["gzip"] and not args.no_gzip
    timeout_sec = args.timeout if args.timeout is not None else defs["timeout_sec"]
    fields["gzip"] = "yes" if gzip_on else "no"
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
    fields["device"] = run_dev
    fields["device_form"] = mcfg.get("device_form", "controller")

    tool = mcfg.get("tool") or ""
    fields["tool"] = tool
    tool_path = find_tool(tool)
    fields["tool_path"] = tool_path

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

    skip = {STATUS_NAME, LOG_NAME}
    matched = list_created_files(outdir, skip)
    if not matched:
        raise DumpError("vendor tool produced no dump files")

    result_files = []
    gzip_errors = []
    if gzip_on:
        for p in matched:
            if p.endswith(".gz"):
                result_files.append(p)
                continue
            newp, err = gzip_file(p, defs["gzip_level"])
            result_files.append(newp)
            if err:
                gzip_errors.append("%s: %s" % (os.path.basename(p), err))
    else:
        result_files = matched

    fields["files"] = ",".join(os.path.basename(p) for p in result_files)
    if gzip_errors:
        raise DumpError("gzip failed (kept uncompressed): %s" % "; ".join(gzip_errors))
    fields["status"] = "ok"
    fields["warning"] = ""
    return 0


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
    p.add_argument("--no-gzip", action="store_true", help="do not gzip dump files")
    p.add_argument("--timeout", type=int, default=None, help="override tool timeout seconds")
    p.add_argument(
        "--quiet",
        action="store_true",
        help="no console output (vendor log is still written to file)",
    )
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        syslog.openlog(SYSLOG_IDENT, syslog.LOG_PID | syslog.LOG_CONS, syslog.LOG_USER)
    except Exception:
        pass
    lock_fd = None
    try:
        lock_fd = acquire_run_lock()
    except DumpError as exc:
        msg = str(exc)
        syslog_warn(msg)
        if not args.quiet:
            sys.stderr.write(msg + "\n")
        return 1
    try:
        return _main_after_lock(args)
    finally:
        release_run_lock(lock_fd)


def _main_after_lock(args):
    outdir = os.path.abspath(args.outdir)
    try:
        recreate_outdir(outdir)
    except DumpError as exc:
        msg = str(exc)
        syslog_warn(msg)
        if not args.quiet:
            sys.stderr.write(msg + "\n")
        return 1
    except OSError as exc:
        msg = "cannot create outdir %s: %s" % (outdir, exc)
        syslog_warn(msg)
        if not args.quiet:
            sys.stderr.write(msg + "\n")
        return 1

    fields = {
        "status": "warning",
        "warning": "",
    }
    if os.geteuid() != 0:
        fields["uid_warning"] = "not root (uid=%s); vendor tools may fail" % os.geteuid()

    log_path = os.path.join(outdir, LOG_NAME)
    rc = 1
    try:
        with open(log_path, "w") as logf:
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
                log_print(logf, "WARNING: %s" % exc, echo=not args.quiet)
                syslog_warn(str(exc))
                rc = 1
            except Exception as exc:
                fields["status"] = "warning"
                fields["warning"] = "internal: %s" % exc
                log_print(logf, "WARNING: internal: %s" % exc, echo=not args.quiet)
                syslog_warn("internal: %s" % exc)
                rc = 1
    except OSError as exc:
        fields["warning"] = "cannot write log: %s" % exc
        syslog_warn(fields["warning"])
        rc = 1

    try:
        write_status(outdir, fields)
    except OSError as exc:
        msg = "cannot write status: %s" % exc
        syslog_warn(msg)
        if not args.quiet:
            sys.stderr.write(msg + "\n")
        return 1

    if fields.get("status") != "ok":
        return rc
    try:
        pack_outdir(outdir)
    except (OSError, tarfile.TarError) as exc:
        msg = "cannot pack outdir %s: %s" % (outdir, exc)
        fields["status"] = "warning"
        fields["warning"] = msg
        try:
            write_status(outdir, fields)
        except OSError as status_exc:
            syslog_warn("cannot write status: %s" % status_exc)
        syslog_warn(msg)
        if not args.quiet:
            sys.stderr.write(msg + "\n")
        return 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
