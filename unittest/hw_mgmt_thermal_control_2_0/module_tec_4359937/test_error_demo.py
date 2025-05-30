#!/usr/bin/env python3
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
Demo script to test the enhanced error reporting in the thermal unittest
"""

from test_thermal_module_tec_sensor import *
import sys
import os

# Add the test directory to path
sys.path.insert(0, '/auto/mtrsysgwork/oleksandrs/hw-managment/hw_mgmt_clean/unittest/hw_mgmt_thermal_control_2_0/module_tec_4359937')

# Import and run the test to demo error reporting


class DemoErrorTest(TestThermalModuleTecSensor):
    """Test class to demonstrate detailed error reporting"""

    def test_intentional_error_demo(self):
        """Test that intentionally fails to demonstrate error reporting"""
        print(f"\n{Icons.ERROR} {Colors.YELLOW}Demonstrating detailed error reporting...{Colors.END}")

        # Create an intentional error for demonstration
        try:
            # Force a division by zero error
            result = 1 / 0
        except ZeroDivisionError:
            # Capture and re-raise to show detailed reporting
            self.fail("Intentional error to demonstrate detailed reporting capabilities")


if __name__ == '__main__':
    # Create test suite with just the demo error
    suite = unittest.TestSuite()
    suite.addTest(DemoErrorTest('test_intentional_error_demo'))

    # Run with beautiful error reporting
    runner = BeautifulTestRunner()
    result = runner.run(suite)
