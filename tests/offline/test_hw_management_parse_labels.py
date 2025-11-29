#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_parse_labels.py
########################################################################

import sys
import os
import tempfile
import shutil
import json
import pickle
import pytest
from unittest.mock import patch, MagicMock, mock_open
from pathlib import Path

# Add source directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))

import hw_management_parse_labels as parse_labels


class TestLoadJson:
    """Test load_json function"""

    def test_load_json_valid_file(self):
        """Test loading valid JSON file"""
        test_data = {"key1": "value1", "key2": {"nested": "data"}}
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(test_data, f)
            temp_file = f.name
        
        try:
            result = parse_labels.load_json(temp_file)
            assert result == test_data
        finally:
            os.unlink(temp_file)

    def test_load_json_empty_object(self):
        """Test loading empty JSON object"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write('{}')
            temp_file = f.name
        
        try:
            result = parse_labels.load_json(temp_file)
            assert result == {}
        finally:
            os.unlink(temp_file)


class TestSaveLoadDictionary:
    """Test save_dictionary and load_dictionary functions"""

    def test_save_and_load_dictionary(self):
        """Test saving and loading dictionary with pickle"""
        test_dict = {
            "labels": {"temp1": "value1"},
            "scales": {"temp1": 1000},
            "nested": {"data": [1, 2, 3]}
        }
        
        with tempfile.NamedTemporaryFile(delete=False, suffix='.pkl') as f:
            temp_file = f.name
        
        try:
            # Save
            parse_labels.save_dictionary(test_dict, temp_file)
            assert os.path.exists(temp_file)
            
            # Load
            loaded_dict = parse_labels.load_dictionary(temp_file)
            assert loaded_dict == test_dict
        finally:
            os.unlink(temp_file)

    def test_save_dictionary_empty(self):
        """Test saving empty dictionary"""
        with tempfile.NamedTemporaryFile(delete=False, suffix='.pkl') as f:
            temp_file = f.name
        
        try:
            parse_labels.save_dictionary({}, temp_file)
            loaded = parse_labels.load_dictionary(temp_file)
            assert loaded == {}
        finally:
            os.unlink(temp_file)


class TestRetrieveValue:
    """Test retrieve_value function"""

    def test_retrieve_value_exact_match(self):
        """Test retrieving value with exact regex match"""
        dictionary = {
            "label1": {
                "temp.*": "temperature_sensor",
                "volt.*": "voltage_sensor"
            }
        }
        
        result = parse_labels.retrieve_value(dictionary, "label1", "temp1")
        assert result == "temperature_sensor"

    def test_retrieve_value_regex_match(self):
        """Test retrieving value with regex pattern"""
        dictionary = {
            "sensors": {
                "temp[0-9]+": "temp_value",
                "fan_\\d+": "fan_value"
            }
        }
        
        result = parse_labels.retrieve_value(dictionary, "sensors", "temp5")
        assert result == "temp_value"
        
        result = parse_labels.retrieve_value(dictionary, "sensors", "fan_3")
        assert result == "fan_value"

    def test_retrieve_value_no_match(self):
        """Test retrieving value when key doesn't match"""
        dictionary = {
            "label1": {
                "temp.*": "temperature_sensor"
            }
        }
        
        result = parse_labels.retrieve_value(dictionary, "label1", "voltage1")
        assert result is None

    def test_retrieve_value_label_not_found(self):
        """Test retrieving value when label doesn't exist"""
        dictionary = {
            "label1": {"key": "value"}
        }
        
        result = parse_labels.retrieve_value(dictionary, "label2", "key")
        assert result is None

    def test_retrieve_value_empty_dictionary(self):
        """Test retrieving value from empty dictionary"""
        result = parse_labels.retrieve_value({}, "label1", "key")
        assert result is None


