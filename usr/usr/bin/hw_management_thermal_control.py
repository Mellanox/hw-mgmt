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
Version: 2.1.0

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

VERSION = "2.1.0"

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
    SYS_CONF_ASIC_PARAM = "asic_config"
    SYS_CONF_SENSOR_LIST_PARAM = "sensor_list"
    SYS_CONF_ERR_MASK = "error_mask"
    SYS_CONF_REDUNDANCY_PARAM = "redundancy"

    # *************************
    # Folders definition
    # *************************

    # default hw-management folder
    HW_MGMT_FOLDER_DEF = "/var/run/hw-management"
    # Link to thermal data
    SYSTEM_CONFIG_FILE = "config/tc_config.json"
    # File which defined current level filename.
    # User can dynamically change loglevel without TC restarting.
    LOG_LEVEL_FILENAME = "config/tc_log_level"
     # File which define TC report period. TC should be restarted to apply changes in this file
    PERIODIC_REPORT_FILE = "config/periodic_report"
    # suspend control file path
    SUSPEND_FILE = "config/suspend"
    # i2c control transfer file path
    I2C_CTRL_FILE = "system/bmc_to_cpu_ctrl"
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

    # delay before TC start (sec)
    THERMAL_WAIT_FOR_CONFIG = 60

    # Default period for printing TC report (in sec.)
    PERIODIC_REPORT_TIME = 1 * 60

    # Default sensor configuration if not 0configured other value
    SENSOR_POLL_TIME_DEF = 30
    TEMP_INIT_VAL_DEF = 25
    TEMP_SENSOR_SCALE = 1000.0
    TEMP_MIN_MAX = {"val_min": 35000, "val_max": 70000, "val_crit": 80000}
    RPM_MIN_MAX = {"val_min": 5000, "val_max": 30000}
    AMB_TEMP_ERR_VAL = 255

    # Max/min PWM value - global for all system
    PWM_MIN = 20
    PWM_MAX = 100
    EMERGENCY_PWM = 100
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
    PWM_VALIDATE_TIME = 30
    # FAN RPM tolerance in percent
    FAN_RPM_TOLERANCE = 30

    # default system devices
    PSU_COUNT_DEF = 2
    FAN_DRWR_COUNT_DEF = 6
    FAN_TACHO_COUNT_DEF = 6
    MODULE_COUNT_MAX = 128

    # Consistent file read  errors for set error state
    SENSOR_FREAD_FAIL_TIMES = 3

    # If more than 1 error, set fans to 100%
    TOTAL_MAX_ERR_COUNT = 2

    # Main TC loop state
    UNCONFIGURED = "UNCONFIGURED"
    STOPPED = "STOPPED"
    RUNNING = "RUNNING"

    # error types
    SENSOR_READ_ERR = "sensor_read_error"
    FAN_ERR = "fan_err"
    PSU_ERR = "psu_err"
    TACHO = "tacho"
    PRESENT = "present"
    DIRECTION = "direction"
    UNTRUSTED = "untrusted"
    EMERGENCY = "emergency"

    DRWR_ERR_LIST = [DIRECTION, TACHO, PRESENT, SENSOR_READ_ERR]
    PSU_ERR_LIST = [DIRECTION, PRESENT, SENSOR_READ_ERR]

    MLXREG_SET_CMD_STR = "yes |  mlxreg -d  {pcidev} --reg_name MFSC --indexes \"pwm=0x0\" --set \"pwm_duty_cycle={pwm}\""
    MLXREG_GET_CMD_STR = "mlxreg -d {pcidev} --reg_name MFSC --get --indexes \"pwm=0x0\" | grep pwm | head -n 1 | cut -d '|' -f 2"

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
    r'drwr\d+':         {"type": "fan_sensor",
                         "val_min": 4500, "val_max": 20000, "poll_time": 5,
                         "refresh_attr_period": 1 * 60
                        },
    r'module\d+':       {"type": "thermal_module_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": 60000, "val_max": 80000, "val_lcrit": 0, "poll_time": 20,
                         "input_suffix": "_temp_input", "value_hyst": 2, "refresh_attr_period": 1 * 60
                        },
    r'gearbox\d+':      {"type": "thermal_module_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "!105000", "val_lcrit": 5,  "poll_tme": 6,
                         "input_suffix": "_temp_input", "value_hyst": 2, "refresh_attr_period": 30 * 60
                        },
    r'asic\d*':         {"type": "thermal_asic_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "!105000", "val_lcrit": 0, "poll_time": 3,
                         "value_hyst": 2, "input_smooth_level": 1
                        },
    r'(cpu_pack|cpu_core\d+)': {"type": "thermal_sensor",
                                "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "90000", "val_lcrit": 0, "poll_time": 3,
                                "value_hyst": 5, "input_smooth_level": 3
                               },
    r'sodimm\d_temp':   {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!75000", "val_max": 85000, "val_lcrit": 0, "poll_time": 30,
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
                         "pwm_min": 30, "pwm_max": 70, "val_min": "!70000", "val_max": "!95000", "val_lcrit": 0, "val_hcrit": 150000, "poll_time": 3,
                         "input_suffix": "_input"
                        },
    r'drivetemp':       {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 70, "val_min": "!70000", "val_max": "!95000", "val_lcrit": 0, "val_hcrit": 120000, "poll_time": 60
                        },
    r'ibc\d+':          {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!80000", "val_max": "!110000", "val_lcrit": 0, "poll_time": 60,
                         "input_suffix": "_input"
                        },
    r'ctx_amb\d*':      {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "!105000", "poll_time": 3,
                         "input_suffix": "_input"
                        },
    r'hotswap\d+_temp': {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 70, "val_min": "!70000", "val_max": "!95000", "val_lcrit": -10000, "val_hcrit": 120000, "poll_time": 30,
                         "input_suffix": "_input"
                        },
    r'bmc\d+_temp':     {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 70, "val_min": "!70000", "val_max": "!95000", "val_lcrit": 0, "val_hcrit": 120000, "poll_time": 30,
                        },
    r'dpu\\d+_module':  {"type": "dpu_module",
                         "pwm_min": 20, "pwm_max": 30, "val_min": "!70000", "val_max": "!95000", "poll_time": 5, "child_sensors_list" : []
                        },
    r'dpu\d+_cx_amb':   {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "!105000", "poll_time": 3},
    r'dpu\d+_cpu':      {"type": "thermal_sensor",
                         "pwm_min": 30, "pwm_max": 100, "val_min": "!70000", "val_max": "105000", "poll_time": 3,
                         "input_smooth_level": 1
                        },
    r'dpu\d+_sodimm\d+': {"type": "thermal_sensor",
                          "pwm_min": 30, "pwm_max": 70
                         },
    r'dpu\d+_drivetemp': {"type": "thermal_sensor",
                          "pwm_min": 30, "pwm_max": 70, "val_min": "!55000", "val_max": "!70000", "poll_time": 60
                         },
    r'dpu\d+_voltmon\d+_temp': {"type": "thermal_sensor",
                                "pwm_min": 30, "pwm_max": 70, "val_min": "!70000", "val_max": "!95000", "poll_time": 3,
                                "input_suffix": "_input"
                               },
}

# PSU/FAN redundancy define example:
"""
"redundancy" : {"psu" : {"min_err_cnt" : "0", "err_mask" : "present"},
                "drwr" : {"min_err_cnt" : "0", "err_mask" : null}},
"""
# Error mask example:
"""
"error_mask" : {"psu" : ["direction"]},
"""

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

DMIN_TABLE_DEFAULT = {
    CONST.C2P: {
        CONST.UNTRUSTED: {"-127:120": 60},
        CONST.FAN_ERR: {
            CONST.TACHO: {"-127:120": 100},
            CONST.PRESENT: {"-127:120": 100},
            CONST.DIRECTION: {"-127:120": 100}
        },
        CONST.PSU_ERR:  {
            CONST.PRESENT: {"-127:120": 100},
            CONST.DIRECTION: {"-127:120": 100},
        },
        CONST.SENSOR_READ_ERR: {"-127:120": 100}
    },
    CONST.P2C: {
        CONST.UNTRUSTED: {"-127:120": 60},
        CONST.FAN_ERR: {
            CONST.TACHO: {"-127:120": 100},
            CONST.PRESENT: {"-127:120": 100},
            CONST.DIRECTION: {"-127:120": 100}
        },
        CONST.PSU_ERR:  {
            CONST.PRESENT: {"-127:120": 100},
            CONST.DIRECTION: {"-127:120": 100},
        },
        CONST.SENSOR_READ_ERR: {"-127:120": 100}
    }
}

ASIC_CONF_DEFAULT = {"1":  {"pwm_control": False, "fan_control": False}}


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


# ----------------------------------------------------------------------
class SyslogFilter(logging.Filter):

    def filter(self, record):
        res = False
        if record.getMessage().startswith("@syslog "):
            record.msg = record.getMessage().replace("@syslog ", "")
            res = True
        return res


# ----------------------------------------------------------------------
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
        except:
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
        except:
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
        except:
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
        except:
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
        except:
            pass
        self.logger_emit = True


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
    def read_file_int(self, filename, scale=1):
        """
        @summary:
            read file from hw-management/ tree.
        @param filename: file to read from {hw-management-folder}/filename
        @return: int value from file
        """
        val = self.read_file(filename)
        val = int(val) / scale
        return int(val)

    # ----------------------------------------------------------------------
    def thermal_read_file_int(self, filename, scale=1):
        """
        @summary:
            read file from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @return: int value from file
        """
        val = self.read_file_int(os.path.join("thermal", filename), scale)
        return val

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
        val = def_val
        if self.check_file(filename):
            try:
                val = int(self.read_file(filename)) / scale
            except:
                pass
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
    def write_pwm(self, pwm, validate=False):
        """
        @summary:
            write value to PWM file.
        @param pwm: PWM value in persent 0..100
        @param validate: Make read-after-write validation. Return Tru in case no error
        """
        ret = True
        try:
            pwm_out = int(pwm * 255 / 100)
            if self.check_file("thermal/pwm1"):
                self.write_file("thermal/pwm1", pwm_out)
            else:
                ret = False
        except BaseException:
            ret = False

        if validate:
            pwm_get = self.read_pwm()
            ret = pwm == pwm_get
        return ret

    # ----------------------------------------------------------------------
    def write_pwm_mlxreg(self, pwm, validate=False):
        """
        @summary:
            wrie PWM using direct ASIC register access.
        @param pwm: PWM value in persent 0..100
        @param validate: Make read-after-write validation. Return Tru in case no error
        """
        ret = True
        if not self.asic_pcidev:
            return False

        try:
            pwm_out = int(pwm * 255 / 100)
            if os.path.exists(self.asic_pcidev):
                mlxreg_set_cmd = CONST.MLXREG_SET_CMD_STR.format(pcidev=self.asic_pcidev,
                                                                 pwm=hex(pwm_out))
                self.log.debug("set mlxreg pwm {}% cmd:{}".format(pwm, mlxreg_set_cmd))
                subprocess.call(mlxreg_set_cmd, shell=True)
            else:
                ret = False
        except BaseException:
            ret = False

        if validate:
            pwm_get = self.read_pwm_mlxreg()
            ret = pwm == pwm_get
        return ret

    # ----------------------------------------------------------------------
    def read_pwm(self, default_val=None):
        """
        @summary:
            read PWM from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @param default_val: return valuse in case of read error
        @return: int value from file
        """
        pwm_out = default_val
        try:
            pwm = int(self.read_file("thermal/pwm1"))
            pwm_out = int(pwm / 2.55 + 0.5)
        except BaseException:
            pass

        return pwm_out

    # ----------------------------------------------------------------------
    def read_pwm_mlxreg(self, default_val=None):
        """
        @summary:
            read PWM using direct ASIC register access.
        @param default_val: return valuse in case of read error
        @return: int pwm value
        """
        if not self.asic_pcidev:
            return default_val

        pwm_out = default_val
        try:
            mlxreg_get_cmd = CONST.MLXREG_GET_CMD_STR.format(pcidev=self.asic_pcidev)
            self.log.debug("get mlxreg pwm cmd:{}".format(mlxreg_get_cmd))
            subprocess.run('{} | grep pwm'.format(mlxreg_get_cmd), shell=True, 
                                                            check=False, 
                                                            stdout=subprocess.PIPE, 
                                                            stderr=subprocess.PIPE, 
                                                            text=True)
            ret = result.stdout
            pwm = int(ret.strip(), 16)
            pwm_out = int(pwm / 2.55 + 0.5)
        except BaseException:
            pass

        return pwm_out


