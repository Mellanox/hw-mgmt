#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Unit Tests for HW_Mgmt_Logger Class
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

import sys
import os
import unittest
import tempfile
import shutil
import threading
import time
import random
import string
import argparse
import traceback
import logging
from io import StringIO
from unittest.mock import patch, MagicMock
from pathlib import Path

# Add the library path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', 'usr', 'usr', 'bin'))

try:
    from hw_management_lib import HW_Mgmt_Logger
except ImportError as e:
    print(f"[FAIL] Failed to import HW_Mgmt_Logger: {e}")
    sys.exit(1)

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
    RESET = '\033[0m'

# Icons for test status - fallback to simple chars if Unicode not supported


class Icons:
    try:
        # Test if Unicode emojis work
        test_encode = "[PASS]".encode(sys.stdout.encoding or 'utf-8')
        PASS = f"{Colors.GREEN}[PASS]{Colors.RESET}"
        FAIL = f"{Colors.RED}[FAIL]{Colors.RESET}"
        SKIP = f"{Colors.YELLOW}⏭️{Colors.RESET}"
        INFO = f"{Colors.BLUE}ℹ️{Colors.RESET}"
        WARNING = f"{Colors.YELLOW}⚠️{Colors.RESET}"
        DEBUG = f"{Colors.CYAN}🐛{Colors.RESET}"
        RANDOM = f"{Colors.MAGENTA}🎲{Colors.RESET}"
        THREAD = f"{Colors.CYAN}🧵{Colors.RESET}"
        FILE = f"{Colors.BLUE}📁{Colors.RESET}"
        LOG = f"{Colors.GREEN}📝{Colors.RESET}"
    except (UnicodeEncodeError, LookupError, AttributeError):
        # Fallback to ASCII characters
        PASS = f"{Colors.GREEN}+{Colors.RESET}"
        FAIL = f"{Colors.RED}X{Colors.RESET}"
        SKIP = f"{Colors.YELLOW}>{Colors.RESET}"
        INFO = f"{Colors.BLUE}i{Colors.RESET}"
        WARNING = f"{Colors.YELLOW}!{Colors.RESET}"
        DEBUG = f"{Colors.CYAN}#{Colors.RESET}"
        RANDOM = f"{Colors.MAGENTA}?{Colors.RESET}"
        THREAD = f"{Colors.CYAN}T{Colors.RESET}"
        FILE = f"{Colors.BLUE}F{Colors.RESET}"
        LOG = f"{Colors.GREEN}L{Colors.RESET}"

# Removed DetailedTestResult class - using standard unittest runner instead


