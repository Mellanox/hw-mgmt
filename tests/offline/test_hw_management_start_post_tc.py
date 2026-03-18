#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for hw-management-start-post.sh TC service logic
# (commit f9f543b4c6b5dd42caac5d0c1b8e4aa559566b8d, Bug 4929286).
#
# Verifies: TC is not auto-enabled on non-SimX; SimX paths set enable/disable
# flags; deferred cmd_line matches reload/start/stop combinations.
################################################################################

import os
import subprocess
import sys
from pathlib import Path

import pytest

pytestmark = pytest.mark.offline

# Mirrors start-post.sh lines 114-159 (flag computation only)
_BASH_TC_FLAGS = r"""
tc_is_enabled=${TC_IS_EN:-0}
tc_should_start=0
if [ "${TC_IS_ACT:-0}" -eq 1 ]; then tc_should_start=1; fi
tc_should_enable=0
tc_should_disable=0

check_tc_is_supported() { return "${TC_CHK_RET:-1}"; }
check_simx() { return "${SIMX_RET:-1}"; }
check_if_simx_supported_platform() { return "${SIMPL_RET:-1}"; }

if check_tc_is_supported; then
	tc_should_disable=1
else
	if check_simx; then
		if ! check_if_simx_supported_platform; then
			if [ "$tc_is_enabled" -eq 1 ]; then
				tc_should_disable=1
				tc_should_start=0
			fi
		else
			if [ "$tc_is_enabled" -eq 0 ]; then
				tc_should_enable=1
				tc_should_start=1
			fi
		fi
	fi
fi
printf '%d %d %d\n' "$tc_should_disable" "$tc_should_enable" "$tc_should_start"
"""

# Mirrors cmd_line build 184-214 (no nohup)
_BASH_CMD_LINE = r"""
tc_should_reload=${R:-0}
tc_should_disable=${D:-0}
tc_should_enable=${E:-0}
tc_should_start=${S:-0}
cmd_line="sleep 10 &&"
if [ "$tc_should_reload" -eq 1 ]; then
	cmd_line="$cmd_line systemctl daemon-reload &&"
fi
if [ "$tc_should_disable" -eq 1 ]; then
	cmd_line="$cmd_line systemctl stop hw-management-tc && systemctl disable hw-management-tc &&"
	tc_should_start=0
elif [ "$tc_should_enable" -eq 1 ]; then
	cmd_line="$cmd_line systemctl enable hw-management-tc &&"
fi
if [ "$tc_should_start" -ne 0 ]; then
	if [ "$tc_should_reload" -eq 1 ]; then
		cmd_line="$cmd_line systemctl restart hw-management-tc &&"
	else
		cmd_line="$cmd_line systemctl start hw-management-tc &&"
	fi
fi
printf '%s\n' "$cmd_line"
"""


def _run_bash_flags(env):
    e = os.environ.copy()
    e.update({k: str(v) for k, v in env.items()})
    r = subprocess.run(
        ["bash", "-e", "-c", _BASH_TC_FLAGS],
        env=e,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert r.returncode == 0, r.stderr
    parts = r.stdout.strip().split()
    return int(parts[0]), int(parts[1]), int(parts[2])


def _run_bash_cmdline(env):
    e = os.environ.copy()
    e.update({k: str(v) for k, v in env.items()})
    r = subprocess.run(
        ["bash", "-e", "-c", _BASH_CMD_LINE],
        env=e,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def test_tc_not_supported_disables():
    """check_tc_is_supported returns 0 -> platform_support 0 -> disable."""
    d, en, st = _run_bash_flags({"TC_CHK_RET": "0", "TC_IS_EN": "0", "TC_IS_ACT": "0"})
    assert (d, en, st) == (1, 0, 0)


def test_tc_supported_non_simx_no_auto_enable():
    """Bug 4929286: bare metal (no SimX) must not set enable when TC was off."""
    d, en, st = _run_bash_flags(
        {"TC_CHK_RET": "1", "SIMX_RET": "1", "TC_IS_EN": "0", "TC_IS_ACT": "0"}
    )
    assert (d, en, st) == (0, 0, 0)


def test_simx_unsupported_platform_disables_when_was_enabled():
    d, en, st = _run_bash_flags(
        {
            "TC_CHK_RET": "1",
            "SIMX_RET": "0",
            "SIMPL_RET": "1",
            "TC_IS_EN": "1",
            "TC_IS_ACT": "1",
        }
    )
    assert (d, en, st) == (1, 0, 0)


def test_simx_supported_enables_when_unit_disabled():
    d, en, st = _run_bash_flags(
        {
            "TC_CHK_RET": "1",
            "SIMX_RET": "0",
            "SIMPL_RET": "0",
            "TC_IS_EN": "0",
            "TC_IS_ACT": "0",
        }
    )
    assert (d, en, st) == (0, 1, 1)


def test_simx_supported_already_enabled_no_enable_flag():
    d, en, st = _run_bash_flags(
        {
            "TC_CHK_RET": "1",
            "SIMX_RET": "0",
            "SIMPL_RET": "0",
            "TC_IS_EN": "1",
            "TC_IS_ACT": "1",
        }
    )
    assert (d, en, st) == (0, 0, 1)


def test_cmd_line_reload_only():
    s = _run_bash_cmdline({"R": "1", "D": "0", "E": "0", "S": "0"})
    assert "daemon-reload" in s
    assert "restart" not in s and "start hw-management-tc" not in s


def test_cmd_line_disable_clears_start():
    s = _run_bash_cmdline({"R": "0", "D": "1", "E": "0", "S": "1"})
    assert "stop hw-management-tc" in s and "disable" in s
    assert "start hw-management-tc" not in s and "restart" not in s


def test_cmd_line_reload_with_start_uses_restart():
    s = _run_bash_cmdline({"R": "1", "D": "0", "E": "0", "S": "1"})
    assert "daemon-reload" in s and "restart hw-management-tc" in s


def test_cmd_line_enable_and_start():
    s = _run_bash_cmdline({"R": "0", "D": "0", "E": "1", "S": "1"})
    assert "enable hw-management-tc" in s and "start hw-management-tc" in s


def test_start_post_script_documents_bug_and_nohup():
    """Regression: script uses deferred nohup bash -c for TC actions."""
    root = Path(__file__).resolve().parents[2]
    sh = root / "usr" / "usr" / "bin" / "hw-management-start-post.sh"
    text = sh.read_text()
    assert "tc_should_enable" in text
    assert "nohup bash -c" in text
    assert "tc_is_enabled" in text
    # Do not auto-enable on TC 2.5 alone: enable only in SimX-supported branch
    assert "if [ $tc_is_enabled -eq 0 ]; then" in text
    assert "tc_should_enable=1" in text
