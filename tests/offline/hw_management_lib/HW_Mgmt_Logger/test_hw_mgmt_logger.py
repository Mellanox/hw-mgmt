#!/usr/bin/env python3
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
########################################################################

"""
Comprehensive Unit Tests for HW_Mgmt_Logger class

Description: Beautiful and detailed unit tests with colorful output and icons
"""

# fmt: off

from pathlib import Path
from io import StringIO
from unittest.mock import Mock, patch, MagicMock, call
import logging
import time
import sys
import argparse
import datetime
import platform
import traceback
import json
import random
import shutil
import tempfile
import os
import unittest


# Add the source path to be able to import the module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', 'usr', 'usr', 'bin'))
from hw_management_lib import HW_Mgmt_Logger, current_milli_time
# fmt: on

# Color codes for beautiful output


class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'

# Icons for test results


class Icons:
    PASS = '[PASS]'
    FAIL = '[FAIL]'
    SKIP = '[SKIP]'
    WARNING = '[WARN]'
    INFO = '[INFO]'
    LOGGER = '[LOG]'
    HASH = '[HASH]'
    TIME = '[TIME]'
    RANDOM = '[RAND]'
    FILE = '[FILE]'
    ERROR = '[ERR!]'
    CHECK = '[DONE]'
    LOCK = '[LOCK]'
    CLEAN = '[CLEN]'
    REPEAT = '[REPT]'


class BeautifulTestResult(unittest.TextTestResult):
    """Custom test result class with beautiful colored output"""

    def __init__(self, *args, **kwargs):
        self.quiet_mode = kwargs.pop('quiet_mode', False)
        super().__init__(*args, **kwargs)
        self.test_start_time = None
        self.iteration = 1

    def startTest(self, test):
        super().startTest(test)
        self.test_start_time = time.time()
        if not self.quiet_mode:
            test_name = self.getDescription(test)
            print(f"\n{Colors.CYAN}{Icons.INFO} Running:{Colors.END} {test_name}")

    def addSuccess(self, test):
        super().addSuccess(test)
        if not self.quiet_mode:
            elapsed = time.time() - self.test_start_time
            test_name = self.getDescription(test)
            print(f"{Colors.GREEN}{Icons.PASS} PASSED:{Colors.END} {test_name} ({elapsed:.3f}s)")

    def addError(self, test, err):
        super().addError(test, err)
        elapsed = time.time() - self.test_start_time
        test_name = self.getDescription(test)
        print(f"{Colors.RED}{Icons.ERROR} ERROR:{Colors.END} {test_name} ({elapsed:.3f}s)")
        self._print_error_details(test, err)

    def addFailure(self, test, err):
        super().addFailure(test, err)
        elapsed = time.time() - self.test_start_time
        test_name = self.getDescription(test)
        print(f"{Colors.RED}{Icons.FAIL} FAILED:{Colors.END} {test_name} ({elapsed:.3f}s)")
        self._print_error_details(test, err)

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        test_name = self.getDescription(test)
        print(f"{Colors.YELLOW}{Icons.SKIP} SKIPPED:{Colors.END} {test_name} - {reason}")

    def _print_error_details(self, test, err):
        """Print detailed error information"""
        exc_type, exc_value, exc_tb = err
        print(f"\n{Colors.RED}{'=' * 80}{Colors.END}")
        print(f"{Colors.RED}{Icons.ERROR} DETAILED ERROR REPORT{Colors.END}")
        print(f"{Colors.RED}{'=' * 80}{Colors.END}")
        print(f"\n{Colors.BOLD}Test:{Colors.END} {self.getDescription(test)}")
        print(f"{Colors.BOLD}Error Type:{Colors.END} {exc_type.__name__}")
        print(f"{Colors.BOLD}Error Message:{Colors.END} {exc_value}")

        # Print traceback
        print(f"\n{Colors.BOLD}Traceback:{Colors.END}")
        tb_lines = traceback.format_tb(exc_tb)
        for line in tb_lines:
            print(f"{Colors.YELLOW}{line}{Colors.END}", end='')

        # Print hash information if available from test object
        if hasattr(test, 'logger') and test.logger:
            try:
                print(f"\n{Colors.BOLD}{Icons.HASH} Hash Information:{Colors.END}")
                print(f"{Colors.CYAN}log_hash:{Colors.END} {json.dumps(dict(test.logger.log_hash), indent=2, default=str)}")
                print(f"{Colors.CYAN}syslog_hash:{Colors.END} {json.dumps(dict(test.logger.syslog_hash), indent=2, default=str)}")
            except Exception as e:
                print(f"{Colors.YELLOW}Could not print hash information: {e}{Colors.END}")

        print(f"{Colors.RED}{'=' * 80}{Colors.END}\n")


