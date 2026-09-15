#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_dpu_thermal_update.py
########################################################################

import hw_management_dpu_thermal_update as dpu_thermal
import sys
import os
import tempfile
import shutil
import pytest
from unittest.mock import patch

# Add source directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))


class TestGetDpuCount:
    """Test get_dpu_count function"""

    def test_get_dpu_count_valid(self):
        """Test reading valid DPU count"""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = os.path.join(tmpdir, "config")
            os.makedirs(config_dir)
            dpu_file = os.path.join(config_dir, "dpu_num")

            with open(dpu_file, 'w') as f:
                f.write("8")

            with patch.object(dpu_thermal, 'BASE_PATH', tmpdir):
                result = dpu_thermal.get_dpu_count()
                assert result == 8

    def test_get_dpu_count_file_not_exist(self, capsys):
        """Test when dpu_num file doesn't exist"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(dpu_thermal, 'BASE_PATH', tmpdir):
                result = dpu_thermal.get_dpu_count()
                assert result == -1
                captured = capsys.readouterr()
                assert "Could not read DPU count" in captured.out

    def test_get_dpu_count_invalid_content(self, capsys):
        """Test reading invalid content from dpu_num"""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = os.path.join(tmpdir, "config")
            os.makedirs(config_dir)
            dpu_file = os.path.join(config_dir, "dpu_num")

            with open(dpu_file, 'w') as f:
                f.write("invalid")

            with patch.object(dpu_thermal, 'BASE_PATH', tmpdir):
                result = dpu_thermal.get_dpu_count()
                assert result == -1
                captured = capsys.readouterr()
                assert "Error reading DPU count" in captured.out


class TestCheckDpuIndex:
    """Test check_dpu_index function"""

    def test_check_dpu_index_valid(self):
        """Test valid DPU index"""
        with patch.object(dpu_thermal, 'get_dpu_count', return_value=8):
            assert dpu_thermal.check_dpu_index(1) is True
            assert dpu_thermal.check_dpu_index(8) is True

    def test_check_dpu_index_zero(self, capsys):
        """Test DPU index 0 (DPUs are 1-indexed)"""
        with patch.object(dpu_thermal, 'get_dpu_count', return_value=8):
            result = dpu_thermal.check_dpu_index(0)
            assert result is False
            captured = capsys.readouterr()
            assert "out of bound" in captured.out

    def test_check_dpu_index_out_of_bound(self, capsys):
        """Test DPU index beyond count"""
        with patch.object(dpu_thermal, 'get_dpu_count', return_value=8):
            result = dpu_thermal.check_dpu_index(9)
            assert result is False
            captured = capsys.readouterr()
            assert "out of bound" in captured.out

    def test_check_dpu_index_count_unavailable(self):
        """Test when DPU count cannot be read"""
        with patch.object(dpu_thermal, 'get_dpu_count', return_value=-1):
            result = dpu_thermal.check_dpu_index(1)
            assert result is False


class TestRemoveFileSafe:
    """Test remove_file_safe function"""

    def test_remove_file_safe_existing_file(self):
        """Test removing existing file"""
        with tempfile.NamedTemporaryFile(delete=False) as f:
            temp_file = f.name

        try:
            # File exists
            assert os.path.exists(temp_file)

            dpu_thermal.remove_file_safe(temp_file)

            # File should be removed
            assert not os.path.exists(temp_file)
        finally:
            if os.path.exists(temp_file):
                os.unlink(temp_file)

    def test_remove_file_safe_nonexistent_file(self):
        """Test removing nonexistent file - should not raise error"""
        # Should handle gracefully
        dpu_thermal.remove_file_safe("/nonexistent/file")

    def test_remove_file_safe_permission_error(self, capsys):
        """Test removing file with permission error"""
        with patch('os.path.exists', return_value=True):
            with patch('os.remove', side_effect=PermissionError("No permission")):
                dpu_thermal.remove_file_safe("/test/file")

                captured = capsys.readouterr()
                assert "file path didn't exist" in captured.out


class TestCreatePathSafe:
    """Test create_path_safe function"""

    def test_create_path_safe_new_directory(self):
        """Test creating new directory"""
        with tempfile.TemporaryDirectory() as tmpdir:
            new_path = os.path.join(tmpdir, "new_dir")

            result = dpu_thermal.create_path_safe(new_path)

            assert result is True
            assert os.path.exists(new_path)

    def test_create_path_safe_existing_directory(self):
        """Test when directory already exists"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Directory already exists
            result = dpu_thermal.create_path_safe(tmpdir)

            assert result is True

    def test_create_path_safe_creation_error(self, capsys):
        """Test when directory creation fails"""
        with patch('os.path.exists', return_value=False):
            with patch('os.mkdir', side_effect=OSError("Cannot create")):
                result = dpu_thermal.create_path_safe("/invalid/path")

                assert result is False
                captured = capsys.readouterr()
                assert "Path can't be created" in captured.out


