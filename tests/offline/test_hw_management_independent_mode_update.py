#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_independent_mode_update.py
########################################################################

import sys
import os
import tempfile
import shutil
import pytest
from unittest.mock import patch, mock_open
from pathlib import Path

# Add source directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))

import hw_management_independent_mode_update as ind_mode


class TestGetAsicCount:
    """Test get_asic_count function"""

    def test_get_asic_count_valid(self):
        """Test reading valid ASIC count"""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = os.path.join(tmpdir, "config")
            os.makedirs(config_dir)
            asic_file = os.path.join(config_dir, "asic_num")
            
            with open(asic_file, 'w') as f:
                f.write("4")
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                result = ind_mode.get_asic_count()
                assert result == 4

    def test_get_asic_count_file_not_exist(self, capsys):
        """Test when asic_num file doesn't exist"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                result = ind_mode.get_asic_count()
                assert result is False
                captured = capsys.readouterr()
                assert "Could not read ASIC count" in captured.out

    def test_get_asic_count_invalid_content(self, capsys):
        """Test reading invalid content from asic_num"""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = os.path.join(tmpdir, "config")
            os.makedirs(config_dir)
            asic_file = os.path.join(config_dir, "asic_num")
            
            with open(asic_file, 'w') as f:
                f.write("not_a_number")
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                result = ind_mode.get_asic_count()
                assert result is False
                captured = capsys.readouterr()
                assert "Error reading asic count" in captured.out


class TestGetModuleCount:
    """Test get_module_count function"""

    def test_get_module_count_valid(self):
        """Test reading valid module count"""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = os.path.join(tmpdir, "config")
            os.makedirs(config_dir)
            module_file = os.path.join(config_dir, "module_counter")
            
            with open(module_file, 'w') as f:
                f.write("64")
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                result = ind_mode.get_module_count()
                assert result == 64

    def test_get_module_count_file_not_exist(self, capsys):
        """Test when module_counter file doesn't exist"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                result = ind_mode.get_module_count()
                assert result is False
                captured = capsys.readouterr()
                assert "Could not read module count" in captured.out

    def test_get_module_count_invalid_content(self, capsys):
        """Test reading invalid content from module_counter"""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = os.path.join(tmpdir, "config")
            os.makedirs(config_dir)
            module_file = os.path.join(config_dir, "module_counter")
            
            with open(module_file, 'w') as f:
                f.write("invalid")
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                result = ind_mode.get_module_count()
                assert result is False
                captured = capsys.readouterr()
                assert "Error reading module count" in captured.out


class TestCheckAsicIndex:
    """Test check_asic_index function"""

    def test_check_asic_index_valid(self):
        """Test valid ASIC index"""
        with patch.object(ind_mode, 'get_asic_count', return_value=4):
            assert ind_mode.check_asic_index(0) is True
            assert ind_mode.check_asic_index(3) is True

    def test_check_asic_index_out_of_bound(self, capsys):
        """Test ASIC index out of bounds"""
        with patch.object(ind_mode, 'get_asic_count', return_value=4):
            result = ind_mode.check_asic_index(4)
            assert result is False
            captured = capsys.readouterr()
            assert "out of bound" in captured.out

    def test_check_asic_index_negative(self, capsys):
        """Test negative ASIC index"""
        with patch.object(ind_mode, 'get_asic_count', return_value=4):
            result = ind_mode.check_asic_index(-1)
            assert result is False

    def test_check_asic_index_count_unavailable(self):
        """Test when ASIC count cannot be read"""
        with patch.object(ind_mode, 'get_asic_count', return_value=False):
            result = ind_mode.check_asic_index(0)
            assert result is False


class TestCheckModuleIndex:
    """Test check_module_index function"""

    def test_check_module_index_valid(self):
        """Test valid module index"""
        with patch.object(ind_mode, 'get_module_count', return_value=64):
            assert ind_mode.check_module_index(0, 1) is True
            assert ind_mode.check_module_index(0, 64) is True

    def test_check_module_index_zero(self, capsys):
        """Test module index 0 (modules are 1-indexed)"""
        with patch.object(ind_mode, 'get_module_count', return_value=64):
            result = ind_mode.check_module_index(0, 0)
            assert result is False
            captured = capsys.readouterr()
            assert "out of bound" in captured.out

    def test_check_module_index_out_of_bound(self, capsys):
        """Test module index beyond count"""
        with patch.object(ind_mode, 'get_module_count', return_value=64):
            result = ind_mode.check_module_index(0, 65)
            assert result is False
            captured = capsys.readouterr()
            assert "out of bound" in captured.out

    def test_check_module_index_count_unavailable(self):
        """Test when module count cannot be read"""
        with patch.object(ind_mode, 'get_module_count', return_value=False):
            result = ind_mode.check_module_index(0, 1)
            assert result is False


