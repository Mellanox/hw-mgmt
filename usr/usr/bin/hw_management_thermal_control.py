#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# Copyright (c) 2022 NVIDIA CORPORATION & AFFILIATES.
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
Created on Oct 01, 2022

Author: Oleksandr Shamray <oleksandrs@nvidia.com>
Version: 2.0.0

Description:
System Thermal control tool

"""


#######################################################################
# Global imports
#######################################################################
import os
import sys
import time
import traceback
import argparse
import subprocess
import signal
import logging
from logging.handlers import RotatingFileHandler, SysLogHandler
import json
import re
from threading import Timer, Event
import pdb

#############################
# Global const
#############################
# pylint: disable=c0301,W0105

VERSION = "2.0.0"


#############################
# Local const
#############################


class CONST(object):
    """
    @summary: hw-management constants
    """

    # string aliases for constants
    LOG_USE_SYSLOG = "use_syslog"
    LOG_FILE = "log_filename"
    HW_MGMT_ROOT = "root_folder"
    GLOBAL_CONFIG = "global_config"
    SYSTEM_CONFIG = "system_config"

    # System config str names
    SYS_CONF_DMIN = "dmin"
    SYS_CONF_FAN_PWM = "psu_fan_pwm_decode"
    SYS_CONF_FAN_PARAM = "fan_trend"
    SYS_CONF_DEV_PARAM = "dev_parameters"
    SYS_CONF_SENSORS_CONF = "sensors_config"

    # *************************
    # Folders definition
    # *************************

    # default hw-management folder
    HW_MGMT_FOLDER_DEF = "/var/run/hw-management"
    # Link to thermal data
    SYSTEM_CONFIG_FILE = "/var/run/hw-management/config/tc_config.json"
    # File which defined current level filename.
    # User can dynamically change loglevel without TC restarting.
    LOG_LEVEL_FILENAME = "config/tc_log_level"
     # File which define TC report period. TC should be restarted to apply changes in this file
    PERIODIC_REPORT_FILE = "config/periodic_report"
    # suspend control file path
    SUSPEND_FILE = "config/suspend"
    # Sensor files for ambiant temperature measurement
    FAN_SENS = "fan_amb"
    PORT_SENS = "port_amb"

    # Fan direction string alias
    # fan dir:
    # 0: port > fan, dir fan to port C2P  Port t change not affect
    # 1: port < fan, dir port to fan P2C  Fan t change not affect
    C2P = "C2P"
    P2C = "P2C"
    DEF_DIR = "P2C"

    UNKNOWN = "Unknown"

    # error types
    UNTRUSTED_ERR = "untrusted"

    # delay before TC start (sec)
    THERMAL_WAIT_FOR_CONFIG = 120

    # Default period for printing TC report (in sec.)
    # Note: set report time to 5 min on release
    PERIODIC_REPORT_TIME = 1 * 20

    # Default sensor configuration if not 0configured other value
    SENSOR_POLL_TIME_DEF = 30
    TEMP_INIT_VAL_DEF = 25
    TEMP_SENSOR_SCALE = 1000.0
    TEMP_MIN_MAX = {"val_min": 35000, "val_max": 70000, "val_crit": 80000}
    RPM_MIN_MAX = {"val_min": 5000, "val_max": 30000}

    # Max/min PWM value - global for all system
    PWM_MIN = 20
    PWM_MAX = 100
    PWM_HYSTERESIS_DEF = 0
    PWM_PSU_MIN = 35

    VALUE_HYSTERESIS_DEF = 0

    # FAN calibration
    # Time for FAN rotation stabilize after change
    FAN_RELAX_TIME = 10

    FAN_SHUTDOWN_ENA = "1"
    FAN_SHUTDOWN_DIS = "0"

    # Cycles for FAN speed calibration at 100%.
    # FAN RPM value will be averaged  by reading by several(FAN_CALIBRATE_CYCLES) readings
    FAN_CALIBRATE_CYCLES = 2

    # PWM smoothing
    DMIN_PWM_STEP_MIN = 2
    # PWM smoothing in time
    PWM_MAX_REDUCTION = 8
    PWM_WORKER_POLL_TIME = 5
    # FAN RPM tolerance in percent
    FAN_RPM_TOLERANCE = 30

    # default system devices
    PSU_COUNT_DEF = 2
    FAN_DRWR_COUNT_DEF = 6
    FAN_TACHO_COUNT_DEF = 6
    MODULE_COUNT_DEF = 16
    GEARBOX_COUNT_DEF = 0

    # Consistent file read  errors for set error state
    SENSOR_FREAD_FAIL_TIMES = 3

    # If more than 1 error, set fans to 100%
    TOTAL_MAX_ERR_COUNT = 1

    # Main TC loop state
    UNCONFIGURED = "UNCONFIGURED"
    STOPPED = "STOPPED"
    RUNNING = "RUNNING"


"""
Default sensor  configuration.
Defined per sensor name. Sensor name can be defined with the regexp mask.
These valued can be overrides with the input sensors configuration file
Options description:

type - device sensor handler type (same as class name)
name - name of sensor. Could be any string
poll_time - polling time in sec for sensor read/error check
val_min/val_max - default values in case sensor don't expose limits in hw-management folder
pwm_max/pwm_min - PWM limits tat sensor can set
input_suffix - second part for sensor input file name
    input_filename = base_file_name + input_suffix
pwm_hyst - hysteresis for PWM value change. PWM value for thermal sensor can be calculated by the formula:
    pwm = pwm_min + ((value - val_min) / (val_max - val_min)) * (pwm_max - pwm_min)
input_smooth_level - soothing level for sensor input value reading. Formula to calculate avg:
    avg_acc -= avg_acc/input_smooth_level
    avg_acc = last_value + avg_acc
    avg = ang_acc / input_smooth_level
