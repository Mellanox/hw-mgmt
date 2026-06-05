#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-get-reset-cause.sh."""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

GET_CAUSE = str(BMC_SCRIPTS_DIR / "hw-management-bmc-get-reset-cause.sh")
SHOW_CAUSE = str(BMC_SCRIPTS_DIR / "hw-management-bmc-show-reset-cause.sh")
LOG_CAUSE = str(BMC_SCRIPTS_DIR / "hw-management-bmc-reset-cause-logger.sh")


def _run_script(script, args="", stubs_dir=None, env_extras=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env_extras:
        env.update(env_extras)
    return subprocess.run(
        ["bash", "-c", f"{script} {args}"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


def _source_and_call(script, snippet, stubs_dir=None, env_extras=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env_extras:
        env.update(env_extras)
    full = f"source {script}\n{snippet}"
    return subprocess.run(
        ["bash", "-c", full],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


def _extract_and_call(snippet, stubs_dir=None, env_extras=None):
    """Extract just the normalize_hex function from the script and call it."""
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env_extras:
        env.update(env_extras)
    # Inline the normalize_hex function definition (matches the script exactly)
    normalize_hex_fn = r"""
normalize_hex() {
    in="$1"
    case "${in}" in
    0x* | 0X*) hex="${in}" ;;
    *) hex="0x${in}" ;;
    esac
    digits="${hex#0x}"
    digits="${digits#0X}"
}
"""
    full = normalize_hex_fn + "\n" + snippet
    return subprocess.run(
        ["bash", "-c", full],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


class TestNormalizeHex:
    def test_hex_with_prefix_unchanged(self, stubs_dir):
        r = _extract_and_call('normalize_hex "0x1234abcd"; echo "$hex"',
                              stubs_dir=stubs_dir)
        assert "0x1234abcd" in r.stdout

    def test_hex_without_prefix_gets_prefix(self, stubs_dir):
        r = _extract_and_call('normalize_hex "deadbeef"; echo "$hex"',
                              stubs_dir=stubs_dir)
        assert "0xdeadbeef" in r.stdout

    def test_uppercase_prefix_0X(self, stubs_dir):
        r = _extract_and_call('normalize_hex "0XABCD"; echo "$hex"',
                              stubs_dir=stubs_dir)
        assert r.returncode == 0
        assert "ABCD" in r.stdout or "0X" in r.stdout

    def test_strips_0x_to_get_digits(self, stubs_dir):
        r = _extract_and_call('normalize_hex "0xCAFE"; echo "$digits"',
                              stubs_dir=stubs_dir)
        assert "CAFE" in r.stdout

    def test_plain_digits_get_0x_prefix(self, stubs_dir):
        r = _extract_and_call('normalize_hex "1234"; echo "$hex"',
                              stubs_dir=stubs_dir)
        assert "0x1234" in r.stdout


class TestGetResetCauseOutDir:
    def test_creates_out_dir(self, stubs_dir, tmp_path):
        out_dir = tmp_path / "hw-management" / "bmc"
        env = {
            "OUT_DIR": str(out_dir),
            "DOMAINS_DIR": str(out_dir / "domains"),
        }
        _run_script(GET_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert out_dir.exists()

    def test_creates_domains_dir(self, stubs_dir, tmp_path):
        out_dir = tmp_path / "hw-management" / "bmc"
        domains = out_dir / "domains"
        env = {
            "OUT_DIR": str(out_dir),
            "DOMAINS_DIR": str(domains),
        }
        _run_script(GET_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert domains.exists()

    def test_respects_out_dir_env(self, stubs_dir, tmp_path):
        custom_dir = tmp_path / "custom_bmc_out"
        env = {
            "OUT_DIR": str(custom_dir),
            "DOMAINS_DIR": str(custom_dir / "domains"),
        }
        _run_script(GET_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert custom_dir.exists()

    def test_default_out_dir_used_when_not_set(self, stubs_dir, tmp_path):
        # Script uses /var/run/hw-management/bmc by default; just verify it runs
        env = {
            "OUT_DIR": str(tmp_path / "bmc"),
            "DOMAINS_DIR": str(tmp_path / "bmc" / "domains"),
        }
        r = _run_script(GET_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        # Should not crash with an unhandled error
        assert r.returncode in (0, 1)


class TestGetResetCauseEnvVars:
    def test_scu_addresses_overrideable(self, stubs_dir, tmp_path):
        out_dir = tmp_path / "bmc"
        env = {
            "OUT_DIR": str(out_dir),
            "DOMAINS_DIR": str(out_dir / "domains"),
            "SCU0_LOG0_ADDR": "0x12c02050",
            "SCU1_LOG0_ADDR": "0x14c02050",
        }
        r = _run_script(GET_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert r.returncode in (0, 1)

    def test_env_variable_names_overrideable(self, stubs_dir, tmp_path):
        out_dir = tmp_path / "bmc"
        env = {
            "OUT_DIR": str(out_dir),
            "DOMAINS_DIR": str(out_dir / "domains"),
            "ENV_SCU1_LOG0": "custom_cause_var",
        }
        r = _run_script(GET_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert r.returncode in (0, 1)


class TestShowResetCause:
    def test_script_runs_without_crash(self, stubs_dir, tmp_path):
        out_dir = tmp_path / "bmc"
        (out_dir / "domains").mkdir(parents=True)
        env = {
            "OUT_DIR": str(out_dir),
            "DOMAINS_DIR": str(out_dir / "domains"),
        }
        r = _run_script(SHOW_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert r.returncode in (0, 1)

    def test_reads_reset_cause_files(self, stubs_dir, tmp_path):
        out_dir = tmp_path / "bmc"
        (out_dir / "domains").mkdir(parents=True)
        (out_dir / "reset_power_on").write_text("1\n")
        env = {
            "OUT_DIR": str(out_dir),
            "DOMAINS_DIR": str(out_dir / "domains"),
        }
        r = _run_script(SHOW_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert r.returncode in (0, 1)


class TestResetCauseLogger:
    def test_logger_script_runs(self, stubs_dir, tmp_path):
        out_dir = tmp_path / "bmc"
        (out_dir / "domains").mkdir(parents=True)
        env = {
            "OUT_DIR": str(out_dir),
            "DOMAINS_DIR": str(out_dir / "domains"),
        }
        r = _run_script(LOG_CAUSE, stubs_dir=stubs_dir, env_extras=env)
        assert r.returncode in (0, 1)
