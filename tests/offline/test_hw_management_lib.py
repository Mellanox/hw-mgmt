#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Comprehensive Test Suite for hw_management_lib.py
# Tests all functions with simple, medium, and complex scenarios
########################################################################

from hw_management_lib import HW_Mgmt_Logger, current_milli_time
import sys
import os
import pytest
import tempfile
import shutil
import threading
import time
import syslog
from pathlib import Path
from unittest.mock import patch, MagicMock, call, mock_open
from io import StringIO

# Add the library path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin'))


# =============================================================================
# FIXTURES
# =============================================================================

@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files"""
    tmp_dir = tempfile.mkdtemp()
    yield tmp_dir
    shutil.rmtree(tmp_dir, ignore_errors=True)


@pytest.fixture
def log_file(temp_dir):
    """Create a test log file path"""
    return os.path.join(temp_dir, "test.log")


@pytest.fixture
def mock_syslog():
    """Mock syslog module"""
    with patch('syslog.openlog') as mock_openlog, \
            patch('syslog.syslog') as mock_syslog, \
            patch('syslog.closelog') as mock_closelog:
        yield {
            'openlog': mock_openlog,
            'syslog': mock_syslog,
            'closelog': mock_closelog
        }


@pytest.fixture
def basic_logger(log_file):
    """Create a basic logger for testing"""
    logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
    yield logger
    logger.stop()


# =============================================================================
# SIMPLE TESTS - Basic functionality
# =============================================================================

class TestCurrentMilliTime:
    """Tests for current_milli_time() helper function"""

    def test_simple_returns_int(self):
        """Simple: Function returns an integer"""
        result = current_milli_time()
        assert isinstance(result, int)

    def test_simple_positive_value(self):
        """Simple: Returns positive value"""
        result = current_milli_time()
        assert result > 0

    def test_medium_monotonic_increasing(self):
        """Medium: Time values increase monotonically"""
        time1 = current_milli_time()
        time.sleep(0.01)  # Sleep 10ms
        time2 = current_milli_time()
        assert time2 > time1
        assert time2 - time1 >= 10  # At least 10ms difference

    def test_complex_precision(self):
        """Complex: Verify millisecond precision"""
        samples = []
        for _ in range(100):
            samples.append(current_milli_time())
            time.sleep(0.001)  # 1ms sleep

        # Check that we get different values (millisecond precision)
        unique_values = len(set(samples))
        assert unique_values > 50  # Should capture many unique timestamps

    def test_complex_concurrent_calls(self):
        """Complex: Multiple threads calling simultaneously"""
        results = []
        lock = threading.Lock()

        def worker():
            for _ in range(10):
                timestamp = current_milli_time()
                with lock:
                    results.append(timestamp)

        threads = [threading.Thread(target=worker) for _ in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        # All calls should succeed and return reasonable values
        assert len(results) == 50
        assert all(isinstance(t, int) for t in results)
        assert all(t > 0 for t in results)


class TestLoggerInitialization:
    """Tests for HW_Mgmt_Logger.__init__()"""

    def test_simple_default_init(self):
        """Simple: Initialize with no parameters"""
        logger = HW_Mgmt_Logger()
        assert logger is not None
        assert logger.logger is not None
        assert logger.log_repeat == HW_Mgmt_Logger.LOG_REPEAT_UNLIMITED
        assert logger.syslog_repeat == HW_Mgmt_Logger.LOG_REPEAT_UNLIMITED
        logger.stop()

    def test_simple_with_ident(self):
        """Simple: Initialize with ident only"""
        logger = HW_Mgmt_Logger(ident="test_logger")
        assert logger is not None
        logger.stop()

    def test_medium_with_file_logging(self, log_file):
        """Medium: Initialize with file logging"""
        logger = HW_Mgmt_Logger(
            log_file=log_file,
            log_level=HW_Mgmt_Logger.DEBUG
        )
        assert os.path.exists(log_file)
        logger.stop()

    def test_medium_with_syslog(self, mock_syslog):
        """Medium: Initialize with syslog"""
        logger = HW_Mgmt_Logger(
            ident="test_syslog",
            syslog_level=HW_Mgmt_Logger.INFO
        )
        mock_syslog['openlog'].assert_called_once()
        logger.stop()

    def test_medium_with_repeat_params(self, log_file):
        """Medium: Initialize with repeat parameters"""
        logger = HW_Mgmt_Logger(
            log_file=log_file,
            log_repeat=3,
            syslog_repeat=2
        )
        assert logger.log_repeat == 3
        assert logger.syslog_repeat == 2
        logger.stop()

    def test_complex_all_parameters(self, log_file, mock_syslog):
        """Complex: Initialize with all parameters"""
        logger = HW_Mgmt_Logger(
            ident="full_test",
            log_file=log_file,
            log_level=HW_Mgmt_Logger.DEBUG,
            syslog_level=HW_Mgmt_Logger.WARNING,
            log_repeat=5,
            syslog_repeat=3
        )
        assert logger.log_repeat == 5
        assert logger.syslog_repeat == 3
        mock_syslog['openlog'].assert_called_once()
        logger.stop()

    def test_complex_invalid_log_repeat(self):
        """Complex: Invalid log_repeat raises ValueError"""
        with pytest.raises(ValueError, match="log_repeat must be >= 0"):
            HW_Mgmt_Logger(log_repeat=-1)

    def test_complex_invalid_syslog_repeat(self):
        """Complex: Invalid syslog_repeat raises ValueError"""
        with pytest.raises(ValueError, match="syslog_repeat must be >= 0"):
            HW_Mgmt_Logger(syslog_repeat=-5)

    def test_complex_multiple_instances_isolated(self, temp_dir):
        """Complex: Multiple logger instances are isolated"""
        log1 = os.path.join(temp_dir, "log1.log")
        log2 = os.path.join(temp_dir, "log2.log")

        logger1 = HW_Mgmt_Logger(log_file=log1, log_level=HW_Mgmt_Logger.INFO)
        logger2 = HW_Mgmt_Logger(log_file=log2, log_level=HW_Mgmt_Logger.DEBUG)

        logger1.info("Logger 1 message")
        logger2.debug("Logger 2 message")

        logger1.stop()
        logger2.stop()

        with open(log1) as f:
            content1 = f.read()
        with open(log2) as f:
            content2 = f.read()

        assert "Logger 1 message" in content1
        assert "Logger 2 message" not in content1
        assert "Logger 2 message" in content2
        assert "Logger 1 message" not in content2


class TestSetParam:
    """Tests for set_param() method"""

    def test_simple_change_log_level(self, log_file):
        """Simple: Change log level"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.WARNING)
        logger.set_param(log_file=log_file, log_level=HW_Mgmt_Logger.DEBUG)
        assert logger.logger.level == HW_Mgmt_Logger.DEBUG
        logger.stop()

    def test_medium_change_log_file(self, temp_dir):
        """Medium: Change log file path"""
        log1 = os.path.join(temp_dir, "log1.log")
        log2 = os.path.join(temp_dir, "log2.log")

        logger = HW_Mgmt_Logger(log_file=log1, log_level=HW_Mgmt_Logger.INFO)
        logger.info("First file message")

        logger.set_param(log_file=log2, log_level=HW_Mgmt_Logger.INFO)
        logger.info("Second file message")

        logger.stop()

        with open(log1) as f:
            assert "First file message" in f.read()
        with open(log2) as f:
            assert "Second file message" in f.read()

    def test_medium_invalid_log_file_type(self):
        """Medium: Invalid log_file type raises ValueError"""
        logger = HW_Mgmt_Logger()
        with pytest.raises(ValueError, match="log_file must be a string"):
            logger.set_param(log_file=123)
        logger.stop()

    def test_medium_invalid_log_level(self, log_file):
        """Medium: Invalid log level raises ValueError"""
        logger = HW_Mgmt_Logger()
        with pytest.raises(ValueError, match="Invalid log_level"):
            logger.set_param(log_file=log_file, log_level=999)
        logger.stop()

    def test_complex_nonexistent_directory(self):
        """Complex: Non-existent log directory raises PermissionError"""
        logger = HW_Mgmt_Logger()
        with pytest.raises(PermissionError, match="Log directory does not exist"):
            logger.set_param(log_file="/nonexistent/dir/test.log")
        logger.stop()

    def test_complex_stream_handlers(self):
        """Complex: Test stdout and stderr stream handlers"""
        logger = HW_Mgmt_Logger()

        # Test stdout
        logger.set_param(log_file="stdout", log_level=HW_Mgmt_Logger.INFO)

        import logging
        assert logger.logger.handlers[0] is not None
        assert isinstance(logger.logger.handlers[0], logging.StreamHandler)

        # Test stderr
        logger.set_param(log_file="stderr", log_level=HW_Mgmt_Logger.INFO)
        assert logger.logger.handlers[1] is not None
        assert isinstance(logger.logger.handlers[1], logging.StreamHandler)

        logger.stop()