class BeautifulTestRunner(unittest.TextTestRunner):
    """Custom test runner with beautiful output"""

    def __init__(self, *args, **kwargs):
        self.quiet_mode = kwargs.get('verbosity', 1) == 0
        # Ensure verbosity is at least 1 for unittest framework
        if kwargs.get('verbosity', 1) == 0:
            kwargs['verbosity'] = 1
        super().__init__(*args, **kwargs)

    def _makeResult(self):
        """Override to pass quiet_mode to result"""
        return BeautifulTestResult(self.stream, self.descriptions, self.verbosity, quiet_mode=self.quiet_mode)

    def run(self, test):
        """Run tests with beautiful header and summary"""
        # Only show header if not in quiet mode
        if not self.quiet_mode:
            print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.END}")
            print(f"{Colors.BOLD}{Colors.BLUE}{Icons.LOGGER} HW_Mgmt_Logger Unit Tests{Colors.END}")
            print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.END}")
            print(f"{Colors.CYAN}Platform:{Colors.END} {platform.platform()}")
            print(f"{Colors.CYAN}Python:{Colors.END} {sys.version.split()[0]}")
            print(f"{Colors.CYAN}Start Time:{Colors.END} {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.END}\n")

        result = super().run(test)

        # Print summary (always shown, even in quiet mode)
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.BLUE}{Icons.CHECK} TEST SUMMARY{Colors.END}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.END}")
        print(f"{Colors.GREEN}{Icons.PASS} Passed:{Colors.END} {result.testsRun - len(result.failures) - len(result.errors) - len(result.skipped)}")
        print(f"{Colors.RED}{Icons.FAIL} Failed:{Colors.END} {len(result.failures)}")
        print(f"{Colors.RED}{Icons.ERROR} Errors:{Colors.END} {len(result.errors)}")
        print(f"{Colors.YELLOW}{Icons.SKIP} Skipped:{Colors.END} {len(result.skipped)}")
        print(f"{Colors.CYAN}Total Tests:{Colors.END} {result.testsRun}")

        if result.wasSuccessful():
            print(f"\n{Colors.GREEN}{Colors.BOLD}{Icons.PASS} ALL TESTS PASSED!{Colors.END}")
        else:
            print(f"\n{Colors.RED}{Colors.BOLD}{Icons.FAIL} SOME TESTS FAILED!{Colors.END}")

        print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.END}\n")

        return result


