#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Every script that a host unit runs must send its stdout and stderr to syslog.
# The journal keeps them under the unit name. The redirect adds the syslog copy
# with the tag hw-management. A unit script without the redirect loses that copy.
#
# Verifies: each ExecStart and ExecStartPre script of debian/*.service that is in
# this tree calls the redirect. A script that logs only through the helper logging
# functions is listed in LOGGER_ONLY with the reason, and must still use them.

import re
from pathlib import Path

import pytest

pytestmark = pytest.mark.offline

ROOT = Path(__file__).resolve().parents[2]
DEBIAN = ROOT / "debian"
SCRIPT_DIRS = [ROOT / "usr" / "usr" / "bin", ROOT / "usr" / "usr" / "local" / "bin"]

EXEC_RE = re.compile(r"^(?:ExecStart|ExecStartPre)=(.*)$")
PATH_RE = re.compile(r"/usr/(?:local/)?s?bin/([A-Za-z0-9_.-]+)")
REDIRECT_RE = re.compile(
    r"\blog_redirect_std_to_syslog\b"
    r"|\bredirect_std_to_syslog\s*\("
    r"|tee >\(logger -t hw-management"
)
LOGGER_RE = re.compile(r"\blogger\b|\blog_(?:info|err)\b")

# Unit scripts that log only through the helper functions, which call logger.
# An entry applies only where a unit in the tree runs the script.
LOGGER_ONLY = {
    "hw-management-ifupdown.sh": "logs through log_info and log_err from the helpers",
    "hw-management-bmc-login.sh": "logs through log_info and log_err from the helpers",
}


def _unit_scripts():
    """Map each script run by a host unit to the unit files that run it."""
    found = {}
    for unit in sorted(DEBIAN.glob("*.service")):
        for line in unit.read_text().splitlines():
            m = EXEC_RE.match(line.strip())
            if not m:
                continue
            for name in PATH_RE.findall(m.group(1)):
                found.setdefault(name, set()).add(unit.name)
    scripts = {}
    for name, units in found.items():
        for script_dir in SCRIPT_DIRS:
            path = script_dir / name
            if path.is_file():
                scripts[name] = (path, sorted(units))
                break
    return scripts


UNIT_SCRIPTS = _unit_scripts()


def test_unit_scripts_are_found():
    """The unit files must resolve to scripts, or the checks below pass vacuously."""
    assert len(UNIT_SCRIPTS) >= 8, sorted(UNIT_SCRIPTS)


@pytest.mark.parametrize("name", sorted(UNIT_SCRIPTS))
def test_unit_script_sends_output_to_syslog(name):
    path, units = UNIT_SCRIPTS[name]
    text = path.read_text(errors="replace")
    if name in LOGGER_ONLY:
        assert "hw-management-helpers.sh" in text, f"{name} does not load the helpers"
        assert LOGGER_RE.search(text), (
            f"{name} is listed in LOGGER_ONLY ({LOGGER_ONLY[name]}) but does not log"
        )
        return
    assert REDIRECT_RE.search(text), (
        f"{name} (run by {', '.join(units)}) does not redirect stdout and stderr to syslog. "
        "Call log_redirect_std_to_syslog, or add it to LOGGER_ONLY with a reason."
    )
