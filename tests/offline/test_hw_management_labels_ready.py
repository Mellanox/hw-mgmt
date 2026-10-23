#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Unit tests for the config/labels_ready indicator.
#
# The indicator used to be published by hw-management-label-init-complete.sh,
# which slept 20 s before it even looked for a running
# hw-management-labels-maker.sh. It is now published by
# hw-management-sysfs-monitor.sh, which already waits for the sysfs tree to
# settle, with hw-management-start-post.sh handing the work over through
# $labels_pending_file.

import os
import signal
import subprocess
import time
from pathlib import Path

import pytest

pytestmark = pytest.mark.offline

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / "usr" / "usr" / "bin"
HELPERS = BIN / "hw-management-helpers.sh"


def _publish(tmp_path, timeout=30, maker=None):
    """Run publish_labels_ready against a temporary tree. Returns its stderr.

    The driver goes into a file rather than `bash -c`: pgrep -f matches a
    command line that merely carries the maker name, which an inline script
    would, while the monitor's own command line does not.
    """
    config_path = tmp_path / "config"
    config_path.mkdir(exist_ok=True)
    driver = tmp_path / "publish-driver.sh"
    driver.write_text(f"""#!/bin/bash
source {HELPERS}
config_path="{config_path}"
labels_pending_file="{tmp_path}/.hw-management-labels-pending"
labels_maker_timeout={timeout}
{'labels_maker_script="' + maker + '"' if maker else ''}
log_err() {{ printf 'ERR %s\\n' "$*" >&2; }}
log_info() {{ printf 'INFO %s\\n' "$*" >&2; }}
publish_labels_ready
""")
    driver.chmod(0o755)
    r = subprocess.run(
        ["bash", str(driver)], capture_output=True, text=True, timeout=120
    )
    assert r.returncode == 0, r.stderr
    return r.stderr


def _labels_ready(tmp_path):
    f = tmp_path / "config" / "labels_ready"
    return f.read_text().strip() if f.exists() else None


def test_no_pending_marker_leaves_indicator_alone(tmp_path):
    """SKU that shipped a ui_tree archive: start-post already published it."""
    err = _publish(tmp_path)
    assert _labels_ready(tmp_path) is None
    assert "Labels data base is ready" not in err


def test_pending_marker_publishes_without_waiting(tmp_path):
    """Nothing left to drain: the indicator is published right away."""
    marker = tmp_path / ".hw-management-labels-pending"
    marker.touch()

    start = time.monotonic()
    err = _publish(tmp_path)
    elapsed = time.monotonic() - start

    assert _labels_ready(tmp_path) == "1"
    assert not marker.exists()
    assert "Labels data base is ready" in err
    # The dropped sleep 20 must not come back in any form.
    assert elapsed < 5


def test_publish_waits_for_maker_still_in_flight(tmp_path):
    """A maker spawned by the last check_n_link must finish before publishing."""
    marker = tmp_path / ".hw-management-labels-pending"
    marker.touch()
    maker = tmp_path / "hw-management-labels-maker-under-test.sh"
    maker.write_text("#!/bin/bash\nsleep 3\n")
    maker.chmod(0o755)

    proc = subprocess.Popen([str(maker)])
    try:
        start = time.monotonic()
        err = _publish(tmp_path, maker=maker.name)
        elapsed = time.monotonic() - start
    finally:
        proc.wait()

    assert _labels_ready(tmp_path) == "1"
    assert elapsed >= 2
    assert "ERR" not in err


def test_publish_gives_up_on_a_stuck_maker(tmp_path):
    """A maker that never exits must not hold the indicator back forever."""
    marker = tmp_path / ".hw-management-labels-pending"
    marker.touch()
    maker = tmp_path / "hw-management-labels-maker-stuck.sh"
    maker.write_text("#!/bin/bash\nsleep 60\n")
    maker.chmod(0o755)

    # Kill the whole group: the sleeper is a child of the wrapper, which has to
    # keep the maker name in its command line for pgrep -f to see it and so
    # cannot exec the sleeper in its own place.
    proc = subprocess.Popen([str(maker)], start_new_session=True)
    try:
        err = _publish(tmp_path, timeout=2, maker=maker.name)
    finally:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        proc.wait()

    assert _labels_ready(tmp_path) == "1"
    assert not marker.exists()
    assert "still being built" in err


def test_start_post_hands_the_indicator_over_to_the_monitor():
    start_post = (BIN / "hw-management-start-post.sh").read_text()
    monitor = (BIN / "hw-management-sysfs-monitor.sh").read_text()
    helpers = HELPERS.read_text()

    # The blind sleep and the script that held it are gone.
    assert not (BIN / "hw-management-label-init-complete.sh").exists()
    assert "hw-management-label-init-complete.sh" not in start_post

    # Archive branch publishes directly, run time branch defers to the monitor.
    archive_branch = start_post[
        start_post.index('if [ -e "$ui_tree_archive_file" ]'):
        start_post.index("# Check if TC service is enabled")
    ]
    assert 'echo 1 > "$config_path"/labels_ready' in archive_branch
    assert 'rm -f "$labels_pending_file"' in archive_branch
    assert 'echo 0 > "$config_path"/labels_ready' in archive_branch
    assert 'touch "$labels_pending_file"' in archive_branch

    # The monitor publishes once the tree settled, before it dumps the tree.
    assert monitor.index('echo "$current_time" > "$SYSFS_MONITOR_RDY_FILE"') < monitor.index(
        "publish_labels_ready"
    )
    assert monitor.index("publish_labels_ready") < monitor.index(
        "hw-mgmt-val.log"
    )

    # Marker lives outside $hw_management_path, which is removed on stop.
    assert 'labels_pending_file="/var/run/.hw-management-labels-pending"' in helpers
    assert helpers.index('tc_state_file="/var/run/.hw-management-tc-state"') < helpers.index(
        'labels_pending_file='
    )
