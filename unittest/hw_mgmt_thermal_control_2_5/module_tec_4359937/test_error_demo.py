#!/usr/bin/env python3
# -*- coding: utf-8 -*-
########################################################################
# Copyright (c) 2022 NVIDIA CORPORATION & AFFILIATES.
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
Error Reporting Demo for thermal_module_tec_sensor unittest (Version 2.5.0)

This simple test demonstrates the detailed error reporting capabilities
of the thermal_module_tec_sensor unittest framework.
"""

from test_thermal_module_tec_sensor import BeautifulTestRunner, Colors, Icons
import sys
import unittest

# Add the source directory to Python path
sys.path.insert(0, '/auto/mtrsysgwork/oleksandrs/hw-managment/hw_mgmt_clean/usr/usr/bin')

# Import the test framework from the main test file


class ErrorReportingDemo(unittest.TestCase):
    """Demo test class to show error reporting capabilities"""

    def test_intentional_error_demo(self):
        """This test intentionally fails to demonstrate error reporting"""
        print(f"\n{Icons.FIRE} {Colors.RED}This test intentionally triggers an error to show detailed reporting...{Colors.END}")

        # Create some context for the error report
        test_data = {
            'sensor_name': 'demo_module',
            'config': {'val_min': 0, 'val_max': 100},
            'iteration': 1
        }

        # Set some attributes that will be captured in the error context
        self.sensor_name = test_data['sensor_name']
        self.test_config = test_data['config']

        # Intentionally cause an error for demonstration
        # This will trigger the detailed error reporting system
        result = 1 / 0  # ZeroDivisionError

        # This line will never be reached
        self.assertEqual(result, "impossible")


def main():
    """Run the error demo"""
    print(f"\n{Colors.YELLOW}{Colors.BOLD}{'=' * 80}{Colors.END}")
    print(f"{Colors.YELLOW}{Colors.BOLD}🚨 ERROR REPORTING DEMONSTRATION - VERSION 2.5.0{Colors.END}")
    print(f"{Colors.YELLOW}{Colors.BOLD}{'=' * 80}{Colors.END}")
    print(f"{Colors.CYAN}This demo shows how detailed error reports are generated when tests fail.{Colors.END}")
    print(f"{Colors.CYAN}The error report will include system info, stack traces, and test context.{Colors.END}\n")

    # Create test suite with just the error demo
    suite = unittest.TestLoader().loadTestsFromTestCase(ErrorReportingDemo)

    # Run with beautiful output and error reporting
    runner = BeautifulTestRunner(verbosity=2)
    result = runner.run(suite)

    return result


if __name__ == '__main__':
    main()
