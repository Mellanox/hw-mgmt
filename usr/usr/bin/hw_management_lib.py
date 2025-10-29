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
import logging
from logging.handlers import RotatingFileHandler
import syslog
import threading
import time


# ----------------------------------------------------------------------
def current_milli_time():
    """
    @summary:
        get current time in milliseconds
    @return: int value time in milliseconds
    """
    return round(time.clock_gettime(time.CLOCK_MONOTONIC) * 1000)


class HW_Mgmt_Logger:
    """
    Hardware Management Logger - provides robust logging to files and syslog.

    Features:
    - Dual destination logging (file + syslog) with independent configuration
    - Thread-safe operation with multiple logger instances
    - Message repeat collapsing to reduce log spam
    - Automatic log rotation and cleanup
    - Unicode-safe message handling

    Syslog Behavior:
    - CRITICAL messages always go to syslog (regardless of priority threshold)
    - ERROR, WARNING, INFO, NOTICE go to syslog if they meet priority threshold
    - DEBUG messages are never sent to syslog

    Log Levels:
    DEBUG   - Detailed diagnostic info for developers during debugging
    INFO    - Normal runtime events showing system is working as expected
    NOTICE  - Important but non-critical events (more significant than INFO)
    WARNING - Unexpected events that didn't cause failure but might
    ERROR   - Serious issues that caused part of the system to fail
    CRITICAL- Critical issues that caused the system to fail
    """
    # Pre-computed constants for performance
    CRITICAL = logging.CRITICAL
    FATAL = CRITICAL
    ERROR = logging.ERROR
    NOTICE = logging.INFO + 5
    WARNING = logging.WARNING
    WARN = WARNING
    INFO = logging.INFO
    DEBUG = logging.DEBUG
    NOTSET = logging.NOTSET

    LOG_FACILITY_DAEMON = syslog.LOG_DAEMON
    LOG_FACILITY_USER = syslog.LOG_USER
    LOG_OPTION_NDELAY = syslog.LOG_NDELAY
    LOG_OPTION_PID = syslog.LOG_PID
    DEFAULT_LOG_FACILITY = syslog.LOG_USER
    DEFAULT_LOG_OPTION = syslog.LOG_NDELAY

    # File rotation settings
    MAX_LOG_FILE_SIZE = 10485760  # 10 * 1024 * 1024 pre-computed
    MAX_LOG_FILE_BACKUP_COUNT = 3

    # Hash management constants
    MAX_MSG_HASH_SIZE = 100
    MAX_MSG_TIMEOUT_HASH_SIZE = 50
    MSG_HASH_TIMEOUT = 3600000  # 60 * 60 * 1000 pre-computed

    LOG_REPEAT_UNLIMITED = 4294836225

    def __init__(self, ident=None, log_file=None, log_level=INFO, syslog_level=CRITICAL, log_repeat=LOG_REPEAT_UNLIMITED, syslog_repeat=LOG_REPEAT_UNLIMITED):
        """
        Initialize the Hardware Management Logger.

        @param ident: Identifier for log entries (default: script name)
        @param log_file: Path to log file, "stdout", "stderr", or None for no file logging
        @param log_level: Minimum level for file logging (DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL)
        @param syslog_level: Minimum level for syslog logging, or None/0 to disable syslog
        @param log_repeat: Default max repeat count for file messages (0 = unlimited)
        @param syslog_repeat: Default max repeat count for syslog messages (0 = unlimited)
        """
        # Configure global logging only once (thread-safe)
        if not logging.getLogger().handlers:
            logging.basicConfig(level=self.DEBUG)
        logging.addLevelName(self.NOTICE, "NOTICE")
        logging.addLevelName(self.CRITICAL, "CRITICAL")

        # Create unique logger for this instance to avoid collisions
        logger_name = f"hw_mgmt_{id(self)}"
        self.logger = logging.getLogger(logger_name)
        self.logger.setLevel(self.DEBUG)
        self.logger.propagate = False
        self._suspend = True
        self._syslog = None
        self._syslog_min_log_priority = self.CRITICAL  # Initialize to high level

        # Validate repeat parameters
        if log_repeat < 0:
            raise ValueError(f"log_repeat must be >= 0, got {log_repeat}")
        if syslog_repeat < 0:
            raise ValueError(f"syslog_repeat must be >= 0, got {syslog_repeat}")

        self.log_repeat = log_repeat
        self.syslog_repeat = syslog_repeat
        self.syslog_hash = {}    # hash array of the messages which was logged to syslog
        self.log_hash = {}    # hash array of the messages which was logged to log
        self._lock = threading.Lock()  # Thread safety for all logger operations

        self._set_param(ident, log_file, log_level, syslog_level)
        for level in ("debug", "info", "notice", "warn", "warning", "error", "critical"):
            setattr(self, level, self._make_log_level(level))
        self.resume()

    def __del__(self):
        """
        @summary:
            Cleanup and stop logger
        """
        try:
            self.stop()
        except Exception:
            # Ignore errors during cleanup in destructor to avoid issues during interpreter shutdown
            pass

    def _make_log_level(self, level):
        level_map = {
            "debug": self.DEBUG,
            "info": self.INFO,
            "notice": self.NOTICE,
            "warn": self.WARNING,
            "warning": self.WARNING,
            "error": self.ERROR,
            "critical": self.CRITICAL,
        }

        def log_method(msg, id=None, repeat=None, log_repeat=None):
            """
            Log a message at the specified level.

            @param msg: Message text to log
            @param id: Optional unique identifier for message grouping and repeat collapsing
            @param repeat: Maximum times to repeat message to syslog (0 = unlimited)
            @param log_repeat: Maximum times to repeat message to file (0 = unlimited)
            """
            self.log_handler(level_map[level], msg, id, log_repeat, repeat)
        return log_method

    def init_syslog(self, log_identifier=None, log_facility=DEFAULT_LOG_FACILITY, log_option=DEFAULT_LOG_OPTION, syslog_level=NOTICE):
        """
        @summary:
            Initialize syslog
        @param log_identifier: log identifier
        @param log_facility: log facility
        @param log_option: log option
        @param syslog_level: syslog level
        """
        try:
            self._syslog = syslog

            if log_identifier is None:
                log_identifier = os.path.basename(sys.argv[0])

            # Initialize syslog
            self._syslog.openlog(ident=log_identifier, logoption=log_option, facility=log_facility)

            # Set the default minimum log priority to LOG_PRIORITY_NOTICE
            self._syslog_min_log_priority = syslog_level
        except Exception as e:
            print(f"Warning: Failed to initialize syslog: {e}")
            self._syslog = None
            self._syslog_min_log_priority = self.CRITICAL

    def close_syslog(self):
        """
        @summary:
            Close syslog
        """
        if self._syslog:
            self._syslog.closelog()
            self._syslog = None

    def suspend(self):
        """
        @summary:
            Suspend logging
        """
        self._suspend = True

    def resume(self):
        """
        @summary:
            Resume logging
        """
        self._suspend = False

    def _set_param(self, ident=None, log_file=None, log_level=INFO, syslog_level=CRITICAL):
        """
        @summary:
            Set logger parameters. Can be called any time
            log provided by /lib/lsb/init-functions always turned on
        @param syslog_level: syslog level
            value 1-enable/0-disable
        @param ident: log identifier
        @param log_file: log to user specified file. Set None if no log needed
        """
        if log_file and not isinstance(log_file, str):
            raise ValueError("log_file must be a string")

        # Validate log levels
        valid_levels = [self.DEBUG, self.INFO, self.NOTICE, self.WARNING, self.ERROR, self.CRITICAL, self.NOTSET]
        if log_level not in valid_levels:
            raise ValueError(f"Invalid log_level: {log_level}. Must be one of {valid_levels}")
        if syslog_level and syslog_level not in valid_levels:
            raise ValueError(f"Invalid syslog_level: {syslog_level}. Must be one of {valid_levels}")

        # Check if it's meant to be a stream handler (contains stdout/stderr)
        is_stream_handler = log_file and any(std_file in log_file for std_file in ["stdout", "stderr"])

        if log_file and not is_stream_handler:
            log_dir = os.path.dirname(log_file)
            # Check if log directory is accessible
            if log_dir:
                if not os.path.exists(log_dir):
                    raise PermissionError(f"Log directory does not exist: {log_dir}")
                elif not os.access(log_dir, os.W_OK):
                    raise PermissionError(f"Cannot write to log directory: {log_dir}")

        self.logger.setLevel(log_level)
        formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
        if log_file:
            if any(std_file in log_file for std_file in ["stdout", "stderr"]):
                logger_fh = logging.StreamHandler()
            else:
                logger_fh = RotatingFileHandler(log_file,
                                                maxBytes=self.MAX_LOG_FILE_SIZE,
                                                backupCount=self.MAX_LOG_FILE_BACKUP_COUNT)

            logger_fh.setFormatter(formatter)
            self.logger.addHandler(logger_fh)

        if syslog_level:
            self.init_syslog(log_identifier=ident, syslog_level=syslog_level)

    def syslog_log(self, level, msg):
        """
        @summary:
            Log message to syslog (thread-safe)
        @param level: log level
        @param msg: message
        """
        if not self._syslog:
            return  # Syslog not initialized, skip logging

        # Map logging levels to syslog priority levels and string representations
        # Note: DEBUG is included for completeness but currently not routed to syslog
        level_priority_map = {
            self.DEBUG: (syslog.LOG_DEBUG, "DBG"),
            self.INFO: (syslog.LOG_INFO, "INFO"),
            self.NOTICE: (syslog.LOG_NOTICE, "NOTICE"),
            self.WARNING: (syslog.LOG_WARNING, "WARNING"),
            self.ERROR: (syslog.LOG_ERR, "ERR"),
            self.CRITICAL: (syslog.LOG_CRIT, "CRIT"),
        }

        if level >= self._syslog_min_log_priority and level in level_priority_map:
            try:
                syslog_priority, level_str = level_priority_map[level]
                # Ensure message is safe for syslog (handle encoding issues)
                safe_msg = msg.encode('utf-8', errors='replace').decode('utf-8')
                self._syslog.syslog(syslog_priority, "{}: {}".format(level_str, safe_msg))
            except Exception as e:
                print(f"Warning: Failed to write to syslog: {e}")

    def _close_log_handler(self):
        """
        @summary:
            Close log handlers
        """
        handler_list = self.logger.handlers[:]
        for handler in handler_list:
            try:
                handler.flush()
                handler.close()
            except (ValueError, IOError):
                pass  # Handler might already be closed
            self.logger.removeHandler(handler)

    def stop(self):
        """
        @summary:
            Cleanup and stop logger
        """
        # Clean up only this logger's handlers (don't shutdown all logging)
        self.suspend()

        self.close_syslog()
        self._close_log_handler()
        self.syslog_hash.clear()
        self.log_hash.clear()

    def log_handler(self, level, msg="", id=None, log_repeat=None, syslog_repeat=None):
        """
        @summary:
            Logs message to file and/or syslog based on configuration and level.
                1. File logging: Messages are logged to file if handler is configured and level meets threshold.
                2. Syslog logging:
                   - CRITICAL messages always go to syslog (regardless of priority threshold)
                   - ERROR, WARNING, INFO, NOTICE go to syslog if they meet priority threshold
                   - DEBUG messages are never sent to syslog
                3. Repeated messages can be "collapsed" using the repeat mechanism:
                   - When a repeated message is detected, it will be shown only "repeat" times.
                   - When the condition clears, a final message with a "clear" marker is logged.
                   This helps reduce log clutter from frequent, identical messages.
        @param level: log level (DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL)
        @param msg: message text
        @param id: unique identifier for the message, used to group and collapse repeats
        @param syslog_repeat: Maximum number of times to log repeated messages to syslog before collapsing.
        @param log_repeat: Maximum number of times to log repeated messages to file before collapsing.
        """

        if self._suspend:
            return

        if log_repeat is None:
            log_repeat = self.log_repeat

        if syslog_repeat is None:
            syslog_repeat = self.syslog_repeat

        # Validate and normalize parameters
        valid_levels = [self.DEBUG, self.INFO, self.NOTICE, self.WARNING, self.ERROR, self.CRITICAL]
        if level not in valid_levels:
            raise ValueError(f"Invalid log level: {level}. Must be one of {valid_levels}")

        if log_repeat < 0:
            raise ValueError(f"log_repeat must be >= 0, got {log_repeat}")

        if syslog_repeat < 0:
            raise ValueError(f"syslog_repeat must be >= 0, got {syslog_repeat}")

        # Ensure msg is a string
        if msg is None:
            msg = ""
        elif not isinstance(msg, str):
            msg = str(msg)

        # Handle syslog logging (independent of file logging)
        syslog_emit = False
        syslog_msg = msg  # Initialize syslog_msg
        if self._syslog:
            # CRITICAL always goes to syslog (regardless of priority threshold)
            if level == self.CRITICAL:
                syslog_msg = msg
                syslog_emit = True
            # Other levels only if they meet priority threshold
            elif level >= self._syslog_min_log_priority:
                if level in [self.ERROR, self.WARNING, self.INFO, self.NOTICE]:
                    syslog_msg, syslog_emit = self._push_syslog(msg, id, syslog_repeat)

        # Handle file logging (independent of syslog logging)
        # Thread-safe handler access
        log_emit = False
        log_msg = msg  # Initialize log_msg

        if level >= self.logger.level:
            log_msg, log_emit = self._push_log(msg, id, log_repeat)

        # Perform actual logging operations (thread-safe)
        try:
            if log_emit:
                self.logger.log(level, log_msg)
            if syslog_emit:
                self.syslog_log(level, syslog_msg)
        except (IOError, OSError, ValueError) as e:
            # Use the appropriate message for error reporting
            error_msg = log_msg if log_msg else syslog_msg
            print("Error logging message: {} - {}".format(error_msg, e))

    def _hash_garbage_collect(self, log_hash):
        """
        @summary:
            Remove from log_hash all messages older than 60 minutes or if hash is too big
        """
        hash_size = len(log_hash)

        # don't clean up if hash size < MAX_MSG_TIMEOUT_HASH_SIZE and < MAX_MSG_HASH_SIZE
        if hash_size > self.MAX_MSG_HASH_SIZE:
            # some major issue. We never expect to have more than MAX_MSG_HASH_SIZE messages in hash.
            # Use print instead of logger to avoid potential circular logging issues
            print("hash_garbage_collect: too many ({}) messages in hash. Remove all messages.".format(hash_size))
            log_hash.clear()  # Clear the actual dictionary, not reassign local variable
            return

        if hash_size > self.MAX_MSG_TIMEOUT_HASH_SIZE:
            # some messages were not cleaned up.
            # remove messages older than MSG_HASH_TIMEOUT seconds
            current_time = current_milli_time()
            cutoff_time = current_time - self.MSG_HASH_TIMEOUT

            # More efficient: build list of keys to delete and batch delete
            expired_keys = [key for key, value in log_hash.items() if value["ts"] < cutoff_time]

            for key in expired_keys:
                # Use print instead of logger to avoid potential circular logging issues
                print("hash_garbage_collect: remove message \"{}\" from hash".format(log_hash[key]["msg"]))
                del log_hash[key]

    def _push_syslog(self, msg="", id=None, repeat=None):
        with self._lock:
            return self._push_log_hash(self.syslog_hash, msg, id, repeat)

    def _push_log(self, msg="", id=None, repeat=None):
        with self._lock:
            return self._push_log_hash(self.log_hash, msg, id, repeat)

    def _push_log_hash(self, log_hash, msg="", id=None, repeat=0):
        """
        @param msg: message to save to log
        @param id: id used as key for message that should be "collapsed" into start/stop messages
        @param repeat: max count of the message to display in log
        @summary:
            if repeat > 0 then message will be logged to log "repeat" times.
            if repeat == 0 then message will not be logged to log

            if id == None just print log (no start-stop markers)
            if id != None then save to hash, message for log start/stop event

            if msg is empty and id is not None then print finalize message to log

            Example:
            LOGGER.notice("Starting hw-management-sync", id=None, repeat=0) - simple log message
            LOGGER.notice("Starting hw-management-sync", id="test", repeat=0) - Same as simple log message. "id" ignored.
            LOGGER.notice("Starting hw-management-sync", id="test", repeat=2) - Message will be logged
            LOGGER.notice("Starting hw-management-sync", id="test", repeat=2) - Message will be logged
            LOGGER.notice("Starting hw-management-sync", id="test", repeat=2) - Message will be ignored
            LOGGER.notice(None, id="test", repeat=0) - Finalize message will be logged for "test" id. "repeat" ignored

        @return: message to log, log_emit flag
        """
        # Handle None message gracefully
        if msg is None:
            msg = ""

        log_emit = False
        # Protect against non-hashable id values
        try:
            id_hash = hash(id) if id else None
        except TypeError:
            # If id is not hashable, treat it as if no id was provided
            id_hash = None

        # msg is not empty
        if msg:
            if repeat == 0:
                log_emit = False
            else:
                if id_hash:
                    if id_hash in log_hash:
                        log_hash[id_hash]["count"] += 1
                    else:
                        self._hash_garbage_collect(log_hash)
                        log_hash[id_hash] = {"count": 1, "msg": msg, "ts": current_milli_time(), "repeat": repeat}
                    log_hash[id_hash]["ts"] = current_milli_time()
                    if log_hash[id_hash]["count"] <= repeat:
                        log_emit = True
                else:
                    log_emit = True
        # msg is empty. print finalize message to log if id_hash is defined
        else:
            if id_hash:
                if id_hash in log_hash:
                    # new message not defined - use message from hash
                    msg = log_hash[id_hash]["msg"]
                    # add "finalization" mark to message
                    msg = "message repeated {} times: [ {} ] and stopped".format(log_hash[id_hash]["count"], msg)
                    # remove message from hash
                    del log_hash[id_hash]
                    log_emit = True

        return msg, log_emit