"""

SENSOR_DEF_CONFIG = {
    r'psu\d+_fan':      {"type": "psu_fan_sensor",
                         "val_min": 4500, "val_max": 20000, "poll_time": 5,
                         "input_suffix": "_fan1_speed_get", "refresh_attr_period": 1 * 60
                        },
    r'fan\d+':          {"type": "fan_sensor",
                         "val_min": 4500, "val_max": 20000, "poll_time": 5,
                         "refresh_attr_period": 1 * 60
                        },
    r'module\d+':       {"type": "thermal_module_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": 60000, "val_max": 80000, "poll_time": 20,
                         "input_suffix": "_temp_input", "value_hyst": 2, "refresh_attr_period": 1 * 60
                        },
    r'gearbox\d+':      {"type": "thermal_module_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "!105000", "poll_tme": 6,
                         "input_suffix": "_temp_input", "value_hyst": 2, "refresh_attr_period": 30 * 60
                        },
    r'asic':            {"type": "thermal_module_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "!105000", "poll_time": 3,
                         "value_hyst": 2, "input_smooth_level": 1
                        },
    r'(cpu_pack|cpu_core\d+)': {"type": "thermal_sensor",
                                "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "90000", "poll_time": 3,
                                "value_hyst": 5, "input_smooth_level": 3
                               },
    r'sodimm\d_temp':   {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!75000", "val_crit": 85000, "poll_time": 30,
                         "input_suffix": "_input", "input_smooth_level": 2
                        },
    r'pch':             {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 60, "val_min": 50000, "val_max": 85000, "poll_time": 10,
                         "input_suffix": "_temp", "value_hyst": 2, "input_smooth_level": 2, "enable": 0
                        },
    r'comex_amb':       {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 60, "val_min": 45000, "val_max": 85000, "value_hyst": 2, "poll_time": 3, "enable": 0
                        },
    r'sensor_amb':      {"type": "ambiant_thermal_sensor",
                         "pwm_min": 30, "pwm_max": 60, "val_min": 20000, "val_max": 50000, "poll_time": 30,
                         "base_file_name": {CONST.C2P: CONST.PORT_SENS, CONST.P2C: CONST.FAN_SENS}, "value_hyst": 0, "input_smooth_level": 1
                        },
    r'psu\d+_temp':     {"type": "thermal_sensor",
                         "val_min": 45000, "val_max": 85000, "poll_time": 30, "enable": 0
                        },
    r'voltmon\d+_temp': {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 70, "val_min": "!70000", "val_max": "!95000", "poll_time": 3,
                         "input_suffix": "_input"
                        }
}


#############################################
# Default configuration.
#############################################
PSU_PWM_DECODE_DEF = {"0:10": 10,
                      "11:21": 20,
                      "21:30": 30,
                      "31:40": 40,
                      "41:50": 50,
                      "51:60": 60,
                      "61:70": 70,
                      "71:80": 80,
                      "81:90": 90,
                      "91:100": 100}

SYS_FAN_PARAM_DEF = {
        "C2P": {
            "0": {"rpm_min": 3000, "rpm_max": 35000, "slope": 200, "pwm_min": 101, "pwm_max_reduction": 10, "rpm_tolerance": 30},
            "1": {"rpm_min": 3000, "rpm_max": 35000, "slope": 200, "pwm_min": 101, "pwm_max_reduction": 10, "rpm_tolerance": 30}},
        "P2C": {
            "0": {"rpm_min": 3000, "rpm_max": 35000, "slope": 200, "pwm_min": 101, "pwm_max_reduction": 10, "rpm_tolerance": 30},
            "1": {"rpm_min": 3000, "rpm_max": 35000, "slope": 200, "pwm_min": 101, "pwm_max_reduction": 10, "rpm_tolerance": 30}}
    }

TABLE_DEFAULT = {
    CONST.C2P: {
        CONST.UNTRUSTED_ERR: {"-127:120": 60},
        "fan_err": {
            "tacho": {"-127:120": 100},
            "present": {"-127:120": 100},
            "fault": {"-127:120": 100},
            "direction": {"-127:120": 100}
        },
        "psu_err":  {
            "present": {"-127:120": 100},
            "direction": {"-127:120": 100},
            "fault": {"-127:120": 100},
        },
        "sensor_err": {"-127:120": 100}
    },
    CONST.P2C: {
        CONST.UNTRUSTED_ERR: {"-127:120": 60},
        "fan_err": {
            "tacho": {"-127:120": 100},
            "present": {"-127:120": 100},
            "fault": {"-127:120": 100},
            "direction": {"-127:120": 100}
        },
        "psu_err":  {
            "present": {"-127:120": 100},
            "direction": {"-127:120": 100},
            "fault": {"-127:120": 100},
        },
        "sensor_err": {"-127:120": 100}
    }
}


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
    if val.lower() in ("yes", "true", "t", "y", "1"):
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
    return round(time.time() * 1000)


# ----------------------------------------------------------------------
def get_dict_val_by_path(dict_in, path):
    """
    @summary: get value from the multi nested dict_in.
    @param dict_in: input dictionary
    @param path: dict_in keys organized in array.
    @return: Dict vale if keys in path exist or None
    Example:
    dict_in =
    { "level1_1" :
        { "level2_1":
            {"level3_1": "3_1",
            "level3_1": "3_2"},
          "level2_2":
            {"level3_3": "3_3",
            "level3_4": "3_4"},
        }
    }
    path = ["level1_1",level2_2, "level3_4"]

    Will return "3_4"
    """
    for sub_path in path:
        dict_in = dict_in.get(sub_path, None)
        if dict_in is None:
            break
    return dict_in

# ----------------------------------------------------------------------
def g_get_range_val(line, in_value):
    """
    @summary: Searching range which is match to input val and returning corresponding outpur value
    @param line: dict with temp ranges and output values
        Example: {"-127:20":30, "21:25":40 , "26:30":50, "31:120":60},
    @param val: input value
    @return: output value
    """
    for key, val in line.items():
        val_range = key.split(":")
        val_min = int(val_range[0])
        val_max = int(val_range[1])
        if val_min <= in_value <= val_max:
            return val, val_min, val_max
    return None, None, None

# ----------------------------------------------------------------------
def g_get_dmin(thermal_table, temp, path, interpolated=False):
    """
    @summary: Searching PWM value in dmin table based on input temperature
    @param thermal_table: dict with thermal table for the current system
    @param temp:  temperature
    @param patch: array with thermal cause path.
    Example: ["C2P": "trusted"] or ["C2P": "psu_err", "present']
    @param interpolated: Use linear interpolation for soothing PWM jumps
    @return: PWM value
    """
    line = get_dict_val_by_path(thermal_table, path)

    if not line:
        return CONST.PWM_MIN
    # get current range
    dmin, range_min, range_max = g_get_range_val(line, temp)
    if not interpolated:
        return dmin

    # get range of next step
    dmin_next, range_min_next, _ = g_get_range_val(line, range_max + 1)
    # reached maximum range
    if dmin_next is None:
        return dmin

    # calculate smooth step
    start_smooth_change_position = range_min_next - (dmin_next - dmin) / CONST.DMIN_PWM_STEP_MIN
    if temp < start_smooth_change_position:
        return dmin
    elif start_smooth_change_position < range_min:
        step = float(dmin_next - dmin) / float(range_max + 1 - range_min)
    else:
        step = CONST.DMIN_PWM_STEP_MIN
    dmin = dmin_next - ((range_min_next - temp) * step)
    return int(dmin)

# ----------------------------------------------------------------------
def add_missing_to_dict(dict_base, dict_new):
    """
    @summary:  Add value to dict. Perform only if value not exists.
    @param dict: dict to which we want to add
    @param dict_new: new value which we want to add
    @return:  None
    """
    base_keys = dict_base.keys()
    for key in dict_new.keys():
        if key not in base_keys:
            dict_base[key] = dict_new[key]


class Logger(object):
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
        self.logger = logging.getLogger("main")
        self.logger.setLevel(logging.DEBUG)
        self.logger.propagate = False
        self.logger_fh = None

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
            elif sys.platform == "linux":
                address = "/dev/log"
            else:
                address = ("localhost", 514)
            facility = SysLogHandler.LOG_SYSLOG
            syslog_handler = SysLogHandler(address=address, facility=facility)
            syslog_handler.setLevel(logging.INFO + 5)

            syslog_handler.setFormatter(logging.Formatter("hw-management-tc: %(levelname)s - %(message)s"))
            self.logger.addHandler(syslog_handler)

    def set_loglevel(self, verbosity):
        """
        @summary:
            Set log level for logging in file
        @param verbosity: logging level 0 .. 80
        """
        if self.logger_fh:
            self.logger_fh.setLevel(verbosity)

    def debug(self, msg=""):
        """
        @summary:
            Log "debug" message.
        @param msg: message to save to log
        """
        if self.logger:
            self.logger.debug(msg)

    def info(self, msg=""):
        """
        @summary:
            Log "info" message.
        @param msg: message to save to log
        """
        if self.logger:
            self.logger.info(msg)

    def notice(self, msg=""):
        """
        @summary:
            Log "notice" message.
        @param msg: message to save to log
        """
        if self.logger:
            self.logger.log(logging.INFO + 5, msg)

    def warn(self, msg=""):
        """
        @summary:
            Log "warn" message.
        @param msg: message to save to log
        """
        if self.logger:
            self.logger.warning(msg)

    def error(self, msg=""):
        """
        @summary:
            Log "error" message.
        @param msg: message to save to log
        """
        if self.logger:
            self.logger.error(msg)


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


class hw_managemet_file_op(object):
    '''
    @summary:
        The following cases providing wrapper for file operations with hw-management files
    '''
    def __init__(self, config):
        if not config[CONST.HW_MGMT_ROOT]:
            self.root_folder = CONST.HW_MGMT_FOLDER_DEF
        else:
            self.root_folder = config[CONST.HW_MGMT_ROOT]

    # ----------------------------------------------------------------------
    def read_file(self, filename):
        """
        @summary:
            read file from hw-management tree.
        @param filename: file to read from {hw-management-folder}/filename
        @return: file contents
        """
        content = None
        filename = os.path.join(self.root_folder, filename)
        if os.path.isfile(filename):
            with open(filename, "r") as content_file:
                content = content_file.read().rstrip("\n")

        return content

    # ----------------------------------------------------------------------
    def write_file(self, filename, data):
        """
        @summary:
            write data to file in hw-management tree.
        @param filename: file to write  {hw-management-folder}/filename
        @param data: data to write
        """
        filename = os.path.join(self.root_folder, filename)
        with open(filename, "w") as content_file:
            content_file.write(str(data))
            content_file.close()

    # ----------------------------------------------------------------------
    def thermal_read_file(self, filename):
        """
        @summary:
            read file from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @return: file contents
        """
        return self.read_file(os.path.join("thermal", filename))

    # ----------------------------------------------------------------------
    def thermal_read_file_int(self, filename, scale=1):
        """
        @summary:
            read file from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @return: int value from file
        """
        val = self.read_file(os.path.join("thermal", filename))
        val = int(val)/scale
        return int(val)

    # ----------------------------------------------------------------------
    def get_file_val(self, filename, def_val=None, scale=1):
        """
        @summary:
            read file from hw-management tree and multiply it to scale value.
        @param filename: file to read from {hw-management-folder}/filename
        @param def_val: default value if file reading was failed
        @param scale: scale factor multiply with file value
        @return: int value
        """
        val = None
        if self.check_file(filename):
            try:
                val = int(self.read_file(filename)) / scale
            except ValueError:
                pass
        if val is None:
            val = def_val
        return val

    # ----------------------------------------------------------------------
    def thermal_write_file(self, filename, data):
        """
        @summary:
            write data to file in hw-management/thermal tree.
        @param filename: file to write  {hw-management-folder}/thermal/filename
        @param data: data to write
        """
        return self.write_file(os.path.join("thermal", filename), data)

    # ----------------------------------------------------------------------
    def check_file(self, filename):
        """
        @summary:
            check if file exist in file system in hw-management tree.
        @param filename: file to check {hw-management-folder}/filename
        """
        filename = os.path.join(self.root_folder, filename)
        return os.path.isfile(filename)

    # ----------------------------------------------------------------------
    def rm_file(self, filename):
        """
        @summary:
            remove file in hw-management tree.
        @param filename: file to remove {hw-management-folder}/filename
        @param data: data to write
        """
        filename = os.path.join(self.root_folder, filename)
        os.remove(filename)

    # ----------------------------------------------------------------------
    def write_pwm(self, pwm):
        """
        @summary:
            write value tp PWM file.
        @param pwm: PWM value in persent 0..100
        """
        pwm_out = int(pwm * 255 / 100)
        self.write_file("thermal/pwm1", pwm_out)

    # ----------------------------------------------------------------------
    def read_pwm(self):
        """
        @summary:
            read PWM from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @return: int value from file
        """
        pwm = int(self.read_file("thermal/pwm1"))
        pwm_out = int(pwm / 2.55 + 0.5)
        return int(pwm_out)


class system_device(hw_managemet_file_op):
    """
    @summary: base class for system sensors
    """
    def __init__(self, cmd_arg, sys_config, name, logger):
        hw_managemet_file_op.__init__(self, cmd_arg)
        self.log = logger
        self.sensors_config = sys_config[CONST.SYS_CONF_SENSORS_CONF][name]
        self.name = name
        self.type = self.sensors_config["type"]
        self.log.info("Init {0} ({1})".format(self.name, self.type))
        self.log.debug("sensor config:\n{}".format(json.dumps(self.sensors_config, indent = 4)))
        self.base_file_name = self.sensors_config.get("base_file_name", None)
        self.file_input = "{}{}".format(self.base_file_name, self.sensors_config.get("input_suffix", ""))
        self.enable = int(self.sensors_config.get("enable", 1))
        self.input_smooth_level = self.sensors_config.get("input_smooth_level", 1)
        if self.input_smooth_level < 1:
            self.input_smooth_level = 1
        self.poll_time = int(self.sensors_config.get("poll_time", CONST.SENSOR_POLL_TIME_DEF))
        self.update_timestump(1000)
        self.val_min = CONST.TEMP_MIN_MAX["val_min"]
        self.val_max = CONST.TEMP_MIN_MAX["val_max"]
        self.pwm_min = CONST.PWM_MIN
        self.pwm_max = CONST.PWM_MAX
        self.value = CONST.TEMP_INIT_VAL_DEF
        self.value_acc = self.value * self.input_smooth_level
        self.pwm = CONST.PWM_MIN
        self.last_pwm = self.pwm
        self.pwm_hysteresis = int(self.sensors_config.get("pwm_hyst", CONST.PWM_HYSTERESIS_DEF))
        self.state = CONST.STOPPED
        self.err_fread_max = CONST.SENSOR_FREAD_FAIL_TIMES
        self.err_fread_err_counter_dict = {}
        self.refresh_attr_period = 0
        self.refresh_timeout = 0

        self.system_flow_dir = CONST.UNKNOWN
        self.update_pwm_flag = 1
        self.value_last_update = 0
        self.value_last_update_trend = 0
        self.value_trend = 0
        self.value_hyst = int(self.sensors_config.get("value_hyst", CONST.VALUE_HYSTERESIS_DEF))
        self.fault_list = []

    # ----------------------------------------------------------------------
    def start(self):
        """
        @summary: Start device service.
        Reload reloads values which can be changed and preparing to run
        """
        if self.state == CONST.RUNNING:
            return

        if self.check_sensor_blocked():
            return

        self.log.info("Staring {}".format(self.name))
        self.state = CONST.RUNNING
        self.pwm_min = int(self.sensors_config.get("pwm_min", CONST.PWM_MIN))
        self.pwm_max = int(self.sensors_config.get("pwm_max", CONST.PWM_MAX))
        self.refresh_attr_period = self.sensors_config.get("refresh_attr_period", 0)
        if self.refresh_attr_period:
            self.refresh_timeout = current_milli_time() + self.refresh_attr_period * 1000
        else:
            self.refresh_timeout = 0

        self.update_pwm_flag = 1
        self.value_last_update = 0
        self.value_last_update_trend = 0
        self.poll_time = int(self.sensors_config.get("poll_time", CONST.SENSOR_POLL_TIME_DEF))
        self.enable = int(self.sensors_config.get("enable", 1))
        self.value_acc = self.value * self.input_smooth_level
        self.err_fread_err_counter_dict = {}
        self.sensor_configure()
        self.update_timestump(1000)
        self.fault_list = []

    # ----------------------------------------------------------------------
    def stop(self):
        """
        @summary: Stop device service
        """
        if self.state == CONST.STOPPED:
            return

        self.pwm = self.pwm_min
        self.log.info("Stopping {}".format(self.name))
        self.state = CONST.STOPPED

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: function which calling at sensor start and can be used in child class for device
        specific configuration
        """

    # ----------------------------------------------------------------------
    def refresh_attr(self):
        """
        @summary: resresh attributes
        """

    # ----------------------------------------------------------------------
    def update_timestump(self, timeout=0):
        """
        @summary: Updating device timestump based on timeout value
        @param  timeout: Next sensor service time in msec
        """
        if not timeout:
            timeout = self.poll_time * 1000
        self.poll_time_next = current_milli_time() + timeout

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: Prototype for child class. Using for reading and processing sensor input values
        """

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: Prototype for child class. Using for reading and processing sensor errors
        """

    # ----------------------------------------------------------------------
    def handle_reading_file_err(self, filename, reset=False):
        """
        @summary: Handle file errors. Saving read error counter for each file
        @param filename: file name to be handled
        @param  reset: 1- increment errors counter for file, 0 - reset error counter for the file
        """
        if not reset:
            if filename in self.err_fread_err_counter_dict.keys():
                self.err_fread_err_counter_dict[filename] += 1
            else:
                self.err_fread_err_counter_dict[filename] = 1
        else:
            self.err_fread_err_counter_dict[filename] = 0

     # ----------------------------------------------------------------------
    def check_reading_file_err(self):
        """
        @summary: Compare error counter for each file with the threshold
        @return: list of files with errors counters more then max threshold
        """
        err_keys = []
        for key, val in self.err_fread_err_counter_dict.items():
            if val >= self.err_fread_max:
                self.log.error("{}: read file {} errors count {}".format(self.name, key, val))
                err_keys.append(key)
        return err_keys

    # ----------------------------------------------------------------------
    def get_pwm(self):
        """
        @summary: Return pwm value
         calculated for this sensor
        """

        if self.update_pwm_flag != 0:
            self.update_pwm_flag = 0
            self.last_pwm = self.pwm
        return self.last_pwm

    # ----------------------------------------------------------------------
    def get_value(self):
        """
        @summary: Return sensor value. Value type depends from sensor type and can be: Celsius degree, rpm, ...
        """
        return self.value

    # ----------------------------------------------------------------------
    def _update_pwm(self):
        self.update_pwm_flag = 1

    # ----------------------------------------------------------------------
    def update_value(self, value=None):
        """
        @summary: Update sensor value. Value type depends from sensor type and can be: Celsius degree, rpm, ...
        This function implements 2 operations for value update
        1. Smoothing by the avareging value. Formula:
            value_acc -= value_acc / smooth_level
            value_acc += value
            value_val = (value_acc) / input_smooth_level

            input_smooth_level defined in sensor configuration
        2. Add hysteresis for value change
            if value >= old_value + hysteresis then update old_value to the new
            If new change in the same diraction (up or downn) then updating value will be immediatly without hysteresis.

            value_hyst defined in sensor configuration
        """
        old_value = self.value
        # integral filter for soothing temperature change
        self.value_acc -= self.value_acc / self.input_smooth_level
        self.value_acc += value
        self.value = int(round(float(self.value_acc) / self.input_smooth_level))

        if self.value > old_value:
            value_trend = 1
        elif self.value < old_value:
            value_trend = -1
        else:
            value_trend = 0

        if self.value_hyst > 0 and value_trend != 0:
            val_diff = abs(self.value_last_update - self.value)
            if value_trend == self.value_last_update_trend or val_diff > self.value_hyst:
                if (value_trend == 1 and value > self.value_last_update) or (value_trend == -1 and value < self.value_last_update):
                    self._update_pwm()
                    self.value_last_update = self.value
                    self.value_last_update_trend = value_trend
        elif self.value_hyst == 0:
            self._update_pwm()

        return self.value

    # ----------------------------------------------------------------------
    def get_timestump(self):
        """
        @summary:  return time when this sensor should be serviced
        """
        return self.poll_time_next

    # ----------------------------------------------------------------------
    def set_system_flow_dir(self, flow_dir):
        """
        @summary: Set system flow dir info
        @param flow_dir: flow dir which is specified for this system or calculated by algo
        @return: None
        """
        self.system_flow_dir = flow_dir

    # ----------------------------------------------------------------------
    def calculate_pwm_formula(self):
        """
        @summary: Calculate PWM by formula
        PWM = pwm_min + ((value - value_min)/(value_max-value_min)) * (pwm_max - pwm_min)
        @return: PWM value rounded to nearest value
        """
        if self.val_max == self.val_min:
            return self.pwm_min

        pwm = self.pwm_min + (float(self.value - self.val_min) / (self.val_max - self.val_min)) * (self.pwm_max - self.pwm_min)
        if pwm > self.pwm_max:
            pwm = self.pwm_max

        if pwm < self.pwm_min:
            pwm = self.pwm_min
        return int(round(pwm))

    # ----------------------------------------------------------------------
    def read_val_min_max(self, filename, trh_type, scale=1):
        """
        @summary: read device min/max values from file. If file can't be read - returning default value from CONST.TEMP_MIN_MAX
        @param filename: file to be read
        @param trh_type: "min" or "max". this string will be added to filename
        @param scale: scale for read value
        @return: int min/max value
        """
        default_val = str(self.sensors_config.get(trh_type, CONST.TEMP_MIN_MAX[trh_type]))
        if default_val[0] == "!":
            # Use config value instead of device parameter reading
            default_val = default_val[1:]
            val = int(default_val)
        else:
            default_val = int(default_val)
            val = self.get_file_val(filename, default_val)
        val /= scale
        self.log.debug("Set {} {} : {}".format(self.name, trh_type, val))
        return int(val)

    # ----------------------------------------------------------------------
    def check_sensor_blocked(self, name=None):
        """
        @summary:  check if sensor disabled. Sensor can be disabled by writing 1 to file {sensor_name}_blacklist
        @param name: device sensor name
        @return: True if device is disabled
        """
        if not name:
            name = self.name
        blk_filename = "thermal/{}_blacklist".format(name)
        if self.check_file(blk_filename):
            try:
                val_str = self.read_file(blk_filename)
                val = str2bool(val_str)
            except ValueError:
                return False
        else:
            return False
        return val

    # ----------------------------------------------------------------------
    def get_fault_list(self):
        """
        @summary: get fault list
        """
        return self.fault_list

    # ----------------------------------------------------------------------
    def process(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: main function to process device/sensor
        """
        if self.check_sensor_blocked():
            self.stop()
        else:
            self.start()

        if self.state == CONST.RUNNING:
            # refreshing attributes
            if self.refresh_timeout > 0 and self.refresh_timeout < current_milli_time():
                self.refresh_attr()
                self.refresh_timeout = current_milli_time() + self.refresh_attr_period * 1000

            self.handle_input(thermal_table, flow_dir, amb_tmp)
            self.handle_err(thermal_table, flow_dir, amb_tmp)

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about current device state. Can be overridden in child class
        """
        info_str = "\"{}\" temp: {}, tmin: {}, tmax: {}, faults:[{}], pwm: {}, {}".format(self.name, self.value, self.val_min, self.val_max, ",".join(self.fault_list), self.pwm, self.state)
        return info_str



class thermal_sensor(system_device):
    """
    @summary: base class for simple thermal sensors
    can be used for cpu/sodimm/psu/voltmon/etc. thermal sensors
    """
    def __init__(self, cmd_arg, sys_config, name, logger):
        system_device.__init__(self, cmd_arg, sys_config, name, logger)

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_min = self.read_val_min_max("{}_min".format(self.base_file_name), "val_min", CONST.TEMP_SENSOR_SCALE)
        self.val_max = self.read_val_min_max("{}_max".format(self.base_file_name), "val_max", CONST.TEMP_SENSOR_SCALE)

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: hahdle sensor device input
        """
        pwm = self.pwm_min
        value = self.value
        if not self.check_file(self.file_input):
            self.log.warn("{}: missing file {}".format(self.name, self.file_input))
            self.handle_reading_file_err(self.file_input)
        else:
            try:
                temperature = int(self.read_file(self.file_input))
                self.handle_reading_file_err(self.file_input, reset=True)
                value = int(temperature / CONST.TEMP_SENSOR_SCALE)
            except BaseException:
                self.log.error("Wrong value reading from file: {}".format(self.file_input))
                self.handle_reading_file_err(self.file_input)
        self.update_value(value)

        if self.value > self.val_max:
            pwm = self.pwm_max
            self.log.info("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                              self.value,
                                                                              self.val_max,
                                                                              pwm))
        elif self.value < self.val_min:
            pwm = self.pwm_min
            self.log.debug("{} value {}".format(self.name, self.value))
        else:
            pwm = self.calculate_pwm_formula()

        self.pwm = pwm

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor errors
        """
        self.fault_list = []
        # sensor error reading counter
        if self.check_reading_file_err():
            self.fault_list.append("sensor_read")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "sensor_err"])
            self.pwm = max(pwm, self.pwm)

        self._update_pwm()
        return None