class TestHWMgmtLogger(unittest.TestCase):
    """Comprehensive test suite for HW_Mgmt_Logger class"""

    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.test_log_file = os.path.join(self.temp_dir, "test.log")
        self._test_params = {}

        # Clean any global state (sensor_read_error mentioned in requirements)
        if hasattr(sys.modules.get('hw_management_lib', None), 'sensor_read_error'):
            sys.modules['hw_management_lib'].sensor_read_error = None

    def tearDown(self):
        """Clean up test environment"""
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _store_test_params(self, **kwargs):
        """Store test parameters for error reporting"""
        self._test_params = kwargs

    def test_basic_initialization(self):
        """Test basic logger initialization"""
        params = {
            'ident': 'test_logger',
            'log_level': HW_Mgmt_Logger.INFO,
            'syslog_level': HW_Mgmt_Logger.WARNING
        }
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Verify logger attributes
        self.assertIsNotNone(logger.logger)
        self.assertEqual(logger.log_repeat, 0)
        self.assertEqual(logger.syslog_repeat, 0)

        logger.stop()

    def test_file_logging_initialization(self):
        """Test logger initialization with file logging"""
        params = {
            'log_file': self.test_log_file,
            'log_level': HW_Mgmt_Logger.DEBUG
        }
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Verify file handler is created
        self.assertIsNotNone(logger.logger_fh)
        self.assertTrue(os.path.exists(self.test_log_file))

        logger.stop()

    def test_stdout_logging(self):
        """Test logging to stdout"""
        params = {'log_file': 'stdout', 'log_level': HW_Mgmt_Logger.INFO}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Verify that a StreamHandler was created
        self.assertIsNotNone(logger.logger_fh)
        self.assertIsInstance(logger.logger_fh, logging.StreamHandler)

        logger.stop()

    def test_stderr_logging(self):
        """Test logging to stderr"""
        params = {'log_file': 'stderr', 'log_level': HW_Mgmt_Logger.INFO}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Verify that a StreamHandler was created
        self.assertIsNotNone(logger.logger_fh)
        self.assertIsInstance(logger.logger_fh, logging.StreamHandler)

        logger.stop()

    def test_syslog_initialization(self):
        """Test syslog initialization"""
        params = {
            'ident': 'test_syslog',
            'syslog_level': HW_Mgmt_Logger.INFO
        }
        self._store_test_params(**params)

        with patch('syslog.openlog') as mock_openlog:
            logger = HW_Mgmt_Logger(**params)
            mock_openlog.assert_called_once()
            logger.stop()

    def test_log_levels(self):
        """Test all log levels"""
        params = {'log_file': self.test_log_file, 'log_level': HW_Mgmt_Logger.DEBUG}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Test all log level methods
        logger.debug("Debug message")
        logger.info("Info message")
        logger.notice("Notice message")
        logger.warn("Warning message")
        logger.error("Error message")
        logger.critical("Critical message")

        logger.stop()

        # Verify messages were logged
        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("Debug message", content)
            self.assertIn("Info message", content)
            self.assertIn("Notice message", content)
            self.assertIn("Warning message", content)
            self.assertIn("Error message", content)
            self.assertIn("Critical message", content)

    def test_level_filtering(self):
        """Test log level filtering"""
        params = {'log_file': self.test_log_file, 'log_level': HW_Mgmt_Logger.WARNING}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Log messages at different levels
        logger.debug("Debug message")  # Should be filtered out
        logger.info("Info message")    # Should be filtered out
        logger.warn("Warning message")  # Should be logged
        logger.error("Error message")      # Should be logged

        logger.stop()

        # Verify filtering
        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertNotIn("Debug message", content)
            self.assertNotIn("Info message", content)
            self.assertIn("Warning message", content)
            self.assertIn("Error message", content)

    def test_repeat_functionality(self):
        """Test message repeat/collapse functionality"""
        params = {
            'log_file': self.test_log_file,
            'log_level': HW_Mgmt_Logger.DEBUG,
            'log_repeat': 0,
            'syslog_repeat': 0
        }
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Test repeat functionality
        logger.info("Repeating message", id="test_repeat", log_repeat=2)
        logger.info("Repeating message", id="test_repeat", log_repeat=2)
        logger.info("Repeating message", id="test_repeat", log_repeat=2)  # Should be collapsed

        # Finalize the repeat
        logger.info("", id="test_repeat")

        logger.stop()

        # Verify repeat behavior
        with open(self.test_log_file, 'r') as f:
            content = f.read()
            self.assertIn("message repeated", content)
            self.assertIn("and stopped", content)

    def test_parameter_validation(self):
        """Test parameter validation"""

        # Test invalid log_repeat
        params = {'log_repeat': -1}
        self._store_test_params(**params)
        with self.assertRaises(ValueError):
            HW_Mgmt_Logger(**params)

        # Test invalid syslog_repeat
        params = {'syslog_repeat': -1}
        self._store_test_params(**params)
        with self.assertRaises(ValueError):
            HW_Mgmt_Logger(**params)

        # Test invalid log_file type
        params = {'log_file': 123}
        self._store_test_params(**params)
        with self.assertRaises(ValueError):
            HW_Mgmt_Logger(**params)

    def test_unicode_messages(self):
        """Test Unicode and special character handling"""
        params = {'log_file': self.test_log_file, 'log_level': HW_Mgmt_Logger.INFO}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Test Unicode messages - use safe characters for testing
        unicode_msg = "Unicode test: Japanese Arabic Russian text"
        logger.info(unicode_msg)

        # Test special characters
        special_msg = "Special chars: \n\t\r\\"
        logger.info(special_msg)

        logger.stop()

        # Verify messages were handled correctly
        with open(self.test_log_file, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("Unicode test", content)

    def test_none_and_empty_messages(self):
        """Test None and empty message handling"""
        params = {'log_file': self.test_log_file, 'log_level': HW_Mgmt_Logger.INFO}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Test None message
        logger.info(None)

        # Test empty message
        logger.info("")

        # Test non-string message
        logger.info(12345)
        logger.info(['list', 'message'])

        logger.stop()

    def test_directory_validation(self):
        """Test log directory validation"""

        # Test non-existent directory
        bad_path = "/non/existent/directory/test.log"
        params = {'log_file': bad_path}
        self._store_test_params(**params)

        with self.assertRaises(PermissionError):
            HW_Mgmt_Logger(**params)

    def test_resource_cleanup(self):
        """Test proper resource cleanup"""
        params = {'log_file': self.test_log_file, 'log_level': HW_Mgmt_Logger.INFO}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        # Verify handler is created
        self.assertIsNotNone(logger.logger_fh)

        # Test cleanup
        logger.stop()

        # Verify cleanup
        self.assertIsNone(logger.logger_fh)

    def test_thread_safety(self):
        """Test thread safety of logger"""
        params = {'log_file': self.test_log_file, 'log_level': HW_Mgmt_Logger.INFO}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(**params)

        def log_worker(worker_id, count):
            for i in range(count):
                logger.info(f"Worker {worker_id} message {i}")

        # Start multiple threads
        threads = []
        for i in range(5):
            thread = threading.Thread(target=log_worker, args=(i, 10))
            threads.append(thread)
            thread.start()

        # Wait for all threads to complete
        for thread in threads:
            thread.join()

        logger.stop()

        # Verify all messages were logged
        with open(self.test_log_file, 'r') as f:
            content = f.read()
            # Should have 50 total messages (5 workers * 10 messages)
            message_count = content.count("Worker")
            self.assertEqual(message_count, 50)


class RandomizedTests(unittest.TestCase):
    """Randomized test cases that run multiple iterations"""

    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self._test_params = {}

        # Clean sensor_read_error before each iteration
        if hasattr(sys.modules.get('hw_management_lib', None), 'sensor_read_error'):
            sys.modules['hw_management_lib'].sensor_read_error = None

    def tearDown(self):
        """Clean up test environment"""
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _store_test_params(self, **kwargs):
        """Store test parameters for error reporting"""
        self._test_params = kwargs

    def _random_string(self, length=None):
        """Generate random string"""
        if length is None:
            length = random.randint(1, 50)
        return ''.join(random.choices(string.ascii_letters + string.digits + ' ', k=length))

    def _random_log_level(self):
        """Get random log level"""
        levels = [
            HW_Mgmt_Logger.DEBUG,
            HW_Mgmt_Logger.INFO,
            HW_Mgmt_Logger.NOTICE,
            HW_Mgmt_Logger.WARNING,
            HW_Mgmt_Logger.ERROR,
            HW_Mgmt_Logger.CRITICAL
        ]
        return random.choice(levels)

    def test_random_messages(self):
        """Test with random messages - run N iterations"""
        iterations = getattr(self, 'iterations', 10)

        for i in range(iterations):
            # Clean sensor_read_error before each iteration
            if hasattr(sys.modules.get('hw_management_lib', None), 'sensor_read_error'):
                sys.modules['hw_management_lib'].sensor_read_error = None

            with self.subTest(iteration=i):
                # Generate random parameters
                log_file = os.path.join(self.temp_dir, f"random_test_{i}.log")
                log_level = self._random_log_level()
                syslog_level = random.choice([None, self._random_log_level()])
                log_repeat = random.randint(0, 5)
                syslog_repeat = random.randint(0, 5)

                params = {
                    'log_file': log_file,
                    'log_level': log_level,
                    'syslog_level': syslog_level,
                    'log_repeat': log_repeat,
                    'syslog_repeat': syslog_repeat,
                    'iteration': i
                }
                self._store_test_params(**params)

                print(f"{Icons.RANDOM} Random test iteration {i + 1}/{iterations}")

                try:
                    logger = HW_Mgmt_Logger(
                        log_file=log_file,
                        log_level=log_level,
                        syslog_level=syslog_level,
                        log_repeat=log_repeat,
                        syslog_repeat=syslog_repeat
                    )

                    # Generate random messages
                    message_count = random.randint(1, 20)
                    for j in range(message_count):
                        message = self._random_string()
                        level_method = random.choice(['debug', 'info', 'notice', 'warn', 'error', 'critical'])
                        getattr(logger, level_method)(message)

                    logger.stop()

                    # Verify log file exists if it should
                    if log_file and os.path.dirname(log_file):
                        self.assertTrue(os.path.exists(log_file))

                except Exception as e:
                    # Add iteration info to error
                    self._test_params['error_iteration'] = i
                    self._test_params['error_details'] = str(e)
                    raise

    def test_random_repeat_patterns(self):
        """Test random repeat patterns - run N iterations"""
        iterations = getattr(self, 'iterations', 10)

        for i in range(iterations):
            # Clean sensor_read_error before each iteration
            if hasattr(sys.modules.get('hw_management_lib', None), 'sensor_read_error'):
                sys.modules['hw_management_lib'].sensor_read_error = None

            with self.subTest(iteration=i):
                log_file = os.path.join(self.temp_dir, f"repeat_test_{i}.log")

                params = {
                    'log_file': log_file,
                    'iteration': i,
                    'log_level': HW_Mgmt_Logger.DEBUG
                }
                self._store_test_params(**params)

                print(f"{Icons.RANDOM} Random repeat test iteration {i + 1}/{iterations}")

                logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.DEBUG)

                # Generate random repeat patterns
                repeat_id = f"repeat_{i}_{random.randint(1000, 9999)}"
                repeat_count = random.randint(1, 10)
                message = self._random_string()

                # Send repeated messages
                for j in range(repeat_count + 2):  # Send more than repeat count
                    logger.info(message, id=repeat_id, repeat=repeat_count)

                # Finalize
                logger.info(None, id=repeat_id)

                logger.stop()


