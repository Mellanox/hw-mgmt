#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# hw_management_tc_launcher.sh selects the thermal control binary from
# tc_version in tc_config.json, writes the version into the unit Description,
# and execs the binary. systemctl and logger are stubbed so the real unit on
# the host is never touched.

import stat
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.offline

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "usr" / "usr" / "bin" / "hw_management_tc_launcher.sh"
UNIT = ROOT / "debian" / "hw-management.hw-management-tc.service"

DEFAULT_DESC = "Thermal control service (ver 2.0) of Nvidia systems"

FAKE_SYSTEMCTL = """#!/bin/sh
case "$1" in
	show) echo "FragmentPath=$UNIT_PATH" ;;
	daemon-reload) echo reload >> "$RELOAD_LOG" ;;
esac
exit 0
"""


def _run(tc_config_content, tmp_path, initial_desc=DEFAULT_DESC, unit_path=None, args=()):
    """Run a copy of the launcher. Return (stdout, final_description, reload_count)."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    bin20 = tmp_path / "tc20"
    bin25 = tmp_path / "tc25"
    # VERSION inside the scripts must not leak into the description.
    bin20.write_text('#!/bin/sh\nVERSION="2.1.1"\nprintf \'2_0\\n\'\n')
    bin25.write_text('#!/bin/sh\nVERSION="2.5.1"\nprintf \'2_5\\n\'\n')
    bin20.chmod(0o755)
    bin25.chmod(0o755)

    unit = tmp_path / "hw-management-tc.service"
    unit.write_text(f"[Unit]\nDescription={initial_desc}\nAfter=hw-management.service\n")
    reload_log = tmp_path / "reloads"

    systemctl = bindir / "systemctl"
    systemctl.write_text(FAKE_SYSTEMCTL)
    systemctl.chmod(0o755)
    logger = bindir / "logger"
    logger.write_text("#!/bin/sh\nexit 0\n")
    logger.chmod(0o755)

    if tc_config_content is None:
        cfg_path = tmp_path / "missing.json"
    else:
        cfg_path = tmp_path / "tc_config.json"
        cfg_path.write_text(tc_config_content)

    script = LAUNCHER.read_text()
    script = script.replace("/usr/bin/hw_management_thermal_control_2_5.py", str(bin25))
    script = script.replace("/usr/bin/hw_management_thermal_control.py", str(bin20))
    script = script.replace("/var/run/hw-management/config/tc_config.json", str(cfg_path))
    path = tmp_path / "launcher.sh"
    path.write_text(script)
    path.chmod(0o755)

    env = {
        "PATH": f"{bindir}:/usr/bin:/bin",
        "UNIT_PATH": str(unit_path if unit_path is not None else unit),
        "RELOAD_LOG": str(reload_log),
    }
    r = subprocess.run(
        [str(path)] + list(args),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        timeout=5,
    )
    assert r.returncode == 0, r.stderr

    desc = [l for l in unit.read_text().splitlines() if l.startswith("Description=")][0]
    reloads = reload_log.read_text().count("reload") if reload_log.exists() else 0
    return r.stdout.strip(), desc, reloads


def test_launcher_is_executable():
    assert LAUNCHER.stat().st_mode & stat.S_IXUSR


def test_launcher_execs_and_does_not_patch_execstart():
    text = LAUNCHER.read_text()
    assert "\nexec " in text
    assert "sed -i \"s/^ExecStart" not in text


def test_launcher_selects_v25(tmp_path):
    out, _, _ = _run('{"tc_version": "2.5"}\n', tmp_path)
    assert out == "2_5"


def test_launcher_selects_v25_subversion(tmp_path):
    out, _, _ = _run('{"tc_version": "2.5.1"}\n', tmp_path)
    assert out == "2_5"


def test_launcher_selects_v20(tmp_path):
    out, _, _ = _run('{"tc_version": "2.0"}\n', tmp_path)
    assert out == "2_0"


def test_launcher_defaults_to_v20_when_config_missing(tmp_path):
    out, desc, _ = _run(None, tmp_path)
    assert out == "2_0"
    assert desc == f"Description={DEFAULT_DESC}"


def test_launcher_defaults_to_v20_for_unknown_version(tmp_path):
    out, _, _ = _run('{"tc_version": "3.0"}\n', tmp_path)
    assert out == "2_0"


def test_description_shows_v25_major_minor(tmp_path):
    _, desc, reloads = _run('{"tc_version": "2.5"}\n', tmp_path)
    assert desc == "Description=Thermal control service (ver 2.5) of Nvidia systems"
    assert reloads == 1


def test_description_subversion_shows_v25(tmp_path):
    _, desc, _ = _run('{"tc_version": "2.5.1"}\n', tmp_path)
    assert desc == "Description=Thermal control service (ver 2.5) of Nvidia systems"


def test_description_unknown_version_shows_v20(tmp_path):
    _, desc, reloads = _run('{"tc_version": "3.0"}\n', tmp_path)
    assert desc == f"Description={DEFAULT_DESC}"
    assert reloads == 0


def test_description_unchanged_skips_reload(tmp_path):
    _, desc, reloads = _run(
        '{"tc_version": "2.0"}\n',
        tmp_path,
        initial_desc="Thermal control service (ver 2.0) of Nvidia systems",
    )
    assert desc == f"Description={DEFAULT_DESC}"
    assert reloads == 0


def test_description_follows_family_change(tmp_path):
    _, desc, reloads = _run(
        '{"tc_version": "2.5"}\n',
        tmp_path,
        initial_desc="Thermal control service (ver 2.0) of Nvidia systems",
    )
    assert desc == "Description=Thermal control service (ver 2.5) of Nvidia systems"
    assert reloads == 1


def test_describe_updates_version_without_starting(tmp_path):
    """--describe is what start-post runs while TC is still stopped."""
    out, desc, reloads = _run('{"tc_version": "2.5"}\n', tmp_path, args=("--describe",))
    assert out == ""
    assert desc == "Description=Thermal control service (ver 2.5) of Nvidia systems"
    assert reloads == 1


def test_missing_unit_path_still_execs(tmp_path):
    out, _, reloads = _run(
        '{"tc_version": "2.5"}\n', tmp_path, unit_path=tmp_path / "absent.service"
    )
    assert out == "2_5"
    assert reloads == 0


def test_service_description_carries_version():
    unit = UNIT.read_text()
    assert f"Description={DEFAULT_DESC}" in unit
    assert "ExecStart=/usr/bin/hw_management_tc_launcher.sh" in unit
    assert "hw_management_thermal_control.py" not in unit


def test_rpm_spec_packages_launcher():
    text = (ROOT / "rpm" / "hw-management.spec").read_text()
    assert "usr/usr/bin/hw_management_tc_launcher.sh" in text
    assert '"/usr/bin/hw_management_tc_launcher.sh"' in text
