# Copyright (c) 2019-2024 NVIDIA CORPORATION & AFFILIATES.
# Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#############################################################################
# Nvidia
#
# Module contains an implementation of RedFish client which provides
# firmware upgrade and sensor retrieval functionality
#
#############################################################################

import os
import sys
import logging
from logging.handlers import RotatingFileHandler, SysLogHandler
from threading import Timer

# ----------------------------------------------------------------------


class SyslogFilter(logging.Filter):

    def filter(self, record):
        res = False
        if record.getMessage().startswith("@syslog "):
            record.msg = record.getMessage().replace("@syslog ", "")
            res = True
        return res


class tc_logger(object):
    """
    Logger class provide functionality to log messages.
    It can log to several places in parallel
    """

    def __init__(self, use_syslog=False, log_file=None, verbosity=20):
        """
        @summary:
            The following class provide functionality to log messages.
        @param use_syslog: log also to syslog. Applicable arg
            value 1-enable/0-disable
        @param log_file: log to user specified file. Set '' if no log needed
        """
        self.logger = None
        logging.basicConfig(level=logging.DEBUG)
        logging.addLevelName(logging.INFO + 5, "NOTICE")
        SysLogHandler.priority_map["NOTICE"] = "notice"
        self.logger = logging.getLogger("main")
        self.logger.setLevel(logging.DEBUG)
        self.logger.propagate = False
        self.logger_fh = None
        self.logger_emit = True

        self.set_param(use_syslog, log_file, verbosity)

    def set_param(self, use_syslog=None, log_file=None, verbosity=20):
        """
        @summary:
            Set logger parameters. Can be called any time
            log provided by /lib/lsb/init-functions always turned on
        @param use_syslog: log also to syslog. Applicable arg
            value 1-enable/0-disable
        @param log_file: log to user specified file. Set None if no log needed
        """
        formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")

        if log_file:
            if any(std_file in log_file for std_file in ["stdout", "stderr"]):
                self.logger_fh = logging.StreamHandler()
            else:
                self.logger_fh = RotatingFileHandler(log_file, maxBytes=(10 * 1024) * 1024, backupCount=3)

            self.logger_fh.setFormatter(formatter)
            self.logger_fh.setLevel(verbosity)
            self.logger.addHandler(self.logger_fh)

        if use_syslog:
            if sys.platform == "darwin":
                address = "/var/run/syslog"
            else:
                if os.path.exists("/dev/log"):
                    address = "/dev/log"
                else:
                    address = ("localhost", 514)
            facility = SysLogHandler.LOG_SYSLOG
            try:
                syslog_handler = SysLogHandler(address=address, facility=facility)
                syslog_handler.setLevel(logging.INFO + 5)

                syslog_handler.setFormatter(logging.Formatter("hw-management-tc: %(levelname)s - %(message)s"))
                syslog_handler.addFilter(SyslogFilter("syslog"))
                self.logger.addHandler(syslog_handler)
            except IOError as err:
                print("Can't init syslog {} address {}".format(str(err), address))

    def stop(self):
        """
        @summary:
            Cleanup and Stop logger
        """
        logging.shutdown()
        handler_list = self.logger.handlers[:]
        for handler in handler_list:
            handler.close()
            self.logger.removeHandler(handler)
        self.logger_emit = False

    def close_tc_log_handler(self):
        if self.logger_fh:
            self.logger_fh.flush()
            self.logger_fh.close()
            self.logger.removeHandler(self.logger_fh)

    def set_loglevel(self, verbosity):
        """
        @summary:
            Set log level for logging in file
        @param verbosity: logging level 0 .. 80
        """
        if self.logger_fh:
            self.logger_fh.setLevel(verbosity)

    def debug(self, msg="", syslog=0):
        """
        @summary:
            Log "debug" message.
        @param msg: message to save to log
        """
        if not self.logger_emit:
            return
        self.logger_emit = False

        msg_prefix = ""
        if syslog:
            msg_prefix = "@syslog "
        try:
            if self.logger:
                self.logger.debug(msg_prefix + msg)
        except BaseException:
            pass
        self.logger_emit = True

    def info(self, msg="", syslog=0):
        """
        @summary:
            Log "info" message.
        @param msg: message to save to log
        """
        if not self.logger_emit:
            return
        self.logger_emit = False

        msg_prefix = ""
        if syslog:
            msg_prefix = "@syslog "
        try:
            if self.logger:
                self.logger.info(msg_prefix + msg)
        except BaseException:
            pass
        self.logger_emit = True

    def notice(self, msg="", syslog=0):
        """
        @summary:
            Log "notice" message.
        @param msg: message to save to log
        """
        if not self.logger_emit:
            return
        self.logger_emit = False

        msg_prefix = ""
        if syslog:
            msg_prefix = "@syslog "
        try:
            if self.logger:
                self.logger.log(logging.INFO + 5, msg_prefix + msg)
        except BaseException:
            pass
        self.logger_emit = True

    def warn(self, msg="", syslog=0):
        """
        @summary:
            Log "warn" message.
        @param msg: message to save to log
        """
        if not self.logger_emit:
            return
        self.logger_emit = False

        msg_prefix = ""
        if syslog:
            msg_prefix = "@syslog "
        try:
            if self.logger:
                self.logger.warning(msg_prefix + msg)
        except BaseException:
            pass
        self.logger_emit = True

    def error(self, msg="", syslog=0):
        """
        @summary:
            Log "error" message.
        @param msg: message to save to log
        """
        if not self.logger_emit:
            return
        self.logger_emit = False

        msg_prefix = ""
        if syslog:
            msg_prefix = "@syslog "
        try:
            if self.logger:
                self.logger.error(msg_prefix + msg)
        except BaseException:
            pass
        self.logger_emit = True


# ----------------------------------------------------------------------
class RepeatedTimer(object):
    """
     @summary:
         Provide repeat timer service. Can start provided function with selected  interval
    """

    def __init__(self, interval, function):
        """
        @summary:
            Create timer object which run function in separate thread
            Automatically start timer after init
        @param interval: Interval in seconds to run function
        @param function: function name to run
        """
        self._timer = None
        self.interval = interval
        self.function = function

        self.is_running = False
        self.start()

    def _run(self):
        """
        @summary:
            wrapper to run function
        """
        self.is_running = False
        self.start()
        self.function()

    def start(self, immediately_run=False):
        """
        @summary:
            Start selected timer (if it not running)
        """
        if immediately_run:
            self.function()
            self.stop()

        if not self.is_running:
            self._timer = Timer(self.interval, self._run)
            self._timer.start()
            self.is_running = True

    def stop(self):
        """
        @summary:
            Stop selected timer (if it started before
        """
        self._timer.cancel()
        self.is_running = False
