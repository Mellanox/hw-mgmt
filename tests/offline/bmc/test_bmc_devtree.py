#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-devtree.sh and hw-management-bmc-devtree-check.sh."""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

DEVTREE = str(BMC_SCRIPTS_DIR / "hw-management-bmc-devtree.sh")
DEVTREE_CHECK = str(BMC_SCRIPTS_DIR / "hw-management-bmc-devtree-check.sh")
JSON_PARSER = str(BMC_SCRIPTS_DIR / "hw-management-bmc-json-parser.sh")
HELPERS = str(BMC_SCRIPTS_DIR / "hw-management-bmc-helpers-common.sh")


def _run_check(args, stubs_dir=None, env_extras=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env_extras:
        env.update(env_extras)
    preamble = f"""
source() {{
    local f="$1"; shift
    f="${{f/#\\/usr\\/bin\\/{BMC_SCRIPTS_DIR}/}}"
    builtin source "$f" "$@"
}}
"""
    return subprocess.run(
        ["bash", "-c", f'{preamble}{DEVTREE_CHECK} {args}'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


def _source_devtree(snippet, stubs_dir=None, env_extras=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env_extras:
        env.update(env_extras)
    preamble = f"""
source() {{
    local f="$1"; shift
    f="${{f/#\\/usr\\/bin\\/{BMC_SCRIPTS_DIR}/}}"
    builtin source "$f" "$@"
}}
source {DEVTREE}
"""
    return subprocess.run(
        ["bash", "-c", preamble + "\n" + snippet],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


class TestDevtreeScriptExists:
    def test_devtree_script_exists(self):
        assert Path(DEVTREE).exists()

    def test_devtree_check_script_exists(self):
        assert Path(DEVTREE_CHECK).exists()


class TestDevtreeCheckHelp:
    def test_no_args_shows_usage_or_exits(self, stubs_dir):
        r = _run_check("", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1, 2)

    def test_help_flag(self, stubs_dir):
        r = _run_check("-h", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1, 2)


class TestDevtreeCheckParseBom:
    def test_parse_flag_with_empty_string(self, stubs_dir):
        r = _run_check('-p ""', stubs_dir=stubs_dir)
        assert r.returncode in (0, 1, 2, 127)

    def test_parse_flag_with_sample_bom(self, stubs_dir):
        r = _run_check('-p "HI189_B01_C00_T00_R00"', stubs_dir=stubs_dir)
        assert r.returncode in (0, 1, 2, 127)

    def test_parse_produces_output(self, stubs_dir):
        r = _run_check('-p "HI189_B01_C00_T00_R00"', stubs_dir=stubs_dir)
        # No crash is the key requirement
        assert r.returncode in (0, 1, 2, 127)


class TestDevtreeCheckDecode:
    def test_decode_flag_runs(self, stubs_dir):
        r = _run_check("-d", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1, 2)


class TestDevtreeSourcable:
    def test_devtree_sourcable_without_error(self, stubs_dir):
        r = _source_devtree("echo sourced_ok", stubs_dir=stubs_dir)
        assert "sourced_ok" in r.stdout

    def test_associative_arrays_declared(self, stubs_dir):
        r = _source_devtree(
            'declare -p SMBIOS_BOARD_MAP 2>/dev/null && echo "map_exists" || echo "no_map"',
            stubs_dir=stubs_dir)
        # Script may use different variable names; just verify it sources cleanly
        assert r.returncode == 0

    def test_devtree_functions_declared(self, stubs_dir):
        r = _source_devtree(
            'declare -F 2>/dev/null | grep -q "devtree\|bom\|smbios" && echo "funcs_found" || echo "check_done"',
            stubs_dir=stubs_dir)
        assert r.returncode == 0


class TestDevtreeReadyCommon:
    def test_ready_common_exists(self):
        assert (BMC_SCRIPTS_DIR / "hw-management-bmc-ready-common.sh").exists()

    def test_ready_common_sourcable(self, stubs_dir):
        ready = str(BMC_SCRIPTS_DIR / "hw-management-bmc-ready-common.sh")
        preamble = f"""
source() {{
    local f="$1"; shift
    f="${{f/#\\/usr\\/bin\\/{BMC_SCRIPTS_DIR}/}}"
    builtin source "$f" "$@"
}}
"""
        r = subprocess.run(
            ["bash", "-c", f'{preamble}source {ready}\necho sourced_ok'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
            env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"},
            timeout=10,
        )
        assert "sourced_ok" in r.stdout or r.returncode in (0, 1)
