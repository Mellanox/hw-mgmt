#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
"""
PMBus Register Dump Script
Dumps all PMBus registers for a given I2C device across multiple pages.
"""

import subprocess
import sys
import argparse
import os
from typing import Optional, Dict, List

# PMBus command definitions
PMBUS_COMMANDS = {
    # Standard PMBus commands
    0x00: ("PAGE", "byte", "rw"),
    0x01: ("OPERATION", "byte", "rw"),
    0x02: ("ON_OFF_CONFIG", "byte", "rw"),
    0x03: ("CLEAR_FAULTS", "send_byte", "w"),
    0x04: ("PHASE", "byte", "rw"),
    0x05: ("PAGE_PLUS_WRITE", "byte", "w"),
    0x06: ("PAGE_PLUS_READ", "byte", "w"),
    0x10: ("WRITE_PROTECT", "byte", "rw"),
    0x11: ("STORE_DEFAULT_ALL", "send_byte", "w"),
    0x12: ("RESTORE_DEFAULT_ALL", "send_byte", "w"),
    0x13: ("STORE_DEFAULT_CODE", "byte", "w"),
    0x14: ("RESTORE_DEFAULT_CODE", "byte", "w"),
    0x15: ("STORE_USER_ALL", "send_byte", "w"),
    0x16: ("RESTORE_USER_ALL", "send_byte", "w"),
    0x17: ("STORE_USER_CODE", "byte", "w"),
    0x18: ("RESTORE_USER_CODE", "byte", "w"),
    0x19: ("CAPABILITY", "byte", "r"),
    0x1A: ("QUERY", "byte", "rw"),
    0x1B: ("SMBALERT_MASK", "word", "rw"),

    # VOUT commands
    0x20: ("VOUT_MODE", "byte", "r"),
    0x21: ("VOUT_COMMAND", "word", "rw"),
    0x22: ("VOUT_TRIM", "word", "rw"),
    0x23: ("VOUT_CAL_OFFSET", "word", "rw"),
    0x24: ("VOUT_MAX", "word", "rw"),
    0x25: ("VOUT_MARGIN_HIGH", "word", "rw"),
    0x26: ("VOUT_MARGIN_LOW", "word", "rw"),
    0x27: ("VOUT_TRANSITION_RATE", "word", "rw"),
    0x28: ("VOUT_DROOP", "word", "rw"),
    0x29: ("VOUT_SCALE_LOOP", "word", "rw"),
    0x2A: ("VOUT_SCALE_MONITOR", "word", "rw"),

    # Coefficients
    0x30: ("COEFFICIENTS", "block", "r"),
    0x31: ("POUT_MAX", "word", "rw"),

    # Fault limits
    0x35: ("FREQUENCY_SWITCH", "word", "rw"),
    0x36: ("VIN_ON", "word", "rw"),
    0x37: ("VIN_OFF", "word", "rw"),
    0x38: ("INTERLEAVE", "word", "rw"),
    0x39: ("IOUT_CAL_GAIN", "word", "rw"),
    0x3A: ("IOUT_CAL_OFFSET", "word", "rw"),
    0x3B: ("FAN_CONFIG_1_2", "byte", "rw"),
    0x3C: ("FAN_COMMAND_1", "word", "rw"),
    0x3D: ("FAN_COMMAND_2", "word", "rw"),
    0x3E: ("FAN_CONFIG_3_4", "byte", "rw"),
    0x3F: ("FAN_COMMAND_3", "word", "rw"),

    # More fault limits
    0x40: ("VOUT_OV_FAULT_LIMIT", "word", "rw"),
    0x41: ("VOUT_OV_FAULT_RESPONSE", "byte", "rw"),
    0x42: ("VOUT_OV_WARN_LIMIT", "word", "rw"),
    0x43: ("VOUT_UV_WARN_LIMIT", "word", "rw"),
    0x44: ("VOUT_UV_FAULT_LIMIT", "word", "rw"),
    0x45: ("VOUT_UV_FAULT_RESPONSE", "byte", "rw"),
    0x46: ("IOUT_OC_FAULT_LIMIT", "word", "rw"),
    0x47: ("IOUT_OC_FAULT_RESPONSE", "byte", "rw"),
    0x48: ("IOUT_OC_LV_FAULT_LIMIT", "word", "rw"),
    0x49: ("IOUT_OC_LV_FAULT_RESPONSE", "byte", "rw"),
    0x4A: ("IOUT_OC_WARN_LIMIT", "word", "rw"),
    0x4B: ("IOUT_UC_FAULT_LIMIT", "word", "rw"),
    0x4C: ("IOUT_UC_FAULT_RESPONSE", "byte", "rw"),

    0x4F: ("OT_FAULT_LIMIT", "word", "rw"),
    0x50: ("OT_FAULT_RESPONSE", "byte", "rw"),
    0x51: ("OT_WARN_LIMIT", "word", "rw"),
    0x52: ("UT_WARN_LIMIT", "word", "rw"),
    0x53: ("UT_FAULT_LIMIT", "word", "rw"),
    0x54: ("UT_FAULT_RESPONSE", "byte", "rw"),
    0x55: ("VIN_OV_FAULT_LIMIT", "word", "rw"),
    0x56: ("VIN_OV_FAULT_RESPONSE", "byte", "rw"),
    0x57: ("VIN_OV_WARN_LIMIT", "word", "rw"),
    0x58: ("VIN_UV_WARN_LIMIT", "word", "rw"),
    0x59: ("VIN_UV_FAULT_LIMIT", "word", "rw"),
    0x5A: ("VIN_UV_FAULT_RESPONSE", "byte", "rw"),
    0x5B: ("IIN_OC_FAULT_LIMIT", "word", "rw"),
    0x5C: ("IIN_OC_FAULT_RESPONSE", "byte", "rw"),
    0x5D: ("IIN_OC_WARN_LIMIT", "word", "rw"),
    0x5E: ("POWER_GOOD_ON", "word", "rw"),
    0x5F: ("POWER_GOOD_OFF", "word", "rw"),

    0x60: ("TON_DELAY", "word", "rw"),
    0x61: ("TON_RISE", "word", "rw"),
    0x62: ("TON_MAX_FAULT_LIMIT", "word", "rw"),
    0x63: ("TON_MAX_FAULT_RESPONSE", "byte", "rw"),
    0x64: ("TOFF_DELAY", "word", "rw"),
    0x65: ("TOFF_FALL", "word", "rw"),
    0x66: ("TOFF_MAX_WARN_LIMIT", "word", "rw"),

    0x68: ("POUT_OP_FAULT_LIMIT", "word", "rw"),
    0x69: ("POUT_OP_FAULT_RESPONSE", "byte", "rw"),
    0x6A: ("POUT_OP_WARN_LIMIT", "word", "rw"),
    0x6B: ("PIN_OP_WARN_LIMIT", "word", "rw"),

    # Status commands
    0x78: ("STATUS_BYTE", "byte", "r"),
    0x79: ("STATUS_WORD", "word", "r"),
    0x7A: ("STATUS_VOUT", "byte", "r"),
    0x7B: ("STATUS_IOUT", "byte", "r"),
    0x7C: ("STATUS_INPUT", "byte", "r"),
    0x7D: ("STATUS_TEMPERATURE", "byte", "r"),
    0x7E: ("STATUS_CML", "byte", "r"),
    0x7F: ("STATUS_OTHER", "byte", "r"),
    0x80: ("STATUS_MFR_SPECIFIC", "byte", "r"),
    0x81: ("STATUS_FANS_1_2", "byte", "r"),
    0x82: ("STATUS_FANS_3_4", "byte", "r"),

    # Read commands
    0x86: ("READ_EIN", "block", "r"),
    0x87: ("READ_EOUT", "block", "r"),
    0x88: ("READ_VIN", "word", "r"),
    0x89: ("READ_IIN", "word", "r"),
    0x8A: ("READ_VCAP", "word", "r"),
    0x8B: ("READ_VOUT", "word", "r"),
    0x8C: ("READ_IOUT", "word", "r"),
    0x8D: ("READ_TEMPERATURE_1", "word", "r"),
    0x8E: ("READ_TEMPERATURE_2", "word", "r"),
    0x8F: ("READ_TEMPERATURE_3", "word", "r"),
    0x90: ("READ_FAN_SPEED_1", "word", "r"),
    0x91: ("READ_FAN_SPEED_2", "word", "r"),
    0x92: ("READ_FAN_SPEED_3", "word", "r"),
    0x93: ("READ_FAN_SPEED_4", "word", "r"),
    0x94: ("READ_DUTY_CYCLE", "word", "r"),
    0x95: ("READ_FREQUENCY", "word", "r"),
    0x96: ("READ_POUT", "word", "r"),
    0x97: ("READ_PIN", "word", "r"),
    0x98: ("PMBUS_REVISION", "byte", "r"),
    0x99: ("MFR_ID", "block", "r"),
    0x9A: ("MFR_MODEL", "block", "r"),
    0x9B: ("MFR_REVISION", "block", "r"),
    0x9C: ("MFR_LOCATION", "block", "r"),
    0x9D: ("MFR_DATE", "block", "r"),
    0x9E: ("MFR_SERIAL", "block", "r"),
    0x9F: ("MFR_VIN_MIN", "word", "r"),
    0xA0: ("MFR_VIN_MAX", "word", "r"),
    0xA1: ("MFR_IIN_MAX", "word", "r"),
    0xA2: ("MFR_PIN_MAX", "word", "r"),
    0xA3: ("MFR_VOUT_MIN", "word", "r"),
    0xA4: ("MFR_VOUT_MAX", "word", "r"),
    0xA5: ("MFR_IOUT_MAX", "word", "r"),
    0xA6: ("MFR_POUT_MAX", "word", "r"),
    0xA7: ("MFR_TAMBIENT_MAX", "word", "r"),
    0xA8: ("MFR_TAMBIENT_MIN", "word", "r"),
    0xA9: ("MFR_EFFICIENCY_LL", "block", "r"),
    0xAA: ("MFR_EFFICIENCY_HL", "block", "r"),
    0xAB: ("MFR_PIN_ACCURACY", "byte", "r"),
    0xAC: ("MFR_IC_DEVICE", "block", "r"),
    0xAD: ("MFR_IC_DEVICE_ID", "block", "r"),
    0xAE: ("MFR_IC_DEVICE_REV", "block", "r"),

    # User data
    0xB0: ("USER_DATA_00", "block", "rw"),
    0xB1: ("USER_DATA_01", "block", "rw"),
    0xB2: ("USER_DATA_02", "block", "rw"),
    0xB3: ("USER_DATA_03", "block", "rw"),
    0xB4: ("USER_DATA_04", "block", "rw"),

    # Additional manufacturer specific commands
    0xD0: ("MFR_SPECIFIC_00", "block", "rw"),
    0xD1: ("MFR_SPECIFIC_01", "block", "rw"),
    0xD2: ("MFR_SPECIFIC_02", "block", "rw"),
    0xD3: ("MFR_SPECIFIC_03", "block", "rw"),
    0xD4: ("MFR_SPECIFIC_04", "block", "rw"),
    0xD5: ("MFR_SPECIFIC_05", "block", "rw"),
    0xD6: ("MFR_SPECIFIC_06", "block", "rw"),
    0xD7: ("MFR_SPECIFIC_07", "block", "rw"),
    0xD8: ("MFR_SPECIFIC_08", "block", "rw"),
}


