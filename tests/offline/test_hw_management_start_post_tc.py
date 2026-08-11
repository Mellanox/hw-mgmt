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

# Mirrors the state restore, the reload gate and the cmd_line build (no nohup).
# Prints NONE when the script would leave the TC service alone.
_BASH_CMD_LINE = r"""
tc_is_enabled=${TC_IS_EN:-0}
tc_is_active=${TC_IS_ACT:-0}
tc_saved_state=${STATE:-}
tc_should_reload=${R:-0}
tc_should_disable=${D:-0}
tc_should_enable=${E:-0}

tc_should_start=$tc_is_active
tc_should_restart=0
if [ "$tc_saved_state" = "started" ] && [ "$tc_is_enabled" -eq 1 ]; then
	tc_should_start=1
fi

# The SimX branch forces a start regardless of the saved state.
if [ "${FORCE_START:-0}" -eq 1 ]; then
	tc_should_start=1
fi

if [ "$tc_should_reload" -eq 1 ]; then
	tc_should_restart=1
	if [ -z "$tc_saved_state" ] && [ "$tc_is_enabled" -eq 1 ]; then
		tc_should_start=1
	fi
fi

tc_action_needed=0
if [ "$tc_should_reload" -eq 1 ] ||
   [ "$tc_should_disable" -eq 1 ] ||
   [ "$tc_should_enable" -eq 1 ] ||
   [ "$tc_should_restart" -eq 1 ]; then
	tc_action_needed=1
elif [ "$tc_should_start" -eq 1 ] && [ "$tc_is_active" -eq 0 ]; then
	tc_action_needed=1
fi

if [ "$tc_action_needed" -eq 0 ]; then
	printf 'NONE\n'
	exit 0
fi

cmd_line="sleep 10 &&"
if [ "$tc_should_reload" -eq 1 ]; then
	cmd_line="$cmd_line systemctl daemon-reload &&"
fi
if [ "$tc_should_disable" -eq 1 ]; then
	cmd_line="$cmd_line systemctl stop hw-management-tc && systemctl disable hw-management-tc &&"
	tc_should_start=0
	tc_should_restart=0
elif [ "$tc_should_enable" -eq 1 ]; then
	cmd_line="$cmd_line systemctl enable hw-management-tc &&"
fi
if [ "$tc_should_start" -ne 0 ]; then
	if [ "$tc_should_restart" -eq 1 ]; then
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
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
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
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
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


def test_systemd_restart_brings_back_tc_that_was_running():
    """PartOf= or systemctl stop both run ExecStop and leave STATE=started.
    After hw-management start, TC must be brought back while the unit stays enabled."""
    s = _run_bash_cmdline({"STATE": "started", "TC_IS_EN": "1", "TC_IS_ACT": "0"})
    assert "start hw-management-tc" in s


def test_no_saved_state_leaves_inactive_tc_alone():
    """Missing marker (never written or already consumed): do not start or stop TC."""
    assert _run_bash_cmdline({"TC_IS_EN": "1", "TC_IS_ACT": "0"}) == "NONE"


def test_running_tc_without_unit_change_is_left_alone():
    assert _run_bash_cmdline({"TC_IS_EN": "1", "TC_IS_ACT": "1"}) == "NONE"


def test_saved_state_with_already_active_tc_is_left_alone():
    """State file only drives start after a systemd stop; if TC is still active, do nothing."""
    assert (
        _run_bash_cmdline({"STATE": "started", "TC_IS_EN": "1", "TC_IS_ACT": "1"}) ==
        "NONE"
    )


def test_saved_state_ignored_when_unit_is_disabled():
    assert _run_bash_cmdline({"STATE": "started", "TC_IS_EN": "0"}) == "NONE"


def test_version_change_restarts_tc_that_was_running():
    s = _run_bash_cmdline(
        {"R": "1", "STATE": "started", "TC_IS_EN": "1", "TC_IS_ACT": "0"}
    )
    assert "daemon-reload" in s and "restart hw-management-tc" in s


def test_cmd_line_reload_only():
    s = _run_bash_cmdline({"R": "1", "TC_IS_EN": "0", "TC_IS_ACT": "0"})
    assert "daemon-reload" in s
    assert "restart" not in s and "start hw-management-tc" not in s


def test_cmd_line_disable_clears_start():
    s = _run_bash_cmdline({"D": "1", "TC_IS_EN": "1", "TC_IS_ACT": "1"})
    assert "stop hw-management-tc" in s and "disable" in s
    assert "start hw-management-tc" not in s and "restart" not in s


def test_cmd_line_reload_with_start_uses_restart():
    s = _run_bash_cmdline({"R": "1", "TC_IS_EN": "1", "TC_IS_ACT": "0"})
    assert "daemon-reload" in s and "restart hw-management-tc" in s


def test_cmd_line_enable_and_start():
    s = _run_bash_cmdline({"E": "1", "FORCE_START": "1", "TC_IS_ACT": "0"})
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


def test_unit_path_taken_from_fragment_path():
    """systemctl status output starts with a warning line once the unit was edited on disk,
    which broke the previous line/field based parsing of the unit path."""
    root = Path(__file__).resolve().parents[2]
    sh = root / "usr" / "usr" / "bin" / "hw-management-start-post.sh"
    text = sh.read_text()
    assert "systemctl show -p FragmentPath hw-management-tc.service" in text
    assert "systemctl status hw-management-tc.service" not in text


def test_tc_state_is_saved_on_hw_management_stop_and_restored_on_start():
    root = Path(__file__).resolve().parents[2]
    tc_unit = (root / "debian" / "hw-management.hw-management-tc.service").read_text()
    helpers = (root / "usr" / "usr" / "bin" / "hw-management-helpers.sh").read_text()
    hw_management = (root / "usr" / "usr" / "bin" / "hw-management.sh").read_text()
    start_post = (
        root / "usr" / "usr" / "bin" / "hw-management-start-post.sh"
    ).read_text()

    assert 'tc_state_file="/var/run/.hw-management-tc-state"' in helpers
    assert "consume_tc_saved_state()" in helpers
    assert "save_tc_state_started" not in helpers
    # Helpers: path near other /run state files; consume after check_tc_is_supported.
    assert helpers.index("asic_chipup_status=") < helpers.index('tc_state_file="/var/run/.hw-management-tc-state"')
    assert helpers.index("check_tc_is_supported()") < helpers.index("consume_tc_saved_state()")
    # Unit: existing ExecStart/ExecStop first; state save/clear after.
    assert tc_unit.index("ExecStart=/bin/sh") < tc_unit.index("ExecStartPost=-/bin/rm -f /var/run/.hw-management-tc-state")
    assert tc_unit.index("ExecStop=/bin/kill $MAINPID") < tc_unit.index("umask 077")
    assert "/var/run/.hw-management-tc-state" in tc_unit
    # State is saved only from the TC unit ExecStop, not from hw-management.sh.
    do_stop = hw_management[hw_management.index("do_stop()"): hw_management.index("function find_asic_hwmon_path")]
    assert "consume_tc_saved_state" not in do_stop
    assert "tc_state_file" not in do_stop
    # start-post: existing enable/active checks first; restore after unit align.
    assert start_post.index("systemctl is-enabled --quiet hw-management-tc.service") < start_post.index(
        "tc_saved_state=$(consume_tc_saved_state)"
    )
    assert start_post.index("tc_should_reload=1") < start_post.index(
        "tc_saved_state=$(consume_tc_saved_state)"
    )


def test_consume_tc_state_handles_missing_broken_and_symlink(tmp_path):
    """Missing / garbage / symlink must not restore TC as started."""
    root = Path(__file__).resolve().parents[2]
    helpers = root / "usr" / "usr" / "bin" / "hw-management-helpers.sh"
    state = tmp_path / ".hw-management-tc-state"
    script = f"""
source {helpers}
tc_state_file="{state}"
printf '%s\\n' "$(consume_tc_saved_state)"
"""

    # Missing file
    r = subprocess.run(["bash", "-e", "-c", script], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert r.stdout.strip() == ""

    # Valid started
    state.write_text("started\n")
    os.chmod(state, 0o600)
    r = subprocess.run(["bash", "-e", "-c", script], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert r.stdout.strip() == "started"
    assert not state.exists()

    # Broken content
    state.write_text("garbage\n")
    r = subprocess.run(["bash", "-e", "-c", script], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert r.stdout.strip() == ""
    assert not state.exists()

    # Empty / whitespace
    state.write_text("   \n")
    r = subprocess.run(["bash", "-e", "-c", script], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert r.stdout.strip() == ""
    assert not state.exists()

    # Symlink: remove and ignore
    target = tmp_path / "elsewhere"
    target.write_text("started\n")
    state.symlink_to(target)
    r = subprocess.run(["bash", "-e", "-c", script], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert r.stdout.strip() == ""
    assert not state.exists()
    assert target.read_text() == "started\n"
