#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for hw-management-start-post.sh TC service logic and
# hw_management_tc_launcher.sh version selection.
#
# Verifies: TC is not auto-enabled on non-SimX; SimX paths set enable/disable
# flags; deferred cmd_line matches enable/disable combinations; launcher picks
# the correct Python binary from tc_config.json.
################################################################################

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.offline

# Mirrors start-post.sh TC flag computation (platform/SimX logic only)
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

# Mirrors the simplified cmd_line build in start-post.sh (no nohup).
# Prints NONE when the script would leave the TC service alone.
_BASH_CMD_LINE = r"""
tc_should_disable=${D:-0}
tc_should_enable=${E:-0}
tc_should_start=${S:-0}

cmd_line=""
if [ "$tc_should_disable" -eq 1 ] || [ "$tc_should_enable" -eq 1 ]; then
	cmd_line="sleep 10 &&"
	if [ "$tc_should_disable" -eq 1 ]; then
		cmd_line="$cmd_line systemctl stop hw-management-tc && systemctl disable hw-management-tc &&"
	elif [ "$tc_should_enable" -eq 1 ]; then
		cmd_line="$cmd_line systemctl enable hw-management-tc &&"
		if [ "$tc_should_start" -eq 1 ]; then
			cmd_line="$cmd_line systemctl start hw-management-tc &&"
		fi
	fi
fi

if [ -z "$cmd_line" ]; then
	printf 'NONE\n'
else
	printf '%s\n' "$cmd_line"
fi
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


def _run_launcher(tc_config_content, tmp_path):
    """Run launcher version-selection logic; return '2_5' or '2_0'."""
    cfg = tmp_path / "tc_config.json"
    if tc_config_content is not None:
        cfg.write_text(tc_config_content)
        cfg_path = str(cfg)
    else:
        cfg_path = "/nonexistent/tc_config.json"

    script = rf"""
tc_cfg="{cfg_path}"
tc_ver=$(grep -o '"tc_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$tc_cfg" 2>/dev/null \
         | head -n1 | cut -d'"' -f4)
case $tc_ver in
    2.5|2.5.*)
        printf '2_5\n'
        ;;
    *)
        printf '2_0\n'
        ;;
esac
"""
    r = subprocess.run(["bash", "-e", "-c", script], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


# ---------------------------------------------------------------------------
# Platform / SimX flag tests
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# cmd_line builder tests
# ---------------------------------------------------------------------------

def test_no_action_needed_returns_none():
    """No disable/enable → nothing to do."""
    assert _run_bash_cmdline({}) == "NONE"


def test_cmd_line_disable():
    s = _run_bash_cmdline({"D": "1"})
    assert "stop hw-management-tc" in s and "disable hw-management-tc" in s
    assert "start hw-management-tc" not in s and "enable" not in s


def test_cmd_line_enable_and_start():
    s = _run_bash_cmdline({"E": "1", "S": "1"})
    assert "enable hw-management-tc" in s and "start hw-management-tc" in s


def test_cmd_line_enable_without_start():
    s = _run_bash_cmdline({"E": "1", "S": "0"})
    assert "enable hw-management-tc" in s
    assert "start hw-management-tc" not in s


# ---------------------------------------------------------------------------
# start-post.sh structural checks
# ---------------------------------------------------------------------------

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


def test_start_post_no_longer_patches_service_file():
    """start-post.sh must not sed-patch the TC unit file."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "usr" / "usr" / "bin" / "hw-management-start-post.sh").read_text()
    assert "sed_edit_executable" not in text
    assert "FragmentPath" not in text
    assert "daemon-reload" not in text
    assert "consume_tc_saved_state" not in text


# ---------------------------------------------------------------------------
# Launcher version selection tests
# ---------------------------------------------------------------------------

def test_launcher_selects_v25_binary(tmp_path):
    assert _run_launcher('{"tc_version": "2.5"}', tmp_path) == "2_5"


def test_launcher_selects_v25_for_subversion(tmp_path):
    assert _run_launcher('{"tc_version": "2.5.1"}', tmp_path) == "2_5"


def test_launcher_selects_v20_explicitly(tmp_path):
    assert _run_launcher('{"tc_version": "2.0"}', tmp_path) == "2_0"


def test_launcher_defaults_to_v20_when_config_missing(tmp_path):
    assert _run_launcher(None, tmp_path) == "2_0"


def test_launcher_defaults_to_v20_for_unknown_version(tmp_path):
    assert _run_launcher('{"tc_version": "3.0"}', tmp_path) == "2_0"


def test_launcher_uses_exec_so_python_is_mainpid():
    """The launcher must exec the Python binary so Python becomes the systemd MAINPID."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "usr" / "usr" / "bin" / "hw_management_tc_launcher.sh").read_text()
    assert "exec /usr/bin/hw_management_thermal_control_2_5.py" in text
    assert "exec /usr/bin/hw_management_thermal_control.py" in text
    # Must not use sh -c wrapper
    assert "/bin/sh -c" not in text
