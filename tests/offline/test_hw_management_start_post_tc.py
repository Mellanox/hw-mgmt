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

# Mirrors the simplified cmd_line build in start-post.sh (no nohup). The
# tc_should_start-only branch defers the marker re-check/consume and the
# is-active check into the command line itself, so they run when the 10s
# sleep elapses, not when cmd_line is built - see _BASH_DEFERRED_START.
# Prints NONE when the script would leave the TC service alone.
_BASH_CMD_LINE = r"""
tc_should_disable=${D:-0}
tc_should_enable=${E:-0}
tc_should_start=${S:-0}
tc_pending_restart_file="$MARKER"

cmd_line=""
if [ "$tc_should_disable" -eq 1 ] || [ "$tc_should_enable" -eq 1 ] || [ "$tc_should_start" -eq 1 ]; then
	cmd_line="sleep 10 &&"
	if [ "$tc_should_disable" -eq 1 ]; then
		cmd_line="$cmd_line systemctl stop hw-management-tc && systemctl disable hw-management-tc &&"
	elif [ "$tc_should_enable" -eq 1 ]; then
		cmd_line="$cmd_line systemctl enable hw-management-tc &&"
		if [ "$tc_should_start" -eq 1 ]; then
			cmd_line="$cmd_line systemctl start hw-management-tc &&"
		fi
	elif [ "$tc_should_start" -eq 1 ]; then
		cmd_line="$cmd_line if [ -f $tc_pending_restart_file ]; then rm -f $tc_pending_restart_file; if ! systemctl is-active --quiet hw-management-tc.service; then systemctl start hw-management-tc; fi; fi &&"
	fi
fi

if [ -z "$cmd_line" ]; then
	printf 'NONE\n'
else
	printf '%s\n' "$cmd_line"
fi
"""

# Mirrors the post-PartOf restart-detection added in start-post.sh: an already
# enabled TC service that is not currently active (hw-management.service was
# stopped and started separately, so PartOf= propagated only the stop) is
# scheduled for a restore-check only when hw-management-tc-stop-post.sh
# recorded that the prior stop was the PartOf= cascade (marker file present),
# not an operator directly stopping TC. The marker itself is deliberately NOT
# consumed here - see _BASH_DEFERRED_START - so a stop issued during the
# scheduling delay is not silently overridden by this early decision.
_BASH_RESTART_CHECK = r"""
tc_is_enabled=${TC_IS_EN:-0}
tc_should_disable=${D:-0}
tc_should_start=${S:-0}
tc_pending_restart_file="$MARKER"

if [ "$tc_is_enabled" -eq 1 ] && [ "$tc_should_disable" -eq 0 ] && [ "$tc_should_start" -eq 0 ]; then
	if [ -f "$tc_pending_restart_file" ]; then
		tc_should_start=1
	fi
fi
printf '%d %d\n' "$tc_should_start" "$([ -f "$tc_pending_restart_file" ] && echo 1 || echo 0)"
"""

# Mirrors the deferred re-check embedded in cmd_line for the tc_should_start
# branch: runs after the 10s scheduling delay, so it sees whatever the marker
# and TC's active state actually are at that moment, not at decision time.
_BASH_DEFERRED_START = r"""
tc_pending_restart_file="$MARKER"

systemctl() {
	if [ "$1" = "is-active" ]; then
		return "${ACTIVE_RET:-0}"
	fi
	if [ "$1" = "start" ]; then
		echo STARTED
	fi
	return 0
}

if [ -f "$tc_pending_restart_file" ]; then
	rm -f "$tc_pending_restart_file"
	if ! systemctl is-active --quiet hw-management-tc.service; then
		systemctl start hw-management-tc
	fi
fi
"""

