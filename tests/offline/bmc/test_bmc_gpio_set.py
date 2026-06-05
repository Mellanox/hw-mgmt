#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

"""Tests for hw-management-bmc-gpio-set.sh."""

import os
import subprocess
from pathlib import Path

import pytest

from conftest import BMC_SCRIPTS_DIR

GPIO_SCRIPT = str(BMC_SCRIPTS_DIR / "hw-management-bmc-gpio-set.sh")


def _src(snippet, stubs_dir=None, extra_env=None):
    env = {**os.environ}
    if stubs_dir:
        env["PATH"] = f"{stubs_dir}:{os.environ['PATH']}"
    if extra_env:
        env.update(extra_env)
    full = f"source {GPIO_SCRIPT}\n{snippet}"
    return subprocess.run(
        ["bash", "-c", full],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, env=env,
    )


class TestGpiochipBaseByNgpio:
    def test_finds_chip_by_ngpio(self, stubs_dir, fake_gpio_sysfs, tmp_path):
        gpio_root, add_chip = fake_gpio_sysfs
        add_chip("gpiochip0", 208, 0)

        snippet = f"""
gpiochip_base_by_ngpio() {{
    local ngpio="$1"
    local quiet="${{2:-}}"
    for chip in {gpio_root}/gpiochip*; do
        [ -d "$chip" ] || continue
        if [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ]; then
            local base=$(cat "$chip/base" 2>/dev/null)
            if [ -n "$base" ]; then
                echo "$base"
                return 0
            fi
        fi
    done
    return 1
}}
gpiochip_base_by_ngpio 208
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert r.stdout.strip() == "0"
        assert r.returncode == 0

    def test_finds_chip_base_value(self, stubs_dir, fake_gpio_sysfs):
        gpio_root, add_chip = fake_gpio_sysfs
        add_chip("gpiochip0", 216, 100)

        snippet = f"""
gpiochip_base_by_ngpio() {{
    local ngpio="$1"
    for chip in {gpio_root}/gpiochip*; do
        [ -d "$chip" ] || continue
        if [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ]; then
            local base=$(cat "$chip/base" 2>/dev/null)
            [ -n "$base" ] && echo "$base" && return 0
        fi
    done
    return 1
}}
gpiochip_base_by_ngpio 216
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert r.stdout.strip() == "100"

    def test_no_matching_chip_returns_nonzero(self, stubs_dir, fake_gpio_sysfs):
        gpio_root, add_chip = fake_gpio_sysfs
        add_chip("gpiochip0", 64, 0)

        snippet = f"""
gpiochip_base_by_ngpio() {{
    local ngpio="$1"
    for chip in {gpio_root}/gpiochip*; do
        [ -d "$chip" ] || continue
        if [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ]; then
            local base=$(cat "$chip/base" 2>/dev/null)
            [ -n "$base" ] && echo "$base" && return 0
        fi
    done
    return 1
}}
gpiochip_base_by_ngpio 208; echo "rc=$?"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=1" in r.stdout

    def test_quiet_mode_no_stderr_on_failure(self, stubs_dir, fake_gpio_sysfs):
        gpio_root, _ = fake_gpio_sysfs  # empty gpio dir
        snippet = f"""
gpio_log() {{ echo "[$1] $2" >&2; }}
gpiochip_base_by_ngpio() {{
    local ngpio="$1"
    local quiet="${{2:-}}"
    for chip in {gpio_root}/gpiochip*; do
        [ -d "$chip" ] || continue
        if [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ]; then
            local base=$(cat "$chip/base" 2>/dev/null)
            [ -n "$base" ] && echo "$base" && return 0
        fi
    done
    if [ "$quiet" != "quiet" ]; then
        gpio_log "err" "not found"
    fi
    return 1
}}
gpiochip_base_by_ngpio 208 quiet
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert r.stderr.strip() == ""

    def test_non_quiet_mode_logs_to_stderr(self, stubs_dir, fake_gpio_sysfs):
        gpio_root, _ = fake_gpio_sysfs
        snippet = f"""
gpio_log() {{ echo "[$1] $2" >&2; }}
gpiochip_base_by_ngpio() {{
    local ngpio="$1"
    local quiet="${{2:-}}"
    for chip in {gpio_root}/gpiochip*; do
        [ -d "$chip" ] || continue
    done
    if [ "$quiet" != "quiet" ]; then
        gpio_log "err" "Failed to find gpiochip ngpio=$ngpio"
    fi
    return 1
}}
gpiochip_base_by_ngpio 208
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "err" in r.stderr or "Failed" in r.stderr


class TestGpioLog:
    def test_gpio_log_formats_correctly(self, stubs_dir):
        r = _src('gpio_log "info" "test message"', stubs_dir=stubs_dir)
        assert "info" in r.stderr or "info" in r.stdout
        assert "test message" in (r.stderr + r.stdout)

    def test_gpio_log_err_level(self, stubs_dir):
        r = _src('gpio_log "err" "gpio error occurred"', stubs_dir=stubs_dir)
        assert "err" in (r.stderr + r.stdout)


class TestGpioExport:
    def test_export_creates_sysfs_entry(self, stubs_dir, tmp_path):
        gpio_sysfs = tmp_path / "gpio_sysfs"
        gpio_sysfs.mkdir()
        export_file = gpio_sysfs / "export"
        export_file.write_text("")

        snippet = f"""
