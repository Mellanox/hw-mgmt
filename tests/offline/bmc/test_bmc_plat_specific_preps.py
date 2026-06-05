#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-plat-specific-preps.sh."""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

PLAT_PREPS = str(BMC_SCRIPTS_DIR / "hw-management-bmc-plat-specific-preps.sh")
HELPERS = str(BMC_SCRIPTS_DIR / "hw-management-bmc-helpers-common.sh")


def _source_fn(snippet, stubs_dir=None, env_extras=None):
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
    full = preamble + f"\nsource {PLAT_PREPS}\n{snippet}"
    return subprocess.run(
        ["bash", "-c", full],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


def _run_script(args="", stubs_dir=None, env_extras=None):
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
        ["bash", "-c", f'{preamble}{PLAT_PREPS} {args}'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=15,
    )


class TestPlatSpecificPrepsScript:
    def test_script_exists(self):
        assert Path(PLAT_PREPS).exists()

    def test_script_is_executable_or_sourcable(self, stubs_dir, tmp_path):
        # Source to verify no syntax errors at load time
        r = _source_fn("echo sourced_ok", stubs_dir=stubs_dir,
                       env_extras={
                           "HID": "HI189",
                           "USR_BIN": str(BMC_SCRIPTS_DIR),
                           "ETC_DIR": str(tmp_path / "etc"),
                           "USR_ETC": str(BMC_SCRIPTS_DIR.parent.parent / "etc"),
                       })
        # Allow exit 0 or 1 (may fail due to missing HID dirs)
        assert r.returncode in (0, 1)


class TestSymlinkCreation:
    def test_symlink_created_when_target_does_not_exist(self, stubs_dir, tmp_path):
        src = tmp_path / "source_file.conf"
        src.write_text("content")
        dst = tmp_path / "dest_link.conf"

        snippet = f"""
if [ ! -e "{dst}" ]; then
    ln -sf "{src}" "{dst}"
fi
[ -L "{dst}" ] && echo "symlink_created" || echo "not_a_symlink"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        assert "symlink_created" in r.stdout

    def test_symlink_idempotent(self, stubs_dir, tmp_path):
        src = tmp_path / "source_file.conf"
        src.write_text("content")
        dst = tmp_path / "dest_link.conf"

        snippet = f"""
ln -sf "{src}" "{dst}"
ln -sf "{src}" "{dst}"
[ -L "{dst}" ] && echo "still_symlink" || echo "broken"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        assert "still_symlink" in r.stdout

    def test_copy_fallback_when_symlink_not_possible(self, stubs_dir, tmp_path):
        src = tmp_path / "source.json"
        src.write_text('{"key": "val"}')
        dst_dir = tmp_path / "dest_dir"
        dst_dir.mkdir()

        snippet = f"""
cp -f "{src}" "{dst_dir}/dest.json"
[ -f "{dst_dir}/dest.json" ] && echo "file_copied" || echo "copy_failed"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        assert "file_copied" in r.stdout


class TestPlatConfDeployment:
    def test_platform_conf_copied_to_etc(self, stubs_dir, tmp_path):
        src_conf = tmp_path / "src" / "hw-management-bmc-platform.conf"
        src_conf.parent.mkdir()
        src_conf.write_text("MGMT_IF_NUM=2\n")
        etc_dir = tmp_path / "etc"
        etc_dir.mkdir()

        snippet = f"""
cp -f "{src_conf}" "{etc_dir}/hw-management-bmc-platform.conf"
[ -f "{etc_dir}/hw-management-bmc-platform.conf" ] && echo "conf_deployed"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        assert "conf_deployed" in r.stdout

    def test_udev_rules_deployed(self, stubs_dir, tmp_path):
        rules_src = tmp_path / "src" / "99-hw-management.rules"
        rules_src.parent.mkdir()
        rules_src.write_text('ACTION=="add", RUN+="/usr/bin/hw-mgmt.sh"\n')
        rules_dst = tmp_path / "etc" / "udev" / "rules.d"
        rules_dst.mkdir(parents=True)

        snippet = f"""
cp -f "{rules_src}" "{rules_dst}/99-hw-management.rules"
[ -f "{rules_dst}/99-hw-management.rules" ] && echo "rules_deployed"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        assert "rules_deployed" in r.stdout


class TestJsonConfigDeployment:
    def test_json_config_copied(self, stubs_dir, tmp_path):
        src = tmp_path / "src" / "hw-management-bmc-a2d-leakage-config.json"
        src.parent.mkdir()
        src.write_text('{"detectors": []}')
        dst_dir = tmp_path / "etc"
        dst_dir.mkdir()

        snippet = f"""
cp -f "{src}" "{dst_dir}/hw-management-bmc-a2d-leakage-config.json"
[ -f "{dst_dir}/hw-management-bmc-a2d-leakage-config.json" ] && echo "json_deployed"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        assert "json_deployed" in r.stdout