class iterate_err_counter():
    def __init__(self, logger, name, err_max):
        self.log = logger
        self.name = name
        self.err_max = err_max
        self.err_counter_dict = {}

    # ----------------------------------------------------------------------
    def reset_all(self):
        self.err_counter_dict = {}

    # ----------------------------------------------------------------------
    def handle_err(self, err_name, reset=False, print_log=True):
        """
        @summary: Handle errors. Saving error counter for each err_name
        @param err_name: err name to be handled
        @param  reset: 1- increment errors counter for file, 0 - reset error counter for the file
        """
        err_cnt = self.err_counter_dict.get(err_name, None)
        err_level = self.err_max
        if not reset:
            if err_cnt:
                err_cnt += 1
            else:
                err_cnt = 1

            if print_log and err_cnt < err_level:
                self.log.warn("{}: {} error {} times".format(self.name, err_name, err_cnt))
        else:
            if err_cnt and err_cnt != 0 and print_log:
                self.log.notice("{}: {} OK".format(self.name, err_name))
            err_cnt = 0
        self.err_counter_dict[err_name] = err_cnt

    # ----------------------------------------------------------------------
    def check_err(self):
        """
        @summary: Compare error counter for each file with the threshold
        @return: list of files with errors counters more then max threshold
        """
        err_keys = []
        for key, val in self.err_counter_dict.items():
            if val >= self.err_max:
                # to reduse log: print err message first 5 times and then only each 10's message
                if val <= (self.err_max + 5) or divmod(val, 100)[1] == 0:
                    self.log.error("{}: err on {} count {}".format(self.name, key, val))
                err_keys.append(key)
        return err_keys

    # ----------------------------------------------------------------------
    def get_err(self, err_name):
        """
        @summary: Get error counter
        @param: err_name: name for error cnt
        @return: number of errors
        """
        return self.err_counter_dict(err_name, 0)

    # ----------------------------------------------------------------------

class system_device(hw_managemet_file_op):
    """
    @summary: base class for system sensors
    """

    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        hw_managemet_file_op.__init__(self, cmd_arg)
        self.log = tc_logger
        self.sensors_config = sys_config[CONST.SYS_CONF_SENSORS_CONF][name]
        self.name = name
        self.type = self.sensors_config["type"]
        self.log.info("Init {0} ({1})".format(self.name, self.type))
        self.log.debug("sensor config:\n{}".format(json.dumps(self.sensors_config, indent=4)))
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
        self.val_hcrit = self.sensors_config.get("val_hcrit", None)      
        self.val_lcrit = self.sensors_config.get("val_lcrit", None)
        self.scale = CONST.TEMP_SENSOR_SCALE
        self.pwm_min = CONST.PWM_MIN
        self.pwm_max = CONST.PWM_MAX
        self.value = CONST.TEMP_INIT_VAL_DEF
        self.value_acc = self.value * self.input_smooth_level
        self.pwm = CONST.PWM_MIN
        self.last_pwm = self.pwm
        self.pwm_hysteresis = int(self.sensors_config.get("pwm_hyst", CONST.PWM_HYSTERESIS_DEF))
        self.state = CONST.STOPPED
        self.fread_err = iterate_err_counter(tc_logger, name, CONST.SENSOR_FREAD_FAIL_TIMES)
        self.refresh_attr_period = 0
        self.refresh_timeout = 0

        self.system_flow_dir = CONST.UNKNOWN
        self.update_pwm_flag = 1
        self.value_last_update = 0
        self.value_last_update_trend = 0
        self.value_trend = 0
        self.value_hyst = int(self.sensors_config.get("value_hyst", CONST.VALUE_HYSTERESIS_DEF))
        self.clear_fault_list()

        # ==================
        self.static_mask_fault_list = []
        self.dynamic_mask_fault_list = self.sensors_config.get("dynamic_err_mask", [])
        if not self.dynamic_mask_fault_list:
            self.dynamic_mask_fault_list = []
        self.mask_fault_list = []
        self.fault_list = []

        self.fault_list_static_filtered = []
        self.fault_list_dynamic_filtered = []
        self.fault_list_dynamic = []
        self.dynamic_filter_ena = False


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
        self.fread_err.reset_all()
        self.sensor_configure()
        self.update_timestump(1000)
        self.clear_fault_list()

    # ----------------------------------------------------------------------
    def stop(self):
        """
        @summary: Stop device service
        """
        if self.state == CONST.STOPPED:
            return

        self.pwm = self.pwm_min
        self.last_pwm = self.pwm
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
    def collect_err(self):
        """
        @summary:
        """

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: Prototype for child class. Using for reading and processing sensor errors
        """

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
    def set_dynamic_mask_fault_list(self, mask_list):
        self.dynamic_mask_fault_list = mask_list

    # ----------------------------------------------------------------------
    def set_static_mask_fault_list(self, fault_list):
        self.static_mask_fault_list = fault_list
        self.mask_fault_list = self.static_mask_fault_list

    # ----------------------------------------------------------------------
    def append_fault(self, fault_name):
        """
        """
        if fault_name not in self.fault_list:
            self.fault_list.append(fault_name)

        # if error present in fault_list_static_filtered (should be masked and ignored)
        if fault_name not in self.static_mask_fault_list:
            if fault_name not in self.fault_list_static_filtered:
                self.fault_list_static_filtered.append(fault_name)

            if (fault_name in self.dynamic_mask_fault_list) and (fault_name not in self.fault_list_dynamic):
                self.fault_list_dynamic.append(fault_name)

        # if error present in fault_list_dynamic_filtered (should be masked and ignored)
        if (fault_name not in self.dynamic_mask_fault_list) and (fault_name not in self.fault_list_dynamic_filtered):
            self.fault_list_dynamic_filtered.append(fault_name)

    # ----------------------------------------------------------------------
    def clear_fault_list(self):
        """
        """
        self.fault_list = []
        self.fault_list_static_filtered = []
        self.fault_list_dynamic_filtered = []
        self.fault_list_dynamic = []

    # ----------------------------------------------------------------------
    def get_fault_list_static_filtered(self):
        """
        @summary: return errors passed trougth static filter
        """
        return self.fault_list_static_filtered

    # ----------------------------------------------------------------------
    def get_fault_list_dynamic(self):
        """
        @summary: return errors passed dynamic filter
        """
        return self.fault_list_dynamic

    # ----------------------------------------------------------------------
    def get_fault_list_filtered(self):
        """
        @summary: return error list passed dynamic filter
        """
        return list(set(self.fault_list_static_filtered  + self.fault_list_dynamic_filtered))

    #----------------------------------------------------------------------
    def set_dynamic_filter_ena(self, ena):
        """
        @summary: Enable for ignore errors marked in dynamic_mask_fault_list
        if enabled - errors in the dynamic_filter will not be taken into account (>2)
        """
        if ena == self.dynamic_filter_ena:
            return
        self.dynamic_filter_ena = ena
        if ena:
            self.mask_fault_list = list(set(self.static_mask_fault_list  + self.dynamic_mask_fault_list))
        else:
            self.mask_fault_list = self.static_mask_fault_list

    # ----------------------------------------------------------------------
    def get_fault_list_str(self):
        fault_lst = []
        for fault_name in self.fault_list:
            if fault_name in self.mask_fault_list:
                fault_name = "#" + fault_name
            fault_lst.append(fault_name)
        return ",".join(fault_lst)

    def get_fault_cnt(self):
        """
        @summary: get fault count
        """
        fault_list = self.get_fault_list_filtered()
        return 1 if fault_list else 0

    # ----------------------------------------------------------------------
    def get_child_list(self):
        return []

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
        fault_list = self.get_fault_list_filtered()
        # sensor error reading counter
        if CONST.SENSOR_READ_ERR in fault_list:
            value = "N/A"
        else:
            value = self.value
        info_str = "\"{}\" temp: {}, tmin: {}, tmax: {}, faults:[{}], pwm: {}, {}".format(self.name,
                                                                                          value,
                                                                                          self.val_min,
                                                                                          self.val_max,
                                                                                          self.get_fault_list_str(),
                                                                                          self.pwm,
                                                                                          self.state)
        return info_str


class thermal_sensor(system_device):
    """
    @summary: base class for simple thermal sensors
    can be used for cpu/sodimm/psu/voltmon/etc. thermal sensors
    """

    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        system_device.__init__(self, cmd_arg, sys_config, name, tc_logger)

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or resume
        """
        scale_value = self.get_file_val(self.base_file_name + "_scale", def_val=1, scale=1)
        self.scale = CONST.TEMP_SENSOR_SCALE / scale_value

        self.val_min = self.read_val_min_max("{}_min".format(self.base_file_name), "val_min", self.scale)
        self.val_max = self.read_val_min_max("{}_max".format(self.base_file_name), "val_max", self.scale)

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: hahdle sensor device input
        """
        pwm = self.pwm_min
        value = self.value
        if not self.check_file(self.file_input):
            self.log.info("Missing file: {}".format(self.file_input))
            self.fread_err.handle_err(self.file_input)
        else:
            try:
                value = self.read_file_int(self.file_input, self.scale)
                self.update_value(value)
                if self.val_hcrit != None and self.value >= self.val_hcrit:
                    self.log.warn("{} value({}) >= hcrit({})".format(self.name,
                                                                            self.value,
                                                                            self.val_hcrit))
                    self.fread_err.handle_err(self.file_input)
                elif self.val_lcrit != None and self.value <= self.val_lcrit:
                    self.log.warn("{} value({}) <= lcrit({})".format(self.name,
                                                                            self.value,
                                                                            self.val_lcrit))
                    self.fread_err.handle_err(self.file_input)
                else:
                    self.fread_err.handle_err(self.file_input, reset=True)
                    if self.value > self.val_max:
                        self.log.warn("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                                      self.value,
                                                                                      self.val_max,
                                                                                      pwm))
                    elif self.value < self.val_min:
                        self.log.debug("{} value {}".format(self.name, self.value))
            except BaseException:
                self.log.warn("Wrong value reading from file: {}".format(self.file_input))
                self.fread_err.handle_err(self.file_input)
        pwm = self.calculate_pwm_formula()
        self.pwm = pwm

    # ----------------------------------------------------------------------
    def collect_err(self):
        self.clear_fault_list()

        if self.fread_err.check_err():
            self.append_fault(CONST.SENSOR_READ_ERR)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor errors
        """
        fault_list = self.get_fault_list_filtered()
        # sensor error reading counter
        if CONST.SENSOR_READ_ERR in fault_list:
            # get special error case for sensor missing
            sensor_err = self.sensors_config.get(CONST.SENSOR_READ_ERR, 0)
            self.pwm = max(int(sensor_err), self.pwm)
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.SENSOR_READ_ERR])
            self.pwm = max(pwm, self.pwm)

        self._update_pwm()
        return None


