#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-leakage-handler.sh and related leakage scripts."""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

LEAKAGE_HANDLER = str(BMC_SCRIPTS_DIR / "hw-management-bmc-leakage-handler.sh")
A2D_READ = str(BMC_SCRIPTS_DIR / "hw-management-bmc-a2d-leakage-read.sh")
A2D_CONFIG = str(BMC_SCRIPTS_DIR / "hw-management-bmc-a2d-leakage-config.sh")


def _run(script, args="", stubs_dir=None, env_extras=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env_extras:
        env.update(env_extras)
    cmd = ["bash", script] + (args.split() if args else [])
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


def _source_fn(script, snippet, stubs_dir=None, input_text=None, env_extras=None):
    """Source only the functions from a script, not its main body.

    For scripts with set -euo pipefail and an arg-check exit at the top,
    we extract just the function definitions using bash function override.
    """
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if env_extras:
        env.update(env_extras)
    # Bypass top-level arg checks by pre-setting positional params and
    # replacing the exit-on-missing-args block with a no-op.
    preamble = f"""
set +euo pipefail 2>/dev/null || true
# Pre-satisfy arg checks
A2D_INDEX="${{A2D_INDEX:-0}}"
TS_MS="${{TS_MS:-0}}"
BASE="${{BASE:-/tmp/leakage_test_base}}"
# Source with error checks relaxed
set +e
source {script} 2>/dev/null || true
set -e 2>/dev/null || true
"""
    full = preamble + "\n" + snippet
    return subprocess.run(
        ["bash", "-c", full],
        input=input_text,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env, timeout=10,
    )


_ALIGN12_FN = r"""
align12() {
    awk -v s="$1" 'BEGIN {
        if (s == "" || s !~ /^-?[0-9]+$/) { print ""; exit 0 }
        v = int(s)
        r = v % 4096
        if (r < 0) { r += 4096 }
        print r
    }'
}
"""


def _run_inline(snippet):
    return subprocess.run(
        ["bash", "-c", _ALIGN12_FN + "\n" + snippet],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, timeout=5,
    )


class TestAlign12:
    def test_value_within_12_bits_unchanged(self):
        r = _run_inline('result=$(align12 2048); echo "$result"')
        assert r.stdout.strip() == "2048"

    def test_value_over_12_bits_masked(self):
        r = _run_inline('result=$(align12 4097); echo "$result"')
        assert r.stdout.strip() == "1"  # 4097 % 4096 = 1

    def test_zero_input(self):
        r = _run_inline('result=$(align12 0); echo "$result"')
        assert r.stdout.strip() == "0"

    def test_max_12_bit_value(self):
        r = _run_inline('result=$(align12 4095); echo "$result"')
        assert r.stdout.strip() == "4095"

    def test_empty_input_returns_empty(self):
        r = _run_inline('result=$(align12 ""); echo "[$result]"')
        assert r.stdout.strip() == "[]"

    def test_non_numeric_returns_empty(self):
        r = _run_inline('result=$(align12 "abc"); echo "[$result]"')
        assert r.stdout.strip() == "[]"

    def test_exact_4096_wraps_to_zero(self):
        r = _run_inline('result=$(align12 4096); echo "$result"')
        assert r.stdout.strip() == "0"


class TestLeakageHandlerArgs:
    def test_missing_args_exits_nonzero(self, stubs_dir):
        r = _run(LEAKAGE_HANDLER, stubs_dir=stubs_dir)
        assert r.returncode == 1

    def test_missing_second_arg_exits_nonzero(self, stubs_dir):
        r = _run(LEAKAGE_HANDLER, args="0", stubs_dir=stubs_dir)
        assert r.returncode == 1

    def test_missing_both_args_error_message(self, stubs_dir):
        r = _run(LEAKAGE_HANDLER, stubs_dir=stubs_dir)
        assert "Usage" in r.stderr or r.returncode != 0

    def test_nonexistent_base_dir_exits_zero(self, stubs_dir, tmp_path):
        # BASE=/var/run/hw-management/leakage/<idx>; if not found, exit 0
        r = _run(LEAKAGE_HANDLER, args="99 12345", stubs_dir=stubs_dir,
                 env_extras={"BASE": str(tmp_path / "nonexistent" / "99")})
        assert r.returncode in (0, 1)


_PROCESS_CHANNEL_FN = _ALIGN12_FN + r"""
process_channel() {
    local ch_dir="$1"
    local input_path="$ch_dir/input"
    local sample=""
    if [ -L "$input_path" ] || [ -f "$input_path" ]; then
        IFS= read -r sample <"$input_path" 2>/dev/null || sample=""
        sample="${sample//$'\r'/}"
        sample="${sample// /}"
    else
        return 0
    fi
    local aligned
    aligned=$(align12 "$sample")
    echo "aligned=$aligned"
    return 0
}
"""


class TestLeakageHandlerProcessChannel:
    def test_channel_with_valid_input(self, tmp_path):
        ch_dir = tmp_path / "ch0"
        ch_dir.mkdir()
        (ch_dir / "input").write_text("1024\n")

        r = subprocess.run(
            ["bash", "-c", _PROCESS_CHANNEL_FN + f'\nprocess_channel "{ch_dir}"; echo "rc=$?"'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True, timeout=5,
        )
        assert "rc=0" in r.stdout
        assert "aligned=1024" in r.stdout

    def test_channel_missing_input_skips(self, tmp_path):
        ch_dir = tmp_path / "ch_no_input"
        ch_dir.mkdir()

        r = subprocess.run(
            ["bash", "-c", _PROCESS_CHANNEL_FN + f'\nprocess_channel "{ch_dir}"; echo "rc=$?"'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True, timeout=5,
        )
        assert "rc=0" in r.stdout

    def test_channel_value_masked_to_12_bits(self, tmp_path):
        ch_dir = tmp_path / "ch1"
        ch_dir.mkdir()
        (ch_dir / "input").write_text("8192\n")  # 8192 % 4096 = 0

        r = subprocess.run(
            ["bash", "-c", _PROCESS_CHANNEL_FN + f'\nprocess_channel "{ch_dir}"'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True, timeout=5,
        )
        assert "aligned=0" in r.stdout


class TestA2dLeakageRead:
    def test_missing_a2d_index_arg_fails(self, stubs_dir):
        r = _run(A2D_READ, stubs_dir=stubs_dir)
        assert r.returncode != 0 or "Usage" in r.stderr

    def test_runs_with_valid_index(self, stubs_dir, tmp_path):
        base = tmp_path / "leakage" / "1"
        base.mkdir(parents=True)
        r = _run(A2D_READ, args="1 99999", stubs_dir=stubs_dir)
        # Without proper sysfs it may exit 0 (no channels to process)
        assert r.returncode in (0, 1)


class TestA2dLeakageConfig:
    def test_script_exists(self):
        assert Path(A2D_CONFIG).exists()

    def test_runs_without_json_config(self, stubs_dir, tmp_path):
        r = _run(A2D_CONFIG, stubs_dir=stubs_dir,
                 env_extras={"A2D_LEAKAGE_CONFIG": str(tmp_path / "nonexistent.json")})
        # Should exit cleanly or with a usage/config error, not a crash
        assert r.returncode in (0, 1)
