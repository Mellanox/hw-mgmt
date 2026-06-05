#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Shared fixtures for BMC offline tests."""

import os
import stat
import subprocess
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).parent.parent.parent.absolute()
PROJECT_ROOT = TESTS_DIR.parent
BMC_SCRIPTS_DIR = PROJECT_ROOT / "bmc" / "usr" / "usr" / "bin"

# Commands that need no-op stubs on the dev host
_STUB_CMDS = [
    "logger", "systemctl", "systemd-cat", "systemd-analyze",
    "i2ctransfer", "i2cset", "i2cget", "i2cdetect",
    "gpioset", "gpioget",
    "fw_printenv", "fw_setenv",
    "devmem",
    "ethtool", "mdio", "networkctl", "udhcpc",
    "modprobe",
    "hexdump",
]


@pytest.fixture
def bmc_scripts_dir():
    return BMC_SCRIPTS_DIR


@pytest.fixture
def stubs_dir(tmp_path):
    """Temp dir with no-op stubs for hardware commands."""
    sd = tmp_path / "stubs"
    sd.mkdir()
    for cmd in _STUB_CMDS:
        p = sd / cmd
        p.write_text("#!/bin/sh\nexit 0\n")
        p.chmod(p.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return sd


@pytest.fixture
def shell_run(stubs_dir):
    """
    Return a callable run(snippet, env=None) that executes a bash snippet with:
    - stub commands in PATH
    - source /usr/bin/hw-management-bmc-* redirected to repo bmc scripts
    """
    bmc_dir = str(BMC_SCRIPTS_DIR)

    preamble = f"""
_BMC_SCRIPTS="{bmc_dir}"
_orig_source() {{ builtin source "$@"; }}
source() {{
    local _f="$1"; shift
    _f="${{_f/#\\/usr\\/bin\\/$_BMC_SCRIPTS/}}"
    builtin source "$_f" "$@"
}}
. () {{
    source "$@"
}}
"""

    def run(snippet, env=None):
        merged_env = {**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"}
        if env:
            merged_env.update(env)
        full = preamble + "\n" + snippet
        return subprocess.run(
            ["bash", "-c", full],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
            env=merged_env,
        )
    return run


@pytest.fixture
def fake_hw_management(tmp_path):
    """Simulated /var/run/hw-management tree."""
    base = tmp_path / "hw-management"
    for d in ["system", "thermal", "eeprom", "leakage", "config", "bmc", "bmc/domains"]:
        (base / d).mkdir(parents=True, exist_ok=True)
    return base


@pytest.fixture
def fake_gpio_sysfs(tmp_path):
    """Fake /sys/class/gpio tree with configurable chips."""
    gpio_root = tmp_path / "sys" / "class" / "gpio"
    gpio_root.mkdir(parents=True)

    def add_chip(name, ngpio, base):
        chip_dir = gpio_root / name
        chip_dir.mkdir()
        (chip_dir / "ngpio").write_text(str(ngpio) + "\n")
        (chip_dir / "base").write_text(str(base) + "\n")
        return chip_dir

    return gpio_root, add_chip
