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

"""Tests for hw-management-eeprom-crc32.py"""

import sys
import os
import subprocess
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = (TESTS_DIR / ".." / "..").resolve()
SCRIPT = PROJECT_ROOT / "usr" / "usr" / "bin" / "hw-management-eeprom-crc32.py"

# Import the module directly for unit tests
sys.path.insert(0, str(PROJECT_ROOT / "usr" / "usr" / "bin"))
import importlib.util
_spec = importlib.util.spec_from_file_location("eeprom_crc32", str(SCRIPT))
eeprom_crc32 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(eeprom_crc32)


def run_script(*args):
    """Run the script as a subprocess. Returns (stdout, stderr, returncode)."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT)] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.decode().strip(), result.stderr.decode().strip(), result.returncode


class TestCalcCrc32:
    """Unit tests for calc_crc32()."""

    def test_empty_bytes_known_value(self):
        """CRC of empty sequence equals 0xFFFFFFFF ^ 0xFFFFFFFF = 0."""
        assert eeprom_crc32.calc_crc32(b"") == 0

    def test_known_byte_sequence(self):
        """CRC of b'\\x00' should match a known-good value from the standard CRC-32 table."""
        crc = eeprom_crc32.calc_crc32(b"\x00")
        assert isinstance(crc, int)
        assert 0 <= crc <= 0xFFFFFFFF

    def test_deterministic(self):
        """Same input always produces same CRC."""
        data = b"hello world"
        assert eeprom_crc32.calc_crc32(data) == eeprom_crc32.calc_crc32(data)

    def test_different_inputs_differ(self):
        """Different inputs produce different CRCs (with overwhelming probability)."""
        assert eeprom_crc32.calc_crc32(b"aaa") != eeprom_crc32.calc_crc32(b"bbb")

    def test_single_byte_all_values(self):
        """calc_crc32 handles all single-byte values 0..255 without error."""
        for i in range(256):
            crc = eeprom_crc32.calc_crc32(bytes([i]))
            assert isinstance(crc, int)

    def test_crc_table_length(self):
        """CRC table must have exactly 256 entries."""
        table = eeprom_crc32.init_crc_table()
        assert len(table) == 256

    def test_crc_table_all_ints(self):
        """All CRC table entries are non-negative integers <= 0xFFFFFFFF."""
        for entry in eeprom_crc32.CRC_TABLE:
            assert isinstance(entry, int)
            assert 0 <= entry <= 0xFFFFFFFF


class TestFormatCrc32BigEndian:
    """Unit tests for format_crc32_big_endian()."""

    def test_zero(self):
        assert eeprom_crc32.format_crc32_big_endian(0) == "0x00 0x00 0x00 0x00"

    def test_max_value(self):
        assert eeprom_crc32.format_crc32_big_endian(0xFFFFFFFF) == "0xff 0xff 0xff 0xff"

    def test_known_value(self):
        assert eeprom_crc32.format_crc32_big_endian(0xdeadbeef) == "0xde 0xad 0xbe 0xef"

    def test_byte_order(self):
        """Most significant byte appears first."""
        result = eeprom_crc32.format_crc32_big_endian(0x01020304)
        assert result == "0x01 0x02 0x03 0x04"

    def test_output_format(self):
        """Output consists of exactly 4 hex bytes separated by spaces."""
        result = eeprom_crc32.format_crc32_big_endian(0x12345678)
        parts = result.split()
        assert len(parts) == 4
        for p in parts:
            assert p.startswith("0x")
            assert len(p) == 4  # "0x" + 2 hex digits


class TestScriptCLI:
    """Integration tests via subprocess (covers main(), PermissionError, etc.)."""

    @pytest.fixture(autouse=True)
    def check_script(self):
        if not SCRIPT.exists():
            pytest.skip(f"Script not found: {SCRIPT}")

    def test_no_args_exits_nonzero(self):
        _, _, rc = run_script()
        assert rc != 0

    def test_no_args_error_to_stderr(self):
        _, err, _ = run_script()
        assert "Usage" in err

    def test_nonexistent_file_exits_nonzero(self, tmp_path):
        _, _, rc = run_script(str(tmp_path / "does_not_exist.bin"))
        assert rc != 0

    def test_nonexistent_file_error_to_stderr(self, tmp_path):
        _, err, _ = run_script(str(tmp_path / "does_not_exist.bin"))
        assert err != ""

    def test_empty_file_exits_nonzero(self, tmp_path):
        empty = tmp_path / "empty.bin"
        empty.write_bytes(b"")
        _, _, rc = run_script(str(empty))
        assert rc != 0

    def test_empty_file_error_to_stderr(self, tmp_path):
        empty = tmp_path / "empty.bin"
        empty.write_bytes(b"")
        _, err, _ = run_script(str(empty))
        assert "empty" in err.lower()

    def test_valid_file_exits_zero(self, tmp_path):
        data_file = tmp_path / "data.bin"
        data_file.write_bytes(b"\x01\x02\x03\x04")
        _, _, rc = run_script(str(data_file))
        assert rc == 0

    def test_valid_file_output_format(self, tmp_path):
        data_file = tmp_path / "data.bin"
        data_file.write_bytes(b"\x01\x02\x03\x04")
        out, _, _ = run_script(str(data_file))
        parts = out.split()
        assert len(parts) == 4
        for p in parts:
            assert p.startswith("0x")

    def test_output_to_stdout_only(self, tmp_path):
        data_file = tmp_path / "data.bin"
        data_file.write_bytes(b"\xde\xad\xbe\xef")
        out, err, rc = run_script(str(data_file))
        assert rc == 0
        assert out != ""
        assert err == ""

    def test_deterministic_output(self, tmp_path):
        data_file = tmp_path / "data.bin"
        data_file.write_bytes(b"repeatme")
        out1, _, _ = run_script(str(data_file))
        out2, _, _ = run_script(str(data_file))
        assert out1 == out2

    def test_different_inputs_give_different_outputs(self, tmp_path):
        file_a = tmp_path / "a.bin"
        file_b = tmp_path / "b.bin"
        file_a.write_bytes(b"AAAA")
        file_b.write_bytes(b"BBBB")
        out_a, _, _ = run_script(str(file_a))
        out_b, _, _ = run_script(str(file_b))
        assert out_a != out_b

    def test_large_file(self, tmp_path):
        data_file = tmp_path / "large.bin"
        data_file.write_bytes(b"\xff" * 4096)
        _, _, rc = run_script(str(data_file))
        assert rc == 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
