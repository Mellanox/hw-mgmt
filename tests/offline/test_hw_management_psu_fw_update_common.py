#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_psu_fw_update_common.py
########################################################################

import sys
import os
import pytest
from unittest.mock import patch, MagicMock, call
from io import StringIO

# Add source directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))

import hw_management_psu_fw_update_common as psu_common


class TestCalcCRC8:
    """Test calc_crc8 CRC calculation function"""

    def test_calc_crc8_empty_data(self):
        """Test CRC8 calculation with empty data"""
        result = psu_common.calc_crc8([])
        assert result == 0

    def test_calc_crc8_single_byte(self):
        """Test CRC8 calculation with single byte"""
        result = psu_common.calc_crc8([0x00])
        assert result == 0x00
        
        result = psu_common.calc_crc8([0xFF])
        assert isinstance(result, int)
        assert 0 <= result <= 255

    def test_calc_crc8_multiple_bytes(self):
        """Test CRC8 calculation with multiple bytes"""
        # Test with known data pattern
        data = [0x58, 0x01, 0x02, 0x03]
        result = psu_common.calc_crc8(data)
        assert isinstance(result, int)
        assert 0 <= result <= 255

    def test_calc_crc8_different_data_different_crc(self):
        """Test that different data produces different CRC"""
        crc1 = psu_common.calc_crc8([0x01, 0x02, 0x03])
        crc2 = psu_common.calc_crc8([0x01, 0x02, 0x04])
        # Different data should (usually) produce different CRC
        assert crc1 != crc2

    def test_calc_crc8_order_matters(self):
        """Test that byte order affects CRC"""
        crc1 = psu_common.calc_crc8([0x01, 0x02])
        crc2 = psu_common.calc_crc8([0x02, 0x01])
        assert crc1 != crc2


class TestPmbusWrite:
    """Test pmbus_write function"""

    def test_pmbus_write_formats_command_correctly(self):
        """Test that pmbus_write formats i2ctransfer command correctly"""
        with patch('os.popen') as mock_popen:
            mock_popen.return_value.read.return_value = ""
            
            psu_common.pmbus_write(i2c_bus=5, i2c_addr=0x58, data=[0x01, 0x02])
            
            # Verify os.popen was called
            assert mock_popen.called
            call_args = mock_popen.call_args[0][0]
            
            # Check command format
            assert "i2ctransfer" in call_args
            assert "-f -y 5" in call_args
            assert "0x58" in call_args
            assert "0x01" in call_args
            assert "0x02" in call_args

    def test_pmbus_write_calculates_pec(self):
        """Test that pmbus_write includes PEC calculation"""
        with patch('os.popen') as mock_popen:
            with patch.object(psu_common, 'calc_crc8', return_value=0xAB) as mock_crc:
                mock_popen.return_value.read.return_value = ""
                
                psu_common.pmbus_write(i2c_bus=5, i2c_addr=0x58, data=[0x01])
                
                # Verify CRC was calculated
                mock_crc.assert_called_once()
                # Verify PEC is in command (uppercase hex)
                call_args = mock_popen.call_args[0][0]
                assert "0xAB" in call_args or "0xab" in call_args


class TestPmbusWriteNoPec:
    """Test pmbus_write_nopec function"""

    def test_pmbus_write_nopec_no_pec_in_command(self):
        """Test that pmbus_write_nopec doesn't include PEC"""
        with patch('os.popen') as mock_popen:
            mock_popen.return_value.read.return_value = ""
            
            psu_common.pmbus_write_nopec(i2c_bus=5, i2c_addr=0x58, data=[0x01, 0x02])
            
            call_args = mock_popen.call_args[0][0]
            
            # Command length should not include PEC
            assert "w2@" in call_args  # 2 bytes, not 3
            assert "i2ctransfer" in call_args