class thermal_module_sensor(system_device):
    """
    @summary: base class for modules sensor
    can be used for mlxsw/gearbox modules thermal sensor
    """

    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        system_device.__init__(self, cmd_arg, sys_config, name, tc_logger)

    # ----------------------------------------------------------------------
    def refresh_attr(self):
        """
        @summary: refresh sensor attributes.
        @return None
        """
        self.val_max = self.read_val_min_max("thermal/{}_temp_crit".format(self.base_file_name), "val_max", scale=self.scale)
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
                if fault_status:
                    status = True
            except BaseException:
                self.log.error("{}- Incorrect value in the file: {} ({})".format(self.name, fault_filename, BaseException))
                status = True

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
            self.log.info("Missing file: {}.".format(temp_read_file))
            self.fread_err.handle_err(temp_read_file)
        else:
            try:
                value = self.read_file_int(temp_read_file, self.scale)
                self.log.debug("{} value:{}".format(self.name, value))
                self.fread_err.handle_err(temp_read_file, reset=True)
                # handle case if cable was replsed by the other cable with the sensor
                if value != 0 and self.val_min == 0 and self.val_max == 0:
                    self.log.info("{} refreshing min/max arttribures by the rule: val({}) min({}) max({})".format(self.name,
                                                                                                                  value,
                                                                                                                  self.val_min,
                                                                                                                  self.val_max))
                    self.refresh_attr()
                self.update_value(value)

                if self.value != 0:
                    if self.value > self.val_max:
                        self.log.warn("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                                          self.value,
                                                                                          self.val_max,
                                                                                          pwm))
                    elif self.value < self.val_min:
                        self.log.debug("{} value {}".format(self.name, self.value))
            except BaseException:
                self.log.warn("value reading from file: {}".format(self.base_file_name))
                self.fread_err.handle_err(temp_read_file)

        # check if module have temperature reading interface
        if self.get_temp_support_status():
            # calculate PWM based on formula
            pwm = max(self.calculate_pwm_formula(), pwm)
        self.pwm = pwm

    # ----------------------------------------------------------------------
    def collect_err(self):
        self.clear_fault_list()

        if self.fread_err.check_err():
            self.append_fault(CONST.SENSOR_READ_ERR)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor errors
        """
        fault_list = self.get_fault_list_filtered()
        # sensor error reading counter
        if CONST.SENSOR_READ_ERR in fault_list:
            self.append_fault(CONST.SENSOR_READ_ERR)
            # get special error case for sensor missing
            sensor_err = self.sensors_config.get(CONST.SENSOR_READ_ERR, 0)
            self.pwm = max(int(sensor_err), self.pwm)
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.SENSOR_READ_ERR], interpolated=False)
            self.pwm = max(pwm, self.pwm)

        self._update_pwm()
        return None


class thermal_asic_sensor(thermal_module_sensor):
    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        thermal_module_sensor.__init__(self, cmd_arg, sys_config, name, tc_logger)
        self.asic_fault_err = iterate_err_counter(tc_logger, name, CONST.SENSOR_FREAD_FAIL_TIMES)
        
    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        # Disable kernel control for this thermal zone
        self.val_max = self.read_val_min_max("thermal/{}_temp_crit".format(self.base_file_name), "val_max", scale=self.scale)
        self.val_min = self.read_val_min_max("thermal/{}_temp_norm".format(self.base_file_name), "val_min", scale=self.scale)

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        pwm = self.pwm_min
        temp_read_file = "thermal/{}".format(self.file_input)
        if not self.check_file(temp_read_file):
            self.log.info("Missing file: {}.".format(temp_read_file))
            self.fread_err.handle_err(temp_read_file)
        else:
            try:
                value = self.read_file_int(temp_read_file, self.scale)
                self.update_value(value)
                                    
                if value == 0:
                    self.log.error("{} Incorrect value: {} in the file: {}). Emergency error!".format(self.name, 
                                                                                        value, 
                                                                                        temp_read_file))
                    self.asic_fault_err.handle_err(temp_read_file)
                else:
                    self.asic_fault_err.handle_err(temp_read_file, reset=True)

                if self.val_hcrit != None and self.value >= self.val_hcrit:
                    self.log.warn("{} value({}) >= hcrit({})".format(self.name,
                                                                            self.value,
                                                                            self.val_hcrit))
                    self.fread_err.handle_err(temp_read_file)
                elif self.val_lcrit != None and self.value <= self.val_lcrit:
                    self.log.warn("{} value({}) =< lcrit({})".format(self.name,
                                                                            self.value,
                                                                            self.val_lcrit))
                    self.fread_err.handle_err(temp_read_file)
                else:
                    self.fread_err.handle_err(self.file_input, reset=True)
                    if self.value > self.val_max:
                        self.log.warn("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                                      self.value,
                                                                                      self.val_max,
                                                                                      pwm))
                    elif self.value < self.val_min:
                        self.log.debug("{} value {}".format(self.name, self.value))
            except BaseException:
                self.log.warn("value reading from file: {}".format(self.base_file_name))
                self.fread_err.handle_err(temp_read_file)

        # calculate PWM based on formula
        pwm = max(self.calculate_pwm_formula(), pwm)
        self.pwm = pwm

    # ----------------------------------------------------------------------
    def collect_err(self):
        self.clear_fault_list()

        if self.fread_err.check_err():
            self.append_fault(CONST.SENSOR_READ_ERR)

        if self.asic_fault_err.check_err():
            self.append_fault(CONST.EMERGENCY)

class psu_fan_sensor(system_device):
    """
    @summary: base class for PSU device
    Can be used for Control of PSU temperature/RPM
    """

    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        system_device.__init__(self, cmd_arg, sys_config, name, tc_logger)
        if CONST.PSU_ERR in sys_config[CONST.SYS_CONF_ERR_MASK]:
            self.set_static_mask_fault_list(sys_config[CONST.SYS_CONF_ERR_MASK][CONST.PSU_ERR])
        self.prsnt_err_pwm_min = self.get_file_val("config/pwm_min_psu_not_present")
        self.pwm_decode = sys_config.get(CONST.SYS_CONF_FAN_PWM, PSU_PWM_DECODE_DEF)
        self.fan_dir = CONST.C2P
        self.pwm_last = CONST.PWM_MIN
        self.fault_list_old = []

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
        direction = CONST.UNKNOWN
        if self._get_status() != 0:
            if self.check_file("thermal/{}_fan_dir".format(self.base_file_name)):
                dir_val = self.read_file("thermal/{}_fan_dir".format(self.base_file_name))
                if dir_val == "0":
                    direction = CONST.C2P
                elif dir_val == "1":
                    direction = CONST.P2C

        return direction

    # ----------------------------------------------------------------------
    def _get_status(self):
        """
        """
        psu_status_filename = "thermal/{}_status".format(self.base_file_name)
        psu_status = 0
        if not self.check_file(psu_status_filename):
            self.log.info("Missing file: {}".format(psu_status_filename))
        else:
            try:
                psu_status = int(self.read_file(psu_status_filename))
            except BaseException:
                self.log.info("Can't read {}".format(psu_status_filename))
        return psu_status

    # ----------------------------------------------------------------------
    def set_pwm(self, pwm):
        """
        @summary: Set PWM level for PSU FAN
        @param pwm: PWM level value <= 100%
        """
        try:
            present = self.thermal_read_file_int("{0}_pwr_status".format(self.base_file_name))
            if present == 1:
                self.log.info("Write {} PWM {}".format(self.name, pwm))
                psu_pwm, _, _ = g_get_range_val(self.pwm_decode, pwm)
                if not psu_pwm:
                    self.log.info("{} Can't much PWM {} to PSU. PWM value not be change".format(self.name, pwm))

                if psu_pwm == -1:
                    self.log.debug("{} PWM value {}. It means PWM should not be changed".format(self.name, pwm))
                    # no need to change PSU PWM
                    return

                if psu_pwm < CONST.PWM_PSU_MIN:
                    psu_pwm = CONST.PWM_PSU_MIN

                self.pwm_last = psu_pwm
                bus = self.read_file("config/{0}_i2c_bus".format(self.base_file_name))
                addr = self.read_file("config/{0}_i2c_addr".format(self.base_file_name))
                command = self.read_file("config/fan_command")
                fan_config_command = self.read_file("config/fan_config_command")
                fan_speed_units = self.read_file("config/fan_speed_units")

                # Set fan speed units (percentage or RPM)
                i2c_cmd = "i2cset -f -y {0} {1} {2} {3} wp".format(bus, addr, fan_config_command, fan_speed_units)
                subprocess.call(i2c_cmd, shell=True)
                # Set fan speed
                i2c_cmd = "i2cset -f -y {0} {1} {2} {3} wp".format(bus, addr, command, psu_pwm)
                self.log.debug("{} set pwm {} cmd:{}".format(self.name, psu_pwm, i2c_cmd))
                subprocess.call(i2c_cmd, shell=True)
        except BaseException:
            self.log.error("{} set PWM error".format(self.name), 1)

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        self.pwm = self.pwm_min
        # check if PSU present.
        # if PSU is plugged in then PSU fan missing is not an error
        psu_status = self._get_status()
        rpm_file_name = "thermal/{}".format(self.file_input)
        if psu_status == 1:
            try:
                value = int(self.read_file(rpm_file_name))
                self.update_value(value)
                self.log.debug("{} value {}".format(self.name, self.value))
            except BaseException:
                self.update_value(-1)
                pass
        return

    # ----------------------------------------------------------------------
    def collect_err(self):
        self.clear_fault_list()

        psu_status = self._get_status()
        if psu_status == 0:
            self.append_fault(CONST.PRESENT)

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
            self.append_fault(CONST.DIRECTION)

        if self.fread_err.check_err():
            self.append_fault(CONST.SENSOR_READ_ERR)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor error
        """
        pwm_new = self.pwm
        fault_list = self.get_fault_list_filtered()
        self.fault_list_old = self.fault_list

        psu_status = self._get_status()

        if CONST.PRESENT in fault_list:
            # PSU status error. Calculating pwm based on dmin information
            self.log.info("{} psu_status {}".format(self.name, psu_status))
            # do not update pwm if error in "masked" list
            if CONST.PRESENT not in self.mask_fault_list:
                if self.prsnt_err_pwm_min:
                    pwm_new = self.prsnt_err_pwm_min
                else:
                    pwm_new = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.PSU_ERR, CONST.PRESENT])
        elif CONST.PRESENT in self.fault_list_old:
            # PSU returned back. Restole old PWM value
            self.log.info("{} PWM restore to {}".format(self.name, self.pwm_last))
            self.set_pwm(self.pwm_last)

        if CONST.DIRECTION in fault_list:
            if CONST.DIRECTION not in self.mask_fault_list:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.PSU_ERR, CONST.DIRECTION])
                pwm_new = max(pwm, pwm_new)
                self.log.warn("{} dir error. Set PWM {}".format(self.name, pwm))

        # sensor error reading file
        if CONST.SENSOR_READ_ERR in fault_list:
            # get special error case for sensor missing
            sensor_err = self.sensors_config.get(CONST.SENSOR_READ_ERR, 0)
            self.pwm = max(int(sensor_err), self.pwm)
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.SENSOR_READ_ERR])
            pwm_new = max(pwm, pwm_new)

        self.pwm = pwm_new
        self._update_pwm()
        return

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about device state.
        """
        return "\"{}\" rpm:{}, dir:{} faults:[{}] pwm: {}, {}".format(self.name,
                                                                      self.value,
                                                                      self.fan_dir,
                                                                      self.get_fault_list_str(),
                                                                      self.pwm,
                                                                      self.state)


class fan_sensor(system_device):
    """
    @summary: base class for FAN device
    Can be used for Control FAN RPM/state.
    """

    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        system_device.__init__(self, cmd_arg, sys_config, name, tc_logger)

        self.fan_drwr_id = int(self.sensors_config["drwr_id"])
        self.fan_param = sys_config.get(CONST.SYS_CONF_FAN_PARAM, SYS_FAN_PARAM_DEF)
        if CONST.FAN_ERR in sys_config[CONST.SYS_CONF_ERR_MASK]:
            self.set_static_mask_fault_list(sys_config[CONST.SYS_CONF_ERR_MASK][CONST.FAN_ERR])
        self.fan_dir = self._read_dir()
        self.fan_dir_fail = False
        self.drwr_param = self._get_fan_drwr_param()
        self.tacho_cnt = self.sensors_config.get("tacho_cnt", 1)
        if self.tacho_cnt > len(self.drwr_param):
            self.log.warn("{} tacho per FAN modlue mismatch: get {}, defined in config {}".format(self.name,
                                                                                           self.tacho_cnt,
                                                                                           len(self.drwr_param)))
            self.log.info("{} init tacho_cnt from config: {}".format(self.name,
                                                                     len(self.drwr_param)))
            self.tacho_cnt = len(self.drwr_param)

        self.tacho_idx = ((self.fan_drwr_id - 1) * self.tacho_cnt) + 1
        self.val_min_def = self.get_file_val("thermal/fan{}_min".format(self.tacho_idx), CONST.RPM_MIN_MAX["val_min"])
        self.val_max_def = self.get_file_val("thermal/fan{}_max".format(self.tacho_idx), CONST.RPM_MIN_MAX["val_max"])
        self.is_calibrated = False

        self.rpm_relax_timeout = CONST.FAN_RELAX_TIME * 1000
        self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout * 2
        self.name = "{}:{}".format(self.name, list(range(self.tacho_idx, self.tacho_idx + self.tacho_cnt)))
        self.pwm_set = self.read_pwm(CONST.PWM_MIN)

        self.rpm_valid_state = True

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_min_def = self.get_file_val("thermal/fan{}_min".format(self.tacho_idx), CONST.RPM_MIN_MAX["val_min"])
        self.val_max_def = self.get_file_val("thermal/fan{}_max".format(self.tacho_idx), CONST.RPM_MIN_MAX["val_max"])

        self.value = [0] * self.tacho_cnt

        self.pwm = self.pwm_min
        self.rpm_valid_state = True
        self.fan_dir_fail = False
        self.fan_dir = self._read_dir()
        self.drwr_param = self._get_fan_drwr_param()
        self.fan_shutdown(False)
        self.pwm_set = self.read_pwm(CONST.PWM_MIN)

    # ----------------------------------------------------------------------
    def refresh_attr(self):
        """
        @summary: refresh sensor attributes.
        @return None
        """
        self.fan_dir = self._read_dir()
        self.drwr_param = self._get_fan_drwr_param()

    # ----------------------------------------------------------------------
    def _get_fan_drwr_param(self):
        """
        @summary: Get fan params from system configuration
        @return: FAN params depending of fan dir
        """
        fan_dir = self.fan_dir
        param = None
        if fan_dir not in self.fan_param.keys():
            fan_dir_def = [key for key in self.fan_param][0]
            if fan_dir == CONST.UNKNOWN:
                self.log.info("{} dir \"{}\". Using default dir: {}".format(self.name, fan_dir, fan_dir_def))
            else:
                self.log.error("{} dir \"{}\" unsupported in configuration. Using default dir: {}:\n{}".format(self.name,
                                                                                                               fan_dir,
                                                                                                               fan_dir_def,
                                                                                                               self.fan_param))
            fan_dir = fan_dir_def

        param = self.fan_param[fan_dir]
        return param

    # ----------------------------------------------------------------------
    def _read_dir(self):
        """
        @summary: Reading chassis fan dir from FS
        """
        direction = CONST.UNKNOWN
        if self._get_status() == 1:
            if self.check_file("thermal/fan{}_dir".format(self.fan_drwr_id)):
                dir_val = self.read_file("thermal/fan{}_dir".format(self.fan_drwr_id))
                if dir_val == "0":
                    direction = CONST.C2P
                elif dir_val == "1":
                    direction = CONST.P2C
        return direction

    # ----------------------------------------------------------------------
    def _get_status(self):
        """
        @summary: Read FAN status value from file thermal/fan{}_status
        @return: Return status value from file or None in case of reading error
        """
        status_filename = "thermal/fan{}_status".format(self.fan_drwr_id)
        status = 0
        if not self.check_file(status_filename):
            self.log.info("Missing file: {}".format(status_filename))
        else:
            try:
                status = int(self.read_file(status_filename))
            except BaseException:
                self.log.error("Value reading from file: {}".format(status_filename))
        return status

    # ----------------------------------------------------------------------
    def _get_fault(self):
        """
        """
        fan_fault = []
        for tacho_idx in range(self.tacho_idx, self.tacho_idx + self.tacho_cnt):
            fan_fault_filename = "thermal/fan{}_fault".format(tacho_idx)
            if not self.check_file(fan_fault_filename):
                self.log.info("Missing file: {}".format(fan_fault_filename))
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
        if not pwm_curr:
            self.log.error("Read PWM error")
            return False

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

            rpm_tolerance = float(fan_param.get("rpm_tolerance", CONST.FAN_RPM_TOLERANCE)) / 100
            pwm_min = int(fan_param["pwm_min"])
            self.log.debug("Real:{} min:{} max:{}".format(rpm_real, rpm_min, rpm_max))
            # 1. Check fan speed in range with tolerance
            if rpm_real < rpm_min * (1 - rpm_tolerance) or rpm_real > rpm_max * (1 + rpm_tolerance):
                self.log.info("{} tacho{}={} out of RPM range {}:{}".format(self.name,
                                                                            tacho_idx + 1,
                                                                            rpm_real,
                                                                            rpm_min,
                                                                            rpm_max))
                return False

             # 2. Check fan trend
            if pwm_curr >= pwm_min:
                # if FAN spped stabilized after the last change
                if self.rpm_relax_timestump <= current_milli_time() and pwm_curr == self.pwm_set:
                    # claculate speed
                    slope = int(fan_param["slope"])
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
                        self.log.warn("{} tacho{}: {} too much different {:.2f}% than calculated {} pwm  {}".format(self.name,
                                                                                                                    tacho_idx,
                                                                                                                    rpm_real,
                                                                                                                    rpm_diff_norm * 100,
                                                                                                                    rpm_calcuated,
                                                                                                                    pwm_curr))
                        return False
        return True

    # ----------------------------------------------------------------------
    def set_pwm(self, pwm_val, force=False):
        """
        @summary: Set PWM level for chassis FAN
        @param pwm_val: PWM level value <= 100%
        """
        self.log.info("Write {} PWM {}".format(self.name, pwm_val))
        if pwm_val < CONST.PWM_MIN:
            pwm_val = CONST.PWM_MIN

        if pwm_val == self.pwm_set and not force:
            return

        pwm_jump = abs(pwm_val - self.pwm_set)

        # For big PWM jumpls - wse longer FAN relax timeout
        relax_time = (pwm_jump * self.rpm_relax_timeout) / 20
        if relax_time > self.rpm_relax_timeout * 2:
            relax_time = self.rpm_relax_timeout * 2
        elif relax_time < self.rpm_relax_timeout / 2:
            relax_time = self.rpm_relax_timeout / 2
        self.rpm_relax_timestump = current_milli_time() + relax_time
        self.log.debug("{} pwm jump by:{} relax_time:{} timestump {}".format(self.name, pwm_jump, relax_time, self.rpm_relax_timestump))

        self.pwm_set = pwm_val

        if not self.write_pwm(pwm_val, validate=True):
            self.log.warn("PWM write validation mismatch set:{} get:{}".format(pwm_val, self.read_pwm()))

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
            value = 0
            rpm_file_name = "thermal/fan{}_speed_get".format(self.tacho_idx + tacho_id)
            if not self.check_file(rpm_file_name):
                self.log.warn("Missing file {}".format(rpm_file_name))
            else:
                try:
                    value = int(self.read_file(rpm_file_name))
                    self.log.debug("{} value {}".format(self.name, self.value))
                except BaseException:
                    self.log.error("Value reading from file: {}".format(rpm_file_name))
            self.value[tacho_id] = value
        return

    # ----------------------------------------------------------------------
    def collect_err(self):
        self.clear_fault_list()
        fan_status = self._get_status()
        if fan_status == 0:
            self.append_fault(CONST.PRESENT)

        if not self._validate_rpm():
            self.append_fault(CONST.TACHO)

        if (self.system_flow_dir == CONST.C2P and self.fan_dir == CONST.P2C) or \
           (self.system_flow_dir == CONST.P2C and self.fan_dir == CONST.C2P):
            self.append_fault(CONST.DIRECTION)

        if self.fread_err.check_err():
            self.append_fault(CONST.SENSOR_READ_ERR)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor error
        """
        pwm_new = self.pwm
        fault_list = self.get_fault_list_filtered()
        if CONST.PRESENT in fault_list:
            # do not update pwm if error in "masked" list
            if CONST.PRESENT not in self.mask_fault_list:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.FAN_ERR, CONST.PRESENT])
                pwm_new = max(pwm, pwm_new)
                self.log.warn("{} status 0. Set PWM {}".format(self.name, pwm))

        if CONST.TACHO in fault_list:
            # do not update pwm if error in "masked" list
            if CONST.TACHO not in self.mask_fault_list:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.FAN_ERR, CONST.TACHO])
                pwm_new = max(pwm, pwm_new)
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
        if CONST.DIRECTION in fault_list:
            # do not update pwm if error in "masked" list
            if CONST.DIRECTION not in self.mask_fault_list:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.FAN_ERR, CONST.DIRECTION])
                self.log.warn("{} dir error. Set PWM {}".format(self.name, pwm))
                pwm_new = max(pwm, pwm_new)
                self.fan_shutdown(False)

        # sensor error reading counter
        if CONST.SENSOR_READ_ERR in fault_list:
            if CONST.SENSOR_READ_ERR not in self.mask_fault_list:
                # get special error case for sensor missing
                sensor_err = self.sensors_config.get(CONST.SENSOR_READ_ERR, 0)
                self.pwm = max(int(sensor_err), self.pwm)
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, CONST.SENSOR_READ_ERR])
                pwm_new = max(pwm, pwm_new)

        self.pwm = pwm_new
        self._update_pwm()
        return

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about device state.
        """
        info_str = "\"{}\" rpm:{}, dir:{} faults:[{}] pwm {} {}".format(self.name,
                                                                        self.value,
                                                                        self.fan_dir,
                                                                        self.get_fault_list_str(),
                                                                        self.pwm,
                                                                        self.state)
        return info_str


class ambiant_thermal_sensor(system_device):
    """
    @summary: base class for ambient sensor. Ambient temperature is a combination
    of several temp sensors like port_amb and fan_amb
    """

    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        system_device.__init__(self, cmd_arg, sys_config, name, tc_logger)
        self.value_dict = {}
        for sens in self.base_file_name.values():
            self.value_dict[sens] = CONST.AMB_TEMP_ERR_VAL
        self.flow_dir = CONST.C2P

 # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_min = self.read_val_min_max("", "val_min", self.scale)
        self.val_max = self.read_val_min_max("", "val_max", self.scale)

    # ----------------------------------------------------------------------
    def set_flow_dir(self, flow_dir):
        """
        @summary: Set fan flow direction
        """
        self.flow_dir = flow_dir

    # ----------------------------------------------------------------------
    def get_fault_cnt(self):
        """
        @summary: get fault count
        """
        err_cnt = 0
        fault_list = self.get_fault_list_filtered()
        if CONST.SENSOR_READ_ERR in fault_list:
            err_cnt = len(self.fread_err.check_err())

        return err_cnt

    # ----------------------------------------------------------------------
    def get_value(self):
        """
        @summary: Return sensor value. Value type depends from sensor type and can be: Celsius degree, rpm, ...
        """
        min_sens_value =  min(self.value_dict.values())
        if min_sens_value != CONST.AMB_TEMP_ERR_VAL:
            return self.value
        else:
            return CONST.AMB_TEMP_ERR_VAL

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        # reading all amb sensors
        for _, file_name in self.base_file_name.items():
            sens_file_name = "thermal/{}".format(file_name)
            if not self.check_file(sens_file_name):
                self.log.info("Missing file: {}".format(sens_file_name))
                self.fread_err.handle_err(sens_file_name)
            else:
                try:
                    temperature = self.read_file_int(sens_file_name, self.scale)
                    self.fread_err.handle_err(sens_file_name, reset=True)
                    self.value_dict[file_name] = temperature
                    self.log.debug("{} {} value {}".format(self.name, sens_file_name, temperature))
                except BaseException:
                    self.log.error("Error value reading from file: {}".format(sens_file_name))
                    self.fread_err.handle_err(sens_file_name)
            # in case of file reading error - set sesor to ignore
            if sens_file_name in self.fread_err.check_err():
                self.value_dict[file_name] = CONST.AMB_TEMP_ERR_VAL

        value = min(self.value_dict.values())
        if value != CONST.AMB_TEMP_ERR_VAL:
            self.update_value(value)

        if self.value > self.val_max:
            self.log.debug("{} value({}) above max({})".format(self.name, self.value, self.val_max))
        elif self.value < self.val_min:
            self.log.debug("{} value {} less min({})".format(self.name, self.value, self.val_min))

        self.pwm = self.calculate_pwm_formula()

    # ----------------------------------------------------------------------
    def collect_err(self):
        self.clear_fault_list()

        if self.fread_err.check_err():
            self.append_fault(CONST.SENSOR_READ_ERR)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor errors
        """
        fault_list = self.get_fault_list_filtered()

        if CONST.SENSOR_READ_ERR in fault_list:
            # get special error case for sensor missing
            sensor_err = self.sensors_config.get(CONST.SENSOR_READ_ERR, 0)
            self.pwm = max(int(sensor_err), self.pwm)
            pwm = g_get_dmin(thermal_table, self.value, [self.flow_dir, CONST.SENSOR_READ_ERR])
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
            if val == CONST.AMB_TEMP_ERR_VAL:
                val = "N/A"
            sens_val += "{}:{} ".format(key, val)
        info_str = "\"{}\" {}({}), dir:{}, faults:[{}] pwm:{}, {}".format(self.name,
                                                                          sens_val,
                                                                          self.value_dict[sensor_name_min],
                                                                          self.flow_dir,
                                                                          self.get_fault_list_str(),
                                                                          self.pwm,
                                                                          self.state)
        return info_str