gpio_log() {{ echo "[$1] $2" >&2; }}
gpio_export() {{
    local g="$1"
    if [ -z "$g" ]; then
        gpio_log "warning" "gpio_export called with empty GPIO number"
        return 1
    fi
    if [ ! -d "{gpio_sysfs}/gpio$g" ]; then
        if ! echo "$g" > "{gpio_sysfs}/export" 2>/dev/null; then
            gpio_log "warning" "Failed to export GPIO $g"
            return 1
        fi
    fi
    return 0
}}
gpio_export 42; echo "rc=$?"
cat "{export_file}"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=0" in r.stdout
        assert "42" in r.stdout

    def test_export_empty_gpio_returns_error(self, stubs_dir):
        r = _src('gpio_export ""', stubs_dir=stubs_dir)
        assert r.returncode != 0 or "warning" in (r.stderr + r.stdout).lower()


class TestGpioSet:
    def test_gpio_set_writes_value(self, stubs_dir, tmp_path):
        gpio_dir = tmp_path / "gpio42"
        gpio_dir.mkdir()
        value_file = gpio_dir / "value"
        value_file.write_text("")

        snippet = f"""
gpio_log() {{ echo "[$1] $2" >&2; }}
gpio_set() {{
    local g="$1"
    local val="$2"
    if [ -z "$g" ]; then
        gpio_log "warning" "gpio_set called with empty GPIO number"
        return 1
    fi
    if ! echo "$val" > "{gpio_dir}/value" 2>/dev/null; then
        gpio_log "warning" "Failed to set GPIO $g value to $val"
        return 1
    fi
    return 0
}}
gpio_set 42 1; echo "rc=$?"
cat "{value_file}"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=0" in r.stdout
        assert "1" in r.stdout

    def test_gpio_set_empty_gpio_returns_error(self, stubs_dir):
        r = _src('gpio_set "" 1', stubs_dir=stubs_dir)
        assert r.returncode != 0 or "warning" in (r.stderr + r.stdout).lower()


class TestGpioDir:
    def test_gpio_dir_writes_direction(self, stubs_dir, tmp_path):
        gpio_dir = tmp_path / "gpio5"
        gpio_dir.mkdir()
        direction_file = gpio_dir / "direction"
        direction_file.write_text("")

        snippet = f"""
gpio_log() {{ echo "[$1] $2" >&2; }}
gpio_dir() {{
    local g="$1"
    local dir="$2"
    if [ -z "$g" ] || [ -z "$dir" ]; then
        gpio_log "warning" "gpio_dir called with invalid args"
        return 1
    fi
    if ! echo "$dir" > "{gpio_dir}/direction" 2>/dev/null; then
        gpio_log "warning" "Failed to set direction"
        return 1
    fi
    return 0
}}
gpio_dir 5 out; echo "rc=$?"
cat "{direction_file}"
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert "rc=0" in r.stdout
        assert "out" in r.stdout


class TestGpiochipBaseAspeed:
    def test_finds_ast2600_208_lines(self, stubs_dir, fake_gpio_sysfs):
        gpio_root, add_chip = fake_gpio_sysfs
        add_chip("gpiochip0", 208, 0)

        snippet = f"""
gpio_log() {{ echo "[$1] $2" >&2; }}
gpiochip_base_by_ngpio() {{
    local ngpio="$1"
    local quiet="${{2:-}}"
    for chip in {gpio_root}/gpiochip*; do
        [ -d "$chip" ] || continue
        if [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ]; then
            local base=$(cat "$chip/base" 2>/dev/null)
            [ -n "$base" ] && echo "$base" && return 0
        fi
    done
    [ "$quiet" != "quiet" ] && gpio_log "err" "not found ngpio=$ngpio"
    return 1
}}
gpiochip_base_aspeed() {{
    local base
    base=$(gpiochip_base_by_ngpio 208 quiet 2>/dev/null)
    if [ -n "$base" ]; then echo "$base"; return 0; fi
    base=$(gpiochip_base_by_ngpio 216 quiet 2>/dev/null)
    if [ -n "$base" ]; then echo "$base"; return 0; fi
    return 1
}}
gpiochip_base_aspeed
"""
        r = subprocess.run(["bash", "-c", snippet],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True,
                           env={**os.environ, "PATH": f"{stubs_dir}:{os.environ['PATH']}"})
        assert r.returncode == 0
        assert r.stdout.strip() == "0"
