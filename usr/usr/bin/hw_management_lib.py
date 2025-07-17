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

import os
import sys
import logging
from logging.handlers import RotatingFileHandler, SysLogHandler
from threading import Timer
import time

# ----------------------------------------------------------------------


def str2bool(val):
    """
    @summary:
        Convert input val value (y/n, true/false, 1/0, y/n) to bool
    @param val: input value.
    @return: True or False
    """
    if isinstance(val, bool):
        return val
    elif isinstance(val, int):
        return bool(val)
    elif val.lower() in ("yes", "true", "t", "y", "1"):
        return True
    elif val.lower() in ("no", "false", "f", "n", "0"):
        return False
    return None


# ----------------------------------------------------------------------
def current_milli_time():
    """
    @summary:
        get current time in milliseconds
    @return: int value time in milliseconds
    """
    return round(time.clock_gettime(1) * 1000)


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

    Level       When to Use

    DEBUG   For detailed diagnostic info. Only useful for developers
                during debugging.

    INFO    For normal runtime events. High-level messages showing the
                system is working as expected.

    NOTICE  For important but non-critical events. More significant than `INFO`,
                but not a problem.

    WARNING For unexpected events that didn't cause a failure, but might.

    ERROR   For serious issues that caused part of the system to fail.
    """

    def __init__(self, use_syslog=False, log_file=None, verbosity=20):
        """
        @summary:
            The following class provide functionality to log messages.
        @param use_syslog: log also to syslog. Applicable arg
            value 1-enable/0-disable
        @param log_file: log to user specified file. Set '' if no log needed
        """
        logging.basicConfig(level=logging.DEBUG)
        logging.addLevelName(logging.INFO + 5, "NOTICE")
        SysLogHandler.priority_map["NOTICE"] = "notice"

        self.logger = logging.getLogger("main")
        self.logger.setLevel(logging.DEBUG)
        self.logger.propagate = False
        self.logger_fh = None
        self.logger_emit = True
        self.syslog_hash = {}    # hash array of the messages which was logged to syslog

        self.set_param(use_syslog, log_file, verbosity)
        for level in ("debug", "info", "notice", "warn", "error", "critical"):
            setattr(self, level, self._make_log_level(level))

    def _make_log_level(self, level):
        level_map = {
            "debug": logging.DEBUG,
            "info": logging.INFO,
            "notice": logging.INFO + 5,
            "warn": logging.WARNING,
            "error": logging.ERROR,
            "critical": logging.CRITICAL,
        }

        def log_method(msg, id=None, repeat=0):
            self.log_handler(level_map[level], msg, id, repeat)
        return log_method

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
                syslog_handler.setLevel(logging.INFO)

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
        self.syslog_hash = {}

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

    def log_handler(self, level, msg="", id=None, repeat=0):
        """
        @summary:
            Logs message to both tc_log and syslog.
                1. The message is always logged to tc_log.
                2. Repeated messages can be "collapsed" in syslog:
                - When a repeated message is detected, it will shown only "repeat" times.
                - When the condition clears, a final message with a "clear" marker is logged.
                This helps reduce syslog clutter from frequent, identical messages.
        @param msg: message text
        @param id: unique identifier for the message, used to group and collapse repeats
        @param repeat:  Maximum number of times to log repeated messages to syslog before collapsing.
        """
        # ERROR, WARNING, INFO, NOTICE can be pushed to syslog (optionally)
        if level in [logging.ERROR, logging.WARNING, logging.INFO, logging.INFO + 5]:
            msg, syslog_emit = self.push_syslog(msg, id, repeat)
        # DEBUG can't be pushed to syslog
        elif level == logging.DEBUG:
            syslog_emit = False
        # CRITICAL always push to syslog
        elif level == logging.CRITICAL:
            syslog_emit = True
        else:
            raise ValueError(f"Invalid log level: {level}")

        if msg:
            if not self.logger_emit:
                return
            self.logger_emit = False

            msg_prefix = "@syslog " if syslog_emit else ""
            try:
                self.logger.log(level, msg_prefix + msg)
            except (IOError, OSError, ValueError) as e:
                pass
            finally:
                self.logger_emit = True

    def syslog_hash_garbage_collect(self):
        """
        @summary:
            Remove from syslog_hash all messages older than 60 minutes or if hash is too big
        """
        hash_size = len(self.syslog_hash)
        self.logger.info("syslog_hash_garbage_collect: hash_size={}".format(hash_size))
        if hash_size > 100:
            # some major issue. We never expect to have more than 100 messages in hash.
            self.logger.error("syslog_hash_garbage_collect: to much ({}) messages in hash. Remove all messages.".format(hash_size))
            self.syslog_hash = {}
            return

        if hash_size > 50:
            # some messages was not cleaned up.
            # remove messages older than 60 minutes
            for id_hash in self.syslog_hash:
                if self.syslog_hash[id_hash]["ts"] < current_milli_time() - 60 * 60 * 1000:
                    self.logger.warning("syslog_hash_garbage_collect: remove message \"{}\" from hash".format(self.syslog_hash[id_hash]["msg"]))
                    del self.syslog_hash[id_hash]

    def push_syslog(self, msg="", id=None, repeat=0):
        """
        @param msg: message to save to log
        @param id: id used as key for message that should be "collapsed" into start/stop messages
        @param repeat: max count of the message to display in syslog
        @summary:
                if repeat > 0 then message will be logged to syslog "repeat" times.
                if id == None just print syslog (no start-stop markers)
                if id != None then save to hash, message for log start/stop event
            if repeat is 0 stop syslog emmit
                if id == None stop syslog emmit
                if id != None syslog emmit log with "clear" marker
        @return: message to log, syslog_emit flag
        """

        syslog_emit = False
        id_hash = hash(id) if id else None

        if repeat > 0:
            syslog_emit = True
            if id_hash:
                if id_hash in self.syslog_hash:
                    self.syslog_hash[id_hash]["count"] += 1
                    self.syslog_hash[id_hash]["msg"] = msg
                else:
                    self.syslog_hash_garbage_collect()
                    self.syslog_hash[id_hash] = {"count": 1, "msg": msg, "ts": current_milli_time()}

                self.syslog_hash[id_hash]["ts"] = current_milli_time()

                if self.syslog_hash[id_hash]["count"] > 1:
                    msg = msg + " (repeated {} times)".format(self.syslog_hash[id_hash]["count"])

                if self.syslog_hash[id_hash]["count"] > repeat:
                    syslog_emit = False
        else:
            # message in hash - print to syslog last time
            if id_hash in self.syslog_hash:
                # new message not defined - use message from hash
                if not msg:
                    msg = self.syslog_hash[id_hash]["msg"]
                    # add "finalization" mark to message
                    if self.syslog_hash[id_hash]["count"]:
                        msg = msg + " (clear)"

                # remove message from hash
                del self.syslog_hash[id_hash]
                syslog_emit = True
        return msg, syslog_emit


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