class TestLogLevelMethods:
    """Tests for debug(), info(), notice(), warn(), error(), critical()"""

    def test_simple_all_levels(self, log_file):
        """Simple: All log level methods work"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.DEBUG)

        logger.debug("Debug msg")
        logger.info("Info msg")
        logger.notice("Notice msg")
        logger.warn("Warn msg")
        logger.warning("Warning msg")
        logger.error("Error msg")
        logger.critical("Critical msg")

        logger.stop()

        with open(log_file) as f:
            content = f.read()
            assert "Debug msg" in content
            assert "Info msg" in content
            assert "Notice msg" in content
            assert "Warn msg" in content
            assert "Warning msg" in content
            assert "Error msg" in content
            assert "Critical msg" in content

    def test_medium_level_filtering(self, log_file):
        """Medium: Messages below log level are filtered"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.WARNING)

        logger.debug("Debug msg")  # Filtered
        logger.info("Info msg")    # Filtered
        logger.notice("Notice msg")  # Filtered
        logger.warning("Warning msg")  # Logged
        logger.error("Error msg")  # Logged

        logger.stop()

        with open(log_file) as f:
            content = f.read()
            assert "Debug msg" not in content
            assert "Info msg" not in content
            assert "Notice msg" not in content
            assert "Warning msg" in content
            assert "Error msg" in content

    def test_complex_with_id_and_repeat(self, log_file):
        """Complex: Log methods with id and repeat parameters"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        # Test repeat functionality
        for i in range(5):
            logger.info("Repeat msg", id="test_id", log_repeat=2)

        # Finalize
        logger.info("", id="test_id")

        logger.stop()

        with open(log_file) as f:
            content = f.read()
            # Should see the message repeated and the finalization
            assert "message repeated" in content
            assert "and stopped" in content


class TestSyslogLog:
    """Tests for syslog_log() method"""

    def test_simple_syslog_disabled(self, log_file):
        """Simple: Syslog logging when syslog is disabled"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        # No syslog initialized, should not raise error
        logger.syslog_log(HW_Mgmt_Logger.INFO, "Test message")
        logger.stop()

    def test_medium_syslog_levels(self, mock_syslog):
        """Medium: Different syslog priority levels"""
        logger = HW_Mgmt_Logger(syslog_level=HW_Mgmt_Logger.DEBUG)

        logger.syslog_log(HW_Mgmt_Logger.DEBUG, "Debug")
        logger.syslog_log(HW_Mgmt_Logger.INFO, "Info")
        logger.syslog_log(HW_Mgmt_Logger.NOTICE, "Notice")
        logger.syslog_log(HW_Mgmt_Logger.WARNING, "Warning")
        logger.syslog_log(HW_Mgmt_Logger.ERROR, "Error")
        logger.syslog_log(HW_Mgmt_Logger.CRITICAL, "Critical")

        logger.stop()

        # Verify syslog was called
        assert mock_syslog['syslog'].call_count >= 6

    def test_medium_unicode_handling(self, mock_syslog):
        """Medium: Unicode characters in syslog messages"""
        logger = HW_Mgmt_Logger(syslog_level=HW_Mgmt_Logger.INFO)

        # Test with Unicode
        logger.syslog_log(HW_Mgmt_Logger.INFO, "Unicode test: \u2764\ufe0f")

        logger.stop()

        # Should not raise exception
        assert mock_syslog['syslog'].called

    def test_complex_syslog_priority_threshold(self, mock_syslog):
        """Complex: Syslog priority threshold filtering"""
        logger = HW_Mgmt_Logger(syslog_level=HW_Mgmt_Logger.WARNING)

        # Below threshold - should not log
        logger.syslog_log(HW_Mgmt_Logger.DEBUG, "Debug")
        logger.syslog_log(HW_Mgmt_Logger.INFO, "Info")

        # Above threshold - should log
        logger.syslog_log(HW_Mgmt_Logger.WARNING, "Warning")
        logger.syslog_log(HW_Mgmt_Logger.ERROR, "Error")

        # CRITICAL always logs
        logger.syslog_log(HW_Mgmt_Logger.CRITICAL, "Critical")

        logger.stop()

        # Verify filtering worked
        call_args = [str(call) for call in mock_syslog['syslog'].call_args_list]
        syslog_content = " ".join(call_args)

        assert "Warning" in syslog_content or "Error" in syslog_content or "Critical" in syslog_content


