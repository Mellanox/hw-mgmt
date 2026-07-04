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

"""Tests for hw_management_thermal_updater.py pure helper functions.

Covers: sdk_temp2degree, is_module_host_management_mode, is_asic_ready,
        asic_temp_reset, CONST constants.
"""

import sys
import os
import pytest
import importlib.util
from unittest.mock import MagicMock, patch, mock_open

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(TESTS_DIR, '..', '..'))
BIN_DIR = os.path.join(PROJECT_ROOT, 'usr', 'usr', 'bin')

# Load thermal_updater with hw_management_lib mocked (it's an optional dep)
_hw_lib_mock = MagicMock()
sys.modules.setdefault('hw_management_lib', _hw_lib_mock)

_spec = importlib.util.spec_from_file_location(
    "hw_management_thermal_updater",
    os.path.join(BIN_DIR, "hw_management_thermal_updater.py")
)
_tu_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_tu_mod)

# Assign a mock LOGGER so functions that use it don't NPE
_tu_mod.LOGGER = MagicMock()


# ---------------------------------------------------------------------------
# TestCONST
# ---------------------------------------------------------------------------
class TestCONST:
    """Verify CONST values are sane."""

    def test_sdk_fw_control_is_zero(self):
        assert _tu_mod.CONST.SDK_FW_CONTROL == 0

    def test_sdk_sw_control_is_one(self):
        assert _tu_mod.CONST.SDK_SW_CONTROL == 1

    def test_sdk_temp_multiplier(self):
        assert _tu_mod.CONST.SDK_TEMP_MULTIPLIER == 125

    def test_sdk_temp_mask(self):
        assert _tu_mod.CONST.SDK_TEMP_MASK == 0xffff

    def test_asic_temp_min_def(self):
        assert _tu_mod.CONST.ASIC_TEMP_MIN_DEF == 75000

    def test_asic_temp_max_def(self):
        assert _tu_mod.CONST.ASIC_TEMP_MAX_DEF == 85000

    def test_asic_read_err_retry_count(self):
        assert _tu_mod.CONST.ASIC_READ_ERR_RETRY_COUNT == 3


# ---------------------------------------------------------------------------
# TestSdkTemp2Degree
# ---------------------------------------------------------------------------
class TestSdkTemp2Degree:
    """Tests for sdk_temp2degree()."""

    def test_positive_zero_returns_zero(self):
        assert _tu_mod.sdk_temp2degree(0) == 0

    def test_positive_value_multiplied(self):
        # 680 * 125 = 85000 millidegrees = 85°C
        assert _tu_mod.sdk_temp2degree(680) == 85000

    def test_positive_one(self):
        assert _tu_mod.sdk_temp2degree(1) == 125

    def test_negative_minus_one(self):
        # -1 → 0xffff + (-1) + 1 = 0xffff = 65535
        assert _tu_mod.sdk_temp2degree(-1) == 65535

    def test_negative_minus_two(self):
        # -2 → 0xffff + (-2) + 1 = 65534
        assert _tu_mod.sdk_temp2degree(-2) == 65534

    def test_positive_large_value(self):
        # 960 * 125 = 120000 millidegrees = 120°C
        assert _tu_mod.sdk_temp2degree(960) == 120000

    def test_positive_returns_millidegrees(self):
        result = _tu_mod.sdk_temp2degree(600)
        assert result == 75000


# ---------------------------------------------------------------------------
# TestIsModuleHostManagementMode
# ---------------------------------------------------------------------------
class TestIsModuleHostManagementMode:
    """Tests for is_module_host_management_mode()."""

    def test_sw_control_returns_true(self):
        with patch('builtins.open', mock_open(read_data='1\n')):
            result = _tu_mod.is_module_host_management_mode('/sys/module/sx_core/asic0/module0/')
        assert result is True

    def test_fw_control_returns_false(self):
        with patch('builtins.open', mock_open(read_data='0\n')):
            result = _tu_mod.is_module_host_management_mode('/sys/module/sx_core/asic0/module0/')
        assert result is False

    def test_oserror_returns_false(self):
        with patch('builtins.open', side_effect=OSError("no such file")):
            result = _tu_mod.is_module_host_management_mode('/missing/path/')
        assert result is False

    def test_valueerror_on_bad_content_returns_false(self):
        with patch('builtins.open', mock_open(read_data='not_a_number\n')):
            result = _tu_mod.is_module_host_management_mode('/sys/module/sx_core/asic0/module0/')
        assert result is False

    def test_logger_called_on_success(self):
        mock_logger = MagicMock()
        _tu_mod.LOGGER = mock_logger
        with patch('builtins.open', mock_open(read_data='1\n')):
            _tu_mod.is_module_host_management_mode('/path/')
        mock_logger.notice.assert_called()

    def test_logger_warning_called_on_error(self):
        mock_logger = MagicMock()
        _tu_mod.LOGGER = mock_logger
        with patch('builtins.open', side_effect=OSError("fail")):
            _tu_mod.is_module_host_management_mode('/path/')
        mock_logger.warning.assert_called()