class TestProcessBOMDictionary:
    """Test process_BOM_dictionary function"""

    def test_process_bom_no_sku(self):
        """Test process_BOM_dictionary with no SKU - should return unchanged"""
        original_dict = {"key": "value"}
        result = parse_labels.process_BOM_dictionary(original_dict, "/tmp/bom", None)
        assert result == original_dict

    def test_process_bom_no_alternatives(self):
        """Test process_BOM_dictionary when alternatives label doesn't exist"""
        dictionary = {
            "labels_MSN1234_rev1_array": {},
            "labels_scale_MSN1234_rev1_array": {}
        }
        
        result = parse_labels.process_BOM_dictionary(dictionary, "/tmp/bom", "MSN1234")
        assert result == dictionary

    def test_process_bom_with_alternatives_valid_bom(self):
        """Test process_BOM_dictionary with valid BOM file"""
        sku = "MSN1234"
        dictionary = {
            f"labels_{sku}_alternativies": {
                "voltmon1": {
                    "mp2891": {
                        "vin": {"name": "mp2891_vin", "scale": 1000},
                        "vout": {"name": "mp2891_vout"}
                    }
                }
            },
            f"labels_{sku}_rev1_array": {},
            f"labels_scale_{sku}_rev1_array": {}
        }
        
        # BOM file format: component_type address bus component_name (4 fields per component)
        bom_content = "mp2891 0x66 5 voltmon1 adt75 0x4a 7 swb_asic1"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(bom_content)
            bom_file = f.name
        
        try:
            result = parse_labels.process_BOM_dictionary(dictionary, bom_file, sku)
            
            # Check that labels were updated
            assert "voltmon1_vin" in result[f"labels_{sku}_rev1_array"]
            assert result[f"labels_{sku}_rev1_array"]["voltmon1_vin"] == "mp2891_vin"
            
            assert "voltmon1_vout" in result[f"labels_{sku}_rev1_array"]
            assert result[f"labels_{sku}_rev1_array"]["voltmon1_vout"] == "mp2891_vout"
            
            # Check scale was added
            assert "voltmon1_vin" in result[f"labels_scale_{sku}_rev1_array"]
            assert result[f"labels_scale_{sku}_rev1_array"]["voltmon1_vin"] == 1000
            
            # vout has no scale, shouldn't be in scale dict
            assert "voltmon1_vout" not in result[f"labels_scale_{sku}_rev1_array"]
            
        finally:
            os.unlink(bom_file)

    def test_process_bom_component_type_not_in_alternatives(self):
        """Test when component type is not defined in alternatives"""
        sku = "MSN1234"
        dictionary = {
            f"labels_{sku}_alternativies": {
                "voltmon1": {
                    "mp2891": {"vin": {"name": "mp2891_vin"}}
                    # tps53659 not defined
                }
            },
            f"labels_{sku}_rev1_array": {},
            f"labels_scale_{sku}_rev1_array": {}
        }
        
        # BOM has tps53659 but dictionary only has mp2891
        bom_content = "tps53659 0x66 5 voltmon1"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(bom_content)
            bom_file = f.name
        
        try:
            result = parse_labels.process_BOM_dictionary(dictionary, bom_file, sku)
            
            # Should skip the component, labels remain empty
            assert len(result[f"labels_{sku}_rev1_array"]) == 0
        finally:
            os.unlink(bom_file)

    def test_process_bom_component_name_not_in_alternatives(self):
        """Test when component name is not in alternatives"""
        sku = "MSN1234"
        dictionary = {
            f"labels_{sku}_alternativies": {
                "voltmon1": {"mp2891": {"vin": {"name": "mp2891_vin"}}}
            },
            f"labels_{sku}_rev1_array": {},
            f"labels_scale_{sku}_rev1_array": {}
        }
        
        # Component name "voltmon2" not in alternatives (only voltmon1 defined)
        bom_content = "mp2891 0x66 5 voltmon2"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(bom_content)
            bom_file = f.name
        
        try:
            result = parse_labels.process_BOM_dictionary(dictionary, bom_file, sku)
            
            # Should skip, labels remain empty
            assert len(result[f"labels_{sku}_rev1_array"]) == 0
        finally:
            os.unlink(bom_file)

    def test_process_bom_file_not_found(self):
        """Test process_BOM_dictionary when BOM file doesn't exist"""
        sku = "MSN1234"
        dictionary = {
            f"labels_{sku}_alternativies": {"voltmon1": {}},
            f"labels_{sku}_rev1_array": {},
            f"labels_scale_{sku}_rev1_array": {}
        }
        
        # Non-existent file - should catch exception and return unchanged
        result = parse_labels.process_BOM_dictionary(dictionary, "/nonexistent/bom", sku)
        assert result == dictionary

    def test_process_bom_malformed_file(self):
        """Test process_BOM_dictionary with malformed BOM file"""
        sku = "MSN1234"
        dictionary = {
            f"labels_{sku}_alternativies": {"voltmon1": {}},
            f"labels_{sku}_rev1_array": {},
            f"labels_scale_{sku}_rev1_array": {}
        }
        
        # Only 2 fields instead of 4 - will cause IndexError
        bom_content = "mp2891 0x66"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(bom_content)
            bom_file = f.name
        
        try:
            # Should catch exception and return unchanged
            result = parse_labels.process_BOM_dictionary(dictionary, bom_file, sku)
            assert result == dictionary
        finally:
            os.unlink(bom_file)