class TestModuleDataSetModuleCounter:
    """Test module_data_set_module_counter function"""

    def test_set_module_counter_valid(self):
        """Test setting valid module counter"""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = os.path.join(tmpdir, "config")
            os.makedirs(config_dir)
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                result = ind_mode.module_data_set_module_counter(32)
                assert result is True
                
                # Verify file was written
                module_file = os.path.join(config_dir, "module_counter")
                with open(module_file) as f:
                    assert f.read() == "32"

    def test_set_module_counter_negative(self, capsys):
        """Test setting negative module counter"""
        result = ind_mode.module_data_set_module_counter(-1)
        assert result is False
        captured = capsys.readouterr()
        assert "Could not set module count" in captured.out

    def test_set_module_counter_write_error(self, capsys):
        """Test error during file write"""
        with patch('builtins.open', side_effect=OSError("Permission denied")):
            result = ind_mode.module_data_set_module_counter(32)
            assert result is False
            captured = capsys.readouterr()
            assert "Error setting module counter" in captured.out


class TestThermalDataSetAsic:
    """Test thermal_data_set_asic function"""

    def test_set_asic_data_index_zero(self):
        """Test setting thermal data for ASIC index 0"""
        with tempfile.TemporaryDirectory() as tmpdir:
            thermal_dir = os.path.join(tmpdir, "thermal")
            os.makedirs(thermal_dir)
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    result = ind_mode.thermal_data_set_asic(0, 45000, 85000, 105000, 0)
                    assert result is True
                    
                    # Verify files were written
                    assert os.path.exists(os.path.join(thermal_dir, "asic"))
                    assert os.path.exists(os.path.join(thermal_dir, "asic_temp_crit"))
                    assert os.path.exists(os.path.join(thermal_dir, "asic_temp_emergency"))
                    assert os.path.exists(os.path.join(thermal_dir, "asic_temp_fault"))
                    
                    with open(os.path.join(thermal_dir, "asic")) as f:
                        assert f.read() == "45000"

    def test_set_asic_data_index_nonzero(self):
        """Test setting thermal data for ASIC index > 0"""
        with tempfile.TemporaryDirectory() as tmpdir:
            thermal_dir = os.path.join(tmpdir, "thermal")
            os.makedirs(thermal_dir)
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    result = ind_mode.thermal_data_set_asic(1, 50000, 90000, 110000)
                    assert result is True
                    
                    # Verify files were written with correct naming (asic2 for index 1)
                    assert os.path.exists(os.path.join(thermal_dir, "asic2"))
                    assert os.path.exists(os.path.join(thermal_dir, "asic2_temp_crit"))

    def test_set_asic_data_invalid_index(self):
        """Test setting thermal data with invalid ASIC index"""
        with patch.object(ind_mode, 'check_asic_index', return_value=False):
            result = ind_mode.thermal_data_set_asic(999, 45000, 85000, 105000)
            assert result is False

    def test_set_asic_data_write_error(self, capsys):
        """Test error during file write"""
        with patch.object(ind_mode, 'check_asic_index', return_value=True):
            with patch('builtins.open', side_effect=OSError("Write failed")):
                result = ind_mode.thermal_data_set_asic(0, 45000, 85000, 105000)
                assert result is False
                captured = capsys.readouterr()
                assert "Error setting thermal data for ASIC" in captured.out


class TestThermalDataSetModule:
    """Test thermal_data_set_module function"""

    def test_set_module_data_valid(self):
        """Test setting thermal data for module"""
        with tempfile.TemporaryDirectory() as tmpdir:
            thermal_dir = os.path.join(tmpdir, "thermal")
            os.makedirs(thermal_dir)
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    with patch.object(ind_mode, 'check_module_index', return_value=True):
                        result = ind_mode.thermal_data_set_module(0, 1, 40000, 80000, 100000, 0)
                        assert result is True
                        
                        # Verify files were written
                        assert os.path.exists(os.path.join(thermal_dir, "module1_temp_input"))
                        assert os.path.exists(os.path.join(thermal_dir, "module1_temp_crit"))
                        assert os.path.exists(os.path.join(thermal_dir, "module1_temp_emergency"))
                        assert os.path.exists(os.path.join(thermal_dir, "module1_temp_fault"))
                        
                        with open(os.path.join(thermal_dir, "module1_temp_input")) as f:
                            assert f.read() == "40000"

    def test_set_module_data_invalid_asic_index(self):
        """Test setting module data with invalid ASIC index"""
        with patch.object(ind_mode, 'check_asic_index', return_value=False):
            result = ind_mode.thermal_data_set_module(999, 1, 40000, 80000, 100000)
            assert result is False

    def test_set_module_data_invalid_module_index(self):
        """Test setting module data with invalid module index"""
        with patch.object(ind_mode, 'check_asic_index', return_value=True):
            with patch.object(ind_mode, 'check_module_index', return_value=False):
                result = ind_mode.thermal_data_set_module(0, 999, 40000, 80000, 100000)
                assert result is False

    def test_set_module_data_write_error(self, capsys):
        """Test error during file write"""
        with patch.object(ind_mode, 'check_asic_index', return_value=True):
            with patch.object(ind_mode, 'check_module_index', return_value=True):
                with patch('builtins.open', side_effect=OSError("Write failed")):
                    result = ind_mode.thermal_data_set_module(0, 1, 40000, 80000, 100000)
                    assert result is False
                    captured = capsys.readouterr()
                    assert "Error setting thermal data for Module" in captured.out


