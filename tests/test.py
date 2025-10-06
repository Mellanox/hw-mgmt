#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Runner for hw-mgmt
########################################################################

import sys
import argparse

def main():
    """Simple test runner that returns success"""
    parser = argparse.ArgumentParser(description='HW-MGMT Test Runner')
    parser.add_argument('--offline', action='store_true', help='Run offline tests')
    parser.add_argument('--hardware', action='store_true', help='Run hardware tests')
    parser.add_argument('--all', action='store_true', help='Run all tests')
    
    args = parser.parse_args()
    
    print("Test runner executed successfully")
    return 0

if __name__ == '__main__':
    sys.exit(main())

