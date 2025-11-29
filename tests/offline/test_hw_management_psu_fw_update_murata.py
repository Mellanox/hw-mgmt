#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_psu_fw_update_murata.py
########################################################################

import sys
import os
import pytest
from unittest.mock import patch, MagicMock

# Add source directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))

import hw_management_psu_fw_update_murata as psu_murata


class TestReadMurataFwRevision:
    """Test read_murata_fw_revision function"""

    def test_read_murata_fw_revision_primary(self):
        """Test reading primary firmware revision"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_page') as mock_page:
            with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read_block') as mock_read:
                # Return hex values for version string
                mock_read.return_value = "0x05 0x56 0x31 0x2E 0x30 0x32"
                
                result = psu_murata.read_murata_fw_revision(i2c_bus=5, i2c_addr=0x58, primary=True)
                
                # Should set page to 0 for primary
                assert mock_page.call_args_list[0][0] == (5, 0x58, 0)
                # Should read from 0x9b
                mock_read.assert_called_with(5, 0x58, 0x9b)
                # Should return ASCII string (skip first char which is length)
                assert result == "V1.02"

    def test_read_murata_fw_revision_secondary(self):
        """Test reading secondary firmware revision"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_page') as mock_page:
            with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read_block') as mock_read:
                mock_read.return_value = "0x04 0x31 0x2E 0x30 0x33"
                
                result = psu_murata.read_murata_fw_revision(i2c_bus=5, i2c_addr=0x58, primary=False)
                
                # Should set page to 1 for secondary
                assert mock_page.call_args_list[0][0] == (5, 0x58, 1)
                assert result == "1.03"

    def test_read_murata_fw_revision_empty_response(self):
        """Test handling empty response"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_page'):
            with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read_block') as mock_read:
                mock_read.return_value = ""
                
                result = psu_murata.read_murata_fw_revision(i2c_bus=5, i2c_addr=0x58, primary=True)
                
                # Should return None when no valid response
                assert result is None

    def test_read_murata_fw_revision_resets_page(self):
        """Test that function resets page to 0 after reading"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_page') as mock_page:
            with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read_block') as mock_read:
                mock_read.return_value = "0x03 0x31 0x32 0x33"
                
                psu_murata.read_murata_fw_revision(i2c_bus=5, i2c_addr=0x58, primary=False)
                
                # Should reset page to 0 after reading
                assert mock_page.call_count == 2
                assert mock_page.call_args_list[1][0] == (5, 0x58, 0)


class TestPowerSupplyReset:
    """Test power_supply_reset function"""

    def test_power_supply_reset_regular_address(self):
        """Test PSU reset with regular I2C address"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write') as mock_write:
            psu_murata.power_supply_reset(i2c_bus=5, i2c_addr=0x58)
            
            # Should use pmbus_write (with PEC)
            mock_write.assert_called_once_with(5, 0x58, [0xf8, 0xaf])

    def test_power_supply_reset_bootloader_address(self):
        """Test PSU reset with bootloader address"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock_write:
            psu_murata.power_supply_reset(i2c_bus=5, i2c_addr=0x60)  # BOOTLOADER_I2C_ADDR
            
            # Should use pmbus_write_nopec (no PEC)
            mock_write.assert_called_once_with(5, 0x60, [0xf8, 0xaf])


class TestEndOfFile:
    """Test end_of_file function"""

    def test_end_of_file_regular_address(self):
        """Test end of file command with regular address"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write') as mock_write:
            psu_murata.end_of_file(i2c_bus=5, i2c_addr=0x58)
            
            # Should use pmbus_write (with PEC)
            assert mock_write.called
            call_args = mock_write.call_args[0]
            assert call_args[0] == 5
            assert call_args[1] == 0x58
            # Data should be [0xfa, 0x44, 0x01, 0x00] + 32 zeros + [0x00, 0xc1]
            assert len(call_args[2]) == 38

    def test_end_of_file_bootloader_address(self):
        """Test end of file command with bootloader address"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock_write:
            psu_murata.end_of_file(i2c_bus=5, i2c_addr=0x60)
            
            # Should use pmbus_write_nopec (no PEC)
            assert mock_write.called
            call_args = mock_write.call_args[0]
            assert call_args[1] == 0x60


class TestCheckPowerSupplyStatus:
    """Test check_power_supply_status function"""

    def test_check_power_supply_status_valid_response(self, capsys):
        """Test checking power supply status with valid response"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read') as mock_read:
            # Return 3 bytes of status
            mock_read.return_value = "0x00 0x07 0x00"  # All flags set
            
            psu_murata.check_power_supply_status(i2c_bus=5, i2c_addr=0x58)
            
            # Should read from PS_STATUS_ADDR (0xE0) with length 3
            mock_read.assert_called_with(5, 0x58, 0xE0, 3)
            
            captured = capsys.readouterr()
            # Should print status bits
            assert "bootoader_mode" in captured.out or "bootload_complette" in captured.out

    def test_check_power_supply_status_empty_response(self):
        """Test handling empty response"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read') as mock_read:
            mock_read.return_value = ""
            
            # Should handle gracefully without error
            psu_murata.check_power_supply_status(i2c_bus=5, i2c_addr=0x58)

    def test_check_power_supply_status_invalid_format(self):
        """Test handling invalid format response"""
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read') as mock_read:
            mock_read.return_value = "invalid"
            
            # Should handle gracefully
            psu_murata.check_power_supply_status(i2c_bus=5, i2c_addr=0x58)


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])

