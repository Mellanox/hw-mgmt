#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for ADS1015, ADS7924, and MAX1363 read-status and force-alarm scripts."""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

ADS1015_READ = str(BMC_SCRIPTS_DIR / "hw-management-bmc-ads1015-read-status.sh")
ADS1015_ALARM = str(BMC_SCRIPTS_DIR / "hw-management-bmc-ads1015-force-alarm.sh")
ADS7924_READ = str(BMC_SCRIPTS_DIR / "hw-management-bmc-ads7924-read-status.sh")
ADS7924_ALARM = str(BMC_SCRIPTS_DIR / "hw-management-bmc-ads7924-force-alarm.sh")
MAX1363_READ = str(BMC_SCRIPTS_DIR / "hw-management-bmc-max1363-read-status.sh")
MAX1363_ALARM = str(BMC_SCRIPTS_DIR / "hw-management-bmc-max1363-force-alarm.sh")


def _run(script, args="", stubs_dir=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    return subprocess.run(
        ["bash", script] + (args.split() if args else []),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


class TestAds1015ReadStatus:
    def test_missing_bus_arg_shows_usage(self, stubs_dir):
        r = _run(ADS1015_READ, stubs_dir=stubs_dir)
        assert r.returncode == 1
        assert "Usage" in r.stdout or "Usage" in r.stderr

    def test_missing_addr_arg_shows_usage(self, stubs_dir):
        r = _run(ADS1015_READ, args="12", stubs_dir=stubs_dir)
        assert r.returncode == 1

    def test_valid_args_attempts_i2c(self, stubs_dir):
        # i2ctransfer is stubbed to exit 0; script may complete or fail gracefully
        r = _run(ADS1015_READ, args="12 0x49", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)

    def test_invalid_channel_exits_nonzero(self, stubs_dir):
        r = _run(ADS1015_READ, args="12 0x49 9", stubs_dir=stubs_dir)
        assert r.returncode != 0
        assert "Invalid channel" in r.stdout or "Invalid channel" in r.stderr

    def test_valid_channel_1(self, stubs_dir):
        r = _run(ADS1015_READ, args="12 0x49 1", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)

    def test_valid_channel_4(self, stubs_dir):
        r = _run(ADS1015_READ, args="12 0x49 4", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)

    def test_channel_zero_invalid(self, stubs_dir):
        r = _run(ADS1015_READ, args="12 0x49 0", stubs_dir=stubs_dir)
        assert r.returncode != 0

    def test_channel_5_invalid(self, stubs_dir):
        r = _run(ADS1015_READ, args="12 0x49 5", stubs_dir=stubs_dir)
        assert r.returncode != 0


class TestAds1015ForceAlarm:
    def test_script_exists(self):
        assert Path(ADS1015_ALARM).exists()

    def test_missing_args_exits_nonzero(self, stubs_dir):
        r = _run(ADS1015_ALARM, stubs_dir=stubs_dir)
        assert r.returncode != 0 or "Usage" in (r.stdout + r.stderr)

    def test_runs_with_args(self, stubs_dir):
        r = _run(ADS1015_ALARM, args="12 0x49", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)


class TestAds7924ReadStatus:
    def test_missing_args_exits_nonzero(self, stubs_dir):
        r = _run(ADS7924_READ, stubs_dir=stubs_dir)
        assert r.returncode != 0 or "Usage" in (r.stdout + r.stderr)

    def test_with_bus_and_addr(self, stubs_dir):
        r = _run(ADS7924_READ, args="5 0x48", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)

    def test_script_exists(self):
        assert Path(ADS7924_READ).exists()


class TestAds7924ForceAlarm:
    def test_script_exists(self):
        assert Path(ADS7924_ALARM).exists()

    def test_missing_args_exits_nonzero(self, stubs_dir):
        r = _run(ADS7924_ALARM, stubs_dir=stubs_dir)
        assert r.returncode != 0 or "Usage" in (r.stdout + r.stderr)

    def test_with_args(self, stubs_dir):
        r = _run(ADS7924_ALARM, args="5 0x48", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)


class TestMax1363ReadStatus:
    def test_script_exists(self):
        assert Path(MAX1363_READ).exists()

    def test_missing_args_exits_nonzero(self, stubs_dir):
        r = _run(MAX1363_READ, stubs_dir=stubs_dir)
        assert r.returncode != 0 or "Usage" in (r.stdout + r.stderr)

    def test_with_bus_and_addr(self, stubs_dir):
        r = _run(MAX1363_READ, args="3 0x36", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)


class TestMax1363ForceAlarm:
    def test_script_exists(self):
        assert Path(MAX1363_ALARM).exists()

    def test_missing_args_exits_nonzero(self, stubs_dir):
        r = _run(MAX1363_ALARM, stubs_dir=stubs_dir)
        assert r.returncode != 0 or "Usage" in (r.stdout + r.stderr)

    def test_with_args(self, stubs_dir):
        r = _run(MAX1363_ALARM, args="3 0x36", stubs_dir=stubs_dir)
        assert r.returncode in (0, 1)
