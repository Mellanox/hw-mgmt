#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#

"""Tests for hw-management-pmbus-device-dump.py"""

import sys
import subprocess
import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = (TESTS_DIR / ".." / "..").resolve()
sys.path.insert(0, str(PROJECT_ROOT / "usr" / "usr" / "bin"))

import importlib.util
_spec = importlib.util.spec_from_file_location(
    "pmbus_device_dump",
    str(PROJECT_ROOT / "usr" / "usr" / "bin" / "hw-management-pmbus-device-dump.py")
)
pmbus = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pmbus)


def _mock_run(stdout="", returncode=0, stderr=""):
    m = MagicMock()
    m.returncode = returncode
    m.stdout = stdout
    m.stderr = stderr
    return m


class TestI2cSetPage:
    """Tests for i2c_set_page()."""

    def test_returns_true_on_success(self):
        with patch("subprocess.run", return_value=_mock_run(returncode=0)):
            assert pmbus.i2c_set_page(1, 0x40, 0) is True

    def test_returns_false_on_failure(self):
        with patch("subprocess.run", return_value=_mock_run(returncode=1)):
            assert pmbus.i2c_set_page(1, 0x40, 0) is False

    def test_returns_false_on_exception(self):
        with patch("subprocess.run", side_effect=Exception("boom")):
            assert pmbus.i2c_set_page(1, 0x40, 0) is False

    def test_calls_i2cset(self):
        with patch("subprocess.run", return_value=_mock_run()) as mock_run:
            pmbus.i2c_set_page(3, 0x58, 2)
            cmd = mock_run.call_args[0][0]
            assert cmd[0] == "i2cset"
            assert "3" in cmd
            assert "0x58" in cmd
            assert "0x02" in cmd


class TestI2cReadByte:
    """Tests for i2c_read_byte()."""

    def test_success_returns_int(self):
        with patch("subprocess.run", return_value=_mock_run(stdout="0x42\n")):
            assert pmbus.i2c_read_byte(1, 0x40, 0x00) == 0x42

    def test_failure_returns_none(self):
        with patch("subprocess.run", return_value=_mock_run(returncode=1, stderr="err")):
            assert pmbus.i2c_read_byte(1, 0x40, 0x00) is None

    def test_file_not_found_exits(self):
        with patch("subprocess.run", side_effect=FileNotFoundError):
            with pytest.raises(SystemExit):
                pmbus.i2c_read_byte(1, 0x40, 0x00)

    def test_timeout_returns_none(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="i2cget", timeout=2)):
            assert pmbus.i2c_read_byte(1, 0x40, 0x00) is None

    def test_bad_hex_returns_none(self):
        with patch("subprocess.run", return_value=_mock_run(stdout="not_hex\n")):
            assert pmbus.i2c_read_byte(1, 0x40, 0x00) is None

    def test_calls_i2cget(self):
        with patch("subprocess.run", return_value=_mock_run(stdout="0x01\n")) as mock_run:
            pmbus.i2c_read_byte(5, 0x60, 0x20)
            cmd = mock_run.call_args[0][0]
            assert cmd[0] == "i2cget"
            assert "5" in cmd
            assert "0x60" in cmd
            assert "0x20" in cmd


class TestI2cReadWord:
    """Tests for i2c_read_word()."""

    def test_success_returns_int(self):
        with patch("subprocess.run", return_value=_mock_run(stdout="0x1234\n")):
            assert pmbus.i2c_read_word(1, 0x40, 0x21) == 0x1234

    def test_failure_returns_none(self):
        with patch("subprocess.run", return_value=_mock_run(returncode=1, stderr="err")):
            assert pmbus.i2c_read_word(1, 0x40, 0x21) is None

    def test_file_not_found_exits(self):
        with patch("subprocess.run", side_effect=FileNotFoundError):
            with pytest.raises(SystemExit):
                pmbus.i2c_read_word(1, 0x40, 0x21)

    def test_timeout_returns_none(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="i2cget", timeout=2)):
            assert pmbus.i2c_read_word(1, 0x40, 0x21) is None

    def test_bad_hex_returns_none(self):
        # "xyz" is not valid hex — raises ValueError which i2c_read_word catches
        with patch("subprocess.run", return_value=_mock_run(stdout="xyz\n")):
            assert pmbus.i2c_read_word(1, 0x40, 0x21) is None

    def test_calls_i2cget_with_w_flag(self):
        with patch("subprocess.run", return_value=_mock_run(stdout="0x0001\n")) as mock_run:
            pmbus.i2c_read_word(1, 0x40, 0x21)
            cmd = mock_run.call_args[0][0]
            assert "w" in cmd


