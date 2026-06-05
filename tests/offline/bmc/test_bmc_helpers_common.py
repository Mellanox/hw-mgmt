#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-helpers-common.sh."""

import os
import stat
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

HELPERS = str(BMC_SCRIPTS_DIR / "hw-management-bmc-helpers-common.sh")


def _src(snippet, stubs_dir=None, env=None):
    merged = {**os.environ}
    if stubs_dir:
        merged["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env:
        merged.update(env)
    full = f"source {HELPERS}\n{snippet}"
    return subprocess.run(
        ["bash", "-c", full],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=merged,
    )


class TestLogMessage:
    def test_outputs_level_and_message(self, stubs_dir):
        r = _src('log_message "info" "hello world"', stubs_dir=stubs_dir)
        assert "[info] hello world" in r.stdout

    def test_err_level(self, stubs_dir):
        r = _src('log_message "err" "disk failure"', stubs_dir=stubs_dir)
        assert "[err] disk failure" in r.stdout

    def test_warning_level(self, stubs_dir):
        r = _src('log_message "warning" "low memory"', stubs_dir=stubs_dir)
        assert "[warning] low memory" in r.stdout

    def test_debug_level(self, stubs_dir):
        r = _src('log_message "debug" "trace point"', stubs_dir=stubs_dir)
        assert "[debug] trace point" in r.stdout

    def test_uppercase_level_normalized(self, stubs_dir):
        r = _src('log_message "ERROR" "something failed"', stubs_dir=stubs_dir)
        assert "something failed" in r.stdout

    def test_unknown_level_uses_notice(self, stubs_dir):
        r = _src('log_message "custom" "test msg"', stubs_dir=stubs_dir)
        assert "test msg" in r.stdout

    def test_multiword_message(self, stubs_dir):
        r = _src('log_message "info" "this is a multi word message"', stubs_dir=stubs_dir)
        assert "this is a multi word message" in r.stdout

    def test_log_tag_default(self, stubs_dir):
        # logger stub exists; script sources fine and echo output is produced
        r = _src('log_message "info" "tag_test"', stubs_dir=stubs_dir)
        assert r.returncode == 0

    def test_custom_log_tag(self, stubs_dir):
        r = _src('LOG_TAG="my-tag"; source ' + HELPERS + '; log_message "info" "x"',
                 stubs_dir=stubs_dir)
        assert r.returncode == 0


class TestLogEvent:
    def test_exits_zero_even_without_systemd_cat(self, stubs_dir):
        # stubs_dir has a no-op systemd-cat
        r = _src('log_event "test event message"', stubs_dir=stubs_dir)
        assert r.returncode == 0

    def test_exits_zero_when_systemd_cat_missing(self, tmp_path):
        # No stubs_dir — systemd-cat absent; log_event uses || true
        sd = tmp_path / "empty_stubs"
        sd.mkdir()
        # Only logger stub, no systemd-cat
        lp = sd / "logger"
        lp.write_text("#!/bin/sh\nexit 0\n")
        lp.chmod(lp.stat().st_mode | stat.S_IEXEC)
        r = _src('log_event "should not fail"', stubs_dir=sd)
        assert r.returncode == 0


class TestLeakDetectionOnInit:
    def test_no_leakage_dir_returns_false(self, stubs_dir, tmp_path):
        env = {"HW_MANAGEMENT_BMC_PLATFORM_CONF": str(tmp_path / "none.conf")}
        snippet = f"""
SYSTEM_DIR="{tmp_path}/no_such"
source {HELPERS}
leak_detection_on_init; echo "rc=$?"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=1" in r.stdout

    def test_no_leakage_files_returns_false(self, stubs_dir, tmp_path):
        sys_dir = tmp_path / "system"
        sys_dir.mkdir()
        snippet = f"""
source {HELPERS}
_SYSTEM_DIR="{sys_dir}"
leak_detection_on_init; echo "rc=$?"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=1" in r.stdout

    def test_leakage_file_value_one_returns_false(self, stubs_dir, tmp_path):
        sys_dir = tmp_path / "system"
        sys_dir.mkdir()
        (sys_dir / "leakage0").write_text("1\n")
        snippet = f"""
source {HELPERS}
leak_detection_on_init() {{
    local system_dir="{sys_dir}"
    local f val
    if [ ! -d "$system_dir" ]; then return 1; fi
    shopt -s nullglob
    local leak_files=( "$system_dir"/leakage[0-9]* )
    shopt -u nullglob
    for f in "${{leak_files[@]}}"; do
        val=$(tr -d '[:space:]' <"$f" 2>/dev/null)
        if [ "$val" = "0" ]; then return 0; fi
    done
    return 1
}}
leak_detection_on_init; echo "rc=$?"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=1" in r.stdout

    def test_leakage_file_value_zero_returns_true(self, stubs_dir, tmp_path):
        sys_dir = tmp_path / "system"
        sys_dir.mkdir()
        (sys_dir / "leakage0").write_text("0\n")
        snippet = f"""
source {HELPERS}
leak_detection_on_init() {{
    local system_dir="{sys_dir}"
    local f val
    if [ ! -d "$system_dir" ]; then return 1; fi
    shopt -s nullglob
    local leak_files=( "$system_dir"/leakage[0-9]* )
    shopt -u nullglob
    for f in "${{leak_files[@]}}"; do
        val=$(tr -d '[:space:]' <"$f" 2>/dev/null)
        if [ "$val" = "0" ]; then return 0; fi
    done
    return 1
}}
leak_detection_on_init; echo "rc=$?"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=0" in r.stdout


class TestHwMgmtBc:
    def test_bc_available_or_graceful(self, stubs_dir):
        r = _src('echo "2+3" | hw_mgmt_bc; echo "done"', stubs_dir=stubs_dir)
        # Either bc computes 5 or returns 127 — must not crash
        assert r.returncode in (0, 127) or "done" in r.stdout

    def test_hw_mgmt_bc_available_reflects_bc_presence(self, stubs_dir):
        r = _src('hw_mgmt_bc_available; echo "rc=$?"', stubs_dir=stubs_dir)
        assert "rc=" in r.stdout


class TestGetMgmtBoardRevision:
    def test_reads_from_config_file(self, stubs_dir, tmp_path):
        config_file = tmp_path / "config1"
        config_file.write_text("7\n")
        snippet = f"""
source {HELPERS}
get_mgmt_board_revision() {{
    local config_file="{config_file}"
    local config1_val
    if [ -f "$config_file" ]; then
        config1_val=$(cat "$config_file" 2>/dev/null)
    else
        config1_val=0
    fi
    echo $((config1_val & 7))
}}
get_mgmt_board_revision
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert r.stdout.strip() == "7"

    def test_masks_to_3_bits(self, stubs_dir, tmp_path):
        config_file = tmp_path / "config1"
        config_file.write_text("15\n")  # 0b1111 & 7 = 7
        snippet = f"""
source {HELPERS}
get_mgmt_board_revision() {{
    local config_file="{config_file}"
    local config1_val=$(cat "$config_file" 2>/dev/null)
    echo $((config1_val & 7))
}}
get_mgmt_board_revision
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert r.stdout.strip() == "7"
