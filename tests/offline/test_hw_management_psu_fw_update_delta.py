#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_psu_fw_update_delta.py
########################################################################

import hw_management_psu_fw_update_delta as psu_delta
import sys
import os
import pytest
from unittest.mock import patch, MagicMock, mock_open

# Add source directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))


class TestModelCheckingFunctions:
    """Test PSU model identification functions"""

    def test_mfr_model_is_acbel_2000_fwd(self):
        """Test Acbel 2000 forward model detection"""
        assert psu_delta.mfr_model_is_acbel("FSP016-9G0G-12345") is True
        assert psu_delta.mfr_model_is_acbel_2000("FSP016-9G0G") is True

    def test_mfr_model_is_acbel_2000_rev(self):
        """Test Acbel 2000 reverse model detection"""
        assert psu_delta.mfr_model_is_acbel("FSP017-9G0G-12345") is True
        assert psu_delta.mfr_model_is_acbel_2000("FSP017-9G0G") is True

    def test_mfr_model_is_acbel_1100_fwd(self):
        """Test Acbel 1100 forward model detection"""
        assert psu_delta.mfr_model_is_acbel("FSP007-9G0G-12345") is True
        assert psu_delta.mfr_model_is_acbel_1100("FSP007-9G0G") is True

    def test_mfr_model_is_acbel_1100_rev(self):
        """Test Acbel 1100 reverse model detection"""
        assert psu_delta.mfr_model_is_acbel("FSN022-9G0G-12345") is True
        assert psu_delta.mfr_model_is_acbel_1100("FSN022-9G0G") is True

    def test_mfr_model_is_acbel_460_fwd(self):
        """Test Acbel 460 forward model detection"""
        assert psu_delta.mfr_model_is_acbel_460("FSF008-9G0G-12345") is True

    def test_mfr_model_is_acbel_460_rev(self):
        """Test Acbel 460 reverse model detection"""
        assert psu_delta.mfr_model_is_acbel_460("FSF007-9G0G") is True

    def test_mfr_model_is_not_acbel(self):
        """Test non-Acbel model returns False"""
        assert psu_delta.mfr_model_is_acbel("DPS-550AB-12345") is False
        assert psu_delta.mfr_model_is_acbel_1100("DPS-550AB") is False
        assert psu_delta.mfr_model_is_acbel_2000("DPS-550AB") is False
        assert psu_delta.mfr_model_is_acbel_460("DPS-550AB") is False

    def test_mfr_model_is_acbel_partial_match(self):
        """Test that function requires startswith match"""
        # Should not match if prefix doesn't match exactly
        assert psu_delta.mfr_model_is_acbel("XXXFSP016-9G0G") is False

    def test_mfr_model_acbel_1100_not_2000(self):
        """Test Acbel 1100 is not detected as 2000"""
        assert psu_delta.mfr_model_is_acbel_1100("FSP007-9G0G") is True
        assert psu_delta.mfr_model_is_acbel_2000("FSP007-9G0G") is False

    def test_mfr_model_acbel_2000_not_1100(self):
        """Test Acbel 2000 is not detected as 1100"""
        assert psu_delta.mfr_model_is_acbel_2000("FSP016-9G0G") is True
        assert psu_delta.mfr_model_is_acbel_1100("FSP016-9G0G") is False


class TestHeaderParsing:
    """Test firmware header parsing functions"""

    def test_parse_header_delta(self, capsys):
        """Test Delta firmware header parsing"""
        # Create test data with proper header structure
        data_list = [0] * 32  # 32 bytes minimum
        # Set model name at bytes 10-21 (12 bytes for "DPS-550AB-12")
        model = "DPS-550AB-12"
        for i, c in enumerate(model):
            data_list[10 + i] = ord(c)

        # Set firmware revision at bytes 23-25
        data_list[23] = 1
        data_list[24] = 2
        data_list[25] = 3

        # Set hardware revision at bytes 26-27
        data_list[26] = ord('A')
        data_list[27] = ord('1')

        # Set block size (little endian) at bytes 28-29
        data_list[28] = 0x00  # Low byte
        data_list[29] = 0x02  # High byte (512 = 2 * 256)

        # Set write time at bytes 30-31
        data_list[30] = 0x0A  # Low byte
        data_list[31] = 0x00  # High byte

        psu_delta.parse_header_delta(data_list)

        # Check FW_HEADER was populated
        assert psu_delta.FW_HEADER["model_name"] == model
        assert psu_delta.FW_HEADER["fw_revision"] == [1, 2, 3]
        assert psu_delta.FW_HEADER["hw_revision"] == "A1"
        assert psu_delta.FW_HEADER["block_size"] == 512
        assert psu_delta.FW_HEADER["write_time"] == 10

    def test_parse_header_acbel(self, capsys):
        """Test Acbel firmware header parsing"""
        # Create test data
        data_list = [0] * 32
        # Set model name at bytes 10-19 (10 bytes)
        model = "FSP016-9G0"
        for i, c in enumerate(model):
            data_list[10 + i] = ord(c)

        # Set firmware revision
        data_list[23] = 4
        data_list[24] = 5
        data_list[25] = 6

        # Set hardware revision at bytes 26-27 (will be joined with '.')
        data_list[26] = ord('2')
        data_list[27] = ord('0')

        # Set block size
        data_list[28] = 0x00
        data_list[29] = 0x04  # 1024 = 4 * 256

        # Set write time
        data_list[30] = 0x14  # 20
        data_list[31] = 0x00

        psu_delta.parse_header_acbel(data_list)

        assert psu_delta.FW_HEADER["model_name"] == model
        assert psu_delta.FW_HEADER["fw_revision"] == [4, 5, 6]
        assert psu_delta.FW_HEADER["hw_revision"] == "2.0"
        assert psu_delta.FW_HEADER["block_size"] == 1024
        assert psu_delta.FW_HEADER["write_time"] == 20


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
