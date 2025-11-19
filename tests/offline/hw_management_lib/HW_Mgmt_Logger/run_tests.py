#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Runner Script for HW_Mgmt_Logger Tests
########################################################################
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

import os
import sys
import argparse
import subprocess
from pathlib import Path

# Color codes for output


class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

# Icons - fallback to simple chars if Unicode not supported


class Icons:
    try:
        # Test if Unicode emojis work
        test_encode = "[START]".encode(sys.stdout.encoding or 'utf-8')
        ROCKET = "[START]"
        TEST = "[TEST]"
        INFO = "[INFO]"
        SUCCESS = "[OK]"
        FAIL = "[FAIL]"
        RANDOM = "[RANDOM]"
    except (UnicodeEncodeError, LookupError, AttributeError):
        # Fallback to ASCII characters
        ROCKET = "*"
        TEST = "T"
        INFO = "i"
        SUCCESS = "+"
        FAIL = "X"
        RANDOM = "?"


def print_banner():
    """Print welcome banner"""
    print(f"\n{Colors.CYAN}{Colors.BOLD}{'=' * 80}{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}{Icons.ROCKET} HW_Mgmt_Logger Test Suite Runner{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}{'=' * 80}{Colors.RESET}")
    print(f"{Colors.BLUE}{Icons.INFO} Comprehensive testing for HW_Mgmt_Logger class{Colors.RESET}")
    print(f"{Colors.BLUE}{Icons.INFO} Includes functional, stress, and randomized tests{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}{'=' * 80}{Colors.RESET}\n")


def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description='HW_Mgmt_Logger Test Suite Runner',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Examples:
  {sys.argv[0]} --quick                    # Quick test with 5 random iterations
  {sys.argv[0]} --standard                 # Standard test with 10 random iterations
  {sys.argv[0]} --thorough                 # Thorough test with 25 random iterations
  {sys.argv[0]} --stress                   # Stress test with 100 random iterations
  {sys.argv[0]} -r 50 -v 2                # Custom: 50 iterations, verbose output
        """
    )

    # Predefined test configurations
    parser.add_argument('--quick', action='store_true',
                        help='Quick test suite (5 random iterations)')
    parser.add_argument('--standard', action='store_true',
                        help='Standard test suite (10 random iterations)')
    parser.add_argument('--thorough', action='store_true',
                        help='Thorough test suite (25 random iterations)')
    parser.add_argument('--stress', action='store_true',
                        help='Stress test suite (100 random iterations)')

    # Custom configuration
    parser.add_argument('-r', '--random-iterations', type=int,
                        help='Custom number of random iterations')
    parser.add_argument('-v', '--verbosity', type=int, default=2, choices=[0, 1, 2],
                        help='Test verbosity level (0=quiet, 1=normal, 2=verbose)')

    args = parser.parse_args()

    print_banner()

    # Determine test configuration
    if args.quick:
        iterations = 5
        config_name = "Quick"
    elif args.standard or not any([args.quick, args.thorough, args.stress, args.random_iterations]):
        iterations = 10  # Default
        config_name = "Standard"
    elif args.thorough:
        iterations = 25
        config_name = "Thorough"
    elif args.stress:
        iterations = 100
        config_name = "Stress"
    else:
        iterations = args.random_iterations
        config_name = "Custom"

    print(f"{Icons.TEST} {Colors.BOLD}Test Configuration:{Colors.RESET} {config_name}")
    print(f"{Icons.RANDOM} {Colors.BOLD}Random Iterations:{Colors.RESET} {iterations}")
    print(f"{Icons.INFO} {Colors.BOLD}Verbosity Level:{Colors.RESET} {args.verbosity}")
    print()

    # Get the test file path
    script_dir = Path(__file__).parent
    test_file = script_dir / "test_hw_mgmt_logger.py"

    if not test_file.exists():
        print(f"{Icons.FAIL} {Colors.RED}Test file not found: {test_file}{Colors.RESET}")
        return 1

    # Build command
    cmd = [
        sys.executable,
        str(test_file),
        '--random-iterations', str(iterations),
        '--verbosity', str(args.verbosity)
    ]

    print(f"{Colors.BOLD}Running command:{Colors.RESET}")
    print(f"  {' '.join(cmd)}")
    print()

    try:
        # Run the tests
        result = subprocess.run(cmd, check=False)
        return result.returncode

    except KeyboardInterrupt:
        print(f"\n{Icons.INFO} {Colors.YELLOW}Tests interrupted by user{Colors.RESET}")
        return 130
    except Exception as e:
        print(f"{Icons.FAIL} {Colors.RED}Error running tests: {e}{Colors.RESET}")
        return 1


if __name__ == '__main__':
    exit_code = main()
    if exit_code == 0:
        print(f"\n{Icons.SUCCESS} {Colors.GREEN}{Colors.BOLD}All tests completed successfully!{Colors.RESET}")
    else:
        print(f"\n{Icons.FAIL} {Colors.RED}{Colors.BOLD}Tests failed with exit code: {exit_code}{Colors.RESET}")
    sys.exit(exit_code)
