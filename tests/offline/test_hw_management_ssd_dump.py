#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#

"""Offline tests for hw-management-ssd-dump.py."""

import gzip
import importlib.util
import json
import os
import stat
import tarfile
import textwrap

import pytest

SCRIPT = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "usr",
    "usr",
    "bin",
    "hw-management-ssd-dump.py",
)


def load_mod():
    spec = importlib.util.spec_from_file_location("hw_management_ssd_dump", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def ssd():
    return load_mod()


@pytest.fixture(autouse=True)
def _ssd_dump_nested_lock(monkeypatch):
    """collect.sh already holds the lock; tests are the same nested case."""
    monkeypatch.setenv("HW_MGMT_SSD_DUMP_LOCKED", "1")


def write_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f)


def virtium_cfg(tool):
    return {
        "defaults": {
            "timeout_sec": 120,
            "gzip": True,
            "gzip_level": 5,
            "min_free_mb": 1,
        },
        "vendors": {
            "Virtium": {
                "models": {
                    "VTPM24CEXI080-BM110006": {
                        "tool": tool,
                        "args": ["{device}"],
                        "device_form": "controller",
                        "timeout_sec": 90,
                    }
                }
            }
        },
    }


def fake_tool(path):
    with open(path, "w") as f:
        f.write(
            textwrap.dedent(
                """\
                #!/bin/sh
                echo "Virtium vtFA_RTK_5766 1.0"
                echo "The binary log was written to file : nandlog_64384-1454.bin"
                echo dummy > nandlog_64384-1454.bin
                """
            )
        )
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)


def tar_text(tar_path, member):
    with tarfile.open(tar_path, "r:gz") as tar:
        f = tar.extractfile(member)
        return f.read().decode("utf-8")


def tar_names(tar_path):
    with tarfile.open(tar_path, "r:gz") as tar:
        return tar.getnames()


class TestMapDevice:
    def test_n1_to_controller(self, ssd):
        assert ssd.map_device("/dev/nvme0n1", "controller") == "/dev/nvme0"

    def test_controller_stays(self, ssd):
        assert ssd.map_device("/dev/nvme0", "controller") == "/dev/nvme0"

    def test_namespace_default_n1(self, ssd):
        assert ssd.map_device("/dev/nvme0", "namespace") == "/dev/nvme0n1"

    def test_non_nvme_rejected(self, ssd):
        with pytest.raises(ssd.DumpError):
            ssd.map_device("/dev/notnvme", "controller")


class TestModelMatch:
    def test_part_name_keeps_suffix(self, ssd):
        assert ssd.part_name_from_model(
            "Virtium VTPM24CEXI080-BM110006"
        ) == "VTPM24CEXI080-BM110006"

    def test_suffix_virtium_prefix(self, ssd):
        cfg = virtium_cfg("vtFA_RTK_5766_v2")
        v, k, m = ssd.find_model_config(
            cfg, "Virtium VTPM24CEXI080-BM110006"
        )
        assert v == "Virtium"
        assert k == "VTPM24CEXI080-BM110006"
        assert m["tool"] == "vtFA_RTK_5766_v2"

    def test_exact_key(self, ssd):
        cfg = virtium_cfg("vtFA_RTK_5766_v2")
        v, k, _ = ssd.find_model_config(cfg, "VTPM24CEXI080-BM110006")
        assert v == "Virtium" and k == "VTPM24CEXI080-BM110006"

    def test_unknown(self, ssd):
        cfg = virtium_cfg("vtFA_RTK_5766_v2")
        v, k, m = ssd.find_model_config(cfg, "MD681GEEBC82")
        assert v is None and k is None and m is None


class TestGzip:
    def test_success_removes_bin(self, ssd, tmp_path):
        bin_path = str(tmp_path / "nandlog_1.bin")
        with open(bin_path, "wb") as f:
            f.write(b"abc" * 100)
        gz, err = ssd.gzip_file(bin_path, 5)
        assert err is None
        assert gz.endswith(".gz")
        assert not os.path.isfile(bin_path)
        with gzip.open(gz, "rb") as f:
            assert f.read() == b"abc" * 100

    def test_fail_keeps_bin(self, ssd, tmp_path, monkeypatch):
        bin_path = str(tmp_path / "nandlog_1.bin")
        with open(bin_path, "wb") as f:
            f.write(b"data")

        def boom(*_a, **_k):
            raise OSError("disk full")

        monkeypatch.setattr(ssd.gzip, "open", boom)
        out, err = ssd.gzip_file(bin_path, 5)
        assert err
        assert out == bin_path
        assert os.path.isfile(bin_path)