class TestMain:
    """Test main function and argument parsing"""

    def test_main_create_dictionary(self, capsys):
        """Test main with --json_file to create dictionary"""
        test_json = {"test": "data"}
        
        with tempfile.TemporaryDirectory() as tmpdir:
            json_file = os.path.join(tmpdir, "test.json")
            dict_file = os.path.join(tmpdir, "dict.pkl")
            
            with open(json_file, 'w') as f:
                json.dump(test_json, f)
            
            with patch('sys.argv', ['parse_labels.py', '--json_file', json_file, 
                                   '--dictionary_file', dict_file]):
                with patch('os.path.isfile', return_value=False):  # No devtree
                    parse_labels.main()
            
            captured = capsys.readouterr()
            assert "Dictionary created and saved successfully" in captured.out
            assert os.path.exists(dict_file)

    def test_main_create_dictionary_with_sku(self, capsys):
        """Test main with SKU and devtree"""
        test_json = {
            "labels_MSN1234_alternativies": {},
            "labels_MSN1234_rev1_array": {},
            "labels_scale_MSN1234_rev1_array": {}
        }
        
        with tempfile.TemporaryDirectory() as tmpdir:
            json_file = os.path.join(tmpdir, "test.json")
            dict_file = os.path.join(tmpdir, "dict.pkl")
            devtree_file = os.path.join(tmpdir, "devtree")
            
            with open(json_file, 'w') as f:
                json.dump(test_json, f)
            
            with open(devtree_file, 'w') as f:
                f.write("mp2891 0x66 5 voltmon1")
            
            with patch('sys.argv', ['parse_labels.py', '--json_file', json_file,
                                   '--dictionary_file', dict_file, '--sku', 'MSN1234']):
                with patch.object(parse_labels, 'HW_MGMT_PATH', tmpdir):
                    parse_labels.main()
            
            captured = capsys.readouterr()
            assert "Dictionary created and saved successfully" in captured.out

    def test_main_get_value_found(self, capsys):
        """Test main with --get_value when value is found"""
        test_dict = {
            "label1": {"temp.*": "temperature_value"}
        }
        
        with tempfile.TemporaryDirectory() as tmpdir:
            dict_file = os.path.join(tmpdir, "dict.pkl")
            
            with open(dict_file, 'wb') as f:
                pickle.dump(test_dict, f)
            
            with patch('sys.argv', ['parse_labels.py', '--get_value',
                                   '--label', 'label1', '--key', 'temp1',
                                   '--dictionary_file', dict_file]):
                parse_labels.main()
            
            captured = capsys.readouterr()
            assert "temperature_value" in captured.out

    def test_main_get_value_not_found(self, capsys):
        """Test main with --get_value when value is not found"""
        test_dict = {
            "label1": {"temp.*": "temperature_value"}
        }
        
        with tempfile.TemporaryDirectory() as tmpdir:
            dict_file = os.path.join(tmpdir, "dict.pkl")
            
            with open(dict_file, 'wb') as f:
                pickle.dump(test_dict, f)
            
            with patch('sys.argv', ['parse_labels.py', '--get_value',
                                   '--label', 'label1', '--key', 'voltage1',
                                   '--dictionary_file', dict_file]):
                parse_labels.main()
            
            captured = capsys.readouterr()
            # Should print empty line when not found
            assert captured.out.strip() == ""

    def test_main_no_arguments(self, capsys):
        """Test main with no arguments - should print help"""
        with patch('sys.argv', ['parse_labels.py']):
            parse_labels.main()
        
        captured = capsys.readouterr()
        # Should print help
        assert "usage:" in captured.out or "JSON Dictionary" in captured.out


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])