class dpu_module(system_device):
    """
    @summary: base class for simple thermal sensors
    can be used for cpu/sodimm/psu/voltmon/etc. thermal sensors
    """

    def __init__(self, cmd_arg, sys_config, name, tc_logger):
        system_device.__init__(self, cmd_arg, sys_config, name, tc_logger)

        self.child_name_list = []
        self.child_obj_list = []
        self.ready = False
        child_list = self.base_file_name = self.sensors_config.get("child_sensors_list", [])
        for sensor in child_list:
            res = re.match(r'(dpu\d+)_module', self.name)
            if res:
                dpu_name = res.group(1)
                sensor_name = "{}_{}".format(dpu_name, sensor)
                self.child_name_list.append(sensor_name)

    # ----------------------------------------------------------------------
    def add_child_obj(self, child):
        ""
        self.child_obj_list.append(child)

    # ----------------------------------------------------------------------
    def get_child_list(self):
        return self.child_name_list

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        ""
        dps_ready_filename = self.file_input
        if not self.check_file(dps_ready_filename):
            self.log.info("Missing file: {}".format(dps_ready_filename))
        else:
            try:
                self.ready = bool(self.read_file_int(dps_ready_filename))
                self.log.debug("{} {} value {}".format(self.name,
                                                       dps_ready_filename,
                                                       self.ready))
            except BaseException:
                self.log.error("Error value reading from file: {}".format(dps_ready_filename))

        for child_obj in self.child_obj_list:
            if self.ready:
                child_obj.start()
                child_obj.enable = True
            else:
                child_obj.stop()
                child_obj.enable = False

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about current device state.
        """
        info_str = "\"{}\", ready:{}, {}".format(self.name, self.ready, self.state)
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

    """
    functions which adding sensor configuration by the sensor name
    """
    ADD_SENSOR_HANDLER = {r'psu\d+': "add_psu_sensor",
                          r'drwr\d+':"add_fan_drwr_sensor",
                          r'module\d*':"add_module_sensor",
                          r'cpu':"add_cpu_sensor",
                          r'voltmon\d+':"add_voltmon_sensor",
                          r'swb\d+_voltmon\d+': "add_swb_voltmon_sensor",
                          r'asic\d+':"add_asic_sensor",
                          r'sodimm\d+':"add_sodimm_sensor",
                          r'sensor_amb':"add_amb_sensor",
                          r'drivetemp':"add_drivetemp_sensor",
                          r'ibc\d*':"add_ibc_sensor",
                          r'ctx_amb\d*':"add_connectx_sensor",
                          r'hotswap\d+':"add_hotswap_sensor",
                          r'bmc\d+':"add_bmc_sensor",
                          r'dpu\d*_cpu':"add_DPU_cpu_sensor",
                          r'dpu\d*_sodimm\d+':"add_DPU_sodimm_sensor",
                          r'dpu\d*_drivetemp':"add_DPU_drivetemp_sensor",
                          r'dpu\d*_voltmon\d+':"add_DPU_voltmon_sensor",
                          r'dpu\d*_cx_amb':"add_DPU_cx_amb_sensor",
                          r'dpu\d *_module':"add_DPU_module"
                         }

    def __init__(self, cmd_arg, tc_logger):
        """
        @summary:
            Init  thermal algorithm
        @param params: global thermal configuration
        """
        hw_managemet_file_op.__init__(self, cmd_arg)
        self.log = tc_logger
        self.log.notice("Preinit thermal control ver {}".format(VERSION), 1)
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
        self.pwm_validate_timeout = current_milli_time() + CONST.PWM_VALIDATE_TIME * 1000
        self.state = CONST.UNCONFIGURED
        self.is_fault_state = False
        self.fan_drwr_num = 0

        signal.signal(signal.SIGTERM, self.sig_handler)
        signal.signal(signal.SIGINT, self.sig_handler)
        signal.signal(signal.SIGHUP, self.sig_handler)
        self.exit = Event()
        self.exit_flag = False

        self.load_configuration()
        if not str2bool(self.sys_config.get("platform_support", 1)):
            self.log.notice("Platform Board:'{}', SKU:'{}' is not supported.".format(self.board_type, self.sku), 1)
            self.log.notice("Set TC to idle.")
            while True:
                self.exit.wait(60)

        if not self.is_pwm_exists():
            self.log.notice("Missing PWM control (probably ASIC driver not loaded). PWM control is requiured for TC run\nWaiting for ASIC init", 1)
            while not self.is_pwm_exists():
                self.log.notice("Wait...")
                self.exit.wait(10)
            self.log.notice("PWM control activated", 1)

        # Set PWM to the default state while we are waiting for system configuration
        self.log.notice("Set FAN PWM {}".format(self.pwm_target), 1)
        if not self.write_pwm(self.pwm_target, validate=True):
            self.log.warn("PWM write validation mismatch set:{} get:{}".format(self.pwm_target, self.read_pwm()))

        if self.check_file("config/thermal_delay"):
            thermal_delay = int(self.read_file("config/thermal_delay"))
            self.log.notice("Additional delay defined in ./config/thermal_delay ({} sec).".format(thermal_delay), 1)
            timeout = current_milli_time() + 1000 * thermal_delay
            while timeout > current_milli_time():
                if not self.write_pwm(self.pwm_target):
                    self.log.info("Set PWM failed. Possible SDK is not started")
                    self.exit.wait(2)
                else:
                    self.log.info("Set PWM successful")
                    break

        if not self.is_fan_tacho_init():
            self.log.notice("Missing FAN tacho (probably ASIC not inited yet). FANs is requiured for TC run\nWaiting for ASIC init", 1)
            while not self.is_fan_tacho_init():
                self.log.notice("Wait...")
                self.exit.wait(10)

        self.log.notice("Mellanox thermal control is waiting for configuration ({} sec).".format(CONST.THERMAL_WAIT_FOR_CONFIG), 1)
        timeout = current_milli_time() + 1000 * CONST.THERMAL_WAIT_FOR_CONFIG
        while timeout > current_milli_time():
            if not self.write_pwm(self.pwm_target):
                self.log.info("Set PWM failed. Possible SDK is not started")
            self.exit.wait(2)

        self._collect_hw_info()
        self.amb_tmp = CONST.TEMP_INIT_VAL_DEF
        self.module_counter = 0
        self.gearbox_counter = 0
        self.dev_err_exclusion_conf = {}
        self.obj_init_continue = True
        self.emergency = False

    # ---------------------------------------------------------------------
    def _collect_hw_info(self):
        """
        @summary: Check and read device info from hw-management config (psu count, fan count etc...
        """
        self.max_tachos = CONST.FAN_TACHO_COUNT_DEF
        self.fan_drwr_num = CONST.FAN_DRWR_COUNT_DEF
        self.psu_count = CONST.PSU_COUNT_DEF
        self.psu_pwr_count = CONST.PSU_COUNT_DEF
        self.fan_flow_capability = CONST.UNKNOWN
        self.asic_counter = 1

        if self.check_file("config/system_flow_capability"):
            self.fan_flow_capability = self.read_file("config/system_flow_capability")

        self.log.info("Collecting HW info...")
        sensor_list = self.sys_config[CONST.SYS_CONF_SENSOR_LIST_PARAM]

        # Collect asic sensors
        try:
            self.asic_counter = int(self.read_file("config/asic_num"))
        except BaseException:
            self.log.error("Missing ASIC num config.", 1)
            sys.exit(1)

        try:
            self.max_tachos = int(self.read_file("config/max_tachos"))
            self.log.info("Fan tacho:{}".format(self.max_tachos))
        except BaseException:
            self.log.error("Missing max tachos config.", 1)
            sys.exit(1)
        # Find ASIC pci device fio
        result = subprocess.run('find /dev/mst -name "*pciconf0"', shell=True, 
                                                            check=False, 
                                                            stdout=subprocess.PIPE, 
                                                            stderr=subprocess.PIPE, 
                                                            text=True)
        # Get the output
        mst_dev = result.stdout 
        if "_pciconf0" in mst_dev:
            self.asic_pcidev = mst_dev.strip()
        else:
            self.asic_pcidev = None       

        # Collect FAN DRWR sensors
        try:
            self.fan_drwr_num = int(self.read_file("config/fan_drwr_num"))
            for drwr_idx in range(1, self.fan_drwr_num + 1):
                sensor_list.append("drwr{}".format(drwr_idx))
        except BaseException:
            self.log.error("Missing fan_drwr_num config.", 1)
            sys.exit(1)

        if self.fan_drwr_num:
            self.fan_drwr_capacity = int(self.max_tachos / self.fan_drwr_num)

        # Collect PSU sensors
        try:
            self.psu_count = int(self.read_file("config/hotplug_psus"))
            for psu_idx in range(1, self.psu_count + 1):
                sensor_list.append("psu{}".format(psu_idx))
        except BaseException:
            self.log.error("Missing hotplug_psus config.", 1)
            sys.exit(1)

        try:
            self.psu_pwr_count = int(self.read_file("config/hotplug_pwrs"))
        except BaseException:
            self.log.error("Missing hotplug_pwrs config.", 1)
            sys.exit(1)

        # Collect voltmon sensors
        file_list = os.listdir("{}/thermal".format(self.cmd_arg[CONST.HW_MGMT_ROOT]))
        for fname in file_list:
            res = re.match(r'(voltmon[0-9]+)_temp1_input', fname)
            if res:
                sensor_list.append(res.group(1))

            res = re.match(r'pwr_conv([0-9]+)_temp1_input', fname)
            if res:
                sensor_list.append("ibc{}".format(res.group(1)))

        # collect sensors based on devtree
        bom_file_data = self.read_file("config/devtree")
        if bom_file_data:
            bom_file_array = bom_file_data.split()
        else:
            bom_file_array = []
            
        try:
            for i in range(0, len(bom_file_array), 4):
                component_lines = bom_file_array[i:i+4]
                if len(component_lines) != 4:
                    break
                #component_name example: voltmon1, pwr_conv1 ...
                component_name = component_lines[3]
                res = re.match(r'(voltmon[0-9]+)', component_name)
                if res:
                    sensor_list.append(res.group(1))
    
                res = re.match(r'pwr_conv([0-9]+)', component_name)
                if res:
                    sensor_list.append("ibc{}".format(res.group(1)))
        except:
            pass

        # Add cpu sensor
        if "cpu" not in sensor_list:
            sensor_list.append("cpu")

        # Collect sodimm sensors
        for sodimm_idx in range(1, 5):
            if self.check_file("thermal/sodimm{}_temp_input".format(sodimm_idx)):
                sensor_list.append("sodimm{}".format(sodimm_idx))

        sensor_list.append("sensor_amb")

        # remove duplications & soort
        sensor_list = list(set(sensor_list))
        sensor_list.sort()

        self.log.info("Sensors enabled on system: {}".format(sensor_list))
        self.sys_config[CONST.SYS_CONF_SENSOR_LIST_PARAM] = sensor_list

    # ----------------------------------------------------------------------
    def _get_dev_obj(self, name_mask):
        """
        @summary: Get device object by it's name
        """
        for dev_obj in self.dev_obj_list:
            if re.match(name_mask, dev_obj.name):
                return dev_obj
        return None

    # ----------------------------------------------------------------------
    def _add_dev_obj(self, dev_name):
        """
        @summary: add device object by it's name
        """
        self.log.info("Add dev {}".format(dev_name))
        dev_obj = self._get_dev_obj(dev_name)
        if dev_obj:
            return dev_obj

        dev_class_name = self.sys_config[CONST.SYS_CONF_SENSORS_CONF][dev_name]["type"]
        try:
            dev_class_ = globals()[dev_class_name]
        except Exception as err:
            self.log.error("Unknown dev class {}".format(err.message))
            return None

        dev_obj = dev_class_(self.cmd_arg, self.sys_config, dev_name, self.log)
        if not dev_obj:
            self.log.error("{} create failed".format(dev_name))
            return None

        self.dev_obj_list.append(dev_obj)
        child_list = dev_obj.get_child_list()
        if child_list:
            self.add_sensors(child_list)
            self.obj_init_continue = True
        return dev_obj

    # ----------------------------------------------------------------------
    def _rm_dev_obj(self, name):
        """
        @summary: Remove device object by it's name
        """
        dev_obj = self._get_dev_obj(name)
        if dev_obj:
            self.log.info("Rm dev {}".format(name))
            self.dev_obj_list.remove(dev_obj)

    # ----------------------------------------------------------------------
    def _init_child_obj(self):
        """
        @summary: Init child pointer list for combined devices
        """
        for dev_obj in self.dev_obj_list:
            child_list = dev_obj.get_child_list()
            for child_name in  child_list:
                child_obj = self._get_dev_obj(child_name)
                if child_obj:
                    dev_obj.add_child_obj(child_obj)

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
            if re.match(r'drwr\d+', dev_obj.name):
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
    def _update_chassis_fan_speed(self, pwm_val, force=False):
        """
        @summary:
            Set chassis fan PWM
        @return: None
        """
        self.log.info("Update chassis FAN PWM {}".format(pwm_val))

        if self.emergency:
            self._set_emergency_pwm(pwm_val)
            return

        if not self.is_pwm_exists():
            self.log.warn("Missing PWM link {}".format(pwm_val))
            return
        for drwr_idx in range(1, self.fan_drwr_num + 1):
            fan_obj = self._get_dev_obj("drwr{}.*".format(drwr_idx))
            if fan_obj:
                fan_obj.set_pwm(pwm_val, force)

    # ----------------------------------------------------------------------
    def _set_emergency_pwm(self, pwm):
        ""
        self.log.notice("Set emergency PWM {}".format(pwm))
        if self.sys_config[CONST.SYS_CONF_ASIC_PARAM]["1"]["pwm_control"] is True:
            self.write_pwm_mlxreg(pwm)
        else:
            self.write_pwm(pwm)

    # ----------------------------------------------------------------------
    def _set_pwm(self, pwm, reason="", force_reason=False):
        """
        @summary: Set target PWM for the system
        @param pwm: target PWM value
        """
        if self.state == CONST.UNCONFIGURED:
            self.log.info("TC is not configureed. Try to force set PWM1 {}%".format(pwm))
            if not self.write_pwm(pwm, validate=True):
                self.log.warn("PWM write validation mismatch set:{} get:{}".format(pwm, self.read_pwm()))

            return

        pwm = int(pwm)
        if pwm > CONST.PWM_MAX:
            pwm = CONST.PWM_MAX

        if force_reason:
            self.pwm_change_reason = reason

        if pwm != self.pwm_target:
            self.pwm_change_reason = reason
            self.log.notice("PWM target changed from {} to PWM {} {}".format(self.pwm_target, pwm, reason))
            self._update_psu_fan_speed(pwm)
            self.pwm_target = pwm
            if self.pwm_worker_timer:
                self.pwm_worker_timer.start(True)
            else:
                self.pwm = pwm
                self._update_chassis_fan_speed(self.pwm)
        elif current_milli_time() > self.pwm_validate_timeout:
            self.pwm_validate_timeout = current_milli_time() + CONST.PWM_VALIDATE_TIME * 1000
            pwm_real = self.read_pwm()
            if not pwm_real:
                self.log.warn("Read PWM error. Possible hw-management is not running", 1)
                return

            if pwm_real != self.pwm:
                self.log.warn("Unexpected pwm1 value {}. Force set to {}".format(pwm_real, self.pwm))
                self._update_chassis_fan_speed(self.pwm, True)

    # ----------------------------------------------------------------------
    def _pwm_worker(self):
        ''
        if self.pwm_target == self.pwm:
            pwm_real = self.read_pwm()
            if not pwm_real:
                self.log.warn("Read PWM error. Possible hw-management is not running", 1)
                return

            if pwm_real != self.pwm:
                self.log.warn("Unexpected pwm1 value {}. Force set to {}".format(pwm_real, self.pwm))
                self._update_chassis_fan_speed(self.pwm, True)
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
    def _is_i2c_control_with_bmc(self):
        """
        @summary: return the i2c bus owner 0 for CPU  1 for BMC
        """
        if self.check_file(CONST.I2C_CTRL_FILE):
            try:
                val_str = self.read_file(CONST.I2C_CTRL_FILE)
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
            elif val == pwm_max and "total_err_cnt" in key:
                name = key
        return pwm_max, name

    # ----------------------------------------------------------------------
    def is_pwm_exists(self):
        """
        @summary: checking if PWM link exists.
        Applicable only for systems with PWM control through ASIC
        """
        ret = True
        if self.sys_config[CONST.SYS_CONF_ASIC_PARAM]["1"]["pwm_control"] is True:
            if self.read_pwm() is None:
                ret = False
        return ret

    # ----------------------------------------------------------------------
    def is_fan_tacho_init(self):
        """
        @summary: checking if fan tacho readlink exists.
        Applicable only for systems with fan_tach reading through ASIC
        """
        ret = True
        tacho_cnt = 0
        if self.sys_config[CONST.SYS_CONF_ASIC_PARAM]["1"]["fan_control"] is True:
            if self.check_file("config/max_tachos"):
                try:
                    tacho_cnt = self.read_file("config/max_tachos")
                    ret = bool(int(tacho_cnt))
                except:
                    self.log.notice("Can't read config/max_tachos. None-numeric value: {}".format(tacho_cnt))
                    ret = False
        return ret

    # ----------------------------------------------------------------------
    def _pwm_strategy_avg(self, pwm_list):
        return float(sum(pwm_list)) / len(pwm_list)

    # ----------------------------------------------------------------------
    def module_scan(self):
        """
        @summary: scanning available SFP module/gearboxes
        and dynamically adding/removing module sensors
        """
        module_count = int(self.get_file_val("config/module_counter", 0))
        if module_count != self.module_counter:
            self.log.info("Module counter changed {} -> {}".format(self.module_counter, module_count))
            module_counter = 0
            for idx in range(1, CONST.MODULE_COUNT_MAX):
                module_name = "module{}".format(idx)
                if self.check_file("thermal/{}_temp_input".format(module_name)):
                    self._sensor_add_config("thermal_module_sensor", module_name, {"base_file_name": module_name})
                    self._add_dev_obj(module_name)
                    module_counter += 1
                else:
                    self._rm_dev_obj(module_name)

            self.log.info("Modules added {} of {}".format(module_counter, module_count))
            self.module_counter = module_counter

        gearbox_count = int(self.get_file_val("config/gearbox_counter", 0))
        if gearbox_count != self.gearbox_counter:
            self.log.info("Gearbox counter changed {} -> {}".format(self.gearbox_counter, gearbox_count))
            gearbox_counter = 0
            for idx in range(1, CONST.MODULE_COUNT_MAX):
                gearbox_name = "gearbox{}".format(idx)
                if self.check_file("thermal/{}_temp_input".format(gearbox_name)):
                    self._sensor_add_config("thermal_module_sensor", gearbox_name, {"base_file_name": gearbox_name})
                    self._add_dev_obj(gearbox_name)
                    gearbox_counter += 1
                else:
                    self._rm_dev_obj(gearbox_name)

            self.log.info("Gearboxes added {} of {}".format(gearbox_counter, gearbox_count))
            self.gearbox_counter = gearbox_counter

    # ----------------------------------------------------------------------
    def sig_handler(self, sig, *_):
        """
        @summary:
            Signal handler for termination signals
        """
        if sig in [signal.SIGTERM, signal.SIGINT, signal.SIGHUP]:
            self.exit_flag = True
            self.log.close_tc_log_handler()
            if self.sys_config.get("platform_support", 1):
                self.stop(reason="SIG {}".format(sig))

            self.log.notice("Thermal control stopped", 1)
            self.log.logger_emit = False
            self.log.stop()
            os._exit(0)

    # ----------------------------------------------------------------------
    def load_configuration(self):
        """
        @summary: Init configuration table.
        """
        board_type_file = "/sys/devices/virtual/dmi/id/board_name"
        sku_file = "/sys/devices/virtual/dmi/id/product_sku"
        system_ver_file = "/sys/devices/virtual/dmi/id/product_version"
        self.board_type = "Unknown"
        self.sku = "Unknown"

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
            config_file_name = os.path.join(self.root_folder, self.cmd_arg[CONST.SYSTEM_CONFIG])
        else:
            config_file_name = os.path.join(self.root_folder, CONST.SYSTEM_CONFIG_FILE)

        if os.path.exists(config_file_name):
            with open(config_file_name) as f:
                self.log.info("Loading system config from {}".format(config_file_name))
                try:
                    sys_config = json.load(f)
                    if "name" in sys_config.keys():
                        self.log.info("System data: {}".format(sys_config["name"]))
                except Exception:
                    self.log.error("System config file {} broken.".format(config_file_name), 1)
                    sys_config["platform_support"] = 0
        else:
            self.log.warn("System config file {} missing. Platform: '{}'/'{}'/'{}' is not supported.".format(config_file_name,
                                                                                          self.board_type,
                                                                                          self.sku,
                                                                                          self.system_ver), 1)
            sys_config["platform_support"] = 0

        # 1. Init dmin table
        if CONST.SYS_CONF_DMIN not in sys_config:
            self.log.info("Dmin table missing in system_config. Using default dmin table")
            thermal_table = DMIN_TABLE_DEFAULT
            sys_config[CONST.SYS_CONF_DMIN] = thermal_table

        # 2. Init PSU fan speed vs system fan speed table
        if CONST.SYS_CONF_FAN_PWM not in sys_config:
            self.log.info("PSU fan speed vs system fan speed table missing in system_config. Set to default.")
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

        # 6. Init ASIC config
        if CONST.SYS_CONF_ASIC_PARAM not in sys_config:
            self.log.info("ASIC specific parameters table missing in system_config. Init it from local")
            sys_config[CONST.SYS_CONF_ASIC_PARAM] = ASIC_CONF_DEFAULT

        if CONST.SYS_CONF_SENSOR_LIST_PARAM not in sys_config:
            self.log.info("Static sensor list missing in system_config. Init it from local")
            sys_config[CONST.SYS_CONF_SENSOR_LIST_PARAM] = []

        if CONST.SYS_CONF_ERR_MASK not in sys_config:
            self.log.info("Dmin mask not defined in system_config. Init it from local")
            sys_config[CONST.SYS_CONF_ERR_MASK] = []

        if CONST.SYS_CONF_REDUNDANCY_PARAM not in sys_config:
            sys_config[CONST.SYS_CONF_REDUNDANCY_PARAM] = {}

        self.sys_config = sys_config

    # ----------------------------------------------------------------------
    def add_psu_sensor(self, name):
        psu_name = "{}_fan".format(name)
        in_file = name
        exclusion_conf = get_dict_val_by_path(self.sys_config, [CONST.SYS_CONF_REDUNDANCY_PARAM, CONST.PSU_ERR])
        err_mask = None
        if exclusion_conf:
            self.dev_err_exclusion_conf[CONST.PSU_ERR] = {"name_mask": "psu\d+_fan", "min_err_cnt" : 2, "curr_err_cnt" : 0}
            err_mask = exclusion_conf.get("err_mask", None)
            if not err_mask:
                err_mask = CONST.DRWR_ERR_LIST
        self._sensor_add_config("psu_fan_sensor", psu_name, {"base_file_name": in_file, "dynamic_err_mask": err_mask})

    # ----------------------------------------------------------------------
    def add_fan_drwr_sensor(self, name):
        res = re.match(r'drwr([0-9]+)', name)
        if res:
            drwr_idx = (res.group(1))

        exclusion_conf = get_dict_val_by_path(self.sys_config, [CONST.SYS_CONF_REDUNDANCY_PARAM, CONST.FAN_ERR])
        err_mask = None
        if exclusion_conf:
            self.dev_err_exclusion_conf[CONST.FAN_ERR] = {"name_mask": "drwr\d+", "min_err_cnt" : 2, "curr_err_cnt": 0}
            err_mask = exclusion_conf.get("err_mask", None)
            if not err_mask:
                err_mask = CONST.PSU_ERR_LIST
        self._sensor_add_config("fan_sensor", name, {"base_file_name": name,
                                                     "drwr_id": drwr_idx,
                                                     "tacho_cnt": self.fan_drwr_capacity,
                                                     "dynamic_err_mask": err_mask})

    # ----------------------------------------------------------------------
    def add_cpu_sensor(self, *_):
        if self.check_file("thermal/cpu_pack"):
            self._sensor_add_config("thermal_sensor", "cpu_pack", {"base_file_name": "thermal/cpu_pack"})
        elif self.check_file("thermal/cpu_core1"):
            self._sensor_add_config("thermal_sensor", "cpu_core1", {"base_file_name": "thermal/cpu_core1"})
        elif self.check_file("thermal/core_temp"):
            self._sensor_add_config("thermal_sensor", "cpu_pack", {"base_file_name": "thermal/core_temp"})
        else:
            self._sensor_add_config("thermal_sensor", "cpu_pack", {"base_file_name": "thermal/cpu_core_sensor"})

    # ----------------------------------------------------------------------
    def add_voltmon_sensor(self, name):
        in_file = "thermal/{}_temp1".format(name)
        sensor_name = "{}_temp".format(name)
        self._sensor_add_config("thermal_sensor", sensor_name, {"base_file_name": in_file})

    # ----------------------------------------------------------------------
    def add_swb_voltmon_sensor(self, name):
        in_file = "thermal/{}_temp1".format(name)
        sensor_name = "{}_temp".format(name)
        self._sensor_add_config("thermal_sensor", sensor_name, {"type": "thermal_sensor", "base_file_name": in_file, "input_suffix": "_input"})

    # ----------------------------------------------------------------------
    def add_asic_sensor(self, name):
        asic_basename = "asic" if  name == "asic1" else name
        self._sensor_add_config("thermal_asic_sensor", name, {"base_file_name": asic_basename})

    # ----------------------------------------------------------------------
    def add_sodimm_sensor(self, name):
        temp_name = "{}_temp".format(name)
        self._sensor_add_config("thermal_sensor", temp_name, {"base_file_name": "thermal/{}".format(temp_name)})

    # ----------------------------------------------------------------------
    def add_module_sensor(self, name):
        self._sensor_add_config("thermal_module_sensor", name, {"base_file_name": name})

    # ----------------------------------------------------------------------
    def add_amb_sensor(self, name):
        self._sensor_add_config("ambiant_thermal_sensor", name)

    # ----------------------------------------------------------------------
    def add_drivetemp_sensor(self, name):
        in_file = "thermal/{}".format(name)
        self._sensor_add_config("thermal_sensor", name, {"base_file_name": in_file})

    # ----------------------------------------------------------------------
    def add_ibc_sensor(self, name):
        idx = name[3:]
        in_file = "thermal/pwr_conv{}_temp1".format(idx)
        sensor_name = "{}".format(name)
        self._sensor_add_config("thermal_sensor", sensor_name, {"base_file_name": in_file})

    # ----------------------------------------------------------------------
    def add_connectx_sensor(self, name):
        self._sensor_add_config("thermal_sensor", name, {"base_file_name": "thermal/{}".format(name)})

    # ----------------------------------------------------------------------
    def add_hotswap_sensor(self, name):
        in_file = "thermal/pdb_{}_temp1".format(name)
        sensor_name = "{}_temp".format(name)
        self._sensor_add_config("thermal_sensor", sensor_name, {"base_file_name": in_file})

    # ----------------------------------------------------------------------
    def add_bmc_sensor(self, name):
        in_file = "thermal/bmc{}_temp".format(name)
        sensor_name = "{}_temp".format(name)
        self._sensor_add_config("thermal_sensor", sensor_name, {"base_file_name": in_file})

    # ----------------------------------------------------------------------
    def add_DPU_cpu_sensor(self, name):
        res = re.match(r'(dpu\d+)_cpu', name)
        if res:
            dpu_idx = res.group(1)
            self._sensor_add_config("thermal_sensor", name,
                                    {"base_file_name": "{0}/thermal/cpu_pack".format(dpu_idx)})

    # ----------------------------------------------------------------------
    def add_DPU_sodimm_sensor(self, name):
        res = re.match(r'(dpu\d+)_(sodimm\d+)', name)
        if res:
            dpu_idx = res.group(1)
            sodmm_idx = res.group(2)
            self._sensor_add_config("thermal_sensor", name,
                                    {"base_file_name": "{0}/thermal/{1}_temp_input".format(dpu_idx, sodmm_idx)})

    # ----------------------------------------------------------------------
    def add_DPU_drivetemp_sensor(self, name):
        res = re.match(r'(dpu\d+)_drivetemp', name)
        if res:
            dpu_idx = res.group(1)
            self._sensor_add_config("thermal_sensor", name,
                                    {"base_file_name": "{0}/thermal/drivetemp".format(dpu_idx)})

    # ----------------------------------------------------------------------
    def add_DPU_voltmon_sensor(self, name):
        res = re.match(r'(dpu\d+)_(voltmon\d+)', name)
        if res:
            dpu_idx = res.group(1)
            voltmon_name = res.group(2)
            sensor_name = "{}_temp".format(name)
            in_file = "{}/thermal/{}_temp1".format(dpu_idx, voltmon_name)
            self._sensor_add_config("thermal_sensor", sensor_name, {"base_file_name": in_file})

    # ----------------------------------------------------------------------
    def add_DPU_cx_amb_sensor(self, name):
        res = re.match(r'(dpu\d+)_cx_amb', name)
        if res:
            dpu_idx = res.group(1)
            self._sensor_add_config("thermal_sensor", name,
                                    {"base_file_name": "{0}/thermal/cx_amb".format(dpu_idx)})

    # ----------------------------------------------------------------------
    def add_DPU_module(self, name):
        res = re.match(r'dpu(\d+)_module', name)
        if res:
            dpu_idx = res.group(1)
            self._sensor_add_config("dpu_module", name,
                                    {"base_file_name": "system/dpu{}_ready".format(dpu_idx)})

    # ----------------------------------------------------------------------
    def add_sensors(self, sensor_list):
        """
        @summary: Add sensor configuration based on sensor list
        """
        for sensor_name in sensor_list:
            for config_handler_mask in self.ADD_SENSOR_HANDLER:
                if re.match(config_handler_mask, sensor_name):
                    fn_name = self.ADD_SENSOR_HANDLER[config_handler_mask]
                    init_fn = getattr(self, fn_name)
                    init_fn(sensor_name)

    # ----------------------------------------------------------------------
    def init(self):
        """
        @summary: Init thermal-control main
        """
        self.log.notice("********************************", 1)
        self.log.notice("Init thermal control ver: v.{}".format(VERSION), 1)
        self.log.notice("********************************", 1)

        self.add_sensors(self.sys_config[CONST.SYS_CONF_SENSOR_LIST_PARAM])

        # Set initial PWM to maximum
        self._set_pwm(CONST.PWM_MAX, reason="Set initial PWM")

        self.log.debug("System config dump\n{}".format(json.dumps(self.sys_config, sort_keys=True, indent=4)))

        while self.obj_init_continue:
            self.obj_init_continue = False
            sys_config = dict(self.sys_config[CONST.SYS_CONF_SENSORS_CONF])
            for key, _ in sys_config.items():
                dev_obj = self._add_dev_obj(key)
                if not dev_obj:
                    self.log.error("{} create failed".format(key))
                    sys.exit(1)
        self.module_scan()
        self._init_child_obj()

        self.dev_obj_list.sort(key=lambda x: x.name)
        self.write_file(CONST.PERIODIC_REPORT_FILE, self.periodic_report_time)

    # ----------------------------------------------------------------------
    def start(self, reason=""):
        """
        @summary: Start sensor service.
        Used when suspend mode was de-asserted
        """

        if self.state != CONST.RUNNING:
            self.log.notice("Thermal control state changed {} -> {} reason:{}".format(self.state, CONST.RUNNING, reason), 1)
            self.state = CONST.RUNNING
            self.emergency = False

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    dev_obj.start()

            # get FAN max reduction from any of FAN
            fan_obj = self._get_dev_obj(r'drwr\d+')
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

            self.write_file("config/thermal_enforced_full_spped", "0\n")   

    # ----------------------------------------------------------------------
    def stop(self, reason=""):
        """
        @summary: Stop sensor service and set PWM to PWM-MAX.
        Used when suspend mode was de-asserted or when kill signal was revived
        """
        if self.state != CONST.STOPPED:
            if self.pwm_worker_timer:
                self.pwm_worker_timer.stop()
                self.pwm_worker_timer = None

            if self.periodic_report_worker_timer:
                self.periodic_report_worker_timer.stop()
                self.periodic_report_worker_timer = None

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    dev_obj.stop()

            self.log.notice("Thermal control state changed {} -> {} reason:{}".format(self.state, CONST.STOPPED, reason), 1)
            self.state = CONST.STOPPED
            self._set_pwm(CONST.PWM_MAX, reason="TC stop")
            self.log.notice("Set FAN PWM {}".format(self.pwm_target), 1)

    # ----------------------------------------------------------------------
    def run(self):
        """
        @summary:  main thermal control loop
        """
        fault_cnt_old = 0
        fault_cnt = 0
        self.log.notice("********************************", 1)
        self.log.notice("Thermal control is running", 1)
        self.log.notice("********************************", 1)
        module_scan_timeout = 0
        # main loop
        while not self.exit.is_set() or not self.exit_flag:
            try:
                log_level = int(self.read_file(CONST.LOG_LEVEL_FILENAME))
                if log_level != self.cmd_arg["verbosity"]:
                    self.cmd_arg["verbosity"] = log_level
                    self.log.set_loglevel(self.cmd_arg["verbosity"])
            except BaseException:
                pass

            if self.emergency:
                self.exit.wait(5)
                continue

            if not self.is_fan_tacho_init():
                self.stop(reason="Missing FANs")
                self.exit.wait(5)
                continue

            if not self.is_pwm_exists():
                self.stop(reason="Missing PWM")
                self.exit.wait(5)
                continue

            if self._is_i2c_control_with_bmc():
                self.stop(reason="BMC has taken over i2c bus")
                self.exit.wait(30)
                continue

            if self._is_suspend():
                self.stop(reason="suspend")
                self.exit.wait(5)
                continue
            else:
                self.start(reason="resume")

            if current_milli_time() >= module_scan_timeout:
                self.module_scan()
                module_scan_timeout = current_milli_time() + 30 * 1000

            pwm_list = {}
            # set maximum next poll timestump = 60 seec
            timestump_next = current_milli_time() + 60 * 1000

            # collect errors
            curr_timestamp = current_milli_time()

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    if curr_timestamp >= dev_obj.get_timestump():
                        # process sensors
                        dev_obj.handle_input(self.sys_config[CONST.SYS_CONF_DMIN], self.system_flow_dir, self.amb_tmp)
                        dev_obj.collect_err()
                        if dev_obj.name == "sensor_amb":
                            self.amb_tmp = dev_obj.get_value()

            total_err_count = 0
            for name, conf in self.dev_err_exclusion_conf.items():
                conf["curr_err_cnt"] = 0
                conf["skip_err"] = False

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    if dev_obj.state != CONST.RUNNING:
                        continue
                    fault_list = dev_obj.get_fault_list_static_filtered()
                    if not fault_list:
                        continue
                    else:
                        if CONST.EMERGENCY in fault_list:
                            self.emergency = True
                            break
                        fault_cnt = dev_obj.get_fault_cnt()
                        total_err_count += fault_cnt

                    dynamic_fault_list = dev_obj.get_fault_list_dynamic()
                    if not dynamic_fault_list:
                        continue

                    for name, conf in self.dev_err_exclusion_conf.items():
                        # don't need to check if min error not set
                        min_num = conf.get("min_err_cnt", 0)
                        if not min_num:
                            continue
                        name_mask = conf["name_mask"]

                        # matched with dev name
                        if re.match(name_mask, dev_obj.name):
                            # optional mask for specific error
                            conf["curr_err_cnt"] += 1
                            # if current err count >= than set in min config
                            conf["skip_err"] = (conf["curr_err_cnt"] < min_num)
                            if conf["skip_err"]:
                                total_err_count -= fault_cnt

            if self.emergency:
                self.stop("Emergency stop {}".format(name))
                self.write_file("config/thermal_enforced_full_spped", "1\n")
                continue

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    if curr_timestamp >= dev_obj.get_timestump():
                        # process sensors
                        for name, conf in self.dev_err_exclusion_conf.items():
                            name_mask = conf["name_mask"]
                            # if exists min err rule for current device
                            if re.match(name_mask, dev_obj.name):
                                dev_obj.set_dynamic_filter_ena(conf["skip_err"])

                        dev_obj.handle_err(self.sys_config[CONST.SYS_CONF_DMIN], self.system_flow_dir, self.amb_tmp)
                        if dev_obj.name == "sensor_amb":
                            self.amb_tmp = dev_obj.get_value()
                        dev_obj.update_timestump()

                    pwm = dev_obj.get_pwm()
                    self.log.debug("{0:25}: PWM {1}".format(dev_obj.name, pwm))
                    pwm_list[dev_obj.name] = pwm

                    obj_timestump = dev_obj.get_timestump()
                    timestump_next = min(obj_timestump, timestump_next)

            if total_err_count >= CONST.TOTAL_MAX_ERR_COUNT:
                pwm_list["total_err_cnt({})>={}".format(total_err_count, CONST.TOTAL_MAX_ERR_COUNT)] = CONST.PWM_MAX
                force_reason = True
            elif fault_cnt_old >= CONST.TOTAL_MAX_ERR_COUNT:
                self.log.info("'total_err_cnt>2' error flag clear")
                force_reason = True
            else:
                force_reason = False
            fault_cnt_old = total_err_count

            pwm, name = self._pwm_get_max(pwm_list)
            self.log.debug("Result PWM {}".format(pwm))
            self._set_pwm(pwm, reason=name, force_reason=force_reason)

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
            if amb_tmp == CONST.AMB_TEMP_ERR_VAL:
                amb_tmp = "N/A"
            flow_dir = self.system_flow_dir
        else:
            amb_tmp = "-"
            flow_dir = "-"

        asic_info = ""
        for asic_idx in range(1, self.asic_counter + 1):
            asic_name = "asic{}".format(asic_idx)
            asic_obj = self._get_dev_obj(asic_name)
            if asic_obj:
                asic_tmp = asic_obj.get_value()
            else:
                asic_tmp = "N/A"
            asic_info += " {} {},".format(asic_name, asic_tmp)

        self.log.info("Thermal periodic report")
        self.log.info("================================")
        self.log.info("Temperature(C):{} amb {}".format(asic_info, amb_tmp))
        self.log.info("Cooling(%) {} (max pwm source:{})".format(self.pwm_target, self.pwm_change_reason))
        self.log.info("dir:{}".format(flow_dir))
        self.log.info("================================")
        for dev_obj in self.dev_obj_list:
            if dev_obj.enable:
                obj_info_str = dev_obj.info()
                if obj_info_str:
                    self.log.info(obj_info_str)
        self.log.info("================================")


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
    logger = Logger(args[CONST.LOG_USE_SYSLOG], args[CONST.LOG_FILE], args["verbosity"])
    thermal_management = None
    try:
        thermal_management = ThermalManagement(args, logger)
        thermal_management.init()
        thermal_management.start(reason="init")
        thermal_management.run()
    except BaseException as e:
        logger.info(traceback.format_exc())
        if thermal_management:
            thermal_management.stop(reason="crash ({})".format(str(e)))
        sys.exit(1)

    sys.exit(0)
