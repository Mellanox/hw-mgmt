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

"""Tests for hw_management_nvl_temperature_get.py pure helper functions.

The script runs module-level code at import time (argparse.parse_args() +
hardware access).  We load it via importlib with three targeted mocks:
  - sys.argv → default args so parse_args() succeeds
  - os.path.exists → True so the device-file check is bypassed
  - builtins.open → real open for everything except the nvswitch device file
  - fcntl.ioctl → no-op so the ioctl call is silent

The module exits with SystemExit(0) after printing temperature; we catch that
and the module object retains all function definitions.
"""

import sys
import struct
import array
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock
import importlib.util

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = (TESTS_DIR / ".." / "..").resolve()
SCRIPT = PROJECT_ROOT / "usr" / "usr" / "bin" / "hw_management_nvl_temperature_get.py"

# ---------------------------------------------------------------------------
# Module loading — runs once at collection time
# ---------------------------------------------------------------------------
_spec = importlib.util.spec_from_file_location("nvl_temp", str(SCRIPT))
nvl_mod = importlib.util.module_from_spec(_spec)

_mock_fd = MagicMock()
_mock_fd.fileno.return_value = 42

_real_open = open


def _smart_open(path, *args, **kwargs):
    """Forward all opens except the nvswitch device to the real open()."""
    if 'nvidia-nvswitch' in str(path):
        return _mock_fd
    return _real_open(path, *args, **kwargs)


with patch('sys.argv', ['script']), \
     patch('os.path.exists', return_value=True), \
     patch('builtins.open', side_effect=_smart_open), \
     patch('fcntl.ioctl'):
    try:
        _spec.loader.exec_module(nvl_mod)
    except SystemExit:
        pass

_CHANNELS = nvl_mod.NVSWITCH_NUM_MAX_CHANNELS   # 16
_BUF_SIZE = 4 + 4 * _CHANNELS + 4 * _CHANNELS  # 132


def _zeroed_buf():
    return array.array('b', [0] * _BUF_SIZE)


@pytest.fixture(autouse=True)
def _skip_if_missing():
    if not SCRIPT.exists():
        pytest.skip(f"Script not found: {SCRIPT}")


# ---------------------------------------------------------------------------
# TestChunks
# ---------------------------------------------------------------------------
class TestChunks:
    """Tests for chunks(l, n)."""

    def test_even_split(self):
        assert nvl_mod.chunks([1, 2, 3, 4], 2) == [[1, 2], [3, 4]]

    def test_uneven_split(self):
        result = nvl_mod.chunks([1, 2, 3, 4, 5], 2)
        assert result == [[1, 2], [3, 4], [5]]

    def test_single_element_chunks(self):
        assert nvl_mod.chunks([10, 20, 30], 1) == [[10], [20], [30]]

    def test_chunk_larger_than_list(self):
        assert nvl_mod.chunks([1, 2], 10) == [[1, 2]]

    def test_empty_list(self):
        assert nvl_mod.chunks([], 4) == []

    def test_chunk_size_zero_becomes_one(self):
        # n = max(1, 0) = 1
        result = nvl_mod.chunks([1, 2, 3], 0)
        assert result == [[1], [2], [3]]

    def test_returns_list_of_slices(self):
        result = nvl_mod.chunks(list(range(8)), 4)
        assert len(result) == 2
        assert result[0] == [0, 1, 2, 3]
        assert result[1] == [4, 5, 6, 7]


