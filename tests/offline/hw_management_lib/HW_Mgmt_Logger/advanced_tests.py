#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Advanced Test Cases for HW_Mgmt_Logger
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
import gc
from pathlib import Path
from unittest.mock import patch, MagicMock, call

# Add the library path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', 'usr', 'usr', 'bin'))

try:
    from hw_management_lib import HW_Mgmt_Logger
except ImportError as e:
    print(f"[ERROR] Failed to import HW_Mgmt_Logger: {e}")
    sys.exit(1)


class AdvancedHWMgmtLoggerTests(unittest.TestCase):
    """Advanced test cases for edge scenarios and performance testing"""

    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self._test_params = {}

        # Clean sensor_read_error before each test
        if hasattr(sys.modules.get('hw_management_lib', None), 'sensor_read_error'):
            sys.modules['hw_management_lib'].sensor_read_error = None

    def tearDown(self):
        """Clean up test environment"""
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir, ignore_errors=True)
        # Force garbage collection
        gc.collect()

    def _store_test_params(self, **kwargs):
        """Store test parameters for error reporting"""
        self._test_params = kwargs

    def test_multiple_logger_instances(self):
        """Test multiple logger instances don't interfere with each other"""
        params = {'num_instances': 5}
        self._store_test_params(**params)

        loggers = []
        log_files = []

        try:
            # Create multiple loggers
            for i in range(5):
                log_file = os.path.join(self.temp_dir, f"logger_{i}.log")
                log_files.append(log_file)

                logger = HW_Mgmt_Logger(
                    ident=f"test_logger_{i}",
                    log_file=log_file,
                    log_level=HW_Mgmt_Logger.INFO
                )
                loggers.append(logger)

            # Each logger logs different messages
            for i, logger in enumerate(loggers):
                logger.info(f"Message from logger {i}")

            # Cleanup all loggers
            for logger in loggers:
                logger.stop()

            # Verify each log file has correct content
            for i, log_file in enumerate(log_files):
                with open(log_file, 'r') as f:
                    content = f.read()
                    self.assertIn(f"Message from logger {i}", content)
                    # Ensure no cross-contamination
                    for j in range(5):
                        if j != i:
                            self.assertNotIn(f"Message from logger {j}", content)

        finally:
            # Ensure cleanup even if test fails
            for logger in loggers:
                try:
                    logger.stop()
                except BaseException:
                    pass

    def test_logger_reinitialization(self):
        """Test logger reinitialization and parameter changes"""
        log_file = os.path.join(self.temp_dir, "reinit_test.log")
        params = {'log_file': log_file}
        self._store_test_params(**params)

        # Initial logger
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.WARNING)
        logger.info("Info message 1")  # Should be filtered
        logger.warning("Warning message 1")  # Should be logged
        logger.stop()

        # Reinitialize with different level
        logger.set_param(log_level=HW_Mgmt_Logger.INFO, log_file=log_file)
        logger.info("Info message 2")  # Should be logged now
        logger.warning("Warning message 2")  # Should be logged
        logger.stop()

        # Verify content
        with open(log_file, 'r') as f:
            content = f.read()
            self.assertNotIn("Info message 1", content)
            self.assertIn("Warning message 1", content)
            self.assertIn("Info message 2", content)
            self.assertIn("Warning message 2", content)

    def test_high_frequency_logging(self):
        """Test high-frequency logging performance"""
        log_file = os.path.join(self.temp_dir, "high_freq.log")
        message_count = 1000
        params = {'message_count': message_count, 'log_file': log_file}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        start_time = time.time()

        # Log many messages quickly
        for i in range(message_count):
            logger.info(f"High frequency message {i}")

        end_time = time.time()
        logger.stop()

        # Verify performance and correctness
        duration = end_time - start_time
        messages_per_second = message_count / duration

        print(f"HIGH FREQUENCY TEST: {messages_per_second:.1f} messages/second")

        # Verify all messages were logged
        with open(log_file, 'r') as f:
            content = f.read()
            logged_count = content.count("High frequency message")
            self.assertEqual(logged_count, message_count)

    def test_complex_repeat_scenarios(self):
        """Test complex message repeat scenarios"""
        log_file = os.path.join(self.temp_dir, "complex_repeat.log")
        params = {'log_file': log_file}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.DEBUG)

        # Scenario 1: Multiple overlapping repeats
        for i in range(5):
            logger.info("Overlapping message A", id="repeat_a", log_repeat=2)
            logger.info("Overlapping message B", id="repeat_b", log_repeat=3)

        # Scenario 2: Nested repeat patterns
        logger.info("Outer message", id="outer", log_repeat=2)
        for i in range(4):
            logger.info("Inner message", id="inner", log_repeat=1)
        logger.info(None, id="inner")  # Finalize inner
        logger.info(None, id="outer")  # Finalize outer

        # Scenario 3: Interleaved different levels
        for i in range(3):
            logger.debug("Debug repeat", id="debug_repeat", log_repeat=1)
            logger.error("Error repeat", id="error_repeat", log_repeat=2)

        logger.stop()

        # Verify complex patterns work correctly
        with open(log_file, 'r') as f:
            content = f.read()
            self.assertIn("message repeated", content)
            self.assertIn("and stopped", content)

    def test_memory_usage_patterns(self):
        """Test memory usage with large hash tables"""
        log_file = os.path.join(self.temp_dir, "memory_test.log")
        params = {'log_file': log_file}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        # Create many unique IDs to test hash growth
        unique_ids = []
        for i in range(150):  # Exceed MAX_MSG_HASH_SIZE (100)
            unique_id = f"memory_test_{i}"
            unique_ids.append(unique_id)
            logger.info(f"Memory test message {i}", id=unique_id, repeat=5)

        # This should trigger garbage collection
        self.assertLessEqual(len(logger.log_hash), logger.MAX_MSG_HASH_SIZE)

        logger.stop()

    def test_concurrent_syslog_and_file(self):
        """Test concurrent syslog and file logging"""
        log_file = os.path.join(self.temp_dir, "concurrent.log")
        params = {'log_file': log_file}
        self._store_test_params(**params)

        with patch('syslog.openlog') as mock_openlog, \
                patch('syslog.syslog') as mock_syslog, \
                patch('syslog.closelog') as mock_closelog:

            # Create logger with both file and syslog
            logger = HW_Mgmt_Logger(
                log_file=log_file,
                log_level=HW_Mgmt_Logger.DEBUG,
                syslog_level=HW_Mgmt_Logger.INFO
            )

            # Test messages at different levels
            logger.debug("Debug message")    # File only
            logger.info("Info message")      # File + Syslog
            logger.error("Error message")    # File + Syslog
            logger.critical("Critical message")  # File + Syslog (always)

            logger.stop()

            # Verify file logging
            with open(log_file, 'r') as f:
                content = f.read()
                self.assertIn("Debug message", content)
                self.assertIn("Info message", content)
                self.assertIn("Error message", content)
                self.assertIn("Critical message", content)

            # Verify syslog calls (should not include debug)
            syslog_calls = mock_syslog.call_args_list
            syslog_messages = [str(call) for call in syslog_calls]

            # Check that appropriate messages went to syslog
            self.assertTrue(any("Info message" in msg for msg in syslog_messages))
            self.assertTrue(any("Error message" in msg for msg in syslog_messages))
            self.assertTrue(any("Critical message" in msg for msg in syslog_messages))

    def test_unicode_edge_cases(self):
        """Test various Unicode and encoding edge cases"""
        log_file = os.path.join(self.temp_dir, "unicode_test.log")
        params = {'log_file': log_file}
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        # Test various Unicode categories
        test_messages = [
            "ASCII: Hello World",
            "Unicode: Rocket symbol",
            "Cyrillic: Privet mir",
            "Control chars: \t\n\r",
            "Special: \u0000\u001F\u007F\u0080\u009F"  # Control characters
        ]

        for msg in test_messages:
            logger.info(msg)

        logger.stop()

        # Verify all messages were handled
        with open(log_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            # Most messages should be present (some control chars may be handled)
            self.assertIn("ASCII: Hello World", content)
            self.assertIn("Unicode: Rocket symbol", content)

    def test_error_recovery(self):
        """Test error recovery scenarios"""
        params = {}
        self._store_test_params(**params)

        # Test with invalid syslog configuration
        with patch('syslog.openlog', side_effect=OSError("Syslog not available")):
            logger = HW_Mgmt_Logger(syslog_level=HW_Mgmt_Logger.INFO)

            # Should still work for other operations
            self.assertIsNone(logger._syslog)

            # File logging should still work
            log_file = os.path.join(self.temp_dir, "recovery_test.log")
            logger.set_param(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
            logger.info("Recovery test message")
            logger.stop()

            with open(log_file, 'r') as f:
                content = f.read()
                self.assertIn("Recovery test message", content)

    def test_destructor_safety(self):
        """Test destructor behavior and safety"""
        log_file = os.path.join(self.temp_dir, "destructor_test.log")
        params = {'log_file': log_file}
        self._store_test_params(**params)

        # Create logger and let it go out of scope
        def create_and_destroy_logger():
            logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
            logger.info("Destructor test message")
            # Don't call stop() - let destructor handle it

        create_and_destroy_logger()

        # Force garbage collection to trigger destructors
        gc.collect()

        # Verify the message was logged
        with open(log_file, 'r') as f:
            content = f.read()
            self.assertIn("Destructor test message", content)


class PerformanceTests(unittest.TestCase):
    """Performance and benchmark tests"""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self._test_params = {}

    def tearDown(self):
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _store_test_params(self, **kwargs):
        self._test_params = kwargs

    def test_threading_performance(self):
        """Test performance under high concurrent load"""
        log_file = os.path.join(self.temp_dir, "threading_perf.log")
        thread_count = 10
        messages_per_thread = 100
        params = {
            'thread_count': thread_count,
            'messages_per_thread': messages_per_thread,
            'log_file': log_file
        }
        self._store_test_params(**params)

        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        def worker(thread_id):
            for i in range(messages_per_thread):
                logger.info(f"Thread {thread_id} message {i}")

        start_time = time.time()

        # Start all threads
        threads = []
        for i in range(thread_count):
            thread = threading.Thread(target=worker, args=(i,))
            threads.append(thread)
            thread.start()

        # Wait for completion
        for thread in threads:
            thread.join()

        end_time = time.time()
        logger.stop()

        duration = end_time - start_time
        total_messages = thread_count * messages_per_thread
        throughput = total_messages / duration

        print(f"THREADING PERFORMANCE: {throughput:.1f} messages/second with {thread_count} threads")

        # Verify all messages were logged
        with open(log_file, 'r') as f:
            content = f.read()
            logged_count = content.count("Thread")
            self.assertEqual(logged_count, total_messages)


if __name__ == '__main__':
    unittest.main(verbosity=2)