class TestCreatedFiles:
    def test_lists_new_files_skips_log(self, ssd, tmp_path):
        nand = tmp_path / "nandlog_1.bin"
        nand.write_text("x")
        (tmp_path / "ssd-dump-tool.log").write_text("log")
        got = ssd.list_created_files(
            str(tmp_path), {"ssd-dump-status.log", "ssd-dump-tool.log"}
        )
        assert got == [str(nand)]


class TestRecreateOutdir:
    def test_refuses_existing_file(self, ssd, tmp_path):
        target = tmp_path / "not-a-dir"
        target.write_text("keep me")
        with pytest.raises(ssd.DumpError, match="non-directory"):
            ssd.recreate_outdir(str(target))
        assert target.read_text() == "keep me"

    def test_refuses_nonempty_custom_dir(self, ssd, tmp_path):
        target = tmp_path / "custom"
        target.mkdir()
        keep = target / "keep.bin"
        keep.write_text("x")
        with pytest.raises(ssd.DumpError, match="non-empty directory"):
            ssd.recreate_outdir(str(target))
        assert keep.read_text() == "x"

    def test_default_outdir_rmtree(self, ssd, tmp_path, monkeypatch):
        target = tmp_path / "ssd-dump"
        target.mkdir()
        (target / "old.bin").write_text("x")
        monkeypatch.setattr(ssd, "DEFAULT_OUTDIR", str(target))
        ssd.recreate_outdir(str(target))
        assert os.path.isdir(str(target))
        assert os.listdir(str(target)) == []


class TestPackOutdir:
    def test_keeps_old_archive_on_fail(self, ssd, tmp_path, monkeypatch):
        outdir = tmp_path / "out"
        outdir.mkdir()
        (outdir / "f.bin").write_text("x")
        tar_path = tmp_path / "out.tar.gz"
        tar_path.write_bytes(b"OLD")

        def boom(*_a, **_k):
            raise OSError("pack fail")

        monkeypatch.setattr(ssd.tarfile, "open", boom)
        with pytest.raises(OSError):
            ssd.pack_outdir(str(outdir))
        assert tar_path.read_bytes() == b"OLD"
        assert outdir.is_dir()
        assert not (tmp_path / "out.tar.gz.tmp").exists()


class TestFindTool:
    def test_missing(self, ssd, tmp_path, monkeypatch):
        monkeypatch.setenv("PATH", str(tmp_path))
        with pytest.raises(ssd.DumpError, match="not found on PATH"):
            ssd.find_tool("vtFA_missing")

    def test_not_executable(self, ssd, tmp_path, monkeypatch):
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        tool = bin_dir / "vtFA_RTK_5766_v2"
        tool.write_text("x")
        os.chmod(str(tool), 0o644)
        monkeypatch.setenv("PATH", str(bin_dir))
        with pytest.raises(ssd.DumpError, match="not executable"):
            ssd.find_tool("vtFA_RTK_5766_v2")

    def test_executable_wins_over_earlier_nonexec(self, ssd, tmp_path, monkeypatch):
        d1 = tmp_path / "a"
        d2 = tmp_path / "b"
        d1.mkdir()
        d2.mkdir()
        bad = d1 / "vtFA_RTK_5766_v2"
        good = d2 / "vtFA_RTK_5766_v2"
        bad.write_text("no")
        os.chmod(str(bad), 0o644)
        good.write_text("yes")
        os.chmod(str(good), 0o755)
        monkeypatch.setenv("PATH", "%s%s%s" % (d1, os.pathsep, d2))
        assert ssd.find_tool("vtFA_RTK_5766_v2") == str(good)


class TestResolveDevice:
    def test_explicit_non_nvme_is_error(self, ssd):
        with pytest.raises(ssd.DumpError, match="not an NVMe"):
            ssd.resolve_device("/dev/sda", virtium_cfg("t"))

    def test_picks_json_matching_controller(self, ssd, monkeypatch):
        cfg = virtium_cfg("t")
        monkeypatch.setattr(
            ssd, "list_nvme_controllers", lambda *_a, **_k: ["/dev/nvme0", "/dev/nvme1"]
        )

        def _read(ctl, sys_class="/sys/class/nvme"):
            if ctl == "nvme0":
                return ("OtherVendor OTHER-1", "1")
            return ("Virtium VTPM24CEXI080-BM110006", "CE00A474")

        monkeypatch.setattr(ssd, "read_sysfs_nvme", _read)
        assert ssd.resolve_device(None, cfg) == "/dev/nvme1"


