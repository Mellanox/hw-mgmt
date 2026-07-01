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


class TestReadMfrFwRevision:
    """Test read_mfr_fw_revision() for all mfr_model branches."""

    def test_delta_500ab_branch(self):
        """MFR_MODEL_500AB prefix → pmbus_read with MFR_FW_REVISION, len=8; ASCII decode."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='DPS-550AB-XYZ'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x41 0x42 0x43') as mock_read:
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            mock_read.assert_called_once_with(0, 0x58, psu_delta.MFR_FW_REVISION, 8)
            assert result == 'ABC'

    def test_delta_500ab_empty_return(self):
        """MFR_MODEL_500AB branch with empty pmbus_read returns None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='DPS-550AB'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            assert result is None

    def test_acbel_1100_branch(self):
        """Acbel 1100 (FSP007-9G0G) → pmbus_read ACBEL,4; reverses bytes, dot-joins."""
        # Returned hex list: '0x02 0x01 0x00 0x00' → int_list[1:3] = ['0x01','0x00']
        # reversed → ['0x00','0x01'] → '0.1'
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='FSP007-9G0G'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x02 0x01 0x00 0x00'):
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            assert result == '0.1'

    def test_acbel_1100_empty_return(self):
        """Acbel 1100 branch with empty pmbus_read returns None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='FSP007-9G0G'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            assert result is None

    def test_acbel_460_branch(self):
        """Acbel 460 (FSF008-9G0G) → pmbus_read ACBEL,5; rearranges bytes, dot-joins."""
        # '0x02 0x03 0x04 0x05 0x06' → int_list[1:5] = ['0x03','0x04','0x05','0x06']
        # ver_list = [int_list[1], int_list[0], int_list[3], int_list[2]] = ['0x04','0x03','0x06','0x05']
        # → '4.3.6.5'
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='FSF008-9G0G-123'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x02 0x03 0x04 0x05 0x06'):
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            assert result == '4.3.6.5'

    def test_acbel_460_empty_return(self):
        """Acbel 460 branch with empty pmbus_read returns None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='FSF008-9G0G'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            assert result is None

    def test_acbel_2000_branch(self):
        """Acbel 2000 (FSP016-9G0G) → pmbus_read ACBEL,6; ASCII decode."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='FSP016-9G0G'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x41 0x42 0x43') as mock_read:
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            mock_read.assert_called_once_with(0, 0x58, psu_delta.MFR_FW_REVISION_ACBEL, 6)
            assert result == 'ABC'

    def test_default_branch(self):
        """Unknown model → pmbus_read MFR_FW_REVISION,6; ASCII decode."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='UNKNOWN-MODEL'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x58 0x59 0x5a') as mock_read:
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            mock_read.assert_called_once_with(0, 0x58, psu_delta.MFR_FW_REVISION, 6)
            assert result == 'XYZ'

    def test_default_branch_empty_return(self):
        """Default branch with empty pmbus_read returns None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='UNKNOWN-MODEL'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_revision(0, 0x58)
            assert result is None


class TestReadMfrFwUploadStatus:
    """Test read_mfr_fw_upload_status() branches."""

    def test_acbel_model_uses_acbel_cmd(self):
        """Acbel model routes to MFR_FWUPLOAD_STATUS_ACBEL command."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='FSP007-9G0G'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x00') as mock_read:
            psu_delta.read_mfr_fw_upload_status(0, 0x58)
            mock_read.assert_called_once_with(0, 0x58, psu_delta.MFR_FWUPLOAD_STATUS_ACBEL, 1)

    def test_non_acbel_model_uses_delta_cmd(self):
        """Non-acbel model routes to MFR_FWUPLOAD_STATUS command."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='DPS-550AB'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x01') as mock_read:
            result = psu_delta.read_mfr_fw_upload_status(0, 0x58)
            mock_read.assert_called_once_with(0, 0x58, psu_delta.MFR_FWUPLOAD_STATUS, 1)
            assert result is not None

    def test_status_0x00_reset(self):
        """Status 0x00 returns the 'Reset' status string."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='DPS-550AB'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x00'):
            result = psu_delta.read_mfr_fw_upload_status(0, 0x58)
            assert result == psu_delta.UPLOAD_STATUS_DICT[0]

    def test_status_0x01_full_image(self):
        """Status 0x01 returns 'Full image received.'"""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='DPS-550AB'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x01'):
            result = psu_delta.read_mfr_fw_upload_status(0, 0x58)
            assert result == psu_delta.UPLOAD_STATUS_DICT[1]

    def test_empty_pmbus_return_gives_none(self):
        """Empty pmbus_read return → function returns None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read_mfr_model', return_value='DPS-550AB'), \
             patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_upload_status(0, 0x58)
            assert result is None


class TestReadMfrFwUploadStatusAcbel460:
    """Test read_mfr_fw_upload_status_acbel_460()."""

    def test_known_status_0x51(self):
        """0x51 → 'ISP Mode Disabled'."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x51'):
            result = psu_delta.read_mfr_fw_upload_status_acbel_460(0, 0x58)
            assert result == psu_delta.UPLOAD_STATUS_DICT_ACBEL_460[0x51]

    def test_known_status_0x30(self):
        """0x30 → 'ISP No Error'."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x30'):
            result = psu_delta.read_mfr_fw_upload_status_acbel_460(0, 0x58)
            assert result == psu_delta.UPLOAD_STATUS_DICT_ACBEL_460[0x30]

    def test_empty_pmbus_return_gives_none(self):
        """Empty pmbus_read → None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_upload_status_acbel_460(0, 0x58)
            assert result is None


