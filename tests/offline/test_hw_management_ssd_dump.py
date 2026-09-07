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


#SpellCheck-ignoreBlockStart
def phison_cfg(tool):
    return {
        "defaults": {
            "timeout_sec": 120,
            "gzip": True,
            "gzip_level": 5,
            "min_free_mb": 1,
        },
        "vendors": {
            "Phison": {
                "models": {
                    "ESLS080GTUE-A329IJ1-TYJN": {
                        "tool": tool,
                        "args": ["-device_index", "{device}"],
                        "device_form": "namespace",
                        "timeout_sec": 120,
                    }
                }
            }
        },
    }
#SpellCheck-ignoreBlockEnd


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
    os.chmod(path, 0o755)


def fake_phison_tool(path):
    with open(path, "w") as f:
        f.write(
            textwrap.dedent(
                """\
                #!/bin/sh
                echo "Save to RD_Dump2_Header_20260907-125506.bin"
                echo dummy > RD_Dump2_Header_20260907-125506.bin
                echo dummy > RD_Dump2_Data_20260907-125506.bin
                echo "RD Dump Pass"
                """
            )
        )
    os.chmod(path, 0o755)


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

    def test_namespace_default_n1(self, ssd, monkeypatch):
        monkeypatch.setattr(
            ssd, "list_nvme_namespaces", lambda *_a, **_k: ["/dev/nvme0n1"]
        )
        assert ssd.map_device("/dev/nvme0", "namespace") == "/dev/nvme0n1"

    def test_namespace_uses_lowest_if_no_n1(self, ssd, monkeypatch):
        monkeypatch.setattr(
            ssd, "list_nvme_namespaces", lambda *_a, **_k: ["/dev/nvme0n2"]
        )
        assert ssd.map_device("/dev/nvme0", "namespace") == "/dev/nvme0n2"

    def test_namespace_missing_is_error(self, ssd, monkeypatch):
        monkeypatch.setattr(ssd, "list_nvme_namespaces", lambda *_a, **_k: [])
        with pytest.raises(ssd.DumpError, match="namespace not found"):
            ssd.map_device("/dev/nvme0", "namespace")

    def test_namespace_keeps_n1(self, ssd):
        assert ssd.map_device("/dev/nvme0n1", "namespace") == "/dev/nvme0n1"

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

    #SpellCheck-ignoreBlockStart
    def test_phison_exact_key(self, ssd):
        cfg = phison_cfg("PCIETOOL")
        v, k, m = ssd.find_model_config(cfg, "ESLS080GTUE-A329IJ1-TYJN")
        assert v == "Phison" and k == "ESLS080GTUE-A329IJ1-TYJN"
        assert m["device_form"] == "namespace"
        assert m["args"] == ["-device_index", "{device}"]

    def test_shipped_json_has_phison_and_virtium(self, ssd):
        path = os.path.join(
            os.path.dirname(__file__),
            "..",
            "..",
            "usr",
            "etc",
            "hw-management-ssd",
            "ssd-dump-config.json",
        )
        cfg = ssd.load_config(path)
        v, k, m = ssd.find_model_config(cfg, "ESLS080GTUE-A329IJ1-TYJN")
        assert v == "Phison" and k == "ESLS080GTUE-A329IJ1-TYJN"
        assert m["device_form"] == "namespace"
        assert m["timeout_sec"] == 120
        v2, k2, m2 = ssd.find_model_config(
            cfg, "Virtium VTPM24CEXI080-BM110006"
        )
        assert v2 == "Virtium" and k2 == "VTPM24CEXI080-BM110006"
        assert m2["device_form"] == "controller"
    #SpellCheck-ignoreBlockEnd


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


