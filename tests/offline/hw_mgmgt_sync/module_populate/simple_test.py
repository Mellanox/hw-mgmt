#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

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
        # Auto-detect - use relative path from test location
        script_dir = os.path.dirname(os.path.abspath(__file__))
        hw_mgmt_dir = os.path.join(script_dir, '..', '..', '..', '..', 'usr', 'usr', 'bin')
        hw_mgmt_dir = os.path.abspath(hw_mgmt_dir)
        if not os.path.exists(os.path.join(hw_mgmt_dir, 'hw_management_sync.py')):
            raise FileNotFoundError(f"Cannot find hw_management_sync.py in {hw_mgmt_dir}")

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