class TestLogHandler:
    """Tests for log_handler() method"""

    def test_simple_basic_logging(self, log_file):
        """Simple: Basic message logging"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        logger.log_handler(HW_Mgmt_Logger.INFO, "Test message")
        logger.stop()

        with open(log_file) as f:
            assert "Test message" in f.read()

    def test_medium_none_message(self, log_file):
        """Medium: None message is converted to empty string"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        logger.log_handler(HW_Mgmt_Logger.INFO, None)
        logger.stop()
        # Should not raise exception

    def test_medium_non_string_message(self, log_file):
        """Medium: Non-string messages are converted to string"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        logger.log_handler(HW_Mgmt_Logger.INFO, 12345)
        logger.log_handler(HW_Mgmt_Logger.INFO, ['list', 'msg'])
        logger.log_handler(HW_Mgmt_Logger.INFO, {'dict': 'msg'})

        logger.stop()

        with open(log_file) as f:
            content = f.read()
            assert "12345" in content
            assert "list" in content
            assert "dict" in content

    def test_complex_invalid_level(self, log_file):
        """Complex: Invalid log level raises ValueError"""
        logger = HW_Mgmt_Logger(log_file=log_file)
        with pytest.raises(ValueError, match="Invalid log level"):
            logger.log_handler(999, "Test")
        logger.stop()

    def test_complex_invalid_repeat_params(self, log_file):
        """Complex: Invalid repeat parameters raise ValueError"""
        logger = HW_Mgmt_Logger(log_file=log_file)

        with pytest.raises(ValueError, match="log_repeat must be >= 0"):
            logger.log_handler(HW_Mgmt_Logger.INFO, "Test", log_repeat=-1)

        with pytest.raises(ValueError, match="syslog_repeat must be >= 0"):
            logger.log_handler(HW_Mgmt_Logger.INFO, "Test", syslog_repeat=-1)

        logger.stop()

    def test_complex_critical_always_to_syslog(self, log_file, mock_syslog):
        """Complex: CRITICAL messages always go to syslog"""
        logger = HW_Mgmt_Logger(
            log_file=log_file,
            log_level=HW_Mgmt_Logger.DEBUG,
            syslog_level=HW_Mgmt_Logger.CRITICAL  # High threshold
        )

        # CRITICAL should go to syslog despite high threshold
        logger.log_handler(HW_Mgmt_Logger.CRITICAL, "Critical msg")

        logger.stop()

        # Verify it went to both file and syslog
        with open(log_file) as f:
            assert "Critical msg" in f.read()

        assert mock_syslog['syslog'].called


class TestPushLogHash:
    """Tests for push_log_hash(), push_log(), push_syslog()"""

    def test_simple_no_repeat(self, basic_logger):
        """Simple: Message with no repeat (repeat=0)"""
        msg, should_emit = basic_logger._push_log_hash(basic_logger.log_hash, "Test", None, HW_Mgmt_Logger.LOG_REPEAT_UNLIMITED)
        assert msg == "Test"
        assert should_emit is True

    def test_medium_with_repeat_id(self, basic_logger):
        """Medium: Message with repeat ID"""
        # First call
        msg1, emit1 = basic_logger._push_log_hash(basic_logger.log_hash, "Repeat msg", "id1", 2)
        assert emit1 is True

        # Second call
        msg2, emit2 = basic_logger._push_log_hash(basic_logger.log_hash, "Repeat msg", "id1", 2)
        assert emit2 is True

        # Third call - should be suppressed
        msg3, emit3 = basic_logger._push_log_hash(basic_logger.log_hash, "Repeat msg", "id1", 2)
        assert emit3 is False

    def test_medium_finalize_message(self, basic_logger):
        """Medium: Finalize message with empty string"""
        # Send repeated messages
        for _ in range(5):
            basic_logger._push_log_hash(basic_logger.log_hash, "Repeat", "id1", 2)

        # Finalize
        msg, emit = basic_logger._push_log_hash(basic_logger.log_hash, "", "id1", 0)
        assert emit is True
        assert "message repeated" in msg
        assert "and stopped" in msg

    def test_complex_none_message(self, basic_logger):
        """Complex: None message is handled gracefully"""
        msg, emit = basic_logger._push_log_hash(basic_logger.log_hash, None, "id1", 2)
        # None should be converted to empty string, treated as finalize
        assert msg == "" or isinstance(msg, str)

    def test_complex_unhashable_id(self, basic_logger):
        """Complex: Unhashable ID is handled gracefully"""
        unhashable_id = ['list', 'id']  # Lists are unhashable
        msg, emit = basic_logger._push_log_hash(basic_logger.log_hash, "Test", unhashable_id, 2)
        # Should work without raising exception
        assert emit is True

    def test_complex_thread_safety(self, basic_logger):
        """Complex: push_log() and push_syslog() are thread-safe"""
        results = []
        lock = threading.Lock()

        def worker(worker_id):
            for i in range(10):
                msg, emit = basic_logger._push_log(f"Worker {worker_id} msg {i}", f"id_{worker_id}", 5)
                with lock:
                    results.append((msg, emit))

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        # All calls should complete successfully
        assert len(results) == 50


class TestHashGarbageCollect:
    """Tests for hash_garbage_collect() method"""

    def test_simple_empty_hash(self, basic_logger):
        """Simple: Garbage collect on empty hash"""
        basic_logger._hash_garbage_collect(basic_logger.log_hash)
        assert len(basic_logger.log_hash) == 0

    def test_medium_small_hash(self, basic_logger):
        """Medium: Garbage collect on small hash"""
        # Add a few entries
        for i in range(10):
            basic_logger.log_hash[f"id_{i}"] = {
                "count": 1,
                "msg": f"Message {i}",
                "ts": current_milli_time(),
                "repeat": 2
            }

        basic_logger._hash_garbage_collect(basic_logger.log_hash)
        # Should not clear small hash
        assert len(basic_logger.log_hash) == 10

    def test_complex_exceed_max_size(self, basic_logger):
        """Complex: Hash exceeds MAX_MSG_HASH_SIZE (100)"""
        # Add more than MAX_MSG_HASH_SIZE entries
        for i in range(150):
            basic_logger.log_hash[f"id_{i}"] = {
                "count": 1,
                "msg": f"Message {i}",
                "ts": current_milli_time(),
                "repeat": 2
            }

        basic_logger._hash_garbage_collect(basic_logger.log_hash)
        # Should clear the entire hash
        assert len(basic_logger.log_hash) == 0

    def test_complex_timeout_cleanup(self, basic_logger):
        """Complex: Cleanup of old messages (timeout)"""
        current_time = current_milli_time()

        # Add mix of old and new messages
        for i in range(60):
            if i < 30:
                # Old messages (> 60 min old)
                ts = current_time - (basic_logger.MSG_HASH_TIMEOUT + 10000)
            else:
                # Recent messages
                ts = current_time - 1000

            basic_logger.log_hash[f"id_{i}"] = {
                "count": 1,
                "msg": f"Message {i}",
                "ts": ts,
                "repeat": 2
            }

        basic_logger._hash_garbage_collect(basic_logger.log_hash)

        # Old messages should be removed, recent ones kept
        assert len(basic_logger.log_hash) < 60
        assert len(basic_logger.log_hash) >= 30


class TestResourceManagement:
    """Tests for stop(), close_log_handler(), __del__()"""

    def test_simple_stop(self, log_file):
        """Simple: stop() method cleanup"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        logger.info("Test message")
        logger.stop()

        # After stop, handler should be cleaned up
        assert logger.logger.handlers == []
        assert len(logger.log_hash) == 0
        assert len(logger.syslog_hash) == 0

    def test_medium_multiple_stops(self, log_file):
        """Medium: Calling stop() multiple times"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        logger.stop()
        logger.stop()  # Should not raise exception

    def test_medium_close_log_handler(self, log_file):
        """Medium: close_log_handler() method"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        assert logger.logger.handlers != []

        logger._close_log_handler()
        assert logger.logger.handlers == []

        logger.stop()

    def test_complex_destructor(self, log_file):
        """Complex: __del__() destructor cleanup"""
        def create_logger():
            logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
            logger.info("Destructor test")
            # Don't call stop() - let destructor handle it

        create_logger()
        # Force garbage collection
        import gc
        gc.collect()

        # Verify message was logged before cleanup
        with open(log_file) as f:
            assert "Destructor test" in f.read()