class TestReadMfrFwUploadMode:
    """Test read_mfr_fw_upload_mode() and its acbel_460 variant."""

    def test_mode_0x00_exit(self):
        """0x00 → 'Exit firmware upload mode.'"""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x00'):
            result = psu_delta.read_mfr_fw_upload_mode(0, 0x58)
            assert result == psu_delta.UPLOAD_MODE_DICT[0]

    def test_mode_0x01_enter(self):
        """0x01 → 'Enter Firmware upload mode.'"""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x01'):
            result = psu_delta.read_mfr_fw_upload_mode(0, 0x58)
            assert result == psu_delta.UPLOAD_MODE_DICT[1]

    def test_empty_return_gives_none(self):
        """Empty pmbus_read → None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_upload_mode(0, 0x58)
            assert result is None

    def test_acbel_460_variant_known_code(self):
        """acbel_460 variant: 0x00 → 'Exit firmware upload mode.'"""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value='0x00'):
            result = psu_delta.read_mfr_fw_upload_mode_acbel_460(0, 0x58)
            assert result == psu_delta.UPLOAD_MODE_DICT[0]

    def test_acbel_460_variant_empty_return(self):
        """acbel_460 variant: empty pmbus_read → None."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_read', return_value=''):
            result = psu_delta.read_mfr_fw_upload_mode_acbel_460(0, 0x58)
            assert result is None


class TestWriteMfrFwUploadMode:
    """Test write_mfr_fw_upload_mode() and its variants."""

    def test_write_mode_calls_pmbus_write(self):
        """write_mfr_fw_upload_mode sends [MFR_FWUPLOAD_MODE, mode] to pmbus_write."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_write') as mock_write:
            psu_delta.write_mfr_fw_upload_mode(0, 0x58, 1)
            mock_write.assert_called_once_with(0, 0x58, [psu_delta.MFR_FWUPLOAD_MODE, 1])

    def test_write_mode_acbel_460_calls_pmbus_write(self):
        """write_mfr_fw_upload_mode_acbel_460 sends correct command."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_write') as mock_write:
            psu_delta.write_mfr_fw_upload_mode_acbel_460(0, 0x58, 0)
            mock_write.assert_called_once_with(0, 0x58, [psu_delta.MFR_FWUPLOAD_MODE_ACBEL_460, 0])


class TestWriteMfrFwUpload:
    """Test write_mfr_fw_upload() and acbel_460 variant."""

    def test_write_upload_prepends_cmd(self):
        """write_mfr_fw_upload prepends MFR_FWUPLOAD before data bytes."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_write') as mock_write:
            psu_delta.write_mfr_fw_upload(0, 0x58, [0xAA, 0xBB])
            mock_write.assert_called_once_with(0, 0x58, [psu_delta.MFR_FWUPLOAD, 0xAA, 0xBB])

    def test_write_upload_acbel_460_prepends_cmd(self):
        """write_mfr_fw_upload_acbel_460 prepends MFR_FWUPLOAD_ACBEL_460 before data bytes."""
        with patch.object(psu_delta.psu_upd_cmn, 'pmbus_write') as mock_write:
            psu_delta.write_mfr_fw_upload_acbel_460(0, 0x58, [0xCC])
            mock_write.assert_called_once_with(0, 0x58, [psu_delta.MFR_FWUPLOAD_ACBEL_460, 0xCC])


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