class CustomTestRunner:
    """Custom test runner with beautiful output"""

    def __init__(self, verbosity=2, random_iterations=10):
        self.verbosity = verbosity
        self.random_iterations = random_iterations

    def run(self, test_suite):
        """Run the test suite with custom formatting"""
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{Icons.LOG} HW_Mgmt_Logger Comprehensive Test Suite{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.RESET}")
        print(f"{Icons.INFO} Random iterations: {Colors.BOLD}{self.random_iterations}{Colors.RESET}")
        print(f"{Icons.INFO} Test verbosity: {Colors.BOLD}{self.verbosity}{Colors.RESET}")

        # Set random iterations on randomized test classes
        for test_case in test_suite:
            if hasattr(test_case, '__iter__'):
                for test in test_case:
                    if isinstance(test, RandomizedTests):
                        test.iterations = self.random_iterations

        # Use standard test runner but capture results
        runner = unittest.TextTestRunner(verbosity=self.verbosity, stream=sys.stdout)

        # Run tests
        start_time = time.time()
        result = runner.run(test_suite)
        end_time = time.time()

        # Print summary
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{Icons.LOG} Test Results Summary{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 80}{Colors.RESET}")

        total_tests = result.testsRun
        failures = len(result.failures)
        errors = len(result.errors)
        skipped = len(result.skipped)
        passed = total_tests - failures - errors - skipped

        print(f"{Icons.PASS} {Colors.GREEN}{Colors.BOLD}Passed:{Colors.RESET} {passed}")
        print(f"{Icons.FAIL} {Colors.RED}{Colors.BOLD}Failed:{Colors.RESET} {failures}")
        print(f"{Icons.FAIL} {Colors.RED}{Colors.BOLD}Errors:{Colors.RESET} {errors}")
        print(f"{Icons.SKIP} {Colors.YELLOW}{Colors.BOLD}Skipped:{Colors.RESET} {skipped}")
        print(f"{Icons.INFO} {Colors.BLUE}{Colors.BOLD}Total:{Colors.RESET} {total_tests}")
        print(f"{Icons.INFO} {Colors.BLUE}{Colors.BOLD}Time:{Colors.RESET} {end_time - start_time:.2f}s")

        success_rate = (passed / total_tests * 100) if total_tests > 0 else 0
        if success_rate == 100:
            print(f"\n{Icons.PASS} {Colors.GREEN}{Colors.BOLD}ALL TESTS PASSED!{Colors.RESET}")
        elif success_rate >= 90:
            print(f"\n{Icons.WARNING} {Colors.YELLOW}{Colors.BOLD}Success Rate: {success_rate:.1f}%{Colors.RESET}")
        else:
            print(f"\n{Icons.FAIL} {Colors.RED}{Colors.BOLD}Success Rate: {success_rate:.1f}%{Colors.RESET}")

        # Print detailed error information if there are failures or errors
        if result.failures:
            print(f"\n{Colors.RED}{Colors.BOLD}FAILURE DETAILS:{Colors.RESET}")
            for test, traceback in result.failures:
                print(f"{Colors.RED}{'=' * 60}{Colors.RESET}")
                print(f"{Colors.BOLD}Test:{Colors.RESET} {test}")
                print(f"{Colors.BOLD}Traceback:{Colors.RESET}")
                print(traceback)

        if result.errors:
            print(f"\n{Colors.RED}{Colors.BOLD}ERROR DETAILS:{Colors.RESET}")
            for test, traceback in result.errors:
                print(f"{Colors.RED}{'=' * 60}{Colors.RESET}")
                print(f"{Colors.BOLD}Test:{Colors.RESET} {test}")
                print(f"{Colors.BOLD}Traceback:{Colors.RESET}")
                print(traceback)

        return result


def main():
    """Main test execution function"""
    parser = argparse.ArgumentParser(description='HW_Mgmt_Logger Comprehensive Test Suite')
    parser.add_argument('-r', '--random-iterations', type=int, default=10,
                        help='Number of iterations for randomized tests (default: 10)')
    parser.add_argument('-v', '--verbosity', type=int, default=2, choices=[0, 1, 2],
                        help='Test verbosity level (default: 2)')

    args = parser.parse_args()

    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add all test cases
    suite.addTests(loader.loadTestsFromTestCase(TestHWMgmtLogger))
    suite.addTests(loader.loadTestsFromTestCase(RandomizedTests))

    # Run tests with custom runner
    runner = CustomTestRunner(verbosity=args.verbosity, random_iterations=args.random_iterations)
    result = runner.run(suite)

    # Exit with appropriate code
    exit_code = 0 if (not result.failures and not result.errors) else 1
    print(f"\n{Icons.INFO} Exiting with code: {exit_code}")
    sys.exit(exit_code)


if __name__ == '__main__':
    main()