class TestThermalDataCleanAsic:
    """Test thermal_data_clean_asic function"""

    def test_clean_asic_data_index_zero(self):
        """Test cleaning thermal data for ASIC index 0"""
        with tempfile.TemporaryDirectory() as tmpdir:
            thermal_dir = os.path.join(tmpdir, "thermal")
            os.makedirs(thermal_dir)
            
            # Create files to be cleaned
            files = ["asic", "asic_temp_crit", "asic_temp_emergency", "asic_temp_fault"]
            for filename in files:
                open(os.path.join(thermal_dir, filename), 'w').close()
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    result = ind_mode.thermal_data_clean_asic(0)
                    assert result is True
                    
                    # Verify files were removed
                    for filename in files:
                        assert not os.path.exists(os.path.join(thermal_dir, filename))

    def test_clean_asic_data_index_nonzero(self):
        """Test cleaning thermal data for ASIC index > 0"""
        with tempfile.TemporaryDirectory() as tmpdir:
            thermal_dir = os.path.join(tmpdir, "thermal")
            os.makedirs(thermal_dir)
            
            # Create files to be cleaned (asic2 for index 1)
            files = ["asic2", "asic2_temp_crit", "asic2_temp_emergency", "asic2_temp_fault"]
            for filename in files:
                open(os.path.join(thermal_dir, filename), 'w').close()
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    result = ind_mode.thermal_data_clean_asic(1)
                    assert result is True

    def test_clean_asic_data_invalid_index(self):
        """Test cleaning with invalid ASIC index"""
        with patch.object(ind_mode, 'check_asic_index', return_value=False):
            result = ind_mode.thermal_data_clean_asic(999)
            assert result is False

    def test_clean_asic_data_file_not_exist(self, capsys):
        """Test cleaning when files don't exist"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    result = ind_mode.thermal_data_clean_asic(0)
                    assert result is False
                    captured = capsys.readouterr()
                    assert "Error cleaning thermal data for ASIC" in captured.out


class TestThermalDataCleanModule:
    """Test thermal_data_clean_module function"""

    def test_clean_module_data_valid(self):
        """Test cleaning thermal data for module"""
        with tempfile.TemporaryDirectory() as tmpdir:
            thermal_dir = os.path.join(tmpdir, "thermal")
            os.makedirs(thermal_dir)
            
            # Create files to be cleaned
            files = ["module1_temp_input", "module1_temp_crit", 
                    "module1_temp_emergency", "module1_temp_fault"]
            for filename in files:
                open(os.path.join(thermal_dir, filename), 'w').close()
            
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    with patch.object(ind_mode, 'check_module_index', return_value=True):
                        result = ind_mode.thermal_data_clean_module(0, 1)
                        assert result is True
                        
                        # Verify files were removed
                        for filename in files:
                            assert not os.path.exists(os.path.join(thermal_dir, filename))

    def test_clean_module_data_invalid_asic_index(self):
        """Test cleaning with invalid ASIC index"""
        with patch.object(ind_mode, 'check_asic_index', return_value=False):
            result = ind_mode.thermal_data_clean_module(999, 1)
            assert result is False

    def test_clean_module_data_invalid_module_index(self):
        """Test cleaning with invalid module index"""
        with patch.object(ind_mode, 'check_asic_index', return_value=True):
            with patch.object(ind_mode, 'check_module_index', return_value=False):
                result = ind_mode.thermal_data_clean_module(0, 999)
                assert result is False

    def test_clean_module_data_file_not_exist(self, capsys):
        """Test cleaning when files don't exist"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(ind_mode, 'BASE_PATH', tmpdir):
                with patch.object(ind_mode, 'check_asic_index', return_value=True):
                    with patch.object(ind_mode, 'check_module_index', return_value=True):
                        result = ind_mode.thermal_data_clean_module(0, 1)
                        assert result is False
                        captured = capsys.readouterr()
                        assert "Error cleaning thermal data for Module" in captured.out


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])

