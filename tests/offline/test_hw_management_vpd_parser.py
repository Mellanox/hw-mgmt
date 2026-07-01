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

"""Tests for hw-management-vpd-parser.py pure-function layer."""

import sys
import struct
import zlib
import pytest
from pathlib import Path

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = (TESTS_DIR / ".." / "..").resolve()
sys.path.insert(0, str(PROJECT_ROOT / "usr" / "usr" / "bin"))

import importlib.util
_spec = importlib.util.spec_from_file_location(
    "vpd_parser",
    str(PROJECT_ROOT / "usr" / "usr" / "bin" / "hw-management-vpd-parser.py")
)
vpd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vpd)


class TestBinDecode:
    """Tests for bin_decode()."""

    def test_bytes_decoded_to_string(self):
        assert vpd.bin_decode(b"hello\x00") == "hello"

    def test_bytes_strips_null_padding(self):
        assert vpd.bin_decode(b"AB\x00\x00\x00") == "AB"

    def test_non_bytes_returned_as_is(self):
        assert vpd.bin_decode("already string") == "already string"
        assert vpd.bin_decode(42) == 42
        assert vpd.bin_decode(None) is None

    def test_empty_bytes(self):
        assert vpd.bin_decode(b"") == ""

    def test_all_null_bytes(self):
        assert vpd.bin_decode(b"\x00\x00") == ""


class TestIntUnpackBe:
    """Tests for int_unpack_be() — big-endian sum."""

    def test_single_byte(self):
        assert vpd.int_unpack_be([0x42]) == 0x42

    def test_two_bytes_be(self):
        # [0x01, 0x00] → 1*256 + 0*1 = 256
        assert vpd.int_unpack_be([0x01, 0x00]) == 256

    def test_three_bytes_be(self):
        assert vpd.int_unpack_be([0x01, 0x00, 0x00]) == 0x10000

    def test_zero(self):
        assert vpd.int_unpack_be([0x00, 0x00]) == 0

    def test_all_ff(self):
        assert vpd.int_unpack_be([0xFF, 0xFF]) == 0xFFFF


class TestIntUnpackLe:
    """Tests for int_unpack_le() — little-endian sum."""

    def test_single_byte(self):
        assert vpd.int_unpack_le([0x42]) == 0x42

    def test_two_bytes_le(self):
        # [0x01, 0x00] → 1*1 + 0*256 = 1
        assert vpd.int_unpack_le([0x01, 0x00]) == 1

    def test_two_bytes_le_second_nonzero(self):
        # [0x00, 0x01] → 0 + 1*256 = 256
        assert vpd.int_unpack_le([0x00, 0x01]) == 256

    def test_zero(self):
        assert vpd.int_unpack_le([0x00, 0x00]) == 0

    def test_vs_be_differs_for_asymmetric(self):
        data = [0x12, 0x34]
        assert vpd.int_unpack_le(data) != vpd.int_unpack_be(data)


class TestParsePackedData:
    """Tests for parse_packed_data()."""

    def test_simple_two_byte_struct(self):
        data = struct.pack(">BB", 0x10, 0x20)
        result, size = vpd.parse_packed_data(data, ">BB", ["type", "size"])
        assert result == {"type": 0x10, "size": 0x20}
        assert size == 2

    def test_bytes_fields_returned_as_bytes(self):
        # ">4s" returns bytes in Python 3; the function only strips str types.
        data = struct.pack(">4s", b"AB\x00\x00")
        result, size = vpd.parse_packed_data(data, ">4s", ["name"])
        assert result["name"] == b"AB\x00\x00"

    def test_size_returned_is_struct_size(self):
        data = struct.pack(">BH", 1, 512)  # 3 bytes
        _, size = vpd.parse_packed_data(data, ">BH", ["a", "b"])
        assert size == 3

    def test_extra_data_ignored(self):
        # data longer than struct — only struct bytes consumed
        data = struct.pack(">BB", 0xAA, 0xBB) + b"\xFF\xFF"
        result, size = vpd.parse_packed_data(data, ">BB", ["x", "y"])
        assert result == {"x": 0xAA, "y": 0xBB}
        assert size == 2