class TestPmbusRead:
    """Test pmbus_read function"""

    def test_pmbus_read_formats_command(self):
        """Test that pmbus_read formats command correctly"""
        with patch('os.popen') as mock_popen:
            mock_popen.return_value.read.return_value = "0x01 0x02"
            
            result = psu_common.pmbus_read(i2c_bus=5, i2c_addr=0x58, cmd_addr=0x99, cmd_len=2)
            
            call_args = mock_popen.call_args[0][0]
            assert "i2ctransfer" in call_args
            assert "w1@0x58" in call_args  # Write 1 byte (command)
            assert "0x99" in call_args      # Command address
            assert "r2" in call_args        # Read 2 bytes
            assert result == "0x01 0x02"


class TestPmbusReadBlock:
    """Test pmbus_read_block function"""

    def test_pmbus_read_block_valid_response(self):
        """Test pmbus_read_block with valid response"""
        with patch.object(psu_common, 'pmbus_read') as mock_read:
            # First read returns length (4 bytes)
            # Second read returns the data
            mock_read.side_effect = ["0x04", "0x04 0x41 0x42 0x43 0x44"]
            
            result = psu_common.pmbus_read_block(i2c_bus=5, i2c_addr=0x58, cmd_addr=0x99)
            
            assert result == "0x04 0x41 0x42 0x43 0x44"
            assert mock_read.call_count == 2
            # Second call should read length+1 bytes
            assert mock_read.call_args_list[1][0][3] == 5  # 4 + 1

    def test_pmbus_read_block_empty_response(self):
        """Test pmbus_read_block with empty response"""
        with patch.object(psu_common, 'pmbus_read') as mock_read:
            mock_read.return_value = ""
            
            result = psu_common.pmbus_read_block(i2c_bus=5, i2c_addr=0x58, cmd_addr=0x99)
            
            assert result == ""
            # Should only call once since first read returned empty
            assert mock_read.call_count == 1

    def test_pmbus_read_block_invalid_format(self):
        """Test pmbus_read_block with invalid format"""
        with patch.object(psu_common, 'pmbus_read') as mock_read:
            mock_read.return_value = "invalid"
            
            result = psu_common.pmbus_read_block(i2c_bus=5, i2c_addr=0x58, cmd_addr=0x99)
            
            assert result == ""


class TestPmbusPage:
    """Test pmbus_page functions"""

    def test_pmbus_page_calls_write(self):
        """Test that pmbus_page calls pmbus_write correctly"""
        with patch.object(psu_common, 'pmbus_write') as mock_write:
            psu_common.pmbus_page(i2c_bus=5, i2c_addr=0x58, page=1)
            
            mock_write.assert_called_once_with(5, 0x58, [0x00, 1])

    def test_pmbus_page_nopec_calls_write_nopec(self):
        """Test that pmbus_page_nopec calls pmbus_write_nopec correctly"""
        with patch.object(psu_common, 'pmbus_write_nopec') as mock_write:
            psu_common.pmbus_page_nopec(i2c_bus=5, i2c_addr=0x58, page=2)
            
            mock_write.assert_called_once_with(5, 0x58, [0x00, 2])


