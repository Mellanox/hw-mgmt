#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_psu_fw_update_murata.py
########################################################################

import hw_management_psu_fw_update_murata as psu_murata
import sys
import os
import pytest
from unittest.mock import patch, MagicMock

# Add source directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))


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
            assert "bootoader_mode" in captured.out or "bootload_complete" in captured.out

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


class TestTwoComplementChecksum:
    """Tests for two_complement_checksum() — pure math, no I/O."""

    def test_zero_data_returns_zero(self):
        assert psu_murata.two_complement_checksum([0, 0, 0]) == 0

    def test_single_byte_gives_twos_complement(self):
        # sum=1 → -(1%256) & 0xFF = 255
        assert psu_murata.two_complement_checksum([1]) == 255

    def test_sum_wraps_to_zero(self):
        # sum=256 → -(256%256) & 0xFF = 0
        assert psu_murata.two_complement_checksum([128, 128]) == 0

    def test_result_always_single_byte(self):
        for v in [1, 17, 127, 200, 255]:
            result = psu_murata.two_complement_checksum([v])
            assert 0 <= result <= 255

    def test_checksum_and_data_sum_to_zero(self):
        data = [0xfa, 0x44, 0x00, 0x00, 0xAA, 0xBB]
        chk = psu_murata.two_complement_checksum(data)
        assert (sum(data) + chk) % 256 == 0

    def test_known_payload(self):
        # upgrade_data_command builds [0xfa, 0x44, 0x0, 0x0] + data + [0x0, chk]
        # With data=[0x10, 0x20]: sum without chk = 0xfa+0x44+0+0+0x10+0x20+0 = 0x168+0 → ...
        data = [0xfa, 0x44, 0x0, 0x0, 0x10, 0x20, 0x0]
        chk = psu_murata.two_complement_checksum(data)
        assert (sum(data) + chk) % 256 == 0


class TestPollUpgradeStatus:
    """Tests for poll_upgrade_status()."""

    def _mock_read(self, val):
        return patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read', return_value=val)

    def test_success_code(self):
        with self._mock_read('0x81'):
            assert psu_murata.poll_upgrade_status(1, 0x40) == "POLL_STATUS_SUCCSESS"

    def test_busy_code(self):
        with self._mock_read('0x55'):
            assert psu_murata.poll_upgrade_status(1, 0x40) == "POLL_STATUS_BUSY"

    def test_notactive_code(self):
        with self._mock_read('0xaa'):
            assert psu_murata.poll_upgrade_status(1, 0x40) == "POLL_STATUS_NOTACTIVE"

    def test_failed_code(self):
        with self._mock_read('0x18'):
            assert psu_murata.poll_upgrade_status(1, 0x40) == "POLL_STATUS_FAILED"

    def test_powerdown_code(self):
        with self._mock_read('0x33'):
            assert psu_murata.poll_upgrade_status(1, 0x40) == "POLL_STATUS_POWERDOWN"

    def test_data_error_code(self):
        with self._mock_read('0x16'):
            assert psu_murata.poll_upgrade_status(1, 0x40) == "POLL_STATUS_DATA_ERROR"

    def test_unknown_code_returns_undefined(self):
        with self._mock_read('0xFF'):
            assert psu_murata.poll_upgrade_status(1, 0x40) == "POLL_STATUS_UNDEFINED"

    def test_empty_response_returns_none(self):
        with self._mock_read(''):
            assert psu_murata.poll_upgrade_status(1, 0x40) is None

    def test_short_response_returns_none(self):
        with self._mock_read('0x'):
            assert psu_murata.poll_upgrade_status(1, 0x40) is None