class TestStatusFormat:
    def test_ok_omits_warning_ends_with_status(self, ssd):
        text = ssd.format_status_fields({"status": "ok", "warning": "", "part": "X"})
        assert "warning:" not in text
        assert text.strip().endswith("Status: Ok / succeeded")

    def test_skipped_ends_with_status_skipped(self, ssd):
        text = ssd.format_status_fields({"status": "skipped", "warning": ""})
        assert "warning:" not in text
        assert text.strip().endswith("Status: skipped")
        assert ssd.completion_message({"status": "skipped"}) == (
            "SSD dump tool skipped"
        )

    def test_error_keeps_warning_ends_with_status(self, ssd):
        text = ssd.format_status_fields(
            {"status": "warning", "warning": "tool missing"}
        )
        assert "warning: tool missing" in text
        assert text.strip().endswith("Status: error")


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

    def test_refuses_dir_symlink(self, ssd, tmp_path):
        real = tmp_path / "real"
        real.mkdir()
        link = tmp_path / "link"
        os.symlink(str(real), str(link))
        with pytest.raises(ssd.DumpError, match="symlink"):
            ssd.check_outdir(str(link))
        assert real.is_dir()

    def test_refuses_symlink_ancestor(self, ssd, tmp_path):
        real = tmp_path / "real"
        real.mkdir()
        link = tmp_path / "link"
        os.symlink(str(real), str(link))
        nested = link / "ssd-dump"
        with pytest.raises(ssd.DumpError, match="symlink component"):
            ssd.check_outdir(str(nested))
        assert real.is_dir()
        assert not (real / "ssd-dump").exists()


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

    def test_replace_ok_rmtree_fail_keeps_new_tar(self, ssd, tmp_path, monkeypatch):
        outdir = tmp_path / "out"
        outdir.mkdir()
        (outdir / "f.bin").write_text("x")
        tar_path = tmp_path / "out.tar.gz"
        tar_path.write_bytes(b"OLD")

        def boom(_path):
            raise OSError("rmtree fail")

        monkeypatch.setattr(ssd.shutil, "rmtree", boom)
        got = ssd.pack_outdir(str(outdir))
        assert got == str(tar_path)
        assert tar_path.read_bytes() != b"OLD"
        assert outdir.is_dir()


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


def _dev_stat(mode):
    return os.stat_result((mode, 0, 0, 0, 0, 0, 0, 0, 0, 0))


def _stub_lstat_dev(ssd, monkeypatch, path, mode, extra=None, missing=None):
    real_lstat = ssd.os.lstat
    nodes = {os.path.abspath(path): mode}
    if extra:
        for p, m in extra.items():
            nodes[os.path.abspath(p)] = m
    missing_set = set()
    if missing:
        for p in missing:
            missing_set.add(os.path.abspath(p))

    def _lstat(p):
        ap = os.path.abspath(p)
        if ap in missing_set:
            raise OSError(2, "No such file or directory", p)
        if ap in nodes:
            return _dev_stat(nodes[ap])
        return real_lstat(p)

    monkeypatch.setattr(ssd.os, "lstat", _lstat)