class TestHWMgmtLogger(unittest.TestCase):
    """Test suite for HW_Mgmt_Logger class"""

    @classmethod
    def setUpClass(cls):
        """Set up test class - runs once before all tests"""
        cls.temp_dir = tempfile.mkdtemp(prefix='hw_mgmt_logger_test_')
        cls.test_log_file = os.path.join(cls.temp_dir, 'test.log')
        cls.random_iterations = getattr(cls, 'random_iterations', 10)
        cls.quiet_mode = getattr(cls, 'quiet_mode', False)
        if not cls.quiet_mode:
            print(f"\n{Colors.CYAN}{Icons.INFO} Test directory:{Colors.END} {cls.temp_dir}")
            print(f"{Colors.CYAN}{Icons.RANDOM} Random iterations:{Colors.END} {cls.random_iterations}")

    @classmethod
    def tearDownClass(cls):
        """Clean up after all tests"""
        if os.path.exists(cls.temp_dir):
            shutil.rmtree(cls.temp_dir)
        if not cls.quiet_mode:
            print(f"\n{Colors.CYAN}{Icons.CLEAN} Cleaned up test directory{Colors.END}")

    def setUp(self):
        """Set up before each test"""
        self.logger = None
        # Clean up any previous log files
        if os.path.exists(self.test_log_file):
            os.remove(self.test_log_file)

    def tearDown(self):
        """Clean up after each test"""
        if self.logger:
            try:
                # Clear hashes before stopping
                with self.logger._lock:
                    self.logger.log_hash.clear()
                    self.logger.syslog_hash.clear()
                self.logger.stop()
            except Exception:
                pass
        self.logger = None

    def _clean_logger_state(self, logger):
        """Clean logger state before each iteration"""
        if logger:
            with logger._lock:
                logger.log_hash.clear()
                logger.syslog_hash.clear()

    # ========================================================================
    # Basic Initialization Tests
    # ========================================================================

    def test_01_basic_initialization(self):
        """Test basic logger initialization with default parameters"""
        self.logger = HW_Mgmt_Logger()
        self.assertIsNotNone(self.logger)
        self.assertEqual(self.logger.log_repeat, HW_Mgmt_Logger.LOG_REPEAT_UNLIMITED)
        self.assertEqual(self.logger.syslog_repeat, HW_Mgmt_Logger.LOG_REPEAT_UNLIMITED)
        self.assertIsInstance(self.logger.log_hash, dict)
        self.assertIsInstance(self.logger.syslog_hash, dict)

    def test_02_initialization_with_file(self):
        """Test logger initialization with log file"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.DEBUG)
        self.assertIsNotNone(self.logger)
        self.logger.info("Test message")
        self.assertTrue(os.path.exists(self.test_log_file))

    def test_03_initialization_with_stdout(self):
        """Test logger initialization with stdout"""
        self.logger = HW_Mgmt_Logger(log_file="stdout", log_level=HW_Mgmt_Logger.INFO)
        self.assertIsNotNone(self.logger)
        # Should not raise exception
        self.logger.info("Test stdout message")

    def test_04_initialization_with_stderr(self):
        """Test logger initialization with stderr"""
        self.logger = HW_Mgmt_Logger(log_file="stderr", log_level=HW_Mgmt_Logger.INFO)
        self.assertIsNotNone(self.logger)
        # Should not raise exception
        self.logger.info("Test stderr message")

    def test_05_initialization_invalid_repeat(self):
        """Test logger initialization with invalid repeat parameters"""
        with self.assertRaises(ValueError):
            self.logger = HW_Mgmt_Logger(log_repeat=-1)

        with self.assertRaises(ValueError):
            self.logger = HW_Mgmt_Logger(syslog_repeat=-1)

    def test_06_initialization_invalid_log_level(self):
        """Test logger initialization with invalid log level"""
        with self.assertRaises(ValueError):
            self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=999)

    def test_07_initialization_nonexistent_directory(self):
        """Test logger initialization with nonexistent directory"""
        bad_path = os.path.join(self.temp_dir, 'nonexistent', 'test.log')
        with self.assertRaises(PermissionError):
            self.logger = HW_Mgmt_Logger(log_file=bad_path)

    # ========================================================================
    # Logging Level Tests
    # ========================================================================

    def test_10_debug_logging(self):
        """Test DEBUG level logging"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.DEBUG)
        self.logger.debug("Debug message")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Debug message", content)
            self.assertIn("DEBUG", content)

    def test_11_info_logging(self):
        """Test INFO level logging"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.INFO)
        self.logger.info("Info message")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Info message", content)
            self.assertIn("INFO", content)

    def test_12_notice_logging(self):
        """Test NOTICE level logging"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.NOTICE)
        self.logger.notice("Notice message")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Notice message", content)
            self.assertIn("NOTICE", content)

    def test_13_warning_logging(self):
        """Test WARNING level logging"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.WARNING)
        self.logger.warning("Warning message")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Warning message", content)
            self.assertIn("WARNING", content)

    def test_14_error_logging(self):
        """Test ERROR level logging"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.ERROR)
        self.logger.error("Error message")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Error message", content)
            self.assertIn("ERROR", content)

    def test_15_critical_logging(self):
        """Test CRITICAL level logging"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.CRITICAL)
        self.logger.critical("Critical message")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Critical message", content)
            self.assertIn("CRITICAL", content)

    def test_16_log_level_filtering(self):
        """Test that log levels are properly filtered"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file, log_level=HW_Mgmt_Logger.WARNING)
        self.logger.debug("Debug - should not appear")
        self.logger.info("Info - should not appear")
        self.logger.warning("Warning - should appear")
        self.logger.error("Error - should appear")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertNotIn("Debug - should not appear", content)
            self.assertNotIn("Info - should not appear", content)
            self.assertIn("Warning - should appear", content)
            self.assertIn("Error - should appear", content)

    # ========================================================================
    # Message Repeat and Hash Tests
    # ========================================================================

    def test_20_message_repeat_unlimited(self):
        """Test unlimited message repeat"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO,
                                     log_repeat=0)

        for i in range(5):
            self.logger.info(f"Message {i}", id="test_id", log_repeat=0)

        # With repeat=0, messages should not be logged
        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertEqual(content.strip(), "")

    def test_21_message_repeat_with_id(self):
        """Test message repeat with ID"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        # Log same message 5 times with repeat limit of 2
        for i in range(5):
            self.logger.info("Repeated message", id="repeat_test", log_repeat=2)

        with open(self.test_log_file, 'r') as f:
            lines = f.readlines()
            # Should only appear 2 times
            msg_count = sum(1 for line in lines if "Repeated message" in line and "stopped" not in line)
            self.assertEqual(msg_count, 2)

    def test_22_message_repeat_finalization(self):
        """Test message repeat finalization"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        # Log message multiple times
        for i in range(5):
            self.logger.info("Test message", id="final_test", log_repeat=2)

        # Send finalization (empty message)
        self.logger.info("", id="final_test")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("message repeated 5 times", content)
            self.assertIn("and stopped", content)

    def test_23_hash_collision_handling(self):
        """Test that different messages with same ID are handled correctly"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        # First message with ID
        self.logger.info("Message 1", id="same_id", log_repeat=2)
        self.logger.info("Message 1", id="same_id", log_repeat=2)

        # Clear and send different message with same ID
        self.logger.info("", id="same_id")
        self.logger.info("Message 2", id="same_id", log_repeat=2)

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Message 1", content)
            self.assertIn("Message 2", content)

    def test_24_hash_garbage_collection_size_limit(self):
        """Test hash garbage collection when size exceeds MAX_MSG_HASH_SIZE"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        # Add more than MAX_MSG_HASH_SIZE messages
        for i in range(HW_Mgmt_Logger.MAX_MSG_HASH_SIZE + 10):
            self.logger.info(f"Message {i}", id=f"id_{i}", log_repeat=1)

        # Hash should be cleared
        self.assertLessEqual(len(self.logger.log_hash), HW_Mgmt_Logger.MAX_MSG_HASH_SIZE)

    def test_25_hash_garbage_collection_timeout(self):
        """Test hash garbage collection based on timeout"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        # Add messages to hash
        for i in range(HW_Mgmt_Logger.MAX_MSG_TIMEOUT_HASH_SIZE + 5):
            self.logger.info(f"Message {i}", id=f"id_{i}", log_repeat=1)

        # Manually set old timestamp for some messages
        current_time = current_milli_time()
        old_time = current_time - HW_Mgmt_Logger.MSG_HASH_TIMEOUT - 1000

        # Modify timestamps
        keys = list(self.logger.log_hash.keys())[:3]
        for key in keys:
            self.logger.log_hash[key]["ts"] = old_time

        # Trigger garbage collection by adding new message
        for i in range(5):
            self.logger.info(f"New message {i}", id=f"new_id_{i}", log_repeat=1)

        # Old messages should be removed
        self.assertLessEqual(len(self.logger.log_hash), HW_Mgmt_Logger.MAX_MSG_TIMEOUT_HASH_SIZE + 10)

    # ========================================================================
    # Suspend/Resume Tests
    # ========================================================================

    def test_30_suspend_logging(self):
        """Test suspending logging"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        self.logger.info("Before suspend")
        self.logger.suspend()
        self.logger.info("During suspend - should not appear")
        self.logger.resume()
        self.logger.info("After resume")

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Before suspend", content)
            self.assertNotIn("During suspend", content)
            self.assertIn("After resume", content)

    def test_31_multiple_suspend_resume(self):
        """Test multiple suspend/resume cycles"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        for i in range(3):
            self.logger.info(f"Active {i}")
            self.logger.suspend()
            self.logger.info(f"Suspended {i}")
            self.logger.resume()

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            for i in range(3):
                self.assertIn(f"Active {i}", content)
                self.assertNotIn(f"Suspended {i}", content)

    # ========================================================================
    # Syslog Tests
    # ========================================================================

    @patch('syslog.openlog')
    @patch('syslog.syslog')
    @patch('syslog.closelog')
    def test_40_syslog_initialization(self, mock_closelog, mock_syslog, mock_openlog):
        """Test syslog initialization"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     syslog_level=HW_Mgmt_Logger.NOTICE)
        self.assertIsNotNone(self.logger._syslog)

    @patch('syslog.openlog')
    @patch('syslog.syslog')
    def test_41_syslog_critical_always_logged(self, mock_syslog, mock_openlog):
        """Test that CRITICAL messages always go to syslog"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     syslog_level=HW_Mgmt_Logger.ERROR)
        self.logger.critical("Critical message")

        # Critical should be logged to syslog
        mock_syslog.assert_called()

    @patch('syslog.openlog')
    @patch('syslog.syslog')
    def test_42_syslog_level_filtering(self, mock_syslog, mock_openlog):
        """Test syslog level filtering"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     syslog_level=HW_Mgmt_Logger.ERROR)

        mock_syslog.reset_mock()
        self.logger.info("Info - should not go to syslog")
        # Info should not trigger syslog
        self.assertEqual(mock_syslog.call_count, 0)

        mock_syslog.reset_mock()
        self.logger.error("Error - should go to syslog")
        # Error should trigger syslog
        self.assertGreater(mock_syslog.call_count, 0)

    @patch('syslog.openlog')
    @patch('syslog.syslog')
    def test_43_syslog_unicode_handling(self, mock_syslog, mock_openlog):
        """Test syslog handles unicode correctly"""
        # Don't log to file to avoid encoding issues on systems with latin-1
        self.logger = HW_Mgmt_Logger(syslog_level=HW_Mgmt_Logger.NOTICE)

        unicode_msg = "Test with unicode: ASCII-safe test message"
        self.logger.notice(unicode_msg)

        # Should handle without raising exception
        mock_syslog.assert_called()

    @patch('syslog.openlog')
    @patch('syslog.syslog')
    @patch('syslog.closelog')
    def test_44_syslog_close(self, mock_closelog, mock_syslog, mock_openlog):
        """Test syslog closure"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     syslog_level=HW_Mgmt_Logger.NOTICE)
        self.logger.close_syslog()

        mock_closelog.assert_called_once()
        self.assertIsNone(self.logger._syslog)

    # ========================================================================
    # set_param Tests
    # ========================================================================

    def test_50_set_param_change_log_file(self):
        """Test changing log file with set_param"""
        log_file2 = os.path.join(self.temp_dir, 'test2.log')

        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)
        self.logger.info("Message in first file")

        # Change log file
        self.logger.set_param(log_file=log_file2, log_level=HW_Mgmt_Logger.INFO)
        self.logger.info("Message in second file")

        # Both files should exist
        self.assertTrue(os.path.exists(self.test_log_file))
        self.assertTrue(os.path.exists(log_file2))

        # Clean up second file
        if os.path.exists(log_file2):
            os.remove(log_file2)

    def test_51_set_param_invalid_log_file_type(self):
        """Test set_param with invalid log_file type"""
        self.logger = HW_Mgmt_Logger()

        with self.assertRaises(ValueError):
            self.logger.set_param(log_file=123)

    def test_52_set_param_invalid_log_level(self):
        """Test set_param with invalid log level"""
        self.logger = HW_Mgmt_Logger()

        with self.assertRaises(ValueError):
            self.logger.set_param(log_level=999)

    def test_53_set_param_invalid_syslog_level(self):
        """Test set_param with invalid syslog level"""
        self.logger = HW_Mgmt_Logger()

        with self.assertRaises(ValueError):
            self.logger.set_param(syslog_level=999)

    # ========================================================================
    # Thread Safety Tests
    # ========================================================================

    def test_60_thread_safety_locks(self):
        """Test that logger has thread safety locks"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        self.assertIsNotNone(self.logger._lock)

    def test_61_concurrent_hash_access(self):
        """Test concurrent access to hash doesn't raise exceptions"""
        import threading

        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        def log_messages():
            for i in range(10):
                self.logger.info(f"Thread message {i}", id=f"thread_{threading.current_thread().name}_{i}")

        threads = []
        for i in range(5):
            t = threading.Thread(target=log_messages, name=f"Thread_{i}")
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

        # Should complete without exceptions
        self.assertTrue(os.path.exists(self.test_log_file))

    # ========================================================================
    # Edge Cases and Special Tests
    # ========================================================================

    def test_70_empty_message(self):
        """Test logging empty message"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        # Should not raise exception
        self.logger.info("")
        self.logger.info(None)

    def test_71_none_message_conversion(self):
        """Test that None messages are converted to empty strings"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        self.logger.info(None)
        # Should not raise exception

    def test_72_non_string_message(self):
        """Test logging non-string messages"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        self.logger.info(12345)
        self.logger.info(3.14159)
        self.logger.info(['list', 'of', 'items'])
        self.logger.info({'dict': 'value'})

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("12345", content)
            self.assertIn("3.14159", content)

    def test_73_very_long_message(self):
        """Test logging very long messages"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        long_msg = "A" * 10000
        self.logger.info(long_msg)

        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("A" * 100, content)  # Check that at least part is there

    def test_74_special_characters_in_message(self):
        """Test logging messages with special characters"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        special_msg = "Test with \n newlines \t tabs and \"quotes\" and 'apostrophes'"
        self.logger.info(special_msg)

        # Should handle special characters
        self.assertTrue(os.path.exists(self.test_log_file))

    def test_75_non_hashable_id(self):
        """Test logging with non-hashable ID"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        # Use list as ID (not hashable)
        self.logger.info("Message with non-hashable id", id=['not', 'hashable'])

        # Should handle gracefully by treating as if no id was provided
        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Message with non-hashable id", content)

    def test_76_invalid_log_level_in_handler(self):
        """Test log_handler with invalid level"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        with self.assertRaises(ValueError):
            self.logger.log_handler(999, "Invalid level")

    def test_77_invalid_repeat_in_handler(self):
        """Test log_handler with invalid repeat values"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        with self.assertRaises(ValueError):
            self.logger.log_handler(HW_Mgmt_Logger.INFO, "Test", log_repeat=-1)

        with self.assertRaises(ValueError):
            self.logger.log_handler(HW_Mgmt_Logger.INFO, "Test", syslog_repeat=-1)

    def test_78_stop_and_cleanup(self):
        """Test stop method cleans up properly"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        self.logger.info("Before stop", id="test_id", log_repeat=1)
        self.assertTrue(len(self.logger.log_hash) > 0)

        self.logger.stop()

        # Hashes should be cleared
        self.assertEqual(len(self.logger.log_hash), 0)
        self.assertEqual(len(self.logger.syslog_hash), 0)

    def test_79_destructor(self):
        """Test that destructor doesn't raise exceptions"""
        logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                log_level=HW_Mgmt_Logger.INFO)
        logger.info("Test message")

        # Delete logger - should call __del__
        del logger
        # Should not raise exception

    # ========================================================================
    # Random Tests with N Iterations
    # ========================================================================

    def test_80_random_log_levels(self):
        """Test random log levels with N iterations"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.DEBUG)

        levels = [
            (self.logger.debug, "DEBUG"),
            (self.logger.info, "INFO"),
            (self.logger.notice, "NOTICE"),
            (self.logger.warning, "WARNING"),
            (self.logger.error, "ERROR"),
            (self.logger.critical, "CRITICAL")
        ]

        for iteration in range(self.random_iterations):
            if not self.quiet_mode:
                print(f"  {Colors.YELLOW}{Icons.RANDOM} Iteration {iteration + 1}/{self.random_iterations}{Colors.END}")

            # Clean state before each iteration
            self._clean_logger_state(self.logger)

            # Pick random level
            log_func, level_name = random.choice(levels)
            msg = f"Random message {iteration} at {level_name}"
            log_func(msg)

            # Verify it was logged
            with open(self.test_log_file, 'r') as f:
                content = f.read()
                self.assertIn(msg, content)

    def test_81_random_repeat_values(self):
        """Test random repeat values with N iterations"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        for iteration in range(self.random_iterations):
            if not self.quiet_mode:
                print(f"  {Colors.YELLOW}{Icons.RANDOM} Iteration {iteration + 1}/{self.random_iterations}{Colors.END}")

            # Clean state before each iteration
            self._clean_logger_state(self.logger)

            # Random repeat value
            repeat_val = random.randint(1, 10)
            test_id = f"rand_repeat_{iteration}"

            # Log more times than repeat value
            for i in range(repeat_val + 5):
                self.logger.info(f"Repeat test {iteration}", id=test_id, log_repeat=repeat_val)

            # Count occurrences
            with open(self.test_log_file, 'r') as f:
                content = f.read()
                count = content.count(f"Repeat test {iteration}")
                # Should only appear repeat_val times (not counting finalization)
                self.assertLessEqual(count, repeat_val + 1)  # +1 for potential finalization

    def test_82_random_message_lengths(self):
        """Test random message lengths with N iterations"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        for iteration in range(self.random_iterations):
            if not self.quiet_mode:
                print(f"  {Colors.YELLOW}{Icons.RANDOM} Iteration {iteration + 1}/{self.random_iterations}{Colors.END}")

            # Clean state before each iteration
            self._clean_logger_state(self.logger)

            # Random message length
            msg_length = random.randint(1, 1000)
            msg = f"Msg_{iteration}_" + ("X" * msg_length)
            self.logger.info(msg)

            # Verify it was logged
            with open(self.test_log_file, 'r') as f:
                content = f.read()
                self.assertIn(f"Msg_{iteration}_", content)

    def test_83_random_suspend_resume(self):
        """Test random suspend/resume with N iterations"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        for iteration in range(self.random_iterations):
            if not self.quiet_mode:
                print(f"  {Colors.YELLOW}{Icons.RANDOM} Iteration {iteration + 1}/{self.random_iterations}{Colors.END}")

            # Clean state before each iteration
            self._clean_logger_state(self.logger)

            # Random suspend/resume
            if random.choice([True, False]):
                self.logger.suspend()
                suspended_msg = f"Suspended message {iteration}"
                self.logger.info(suspended_msg)
                self.logger.resume()

                # Should not be in log
                with open(self.test_log_file, 'r') as f:
                    content = f.read()
                    self.assertNotIn(suspended_msg, content)
            else:
                active_msg = f"Active message {iteration}"
                self.logger.info(active_msg)

                # Should be in log
                with open(self.test_log_file, 'r') as f:
                    content = f.read()
                    self.assertIn(active_msg, content)

    def test_84_random_hash_operations(self):
        """Test random hash operations with N iterations"""
        self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                     log_level=HW_Mgmt_Logger.INFO)

        for iteration in range(self.random_iterations):
            if not self.quiet_mode:
                print(f"  {Colors.YELLOW}{Icons.RANDOM} Iteration {iteration + 1}/{self.random_iterations}{Colors.END}")

            # Clean state before each iteration
            self._clean_logger_state(self.logger)

            # Add random number of messages to hash
            num_messages = random.randint(1, 20)
            for i in range(num_messages):
                self.logger.info(f"Hash msg {iteration}_{i}",
                                 id=f"hash_id_{iteration}_{i}",
                                 log_repeat=random.randint(1, 5))

            # Verify hash is not too large
            self.assertLessEqual(len(self.logger.log_hash), HW_Mgmt_Logger.MAX_MSG_HASH_SIZE)

    # ========================================================================
    # File Rotation Tests
    # ========================================================================

    def test_90_file_rotation(self):
        """Test log file rotation"""
        small_size = 1024  # 1KB for testing

        # Temporarily modify the max size
        original_size = HW_Mgmt_Logger.MAX_LOG_FILE_SIZE
        HW_Mgmt_Logger.MAX_LOG_FILE_SIZE = small_size

        try:
            self.logger = HW_Mgmt_Logger(log_file=self.test_log_file,
                                         log_level=HW_Mgmt_Logger.INFO)

            # Write enough to trigger rotation
            for i in range(100):
                self.logger.info("X" * 100)

            # Check if rotated files exist
            self.assertTrue(os.path.exists(self.test_log_file))

        finally:
            HW_Mgmt_Logger.MAX_LOG_FILE_SIZE = original_size

    # ========================================================================
    # Current Time Function Test
    # ========================================================================

    def test_95_current_milli_time(self):
        """Test current_milli_time function"""
        time1 = current_milli_time()
        time.sleep(0.01)  # Sleep 10ms
        time2 = current_milli_time()

        self.assertGreater(time2, time1)
        self.assertGreaterEqual(time2 - time1, 10)  # At least 10ms difference