class TestMurataPollUpgradeStatusFn:
    """Tests for murata's test_poll_upgrade_status() function (retry logic)."""

    def test_success_does_not_exit(self):
        with patch.object(psu_murata, 'poll_upgrade_status', return_value='POLL_STATUS_SUCCSESS'), \
             patch('time.sleep'):
            psu_murata.test_poll_upgrade_status(1, 0x40)

    def test_busy_retries_then_succeeds(self):
        responses = iter(['POLL_STATUS_BUSY', 'POLL_STATUS_BUSY', 'POLL_STATUS_SUCCSESS'])
        with patch.object(psu_murata, 'poll_upgrade_status', side_effect=responses), \
             patch('time.sleep') as mock_sleep:
            psu_murata.test_poll_upgrade_status(1, 0x40)
            assert mock_sleep.call_count == 2

    def test_failure_exits(self):
        with patch.object(psu_murata, 'poll_upgrade_status', return_value='POLL_STATUS_FAILED'), \
             patch('time.sleep'):
            with pytest.raises(SystemExit):
                psu_murata.test_poll_upgrade_status(1, 0x40)

    def test_too_many_busy_retries_exits(self):
        with patch.object(psu_murata, 'poll_upgrade_status', return_value='POLL_STATUS_BUSY'), \
             patch('time.sleep'):
            with pytest.raises(SystemExit):
                psu_murata.test_poll_upgrade_status(1, 0x40)


class TestBootloaderStatus:
    """Tests for bootloader_status()."""

    def _mock_read(self, val):
        return patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_read', return_value=val)

    def test_zero_returns_none_status(self):
        with self._mock_read('0x00'):
            result = psu_murata.bootloader_status(1, 0x40)
            assert result == "BOOTLOADER_STATUS_NONE"

    def test_primary_bootloading(self):
        with self._mock_read('0x01'):
            result = psu_murata.bootloader_status(1, 0x40)
            assert result == "B0OTLOADING_PRIMARY"

    def test_empty_response_returns_none(self):
        with self._mock_read(''):
            result = psu_murata.bootloader_status(1, 0x40)
            assert result is None