class TestThermalDataDpuCpuCoreSet:
    """Test thermal_data_dpu_cpu_core_set function"""

    def test_thermal_data_dpu_cpu_core_set_basic(self):
        """Test setting DPU CPU core thermal data"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(dpu_thermal, 'BASE_PATH', tmpdir):
                with patch.object(dpu_thermal, 'check_dpu_index', return_value=True):
                    result = dpu_thermal.thermal_data_dpu_cpu_core_set(
                        dpu_index=1,
                        temperature=45000,
                        warning_threshold=85000,
                        critical_temperature=105000,
                        fault=0
                    )

                    assert result is True

                    # Verify files were created
                    cpu_pack_file = os.path.join(tmpdir, "dpu1/thermal/cpu_pack")
                    assert os.path.exists(cpu_pack_file)
                    with open(cpu_pack_file) as f:
                        assert f.read() == "45000"

    def test_thermal_data_dpu_cpu_core_set_no_thresholds(self):
        """Test setting DPU CPU data without optional thresholds"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(dpu_thermal, 'BASE_PATH', tmpdir):
                with patch.object(dpu_thermal, 'check_dpu_index', return_value=True):
                    result = dpu_thermal.thermal_data_dpu_cpu_core_set(
                        dpu_index=1,
                        temperature=50000
                    )

                    assert result is True

    def test_thermal_data_dpu_cpu_core_set_invalid_index(self):
        """Test with invalid DPU index"""
        with patch.object(dpu_thermal, 'check_dpu_index', return_value=False):
            result = dpu_thermal.thermal_data_dpu_cpu_core_set(
                dpu_index=999,
                temperature=50000
            )

            assert result is False

    def test_thermal_data_dpu_cpu_core_set_path_creation_fails(self):
        """Test when path creation fails"""
        with patch.object(dpu_thermal, 'check_dpu_index', return_value=True):
            with patch.object(dpu_thermal, 'create_path_safe', return_value=False):
                result = dpu_thermal.thermal_data_dpu_cpu_core_set(
                    dpu_index=1,
                    temperature=50000
                )

                assert result is False


class TestThermalDataDpuDdrSet:
    """Test thermal_data_dpu_ddr_set function"""

    def test_thermal_data_dpu_ddr_set_basic(self):
        """Test setting DPU DDR thermal data"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(dpu_thermal, 'BASE_PATH', tmpdir):
                with patch.object(dpu_thermal, 'check_dpu_index', return_value=True):
                    result = dpu_thermal.thermal_data_dpu_ddr_set(
                        dpu_index=2,
                        temperature=40000,
                        warning_threshold=80000,
                        critical_temperature=95000
                    )

                    assert result is True

                    # Verify sodimm files were created
                    sodimm_file = os.path.join(tmpdir, "dpu2/thermal/sodimm_temp_input")
                    assert os.path.exists(sodimm_file)

    def test_thermal_data_dpu_ddr_set_invalid_index(self):
        """Test DDR set with invalid DPU index"""
        with patch.object(dpu_thermal, 'check_dpu_index', return_value=False):
            result = dpu_thermal.thermal_data_dpu_ddr_set(
                dpu_index=999,
                temperature=40000
            )

            assert result is False


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