class TestResolveDevice:
    def test_explicit_non_nvme_is_error(self, ssd):
        with pytest.raises(ssd.DumpError, match="not an NVMe"):
            ssd.resolve_device("/dev/sda", virtium_cfg("t"))

    def test_explicit_outside_dev_is_error(self, ssd, tmp_path):
        fake = tmp_path / "nvme0"
        fake.write_text("")
        with pytest.raises(ssd.DumpError, match="not an NVMe"):
            ssd.resolve_device(str(fake), virtium_cfg("t"))

    def test_explicit_missing_node_is_error(self, ssd):
        missing = "/dev/nvme999n999"
        with pytest.raises(ssd.DumpError, match="not found"):
            ssd.resolve_device(missing, virtium_cfg("t"))

    def test_explicit_regular_file_is_error(self, ssd, monkeypatch):
        _stub_lstat_dev(ssd, monkeypatch, "/dev/nvme0", stat.S_IFREG | 0o644)
        with pytest.raises(ssd.DumpError, match="device node"):
            ssd.resolve_device("/dev/nvme0", virtium_cfg("t"))

    def test_explicit_symlink_is_error(self, ssd, monkeypatch):
        _stub_lstat_dev(ssd, monkeypatch, "/dev/nvme0", stat.S_IFLNK | 0o777)
        with pytest.raises(ssd.DumpError, match="symlink"):
            ssd.resolve_device("/dev/nvme0", virtium_cfg("t"))

    def test_explicit_chr_node_ok(self, ssd, monkeypatch):
        _stub_lstat_dev(ssd, monkeypatch, "/dev/nvme0", stat.S_IFCHR | 0o600)
        assert ssd.resolve_device("/dev/nvme0", virtium_cfg("t")) == "/dev/nvme0"

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
        _stub_lstat_dev(ssd, monkeypatch, "/dev/nvme0", stat.S_IFCHR | 0o600)

    def test_verify_ok_does_not_write_dumps(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        tool = str(tmp_path / "vtFA_RTK_5766_v2")
        fake_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg(tool))
        outdir = tmp_path / "out"
        outdir.mkdir()
        stale = outdir / "stale.bin"
        stale.write_text("keep")
        monkeypatch.setattr(ssd, "DEFAULT_OUTDIR", str(outdir))
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--verify",
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        out = capsys.readouterr().out
        assert rc == 0
        assert "status: ok" in out
        assert "verify: yes" in out
        assert stale.read_text() == "keep"
        assert not (tmp_path / "out.tar.gz").exists()
        assert not (outdir / "ssd-dump-status.log").exists()

    def test_verify_quiet_hides_stdout(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        tool = str(tmp_path / "vtFA_RTK_5766_v2")
        fake_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg(tool))
        outdir = tmp_path / "out"
        outdir.mkdir()
        monkeypatch.setattr(ssd, "DEFAULT_OUTDIR", str(outdir))
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--verify",
                "--quiet",
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        captured = capsys.readouterr()
        assert rc == 0
        assert captured.out == ""
        assert "SSD dump tool started" in captured.err
        assert "SSD dump tool succeeded" in captured.err

    def test_verify_refuses_dir_symlink(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA"))
        real = tmp_path / "real"
        real.mkdir()
        link = tmp_path / "link"
        os.symlink(str(real), str(link))
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--verify",
                "--config",
                str(cfg),
                "--outdir",
                str(link),
                "--device",
                "/dev/nvme0",
            ]
        )
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "symlink" in text
        assert real.is_dir()

    def test_verify_refuses_symlink_ancestor(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA"))
        real = tmp_path / "real"
        real.mkdir()
        link = tmp_path / "link"
        os.symlink(str(real), str(link))
        nested = link / "ssd-dump"
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--verify",
                "--config",
                str(cfg),
                "--outdir",
                str(nested),
                "--device",
                "/dev/nvme0",
            ]
        )
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "symlink component" in text
        assert not (real / "ssd-dump").exists()

    def test_verify_refuses_nonempty_custom(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA"))
        outdir = tmp_path / "custom"
        outdir.mkdir()
        keep = outdir / "keep.bin"
        keep.write_text("x")
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--verify",
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "non-empty directory" in text
        assert keep.read_text() == "x"

    def test_verify_missing_tool_no_outdir(self, ssd, tmp_path, monkeypatch, capsys):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA_missing_tool_xyz"))
        outdir = tmp_path / "out"
        self._nvme(ssd, monkeypatch)
        rc = ssd.main(
            [
                "--verify",
                "--config",
                str(cfg),
                "--outdir",
                str(outdir),
                "--device",
                "/dev/nvme0",
            ]
        )
        err = capsys.readouterr().err
        assert rc != 0
        assert "SSD dump tool started" in err
        assert "SSD dump tool failed:" in err
        assert "not found on PATH" in err
        assert "WARNING:" not in err
        assert not outdir.exists()

    def test_verify_no_nvme_skipped(self, ssd, tmp_path, monkeypatch, capsys):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, virtium_cfg("vtFA_RTK_5766_v2"))
        monkeypatch.setattr(ssd, "list_nvme_controllers", lambda *_a, **_k: [])
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        captured = capsys.readouterr()
        assert rc == 0
        assert "status: skipped" in captured.out
        assert "SSD dump tool skipped" in captured.err

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
        assert "Status: error" in status
        assert any(ln.startswith("warning:") for ln in status.splitlines())
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

    def test_invalid_json_config_is_warning_not_internal(
        self, ssd, tmp_path, monkeypatch
    ):
        cfg = tmp_path / "cfg.json"
        cfg.write_text("{")
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
        assert "status: warning" in status
        assert "invalid config" in status
        assert "internal:" not in status

    def test_defaults_array_is_config_warning_not_internal(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        write_json(cfg, {"defaults": [], "vendors": {}})
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        out = capsys.readouterr()
        text = out.out + out.err
        assert rc != 0
        assert "invalid config" in text
        assert "defaults is not an object" in text
        assert "internal:" not in text

    def test_timeout_zero_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["defaults"]["timeout_sec"] = 0
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "invalid config" in text
        assert "timeout_sec" in text

    def test_timeout_over_json_max_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["defaults"]["timeout_sec"] = ssd.TIMEOUT_SEC_JSON_MAX + 1
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "invalid config" in text
        assert "timeout_sec" in text

    def test_missing_tool_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        del obj["vendors"]["Virtium"]["models"]["VTPM24CEXI080-BM110006"]["tool"]
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "invalid config" in text
        assert "tool" in text

    def test_missing_args_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        del obj["vendors"]["Virtium"]["models"]["VTPM24CEXI080-BM110006"]["args"]
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "invalid config" in text
        assert "args" in text

    def test_args_null_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["vendors"]["Virtium"]["models"]["VTPM24CEXI080-BM110006"]["args"] = None
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "invalid config" in text
        assert "args" in text

    def test_bad_device_form_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["vendors"]["Virtium"]["models"]["VTPM24CEXI080-BM110006"][
            "device_form"
        ] = "disk"
        write_json(cfg, obj)
        monkeypatch.setattr(ssd, "list_nvme_controllers", lambda *_a, **_k: [])
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "status: skipped" not in text
        assert "invalid config" in text
        assert "device_form" in text

    def test_gzip_level_10_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["defaults"]["gzip_level"] = 10
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "gzip_level" in text

    def test_args_string_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["vendors"]["Virtium"]["models"]["VTPM24CEXI080-BM110006"][
            "args"
        ] = "{device}"
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "invalid config" in text
        assert "args" in text

    def test_gzip_string_false_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["defaults"]["gzip"] = "false"
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "defaults.gzip" in text

    def test_timeout_bool_rejected_by_verify(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        cfg = tmp_path / "cfg.json"
        obj = virtium_cfg("vtFA")
        obj["defaults"]["timeout_sec"] = True
        write_json(cfg, obj)
        rc = ssd.main(["--verify", "--config", str(cfg), "--outdir", str(tmp_path / "out")])
        text = "".join(capsys.readouterr())
        assert rc != 0
        assert "timeout_sec" in text

    def test_cli_timeout_zero_rejected(self, ssd):
        with pytest.raises(SystemExit):
            ssd.parse_args(["--timeout", "0"])

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
        assert "Status: skipped" in status
        assert not any(ln.startswith("warning:") for ln in status.splitlines())
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
        assert "Status: Ok / succeeded" in status
        assert not any(ln.startswith("warning:") for ln in status.splitlines())
        assert "nandlog_64384-1454.bin.gz" in status
        assert not outdir.exists()
        names = tar_names(tar_path)
        assert "out/nandlog_64384-1454.bin.gz" in names
        assert "out/nandlog_64384-1454.bin" not in names
        log = tar_text(tar_path, "out/ssd-dump-tool.log")
        assert "SSD dump tool started" in log
        assert "SSD dump tool succeeded" in log
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
        assert "SSD dump tool started" in captured.err
        assert "SSD dump tool succeeded" in captured.err
        assert "written to file" not in captured.err
        assert "written to file" not in captured.out
        assert "written to file" in tar_text(tar_path, "out/ssd-dump-tool.log")

    #SpellCheck-ignoreBlockStart
    def test_phison_namespace_device_index(self, ssd, tmp_path, monkeypatch):
        tool = str(
            tmp_path / "PCIETOOL08-6130_RD_Dump2_(Nvidia)_Linux_64bit_v2"
        )
        fake_phison_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, phison_cfg(tool))
        outdir = tmp_path / "out"
        monkeypatch.setattr(ssd.syslog, "syslog", lambda *a, **_k: None)
        monkeypatch.setattr(ssd.syslog, "openlog", lambda *a, **_k: None)
        monkeypatch.setattr(
            ssd,
            "read_sysfs_nvme",
            lambda *_a, **_k: ("ESLS080GTUE-A329IJ1-TYJN", "ETFIP0T6"),
        )
        monkeypatch.setattr(
            ssd, "list_nvme_namespaces", lambda *_a, **_k: ["/dev/nvme0n1"]
        )
        _stub_lstat_dev(
            ssd,
            monkeypatch,
            "/dev/nvme0",
            stat.S_IFCHR | 0o600,
            extra={"/dev/nvme0n1": stat.S_IFBLK | 0o660},
        )
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
        assert "device: /dev/nvme0n1" in status
        assert "device_form: namespace" in status
        assert "-device_index" in status
        names = tar_names(tar_path)
        assert "out/RD_Dump2_Header_20260907-125506.bin.gz" in names
        assert "out/RD_Dump2_Data_20260907-125506.bin.gz" in names
    #SpellCheck-ignoreBlockEnd

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
        assert "Status: error" in status
        assert "cannot pack outdir" in status
        assert tar_path.read_bytes() == b"GOOD"
        log = (outdir / "ssd-dump-tool.log").read_text()
        assert "SSD dump tool succeeded" not in log
        assert "SSD dump tool failed: cannot pack outdir" in log

    #SpellCheck-ignoreBlockStart
    def test_phison_missing_namespace_is_warning(
        self, ssd, tmp_path, monkeypatch, capsys
    ):
        tool = str(
            tmp_path / "PCIETOOL08-6130_RD_Dump2_(Nvidia)_Linux_64bit_v2"
        )
        fake_phison_tool(tool)
        cfg = tmp_path / "cfg.json"
        write_json(cfg, phison_cfg(tool))
        outdir = tmp_path / "out"
        monkeypatch.setattr(ssd.syslog, "syslog", lambda *a, **_k: None)
        monkeypatch.setattr(ssd.syslog, "openlog", lambda *a, **_k: None)
        monkeypatch.setattr(
            ssd,
            "read_sysfs_nvme",
            lambda *_a, **_k: ("ESLS080GTUE-A329IJ1-TYJN", "ETFIP0T6"),
        )
        monkeypatch.setattr(
            ssd, "list_nvme_namespaces", lambda *_a, **_k: ["/dev/nvme0n1"]
        )
        _stub_lstat_dev(
            ssd,
            monkeypatch,
            "/dev/nvme0",
            stat.S_IFCHR | 0o600,
            missing=["/dev/nvme0n1"],
        )
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
        captured = capsys.readouterr()
        assert rc != 0
        status = (outdir / "ssd-dump-status.log").read_text()
        assert "status: warning" in status
        assert "NVMe device not found: /dev/nvme0n1" in status
        assert (
            "SSD dump tool failed: NVMe device not found: /dev/nvme0n1"
            in captured.err
        )
    #SpellCheck-ignoreBlockEnd

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