class TestUpgradeDataCommand:
    """Tests for upgrade_data_command()."""

    def test_calls_write_nopec(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock:
            psu_murata.upgrade_data_command(1, 0x60, [0xAA, 0xBB])
            mock.assert_called_once()

    def test_send_data_starts_with_header(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock:
            psu_murata.upgrade_data_command(1, 0x60, [0xAA])
            data = mock.call_args[0][2]
            assert data[:4] == [0xfa, 0x44, 0x0, 0x0]

    def test_send_data_contains_payload(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock:
            psu_murata.upgrade_data_command(1, 0x60, [0xDE, 0xAD])
            data = mock.call_args[0][2]
            assert 0xDE in data
            assert 0xAD in data

    def test_checksum_makes_total_zero(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock:
            psu_murata.upgrade_data_command(1, 0x60, [0x10, 0x20])
            data = mock.call_args[0][2]
            assert sum(data) % 256 == 0


class TestEnterBootloadMode:
    """Tests for enter_bootload_mode()."""

    def test_primary_sends_primary_type(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock:
            psu_murata.enter_bootload_mode(1, psu_murata.BOOTLOADER_I2C_ADDR, True)
            data = mock.call_args[0][2]
            assert psu_murata.microtype_dict["MICROTYPE_PRIMARY"] in data

    def test_secondary_sends_secondary_type(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock:
            psu_murata.enter_bootload_mode(1, psu_murata.BOOTLOADER_I2C_ADDR, False)
            data = mock.call_args[0][2]
            assert psu_murata.microtype_dict["MICROTYPE_SECONDARY"] in data

    def test_bootloader_addr_uses_nopec(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock_nopec, \
             patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write') as mock_write:
            psu_murata.enter_bootload_mode(1, psu_murata.BOOTLOADER_I2C_ADDR, True)
            mock_nopec.assert_called_once()
            mock_write.assert_not_called()

    def test_other_addr_uses_write(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock_nopec, \
             patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write') as mock_write:
            psu_murata.enter_bootload_mode(1, 0x58, True)
            mock_write.assert_called_once()
            mock_nopec.assert_not_called()

    def test_data_starts_with_bootload_header(self):
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.pmbus_write_nopec') as mock:
            psu_murata.enter_bootload_mode(1, psu_murata.BOOTLOADER_I2C_ADDR, True)
            data = mock.call_args[0][2]
            assert data[:2] == [0xfa, 0x42]


class TestBurnFwFile:
    """Tests for burn_fw_file()."""

    def test_parses_data_section(self, tmp_path):
        fw = tmp_path / "test.fw"
        fw.write_text("[data]\n=AABBCCDD\n[checksum]\ncrc\n")
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.progress_bar'), \
             patch.object(psu_murata, 'upgrade_data_command') as mock_cmd, \
             patch.object(psu_murata, 'test_poll_upgrade_status'):
            psu_murata.burn_fw_file(1, psu_murata.BOOTLOADER_I2C_ADDR, str(fw))
            mock_cmd.assert_called_once()
            data = mock_cmd.call_args[0][2]
            assert data == [0xAA, 0xBB, 0xCC, 0xDD]

    def test_multiple_data_lines(self, tmp_path):
        fw = tmp_path / "test.fw"
        fw.write_text("[data]\n=AABB\n=CCDD\n")
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.progress_bar'), \
             patch.object(psu_murata, 'upgrade_data_command') as mock_cmd, \
             patch.object(psu_murata, 'test_poll_upgrade_status'):
            psu_murata.burn_fw_file(1, psu_murata.BOOTLOADER_I2C_ADDR, str(fw))
            assert mock_cmd.call_count == 2

    def test_no_data_section_no_commands(self, tmp_path):
        fw = tmp_path / "test.fw"
        fw.write_text("[header]\nsome_header\n[checksum]\ncrc\n")
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.progress_bar'), \
             patch.object(psu_murata, 'upgrade_data_command') as mock_cmd, \
             patch.object(psu_murata, 'test_poll_upgrade_status'):
            psu_murata.burn_fw_file(1, psu_murata.BOOTLOADER_I2C_ADDR, str(fw))
            mock_cmd.assert_not_called()

    def test_prints_done_message(self, tmp_path, capsys):
        fw = tmp_path / "test.fw"
        fw.write_text("[data]\n=FF\n")
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.progress_bar'), \
             patch.object(psu_murata, 'upgrade_data_command'), \
             patch.object(psu_murata, 'test_poll_upgrade_status'):
            psu_murata.burn_fw_file(1, psu_murata.BOOTLOADER_I2C_ADDR, str(fw))
            assert "Done" in capsys.readouterr().out

    def test_checksum_section_stops_data(self, tmp_path):
        fw = tmp_path / "test.fw"
        fw.write_text("[data]\n=AABB\n[checksum]\n=CCDD\n")
        with patch('hw_management_psu_fw_update_murata.psu_upd_cmn.progress_bar'), \
             patch.object(psu_murata, 'upgrade_data_command') as mock_cmd, \
             patch.object(psu_murata, 'test_poll_upgrade_status'):
            psu_murata.burn_fw_file(1, psu_murata.BOOTLOADER_I2C_ADDR, str(fw))
            # Only one data line before [checksum]
            assert mock_cmd.call_count == 1


class TestDetectAddress60:
    """Tests for detect_address_60()."""

    def test_proceed_true_prints_proceed(self, capsys):
        with patch('os.popen') as mock_popen:
            mock_popen.return_value.read.return_value = ""
            psu_murata.detect_address_60(1, True)
            assert "proceed" in capsys.readouterr().out

    def test_addr_60_free_no_error(self):
        with patch('os.popen') as mock_popen:
            # "60: --" → re.findall(r'60: (..)', ...) = ["--"] → addr_60[0] != "60"
            mock_popen.return_value.read.return_value = "     60\n60: --"
            psu_murata.detect_address_60(1, False)  # should not exit

    def test_addr_60_occupied_exits(self):
        with patch('os.popen') as mock_popen:
            # "60: 60" → re.findall = ["60"] → occupied; no 70 entry → else branch → exit(1)
            mock_popen.return_value.read.return_value = "     60\n60: 60"
            with pytest.raises(SystemExit):
                psu_murata.detect_address_60(1, False)


class TestModuleConstants:
    """Verify key module constants."""

    def test_bootloader_i2c_addr_is_0x60(self):
        assert psu_murata.BOOTLOADER_I2C_ADDR == 0x60

    def test_upgrade_status_dict_has_success(self):
        assert psu_murata.upgrade_status_dict[0x81] == "POLL_STATUS_SUCCSESS"

    def test_upgrade_status_dict_has_busy(self):
        assert psu_murata.upgrade_status_dict[0x55] == "POLL_STATUS_BUSY"

    def test_microtype_primary_not_secondary(self):
        assert psu_murata.microtype_dict["MICROTYPE_PRIMARY"] != \
               psu_murata.microtype_dict["MICROTYPE_SECONDARY"]

    def test_upgrade_status_dict_all_string_values(self):
        for key, val in psu_murata.upgrade_status_dict.items():
            assert isinstance(val, str)


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
