#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2022-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
Basic Hardware Service Tests (No DVS Required)

Tests that services can start/stop and basic file structure exists.
Does NOT require DVS to be running - faster and more reliable.
"""

import os
import subprocess
import time
import unittest


class BasicServiceTest(unittest.TestCase):
    """Basic tests that don't require DVS"""

    THERMAL_PATH = "/var/run/hw-management/thermal"
    CONFIG_PATH = "/var/run/hw-management/config"
    THERMAL_SERVICE = "hw-management-thermal-updater"
    PERIPHERAL_SERVICE = "hw-management-peripheral-updater"

    def test_01_thermal_service_can_start(self):
        """Test that thermal updater service can start"""
        print("\n" + "=" * 70)
        print("TEST: Thermal service can start/stop")
        print("=" * 70)

        # Stop first
        subprocess.run(["sudo", "systemctl", "stop", self.THERMAL_SERVICE], check=False)
        time.sleep(1)

        # Start
        result = subprocess.run(
            ["sudo", "systemctl", "start", self.THERMAL_SERVICE],
            capture_output=True,
            text=True
        )
        time.sleep(2)

        # Check status
        status = subprocess.run(
            ["systemctl", "is-active", self.THERMAL_SERVICE],
            capture_output=True,
            text=True
        )

        is_active = status.stdout.strip() == "active"

        # Stop
        subprocess.run(["sudo", "systemctl", "stop", self.THERMAL_SERVICE], check=False)

        self.assertTrue(is_active, f"Thermal service should start successfully. Status: {status.stdout}")
        print("PASS: Thermal service started and stopped successfully")

    def test_02_peripheral_service_can_start(self):
        """Test that peripheral updater service can start"""
        print("\n" + "=" * 70)
        print("TEST: Peripheral service can start/stop")
        print("=" * 70)

        # Stop first
        subprocess.run(["sudo", "systemctl", "stop", self.PERIPHERAL_SERVICE], check=False)
        time.sleep(1)

        # Start
        result = subprocess.run(
            ["sudo", "systemctl", "start", self.PERIPHERAL_SERVICE],
            capture_output=True,
            text=True
        )
        time.sleep(2)

        # Check status
        status = subprocess.run(
            ["systemctl", "is-active", self.PERIPHERAL_SERVICE],
            capture_output=True,
            text=True
        )

        is_active = status.stdout.strip() == "active"

        # Stop
        subprocess.run(["sudo", "systemctl", "stop", self.PERIPHERAL_SERVICE], check=False)

        self.assertTrue(is_active, f"Peripheral service should start successfully. Status: {status.stdout}")
        print("PASS: Peripheral service started and stopped successfully")

    def test_03_hw_management_paths_exist(self):
        """Test that hw-management directory structure exists"""
        print("\n" + "=" * 70)
        print("TEST: HW-management paths exist")
        print("=" * 70)

        paths = [
            "/var/run/hw-management",
            "/var/run/hw-management/thermal",
            "/var/run/hw-management/config",
        ]

        for path in paths:
            exists = os.path.exists(path)
            print(f"  {path}: {'EXISTS' if exists else 'MISSING'}")
            self.assertTrue(exists, f"Path {path} should exist")

        print("PASS: All required paths exist")

    def test_04_services_are_independent(self):
        """Test that services can run independently"""
        print("\n" + "=" * 70)
        print("TEST: Services are independent")
        print("=" * 70)

        # Stop both
        subprocess.run(["sudo", "systemctl", "stop", self.THERMAL_SERVICE], check=False)
        subprocess.run(["sudo", "systemctl", "stop", self.PERIPHERAL_SERVICE], check=False)
        time.sleep(1)

        # Start only peripheral
        subprocess.run(["sudo", "systemctl", "start", self.PERIPHERAL_SERVICE], check=False)
        time.sleep(2)

        # Check peripheral is running
        peripheral_status = subprocess.run(
            ["systemctl", "is-active", self.PERIPHERAL_SERVICE],
            capture_output=True,
            text=True
        ).stdout.strip()

        # Check thermal is NOT running
        thermal_status = subprocess.run(
            ["systemctl", "is-active", self.THERMAL_SERVICE],
            capture_output=True,
            text=True
        ).stdout.strip()

        # Stop peripheral
        subprocess.run(["sudo", "systemctl", "stop", self.PERIPHERAL_SERVICE], check=False)

        print(f"  Peripheral service: {peripheral_status}")
        print(f"  Thermal service: {thermal_status}")

        self.assertEqual(peripheral_status, "active", "Peripheral should be active")
        self.assertNotEqual(thermal_status, "active", "Thermal should not be active")

        print("PASS: Services operate independently")

    def test_05_service_files_exist(self):
        """Test that service files are installed"""
        print("\n" + "=" * 70)
        print("TEST: Service files exist")
        print("=" * 70)

        service_files = [
            "/lib/systemd/system/hw-management-thermal-updater.service",
            "/lib/systemd/system/hw-management-peripheral-updater.service",
        ]

        for service_file in service_files:
            exists = os.path.exists(service_file)
            print(f"  {service_file}: {'EXISTS' if exists else 'MISSING'}")
            self.assertTrue(exists, f"Service file {service_file} should exist")

        print("PASS: All service files exist")


if __name__ == "__main__":
    unittest.main(verbosity=2)
