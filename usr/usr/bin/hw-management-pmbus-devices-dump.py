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
PMBus Multiple Devices Dump Script
Dumps PMBus registers for multiple devices specified in a JSON configuration file.
"""

import subprocess
import sys
import argparse
import json
import os
from datetime import datetime
from typing import List, Dict


def validate_device(device: Dict, index: int) -> tuple:
    """Validate device configuration and return (bus, addr, pages) or raise error."""
    required_fields = ["BusNumber", "SlaveAddr", "NumPages"]

    for field in required_fields:
        if field not in device:
            raise ValueError(f"Device {index}: Missing required field '{field}'")

    try:
        bus = int(device["BusNumber"])
    except (ValueError, TypeError):
        raise ValueError(f"Device {index}: Invalid BusNumber '{device['BusNumber']}', must be integer")

    # Validate bus number range (I2C buses are typically 0-255 on Linux)
    if bus < 0 or bus > 255:
        raise ValueError(f"Device {index}: BusNumber must be between 0 and 255, got {bus}")

    try:
        addr_str = device["SlaveAddr"]
        if isinstance(addr_str, str):
            addr = int(addr_str, 16) if addr_str.lower().startswith("0x") else int(addr_str)
        else:
            addr = int(addr_str)
    except (ValueError, TypeError):
        raise ValueError(f"Device {index}: Invalid SlaveAddr '{device['SlaveAddr']}'")

    if not (0x08 <= addr <= 0x77):
        raise ValueError(f"Device {index}: SlaveAddr must be between 0x08 and 0x77 (excluding reserved addresses), got 0x{addr:02X}")

    try:
        pages = int(device["NumPages"])
    except (ValueError, TypeError):
        raise ValueError(f"Device {index}: Invalid NumPages '{device['NumPages']}', must be integer")

    # Validate pages range (PMBus spec allows up to 32 pages, 0x00-0x1F)
    if pages < 1 or pages > 32:
        raise ValueError(f"Device {index}: NumPages must be between 1 and 32, got {pages}")

    return bus, addr, pages


def load_devices_config(config_file: str) -> List[Dict]:
    """Load and validate device configuration from JSON file."""
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
    except FileNotFoundError:
        raise FileNotFoundError(f"Configuration file not found: {config_file}")
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in configuration file: {e}")

    # Handle both array format and object with 'devices' key
    if isinstance(config, list):
        devices = config
    elif isinstance(config, dict) and "devices" in config:
        devices = config["devices"]
        # Validate that devices is actually a list
        if not isinstance(devices, list):
            raise ValueError("'devices' must be an array")
    else:
        raise ValueError("JSON must be an array of devices or object with 'devices' key")

    if not devices:
        raise ValueError("No devices found in configuration file")

    return devices


def dump_device(bus: int, addr: int, pages: int, script_path: str, output_file) -> bool:
    """Dump a single device using the hw-management-pmbus-device-dump.py script."""
    try:
        cmd = [script_path, str(bus), f"0x{addr:02X}", str(pages)]
        result = subprocess.run(
            cmd,
            stdout=output_file,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300  # 5 minute timeout per device
        )

        # Always log stderr if present (warnings and errors)
        if result.stderr:
            print(f"  Output from device dump (stderr):", file=sys.stderr)
            for line in result.stderr.strip().split('\n'):
                print(f"    {line}", file=sys.stderr)

        if result.returncode != 0:
            print(f"  ERROR: Script returned exit code {result.returncode}", file=sys.stderr)
            return False

        return True
    except subprocess.TimeoutExpired:
        print(f"  ERROR: Timeout while dumping device", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  ERROR: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Dump PMBus registers for multiple devices from JSON configuration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
JSON Configuration Format:
  [
    {
      "BusNumber": 16,
      "SlaveAddr": "0x69",
      "NumPages": 2
    },
    {
      "BusNumber": 17,
      "SlaveAddr": "0x50",
      "NumPages": 4
    }
  ]

Or:
  {
    "devices": [
      {
        "BusNumber": 16,
        "SlaveAddr": "0x69",
        "NumPages": 2
      }
    ]
  }

Examples:
  # Dump all devices from config to default log file
  hw-management-pmbus-devices-dump.py devices.json

  # Dump to specific output file
  hw-management-pmbus-devices-dump.py devices.json -o /var/log/pmbus_dump.log
        """
    )

    parser.add_argument("config", help="JSON configuration file with device list")
    parser.add_argument("-o", "--output",
                        default="/tmp/pmbus_regmap.dump",
                        help="Output log file (default: /tmp/pmbus_regmap.dump)")
    parser.add_argument("--script",
                        default=None,
                        help="Path to hw-management-pmbus-device-dump.py script (default: auto-detect)")

    args = parser.parse_args()

    # Check if running as root
    if os.geteuid() != 0:
        print("Warning: This script typically needs to run as root (use sudo)", file=sys.stderr)

    # Find the device dump script
    if args.script:
        script_path = args.script
    else:
        # Try to find script in multiple locations
        # SECURITY: Do NOT include current working directory to prevent
        # execution of malicious scripts with elevated privileges
        script_name = "hw-management-pmbus-device-dump.py"
        search_paths = [
            # Same directory as this script
            os.path.join(os.path.dirname(os.path.realpath(__file__)), script_name),
            # Standard installation paths
            f"/usr/bin/{script_name}",
            f"/usr/local/bin/{script_name}",
        ]

        script_path = None
        for path in search_paths:
            if os.path.isfile(path) and os.access(path, os.X_OK):
                script_path = path
                break

        if not script_path:
            print("ERROR: Cannot find hw-management-pmbus-device-dump.py script", file=sys.stderr)
            print(f"Searched in: {', '.join(search_paths)}", file=sys.stderr)
            print("Please specify path with --script option", file=sys.stderr)
            sys.exit(1)

    if not os.path.isfile(script_path):
        print(f"ERROR: Script not found: {script_path}", file=sys.stderr)
        sys.exit(1)

    if not os.access(script_path, os.X_OK):
        print(f"ERROR: Script is not executable: {script_path}", file=sys.stderr)
        sys.exit(1)

    # Load and validate device configuration
    try:
        devices = load_devices_config(args.config)
    except (FileNotFoundError, ValueError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Loaded {len(devices)} device(s) from configuration")
    print(f"Output file: {args.output}")
    print(f"Using script: {script_path}")
    print()

    # Validate all devices first
    validated_devices = []
    for i, device in enumerate(devices):
        try:
            bus, addr, pages = validate_device(device, i)
            validated_devices.append((bus, addr, pages, device))
            print(f"Device {i+1}: Bus {bus}, Address 0x{addr:02X}, Pages {pages} - OK")
        except ValueError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            sys.exit(1)

    print()

    # Warn if output file exists and will be overwritten
    if os.path.exists(args.output):
        print(f"Warning: Output file '{args.output}' already exists and will be overwritten", file=sys.stderr)

    # Security check: Warn if writing to /tmp with elevated privileges
    # This helps prevent symlink attacks where a malicious symlink in /tmp
    # could redirect output to an arbitrary file with root privileges
    if args.output.startswith('/tmp/') and os.geteuid() == 0:
        print(f"Warning: Writing to /tmp with root privileges may be unsafe due to symlink attacks", file=sys.stderr)
        print(f"         Consider using a more secure location like /var/log/ or /root/", file=sys.stderr)

    # Open output file
    try:
        # Use os.open with O_CREAT|O_EXCL|O_WRONLY to prevent symlink attacks
        # O_EXCL ensures the file doesn't already exist (including symlinks)
        # This is critical when running with root privileges
        try:
            fd = os.open(args.output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            output_file = os.fdopen(fd, 'w')
        except FileExistsError:
            print(f"ERROR: Output file '{args.output}' already exists. Please remove it or choose a different path.", file=sys.stderr)
            sys.exit(1)

        # Write header
        header = f"""
{'=' * 80}
PMBus Multi-Device Register Dump
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Configuration: {args.config}
Number of Devices: {len(validated_devices)}
{'=' * 80}

"""
        output_file.write(header)
        output_file.flush()

        # Dump each device
        success_count = 0
        for i, (bus, addr, pages, device_info) in enumerate(validated_devices):
            print(f"Dumping device {i+1}/{len(validated_devices)}: Bus {bus}, Address 0x{addr:02X}, Pages {pages}...")

            # Write device separator
            separator = f"""

{'#' * 80}
{'#' * 80}
DEVICE {i+1}: Bus {bus}, Address 0x{addr:02X}, Pages {pages}
"""
            if "Name" in device_info:
                separator += f"Name: {device_info['Name']}\n"
            if "Description" in device_info:
                separator += f"Description: {device_info['Description']}\n"
            separator += f"{'#' * 80}\n{'#' * 80}\n\n"

            output_file.write(separator)
            output_file.flush()

            # Dump the device
            if dump_device(bus, addr, pages, script_path, output_file):
                print(f"  SUCCESS")
                success_count += 1
            else:
                print(f"  FAILED")

            output_file.flush()

        # Write footer
        footer = f"""

{'=' * 80}
Summary:
  Total Devices: {len(validated_devices)}
  Successful: {success_count}
  Failed: {len(validated_devices) - success_count}
{'=' * 80}
"""
        output_file.write(footer)
        output_file.close()

        print()
        print(f"Dump completed: {success_count}/{len(validated_devices)} devices successful")
        print(f"Output saved to: {args.output}")

        if success_count < len(validated_devices):
            sys.exit(1)

    except IOError as e:
        print(f"ERROR: Cannot write to output file: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nInterrupted by user", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