# ----------------------------------------------------------------------


class RepeatedTimer:
    THREAD_STOP_TIMEOUT = 0.2

    def __init__(self, interval, function, auto_start=True):
        """
        @summary: Create timer object which run function in separate thread
        @param interval: Interval in seconds to run function
        @param function: function name to run
        @param auto_start: If True, automatically start the timer (default). If False, requires manual start().
        """
        self.func = function
        self.interval = interval
        self._stop_event = threading.Event()
        self._thread = None
        if auto_start:
            self.start()

    def __del__(self):
        """
        @summary:
            Ensure timer is stopped during cleanup
        """
        try:
            # Use a timeout to avoid blocking indefinitely during app termination
            self.stop()
        except Exception:
            pass

    def _run(self):
        """
        @summary:
            Run function in separate thread
        """
        while not self._stop_event.is_set():
            start = time.time()
            try:
                self.func()
            except Exception as e:
                print(f"Error in periodic task: {e}")
            # Sleep remaining time if func took less than interval
            elapsed = time.time() - start
            sleep_time = max(0, self.interval - elapsed)
            if self._stop_event.wait(timeout=sleep_time):  # Interruptible sleep
                break  # Event was set, exit immediately

    def start(self, immediately_run=False):
        """
        @summary:
            Start selected timer (if it not running)
        """
        if immediately_run:
            self.func()

        if self._thread and self._thread.is_alive():
            return  # already running

        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        """Stop periodic execution.
        @summary:
            Stop selected timer (if it started before
        @return: True if thread stopped successfully, False if still alive after timeout
        """
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=self.THREAD_STOP_TIMEOUT)
            # Verify thread actually stopped
            if self._thread.is_alive():
                print(f"Warning: RepeatedTimer thread still alive after stop timeout")
                return False
            self._thread = None
        return True

    def is_running(self):
        """
        @summary:
            Return True if the timer is currently running
        """
        return self._thread is not None and self._thread.is_alive()