# ---------------------------------------------------------------------------
# TestIsAsicReady
# ---------------------------------------------------------------------------
class TestIsAsicReady:
    """Tests for is_asic_ready()."""

    def test_path_not_exists_returns_false(self):
        with patch('os.path.exists', return_value=False):
            result = _tu_mod.is_asic_ready('asic1', {'fin': '/nonexistent/'})
        assert result is False

    def test_path_exists_ready_file_reads_one(self):
        with patch('os.path.exists', return_value=True), \
                patch('builtins.open', mock_open(read_data='1\n')):
            result = _tu_mod.is_asic_ready('asic1', {'fin': '/sys/module/sx_core/asic0/'})
        assert result is True

    def test_path_exists_ready_file_reads_zero(self):
        with patch('os.path.exists', return_value=True), \
                patch('builtins.open', mock_open(read_data='0\n')):
            result = _tu_mod.is_asic_ready('asic1', {'fin': '/sys/module/sx_core/asic0/'})
        assert result is False

    def test_path_exists_ready_file_oserror_assumes_ready(self):
        with patch('os.path.exists', return_value=True), \
                patch('builtins.open', side_effect=OSError("fail")):
            result = _tu_mod.is_asic_ready('asic1', {'fin': '/sys/module/sx_core/asic0/'})
        assert result is True

    def test_path_exists_ready_file_valueerror_assumes_ready(self):
        with patch('os.path.exists', return_value=True), \
                patch('builtins.open', mock_open(read_data='not_int')):
            result = _tu_mod.is_asic_ready('asic1', {'fin': '/sys/'})
        assert result is True

    def test_logger_warning_on_read_error(self):
        mock_logger = MagicMock()
        _tu_mod.LOGGER = mock_logger
        with patch('os.path.exists', return_value=True), \
                patch('builtins.open', side_effect=OSError("fail")):
            _tu_mod.is_asic_ready('asic1', {'fin': '/sys/'})
        mock_logger.warning.assert_called()


# ---------------------------------------------------------------------------
# TestAsicTempReset
# ---------------------------------------------------------------------------
class TestAsicTempReset:
    """Tests for asic_temp_reset()."""

    def test_calls_atomic_write_for_each_suffix(self):
        with patch.object(_tu_mod, 'atomic_file_write') as mock_afw:
            _tu_mod.asic_temp_reset('asic1', '/dummy/path')

        expected_suffixes = ["", "_temp_norm", "_temp_crit", "_temp_emergency", "_temp_trip_crit"]
        call_paths = [call[0][0] for call in mock_afw.call_args_list]
        for suffix in expected_suffixes:
            assert any(suffix in p for p in call_paths)

    def test_writes_empty_string_for_each_file(self):
        with patch.object(_tu_mod, 'atomic_file_write') as mock_afw:
            _tu_mod.asic_temp_reset('asic', '/dummy/path')

        for call in mock_afw.call_args_list:
            val = call[0][1]
            assert val == "\n"

    def test_asic_name_in_path(self):
        with patch.object(_tu_mod, 'atomic_file_write') as mock_afw:
            _tu_mod.asic_temp_reset('asic2', '/dummy/path')

        call_paths = [call[0][0] for call in mock_afw.call_args_list]
        assert any('asic2' in p for p in call_paths)

    def test_exactly_five_writes(self):
        with patch.object(_tu_mod, 'atomic_file_write') as mock_afw:
            _tu_mod.asic_temp_reset('asic1', '/dummy/path')
        assert mock_afw.call_count == 5


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