# ---------------------------------------------------------------------------
# TestConvertTemperature
# ---------------------------------------------------------------------------
class TestConvertTemperature:
    """Tests for convert_temperature(buf)."""

    def test_zero_buffer_gives_zero(self):
        buf = struct.pack('i', 0)
        assert nvl_mod.convert_temperature(buf) == 0.0

    def test_256_gives_1_degree(self):
        buf = struct.pack('i', 256)
        assert nvl_mod.convert_temperature(buf) == pytest.approx(1.0)

    def test_negative_temperature(self):
        buf = struct.pack('i', -256)
        assert nvl_mod.convert_temperature(buf) == pytest.approx(-1.0)

    def test_25_degrees(self):
        # 25.0 * 256 = 6400
        buf = struct.pack('i', 6400)
        assert nvl_mod.convert_temperature(buf) == pytest.approx(25.0)

    def test_result_is_float(self):
        buf = struct.pack('i', 512)
        assert isinstance(nvl_mod.convert_temperature(buf), float)

    def test_precision(self):
        # 128 → 128/256 = 0.5
        buf = struct.pack('i', 128)
        assert nvl_mod.convert_temperature(buf) == pytest.approx(0.5)


# ---------------------------------------------------------------------------
# TestComposeRequest
# ---------------------------------------------------------------------------
class TestComposeRequest:
    """Tests for compose_request(sensor)."""

    def test_returns_array_of_correct_size(self):
        buf = nvl_mod.compose_request(0)
        assert len(buf) == _BUF_SIZE

    def test_sensor_0_sets_bit_0(self):
        buf = nvl_mod.compose_request(0)
        assert buf[0] == 1  # 1 << 0

    def test_sensor_1_sets_bit_1(self):
        buf = nvl_mod.compose_request(1)
        assert buf[0] == 2  # 1 << 1

    def test_sensor_2_sets_bit_2(self):
        buf = nvl_mod.compose_request(2)
        assert buf[0] == 4  # 1 << 2

    def test_remaining_bytes_are_zero(self):
        buf = nvl_mod.compose_request(0)
        assert all(b == 0 for b in buf[1:])

    def test_different_sensors_differ(self):
        buf0 = nvl_mod.compose_request(0)
        buf1 = nvl_mod.compose_request(1)
        assert buf0[0] != buf1[0]


# ---------------------------------------------------------------------------
# TestParseResponce
# ---------------------------------------------------------------------------
class TestParseResponce:
    """Tests for parse_responce(buf)."""

    def test_zeroed_buffer_all_zero(self):
        result = nvl_mod.parse_responce(_zeroed_buf())
        assert result["mask"] == 0
        assert all(t == 0.0 for t in result["temp"])
        assert all(s == 0 for s in result["status"])

    def test_result_has_required_keys(self):
        result = nvl_mod.parse_responce(_zeroed_buf())
        assert "mask" in result
        assert "temp" in result
        assert "status" in result

    def test_temp_list_length(self):
        result = nvl_mod.parse_responce(_zeroed_buf())
        assert len(result["temp"]) == _CHANNELS

    def test_status_list_length(self):
        result = nvl_mod.parse_responce(_zeroed_buf())
        assert len(result["status"]) == _CHANNELS

    def test_nonzero_mask(self):
        buf = _zeroed_buf()
        struct.pack_into('i', buf, 0, 0x0001)
        result = nvl_mod.parse_responce(buf)
        assert result["mask"] == 1

    def test_temperature_at_index_0(self):
        buf = _zeroed_buf()
        # Write 25.0 * 256 = 6400 at temperature[0] offset (offset 4)
        struct.pack_into('i', buf, 4, 6400)
        result = nvl_mod.parse_responce(buf)
        assert result["temp"][0] == pytest.approx(25.0)

    def test_temperature_at_index_1(self):
        buf = _zeroed_buf()
        # temperature[1] is at offset 4 + 4 = 8
        struct.pack_into('i', buf, 8, 512)
        result = nvl_mod.parse_responce(buf)
        assert result["temp"][1] == pytest.approx(2.0)

    def test_status_nonzero(self):
        buf = _zeroed_buf()
        # status[0] is at offset 4 + 4*16 = 68
        struct.pack_into('i', buf, 4 + 4 * _CHANNELS, 1)
        result = nvl_mod.parse_responce(buf)
        assert result["status"][0] == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
