#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Integration Test for Dynamic Log Level Adjustment
#
# Tests that thermal_updater and peripheral_updater can dynamically
# adjust their log levels using LOGGER.set_loglevel() when reading
# from the log_level configuration file.
#
# This test catches the missing set_loglevel() method that was
# identified by agent review.
########################################################################

import sys
import os
import pytest
import tempfile
import shutil
from pathlib import Path
from unittest.mock import patch, MagicMock, mock_open

# Add the library path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))


@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files"""
    tmp_dir = tempfile.mkdtemp()
    yield tmp_dir
    shutil.rmtree(tmp_dir, ignore_errors=True)


class TestDynamicLogLevelAdjustment:
    """
    Integration tests for dynamic log level adjustment feature.

    Both thermal_updater and peripheral_updater read /var/run/hw-management/config/log_level
    and call LOGGER.set_loglevel() to adjust verbosity at runtime.
    """

    def test_thermal_updater_set_loglevel_exists(self):
        """Test that thermal_updater's LOGGER has set_loglevel method"""
        from hw_management_lib import HW_Mgmt_Logger

        # Create a logger instance like thermal_updater does
        logger = HW_Mgmt_Logger(ident='thermal_updater_test')

        # Verify set_loglevel method exists
        assert hasattr(logger, 'set_loglevel'), "HW_Mgmt_Logger missing set_loglevel() method"
        assert callable(logger.set_loglevel), "set_loglevel is not callable"

        # Verify it works
        logger.set_loglevel(logger.DEBUG)
        assert logger.logger.level == logger.DEBUG

        logger.stop()

    def test_peripheral_updater_set_loglevel_exists(self):
        """Test that peripheral_updater's LOGGER has set_loglevel method"""
        from hw_management_lib import HW_Mgmt_Logger

        # Create a logger instance like peripheral_updater does
        logger = HW_Mgmt_Logger(ident='peripheral_updater_test')

        # Verify set_loglevel method exists
        assert hasattr(logger, 'set_loglevel'), "HW_Mgmt_Logger missing set_loglevel() method"
        assert callable(logger.set_loglevel), "set_loglevel is not callable"

        # Verify it works
        logger.set_loglevel(logger.INFO)
        assert logger.logger.level == logger.INFO

        logger.stop()

    def test_simulate_thermal_updater_log_level_adjustment(self, temp_dir):
        """
        Simulate thermal_updater.py reading log level file and calling set_loglevel().

        This reproduces the exact code path:
        try:
            log_level_filename = os.path.join(CONST.HW_MGMT_FOLDER_DEF, CONST.LOG_LEVEL_FILENAME)
            if os.path.isfile(log_level_filename):
                with open(log_level_filename, 'r', encoding="utf-8") as f:
                    log_level = f.read().rstrip('\n')
                    log_level = int(log_level)
                    LOGGER.set_loglevel(log_level)  # ← This must work!
        except (OSError, ValueError):
            pass
        """
        from hw_management_lib import HW_Mgmt_Logger

        # Setup
        log_file = os.path.join(temp_dir, "thermal.log")
        log_level_file = os.path.join(temp_dir, "log_level")

        logger = HW_Mgmt_Logger(
            ident='thermal_updater',
            log_file=log_file,
            log_level=HW_Mgmt_Logger.INFO
        )

        # Create log level file with DEBUG level
        with open(log_level_file, 'w') as f:
            f.write(f"{HW_Mgmt_Logger.DEBUG}\n")

        # Simulate the code from thermal_updater.py main loop
        try:
            if os.path.isfile(log_level_file):
                with open(log_level_file, 'r', encoding="utf-8") as f:
                    log_level = f.read().rstrip('\n')
                    log_level = int(log_level)
                    logger.set_loglevel(log_level)  # This was failing before!
        except (OSError, ValueError) as e:
            pytest.fail(f"Should not raise OSError or ValueError: {e}")
        except AttributeError as e:
            pytest.fail(f"set_loglevel() method is missing! {e}")

        # Verify it worked
        assert logger.logger.level == HW_Mgmt_Logger.DEBUG

        logger.stop()

    def test_simulate_peripheral_updater_log_level_adjustment(self, temp_dir):
        """
        Simulate peripheral_updater.py reading log level file and calling set_loglevel().

        Same code path as thermal_updater.
        """
        from hw_management_lib import HW_Mgmt_Logger

        # Setup
        log_file = os.path.join(temp_dir, "peripheral.log")
        log_level_file = os.path.join(temp_dir, "log_level")

        logger = HW_Mgmt_Logger(
            ident='peripheral_updater',
            log_file=log_file,
            log_level=HW_Mgmt_Logger.WARNING
        )

        # Create log level file with INFO level
        with open(log_level_file, 'w') as f:
            f.write(f"{HW_Mgmt_Logger.INFO}\n")

        # Simulate the code from peripheral_updater.py main loop
        try:
            if os.path.isfile(log_level_file):
                with open(log_level_file, 'r', encoding="utf-8") as f:
                    log_level = f.read().rstrip('\n')
                    log_level = int(log_level)
                    logger.set_loglevel(log_level)  # This was failing before!
        except (OSError, ValueError) as e:
            pytest.fail(f"Should not raise OSError or ValueError: {e}")
        except AttributeError as e:
            pytest.fail(f"set_loglevel() method is missing! {e}")

        # Verify it worked
        assert logger.logger.level == HW_Mgmt_Logger.INFO

        logger.stop()

    def test_log_level_adjustment_actually_changes_output(self, temp_dir):
        """
        Test that adjusting log level actually changes what gets logged.

        This ensures the feature works end-to-end.
        """
        from hw_management_lib import HW_Mgmt_Logger

        log_file = os.path.join(temp_dir, "test.log")
        log_level_file = os.path.join(temp_dir, "log_level")

        # Start with WARNING level
        logger = HW_Mgmt_Logger(
            ident='test_service',
            log_file=log_file,
            log_level=HW_Mgmt_Logger.WARNING
        )

        # These should not appear
        logger.debug("DEBUG before adjustment")
        logger.info("INFO before adjustment")

        # This should appear
        logger.warning("WARNING before adjustment")

        # Adjust to DEBUG level
        with open(log_level_file, 'w') as f:
            f.write(f"{HW_Mgmt_Logger.DEBUG}\n")

        if os.path.isfile(log_level_file):
            with open(log_level_file, 'r', encoding="utf-8") as f:
                log_level = int(f.read().rstrip('\n'))
                logger.set_loglevel(log_level)

        # Now these should appear
        logger.debug("DEBUG after adjustment")
        logger.info("INFO after adjustment")
        logger.warning("WARNING after adjustment")

        # Verify log file content
        with open(log_file, 'r') as f:
            content = f.read()

            # Before adjustment - should not appear
            assert "DEBUG before adjustment" not in content
            assert "INFO before adjustment" not in content

            # Should always appear
            assert "WARNING before adjustment" in content

            # After adjustment - should appear
            assert "DEBUG after adjustment" in content
            assert "INFO after adjustment" in content
            assert "WARNING after adjustment" in content

        logger.stop()

    def test_invalid_log_level_handled_gracefully(self, temp_dir):
        """
        Test that invalid log levels in the file are handled gracefully.

        The services catch (OSError, ValueError) so invalid values should not crash.
        """
        from hw_management_lib import HW_Mgmt_Logger

        log_level_file = os.path.join(temp_dir, "log_level")
        logger = HW_Mgmt_Logger(ident='test_service')

        # Write invalid value
        with open(log_level_file, 'w') as f:
            f.write("invalid\n")

        # This should be caught by the ValueError exception
        try:
            if os.path.isfile(log_level_file):
                with open(log_level_file, 'r', encoding="utf-8") as f:
                    log_level = f.read().rstrip('\n')
                    log_level = int(log_level)  # This will raise ValueError
                    logger.set_loglevel(log_level)
        except (OSError, ValueError):
            # Expected - should handle gracefully
            pass
        except AttributeError:
            pytest.fail("set_loglevel() method is missing!")

        logger.stop()


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
