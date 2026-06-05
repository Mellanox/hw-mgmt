#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-boot-complete.sh."""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

SCRIPT = str(BMC_SCRIPTS_DIR / "hw-management-bmc-boot-complete.sh")


def _run_boot_complete(tmp_path, sys_entries=0, thr_entries=0, eep_entries=0,
                       need_sys=1, need_thr=1, need_eep=1,
                       max_wait=1, poll=1, conf_missing=False, var_missing=None):
    sys_dir = tmp_path / "system"
    thr_dir = tmp_path / "thermal"
    eep_dir = tmp_path / "eeprom"
    sys_dir.mkdir()
    thr_dir.mkdir()
    eep_dir.mkdir()

    for i in range(sys_entries):
        (sys_dir / f"entry{i}").write_text("")
    for i in range(thr_entries):
        (thr_dir / f"entry{i}").write_text("")
    for i in range(eep_entries):
        (eep_dir / f"entry{i}").write_text("")

    conf_path = tmp_path / "boot-complete.conf"
    if not conf_missing:
        lines = []
        if var_missing != "SYSFS_SYSTEM_COUNTER":
            lines.append(f"SYSFS_SYSTEM_COUNTER={need_sys}")
        if var_missing != "SYSFS_THERMAL_COUNTER":
            lines.append(f"SYSFS_THERMAL_COUNTER={need_thr}")
        if var_missing != "SYSFS_EEPROM_COUNTER":
            lines.append(f"SYSFS_EEPROM_COUNTER={need_eep}")
        lines.append(f"BOOT_COMPLETE_MAX_WAIT_SEC={max_wait}")
        lines.append(f"BOOT_COMPLETE_POLL_SEC={poll}")
        conf_path.write_text("\n".join(lines) + "\n")

    # Wrap the script, overriding hardcoded dirs via a sourced override file
    wrapper = f"""
SYS_DIR="{sys_dir}"
THERMAL_DIR="{thr_dir}"
EEPROM_DIR="{eep_dir}"
BOOT_COMPLETE_CONF="{conf_path}"

count_entries() {{
    _d="$1"
    if [ ! -d "$_d" ]; then echo 0; return; fi
    ls -A "$_d" 2>/dev/null | wc -l
}}

if [ ! -f "$BOOT_COMPLETE_CONF" ]; then
    echo "hw-management-bmc-boot-complete: missing $BOOT_COMPLETE_CONF" >&2
    exit 1
fi
. "$BOOT_COMPLETE_CONF"

: "${{SYSFS_SYSTEM_COUNTER:?SYSFS_SYSTEM_COUNTER missing in $BOOT_COMPLETE_CONF}}"
: "${{SYSFS_THERMAL_COUNTER:?SYSFS_THERMAL_COUNTER missing in $BOOT_COMPLETE_CONF}}"
: "${{SYSFS_EEPROM_COUNTER:?SYSFS_EEPROM_COUNTER missing in $BOOT_COMPLETE_CONF}}"

need_sys=$SYSFS_SYSTEM_COUNTER
need_thr=$SYSFS_THERMAL_COUNTER
need_eep=$SYSFS_EEPROM_COUNTER
max_wait=${{BOOT_COMPLETE_MAX_WAIT_SEC:-1800}}
poll=${{BOOT_COMPLETE_POLL_SEC:-2}}

elapsed=0
while :; do
    c_sys=$(count_entries "$SYS_DIR")
    c_thr=$(count_entries "$THERMAL_DIR")
    c_eep=$(count_entries "$EEPROM_DIR")

    if [ "$c_sys" -ge "$need_sys" ] && [ "$c_thr" -ge "$need_thr" ] && [ "$c_eep" -ge "$need_eep" ]; then
        echo "hw-management-bmc-boot-complete: thresholds met" >&2
        exit 0
    fi

    if [ "$max_wait" -gt 0 ] && [ "$elapsed" -ge "$max_wait" ]; then
        echo "hw-management-bmc-boot-complete: timeout after ${{max_wait}}s" >&2
        exit 1
    fi

    if [ "$max_wait" -eq 0 ]; then
        echo "hw-management-bmc-boot-complete: no limit" >&2
        exit 0
    fi

    sleep "$poll" 2>/dev/null || true
    elapsed=$((elapsed + poll))
done
"""
    return subprocess.run(
        ["bash", "-c", wrapper],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, timeout=15,
    )


class TestBootCompleteThresholdsMet:
    def test_all_thresholds_met_exits_zero(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=2, thr_entries=2, eep_entries=2,
                               need_sys=2, need_thr=2, need_eep=2)
        assert r.returncode == 0

    def test_exact_threshold_exits_zero(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=1, thr_entries=1, eep_entries=1,
                               need_sys=1, need_thr=1, need_eep=1)
        assert r.returncode == 0

    def test_success_message_in_stderr(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=1, thr_entries=1, eep_entries=1,
                               need_sys=1, need_thr=1, need_eep=1)
        assert "thresholds met" in r.stderr

    def test_more_than_threshold_also_passes(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=5, thr_entries=5, eep_entries=5,
                               need_sys=1, need_thr=1, need_eep=1)
        assert r.returncode == 0


class TestBootCompleteTimeout:
    def test_empty_dirs_timeout_exits_nonzero(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=0, thr_entries=0, eep_entries=0,
                               need_sys=1, need_thr=1, need_eep=1,
                               max_wait=1, poll=1)
        assert r.returncode == 1

    def test_timeout_message_in_stderr(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=0, thr_entries=0, eep_entries=0,
                               need_sys=1, need_thr=1, need_eep=1,
                               max_wait=1, poll=1)
        assert "timeout" in r.stderr

    def test_partial_dirs_timeout(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=1, thr_entries=0, eep_entries=1,
                               need_sys=1, need_thr=1, need_eep=1,
                               max_wait=1, poll=1)
        assert r.returncode == 1


class TestBootCompleteMissingConf:
    def test_missing_conf_exits_nonzero(self, tmp_path):
        r = _run_boot_complete(tmp_path, conf_missing=True)
        assert r.returncode == 1

    def test_missing_conf_error_in_stderr(self, tmp_path):
        r = _run_boot_complete(tmp_path, conf_missing=True)
        assert "missing" in r.stderr


class TestBootCompleteMissingVar:
    def test_missing_system_counter_exits_nonzero(self, tmp_path):
        r = _run_boot_complete(tmp_path, var_missing="SYSFS_SYSTEM_COUNTER",
                               max_wait=1, poll=1)
        assert r.returncode != 0

    def test_missing_thermal_counter_exits_nonzero(self, tmp_path):
        r = _run_boot_complete(tmp_path, var_missing="SYSFS_THERMAL_COUNTER",
                               max_wait=1, poll=1)
        assert r.returncode != 0


class TestBootCompleteUnlimitedWait:
    def test_max_wait_zero_shows_no_limit(self, tmp_path):
        r = _run_boot_complete(tmp_path, sys_entries=0, thr_entries=0, eep_entries=0,
                               need_sys=1, need_thr=1, need_eep=1,
                               max_wait=0, poll=1)
        assert "no limit" in r.stderr or r.returncode == 0