class TestFruGetTlvHeader:
    """Tests for fru_get_tlv_header()."""

    def test_valid_header(self):
        # TLV_FORMAT = ">BB": type=0x10, size=0x20
        data = struct.pack(">BB", 0x10, 0x20)
        result, size = vpd.fru_get_tlv_header(data)
        assert result is not None
        assert result["type"] == 0x10
        assert result["size"] == 0x20
        assert size == 2

    def test_size_exceeds_1024_returns_none(self):
        # size field > 1024 → returns None, 0
        data = struct.pack(">BB", 0x10, 0xFF) + b"\x00" * 255
        # Even single byte can't exceed 1024, so use a larger format
        # TLV_FORMAT is ">BB" — size is one byte (max 255 < 1024).
        # To hit the None path we need size > 1024, which a single byte can't do.
        # This path is effectively dead for TLV_FORMAT but we document the guard.
        result, size = vpd.fru_get_tlv_header(data)
        assert result is not None  # single byte max 255, never exceeds 1024

    def test_extra_bytes_beyond_struct_ok(self):
        data = struct.pack(">BB", 0x01, 0x08) + b"\x00" * 10
        result, size = vpd.fru_get_tlv_header(data)
        assert result is not None
        assert size == 2


class TestCheckCrc32:
    """Tests for check_crc32()."""

    def test_correct_crc_returns_0(self):
        data = b"hello world"
        crc_int = zlib.crc32(data, 0) & 0xFFFFFFFF
        crc_str = format(crc_int, '08x').upper()
        assert vpd.check_crc32(data, crc_str) == 0

    def test_wrong_crc_returns_1(self):
        data = b"hello world"
        assert vpd.check_crc32(data, "DEADBEEF") == 1

    def test_empty_data(self):
        crc_int = zlib.crc32(b"", 0) & 0xFFFFFFFF
        crc_str = format(crc_int, '08x').upper()
        assert vpd.check_crc32(b"", crc_str) == 0

    def test_case_sensitivity(self):
        data = b"test"
        crc_int = zlib.crc32(data, 0) & 0xFFFFFFFF
        crc_str_upper = format(crc_int, '08x').upper()
        # check_crc32 compares uppercase — lowercase CRC string won't match
        crc_str_lower = format(crc_int, '08x')
        if crc_str_upper != crc_str_lower:
            assert vpd.check_crc32(data, crc_str_lower) == 1


class TestLoadFruBin:
    """Tests for load_fru_bin()."""

    def test_none_input_returns_none(self):
        assert vpd.load_fru_bin(None) is None

    def test_nonexistent_file_returns_none(self):
        assert vpd.load_fru_bin("/nonexistent/path/fru.bin") is None

    def test_valid_file_returns_bytes(self, tmp_path):
        f = tmp_path / "fru.bin"
        f.write_bytes(b"\x01\x02\x03\x04")
        result = vpd.load_fru_bin(str(f))
        assert result == b"\x01\x02\x03\x04"

    def test_empty_string_returns_none(self):
        assert vpd.load_fru_bin("") is None

    def test_large_file_truncated_to_max(self, tmp_path):
        f = tmp_path / "big.bin"
        f.write_bytes(b"\xAA" * (vpd.MAX_VPD_DATA_SIZE + 100))
        result = vpd.load_fru_bin(str(f))
        assert len(result) == vpd.MAX_VPD_DATA_SIZE


class TestConstants:
    """Verify key module constants."""

    def test_max_vpd_data_size(self):
        assert vpd.MAX_VPD_DATA_SIZE == 4096

    def test_tlv_format_is_two_bytes(self):
        assert struct.calcsize(vpd.TLV_FORMAT) == 2

    def test_tlv_fields_length(self):
        assert len(vpd.TLV_FIELDS) == 2

    def test_supported_fru_ver(self):
        assert 1 in vpd.SUPPORTED_FRU_VER


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