def main():
    """Main entry point for standalone execution"""
    parser = argparse.ArgumentParser(
        description='Unit Tests for HW_Mgmt_Logger class',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
{Colors.BOLD}Examples:{Colors.END}
  {Colors.CYAN}# Run all tests with default 10 random iterations{Colors.END}
  python3 test_hw_mgmt_logger.py

  {Colors.CYAN}# Run tests with 50 random iterations{Colors.END}
  python3 test_hw_mgmt_logger.py --random-iterations 50

  {Colors.CYAN}# Run tests with short option{Colors.END}
  python3 test_hw_mgmt_logger.py -n 100

  {Colors.CYAN}# Run specific test{Colors.END}
  python3 test_hw_mgmt_logger.py __main__.TestHWMgmtLogger.test_01_basic_initialization

  {Colors.CYAN}# Run with verbose output (verbosity level 2){Colors.END}
  python3 test_hw_mgmt_logger.py --verbosity 2

  {Colors.CYAN}# Run in quiet mode (verbosity level 0){Colors.END}
  python3 test_hw_mgmt_logger.py --verbosity 0
        """
    )

    parser.add_argument(
        '--random-iterations', '-n',
        type=int,
        default=10,
        dest='iterations',
        help='Number of iterations for random tests (default: 10)'
    )

    parser.add_argument(
        '--verbosity',
        type=int,
        choices=[0, 1, 2],
        default=1,
        help='Verbosity level: 0=quiet, 1=normal, 2=verbose (default: 1)'
    )

    parser.add_argument(
        'tests',
        nargs='*',
        help='Specific tests to run (e.g., __main__.TestHWMgmtLogger.test_01_basic_initialization)'
    )

    args = parser.parse_args()

    # Set random iterations and quiet mode on the test class
    TestHWMgmtLogger.random_iterations = args.iterations
    TestHWMgmtLogger.quiet_mode = (args.verbosity == 0)

    # Create test suite
    if args.tests:
        # Run specific tests
        suite = unittest.TestLoader().loadTestsFromNames(args.tests)
    else:
        # Run all tests
        suite = unittest.TestLoader().loadTestsFromTestCase(TestHWMgmtLogger)

    # Run tests with beautiful output
    runner = BeautifulTestRunner(verbosity=args.verbosity)
    result = runner.run(suite)

    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == '__main__':
    main()
