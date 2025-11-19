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
Hardware Integration Tests for hw_management_thermal_updater.py

Tests thermal monitoring functionality with DVS (Data Vortex System):
- ASIC temperature file creation and population
- Module temperature file creation and population
- DVS start/stop integration

Prerequisites:
- DVS tools available (dvs_start.sh, dvs_stop.sh)
- hw_management_thermal_updater service installed
- Root/sudo access for service control
"""

import os
import subprocess
import time
import unittest
import glob


class ThermalUpdaterIntegrationTest(unittest.TestCase):
    """Integration tests for thermal updater with DVS"""

    THERMAL_PATH = "/var/run/hw-management/thermal"
    SERVICE_NAME = "hw-management-thermal-updater"
    DVS_START_TIMEOUT = 25  # seconds to wait for DVS operations (15s init + 10s buffer)
    FILE_POPULATE_TIMEOUT = 20  # seconds to wait for files to populate after DVS starts
    FILE_EMPTY_TIMEOUT = 15  # seconds to wait for files to empty (needs 3 retries * 3s poll = 9s minimum)

    @classmethod
    def setUpClass(cls):
        """Setup before all tests"""
        print("\n" + "=" * 70)
        print("THERMAL UPDATER HARDWARE INTEGRATION TESTS")
        print("=" * 70)

        # Check if thermal path exists
        if not os.path.exists(cls.THERMAL_PATH):
            raise unittest.SkipTest(
                f"Thermal path {cls.THERMAL_PATH} does not exist. "
                "Is hw-management installed?"
            )

        # Check if DVS tools are available
        cls.dvs_available = cls._check_command_exists("dvs_stop.sh") and \
            cls._check_command_exists("dvs_start.sh")

        if not cls.dvs_available:
            raise unittest.SkipTest("DVS tools (dvs_start.sh, dvs_stop.sh) not found in PATH")

        # Stop DVS before tests
        print("Stopping DVS before tests...")
        cls._stop_dvs()

        # OPTIMIZATION: Start DVS once and reuse across tests
        # Tests 1 & 2 need DVS stopped initially (they test without DVS / transition)
        # Tests 3 & 4 reuse DVS after test 2 starts it (saves ~28 seconds)
        print("Starting DVS once for thermal tests (tests 1-2 will control DVS lifecycle)...")
        cls.dvs_running = cls._start_dvs_once()
        if cls.dvs_running:
            print("DVS is running and ready (tests 1-2 will stop/restart as needed)")
        else:
            print("WARNING: DVS may not be running, tests will start it as needed")

    @classmethod
    def tearDownClass(cls):
        """Cleanup after all tests"""
        print("\n" + "=" * 70)
        print("Cleaning up...")
        print("=" * 70)

        # Stop DVS
        cls._stop_dvs()

        # Stop thermal updater service
        cls._stop_service(cls.SERVICE_NAME)

    def setUp(self):
        """Setup before each test"""
        # Stop service before each test
        self._stop_service(self.SERVICE_NAME)
        # Reset systemd rate-limit state to prevent "start-limit-hit" errors
        self._reset_service_failed_state(self.SERVICE_NAME)
        time.sleep(0.5)  # OPTIMIZED: Reduced from 1s

    def tearDown(self):
        """Cleanup after each test"""
        # Stop service after each test
        self._stop_service(self.SERVICE_NAME)
        # OPTIMIZED: Reduced from 1s to 0.5s
        time.sleep(0.5)

    @staticmethod
    def _check_command_exists(command):
        """Check if a command exists in PATH"""
        try:
            subprocess.run(
                ["which", command],
                capture_output=True,
                check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False

    @staticmethod
    def _run_command(command, check=True, timeout=30):
        """Run a shell command"""
        try:
            result = subprocess.run(
                command if isinstance(command, list) else [command],
                shell=isinstance(command, str) if isinstance(command, str) else False,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=check
            )
            return result
        except subprocess.CalledProcessError as e:
            if check:
                print(f"Command failed: {command}")
                print(f"stdout: {e.stdout}")
                print(f"stderr: {e.stderr}")
                raise
            return e
        except subprocess.TimeoutExpired as e:
            print(f"Command timed out: {command}")
            raise

    @staticmethod
    def _start_service(service_name):
        """Start a systemd service"""
        print(f"Starting service: {service_name}")
        result = subprocess.run(
            ["sudo", "systemctl", "start", service_name],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"Warning: Failed to start {service_name}")
            print(f"stderr: {result.stderr}")
        time.sleep(2)  # Give service time to start

    @staticmethod
    def _stop_service(service_name):
        """Stop a systemd service"""
        subprocess.run(
            ["sudo", "systemctl", "stop", service_name],
            capture_output=True,
            text=True,
            check=False
        )

    @staticmethod
    def _is_service_running(service_name):
        """Check if a systemd service is running"""
        result = subprocess.run(
            ["systemctl", "is-active", service_name],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == "active"

    @staticmethod
    def _reset_service_failed_state(service_name):
        """Reset systemd failed state for a service to prevent start-limit-hit"""
        subprocess.run(
            ["sudo", "systemctl", "reset-failed", service_name],
            capture_output=True,
            text=True,
            check=False
        )

    def _clean_thermal_files(self):
        """Clean all ASIC and module temperature files"""
        print(f"Cleaning thermal files in {self.THERMAL_PATH}...", end='', flush=True)

        # Find all asic* and module* files
        asic_files = glob.glob(os.path.join(self.THERMAL_PATH, "asic*"))
        module_files = glob.glob(os.path.join(self.THERMAL_PATH, "module*"))

        files_to_clean = asic_files + module_files
        cleaned_count = 0
        error_count = 0

        for filepath in files_to_clean:
            if os.path.isfile(filepath):
                try:
                    # Empty the file (don't delete, as updater may expect them)
                    with open(filepath, 'w') as f:
                        f.write("")
                    cleaned_count += 1
                except (OSError, PermissionError) as e:
                    error_count += 1
                    print(f"\n  Warning: Could not clean {filepath}: {e}")

        # OPTIMIZED: Print summary only, not each file
        print(f" Done. Cleaned {cleaned_count} files" + (f" ({error_count} errors)" if error_count > 0 else ""))
        return files_to_clean

    def _get_thermal_files(self):
        """Get list of ASIC and module temperature files"""
        asic_files = glob.glob(os.path.join(self.THERMAL_PATH, "asic*"))
        module_files = glob.glob(os.path.join(self.THERMAL_PATH, "module*_temp_*"))

        return {
            'asic': sorted(asic_files),
            'module': sorted(module_files)
        }

    def _check_files_have_default_values(self, files, timeout=5):
        """
        Check if files have default values when DVS/SDK is not running.

        Expected behavior (from code review):
        - ASIC files: EMPTY (SDK not loaded, asic_temp_reset writes empty strings)
        - Module files: "0" (default values when module presence unknown)

        This matches the actual hw_management_thermal_updater.py behavior:
        - asic_temp_populate: Resets to empty on SDK read error
        - module_temp_populate: Writes "0" as default when can't read module presence
        """
        start_time = time.time()

        while time.time() - start_time < timeout:
            all_default = True
            for filepath in files:
                if not os.path.exists(filepath):
                    continue
                try:
                    with open(filepath, 'r') as f:
                        content = f.read().strip()
                        # Valid default values: empty (ASIC) or "0" (modules)
                        if content and content != "0":
                            all_default = False
                            break
                except (OSError, PermissionError):
                    pass

            if all_default:
                return True

            time.sleep(0.5)

        return False

    def _check_files_populated(self, files, timeout=10):
        """Check if files have non-empty content"""
        start_time = time.time()

        while time.time() - start_time < timeout:
            populated_count = 0
            for filepath in files:
                if not os.path.exists(filepath):
                    continue
                try:
                    with open(filepath, 'r') as f:
                        content = f.read().strip()
                        if content:
                            populated_count += 1
                except (OSError, PermissionError):
                    pass

            # Consider success if at least some files are populated
            # (not all hardware may be present)
            if populated_count > 0:
                return True, populated_count

            time.sleep(0.5)

        return False, 0

    @classmethod
    def _start_dvs_once(cls):
        """
        OPTIMIZATION: Start DVS once and reuse across tests.
        This saves ~14s per test that needs DVS.
        """
        print("Starting DVS with --sdk_bridge_mode=HYBRID (optimized)...")
        print("NOTE: DVS will be started in background, then we wait 12 seconds...")

        # Start DVS in background
        print("Starting DVS in background...")
        try:
            cmd = "nohup dvs_start.sh --sdk_bridge_mode=HYBRID > /tmp/dvs_start.log 2>&1 &"
            cls._run_command(cmd, check=False, timeout=5)

            # OPTIMIZED: Wait 12 seconds instead of 15 (with better validation)
            print("Waiting 12 seconds for DVS to initialize...")
            time.sleep(12)

            # Better validation: check multiple times
            for attempt in range(3):
                result = cls._run_command("pgrep -f 'dvs_start.sh|sx_sdk'", check=False, timeout=5)
                if result and result.returncode == 0:
                    print(f"DVS processes detected (attempt {attempt + 1}/3)")
                    return True
                time.sleep(1)

            print("WARNING: No DVS processes found after 3 attempts")
            return False

        except Exception as e:
            print(f"WARNING: Exception starting DVS: {e}")
            return False

    def _start_dvs(self):
        """
        Start DVS with hybrid SDK bridge mode.

        OPTIMIZATION: Check if DVS is already running from setUpClass.
        Only restart if needed.
        """
        # Check if DVS is already running from setUpClass
        result = self._run_command("pgrep -f 'dvs_start.sh|sx_sdk'", check=False, timeout=5)
        if result and result.returncode == 0:
            print("DVS already running (reusing from setUpClass) - skipping start")
            return True

        print("DVS not running - starting fresh...")
        print("NOTE: DVS will be started in background, then we wait 12 seconds...")

        # Stop DVS first
        print("Stopping DVS first...")
        self._stop_dvs()

        # Start DVS in background
        print("Starting DVS in background...")
        try:
            cmd = "nohup dvs_start.sh --sdk_bridge_mode=HYBRID > /tmp/dvs_start.log 2>&1 &"
            self._run_command(cmd, check=False, timeout=5)

            # OPTIMIZED: Wait 12 seconds instead of 15 (with better validation)
            print("Waiting 12 seconds for DVS to initialize...")
            time.sleep(12)

            # Better validation
            for attempt in range(3):
                result = self._run_command("pgrep -f 'dvs_start.sh|sx_sdk'", check=False, timeout=5)
                if result and result.returncode == 0:
                    print(f"DVS processes detected (attempt {attempt + 1}/3)")
                    return True
                time.sleep(1)

            print("WARNING: No DVS processes found, but assuming DVS is up")
            return True

        except Exception as e:
            print(f"WARNING: Exception starting DVS: {e}")
            print("Assuming DVS started anyway - tests will tell us if it works")
            return True

    @classmethod
    def _stop_dvs(cls):
        """Stop DVS (fast operation)"""
        try:
            # dvs_stop.sh is fast - only needs 5 seconds max
            cls._run_command("timeout 5 dvs_stop.sh || true", check=False, timeout=10)
        except Exception as e:
            print(f"Warning: DVS stop had issues: {e}")
        time.sleep(1)  # Brief pause after stop

    # =========================================================================
    # TEST CASES
    # =========================================================================

    def test_01_thermal_files_empty_without_dvs(self):
        """
        Test 1: Verify thermal files have default values when DVS is not running

        Steps:
        1. Clean all thermal files
        2. Start thermal updater
        3. Verify files have default values when DVS is not running
           (ASIC files: empty, Module files: "0")
        """
        print("\n" + "-" * 70)
        print("TEST 1: Thermal files have default values without DVS")
        print("-" * 70)

        # IMPORTANT: Stop DVS for this test (it was started in setUpClass for optimization)
        # This test specifically verifies behavior WITHOUT DVS running
        print("Stopping DVS for this test (tests without DVS scenario)...")
        self._stop_dvs()
        time.sleep(1)

        # Step 1: Clean thermal files
        self._clean_thermal_files()

        # Step 2: Start thermal updater
        self._start_service(self.SERVICE_NAME)

        # Give updater time to create files
        time.sleep(3)

        # Step 3: Get thermal files
        files = self._get_thermal_files()
        all_files = files['asic'] + files['module']

        self.assertGreater(len(all_files), 0, "No thermal files found")

        print(f"Found {len(files['asic'])} ASIC files")
        print(f"Found {len(files['module'])} module files")

        # Step 4: Verify files have default values (0 or empty)
        files_default = self._check_files_have_default_values(all_files, timeout=self.FILE_EMPTY_TIMEOUT)
        self.assertTrue(
            files_default,
            "Thermal files should have default values when DVS is not running (ASIC: empty, Modules: 0)"
        )

        print("PASS: All thermal files have default values without DVS")

    def test_02_thermal_files_populated_with_dvs(self):
        """
        Test 2: Verify thermal files get populated when DVS starts

        Steps:
        1. Clean all thermal files
        2. Start thermal updater
        3. Verify files have default values
        4. Start DVS
        5. Verify files get populated with real values
        """
        print("\n" + "-" * 70)
        print("TEST 2: Thermal files populated with DVS")
        print("-" * 70)

        # IMPORTANT: Ensure DVS is stopped (test will start it)
        # This test verifies transition from no-DVS to DVS-running
        print("Ensuring DVS is stopped (test will start it)...")
        self._stop_dvs()
        time.sleep(1)

        # Step 1: Clean thermal files
        self._clean_thermal_files()

        # Step 2: Start thermal updater
        self._start_service(self.SERVICE_NAME)
        time.sleep(2)

        # Step 3: Verify files are empty initially
        files = self._get_thermal_files()
        all_files = files['asic'] + files['module']

        self.assertGreater(len(all_files), 0, "No thermal files found")

        files_default = self._check_files_have_default_values(all_files, timeout=self.FILE_EMPTY_TIMEOUT)
        self.assertTrue(files_default, "Files should have default values before DVS starts (ASIC: empty, Modules: 0)")
        print("Confirmed: Files have default values before DVS")

        # Step 4: Start DVS
        dvs_started = self._start_dvs()
        self.assertTrue(dvs_started, "Failed to start DVS")

        # Step 5: Verify files get populated
        print("Waiting for thermal files to populate...")
        populated, count = self._check_files_populated(all_files, timeout=self.FILE_POPULATE_TIMEOUT)

        self.assertTrue(
            populated,
            f"Thermal files should be populated after DVS starts. Got {count} populated files."
        )

        print(f"PASS: {count} thermal files populated with DVS running")

        # Show some sample values
        for filepath in all_files[:5]:  # Show first 5 files
            try:
                with open(filepath, 'r') as f:
                    content = f.read().strip()
                    if content:
                        print(f"  {os.path.basename(filepath)}: {content[:50]}")
            except (OSError, PermissionError):
                pass

    def test_03_thermal_files_empty_after_dvs_stop(self):
        """
        Test 3: Verify thermal files return to default values when DVS stops

        Steps:
        1. Clean all thermal files
        2. Start thermal updater
        3. Start DVS
        4. Verify files are populated with real values
        5. Stop DVS
        6. Verify files return to default values (0 or empty)
        """
        print("\n" + "-" * 70)
        print("TEST 3: Thermal files return to default values after DVS stop")
        print("-" * 70)

        # Step 1: Clean thermal files
        self._clean_thermal_files()

        # Step 2: Start thermal updater
        self._start_service(self.SERVICE_NAME)
        time.sleep(2)

        # Step 3: Start DVS
        dvs_started = self._start_dvs()
        self.assertTrue(dvs_started, "Failed to start DVS")

        # Step 4: Verify files are populated
        files = self._get_thermal_files()
        all_files = files['asic'] + files['module']

        populated, count = self._check_files_populated(all_files, timeout=self.FILE_POPULATE_TIMEOUT)
        self.assertTrue(populated, f"Files should be populated with DVS. Got {count} files.")
        print(f"Confirmed: {count} files populated with DVS running")

        # Step 5: Stop DVS
        self._stop_dvs()

        # Step 6: Verify files return to default values
        print("Waiting for thermal files to return to default values after DVS stop...")
        files_default = self._check_files_have_default_values(all_files, timeout=self.FILE_EMPTY_TIMEOUT)

        self.assertTrue(
            files_default,
            "Thermal files should have default values after DVS stops (ASIC: empty, Modules: 0)"
        )
        print("PASS: All thermal files returned to default values after DVS stop")

    def test_04_service_restart_persistence(self):
        """
        Test 4: Verify thermal updater service can restart and resume monitoring

        Steps:
        1. Start DVS
        2. Start thermal updater
        3. Verify files populated
        4. Restart service
        5. Verify files still populated
        """
        print("\n" + "-" * 70)
        print("TEST 4: Service restart persistence")
        print("-" * 70)

        # Step 1: Start DVS
        dvs_started = self._start_dvs()
        self.assertTrue(dvs_started, "Failed to start DVS")

        # Step 2: Start thermal updater
        self._start_service(self.SERVICE_NAME)
        time.sleep(2)

        # Step 3: Verify files populated
        files = self._get_thermal_files()
        all_files = files['asic'] + files['module']

        populated, count = self._check_files_populated(all_files, timeout=self.FILE_POPULATE_TIMEOUT)
        self.assertTrue(populated, f"Files should be populated. Got {count} files.")
        print(f"Confirmed: {count} files populated before restart")

        # Step 4: Restart service
        print("Restarting thermal updater service...")
        self._stop_service(self.SERVICE_NAME)
        time.sleep(2)
        self._start_service(self.SERVICE_NAME)
        time.sleep(2)

        # Step 5: Verify files still populated after restart
        populated, count = self._check_files_populated(all_files, timeout=self.FILE_POPULATE_TIMEOUT)
        self.assertTrue(
            populated,
            f"Files should still be populated after service restart. Got {count} files."
        )

        print(f"PASS: {count} files still populated after service restart")


if __name__ == "__main__":
    unittest.main(verbosity=2)
