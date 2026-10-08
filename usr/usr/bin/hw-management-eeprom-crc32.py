#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause
#
# EEPROM CRC32 Calculator
# Purpose: Calculate CRC32 checksum for EEPROM data (ONIE TLV standard)
# Usage: hw-management-eeprom-crc32.py <input_file>

import sys
import os


def init_crc_table():
    """Initialize CRC32 lookup table."""
    table = []
    for n in range(256):
        c = n
        for k in range(8):
            c = 0xedb88320 ^ (c >> 1) if c & 1 else c >> 1
        table.append(c)
    return table


# Initialize CRC32 table at module level
CRC_TABLE = init_crc_table()


def calc_crc32(data):
    """
    Calculate CRC32 checksum for given data.

    Args:
        data: Binary data bytes

    Returns:
        CRC32 checksum as integer
    """
    crc = 0xFFFFFFFF
    for byte in data:
        crc = CRC_TABLE[(crc ^ byte) & 0xFF] ^ (crc >> 8)
    return crc ^ 0xFFFFFFFF


def format_crc32_big_endian(crc):
    """
    Format CRC32 value as big-endian byte string (ONIE standard).

    Args:
        crc: CRC32 value as integer

    Returns:
        String with space-separated hex bytes in big-endian format
    """
    byte0 = (crc >> 24) & 0xFF
    byte1 = (crc >> 16) & 0xFF
    byte2 = (crc >> 8) & 0xFF
    byte3 = crc & 0xFF
    return f'0x{byte0:02x} 0x{byte1:02x} 0x{byte2:02x} 0x{byte3:02x}'


def main():
    """Main entry point."""
    if len(sys.argv) != 2:
        print("Usage: hw-management-eeprom-crc32.py <input_file>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]

    if not os.path.exists(input_file):
        print(f"ERROR: Input file not found: {input_file}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(input_file, 'rb') as f:
            data = f.read()

        if not data:
            print("ERROR: Input file is empty", file=sys.stderr)
            sys.exit(1)

        crc = calc_crc32(data)
        print(format_crc32_big_endian(crc))

    except PermissionError:
        print(f"ERROR: Permission denied reading file: {input_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