def i2c_set_page(bus: int, addr: int, page: int) -> bool:
    """Set the current PMBus page."""
    try:
        cmd = ["i2cset", "-f", "-y", str(bus), f"0x{addr:02X}", "0x00", f"0x{page:02X}"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        return result.returncode == 0
    except Exception as e:
        print(f"Error setting page {page}: {e}", file=sys.stderr)
        return False


def i2c_read_byte(bus: int, addr: int, cmd: int) -> Optional[int]:
    """Read a byte from I2C device."""
    try:
        result = subprocess.run(
            ["i2cget", "-f", "-y", str(bus), f"0x{addr:02X}", f"0x{cmd:02X}"],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0:
            return int(result.stdout.strip(), 16)
        else:
            # Log non-zero exit codes for debugging
            if result.stderr:
                print(f"i2cget failed for command 0x{cmd:02x}: {result.stderr.strip()}", file=sys.stderr)
    except FileNotFoundError:
        print("Error: i2cget command not found. Please install i2c-tools package.", file=sys.stderr)
        sys.exit(1)
    except (ValueError, subprocess.TimeoutExpired) as e:
        print(f"Error reading byte from command 0x{cmd:02x}: {e}", file=sys.stderr)
    return None


def i2c_read_word(bus: int, addr: int, cmd: int) -> Optional[int]:
    """Read a word (2 bytes) from I2C device."""
    try:
        result = subprocess.run(
            ["i2cget", "-f", "-y", str(bus), f"0x{addr:02X}", f"0x{cmd:02X}", "w"],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0:
            return int(result.stdout.strip(), 16)
        else:
            # Log non-zero exit codes for debugging
            if result.stderr:
                print(f"i2cget failed for command 0x{cmd:02x}: {result.stderr.strip()}", file=sys.stderr)
    except FileNotFoundError:
        print("Error: i2cget command not found. Please install i2c-tools package.", file=sys.stderr)
        sys.exit(1)
    except (ValueError, subprocess.TimeoutExpired) as e:
        print(f"Error reading word from command 0x{cmd:02x}: {e}", file=sys.stderr)
    return None


def i2c_read_block(bus: int, addr: int, cmd: int) -> Optional[List[int]]:
    """Read a block of data from I2C device."""
    try:
        result = subprocess.run(
            ["i2cget", "-f", "-y", str(bus), f"0x{addr:02X}", f"0x{cmd:02X}", "i"],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0:
            # Parse output like "0x07 0x49 0x6e 0x66 0x69 0x6e 0x65 0x6f"
            values = result.stdout.strip().split()
            if not values:
                return None

            # First byte is the length
            length = int(values[0], 16)

            # Validate: PMBus block reads are limited to 255 bytes max
            if length > 255:
                print(f"Warning: Invalid block length {length} for command 0x{cmd:02x}", file=sys.stderr)
                return None

            # Validate we have enough data in the buffer
            # We need length+1 values (length byte + data bytes)
            if len(values) < length + 1:
                print(f"Warning: Buffer underrun for command 0x{cmd:02x}: "
                      f"expected {length} bytes but got {len(values)-1}", file=sys.stderr)
                return None

            # Extract only the number of bytes specified by length
            data = [int(v, 16) for v in values[1:length+1]]
            return data
        else:
            # Log non-zero exit codes for debugging
            if result.stderr:
                print(f"i2cget failed for command 0x{cmd:02x}: {result.stderr.strip()}", file=sys.stderr)
    except FileNotFoundError:
        print("Error: i2cget command not found. Please install i2c-tools package.", file=sys.stderr)
        sys.exit(1)
    except (ValueError, IndexError) as e:
        print(f"Error parsing block data for command 0x{cmd:02x}: {e}", file=sys.stderr)
    except subprocess.TimeoutExpired:
        print(f"Timeout reading block data for command 0x{cmd:02x}", file=sys.stderr)
    except Exception as e:
        print(f"Unexpected error reading block data for command 0x{cmd:02x}: {e}", file=sys.stderr)
    return None


def dump_pmbus_command(bus: int, addr: int, cmd: int, name: str, data_type: str, rw: str, page: int) -> Dict:
    """Dump a single PMBus command."""
    result = {
        "page": page,
        "command": f"0x{cmd:02X}",
        "name": name,
        "type": data_type,
        "access": rw,
        "status": "not_readable",
        "raw": None,
        "formatted": None
    }

    # Skip write-only commands
    if rw == "w":
        result["status"] = "write_only"
        return result

    try:
        if data_type == "byte" or data_type == "send_byte":
            value = i2c_read_byte(bus, addr, cmd)
            if value is not None:
                result["status"] = "success"
                result["raw"] = f"0x{value:02X}"
                result["formatted"] = f"{value} (0x{value:02X})"

        elif data_type == "word":
            value = i2c_read_word(bus, addr, cmd)
            if value is not None:
                result["status"] = "success"
                result["raw"] = f"0x{value:04X}"
                result["formatted"] = f"{value} (0x{value:04X})"

        elif data_type == "block":
            data = i2c_read_block(bus, addr, cmd)
            if data is not None:
                result["status"] = "success"
                result["raw"] = " ".join([f"0x{b:02X}" for b in data])
                # Try to format as ASCII string if printable
                try:
                    ascii_str = "".join([chr(b) if 32 <= b < 127 else "." for b in data])
                    result["formatted"] = f"[{len(data)} bytes] {result['raw']} ('{ascii_str}')"
                except ValueError:
                    result["formatted"] = f"[{len(data)} bytes] {result['raw']}"
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)

    return result


def dump_all_commands(bus: int, addr: int, num_pages: int, verbose: bool = False):
    """Dump all PMBus commands for all pages."""
    print("=" * 80)
    print(f"PMBus Register Dump")
    print(f"I2C Bus: {bus}")
    print(f"Slave Address: 0x{addr:02X}")
    print(f"Number of Pages: {num_pages}")
    print("=" * 80)
    print()

    # First, try to read device identification (page-independent)
    # Initialize to page 0 to ensure device is in a known state
    print("Device Identification (Page-independent):")
    print("-" * 80)
    if not i2c_set_page(bus, addr, 0):
        print("Warning: Failed to initialize device to page 0", file=sys.stderr)
    for cmd in [0x98, 0x99, 0x9A, 0x9B, 0xAD, 0xAE]:
        if cmd in PMBUS_COMMANDS:
            name, dtype, rw = PMBUS_COMMANDS[cmd]
            result = dump_pmbus_command(bus, addr, cmd, name, dtype, rw, -1)
            if result["status"] == "success":
                print(f"  {result['command']} {name:30s}: {result['formatted']}")
    print()

    # Now dump all commands for each page
    for page in range(num_pages):
        print(f"\n{'=' * 80}")
        print(f"PAGE {page}")
        print(f"{'=' * 80}\n")

        # Set the page
        if not i2c_set_page(bus, addr, page):
            print(f"ERROR: Failed to set page {page}. Device may not support this page or is not responding.", file=sys.stderr)
            print(f"       Skipping page {page} and continuing with next page...", file=sys.stderr)
            continue

        # Dump all known commands
        success_count = 0
        for cmd in sorted(PMBUS_COMMANDS.keys()):
            name, dtype, rw = PMBUS_COMMANDS[cmd]
            result = dump_pmbus_command(bus, addr, cmd, name, dtype, rw, page)

            if verbose or result["status"] == "success":
                status_str = result["status"].upper()
                print(f"{result['command']} {name:30s} [{dtype:10s}] [{rw:2s}] : ", end="")

                if result["status"] == "success":
                    print(f"{result['formatted']}")
                    success_count += 1
                else:
                    print(f"{status_str}")

        print(f"\nPage {page} Summary: {success_count} commands successfully read")

        # Also try to read some unknown manufacturer-specific commands
        print(f"\nScanning unknown manufacturer-specific commands (0xD0-0xFF excluding defined commands):")
        print("-" * 80)
        mfr_success = 0
        for cmd in range(0xD0, 0x100):
            if cmd not in PMBUS_COMMANDS:
                # Try reading as byte first
                value = i2c_read_byte(bus, addr, cmd)
                if value is not None:
                    print(f"0x{cmd:02X} {f'MFR_UNKNOWN_{cmd:02X}':30s} [byte      ] [??] : {value} (0x{value:02X})")
                    mfr_success += 1
                elif verbose:
                    print(f"0x{cmd:02X} {f'MFR_UNKNOWN_{cmd:02X}':30s} [byte      ] [??] : NO_RESPONSE")

        if mfr_success > 0:
            print(f"\nFound {mfr_success} additional manufacturer-specific commands")


def main():
    parser = argparse.ArgumentParser(
        description="Dump all PMBus registers for an I2C device",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dump device at address 0x48 on bus 0 with 2 pages
  hw-management-pmbus-device-dump.py 0 0x48 2

  # Dump with verbose output (show all commands including failed ones)
  hw-management-pmbus-device-dump.py 0 0x48 2 -v

  # Save output to file
  hw-management-pmbus-device-dump.py 0 0x48 2 > pmbus_dump.txt
        """
    )

    parser.add_argument("bus", type=int, help="I2C bus number")
    parser.add_argument("address", type=str, help="Slave address (hex with 0x prefix, e.g., 0x48, or decimal without prefix)")
    parser.add_argument("pages", type=int, help="Number of pages to dump")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Show all commands including failed/unsupported ones")

    args = parser.parse_args()

    # Validate bus number (I2C buses are typically 0-255 on Linux)
    if args.bus < 0 or args.bus > 255:
        print(f"Error: I2C bus number must be between 0 and 255, got {args.bus}", file=sys.stderr)
        sys.exit(1)

    # Parse address (accept both 0x48 and 48 format, case-insensitive)
    try:
        addr = int(args.address, 16) if args.address.lower().startswith("0x") else int(args.address)
    except ValueError:
        print(f"Error: Invalid address format: {args.address}", file=sys.stderr)
        sys.exit(1)

    if not (0x08 <= addr <= 0x77):
        print(f"Error: I2C address must be between 0x08 and 0x77 (excluding reserved addresses), got 0x{addr:02X}", file=sys.stderr)
        sys.exit(1)

    # Validate number of pages (PMBus spec allows up to 32 pages, 0x00-0x1F)
    if args.pages < 1 or args.pages > 32:
        print(f"Error: Number of pages must be between 1 and 32, got {args.pages}", file=sys.stderr)
        sys.exit(1)

    # Check if running as root (needed for i2c access)
    if os.geteuid() != 0:
        print("Warning: This script typically needs to run as root (use sudo)", file=sys.stderr)

    try:
        dump_all_commands(args.bus, addr, args.pages, args.verbose)
    except KeyboardInterrupt:
        print("\n\nInterrupted by user", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