# Mirrors hw-management-tc-stop-post.sh (ExecStopPost hook): decides whether
# TC's stop was an operator directly stopping TC, or a PartOf= cascade from
# hw-management.service also stopping/restarting. TC has
# After=hw-management.service, so on a coordinated stop the parent's own stop
# job has not even started (ActiveState is still "active") by the time this
# hook runs - a job queued for the whole transaction is what distinguishes
# the cascade case, not the parent's current ActiveState.
_BASH_STOP_POST = r"""
tc_pending_restart_file="$MARKER"

systemctl() {
	if [ "$1" = "list-jobs" ]; then
		printf '%s\n' "$HWMGMT_JOBS_OUTPUT"
		return 0
	fi
	return 0
}

if systemctl list-jobs --no-legend hw-management.service 2>/dev/null | grep -q .; then
	touch "$tc_pending_restart_file"
else
	rm -f "$tc_pending_restart_file"
fi
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


def _run_bash_cmdline(env, marker="/nonexistent/pending"):
    e = os.environ.copy()
    e.update({k: str(v) for k, v in env.items()})
    e["MARKER"] = str(marker)
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


def _run_deferred_start(marker, active_ret):
    e = os.environ.copy()
    e["MARKER"] = str(marker)
    e["ACTIVE_RET"] = "0" if active_ret else "1"
    r = subprocess.run(
        ["bash", "-e", "-c", _BASH_DEFERRED_START],
        env=e,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        timeout=5,
    )
    assert r.returncode == 0, r.stderr
    return "STARTED" in r.stdout


def _run_restart_check(env, marker):
    e = os.environ.copy()
    e.update({k: str(v) for k, v in env.items()})
    e["MARKER"] = str(marker)
    r = subprocess.run(
        ["bash", "-e", "-c", _BASH_RESTART_CHECK],
        env=e,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        timeout=5,
    )
    assert r.returncode == 0, r.stderr
    should_start, marker_left = r.stdout.strip().split()
    return int(should_start), int(marker_left)


def _run_stop_post(parent_job_queued, marker):
    e = os.environ.copy()
    e["MARKER"] = str(marker)
    e["HWMGMT_JOBS_OUTPUT"] = (
        "1234 hw-management.service stop waiting" if parent_job_queued else ""
    )
    r = subprocess.run(
        ["bash", "-e", "-c", _BASH_STOP_POST],
        env=e,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        timeout=5,
    )
    assert r.returncode == 0, r.stderr


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


def _run_launcher_desc_patch(tc_config_content, initial_desc, tmp_path):
    """Run launcher version-selection + Description-patch logic against a fake
    unit file and a stubbed systemctl. Returns (bin_tag, final_desc, reload_calls)."""
    cfg = tmp_path / "tc_config.json"
    if tc_config_content is not None:
        cfg.write_text(tc_config_content)
        cfg_path = str(cfg)
    else:
        cfg_path = "/nonexistent/tc_config.json"

    unit = tmp_path / "hw-management-tc.service"
    unit.write_text(f"[Unit]\nDescription={initial_desc}\nAfter=hw-management.service\n")

    reload_log = tmp_path / "reload.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    stub = bin_dir / "systemctl"
    stub.write_text(f'#!/bin/sh\necho "$*" >> "{reload_log}"\n')
    stub.chmod(0o755)

    script = rf"""
tc_cfg="{cfg_path}"
unit_path="{unit}"

tc_ver=$(grep -o '"tc_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$tc_cfg" 2>/dev/null \
         | head -n1 | cut -d'"' -f4)

case $tc_ver in
    2.5|2.5.*)
        tc_ver_label=2.5
        tc_bin=/usr/bin/hw_management_thermal_control_2_5.py
        ;;
    *)
        tc_ver_label=2.0
        tc_bin=/usr/bin/hw_management_thermal_control.py
        ;;
esac

desc="Thermal control service (ver $tc_ver_label) of Nvidia systems"
if ! grep -qF "Description=$desc" "$unit_path"; then
    sed -i "s/^Description=.*/Description=$desc/" "$unit_path"
    systemctl daemon-reload