class TestI2cReadBlock:
    """Tests for i2c_read_block()."""

    def test_success_parses_block(self):
        # First byte is length (3), then 3 data bytes
        with patch("subprocess.run", return_value=_mock_run(stdout="0x03 0x41 0x42 0x43\n")):
            result = pmbus.i2c_read_block(1, 0x40, 0x9a)
            assert result == [0x41, 0x42, 0x43]

    def test_failure_returns_none(self):
        with patch("subprocess.run", return_value=_mock_run(returncode=1, stderr="err")):
            assert pmbus.i2c_read_block(1, 0x40, 0x9a) is None

    def test_empty_output_returns_none(self):
        with patch("subprocess.run", return_value=_mock_run(stdout="\n")):
            assert pmbus.i2c_read_block(1, 0x40, 0x9a) is None

    def test_invalid_length_returns_none(self):
        # Length byte = 0xff (256) exceeds max 255 check... actually 0xff = 255, ok.
        # Use length 0x100... but that won't fit in hex byte output.
        # Instead test buffer underrun: length=5 but only 2 data bytes
        with patch("subprocess.run", return_value=_mock_run(stdout="0x05 0x41 0x42\n")):
            assert pmbus.i2c_read_block(1, 0x40, 0x9a) is None

    def test_file_not_found_exits(self):
        with patch("subprocess.run", side_effect=FileNotFoundError):
            with pytest.raises(SystemExit):
                pmbus.i2c_read_block(1, 0x40, 0x9a)

    def test_timeout_returns_none(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="i2cget", timeout=2)):
            assert pmbus.i2c_read_block(1, 0x40, 0x9a) is None

    def test_truncates_to_length_byte(self):
        # Length=2 but 4 extra bytes follow — only take 2
        with patch("subprocess.run", return_value=_mock_run(stdout="0x02 0xAA 0xBB 0xCC 0xDD\n")):
            result = pmbus.i2c_read_block(1, 0x40, 0x9a)
            assert result == [0xAA, 0xBB]


class TestDumpPmbusCommand:
    """Tests for dump_pmbus_command()."""

    def test_write_only_command_skipped(self):
        result = pmbus.dump_pmbus_command(1, 0x40, 0x03, "CLEAR_FAULTS", "send_byte", "w", 0)
        assert result["status"] == "write_only"
        assert result["raw"] is None

    def test_byte_read_success(self):
        with patch.object(pmbus, 'i2c_read_byte', return_value=0x42):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x00, "PAGE", "byte", "rw", 0)
            assert result["status"] == "success"
            assert result["raw"] == "0x42"

    def test_byte_read_failure(self):
        with patch.object(pmbus, 'i2c_read_byte', return_value=None):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x00, "PAGE", "byte", "rw", 0)
            assert result["status"] == "not_readable"

    def test_word_read_success(self):
        with patch.object(pmbus, 'i2c_read_word', return_value=0x1234):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x21, "VOUT_COMMAND", "word", "rw", 0)
            assert result["status"] == "success"
            assert result["raw"] == "0x1234"

    def test_word_read_failure(self):
        with patch.object(pmbus, 'i2c_read_word', return_value=None):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x21, "VOUT_COMMAND", "word", "rw", 0)
            assert result["status"] == "not_readable"

    def test_block_read_success_printable_ascii(self):
        with patch.object(pmbus, 'i2c_read_block', return_value=[0x41, 0x42, 0x43]):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x9a, "MFR_MODEL", "block", "r", 0)
            assert result["status"] == "success"
            assert "ABC" in result["formatted"]

    def test_block_read_success_non_printable(self):
        with patch.object(pmbus, 'i2c_read_block', return_value=[0x01, 0x02, 0x03]):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x9a, "MFR_MODEL", "block", "r", 0)
            assert result["status"] == "success"
            assert "." in result["formatted"]

    def test_block_read_failure(self):
        with patch.object(pmbus, 'i2c_read_block', return_value=None):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x9a, "MFR_MODEL", "block", "r", 0)
            assert result["status"] == "not_readable"

    def test_result_contains_expected_fields(self):
        with patch.object(pmbus, 'i2c_read_byte', return_value=0):
            result = pmbus.dump_pmbus_command(1, 0x40, 0x00, "PAGE", "byte", "rw", 0)
            for field in ("page", "command", "name", "type", "access", "status"):
                assert field in result


class TestPmbusCommandsDict:
    """Verify the PMBUS_COMMANDS table is sane."""

    def test_page_command_exists(self):
        assert 0x00 in pmbus.PMBUS_COMMANDS
        name, dtype, rw = pmbus.PMBUS_COMMANDS[0x00]
        assert name == "PAGE"

    def test_all_entries_have_three_fields(self):
        for code, entry in pmbus.PMBUS_COMMANDS.items():
            assert len(entry) == 3, f"Command 0x{code:02X} has wrong number of fields"

    def test_rw_field_is_valid(self):
        valid = {"r", "w", "rw"}
        for code, entry in pmbus.PMBUS_COMMANDS.items():
            assert entry[2] in valid, f"Command 0x{code:02X} has invalid rw={entry[2]!r}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