class TestEndToEnd:
    def _nvme(self, ssd, monkeypatch, model="Virtium VTPM24CEXI080-BM110006"):
        monkeypatch.setattr(ssd.syslog, "syslog", lambda *a, **_k: None)
        monkeypatch.setattr(ssd.syslog, "openlog", lambda *a, **_k: None)
        monkeypatch.setattr(ssd, "read_sysfs_nvme", lambda *_a, **_k: (model, "CE00A474"))
        monkeypatch.setattr(ssd, "list_nvme_controllers", lambda *_a, **_k: ["/dev/nvme0"])
        monkeypatch.setattr(ssd, "parse_nvme_name", lambda d: ("nvme0", None))
        monkeypatch.setattr(ssd, "map_device", lambda d, form: "/dev/nvme0")

    def test_missing_tool_writes_status(self, ssd, tmp_path, monkeypatch):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA_missing_tool_xyz"))
        outdir = tmp_path / "out"
        self._nvme(ssd, monkeypatch)
        seen = []

        def _syslog(*a, **_k):
            seen.append(a)

        monkeypatch.setattr(ssd.syslog, "syslog", _syslog)
        monkeypatch.setattr(ssd.syslog, "openlog", lambda *a, **_k: None)
        tar_path = str(tmp_path / "out.tar.gz")
        with open(tar_path, "wb") as f:
            f.write(b"GOOD")
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        assert rc != 0
        assert outdir.is_dir()
        status = (outdir / "ssd-dump-status.log").read_text()
        assert "not found on PATH" in status
        assert "status: warning" in status
        assert (outdir / "ssd-dump-tool.log").is_file()
        with open(tar_path, "rb") as f:
            assert f.read() == b"GOOD"
        warn_text = " ".join(str(c) for c in seen)
        assert "not found on PATH" in warn_text

    def test_explicit_non_nvme_is_warning(self, ssd, tmp_path, monkeypatch):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA_RTK_5766_v2"))
        outdir = tmp_path / "out"
        monkeypatch.setattr(ssd.syslog, "syslog", lambda *a, **_k: None)
        monkeypatch.setattr(ssd.syslog, "openlog", lambda *a, **_k: None)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/sda",
            ]
        )
        status = (outdir / "ssd-dump-status.log").read_text()
        assert rc != 0
        assert "status: warning" in status
        assert "not an NVMe" in status
        assert not (tmp_path / "out.tar.gz").exists()

    def test_not_executable_tool(self, ssd, tmp_path, monkeypatch):
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        tool = bin_dir / "vtFA_RTK_5766_v2"
        tool.write_text("x")
        os.chmod(str(tool), 0o644)
        monkeypatch.setenv("PATH", str(bin_dir))
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA_RTK_5766_v2"))
        outdir = tmp_path / "out"
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        status = (outdir / "ssd-dump-status.log").read_text()
        assert rc != 0
        assert "not executable" in status
        assert str(tool) in status

    def test_unsupported_model_includes_config(self, ssd, tmp_path, monkeypatch):
        cfg = tmp_path / "cfg.json"
        write_json(
            cfg,
            {
                "defaults": {"timeout_sec": 120, "gzip": True, "gzip_level": 5,
                             "min_free_mb": 1},
                "vendors": {"Virtium": {"models": {
                    "NO_SUCH_MODEL": {
                        "tool": "vtFA_RTK_5766_v2",
                        "args": ["{device}"],
                        "device_form": "controller",
                    }
                }}},
            },
        )
        outdir = tmp_path / "out"
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        status = (outdir / "ssd-dump-status.log").read_text()
        log = (outdir / "ssd-dump-tool.log").read_text()
        assert rc != 0
        assert (
            'unsupported SSD model "Virtium VTPM24CEXI080-BM110006"'
            in status
        )
        assert "for the SSD dump tool" in status
        assert "config:" in status
        assert str(cfg.resolve()) in status
        assert "WARNING:" in log

    def test_recreate_drops_old_files(self, ssd, tmp_path, monkeypatch):
        tool = str(tmp_path / "vtFA_RTK_5766_v2")
        fake_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg(tool))
        outdir = tmp_path / "out"
        outdir.mkdir()
        stale = outdir / "stale.bin"
        stale.write_text("old")
        monkeypatch.setattr(ssd, "DEFAULT_OUTDIR", str(outdir))
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        tar_path = str(tmp_path / "out.tar.gz")
        assert rc == 0
        names = tar_names(tar_path)
        assert not any(n.endswith("stale.bin") for n in names)

    def test_no_nvme_skipped_no_syslog(self, ssd, tmp_path, monkeypatch):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA_RTK_5766_v2"))
        outdir = tmp_path / "out"
        monkeypatch.setattr(ssd, "list_nvme_controllers", lambda *_a, **_k: [])
        monkeypatch.setattr(ssd, "free_mb", lambda *_a, **_k: 0)
        seen = []
        monkeypatch.setattr(ssd.syslog, "syslog", lambda *a, **_k: seen.append(a))
        monkeypatch.setattr(ssd.syslog, "openlog", lambda *a, **_k: None)
        rc = ssd.main(["--config", str(cfg), "--outdir", str(outdir)])
        status = (outdir / "ssd-dump-status.log").read_text()
        assert rc == 0
        assert "status: skipped" in status
        assert "not enough free space" not in status
        assert seen == []
        assert not (tmp_path / "out.tar.gz").exists()

    def test_fake_tool_gzip(self, ssd, tmp_path, monkeypatch):
        tool = str(tmp_path / "vtFA_RTK_5766_v2")
        fake_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg(tool))
        outdir = tmp_path / "out"
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        tar_path = str(tmp_path / "out.tar.gz")
        status = tar_text(tar_path, "out/ssd-dump-status.log")
        assert rc == 0, status
        assert "status: ok" in status
        assert "nandlog_64384-1454.bin.gz" in status
        assert not outdir.exists()
        names = tar_names(tar_path)
        assert "out/nandlog_64384-1454.bin.gz" in names
        assert "out/nandlog_64384-1454.bin" not in names
        log = tar_text(tar_path, "out/ssd-dump-tool.log")
        assert "written to file" in log

    def test_vendor_output_not_on_console(self, ssd, tmp_path, monkeypatch, capsys):
        tool = str(tmp_path / "vtFA_RTK_5766_v2")
        fake_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg(tool))
        outdir = tmp_path / "out"
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        assert rc == 0
        captured = capsys.readouterr()
        tar_path = str(tmp_path / "out.tar.gz")
        assert "written to file" not in captured.err
        assert "written to file" not in captured.out
        assert "written to file" in tar_text(tar_path, "out/ssd-dump-tool.log")

    def test_pack_fail_rewrites_status_warning(self, ssd, tmp_path, monkeypatch):
        tool = str(tmp_path / "vtFA_RTK_5766_v2")
        fake_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg(tool))
        outdir = tmp_path / "out"
        tar_path = tmp_path / "out.tar.gz"
        tar_path.write_bytes(b"GOOD")
        self._nvme(ssd, monkeypatch)

        def boom(*_a, **_k):
            raise OSError("pack fail")

        monkeypatch.setattr(ssd, "pack_outdir", boom)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        assert rc != 0
        assert outdir.is_dir()
        status = (outdir / "ssd-dump-status.log").read_text()
        assert "status: warning" in status
        assert "cannot pack outdir" in status
        assert tar_path.read_bytes() == b"GOOD"

    def test_vendor_no_dump_files_is_warning(self, ssd, tmp_path, monkeypatch):
        tool = str(tmp_path / "vtFA_empty")
        with open(tool, "w") as f:
            f.write("#!/bin/sh\necho no nandlog\n")
        os.chmod(tool, os.stat(tool).st_mode | stat.S_IEXEC)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg(tool))
        outdir = tmp_path / "out"
        tar_path = tmp_path / "out.tar.gz"
        tar_path.write_bytes(b"GOOD")
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        assert rc != 0
        assert outdir.is_dir()
        status = (outdir / "ssd-dump-status.log").read_text()
        assert "status: warning" in status
        assert "produced no dump files" in status
        assert tar_path.read_bytes() == b"GOOD"


class TestRunLock:
    def test_second_acquire_fails(self, ssd, tmp_path, monkeypatch):
        monkeypatch.delenv("HW_MGMT_SSD_DUMP_LOCKED", raising=False)
        lock = str(tmp_path / "ssd.lock")
        monkeypatch.setattr(ssd, "LOCK_PATHS", (lock,))
        monkeypatch.setattr(ssd, "LOCK_WAIT_SEC", 0)
        fd = ssd.acquire_run_lock()
        try:
            with pytest.raises(ssd.DumpError, match="another ssd-dump is running"):
                ssd.acquire_run_lock()
        finally:
            ssd.release_run_lock(fd)
        fd2 = ssd.acquire_run_lock()
        ssd.release_run_lock(fd2)