fi
"""
    env = dict(os.environ)
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    r = subprocess.run(
        ["bash", "-e", "-c", script],
        capture_output=True,
        text=True,
        timeout=5,
        env=env,
    )
    assert r.returncode == 0, r.stderr

    final_desc = [line for line in unit.read_text().splitlines() if line.startswith("Description=")][0]
    reload_calls = reload_log.read_text().splitlines() if reload_log.exists() else []
    return final_desc, reload_calls


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


def test_cmd_line_start_only(tmp_path):
    """Already-enabled TC that just needs restarting: the deferred re-check
    block is scheduled, no enable/disable."""
    marker = tmp_path / "pending"
    s = _run_bash_cmdline({"S": "1"}, marker=marker)
    assert "start hw-management-tc" in s
    assert str(marker) in s
    assert "enable hw-management-tc" not in s and "disable hw-management-tc" not in s


def test_cmd_line_no_action_ignores_marker():
    """Marker presence alone (without S=1) must not trigger scheduling."""
    assert _run_bash_cmdline({}) == "NONE"


# ---------------------------------------------------------------------------
# PartOf= start-propagation restart-detection tests
# ---------------------------------------------------------------------------
# tc_should_start is only scheduled here - the marker is deliberately left
# untouched (not consumed, no is-active check) so an operator's action during
# the 10s scheduling delay can still take effect; see the deferred-start
# tests below for the actual consume/start logic.

def test_restart_flagged_when_marker_present(tmp_path):
    """Marker present (PartOf= cascade recorded by stop-post): schedule a
    restore-check, and leave the marker in place for the deferred re-check."""
    marker = tmp_path / "pending"
    marker.touch()
    should_start, marker_left = _run_restart_check({"TC_IS_EN": "1", "D": "0", "S": "0"}, marker)
    assert (should_start, marker_left) == (1, 1)


def test_restart_not_flagged_when_marker_absent():
    """No marker (no stop-post ran, or last stop was operator-intentional):
    do not schedule a restore even though TC is enabled and inactive."""
    should_start, marker_left = _run_restart_check(
        {"TC_IS_EN": "1", "D": "0", "S": "0"}, "/nonexistent/pending"
    )
    assert (should_start, marker_left) == (0, 0)


def test_restart_not_flagged_when_not_enabled(tmp_path):
    marker = tmp_path / "pending"
    marker.touch()
    should_start, marker_left = _run_restart_check({"TC_IS_EN": "0", "D": "0", "S": "0"}, marker)
    assert (should_start, marker_left) == (0, 1)


def test_restart_not_flagged_when_disabling(tmp_path):
    marker = tmp_path / "pending"
    marker.touch()
    should_start, marker_left = _run_restart_check({"TC_IS_EN": "1", "D": "1", "S": "0"}, marker)
    assert (should_start, marker_left) == (0, 1)


def test_restart_not_double_flagged_when_already_starting(tmp_path):
    marker = tmp_path / "pending"
    marker.touch()
    should_start, marker_left = _run_restart_check({"TC_IS_EN": "1", "D": "0", "S": "1"}, marker)
    assert (should_start, marker_left) == (1, 1)


# ---------------------------------------------------------------------------
# Deferred restore re-check tests (embedded in cmd_line, runs after the 10s
# scheduling delay - this is what actually consumes the marker and starts TC)
# ---------------------------------------------------------------------------

def test_deferred_start_starts_and_consumes_marker_when_still_pending(tmp_path):
    marker = tmp_path / "pending"
    marker.touch()
    assert _run_deferred_start(marker, active_ret=False) is True
    assert not marker.exists()


def test_deferred_start_does_nothing_when_marker_no_longer_present(tmp_path):
    """The key race fix: if something consumed/removed the marker during the
    10s scheduling delay (e.g. a fresh stop-post run), the deferred re-check
    must not start TC - it must not rely on the decision made 10s earlier."""
    marker = tmp_path / "pending"
    assert _run_deferred_start(marker, active_ret=False) is False


def test_deferred_start_skips_start_when_already_active(tmp_path):
    """Marker present but TC is already active by execution time: consume the
    marker (cleanup) but do not issue a redundant start."""
    marker = tmp_path / "pending"
    marker.touch()
    assert _run_deferred_start(marker, active_ret=True) is False
    assert not marker.exists()


# ---------------------------------------------------------------------------
# hw-management-tc-stop-post.sh (ExecStopPost) tests
# ---------------------------------------------------------------------------

def test_stop_post_clears_marker_when_no_parent_job_queued(tmp_path):
    """Operator directly stops TC, no stop/restart job queued for
    hw-management.service: treat as intentional, clear any stale marker."""
    marker = tmp_path / "pending"
    marker.touch()
    _run_stop_post(parent_job_queued=False, marker=marker)
    assert not marker.exists()


def test_stop_post_sets_marker_when_parent_job_queued(tmp_path):
    """A stop/restart job is queued for hw-management.service (it has not
    started yet due to After= ordering, so it's still "active"): TC's stop
    is the PartOf= cascade, mark it for restore on the next start."""
    marker = tmp_path / "pending"
    _run_stop_post(parent_job_queued=True, marker=marker)
    assert marker.exists()


def test_stop_post_no_marker_stays_absent_when_no_parent_job_queued(tmp_path):
    marker = tmp_path / "pending"
    _run_stop_post(parent_job_queued=False, marker=marker)
    assert not marker.exists()


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


def test_start_post_restarts_enabled_but_inactive_tc():
    """start-post.sh must restart an already-enabled TC left inactive by a
    separate hw-management.service stop+start (PartOf= only propagates stop),
    gated on the marker written by hw-management-tc-stop-post.sh."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "usr" / "usr" / "bin" / "hw-management-start-post.sh").read_text()
    assert "systemctl is-active --quiet hw-management-tc.service" in text
    assert "tc_should_start=1" in text
    assert "tc_pending_restart_file" in text


def test_start_post_defers_marker_consumption_past_the_scheduling_delay():
    """Regression for the marker-consumed-too-early race: the decision-time
    block (before the 10s deferral) must not remove the marker or check
    is-active itself - only the deferred cmd_line block (which runs after the
    delay) may do that, so a stop issued during the delay is not overridden."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "usr" / "usr" / "bin" / "hw-management-start-post.sh").read_text()
    decision_block = text.split("# Build and execute the command line")[0]
    assert "rm -f" not in decision_block
    assert "is-active" not in decision_block
    assert 'rm -f $tc_pending_restart_file' in text


def test_stop_post_script_distinguishes_operator_stop_from_cascade():
    """hw-management-tc-stop-post.sh must check for a queued job on the
    parent, not its ActiveState, to tell an operator-initiated TC stop apart
    from a PartOf= cascade: TC has After=hw-management.service, so the
    parent's own stop job has not started (still "active") by the time this
    hook runs even during a genuine cascade."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "usr" / "usr" / "bin" / "hw-management-tc-stop-post.sh").read_text()
    assert "systemctl list-jobs --no-legend hw-management.service" in text
    assert "systemctl is-active" not in text
    assert 'rm -f "$tc_pending_restart_file"' in text
    assert 'touch "$tc_pending_restart_file"' in text


def test_helpers_define_shared_pending_restart_marker():
    """The marker path must be defined once and shared by both scripts."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "usr" / "usr" / "bin" / "hw-management-helpers.sh").read_text()
    assert "tc_pending_restart_file=/var/run/.hw-management-tc-pending-restart" in text


def test_service_file_wires_stop_post_hook():
    root = Path(__file__).resolve().parents[2]
    text = (root / "debian" / "hw-management.hw-management-tc.service").read_text()
    assert "ExecStopPost=/usr/bin/hw-management-tc-stop-post.sh" in text


# ---------------------------------------------------------------------------
# RPM packaging tests
# ---------------------------------------------------------------------------

def test_rpm_spec_packages_tc_launcher():
    """The launcher script must be installed and listed in %files, or
    hw-management-tc.service's ExecStart is missing on RPM-based installs."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "rpm" / "hw-management.spec").read_text()
    assert "usr/usr/bin/hw_management_tc_launcher.sh" in text
    assert '"/usr/bin/hw_management_tc_launcher.sh"' in text


def test_rpm_spec_packages_tc_stop_post():
    """The ExecStopPost hook must be installed and listed in %files, or
    hw-management-tc.service's ExecStopPost is missing on RPM-based installs."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "rpm" / "hw-management.spec").read_text()
    assert "usr/usr/bin/hw-management-tc-stop-post.sh" in text
    assert '"/usr/bin/hw-management-tc-stop-post.sh"' in text


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
    assert "tc_bin=/usr/bin/hw_management_thermal_control_2_5.py" in text
    assert "tc_bin=/usr/bin/hw_management_thermal_control.py" in text
    assert 'exec "$tc_bin"' in text
    # Must not use sh -c wrapper
    assert "/bin/sh -c" not in text


# ---------------------------------------------------------------------------
# Launcher Description-patch tests
# ---------------------------------------------------------------------------

def test_launcher_patches_description_to_v25(tmp_path):
    final_desc, reload_calls = _run_launcher_desc_patch(
        '{"tc_version": "2.5"}', "Thermal control service (ver x.x) of Nvidia systems", tmp_path
    )
    assert final_desc == "Description=Thermal control service (ver 2.5) of Nvidia systems"
    assert reload_calls == ["daemon-reload"]


def test_launcher_patches_description_to_v20(tmp_path):
    final_desc, reload_calls = _run_launcher_desc_patch(
        None, "Thermal control service (ver x.x) of Nvidia systems", tmp_path
    )
    assert final_desc == "Description=Thermal control service (ver 2.0) of Nvidia systems"
    assert reload_calls == ["daemon-reload"]


def test_launcher_skips_reload_when_description_already_current(tmp_path):
    final_desc, reload_calls = _run_launcher_desc_patch(
        '{"tc_version": "2.0"}', "Thermal control service (ver 2.0) of Nvidia systems", tmp_path
    )
    assert final_desc == "Description=Thermal control service (ver 2.0) of Nvidia systems"
    assert reload_calls == []


def test_launcher_repatches_description_on_version_change(tmp_path):
    """A prior boot's stale (ver 2.0) must be corrected once tc_config.json says 2.5."""
    final_desc, reload_calls = _run_launcher_desc_patch(
        '{"tc_version": "2.5"}', "Thermal control service (ver 2.0) of Nvidia systems", tmp_path
    )
    assert final_desc == "Description=Thermal control service (ver 2.5) of Nvidia systems"
    assert reload_calls == ["daemon-reload"]


def test_launcher_hardcodes_unit_path():
    """The install location is fixed by debhelper convention (debian/hw-management.hw-management-tc.service
    -> package hw-management -> /lib/systemd/system/hw-management-tc.service); no runtime lookup needed."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "usr" / "usr" / "bin" / "hw_management_tc_launcher.sh").read_text()
    assert "unit_path=/lib/systemd/system/hw-management-tc.service" in text


def test_service_file_ships_unpatched_version_placeholder():
    """Before the launcher's first run, the shipped Description must not claim a
    specific version it hasn't verified (e.g. a stale/wrong 'ver 2.0')."""
    root = Path(__file__).resolve().parents[2]
    text = (root / "debian" / "hw-management.hw-management-tc.service").read_text()
    assert "Description=Thermal control service (ver x.x) of Nvidia systems" in text