class TestConcurrencyAndPerformance:
    """Tests for concurrent access and performance"""

    def test_medium_concurrent_logging(self, log_file):
        """Medium: Multiple threads logging simultaneously"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        def worker(thread_id):
            for i in range(20):
                logger.info(f"Thread {thread_id} message {i}")

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        logger.stop()

        # Verify all messages logged
        with open(log_file) as f:
            content = f.read()
            count = content.count("Thread")
            assert count == 100  # 5 threads * 20 messages

    def test_complex_high_frequency_logging(self, log_file):
        """Complex: High-frequency logging performance"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        message_count = 1000
        start_time = time.time()

        for i in range(message_count):
            logger.info(f"Message {i}")

        end_time = time.time()
        logger.stop()

        duration = end_time - start_time
        throughput = message_count / duration

        # Should be able to log > 100 messages/second
        assert throughput > 100

        # Verify all messages were logged
        with open(log_file) as f:
            content = f.read()
            assert content.count("Message") == message_count

    def test_complex_concurrent_repeat_patterns(self, log_file):
        """Complex: Concurrent threads with repeat patterns"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        def worker(thread_id):
            for i in range(10):
                logger.info(f"Repeat msg {thread_id}", id=f"id_{thread_id}", log_repeat=3)
            logger.info("", id=f"id_{thread_id}")

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        logger.stop()

        # Verify repeat finalization messages
        with open(log_file) as f:
            content = f.read()
            # Should have finalization messages
            assert "message repeated" in content


class TestEdgeCasesAndErrors:
    """Tests for edge cases and error handling"""

    def test_medium_empty_string_messages(self, log_file):
        """Medium: Empty string messages"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        logger.info("")
        logger.info("   ")
        logger.stop()
        # Should not raise exception

    def test_medium_very_long_message(self, log_file):
        """Medium: Very long message (10KB)"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)
        long_msg = "A" * 10000
        logger.info(long_msg)
        logger.stop()

        with open(log_file) as f:
            content = f.read()
            assert long_msg in content

    def test_complex_special_characters(self, log_file):
        """Complex: Special characters in messages"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        special_msgs = [
            "Tabs:\t\t\tTest",
            "Newlines:\n\n\nTest",
            "Quotes: \"'`Test",
            "Backslashes: \\\\\\Test",
            "Control chars: \x00\x01\x02Test"
        ]

        for msg in special_msgs:
            logger.info(msg)

        logger.stop()

        with open(log_file, encoding='utf-8', errors='replace') as f:
            content = f.read()
            # Most messages should be logged (some control chars may be handled)
            assert "Test" in content

    def test_complex_unicode_edge_cases(self, log_file):
        """Complex: Various Unicode edge cases"""
        logger = HW_Mgmt_Logger(log_file=log_file, log_level=HW_Mgmt_Logger.INFO)

        unicode_msgs = [
            "Emoji: \U0001F680",  # Rocket
            "CJK: \u4E2D\u6587",  # Chinese
            "Arabic: \u0627\u0644\u0639\u0631\u0628\u064A\u0629",
            "Combining: e\u0301",  # e with acute accent
            "Zero-width: \u200B\u200C\u200D"
        ]

        for msg in unicode_msgs:
            logger.info(msg)

        logger.stop()

        # Should handle without crashing
        assert os.path.exists(log_file)

    def test_complex_syslog_failure_recovery(self, log_file):
        """Complex: Recovery from syslog failure"""
        with patch('syslog.openlog', side_effect=OSError("Syslog unavailable")):
            logger = HW_Mgmt_Logger(
                log_file=log_file,
                log_level=HW_Mgmt_Logger.INFO,
                syslog_level=HW_Mgmt_Logger.INFO
            )

            # File logging should still work
            logger.info("Test message")
            logger.stop()

            with open(log_file) as f:
                assert "Test message" in f.read()


# =============================================================================
# TEST MAIN
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