class TestPmbusReadMfrFunctions:
    """Test pmbus_read_mfr_* parsing functions"""

    def test_pmbus_read_mfr_id_valid(self):
        """Test pmbus_read_mfr_id with valid ASCII data"""
        with patch.object(psu_common, 'pmbus_read_block') as mock_read:
            # Return hex values for "DELTA" (0x44 0x45 0x4C 0x54 0x41)
            mock_read.return_value = "0x05 0x44 0x45 0x4C 0x54 0x41"
            
            result = psu_common.pmbus_read_mfr_id(i2c_bus=5, i2c_addr=0x58)
            
            assert result == "DELTA"

    def test_pmbus_read_mfr_id_empty(self):
        """Test pmbus_read_mfr_id with empty response"""
        with patch.object(psu_common, 'pmbus_read_block') as mock_read:
            mock_read.return_value = ""
            
            result = psu_common.pmbus_read_mfr_id(i2c_bus=5, i2c_addr=0x58)
            
            assert result == ""

    def test_pmbus_read_mfr_id_invalid_format(self):
        """Test pmbus_read_mfr_id with invalid format"""
        with patch.object(psu_common, 'pmbus_read_block') as mock_read:
            mock_read.return_value = "invalid"
            
            result = psu_common.pmbus_read_mfr_id(i2c_bus=5, i2c_addr=0x58)
            
            assert result == ""

    def test_pmbus_read_mfr_model_valid(self):
        """Test pmbus_read_mfr_model with valid data"""
        with patch.object(psu_common, 'pmbus_read_block') as mock_read:
            # Return hex values for "PSU1200" 
            mock_read.return_value = "0x07 0x50 0x53 0x55 0x31 0x32 0x30 0x30"
            
            result = psu_common.pmbus_read_mfr_model(i2c_bus=5, i2c_addr=0x58)
            
            assert result == "PSU1200"

    def test_pmbus_read_mfr_revision_valid(self):
        """Test pmbus_read_mfr_revision with valid data"""
        with patch.object(psu_common, 'pmbus_read_block') as mock_read:
            # Return hex values for "V1.0" (0x56=V, 0x31=1, 0x2E=., 0x30=0)
            mock_read.return_value = "0x04 0x56 0x31 0x2E 0x30"
            
            result = psu_common.pmbus_read_mfr_revision(i2c_bus=5, i2c_addr=0x58)
            
            # First char (length byte) is skipped in ASCII conversion
            assert result == "V1.0"


class TestProgressBar:
    """Test progress_bar function"""

    def test_progress_bar_zero_percent(self, capsys):
        """Test progress bar at 0%"""
        psu_common.progress_bar(0, 100)
        
        captured = capsys.readouterr()
        assert "[" in captured.out
        assert "]" in captured.out
        assert "0" in captured.out

    def test_progress_bar_fifty_percent(self, capsys):
        """Test progress bar at 50%"""
        psu_common.progress_bar(50, 100)
        
        captured = capsys.readouterr()
        assert "#" in captured.out
        assert "50" in captured.out

    def test_progress_bar_hundred_percent(self, capsys):
        """Test progress bar at 100%"""
        psu_common.progress_bar(100, 100)
        
        captured = capsys.readouterr()
        assert "####################" in captured.out  # 20 hashes
        assert "100" in captured.out


class TestCheckPsuRedundancy:
    """Test check_psu_redundancy function"""

    def test_check_psu_redundancy_all_powered(self):
        """Test when all PSUs are powered on"""
        with patch('os.popen') as mock_popen:
            # Mock: 2 PSUs, both powered on (pwr_status=1)
            mock_popen.side_effect = [
                MagicMock(read=lambda: "2"),      # hotplug_psus
                MagicMock(read=lambda: "1"),      # psu1_pwr_status
                MagicMock(read=lambda: "0x58\n"), # psu1_i2c_addr
                MagicMock(read=lambda: "1"),      # psu2_pwr_status
                MagicMock(read=lambda: "0x59\n"), # psu2_i2c_addr
            ]
            
            result = psu_common.check_psu_redundancy(proceed=False, ignore_addr=0)
            
            assert result == 0

    def test_check_psu_redundancy_ignore_addr(self, capsys):
        """Test when one PSU is powered off but matches ignore_addr"""
        with patch('os.popen') as mock_popen:
            # Mock: 2 PSUs, one matches ignore_addr
            mock_popen.side_effect = [
                MagicMock(read=lambda: "2"),      # hotplug_psus
                MagicMock(read=lambda: "0"),      # psu1_pwr_status (OFF)
                MagicMock(read=lambda: "0x58\n"), # psu1_i2c_addr
                MagicMock(read=lambda: "1"),      # psu2_pwr_status
                MagicMock(read=lambda: "0x59\n"), # psu2_i2c_addr
            ]
            
            result = psu_common.check_psu_redundancy(proceed=True, ignore_addr=0x58)
            
            assert result == 0
            captured = capsys.readouterr()
            assert "previous update is in progress" in captured.out


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])

