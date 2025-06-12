#!/usr/bin/env python3
"""Simple test to verify folder-agnostic functionality"""

import sys
import os
import argparse

def setup_import_path(hw_mgmt_path=None):
    """Setup import path for hw_management_sync module"""
    if hw_mgmt_path:
        if os.path.isfile(hw_mgmt_path):
            hw_mgmt_dir = os.path.dirname(os.path.abspath(hw_mgmt_path))
        else:
            hw_mgmt_dir = os.path.abspath(hw_mgmt_path)
    else:
        # Auto-detect
        if os.path.exists('./hw_management_sync.py'):
            hw_mgmt_dir = '.'
        elif os.path.exists('./bin/hw_management_sync.py'):
            hw_mgmt_dir = './bin'
        else:
            raise FileNotFoundError("Cannot find hw_management_sync.py")
    
    hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)
    if hw_mgmt_dir not in sys.path:
        sys.path.insert(0, hw_mgmt_dir)
    return hw_mgmt_dir

def main():
    parser = argparse.ArgumentParser(description='Simple test for folder-agnostic functionality')
    parser.add_argument('--hw-mgmt-path', help='Path to hw_management_sync.py')
    args = parser.parse_args()

    try:
        hw_mgmt_dir = setup_import_path(args.hw_mgmt_path)
        print(f"Found hw_management_sync.py in: {hw_mgmt_dir}")
        
        from hw_management_sync import CONST, sdk_temp2degree, module_temp_populate
        print("✅ Import successful!")
        print(f"✅ CONST.SDK_FW_CONTROL = {CONST.SDK_FW_CONTROL}")
        print(f"✅ CONST.SDK_SW_CONTROL = {CONST.SDK_SW_CONTROL}")
        print(f"✅ sdk_temp2degree(25) = {sdk_temp2degree(25)}")
        print(f"✅ sdk_temp2degree(-10) = {sdk_temp2degree(-10)}")
        
        # Test temperature conversion formula
        assert sdk_temp2degree(25) == 25 * 125, "Positive temperature conversion failed"
        assert sdk_temp2degree(-10) == 0xffff + (-10) + 1, "Negative temperature conversion failed"
        print("✅ Temperature conversion tests PASSED")
        
        # Test constants
        assert CONST.SDK_FW_CONTROL == 0, "SDK_FW_CONTROL should be 0"
        assert CONST.SDK_SW_CONTROL == 1, "SDK_SW_CONTROL should be 1"
        print("✅ Constants tests PASSED")
        
        # Test function exists
        assert callable(module_temp_populate), "module_temp_populate should be callable"
        print("✅ Function existence tests PASSED")
        
        print("✅ ALL TESTS PASSED!")
        print(f"✅ Successfully tested folder-agnostic import from: {hw_mgmt_dir}")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1
    
    return 0

if __name__ == '__main__':
    exit(main()) 