class thermal_module_sensor(system_device):
    """
    @summary: base class for modules sensor
    can be used for mlxsw/gearbox modules thermal sensor
    """
    def __init__(self, cmd_arg, sys_config, name, logger):
        system_device.__init__(self, cmd_arg, sys_config, name, logger)

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        # Disable kernel control for this thermal zone
        self.refresh_attr()
        if "asic" in self.base_file_name:
            tz_name = "mlxsw"
        else:
            tz_name = "mlxsw-{}".format(self.base_file_name)
        tz_policy_filename = "thermal/{}/thermal_zone_policy".format(tz_name)
        tz_mode_filename = "thermal/{}/thermal_zone_mode".format(tz_name)
        try:
            self.write_file(tz_policy_filename, "user_space")
            self.write_file(tz_mode_filename, "disabled")
        except:
            pass

    # ----------------------------------------------------------------------
    def refresh_attr(self):
        """
        @summary: refresh sensor attributes.
        @return None
        """
        self.val_max = self.read_val_min_max("thermal/{}_temp_crit".format(self.base_file_name), "val_max", scale=CONST.TEMP_SENSOR_SCALE)
        if "asic" in self.base_file_name:
            self.val_min = self.read_val_min_max("thermal/{}_temp_norm".format(self.base_file_name), "val_min", scale=CONST.TEMP_SENSOR_SCALE)
        else:
            if self.val_max != 0:
                self.val_min = self.val_max - 20
            else:
                self.val_min = self.val_max

    # ----------------------------------------------------------------------
    def get_fault(self):
        """
        @summary: Get module sensor fault status
        @return: True - in case if sensor is readeble and have consistent values
            False - if module is in 'faulty' state
        """
        status = False
        fault_filename = "thermal/{}_temp_fault".format(self.base_file_name)
        if self.check_file(fault_filename):
            try:
                fault_status = int(self.read_file(fault_filename))
                self.handle_reading_file_err(fault_filename, reset=True)
                if fault_status:
                    status = True
            except BaseException:
                self.log.error("{}- Incorrect value in the file: {} ({})".format(self.name, fault_filename, BaseException))
                status = True
                self.handle_reading_file_err(fault_filename)

        return status

    # ----------------------------------------------------------------------
    def get_temp_support_status(self):
        """
        @summary: Check if module supporting temp sensor (optic)
        @return: True - in case if temp sensor is supported
            False - if module is not optical
        """
        status = True

        if self.value == 0 and self.val_max == 0 and self.val_min == 0:
            self.log.debug("Module not supporting temp reading val:{} max:{}".format(self.value, self.val_max))
            status = False

        return status

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        pwm = self.pwm_min

        temp_read_file = "thermal/{}".format(self.file_input)
        if not self.check_file(temp_read_file):
            self.log.info("Missing file {} :{}.".format(self.name, temp_read_file))
            self.handle_reading_file_err(temp_read_file)
        else:
            try:
                temperature = int(self.read_file(temp_read_file))
                self.handle_reading_file_err(temp_read_file, reset=True)
                temperature /= CONST.TEMP_SENSOR_SCALE
                self.log.debug("{} value:{}".format(self.name, temperature))
                # for modules that is not equipped with thermal sensor temperature returns zero
                value = int(temperature)
                # handle case if cable was replsed by the other cable with the sensor
                if value != 0 and self.val_min == 0 and self.val_max == 0:
                    self.log.info("{} refreshing min/max arttribures by the rule: val({}) min({}) max({})".format(self.name,
                                                                                                                  self.val_min,
                                                                                                                  self.val_max))
                    self.refresh_attr()
                self.update_value(value)

                if self.value != 0:
                    if self.value > self.val_max:
                        pwm = self.pwm_max
                        self.log.info("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                                          self.value,
                                                                                          self.val_max,
                                                                                          pwm))
                    elif self.value < self.val_min:
                        pwm = self.pwm_min
            except BaseException:
                self.log.warn("value reading from file: {}".format(self.base_file_name))
                self.handle_reading_file_err(temp_read_file)

        self.pwm = pwm
        # check if module have sensor interface
        if self.get_temp_support_status():
            # calculate PWM based on formula
            self.pwm = max(self.calculate_pwm_formula(), pwm)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor errors
        """
        self.fault_list = []
        module_fault = self.get_fault()
        """if module_fault:
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.UNTRUSTED_ERR], interpolated=False)
            self.pwm = max(pwm, self.pwm)
            self.fault_list.append(CONST.UNTRUSTED_ERR)
            self.log.warn("{} fault (untrusted). Set PWM {}".format(self.name, pwm))"""

        # sensor error reading counter
        if self.check_reading_file_err():
            self.fault_list.append("sensor_read")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "sensor_read_error"], interpolated=False)
            self.pwm = max(pwm, self.pwm)

        self._update_pwm()
        return None


class psu_fan_sensor(system_device):
    """
    @summary: base class for PSU device
    Can be used for Control of PSU temperature/RPM
    """
    def __init__(self, cmd_arg, sys_config, name, logger):
        system_device.__init__(self, cmd_arg, sys_config, name, logger)

        self.prsnt_err_pwm_min = self.get_file_val("config/pwm_min_psu_not_present")
        self.pwm_decode = sys_config.get(CONST.SYS_CONF_FAN_PWM, PSU_PWM_DECODE_DEF)
        self.fan_dir = CONST.C2P
        self.pwm_last = CONST.PWM_MIN

        self.fault_list = []

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_min = self.read_val_min_max("thermal/{}_fan_min".format(self.base_file_name), "val_min")
        self.val_max = self.read_val_min_max("thermal/{}_fan_max".format(self.base_file_name), "val_max")
        self.refresh_attr()
        self.pwm_last = CONST.PWM_MIN
        
    # ----------------------------------------------------------------------
    def refresh_attr(self):
        """
        @summary: refresh sensor attributes.
        @return None
        """
        self.fan_dir = self._read_dir()

    # ----------------------------------------------------------------------
    def _read_dir(self):
        """
        @summary: Reading chassis fan dir from FS
        """
        if self._get_status() == 0:
            return CONST.UNKNOWN

        if self.check_file("thermal/{}_fan_dir".format(self.base_file_name)):
            dir_val = self.read_file("thermal/{}_fan_dir".format(self.base_file_name))
            if dir_val == "0":
                direction = CONST.C2P
            else:
                direction = CONST.P2C
        else:
            direction = CONST.UNKNOWN
        return direction

    # ----------------------------------------------------------------------
    def _get_status(self):
        """
        """
        psu_status_filename = "thermal/{}_status".format(self.base_file_name)
        psu_status = 0
        if not self.check_file(psu_status_filename):
            self.log.warn("Missing file {} dev: {}".format(psu_status_filename, self.name))
            self.handle_reading_file_err(psu_status_filename)
        else:
            try:
                psu_status = int(self.read_file(psu_status_filename))
                self.handle_reading_file_err(psu_status_filename, reset=True)
            except BaseException:
                self.log.error("Can't read {}".format(psu_status_filename))
                self.handle_reading_file_err(psu_status_filename)
        return psu_status

    # ----------------------------------------------------------------------
    def set_pwm(self, pwm):
        """
        @summary: Set PWM level for PSU FAN
        @param pwm: PWM level value <= 100%
        """
        self.log.info("Write {} PWM {}".format(self.name, pwm))
        try:
            present = self.thermal_read_file_int("{0}_pwr_status".format(self.base_file_name))
            if present == 1:
                psu_pwm, _, _ = g_get_range_val(self.pwm_decode, pwm)
                if not psu_pwm:
                    self.log.warning("{} Can't much PWM {} to PSU. PWM value not be change".format(self.name, pwm))

                if psu_pwm == -1:
                    self.log.debug("{} PWM value {}. It means PWM should not be shanged".format(self.name, pwm))
                    # no need to change PSU PWM
                    return

                if psu_pwm < CONST.PWM_PSU_MIN:
                    psu_pwm = CONST.PWM_PSU_MIN

                self.pwm_last = psu_pwm
                bus = self.read_file("config/{0}_i2c_bus".format(self.base_file_name))
                addr = self.read_file("config/{0}_i2c_addr".format(self.base_file_name))
                command = self.read_file("config/fan_command")
                i2c_cmd = "i2cset -f -y {0} {1} {2} {3} wp".format(bus, addr, command, psu_pwm)
                self.log.debug("{} set pwm {} cmd:{}".format(self.name, psu_pwm, i2c_cmd))
                subprocess.call(i2c_cmd, shell=True)
        except BaseException:
            self.log.error("{} set PWM error".format(self.name))

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        self.pwm = self.pwm_min
        rpm_file_name = "thermal/{}".format(self.file_input)
        if not self.check_file(rpm_file_name):
            self.log.warn("Missing file {} dev: {}".format(rpm_file_name, self.name))
            self.handle_reading_file_err(rpm_file_name)
        else:
            try:
                value = int(self.read_file(rpm_file_name))
                self.handle_reading_file_err(rpm_file_name, reset=True)
                self.update_value(value)
                self.log.debug("{} value {}".format(self.name, self.value))
            except BaseException:
                self.log.error("Value reading from file: {}".format(rpm_file_name))
                self.handle_reading_file_err(rpm_file_name)
        return

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor error
        """
        fault_list_old = self.fault_list
        self.fault_list = []
        psu_status = self._get_status()
        if psu_status == 0:
            # PSU status error. Calculating dmin based on this information
            self.log.info("{} psu_status {}".format(self.name, psu_status))
            self.fault_list.append("present")
            if self.prsnt_err_pwm_min:
                pwm = self.prsnt_err_pwm_min
            else:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "psu_err", "present"])
            self.pwm = max(pwm, self.pwm)
        elif "present" in fault_list_old:
            # PSU returned back. Restole old PWM value
            self.log.info("{} PWM restore to {}".format(self.name, self.pwm_last))
            self.set_pwm(self.pwm_last)

        # truth table for fan direction
        #  FAN_DIR SYS_DIR     ERROR
        #  C2P     C2P        False
        #  C2P     P2C        True
        #  C2P     UNKNOWN    False
        #  P2C     C2P        True
        #  P2C     P2C        False
        #  P2C     UNKNOWN    False
        #  UNKNOWN C2P        False
        #  UNKNOWN P2C        False
        #  UNKNOWN UNKNOWN    False
        if (self.system_flow_dir == CONST.C2P and self.fan_dir == CONST.P2C) or \
           (self.system_flow_dir == CONST.P2C and self.fan_dir == CONST.C2P):
            self.fault_list.append("direction")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "psu_err", "direction"])
            self.pwm = max(pwm, self.pwm)
            self.log.warn("{} dir error. Set PWM {}".format(self.name, pwm))

        # sensor error reading counter
        if self.check_reading_file_err():
            self.fault_list.append("sensor_read")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "sensor_err"])
            self.pwm = max(pwm, self.pwm)

        self._update_pwm()
        return

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about device state.
        """
        return "\"{}\" rpm:{}, dir:{} faults:[{}] pwm: {}, {}".format(self.name, self.value, self.fan_dir, ",".join(self.fault_list), self.pwm, self.state)


class fan_sensor(system_device):
    """
    @summary: base class for FAN device
    Can be used for Control FAN RPM/state.
    """
    def __init__(self, cmd_arg, sys_config, name, logger):
        system_device.__init__(self, cmd_arg, sys_config, name, logger)

        self.fan_param = sys_config.get(CONST.SYS_CONF_FAN_PARAM, SYS_FAN_PARAM_DEF)
        self.tacho_cnt = self.sensors_config.get("tacho_cnt", 1)
        self.fan_drwr_id = int(self.sensors_config["drwr_id"])
        self.tacho_idx = ((self.fan_drwr_id - 1) * self.tacho_cnt) + 1
        self.fan_dir = self._read_dir()
        self.fan_dir_fail = False
        self.drwr_param = self._get_fan_drwr_param()
        self.val_min_def = self.get_file_val("config/fan_min_speed", CONST.RPM_MIN_MAX["val_min"])
        self.val_max_def = self.get_file_val("config/fan_max_speed", CONST.RPM_MIN_MAX["val_max"])
        self.is_calibrated = False

        self.rpm_relax_timeout = CONST.FAN_RELAX_TIME * 1000
        self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout * 2
        self.name = "{}:{}".format(self.name, list(range(self.tacho_idx, self.tacho_idx + self.tacho_cnt)))

        self.rpm_valid_state = True

        self.fault_list = []

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_min_def = self.get_file_val("config/fan_min_speed", CONST.RPM_MIN_MAX["val_min"])
        self.val_max_def = self.get_file_val("config/fan_max_speed", CONST.RPM_MIN_MAX["val_max"])

        self.value = [0] * self.tacho_cnt

        self.fault_list = []
        self.pwm = self.pwm_min
        self.rpm_valid_state = True
        self.fan_dir_fail = False
        self.fan_dir = self._read_dir()
        self.drwr_param = self._get_fan_drwr_param()
        self.fan_shutdown(False)

    # ----------------------------------------------------------------------
    def refresh_attr(self):
        """
        @summary: refresh sensor attributes.
        @return None
        """
        self.fan_dir = self._read_dir()

    # ----------------------------------------------------------------------
    def _get_fan_drwr_param(self):
        """
        @summary: Get fan params from system configuration
        @return: FAN params depending of fan dir
        """
        dir = self.fan_dir
        param = None
        if dir not in self.fan_param.keys():
            if dir == CONST.UNKNOWN:
                self.log.info("{} dir \"{}\". Using default dir: P2C".format(self.name, dir))
            else:
                self.log.error("{} dir \"{}\" unsupported in configuration:\n{}".format(self.name, dir, self.fan_param))
                self.log.error("Using default dir: P2C")
            dir = CONST.DEF_DIR

        param = self.fan_param[dir]
        return param

    # ----------------------------------------------------------------------
    def _read_dir(self):
        """
        @summary: Reading chassis fan dir from FS
        """
        if self._get_status() == 0:
            return CONST.UNKNOWN

        if self.check_file("thermal/fan{}_dir".format(self.fan_drwr_id)):
            dir_val = self.read_file("thermal/fan{}_dir".format(self.fan_drwr_id))
            direction = CONST.C2P if dir_val == "0" else CONST.P2C
        else:
            direction = CONST.UNKNOWN
        return direction

    # ----------------------------------------------------------------------
    def _get_status(self):
        """
        @summary: Read FAN status value from file thermal/fan{}_status
        @return: Return status value from file or None in case of reading error
        """
        status_filename = "thermal/fan{}_status".format(self.fan_drwr_id)
        status = None
        if not self.check_file(status_filename):
            self.log.warn("Missing file {} dev: {}".format(status_filename, self.name))
            self.handle_reading_file_err(status_filename)
        else:
            try:
                status = int(self.read_file(status_filename))
                self.handle_reading_file_err(status_filename, reset=True)
            except BaseException:
                self.log.error("Value reading from file: {}".format(status_filename))
                self.handle_reading_file_err(status_filename)
        return status

    # ----------------------------------------------------------------------
    def _get_fault(self):
        """
        """
        fan_fault = []
        for tacho_idx in range(self.tacho_idx, self.tacho_idx + self.tacho_cnt):
            fan_fault_filename = "thermal/fan{}_fault".format(tacho_idx)
            if not self.check_file(fan_fault_filename):
                self.log.info("Missing file {} dev: {}".format(fan_fault_filename, self.name))
            else:
                try:
                    val = int(self.read_file(fan_fault_filename))
                    fan_fault.append(val)
                except BaseException:
                    self.log.error("Value reading from file: {}".format(fan_fault_filename))
        return fan_fault

    # ----------------------------------------------------------------------
    def _validate_rpm(self):
        """
        """
        pwm_curr = self.read_pwm()

        for tacho_idx in range(self.tacho_cnt):
            fan_param = self.drwr_param[str(tacho_idx)]
            rpm_file_name = "fan{}_speed_get".format(self.tacho_idx + tacho_idx)
            try:
                rpm_real = self.thermal_read_file_int(rpm_file_name)
            except BaseException:
                self.log.warn("value reading from file: {}".format(rpm_file_name))
                rpm_real = self.value[tacho_idx]

            rpm_min = int(fan_param["rpm_min"])
            if rpm_min == 0:
                rpm_min = self.val_min_def

            rpm_max = int(fan_param["rpm_max"])
            if rpm_max == 0:
                rpm_max = self.val_max_def

            rpm_tolerance = float(fan_param.get("rpm_tolerance", CONST.FAN_RPM_TOLERANCE))/100
            pwm_min = int(fan_param["pwm_min"])
            slope = int(fan_param["slope"])
            self.log.debug("Real:{} min:{} max:{} slope{} validate rpm".format(rpm_real, rpm_min, rpm_max, slope))
            # 1. Check fan speed in range with tolerance
            if rpm_real < rpm_min*(1-rpm_tolerance) or rpm_real > rpm_max*(1+rpm_tolerance):
                self.log.info("{} tacho{}={} out of RPM range {}:{}".format(self.name,
                                                                            tacho_idx+1,
                                                                            rpm_real,
                                                                            rpm_min,
                                                                            rpm_max))
                return False

             # 2. Check fan trend
            if pwm_curr >= pwm_min:
                # if FAN spped stabilized after the last change
                if self.rpm_relax_timestump <= current_milli_time():
                    # claculate speed
                    b = rpm_max - slope * CONST.PWM_MAX
                    rpm_calcuated = slope * pwm_curr + b
                    rpm_diff = abs(rpm_real - rpm_calcuated)
                    rpm_diff_norm = float(rpm_diff) / rpm_calcuated
                    self.log.debug("validate_rpm:{} b:{} rpm_calcuated:{} rpm_diff:{} rpm_diff_norm:{:.2f}".format(self.name,
                                                                                                               b,
                                                                                                               rpm_calcuated,
                                                                                                               rpm_diff,
                                                                                                               rpm_diff_norm))
                    if rpm_diff_norm >= rpm_tolerance:
                        self.log.warn("{} tacho {}: {} too much different {:.2f}% than calculated {} pwm  {}".format(self.name,
                                                                                                                 tacho_idx,
                                                                                                                 rpm_real,
                                                                                                                 rpm_diff_norm*100,
                                                                                                                 rpm_calcuated,
                                                                                                                 pwm_curr))
                        return False
        return True

    # ----------------------------------------------------------------------
    def set_pwm(self, pwm_val):
        """
        @summary: Set PWM level for chassis FAN
        @param pwm_val: PWM level value <= 100%
        """
        self.log.info("Write {} PWM {}".format(self.name, pwm_val))
        if pwm_val < CONST.PWM_MIN:
            pwm_val = CONST.PWM_MIN

        pwn_curr = self.read_pwm()
        if pwm_val == pwn_curr:
            return

        pwm_jump = abs(pwm_val - pwn_curr)

        # For big PWM jumpls - wse longer FAN relax timeout
        relax_time = (pwm_jump * self.rpm_relax_timeout) / 20
        if relax_time >  self.rpm_relax_timeout * 2:
            relax_time = self.rpm_relax_timeout * 2
        elif relax_time < self.rpm_relax_timeout / 2:
            relax_time = self.rpm_relax_timeout / 2
        self.log.debug("{} pwm_change:{} relax_time:{}".format(self.name, pwm_jump, relax_time))
        self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout * 2

        self.write_pwm(pwm_val)

    # ----------------------------------------------------------------------
    def get_dir(self):
        """
        @summary: return cached chassis fan direction
        @return: fan direction CONST.P2C/CONST.C2P
        """
        return self.fan_dir

    def get_max_reduction(self):
        """
        @summary: get max_reduction value from fan parameters
        """
        val = self.drwr_param["0"].get("pwm_max_reduction", CONST.PWM_MAX_REDUCTION)
        return int(val)

    # ----------------------------------------------------------------------
    def check_sensor_blocked(self, name=None):
        """
        @summary:  check if sensor disabled. Sensor can be disabled by writing 1 to file {sensor_name}_blacklist
        @param name: device sensor name
        @return: True if device is disabled
        """
        val = False
        if not name:
            try:
                name = self.name.split(':')[0]
            except:
                name = self.name
        blk_filename = "thermal/{}_blacklist".format(name)
        if self.check_file(blk_filename):
            try:
                val_str = self.read_file(blk_filename)
                val = str2bool(val_str)
            except ValueError:
                return False
        else:
            return False
        return val

    # ----------------------------------------------------------------------
    def fan_shutdown(self, shutdown=False):
        """
        @summary: Shutdown FAN
        @param shutdown: bool.
        @return: True if shutdown successfull. False If shutdown not supportingor error
        """
        ret = True
        fan_shutdown_filename = "system/{}_shutdown"
        if self.check_file(fan_shutdown_filename):
            try:
                state = CONST.FAN_SHUTDOWN_ENA if shutdown else CONST.FAN_SHUTDOWN_DIS
                self.write_file(fan_shutdown_filename, state)
            except ValueError:
                ret = False
        else:
            ret = False
        return ret

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        self.pwm = self.pwm_min
        for tacho_id in range(0, self.tacho_cnt):
            rpm_file_name = "thermal/fan{}_speed_get".format(self.tacho_idx + tacho_id)
            if not self.check_file(rpm_file_name):
                self.log.warn("Missing file {} dev: {}".format(rpm_file_name, self.name))
                self.handle_reading_file_err(rpm_file_name)
            else:
                try:
                    self.value[tacho_id] = int(self.read_file(rpm_file_name))
                    self.handle_reading_file_err(rpm_file_name, reset=True)
                    self.log.debug("{} value {}".format(self.name, self.value))
                except BaseException:
                    self.log.error("Value reading from file: {}".format(rpm_file_name))
                    self.handle_reading_file_err(rpm_file_name)
        return

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor error
        """
        self.fault_list = []
        fan_status = self._get_status()
        if fan_status == 0:
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", "present"])
            self.pwm = max(pwm, self.pwm)
            self.fault_list.append("present")
            self.log.warn("{} status 0. Set PWM {}".format(self.name, pwm))

        if not self._validate_rpm():
            self.fault_list.append("tacho")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", "tacho"])
            self.pwm = max(pwm, self.pwm)
            self.log.warn("{} incorrect rpm {}. Set PWM  {}".format(self.name, self.value, pwm))

        # truth table for fan direction
        #  FAN_DIR SYS_DIR     ERROR
        #  C2P     C2P        False
        #  C2P     P2C        True
        #  C2P     UNKNOWN    False
        #  P2C     C2P        True
        #  P2C     P2C        False
        #  P2C     UNKNOWN    False
        #  UNKNOWN C2P        False
        #  UNKNOWN P2C        False
        #  UNKNOWN UNKNOWN    False

        if (self.system_flow_dir == CONST.C2P and self.fan_dir == CONST.P2C) or \
           (self.system_flow_dir == CONST.P2C and self.fan_dir == CONST.C2P):
            self.fault_list.append("direction")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", "direction"])
            self.log.warn("{} dir error. Set PWM {}".format(self.name, pwm))
            self.pwm = max(pwm, self.pwm)
            self.fan_shutdown(False)

        # sensor error reading counter
        if self.check_reading_file_err():
            self.fault_list.append("sensor_read")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "sensor_err"])
            self.pwm = max(pwm, self.pwm)
        self._update_pwm()
        return

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about device state.
        """
        info_str = "\"{}\" rpm:{}, dir:{} faults:[{}] pwm {} {}".format(self.name, self.value, self.fan_dir, ",".join(self.fault_list), self.pwm, self.state)
        return info_str


class ambiant_thermal_sensor(system_device):
    """
    @summary: base class for ambient sensor. Ambient temperature is a combination
    of several temp sensors like port_amb and fan_amb
    """
    def __init__(self, cmd_arg, sys_config, name, logger):
        system_device.__init__(self, cmd_arg, sys_config, name, logger)
        self.value_dict = {CONST.FAN_SENS: 0, CONST.PORT_SENS: 0}
        self.flow_dir = CONST.C2P

 # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_min = self.read_val_min_max("", "val_min", CONST.TEMP_SENSOR_SCALE)
        self.val_max = self.read_val_min_max("", "val_max", CONST.TEMP_SENSOR_SCALE)

    # ----------------------------------------------------------------------
    def set_flow_dir(self, flow_dir):
        """
        @summary: Set fan flow direction
        """
        self.flow_dir = flow_dir

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        pwm = self.pwm_min

        # reading all amb8 sensors
        for sensor_name, file_name in self.base_file_name.items():
            sens_file_name = "thermal/{}".format(file_name)
            if not self.check_file(sens_file_name):
                self.log.warn("{}: missing file {}".format(self.name, sens_file_name))
                self.handle_reading_file_err(sens_file_name)
            else:
                try:
                    temperature = int(self.read_file(sens_file_name))
                    self.handle_reading_file_err(sens_file_name, reset=True)
                    temperature /= CONST.TEMP_SENSOR_SCALE
                    self.value_dict[file_name] = int(temperature)
                    self.log.debug("{} {} value {}".format(self.name, sens_file_name, temperature))
                except BaseException:
                    self.log.error("Error value reading from file: {}".format(self.base_file_name))
                    self.handle_reading_file_err(sens_file_name)

        sensor_name_min = min(self.value_dict, key=self.value_dict.get)
        value = self.value_dict[sensor_name_min]
        self.update_value(value)

        if self.value > self.val_max:
            pwm = self.pwm_max
            self.log.info("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                              self.value,
                                                                              self.val_max,
                                                                              pwm))
        elif self.value < self.val_min:
            pwm = self.pwm_min
            self.log.debug("{} value {}".format(self.name, self.value))
        else:
            pwm = self.calculate_pwm_formula()

        self.pwm = pwm
        #g_get_dmin(thermal_table, self.value, [self.flow_dir, self.trusted], interpolated=True)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor errors
        """
        self.fault_list = []
        # sensor error reading counter
        if self.check_reading_file_err():
            self.fault_list.append("sensor_read")
            pwm = g_get_dmin(thermal_table, 60, [self.flow_dir, "sensor_err"])
            self.pwm = max(pwm, self.pwm)
        self._update_pwm()
        return None

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about device state.
        """
        sens_val = ""
        sensor_name_min = min(self.value_dict, key=self.value_dict.get)
        for key, val in self.value_dict.items():
            sens_val += "{}:{} ".format(key, val)
        info_str = "\"{}\" {}({}), dir:{}, faults:[{}] pwm:{}, {}".format(self.name,
                                                                          sens_val,
                                                                          self.value_dict[sensor_name_min],
                                                                          self.flow_dir,
                                                                          ",".join(self.fault_list),
                                                                          self.pwm,
                                                                          self.state)
        return info_str


"""
Main class for Thermal control. Init and running all devices objects.
Controlling devices states and calculation PWM based on this information.
"""


class ThermalManagement(hw_managemet_file_op):
    """
        @summary:
            Main class of thermal algorithm.
            Provide system monitoring and thermal control
    """

    def __init__(self, cmd_arg):
        """
        @summary:
            Init  thermal algorithm
        @param params: global thermal configuration
        """
        hw_managemet_file_op.__init__(self, cmd_arg)
        self.log = Logger(cmd_arg[CONST.LOG_USE_SYSLOG], cmd_arg[CONST.LOG_FILE], cmd_arg["verbosity"])
        self.log.notice("Preinit thermal control")
        try:
            self.write_file(CONST.LOG_LEVEL_FILENAME, cmd_arg["verbosity"])
        except BaseException:
            pass
        self.periodic_report_worker_timer = None
        self.cmd_arg = cmd_arg

        self.pwm_target = CONST.PWM_MAX
        self.pwm = self.pwm_target
        self.pwm_change_reason = "tc start"
        self.system_flow_dir = CONST.UNKNOWN

        if self.check_file(CONST.PERIODIC_REPORT_FILE):
            self.periodic_report_time = int(self.read_file(CONST.PERIODIC_REPORT_FILE))
            self.rm_file(CONST.PERIODIC_REPORT_FILE)
        else:
            self.periodic_report_time = CONST.PERIODIC_REPORT_TIME
        self.log.info("periodic report {} sec".format(self.periodic_report_time))

        self.dev_obj_list = []

        self.pwm_max_reduction = CONST.PWM_MAX_REDUCTION
        self.pwm_worker_poll_time = CONST.PWM_WORKER_POLL_TIME
        self.pwm_worker_timer = None
        self.state = CONST.UNCONFIGURED

        signal.signal(signal.SIGTERM, self.sig_handler)
        signal.signal(signal.SIGINT, self.sig_handler)
        signal.signal(signal.SIGHUP, self.sig_handler)
        self.exit = Event()

        self.load_configuration()

        # Set PWM to the default state while we are waiting for system configuration
        self.log.notice("Set FAN PWM {}".format(self.pwm_target))
        self.write_pwm(self.pwm_target)

        if self.check_file("config/thermal_delay"):
            thermal_delay = int(self.read_file("config/thermal_delay"))
            self.log.info("Sleep (thermal_delay) {} sec".format(thermal_delay))
            self.exit.wait(thermal_delay)

        self.log.notice("Mellanox thermal control is waiting for configuration ({} sec).".format(CONST.THERMAL_WAIT_FOR_CONFIG))
        self.exit.wait(CONST.THERMAL_WAIT_FOR_CONFIG)
        self._collect_hw_info()
        self.amb_tmp = CONST.TEMP_INIT_VAL_DEF

    # ---------------------------------------------------------------------
    def _collect_hw_info(self):
        """
        @summary: Check and read device info from hw-management config (psu count, fan count etc...
        """
        self.max_tachos = CONST.FAN_TACHO_COUNT_DEF
        self.fan_drwr_num = CONST.FAN_DRWR_COUNT_DEF
        self.psu_count = CONST.PSU_COUNT_DEF
        self.psu_pwr_count = CONST.PSU_COUNT_DEF
        self.module_counter = CONST.MODULE_COUNT_DEF
        self.gearbox_counter = CONST.GEARBOX_COUNT_DEF
        self.fan_flow_capability = CONST.UNKNOWN
        self.voltmon_file_list = []

        if self.check_file("config/system_flow_capability"):
            self.fan_flow_capability = self.read_file("config/system_flow_capability")

        self.log.info("Collecting HW info...")

        try:
            self.max_tachos = int(self.read_file("config/max_tachos"))
            self.log.info("Fan tacho:{}".format(self.max_tachos))
        except BaseException:
            self.log.error("Missing max tachos config.")
            sys.exit(1)

        try:
            self.fan_drwr_num = int(self.read_file("config/fan_drwr_num"))
            self.log.info("Fan drwr:{}".format(self.fan_drwr_num))
        except BaseException:
            self.log.error("Missing fan_drwr_num config.")
            sys.exit(1)

        try:
            self.psu_count = int(self.read_file("config/hotplug_psus"))
            self.log.info("PSU count:{}".format(self.psu_count))
        except BaseException:
            self.log.error("Missing hotplug_psus config.")
            sys.exit(1)

        try:
            self.psu_pwr_count = int(self.read_file("config/hotplug_pwrs"))
        except BaseException:
            self.log.error("Missing hotplug_pwrs config.")
            sys.exit(1)

        # Find voltmon temp sensors
        file_list = os.listdir("{}/thermal".format(self.cmd_arg[CONST.HW_MGMT_ROOT]))
        for fname in file_list:
            res = re.match(r'(voltmon[0-9]+_temp)_input', fname)
            if res:
                self.voltmon_file_list.append(res.group(1))
        self.log.info("voltmon count:{}".format(len(self.voltmon_file_list)))

        if self.fan_drwr_num:
            self.fan_drwr_capacity = int(self.max_tachos / self.fan_drwr_num)
        self.module_counter = int(self.get_file_val("config/module_counter", CONST.MODULE_COUNT_DEF))
        self.log.info("module count:{}".format(self.module_counter))
        self.gearbox_counter = int(self.get_file_val("config/gearbox_counter", CONST.GEARBOX_COUNT_DEF))
        self.log.info("gearbox count:{}".format(self.gearbox_counter))

    # ----------------------------------------------------------------------
    def _get_dev_obj(self, name_mask):
        """
        @summary: Get device object by it's name
        """
        for dev_obj in self.dev_obj_list:
            if re.match(name_mask, dev_obj.name):
                return dev_obj
        return None

    # ---------------------------------------------------------------------
    def _get_chassis_fan_dir(self):
        """
        @summary: Comparing case FAN direction. In case the number of presented air-in fans is higher or equal to the
        number of presented air-out fans, set the direction error bit of all the presented air-out fans.
        Otherwise, set the direction error bit of all the presented air-in fans.
        """
        if self.fan_flow_capability != CONST.UNKNOWN:
            return self.fan_flow_capability

        c2p_count = 0
        p2c_count = 0
        for dev_obj in self.dev_obj_list:
            if re.match(r'fan\d+', dev_obj.name):
                fan_dir = dev_obj.fan_dir
                if fan_dir == CONST.C2P:
                    c2p_count += 1
                elif fan_dir == CONST.P2C:
                    p2c_count += 1

        if c2p_count > p2c_count:
            pref_dir = CONST.C2P
        else:
            pref_dir = CONST.P2C

        return pref_dir

    # ----------------------------------------------------------------------
    def _update_psu_fan_speed(self, pwm):
        """
        @summary:
            Set PSU fan depending of current cooling state
        @return: pwm value calculated based on PSU state
        """
        for psu_idx in range(1, self.psu_pwr_count + 1):
            psu_obj = self._get_dev_obj("psu{}_fan".format(psu_idx))
            if psu_obj:
                psu_obj.set_pwm(pwm)

    # ----------------------------------------------------------------------
    def _update_chassis_fan_speed(self, pwm_val):
        """
        @summary:
            Set chassis fan PWM
        @return: None
        """
        self.log.info("Update chassis FAN PWM {}".format(pwm_val))
        for fan_idx in range(1, self.fan_drwr_num + 1):
            fan_obj = self._get_dev_obj("fan{}.*".format(fan_idx))
            if fan_obj:
                fan_obj.set_pwm(pwm_val)

    # ----------------------------------------------------------------------
    def _set_pwm(self, pwm, reason=""):
        """
        @summary: Set target PWM for the system
        @param pwm: target PWM value
        """
        pwm = int(pwm)
        if pwm > CONST.PWM_MAX:
            pwm = CONST.PWM_MAX

        if pwm != self.pwm_target:
            if reason:
                reason_notice = 'reason:"{}"'.format(reason)
            else:
                reason_notice = ""
            self.pwm_change_reason = reason_notice
            self.log.notice("PWM target changed from {} to PWM {} {}".format(self.pwm_target, pwm, reason_notice))
            self._update_psu_fan_speed(pwm)
            self.pwm_target = pwm
            if self.pwm_worker_timer:
                self.pwm_worker_timer.start(True)
            else:
                self.pwm = pwm
                self._update_chassis_fan_speed(self.pwm)
        else:
            pwm_real = self.read_pwm()
            if pwm_real != self.pwm:
                self.log.warn("Unexpected pwm1 value {}. Force set to {}".format(pwm_real, self.pwm_target))
                self._update_chassis_fan_speed(self.pwm)

    # ----------------------------------------------------------------------
    def _pwm_worker(self):
        ''
        if self.pwm_target == self.pwm:
            pwm_real = self.read_pwm()
            if pwm_real != self.pwm:
                self.log.warn("Unexpected pwm1 value {}. Force set to {}".format(pwm_real, self.pwm))
                self._update_chassis_fan_speed(self.pwm)
            self.pwm_worker_timer.stop()
            return

        self.log.debug("PWM target: {} curr: {}".format(self.pwm_target, self.pwm))
        if self.pwm_target < self.pwm:
            diff = abs(self.pwm_target - self.pwm)
            step = int(round((float(diff) / 2 + 0.5)))
            if step > self.pwm_max_reduction:
                step = self.pwm_max_reduction
            self.pwm -= step
        else:
            self.pwm = self.pwm_target
        self._update_chassis_fan_speed(self.pwm)

    # ----------------------------------------------------------------------
    def _update_system_flow_dir(self, flow_dir):
        """
        @summary:
            Update all nested subsystems with the expected flow fir
        @return: None
        """
        self.log.info("Update chassis FAN dir {}".format(flow_dir))
        self.system_flow_dir = flow_dir
        for dev_obj in self.dev_obj_list:
            dev_obj.set_system_flow_dir(flow_dir)

    # ----------------------------------------------------------------------
    def _is_suspend(self):
        """
        @summary: return suspend state from suspend file configuration
        """
        if self.check_file(CONST.SUSPEND_FILE):
            try:
                val_str = self.read_file(CONST.SUSPEND_FILE)
                val = str2bool(val_str)
            except ValueError:
                return False
        else:
            return False
        return val

    # ----------------------------------------------------------------------
    def _sensor_add_config(self, sensor_type, sensor_name, extra_config=None):
        """
        @summary: Create sensor config and add it to main config dict
        @param sensor_type: sensor/device sensor_type
        @param sensor_name: sensor/device sensor_name
        @param extr_config: additional configuration which can override default values from SENSOR_DEF_CONFIG
        """
        sensors_config = self.sys_config[CONST.SYS_CONF_SENSORS_CONF]
        if sensor_name not in sensors_config.keys():
            sensors_config[sensor_name] = {"type": sensor_type}
        sensors_config[sensor_name]["name"] = sensor_name

        if extra_config:
            add_missing_to_dict(sensors_config[sensor_name], extra_config)

        # 1. Add missing keys from system_conf->sensors_config to sensor_conf
        dev_param = self.sys_config[CONST.SYS_CONF_DEV_PARAM]
        for name_mask, val in dev_param.items():
            if re.match(name_mask, sensor_name):
                add_missing_to_dict(sensors_config[sensor_name], val)
                break

        # 2. Add missing keys from def config to sensor_conf
        dev_param = SENSOR_DEF_CONFIG
        for name_mask, val in dev_param.items():
            if re.match(name_mask, sensor_name):
                add_missing_to_dict(sensors_config[sensor_name], val)
                break

    # ----------------------------------------------------------------------
    def _pwm_get_max(self, pwm_list):
        """
        @summary: calculating PWM. returning maximum PWM value in the passed list
        @param pwm_lis: list with pwm values.
        @return:Max PWM value (int)
        """
        pwm_max = 0
        name = ""
        for key, val in pwm_list.items():
            if val > pwm_max:
                pwm_max = val
                name = key
        return pwm_max, name

    # ----------------------------------------------------------------------
    def get_fault_cnt(self):
        """
        @summary: get error count (total error kinds) for sensor
        @return: total raised error flags count
        """

        fault_cnt = 0
        for dev_obj in self.dev_obj_list:
            if dev_obj.get_fault_list():
                fault_cnt += 1
        return fault_cnt

    # ----------------------------------------------------------------------
    def _pwm_strategy_avg(self, pwm_list):
        return float(sum(pwm_list)) / len(pwm_list)

    # ----------------------------------------------------------------------
    def sig_handler(self, sig, frame):
        """
        @summary:
            Signal handler for termination signals
        """
        if sig in [signal.SIGTERM, signal.SIGINT, signal.SIGHUP]:
            self.stop(reason="SIG {}".format(sig))
            self.exit.set()

            self.log.notice("Thermal control stopped")
            sys.exit(1)

    # ----------------------------------------------------------------------
    def load_configuration(self):
        """
        @summary: Init sonfiguration table.
        """
        board_type_file = "/sys/devices/virtual/dmi/id/board_name"
        sku_file = "/sys/devices/virtual/dmi/id/product_sku"
        system_ver_file = "/sys/devices/virtual/dmi/id/product_version"

        if os.path.isfile(board_type_file):
            with open(board_type_file, "r") as content_file:
                self.board_type = content_file.read().rstrip("\n")

        if os.path.isfile(sku_file):
            with open(sku_file, "r") as content_file:
                self.sku = content_file.read().rstrip("\n")

        if os.path.isfile(system_ver_file):
            with open(system_ver_file, "r") as content_file:
                self.system_ver = content_file.read().rstrip("\n")

        sys_config = {}
        if self.cmd_arg[CONST.SYSTEM_CONFIG]:
            config_file_name = self.cmd_arg[CONST.SYSTEM_CONFIG]
        else:
            config_file_name = CONST.SYSTEM_CONFIG_FILE

        if os.path.exists(config_file_name):
            with open(config_file_name) as f:
                self.log.info("Loading system config from {}".format(config_file_name))
                try:
                    sys_config = json.load(f)
                    if "name" in sys_config.keys():
                        self.log.info("System data: {}".format(sys_config["name"]))
                except Exception:
                    self.log.error("System config file {} broken. Applying default config.".format(config_file_name))
        else:
            self.log.warn("System config file {} missing. Applying default config.".format(config_file_name))

        # 1. Init dmin table
        if CONST.SYS_CONF_DMIN not in sys_config:
            self.log.info("Dmin table missing in system_config. Using default dmin table")
            thermal_table = TABLE_DEFAULT
            sys_config[CONST.SYS_CONF_DMIN] = thermal_table

        # 2. Init PSU fan speed vs system fan speed table
        if CONST.SYS_CONF_FAN_PWM not in sys_config:
            self.log.info("PSU fan speed vs system fan speed table missing in system_config. Init it from local.")
            sys_config[CONST.SYS_CONF_FAN_PWM] = PSU_PWM_DECODE_DEF

        # 3. Init Fan Parameters table
        if CONST.SYS_CONF_FAN_PARAM not in sys_config:
            self.log.info("Fan Parameters table missing in system_config. Init it from local")
            sys_config[CONST.SYS_CONF_FAN_PARAM] = SYS_FAN_PARAM_DEF

        # 4. Init device parameters table
        if CONST.SYS_CONF_DEV_PARAM not in sys_config:
            self.log.info("Sensors param config table missing in system_config. Init it from local")
            sys_config[CONST.SYS_CONF_DEV_PARAM] = {}

        # 5. Init sensors config table
        if CONST.SYS_CONF_SENSORS_CONF not in sys_config:
            sys_config[CONST.SYS_CONF_SENSORS_CONF] = {}

        self.sys_config = sys_config

    # ----------------------------------------------------------------------
    def init_sensor_configuration(self):
        """
        @summary: Init sensor configuration based on system type and information from
        hw-management configuration folder
        """

        for psu_idx in range(1, self.psu_count + 1):
            name = "psu{}_fan".format(psu_idx)
            in_file = "psu{}".format(psu_idx)
            self._sensor_add_config("psu_fan_sensor", name, {"base_file_name": in_file})

            name = "psu{}_temp".format(psu_idx)
            in_file = "thermal/psu{}_temp".format(psu_idx)
            self._sensor_add_config("thermal_sensor", name, {"base_file_name": in_file})

        for fan_idx in range(1, self.fan_drwr_num + 1):
            name = "fan{}".format(fan_idx)
            self._sensor_add_config("fan_sensor", name, {"base_file_name": name, "drwr_id": fan_idx, "tacho_cnt": self.fan_drwr_capacity})

        for module_idx in range(1, self.module_counter + 1):
            name = "module{}".format(module_idx)
            self._sensor_add_config("thermal_module_sensor", name, {"base_file_name": name})

        for gearbox_idx in range(1, self.gearbox_counter + 1):
            name = "gearbox{}".format(gearbox_idx)
            self._sensor_add_config("thermal_module_sensor", name, {"base_file_name": name})

        for voltmon in self.voltmon_file_list:
            name = voltmon
            in_file = "thermal/{}".format(name)
            self._sensor_add_config("thermal_sensor", name, {"base_file_name": in_file})

        self._sensor_add_config("thermal_module_sensor", "asic", {"base_file_name": "asic"})

        if self.check_file("thermal/cpu_pack"):
            self._sensor_add_config("thermal_sensor", "cpu_pack", {"base_file_name": "thermal/cpu_pack"})
        elif self.check_file("thermal/cpu_core1"):
            self._sensor_add_config("thermal_sensor", "cpu_core1", {"base_file_name": "thermal/cpu_core1"})

        self._sensor_add_config("ambiant_thermal_sensor", "sensor_amb")

        # scanning for extra sensors (SODIMM 1-4)
        for sodimm_idx in range(1, 5):
            name = "sodimm{}_temp".format(sodimm_idx)
            if self.check_file("thermal/{}_input".format(name)):
                self._sensor_add_config("thermal_sensor", name, {"base_file_name": "thermal/{}".format(name)})

        if self.check_file("thermal/pch_temp"):
            self._sensor_add_config("thermal_sensor", "pch", {"base_file_name": "thermal/pch"})

        if self.check_file("thermal/comex_amb"):
            self._sensor_add_config("thermal_sensor", "comex_amb", {"base_file_name": "thermal/comex_amb"})

    # ----------------------------------------------------------------------
    def init(self):
        """
        @summary: Init thermal-control main
        """
        self.log.notice("********************************")
        self.log.notice("Init thermal control ver: v.{}".format(VERSION))
        self.log.notice("********************************")

        self.init_sensor_configuration()

        # Set initial PWM to maximum
        self._set_pwm(CONST.PWM_MAX, reason="Set initial PWM")

        self.log.debug("System config dump\n{}".format(json.dumps(self.sys_config, sort_keys=True, indent=4)))

        for key, val in self.sys_config[CONST.SYS_CONF_SENSORS_CONF].items():
            try:
                dev_class_ = globals()[val["type"]]
            except Exception as err:
                self.log.error("Unknown dev class {}".format(err.message))
                continue
            dev_obj = dev_class_(self.cmd_arg, self.sys_config, key, self.log)
            if not dev_obj:
                self.log.error("{} create failed".format(key))
                sys.exit(1)

            self.dev_obj_list.append(dev_obj)
        self.dev_obj_list.sort(key=lambda x: x.name)
        self.write_file(CONST.PERIODIC_REPORT_FILE, self.periodic_report_time)

    # ----------------------------------------------------------------------
    def start(self, reason=""):
        """
        @summary: Start sensor service.
        Used when suspend mode was de-asserted
        """

        if self.state != CONST.RUNNING:
            self.log.notice("Thermal control state changed {} -> {} reason:{})".format(self.state, CONST.RUNNING, reason))
            self.state = CONST.RUNNING

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    dev_obj.start()

            # get FAN max reduction from any of FAN
            fan_obj = self._get_dev_obj(r'fan\d+')
            if fan_obj:
                self.pwm_max_reduction = fan_obj.get_max_reduction()

            if not self.periodic_report_worker_timer:
                self.periodic_report_worker_timer = RepeatedTimer(self.periodic_report_time, self.print_periodic_info)
            self.periodic_report_worker_timer.start()

            if not self.pwm_worker_timer:
                self.pwm_worker_timer = RepeatedTimer(self.pwm_worker_poll_time, self._pwm_worker)
            self.pwm_worker_timer.stop()

            fan_dir = self._get_chassis_fan_dir()
            self._update_system_flow_dir(fan_dir)

            ambient_sensor = self._get_dev_obj("sensor_amb")
            if ambient_sensor:
                ambient_sensor.set_flow_dir(fan_dir)
                ambient_sensor.process(self.sys_config[CONST.SYS_CONF_DMIN], fan_dir, CONST.TEMP_INIT_VAL_DEF)
                ambient_sensor = self._get_dev_obj("sensor_amb")
                self.amb_tmp = ambient_sensor.get_value()

    # ----------x------------------------------------------------------------
    def stop(self, reason=""):
        """
        @summary: Stop sensor service and set PWM to PWM-MAX.
        Used when suspend mode was de-asserted  or when kill signal was revived
        """
        if self.state != CONST.STOPPED:
            self.log.notice("Thermal control state changed {} -> {} reason:{}".format(self.state, CONST.STOPPED, reason))
            self.state = CONST.STOPPED

            if self.pwm_worker_timer:
                self.pwm_worker_timer.stop()
                self.pwm_worker_timer = None

            if self.periodic_report_worker_timer:
                self.periodic_report_worker_timer.stop()
                self.periodic_report_worker_timer = None

            self._set_pwm(CONST.PWM_MAX, reason="TC stop")
            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    dev_obj.stop()

    # ----------------------------------------------------------------------
    def run(self):
        """
        @summary:  main thermal control loop
        """

        self.log.notice("********************************")
        self.log.notice("Run thermal control")
        self.log.notice("********************************")

        # main loop
        while not self.exit.is_set():
            try:
                log_level = int(self.read_file(CONST.LOG_LEVEL_FILENAME))
                if log_level != self.cmd_arg["verbosity"]:
                    self.cmd_arg["verbosity"] = log_level
                    self.log.set_loglevel(self.cmd_arg["verbosity"])
            except BaseException:
                pass

            if self._is_suspend():
                self.stop(reason="suspend")
                self.exit.wait(5)
                continue
            else:
                self.start(reason="resume")

            pwm_list = {}
            # set maximum next poll timestump = 60 seec
            timestump_next = current_milli_time() + 60 * 1000
            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    if current_milli_time() >= dev_obj.get_timestump():
                        # process sensors
                        dev_obj.process(self.sys_config[CONST.SYS_CONF_DMIN], self.system_flow_dir, self.amb_tmp)
                        if dev_obj.name == "sensor_amb":
                            self.amb_tmp = dev_obj.get_value()
                        dev_obj.update_timestump()

                    pwm = dev_obj.get_pwm()
                    self.log.debug("{0:25}: PWM {1}".format(dev_obj.name, pwm))
                    pwm_list[dev_obj.name] = pwm

                    obj_timestump = dev_obj.get_timestump()
                    timestump_next = min(obj_timestump, timestump_next)
            fault_cnt = self.get_fault_cnt()
            if fault_cnt > CONST.TOTAL_MAX_ERR_COUNT:
                pwm_list["total_err_cnt({})>{}".format(fault_cnt, CONST.TOTAL_MAX_ERR_COUNT)] = CONST.PWM_MAX

            pwm, name = self._pwm_get_max(pwm_list)
            self.log.debug("Result PWM {}".format(pwm))
            self._set_pwm(pwm, reason=name)
            sleep_ms = int(timestump_next - current_milli_time())

            # Poll time should not be smaller than 1 sec to reduce system load
            # and mot more 20 sec to have a good respreaction for suspend mode change polling
            if sleep_ms < 1 * 1000:
                sleep_ms = 1 * 1000
            elif sleep_ms > 20 * 1000:
                sleep_ms = 20 * 1000
            self.exit.wait(sleep_ms / 1000)

    # ----------------------------------------------------------------------
    def print_periodic_info(self):
        """
        @summary:  Print current TC state and info reported by the sensor objects
        """
        ambient_sensor = self._get_dev_obj("sensor_amb")
        if ambient_sensor:
            amb_tmp = ambient_sensor.get_value()
            flow_dir = self.system_flow_dir
        else:
            amb_tmp = "-"
            flow_dir = "-"

        mlxsw_sensor = self._get_dev_obj("asic")
        if mlxsw_sensor:
            mlxsw_tmp = mlxsw_sensor.get_value()
        else:
            mlxsw_tmp = "N/A"

        self.log.notice("Thermal periodic report")
        self.log.notice("================================")
        self.log.notice("Temperature(C): asic {}, amb {}".format(mlxsw_tmp, amb_tmp))
        self.log.notice("Cooling(%) {} ({})".format(self.pwm_target, self.pwm_change_reason))
        self.log.notice("dir:{}".format(flow_dir))
        self.log.notice("================================")
        for dev_obj in self.dev_obj_list:
            if dev_obj.enable:
                obj_info_str = dev_obj.info()
                if obj_info_str:
                    self.log.notice(obj_info_str)
        self.log.notice("================================")


def str2bool_argparse(val):
    """
    @summary:
        Convert input val value to bool
    """
    res = str2bool(val)
    if res is None:
        raise argparse.ArgumentTypeError("Boolean value expected.")
    return res


class RawTextArgumentDefaultsHelpFormatter(
        argparse.ArgumentDefaultsHelpFormatter,
        argparse.RawTextHelpFormatter
    ):
    """
        @summary:
            Formatter class for pretty print ArgumentParser help
    """
    pass


if __name__ == '__main__':
    CMD_PARSER = argparse.ArgumentParser(formatter_class=RawTextArgumentDefaultsHelpFormatter, description="hw-management thermal control")
    CMD_PARSER.add_argument("--version", action="version", version="%(prog)s ver:{}".format(VERSION))
    CMD_PARSER.add_argument("--system_config",
                            dest=CONST.SYSTEM_CONFIG,
                            help="System configuration file",
                            default=CONST.SYSTEM_CONFIG_FILE)
    CMD_PARSER.add_argument("-l", "--log_file",
                            dest=CONST.LOG_FILE,
                            help="Add output also to log file. Pass file name here",
                            default="/var/log/tc_log")
    CMD_PARSER.add_argument("-s", "--syslog",
                            dest=CONST.LOG_USE_SYSLOG,
                            help="enable/disable output to syslog",
                            type=str2bool_argparse, default=True)
    # Note: set logging to 50 on release
    CMD_PARSER.add_argument("-v", "--verbosity",
                            dest="verbosity",
                            help="""Set log verbosity level.
                        CRITICAL = 50
                        ERROR = 40
                        WARNING = 30
                        INFO = 20
                        DEBUG = 10
                        NOTSET = 0
                        """,
                            type=int, default=20)
    CMD_PARSER.add_argument("-r", "--root_folder",
                            dest=CONST.HW_MGMT_ROOT,
                            help="Define custom hw-management root folder",
                            default=CONST.HW_MGMT_FOLDER_DEF)
    args = vars(CMD_PARSER.parse_args())
    thermal_management = ThermalManagement(args)

    try:
        thermal_management.init()
        thermal_management.start(reason="init")
        thermal_management.run()
    except BaseException as e:
        if str(e) != "1":
            thermal_management.log.info(traceback.format_exc())
        thermal_management.stop(reason=str(e))

    sys.exit(0)
