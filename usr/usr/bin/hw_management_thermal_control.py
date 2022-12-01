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
    SENSORS_CONFIG = "sensors_config"

    # File which defined current level filename.
    # User can dynamically change loglevel without TC restarting.
    LOG_LEVEL_FILENAME = "config/tc_log_level"

    # Fan direction string alias
    #fan dir:
    # 0: port > fan, dir fan->port C2P  Port t change not affect
    # 1: port < fan, dir port->fan P2C  Fan t change not affect
    C2P = "C2P"
    P2C = "P2C"

    # Sensor files for ambiant temperature measurement 
    FAN_SENS = "thermal/fan_amb"
    PORT_SENS = "thermal/port_amb"

    # thermal zone types
    UNKNOWN = "Unknown"
    TRUST_TYPE = "trusted"
    UNTRUST_TYPE = "untrusted"

    # default hw-management folder
    HW_MGMT_FOLDER_DEF = "/var/run/hw-management"

    # suspend control file path
    SUSPEND_FILE = "config/suspend"

    # Default period for printing TC report (in sec.)
    PERIODIC_REPORT_TIME = 5 * 60
    # File which define TC report period. TC should be restarted to apply changes in this file
    PERIODIC_REPORT_FILE = "config/periodic_report"

    # Default sensor configuration if not 0configured other value
    SENSOR_POLL_TIME_DEF = 3
    TEMP_INIT_DEF = 25
    TEMP_SENSOR_SCALE = 1000.0
    TEMP_MIN_MAX = {"val_min": 35000, "val_max": 65000}
    RPM_MIN_MAX = {"val_min": 5000, "val_max": 25000}

    # Max/min PWM value - global for all system
    PWM_MIN = 20
    PWM_MAX = 100
    PWM_HYSTERESIS_DEF = 0

    ### FAN calibration
    # Time for FAN rotation stabilize after change
    FAN_RELAX_TIME = 10
    # Cycles for FAN speed calibration at 100%.
    # FAN RPM value will be averaged  by reading by several(FAN_CALIBRATE_CYCLES) readings 
    FAN_CALIBRATE_CYCLES = 2

    ### PWM smoothing
    DMIN_PWM_STEP_MIN = 2
    # PWM smoothing in time
    PWM_INC_STEP_MAX = 8
    PWM_WORKET_POLL_TIME = 2

    # default system devices
    PSU_COUNT_DEF = 2
    FAN_DRWR_COUNT_DEF = 6
    FAN_TACHO_COUNT_DEF = 6
    MODULE_COUNT_DEF = 16
    GEARBOX_COUNT_DEF = 0

    # Consistent file read  errors for set error state
    SENSOR_FREAD_FAIL_TIMES = 3

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
pwm_hyst - hysteresis for PWM value change. PWM value for thermal sensor can be calculated by the formula:
    pwm = pwm_min + ((value - val_min) / (val_max - val_min)) * (pwm_max - pwm_min)
input_smooth_level - soothing level for sensor input value reading. Formula to calculate avg:
    avg_acc -= avg_acc/input_smooth_level
    avg_acc = last_value + avg_acc
    avg = ang_acc / input_smooth_level
"""

SENSOR_DEF_CONFIG = {
    r'psu\d+_fan': {"type": "psu_fan_sensor", "input_suffix": "_fan1_speed_get", "poll_time": 30},
    r'fan\d+': {"type": "fan_sensor", "poll_time": 30},
    r'mlxsw-module\d+': {"type": "thermal_module_sensor", "val_min":60000, "val_max":80000, "poll_time": 20, "refresh_attr_period": 30 * 60},
    r'mlxsw-gearbox\d+': {"type": "thermal_module_sensor", "val_min":60000, "val_max":80000, "poll_time": 20, "refresh_attr_period": 30 * 60},
    r'mlxsw': {"type": "thermal_module_sensor", "poll_time": 3},
    r'(cpu_pack|cpu_core\d+)': {"type": "thermal_sensor", "val_min": 50000, "val_max": 90000, "poll_time": 3, "pwm_hyst" : 5, "input_smooth_level": 3},
    r'sodimm\d_temp': {"type": "thermal_sensor", "input_suffix": "_input", "val_min_override": 50000, "val_max": 85000, "poll_time": 10, "input_smooth_level": 2},
    r'pch': {"type": "thermal_sensor", "input_suffix": "_temp", "val_min": 50000, "val_max": 85000, "poll_time": 10, "pwm_hyst" : 3, "input_smooth_level": 2},
    r'comex_amb': {"type": "thermal_sensor", "val_min": 45000, "val_max": 85000, "poll_time": 3},
    r'sensor_amb': {"type": "ambiant_thermal_sensor", "file_in_dict": {CONST.C2P: CONST.FAN_SENS, CONST.P2C: CONST.PORT_SENS}, "poll_time": 10},
    r'psu\d+_temp': {"type": "thermal_sensor", "val_min": 45000, "val_max":  85000, "poll_time": 30}
}

#############################
# System definition table
############################
fan_err_default = {
    "tacho": {"-127:120": 100},
    "present": {"-127:120": 100},
    "fault": {"-127:120": 100},
    "direction": {"-127:120": 100}
}

psu_err_default = {
    "present": {"-127:120": 100},
    "direction": {"-127:120": 100},
    "fault": {"-127:120": 100},
}

sensor_read_err_default = {"-127:120": 100}

TABLE_DEFAULT = {
    "name": "default",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:120": 60},
        CONST.UNTRUST_TYPE: {"-127:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:120": 60},
        CONST.UNTRUST_TYPE: {"-127:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:120": 60},
        CONST.UNTRUST_TYPE: {"-127:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t1 for MSN27*|MSN24*
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        30    30    30    30    30    30
#   0-5        30    30    30    30    30    30
#  5-10        30    30    30    30    30    30
# 10-15        30    30    30    30    30    30
# 15-20        30    30    30    30    30    30
# 20-25        30    30    40    40    40    40
# 25-30        30    40    50    50    50    50
# 30-35        30    50    60    60    60    60
# 35-40        30    60    60    60    60    60
# 40-45        50    60    60    60    60    60
TABLE_CLASS1 = {
    "name": "class 1",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:20": 30, "21:25": 40, "26:30": 50, "31:120": 60},
        CONST.UNTRUST_TYPE: {"-127:20": 30, "21:25": 40, "26:30": 50, "31:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:40": 30, "41:120": 50},
        CONST.UNTRUST_TYPE: {"-127:25": 30, "26:30": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:25": 30, "26:30": 40, "31:35": 50, "36:120": 60},
        CONST.UNTRUST_TYPE: {"-127:25": 30, "26:30": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t2 for MSN21*
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    20    20    20    20    20
# 10-15        20    20    20    20    20    20
# 15-20        20    30    20    20    20    30
# 20-25        20    30    20    20    20    30
# 25-30        20    40    20    20    20    40
# 30-35        20    50    20    20    20    50
# 35-40        20    60    20    20    20    60
# 40-45        20    60    30    30    30    60
TABLE_CLASS2 = {
    "name": "class 2",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:40": 20, "41:120": 30},
        CONST.UNTRUST_TYPE: {"-127:40": 20, "41:120": 30},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:15": 20, "16:25": 30, "26:31": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:40": 20, "41:120": 30},
        CONST.UNTRUST_TYPE: {"-127:15": 20, "16:25": 30, "26:31": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t3 for MSN274*
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        30    30    30    30    30    30
#   0-5        30    30    30    30    30    30
#  5-10        30    30    30    30    30    30
# 10-15        30    30    30    30    30    30
# 15-20        30    30    30    40    30    40
# 20-25        30    30    30    40    30    40
# 25-30        30    30    30    40    30    40
# 30-35        30    30    30    50    30    50
# 35-40        30    40    30    70    30    70
# 40-45        30    50    30    70    30    70
TABLE_CLASS3 = {
    "name": "class 3",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:120": 30},
        CONST.UNTRUST_TYPE: {"-127:15": 30, "16:30": 40, "31:35": 50, "36:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:120": 30},
        CONST.UNTRUST_TYPE: {"-127:35": 30, "36:40": 40, "41:120": 50},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:120": 30},
        CONST.UNTRUST_TYPE: {"-127:15": 30, "16:30": 40, "31:35": 50, "36:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t4 for MSN201*
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    20    20    20    20    20
# 10-15        20    20    20    20    20    20
# 15-20        20    30    20    20    20    30
# 20-25        20    40    20    30    20    40
# 25-30        20    40    20    40    20    40
# 30-35        20    50    20    50    20    50
# 35-40        20    60    20    60    20    60
# 40-45        20    60    20    60    20    60

TABLE_CLASS4 = {
    "name": "class 4",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:20": 20, "21:25": 30, "26:30": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:15": 20, "16:20": 30, "21:30": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:15": 20, "16:20": 30, "21:30": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t5 for MSN3700|MQM8700
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    20    20    20    20    20
# 10-15        20    20    20    20    20    20
# 15-20        20    30    20    20    20    30
# 20-25        20    30    20    20    20    30
# 25-30        30    30    30    30    30    30
# 30-35        30    40    30    30    30    40
# 35-40        30    50    30    30    30    50
# 40-45        40    60    40    40    40    60
TABLE_CLASS5 = {
    "name": "class 5",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:25": 20, "26:40": 30, "41:120": 40},
        CONST.UNTRUST_TYPE: {"-127:25": 20, "26:40": 30, "41:120": 40},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:26": 20, "26:40": 30, "41:120": 40},
        CONST.UNTRUST_TYPE: {"-127:15": 20, "16:30": 30, "31:35": 40, "36:40": 40, "41:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:26": 20, "26:40": 30, "41:120": 40},
        CONST.UNTRUST_TYPE: {"-127:15": 20, "16:30": 30, "31:35": 40, "36:40": 40, "41:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t6 for MSN3700C
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    20    20    20    20    20
# 10-15        20    30    20    20    20    30
# 15-20        20    30    20    20    20    30
# 20-25        20    40    20    20    20    40
# 25-30        20    40    20    20    20    40
# 30-35        20    50    20    20    20    50
# 35-40        20    60    20    30    20    60
# 40-45        30    60    20    40    30    60

TABLE_CLASS6 = {
    "name": "class 6",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:35": 20, "36:40": 30, "41:120": 40},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:40": 20, "41:120": 30},
        CONST.UNTRUST_TYPE: {"-127:10": 20, "11:20": 30, "21:30": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:40": 30, "41:120": 30},
        CONST.UNTRUST_TYPE: {"-127:10": 20, "11:20": 30, "21:30": 40, "31:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t7 for MSN3800
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    30    20    20    20    30
#  5-10        20    30    20    20    20    30
# 10-15        20    40    20    20    20    40
# 15-20        20    50    20    20    20    50
# 20-25        20    60    20    30    20    60
# 25-30        20    60    20    30    20    60
# 30-35        20    60    30    40    30    60
# 35-40        30    70    30    50    30    70
# 40-45        30    70    40    60    40    70
TABLE_CLASS7 = {
    "name": "class 7",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:30": 20, "31:40": 30, "41:120": 40},
        CONST.UNTRUST_TYPE: {"-127:20": 20, "21:30": 30, "31:40": 40, "41:45": 50, "46:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:35": 20, "36:120": 30},
        CONST.UNTRUST_TYPE: {"-127:0": 20, "1:10": 30, "11:15": 40, "16:20": 50, "21:35": 60, "36:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:30": 20, "31:40": 30, "41:120": 40},
        CONST.UNTRUST_TYPE: {"-127:0": 20, "1:10": 30, "11:15": 40, "16:20": 50, "21:35": 60, "36:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t8 for MSN4600
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    30    20    20    20    30
# 10-15        20    30    20    20    20    30
# 15-20        20    30    20    20    20    30
# 20-25        20    40    20    20    20    40
# 25-30        20    40    20    20    20    40
# 30-35        20    50    20    30    20    50
# 35-40        20    60    20    30    20    60
# 40-45        20    70    30    40    30    70
TABLE_CLASS8 = {
    "name": "class 8",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:40": 20, "41:120": 30},
        CONST.UNTRUST_TYPE: {"-127:30": 20, "31:40": 30, "41:120": 40},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:5": 20, "6:20": 30, "21:30": 40, "31:35": 50, "36:40": 60, "41:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:40": 20, "41:120": 30},
        CONST.UNTRUST_TYPE: {"-127:5": 20, "6:20": 30, "21:30": 40, "31:35": 50, "36:40": 60, "41:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t9 for MSN3420
# Direction    P2C        C2P        Unknown

#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    20    20    20    20    20
# 10-15        20    20    20    20    20    20
# 15-20        20    20    20    20    20    20
# 20-25        20    20    20    20    20    20
# 25-30        20    30    20    20    20    30
# 30-35        20    30    20    20    20    30
# 35-40        20    40    20    20    20    40
# 40-45        20    60    20    40    20    60
TABLE_CLASS9 = {
    "name": "class 9",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:40": 20, "41:120": 40},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:25": 20, "26:35": 30, "36:40": 40, "41:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:25": 20, "26:35": 30, "36:40": 40, "41:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t10 for MSN4700
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    20    20    20    20    20
# 10-15        20    20    20    20    20    20
# 15-20        20    20    20    20    20    20
# 20-25        20    20    20    20    20    20
# 25-30        20    20    20    20    20    20
# 30-35        20    20    20    20    20    20
# 35-40        50    50    50    50    50    50
# 40-45        50    50    50    50    50    50

TABLE_CLASS10 = {
    "name": "class 10",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:35": 20, "36:120": 50},
        CONST.UNTRUST_TYPE: {"-127:35": 20, "36:120": 50},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:35": 20, "36:120": 50},
        CONST.UNTRUST_TYPE: {"-127:35": 20, "36:120": 50},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:35": 20, "36:120": 50},
        CONST.UNTRUST_TYPE: {"-127:35": 20, "36:120": 50},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t11 for SN2201.
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        30    30    30    30    30    30
#   0-5        30    30    30    30    30    30
#  5-10        30    30    30    30    30    30
# 10-15        30    30    30    30    30    30
# 15-20        30    40    30    30    30    40
# 20-25        30    50    30    40    30    50
# 25-30        30    60    30    50    30    60
# 30-35        40    70    30    60    40    70
# 35-40        50    80    40    70    50    80
# 40-45        60    90    50    80    60    90
TABLE_CLASS11 = {
    "name": "class 11",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:35": 30, "36:40": 40, "41:120": 50},
        CONST.UNTRUST_TYPE: {"-127:20": 30, "21:25": 40, "26:30": 50, "31:35": 60, "36:40": 70, "41:120": 80},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:30": 30, "31:35": 40, "36:40": 50, "41:120": 60},
        CONST.UNTRUST_TYPE: {"-127:15": 30, "16:20": 40, "21:25": 50, "26:30": 60, "31:35": 70, "41:45": 80, "46:120": 90},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:30": 30, "31:35": 40, "36:40": 50, "41:120": 60},
        CONST.UNTRUST_TYPE: {"-127:15": 30, "16:20": 40, "21:25": 50, "26:30": 60, "31:35": 70, "41:45": 80, "46:120": 90},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t12 for MSN4600
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    30    20    20    20    30
# 10-15        20    30    20    20    30    30
# 15-20        20    40    30    30    30    40
# 20-25        20    40    30    30    30    40
# 25-30        20    50    30    40    30    50
# 30-35        20    60    30    40    30    60
# 35-40        20    70    40    60    40    70
# 40-45        20    70    40    60    40    70
TABLE_CLASS12 = {
    "name": "class 12",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:15": 20, "16:35": 30, "36:120": 40},
        CONST.UNTRUST_TYPE: {"-127:15": 20, "16:25": 30, "26:35": 40, "41:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:5": 20, "6:15": 30, "16:25": 40, "26:30": 50, "36:40": 60, "41:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:15": 20, "16:35": 30, "36:120": 40},
        CONST.UNTRUST_TYPE: {"-127:5": 20, "6:15": 30, "16:25": 40, "26:30": 50, "36:40": 60, "41:120": 70},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t13 for MSN4800
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        20    20    20    20    20    20
#   0-5        20    20    20    20    20    20
#  5-10        20    30    20    20    20    30
# 10-15        20    30    20    20    20    30
# 15-20        20    30    20    20    20    30
# 20-25        20    40    20    20    20    40
# 25-30        30    50    20    20    30    50
# 30-35        30    50    20    20    30    50
# 35-40        40    60    20    20    40    60

TABLE_CLASS13 = {
    "name": "class 13",
    CONST.C2P: {
        CONST.TRUST_TYPE: {"-127:120": 20},
        CONST.UNTRUST_TYPE: {"-127:120": 20},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:25": 20, "26:30": 30, "31:120": 40},
        CONST.UNTRUST_TYPE: {"-127:5": 20, "6:20": 30, "21:25": 40, "26:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:25": 20, "26:30": 30, "31:120": 40},
        CONST.UNTRUST_TYPE: {"-127:5": 20, "6:20": 30, "21:25": 40, "26:35": 50, "36:120": 60},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

# Class t14 for SN5600.
# ToDo This is preBU setting, just as placeholder
# Actual info should be provided aftyer tests on real system with ASIC.
# Direction    P2C        C2P        Unknown
#--------------------------------------------------------------
# Amb [C]    copper/    AOC W/O copper/    AOC W/O    copper/    AOC W/O
#        sensors    sensor    sensor    sensor    sensor    sensor
#--------------------------------------------------------------
#    <0        30    30    30    30    30    30
#   0-5        30    30    30    30    30    30
#  5-10        30    30    30    30    30    30
# 10-15        30    30    30    30    30    30
# 15-20        30    40    30    30    30    40
# 20-25        30    50    30    40    30    50
# 25-30        30    60    30    50    30    60
# 30-35        40    70    30    60    40    70
# 35-40        50    80    40    70    50    80
# 40-45        60    90    50    80    60    90

TABLE_CLASS14 = {
    "name": "class 14",
    CONST.C2P: {
        CONST.TRUST_TYPE:{"-127:35": 30, "36:40": 40, "41:120": 50},
        CONST.UNTRUST_TYPE: {"-127:20": 30, "21:25": 40, "26:30": 50, "31:35": 60, "36:40": 70, "41:120": 80},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.P2C: {
        CONST.TRUST_TYPE: {"-127:30": 30, "31:35": 40, "36:40": 50, "41:120": 60},
        CONST.UNTRUST_TYPE: {"-127:15": 30, "16:20": 40, "21:25": 50, "26:30": 60, "31:35": 70, "36:40": 80, "41:120": 90},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
        CONST.TRUST_TYPE: {"-127:30": 30, "31:35": 40, "36:40": 50, "41:120": 60},
        CONST.UNTRUST_TYPE:  {"-127:15": 30, "16:20": 40, "21:25": 50, "26:30": 60, "31:35": 70, "36:40": 80, "41:120": 90},
        "fan_err": fan_err_default,
        "psu_err": psu_err_default
    },
    "sensor_err" :sensor_read_err_default
}

THERMAL_TABLE_LIST = {
    "default": TABLE_DEFAULT,
    r'(MSN27\d+)|(MSN24\d+)|(tc_t1)': TABLE_CLASS1,
    r'(MSN21\d+)': TABLE_CLASS2,
    r'MSN274\d+': TABLE_CLASS3,
    r"(MSN201\d)|(tc_t4)": TABLE_CLASS4,
    r"(MSN3700)|(MQM8700)|(tc_t5)": TABLE_CLASS5,
    r"(MSN3700C)|(tc_t6)": TABLE_CLASS6,
    r"(MSN3800)|(tc_t7)": TABLE_CLASS7,
    r"(MSN4600C)|(tc_t8)": TABLE_CLASS8,
    r"(MSN3420)|(tc_t9)": TABLE_CLASS9,
    r"(MSN4700)|(tc_t10)": TABLE_CLASS10,
    r"(SN2201)|(tc_t11)": TABLE_CLASS11,
    r"(MSN4600C)|(tc_t12)": TABLE_CLASS12,
    r"(MSN4800)|(tc_t13)": TABLE_CLASS13,
    r"(MSN5600)|(tc_t14)": TABLE_CLASS14
}


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


def current_milli_time():
    """
    @summary:
        get current time in milliseconds
    @return: int value time in milliseconds
    """
    return round(time.time() * 1000)


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


def g_get_dmin_range(line, temp):
    """
    @summary: Searching temperature range which is match input temp and returning corresponding PWM value in
    @param line: dict with temp ranges and PWM values
        Example: {"-127:20":30, "21:25":40 , "26:30":50, "31:120":60},
    @param temp: target temperature
    @return: PWM value
    """
    for key, val in line.items():
        t_range = key.split(":")
        t_min = int(t_range[0])
        t_max = int(t_range[1])
        if t_min <= temp <= t_max:
            return val, t_min, t_max
    return None, None, None


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
        return CONST.PWM_MAX
    # get current range
    dmin, range_min, range_max = g_get_dmin_range(line, temp)
    if not interpolated:
        return dmin

    # get range of next step
    dmin_next, _, _ = g_get_dmin_range(line, range_max + 1)
    # reached maximum range
    if dmin_next is None:
        return dmin

    # calculate smooth step
    start_smooth_change_position = range_max - (dmin_next - dmin) / CONST.DMIN_PWM_STEP_MIN + 1
    if temp < start_smooth_change_position:
        return dmin
    elif start_smooth_change_position < range_min:
        step = float(dmin_next - dmin) / float(range_max + 1 - range_min)
    else:
        step = CONST.DMIN_PWM_STEP_MIN
    dmin = dmin_next - ((range_max - temp) * step)
    return int(dmin)


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
                self.logger_fh = RotatingFileHandler(log_file, maxBytes=(5 * 1024) * 1024, backupCount=2)

            self.logger_fh.setFormatter(formatter)
            self.logger_fh.setLevel(verbosity)
            self.logger.addHandler(self.logger_fh)

        if use_syslog:
            if sys.platform == "darwin":
                address = "/var/run/syslog"
            elif sys.platform == "linux2":
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
    def thermal_read_file_int(self, filename):
        """
        @summary:
            read file from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @return: int value from file
        """
        val = self.read_file(os.path.join("thermal", filename))
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

    def rm_file(self, filename):
        """
        @summary:
            remove file in hw-management tree.
        @param filename: file to remove {hw-management-folder}/filename
        @param data: data to write
        """
        filename = os.path.join(self.root_folder, filename)
        os.remove(filename)



class system_device(hw_managemet_file_op):
    """
    @summary: base class for system sensors
    """
    def __init__(self, config, dev_config_dict, logger):
        hw_managemet_file_op.__init__(self, config)
        self.log = logger
        self.sensors_config = dev_config_dict
        self.name = dev_config_dict["name"]
        self.type = dev_config_dict["type"]
        self.log.info("Init {0} ({1})".format(self.name, self.type))
        self.base_name = self.sensors_config.get("base_name", None)
        self.enable = int(self.sensors_config.get("enable", 1))
        self.input_smooth_level = self.sensors_config.get("input_smooth_level", 1)
        self.poll_time = int(self.sensors_config.get("poll_time", CONST.SENSOR_POLL_TIME_DEF))
        self.update_timestump(1000)
        self.value = CONST.TEMP_INIT_DEF
        self.value_acc = self.value * self.input_smooth_level
        self.pwm = CONST.PWM_MIN
        self.last_pwm = self.pwm
        self.pwm_hysteresis = int(self.sensors_config.get("pwm_hyst", CONST.PWM_HYSTERESIS_DEF))
        self.set_trusted(True)
        self.state = CONST.STOPPED
        self.err_fread_max = CONST.SENSOR_FREAD_FAIL_TIMES
        self.err_fread_err_counter_dict = {}
        self.pwm_min = CONST.PWM_MIN
        self.pwm_max = CONST.PWM_MAX
        self.val_min = CONST.TEMP_MIN_MAX["val_min"]
        self.val_max = CONST.TEMP_MIN_MAX["val_max"]

    # ----------------------------------------------------------------------
    def start(self):
        """
        @summary: Start device service.
        Reload reloads values which can be changed and preparing to run
        """
        if self.state == CONST.RUNNING:
            return
        self.log.info("Staring {}".format(self.name))
        self.state = CONST.RUNNING
        self.pwm_min = int(self.sensors_config.get("pwm_min", CONST.PWM_MIN))
        self.pwm_max = int(self.sensors_config.get("pwm_max", CONST.PWM_MAX))
        self.val_min = CONST.TEMP_MIN_MAX["val_min"]
        self.val_max = CONST.TEMP_MIN_MAX["val_max"]
        self.poll_time = int(self.sensors_config.get("poll_time", CONST.SENSOR_POLL_TIME_DEF))
        self.enable = int(self.sensors_config.get("enable", 1))
        self.value_acc = self.value * self.input_smooth_level
        self.err_fread_err_counter_dict = {}
        self.sensor_configure()
        self.update_timestump(1000)

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
            if val > self.err_fread_max:
                self.log.error("{}: read file {} errors count {}".format(self.name, key, val))
                err_keys.append(key)
        return err_keys

    # ----------------------------------------------------------------------
    def get_pwm(self):
        """
        @summary: Return pwm value
         calculated for this sensor
        """
        pwm_diff = abs(self.last_pwm - self.pwm)
        if pwm_diff >= self.pwm_hysteresis:
            self.last_pwm = self.pwm
        return self.last_pwm

    # ----------------------------------------------------------------------
    def get_value(self):
        """
        @summary: Return sensor value. Value type depends from sensor type and can be: Celsius degree, rpm, ...
        """
        return self.value

    # ----------------------------------------------------------------------
    def get_timestump(self):
        """
        @summary:  return time when this sensor should be serviced
        """
        return self.poll_time_next

    # ----------------------------------------------------------------------
    def is_trusted(self):
        """
        @summary: Return True/False if sensor is trusted/not trusted
        """
        return True if self.trusted == CONST.TRUST_TYPE else False

    # ----------------------------------------------------------------------
    def set_trusted(self, trusted):
        """
        @summary:  set sensor trusted/untrusted
        @param trusted: True/False
        """
        self.trusted = CONST.TRUST_TYPE if trusted else CONST.UNTRUST_TYPE

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
        val = self.get_file_val(filename, self.sensors_config.get(trh_type, CONST.TEMP_MIN_MAX[trh_type]))
        val /= scale
        self.log.info("Set {} {} : {}".format(self.name, trh_type, val))
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
    def process(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: main function to process device/sensor
        """
        if self.check_sensor_blocked():
            self.stop()
        else:
            self.start()

        if self.state == CONST.RUNNING:
            self.handle_input(thermal_table, flow_dir, amb_tmp)
            self.handle_err(thermal_table, flow_dir, amb_tmp)

    def info(self):
        """
        @summary: returning info about current device state. Can be overridden in child class
        """
        info_str = "\"{}\" temp: {}, tmin: {}, tmax: {}, pwm: {}, {}".format(self.name, self.value, self.val_min, self.val_max, self.pwm, self.state)
        return info_str



class thermal_sensor(system_device):
    """
    @summary: base class for simple thermal sensors
    can be used for cpu/sodimm/psu/voltmon/etc. thermal sensors
    """
    def __init__(self, config, dev_config_dict, logger):
        system_device.__init__(self, config, dev_config_dict, logger)
        self.file_input = self.base_name + dev_config_dict.get("input_suffix", "")

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_min = self.read_val_min_max("{}_min".format(self.base_name), "val_min", CONST.TEMP_SENSOR_SCALE)
        self.val_min = self.sensors_config.get("val_min_override", self.val_min)
        self.val_max = self.read_val_min_max("{}_max".format(self.base_name), "val_max", CONST.TEMP_SENSOR_SCALE)

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

        # integral filter for soothing temperature change
        self.value_acc -= self.value_acc / self.input_smooth_level
        self.value_acc += value
        self.value = int(round(float(self.value_acc) / self.input_smooth_level))

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
        pwm = self.pwm_min
        # sensor error reading counter
        if self.check_reading_file_err():
            pwm = g_get_dmin(thermal_table, amb_tmp, ["sensor_err"])

        self.pwm = max(pwm, self.pwm)
        return None


class thermal_module_sensor(system_device):
    """
    @summary: base class for modules sensor
    can be used for mlxsw/gearbox modules thermal sensor
    """
    def __init__(self, config, dev_config_dict, logger):
        system_device.__init__(self, config, dev_config_dict, logger)

        result = re.match(r".*(module\d+)", self.base_name)
        if result:
            module_name = result.group(1)
            self.module_name = module_name
        else:
            self.module_name = ""
        self.refresh_attr_period = 0
        self.refresh_timeout = 0

     # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.val_max = self.read_val_min_max("thermal/{}/temp_trip_hot".format(self.base_name), "val_max", scale=CONST.TEMP_SENSOR_SCALE)
        self.val_min = self.read_val_min_max("thermal/{}/temp_trip_norm".format(self.base_name), "val_min", scale=CONST.TEMP_SENSOR_SCALE)

        self.refresh_attr_period = self.sensors_config.get("refresh_attr_period", 0)
        if self.refresh_attr_period:
            self.refresh_timeout = current_milli_time() + self.refresh_attr_period * 1000
        else:
            self.refresh_timeout = 0
        self.set_trusted(False)

        # Disable kernel control for this thermal zone
        tz_policy_filename = "thermal/{}/thermal_zone_policy".format(self.base_name)
        tz_mode_filename = "thermal/{}/thermal_zone_mode".format(self.base_name)

        self.write_file(tz_policy_filename, "user_space")
        self.write_file(tz_mode_filename, "disabled")

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor input
        """
        pwm = self.pwm_min
        self.set_trusted(True)
        # refreshing min/max attributes each 30 min
        if self.refresh_timeout > 0 and self.refresh_timeout < current_milli_time():
            self.val_max = self.read_val_min_max("thermal/{}/temp_trip_hot".format(self.base_name), "val_max", scale=CONST.TEMP_SENSOR_SCALE)
            self.val_min = self.read_val_min_max("thermal/{}/temp_trip_norm".format(self.base_name), "val_min", scale=CONST.TEMP_SENSOR_SCALE)
            self.refresh_timeout = current_milli_time() + self.refresh_attr_period * 1000

        temp_read_file = "thermal/{}/thermal_zone_temp".format(self.base_name)
        if not self.check_file(temp_read_file):
            self.log.info("Missing file {} :{}.".format(self.name, temp_read_file))
            self.handle_reading_file_err(temp_read_file)
        else:
            try:
                temperature = int(self.read_file(temp_read_file))
                self.handle_reading_file_err(temp_read_file, reset=True)
                temperature /= CONST.TEMP_SENSOR_SCALE
                # for modules that is not equipped with thermal sensor temperature returns zero
                self.value = int(temperature)
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
                self.log.warn("value reading from file: {}".format(self.base_name))
                self.handle_reading_file_err(temp_read_file)

        self.log.debug("{} value {}".format(self.name, self.value))

        self.pwm = pwm
        # check if module have sensor interface
        if self.val_max == 0 and self.val_min == 0 and self.value == 0:
            return
        else:
            # calculate PWM based on formula
            self.pwm = max(self.calculate_pwm_formula(), pwm)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        @summary: handle sensor errors
        """
        fault_status = 0
        if self.module_name:
            fault_filename = "thermal/{}_temp_fault".format(self.module_name)
            if self.check_file(fault_filename):
                try:
                    fault_status = int(self.read_file(fault_filename))
                    self.handle_reading_file_err(fault_filename, reset=True)
                    if fault_status:
                        self.log.notice("{}: {} (untrusted)".format(fault_filename, fault_status))
                        self.set_trusted(False)
                except BaseException:
                    self.log.error("Value reading from file: {}".format(fault_filename))
                    self.handle_reading_file_err(fault_filename)
            else:
                self.log.error("{} : {} not exist".format(self.name, fault_filename))
                self.handle_reading_file_err(fault_filename)

        # sensor error reading counter
        if self.check_reading_file_err():
            self.set_trusted(False)

        return None


class psu_fan_sensor(system_device):
    """
    @summary: base class for PSU device
    Can be used for Control of PSU temperature/RPM
    """
    def __init__(self, config, dev_config_dict, logger):
        system_device.__init__(self, config, dev_config_dict, logger)
        self.file_input = self.base_name + dev_config_dict.get("input_suffix", "")
        self.val_min = self.read_val_min_max("thermal/{}_fan_min".format(self.base_name), "val_min")
        self.val_max = self.read_val_min_max("thermal/{}_fan_max".format(self.base_name), "val_max")
        self.prsnt_err_pwm_min = self.get_file_val("config/pwm_min_psu_not_present")

        self.rpm_trh = 0.15
        self.fault_list = []

    # ----------------------------------------------------------------------
    def _get_status(self):
        """
        """
        psu_status_filename = "thermal/{}_status".format(self.base_name)
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
    def _get_rpm_fault(self):
        if self.value < self.val_min * 0.2 or self.value > self.val_max * 1.2:
            return True
        return False

    # ----------------------------------------------------------------------
    def set_pwm(self, pwm):
        """
        @summary: Set PWM level for PSU FAN
        @param pwm: PWM level value <= 100%
        """
        present = self.thermal_read_file_int("{0}_pwr_status".format(self.base_name))
        if present == 1:
            bus = self.read_file("config/{0}_i2c_bus".format(self.base_name))
            addr = self.read_file("config/{0}_i2c_addr".format(self.base_name))
            command = self.read_file("config/fan_command")
            subprocess.call("i2cset -f -y {0} {1} {2} {3} wp".format(bus, addr, command, pwm), shell=True)

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
                self.value = int(self.read_file(rpm_file_name))
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
        pwm = self.pwm_min
        psu_status = self._get_status()
        if psu_status == 0:
            # PSU status error. Calculating dmin based on this information
            self.log.info("{} psu_status {}".format(self.name, psu_status))
            self.fault_list.append("present")
            if self.prsnt_err_pwm_min:
                pwm = self.prsnt_err_pwm_min
            else:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "psu_err", "present"])

        rpm_fault = self._get_rpm_fault()
        if rpm_fault:
            self.log.warn("{} psu_fan_fault".format(self.name))
            # PSU status error. Calculating dmin based on this information
            self.fault_list.append("fault")
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "psu_err", "present"])

        self.pwm = max(pwm, self.pwm)
        # sensor error reading counter
        if self.check_reading_file_err():
            pwm = g_get_dmin(thermal_table, amb_tmp, ["sensor_err"])
        self.pwm = max(pwm, self.pwm)

        return

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about device state.
        """
        return "\"{}\" rpm:{}, faults:[{}] pwm: {}, {}".format(self.name, self.value, ",".join(self.fault_list), self.pwm, self.state)


class fan_sensor(system_device):
    """
    @summary: base class for FAN device
    Can be used for Control FAN RPM/state.
    """
    def __init__(self, config, dev_config_dict, logger):
        system_device.__init__(self, config, dev_config_dict, logger)

        self.val_min = self.read_val_min_max("config/fan_min_speed", "val_min")
        self.val_max = self.read_val_min_max("config/fan_max_speed", "val_max")
        self.tacho_cnt = dev_config_dict.get("tacho_cnt", 1)
        self.fan_drwr_id = int(dev_config_dict["drwr_id"])
        self.tacho_idx = ((self.fan_drwr_id - 1) * self.tacho_cnt) + 1
        self.fan_dir = self._read_dir()
        self.fan_dir_fail = False
        self.is_calibrated = False
        self.rpm_pwm_scale = self.val_max / 255

        self.rpm_trh = 0.35
        self.rpm_relax_timeout = CONST.FAN_RELAX_TIME * 1000
        self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout * 2
        self.name = "{}:{}".format(self.name, range(self.tacho_idx, self.tacho_idx + self.tacho_cnt))

        self.pwm_last = 0
        self.rpm_valid_state = True

        self.fault_list = []

        self.log.info("{}: Preparing calibration".format(self.name))
        # get real FAN max_speed
        pwm = int(self.read_file("thermal/pwm1"))
        # check if PWM max already set
        if pwm < 255:
            self.thermal_write_file("pwm1", 255)
            time.sleep(int(self.rpm_relax_timeout / 1000))

        # get FAN RPM
        rpm = 0
        self.log.info("{}: Calibrating FAN rpm max...".format(self.name))
        for i in range(CONST.FAN_CALIBRATE_CYCLES):
            for tacho_idx in range(self.tacho_idx, self.tacho_idx + self.tacho_cnt):
                time.sleep(0.5)
                rpm += self.thermal_read_file_int("fan{}_speed_get".format(tacho_idx))

        rpm_max_real = float(rpm) / (CONST.FAN_CALIBRATE_CYCLES * self.tacho_cnt)
        self.rpm_pwm_scale = rpm_max_real / 255
        self.log.info("{}: rpm: max {} real {} scale {}".format(self.name, self.val_max, rpm_max_real, self.rpm_pwm_scale))

    # ----------------------------------------------------------------------
    def sensor_configure(self):
        """
        @summary: this function calling on sensor start after initialization or suspend off
        """
        self.value = [0] * self.tacho_cnt

        self.fault_list = []
        self.pwm = self.pwm_min
        self.pwm_last = 0
        self.rpm_valid_state = True
        self.fan_dir_fail = False
        self.fan_dir = self._read_dir()

    # ----------------------------------------------------------------------
    def _read_dir(self):
        """
        @summary: Reading chassis fan dir from FS
        """
        dir_val = self.read_file("thermal/fan{}_dir".format(self.fan_drwr_id))
        direction = CONST.C2P if dir_val == "0" else CONST.P2C
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
        pwm_curr = self.thermal_read_file_int("pwm1")
        if pwm_curr != self.pwm_last:
            self.pwm_last = self.thermal_read_file_int("pwm1")
            self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout * 2
        elif self.rpm_relax_timestump < current_milli_time():
            self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout * 2
            self.rpm_valid_state = True
            for tacho_idx in range(self.tacho_idx, self.tacho_idx + self.tacho_cnt):
                rpm_real = self.thermal_read_file_int("fan{}_speed_get".format(tacho_idx))
                rpm_expected = int(pwm_curr * self.rpm_pwm_scale)
                rpm_diff = abs(rpm_real - rpm_expected)
                rpm_diff = int(float(rpm_diff) / rpm_expected)
                if rpm_diff >= self.rpm_trh:
                    self.log.warn("{} tacho {}: {} too much different {}% than expected {} pwm  {} scale {}".format(self.name,
                                                                                                                    tacho_idx,
                                                                                                                    rpm_real,
                                                                                                                    rpm_diff,
                                                                                                                    rpm_expected,
                                                                                                                    pwm_curr,
                                                                                                                    self.rpm_pwm_scale))
                    self.rpm_valid_state = False

        return self.rpm_valid_state

    # ----------------------------------------------------------------------
    def get_dir(self):
        """
        @summary: return cached chassis fan direction
        @return: fan direction CONST.P2C/CONST.C2P
        """
        return self.fan_dir

    # ----------------------------------------------------------------------
    def check_sensor_blocked(self, name=None):
        """
        @summary:  check if sensor disabled. Sensor can be disabled by writing 1 to file {sensor_name}_blacklist
        @param name: device sensor name
        @return: True if device is disabled
        """
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
        pwm = self.pwm_min
        fan_status = self._get_status()
        if fan_status == 0:
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", "present"])
            self.fault_list.append("present")
            self.log.warn("{} status 0. Set PWM {}".format(self.name, pwm))

        fan_fault = self._get_fault()
        if 1 in fan_fault:
            pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", "fault"])
            self.fault_list.append("fault")
            self.log.warn("{} tacho {} fault. Set PWM {}".format(self.name, fan_fault, pwm))

        if not self._validate_rpm():
            self.fault_list.append("tacho")
            pwm = max(g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", "tacho"]), pwm)
            self.log.warn("{} incorrect rpm {}. Set PWM  {}".format(self.name, self.value, pwm))

        if self.fan_dir_fail:
            self.fault_list.append("direction")
            pwm = max(g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", "direction"]), pwm)
            self.log.warn("{} dir error. Set PWM {}".format(self.name, pwm))

        self.pwm = max(pwm, self.pwm)
        # sensor error reading counter
        if self.check_reading_file_err():
            pwm = g_get_dmin(thermal_table, amb_tmp, ["sensor_err"])
        self.pwm = max(pwm, self.pwm)

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
    def __init__(self, config, dev_config_dict, logger):
        system_device.__init__(self, config, dev_config_dict, logger)

        self.base_name = dev_config_dict.get("file_in_dict", None)
        self.value_dict = {CONST.FAN_SENS: 0, CONST.PORT_SENS: 0}
        self.flow_dir = CONST.UNKNOWN

    # ----------------------------------------------------------------------
    def get_flow_dir(self):
        return self.flow_dir

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        """
        """
        # reading all amb sensors
        for _, sens_file_name in self.base_name.items():
            if not self.check_file(sens_file_name):
                self.log.warn("{}: missing file {}".format(self.name, sens_file_name))
                self.handle_reading_file_err(sens_file_name)
            else:
                try:
                    temperature = int(self.read_file(sens_file_name))
                    self.handle_reading_file_err(sens_file_name, reset=True)
                    temperature /= CONST.TEMP_SENSOR_SCALE
                    self.value_dict[sens_file_name] = int(temperature)
                    self.log.debug("{} {} value {}".format(self.name, sens_file_name, temperature))
                except BaseException:
                    self.log.error("Error value reading from file: {}".format(self.base_name))
                    self.handle_reading_file_err(sens_file_name)

        if self.value_dict[CONST.PORT_SENS] > self.value_dict[CONST.FAN_SENS]:
            self.flow_dir = CONST.C2P
            self.value = self.value_dict[CONST.FAN_SENS]
        elif self.value_dict[CONST.PORT_SENS] < self.value_dict[CONST.FAN_SENS]:
            self.flow_dir = CONST.P2C
            self.value = self.value_dict[CONST.PORT_SENS]
        else:
            self.flow_dir = CONST.UNKNOWN
            self.value = self.value_dict[CONST.PORT_SENS]

        self.pwm = g_get_dmin(thermal_table, self.value, [self.flow_dir, self.trusted], interpolated=True)

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        """
        """
        pwm = self.pwm_min
        # sensor error reading counter
        if self.check_reading_file_err():
            pwm = g_get_dmin(thermal_table, amb_tmp, ["sensor_err"])
        self.pwm = max(pwm, self.pwm)
        return None

    # ----------------------------------------------------------------------
    def info(self):
        """
        @summary: returning info about device state.
        """
        info_str = "\"{}\" temp:{}, dir:{}, pwm:{}, {}".format(self.name, self.value_dict, self.flow_dir, self.pwm, self.state)
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

    def __init__(self, config):
        """
        @summary:
            Init  thermal algorithm
        @param config: global thermal configuration
        """
        hw_managemet_file_op.__init__(self, config)
        self.log = Logger(config[CONST.LOG_USE_SYSLOG], config[CONST.LOG_FILE], config["verbosity"])
        self.log.notice("Preinit thermal control")
        self.write_file(CONST.LOG_LEVEL_FILENAME, config["verbosity"])
        self.periodic_report_worker_timer = None
        self.thermal_table = None
        self.config = config
        # Set PWM to maximum -1. This is a trick for forse waiting
        # of FAN_RELAX_TIME on FAN calibrate
        self.pwm_target = CONST.PWM_MAX
        self.pwm = self.pwm_target
        self.pwm_change_reason = "-"
        self._collect_hw_info()
        self._write_pwm(self.pwm_target)

        sensors_config = {}
        if config[CONST.SENSORS_CONFIG]:
            config_file = config[CONST.SENSORS_CONFIG]
            if not os.path.isfile(config_file):
                self.log.warn("Can't load sensor config. Missing file {}".format(config_file))
            else:
                with open(config_file) as f:
                    sensors_config = json.load(f)
        else:
            config_file = "{}/config/tc_sensors.conf".format(self.root_folder)
            if os.path.isfile(config_file):
                with open(config_file) as f:
                    sensors_config = json.load(f)

        if self.check_file(CONST.PERIODIC_REPORT_FILE):
            self.periodic_report_time = int(self.read_file(CONST.PERIODIC_REPORT_FILE))
            self.rm_file(CONST.PERIODIC_REPORT_FILE)
        else:
            self.periodic_report_time = CONST.PERIODIC_REPORT_TIME

        self.sensors_config = sensors_config
        self.sys_typename = self.config.get("systypename", None)

        self.dev_obj_list = []

        self.pwm_sooth_step_max = CONST.PWM_INC_STEP_MAX
        self.pwm_worker_poll_time = CONST.PWM_WORKET_POLL_TIME
        self.pwm_worker_timer = None

        self.trusted = True
        self.state = CONST.UNCONFIGURED

        self.exit = Event()
        try:
            thermal_delay = int(self.read_file("config/thermal_delay"))
            self.exit.wait(thermal_delay)
        except BaseException:
            pass

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
        self.board_type = None
        self.sku = None
        self.system_ver = None

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

        try:
            self.max_tachos = int(self.read_file("config/max_tachos"))
        except BaseException:
            self.log.error("Missing max tachos config.")
            sys.exit(1)

        try:
            self.fan_drwr_num = int(self.read_file("config/fan_drwr_num"))
        except BaseException:
            self.log.error("Missing fan_drwr_num config.")
            sys.exit(1)

        try:
            self.psu_count = int(self.read_file("config/hotplug_psus"))
        except BaseException:
            self.log.error("Missing hotplug_psus config.")
            sys.exit(1)

        try:
            self.psu_pwr_count = int(self.read_file("config/hotplug_pwrs"))
        except BaseException:
            self.log.error("Missing hotplug_pwrs config.")
            sys.exit(1)

        self.fan_drwr_capacity = int(self.max_tachos / self.fan_drwr_num)
        self.module_counter = int(self.get_file_val("config/module_counter", CONST.MODULE_COUNT_DEF))
        self.gearbox_counter = int(self.get_file_val("config/gearbox_counter", CONST.GEARBOX_COUNT_DEF))

    # ----------------------------------------------------------------------
    def _get_dev_obj(self, name):
        """
        @summary: Get device object by it's name
        """
        for dev_obj in self.dev_obj_list:
            if name == dev_obj.name:
                return dev_obj
        return None

    # ----------------------------------------------------------------------
    def _check_untrusted_module_sensor(self):
        """
        @summary:
            Check if some module if fault state
        @return: True - on sensor failure False - Ok
        """
        for dev_obj in self.dev_obj_list:
            if dev_obj.enable:
                if not dev_obj.is_trusted():
                    return False
        return True

    def _check_fan_dir(self):
        """
        @summary: Comparing case FAN direction. In case the number of presented air-in fans is higher or equal to the
        number of presented air-out fans, set the direction error bit of all the presented air-out fans.
        Otherwise, set the direction error bit of all the presented air-in fans.
        """
        c2p_count = 0
        p2c_count = 0
        for obj in self.dev_obj_list:
            fan_dir = getattr(obj, "fan_dir", None)
            if fan_dir == CONST.C2P:
                c2p_count += 1
            elif fan_dir == CONST.P2C:
                p2c_count += 1
        pref_dir = CONST.C2P if c2p_count >= p2c_count else CONST.P2C

        for obj in self.dev_obj_list:
            fan_dir = getattr(obj, "fan_dir", None)
            if fan_dir is not None and fan_dir != pref_dir:
                setattr(obj, "fan_dir_fail", 1)

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
    def _write_pwm(self, pwm_val):
        """
        @summary: Write PWM value to the pwm file .
        @param pwm: pwm value in present
        """
        self.log.info("Update FAN PWM {}".format(pwm_val))
        self.thermal_write_file("pwm1", int(pwm_val * 255 / 100))

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
                self._write_pwm(self.pwm)

    # ----------------------------------------------------------------------
    def _pwm_worker(self):
        ''
        if self.pwm_target == self.pwm:
            pwm_real = self.thermal_read_file_int("pwm1")
            pwm_set = round(self.pwm * 255 / 100)
            if pwm_real != pwm_set:
                self.log.warn("Unexpected pwm1 value {}. Force set to {}".format(pwm_real, pwm_set))
                self._write_pwm(self.pwm)
            self.pwm_worker_timer.stop()
            return

        self.log.debug("PWM target: {} curr: {}".format(self.pwm_target, self.pwm))
        if self.pwm_target < self.pwm:
            diff = abs(self.pwm_target - self.pwm)
            step = int(round((float(diff) / 2 + 0.5)))
            if step > self.pwm_sooth_step_max:
                step = self.pwm_sooth_step_max
            self.pwm -= step
        else:
            self.pwm = self.pwm_target
        self._write_pwm(self.pwm)

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
        if sensor_name not in self.sensors_config.keys():
            self.sensors_config[sensor_name] = {"type": sensor_type}
        self.sensors_config[sensor_name]["name"] = sensor_name

        if extra_config:
            add_missing_to_dict(self.sensors_config[sensor_name], extra_config)

        for name_mask in SENSOR_DEF_CONFIG.keys():
            if re.match(name_mask, sensor_name):
                add_missing_to_dict(self.sensors_config[sensor_name], SENSOR_DEF_CONFIG[name_mask])
                break

    # ----------------------------------------------------------------------
    @staticmethod
    def _pwm_strategy_max(pwm_list):
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
    @staticmethod
    def _pwm_strategy_avg(pwm_list):
        return float(sum(pwm_list)) / len(pwm_list)

    # ----------------------------------------------------------------------
    def sig_handler(self, sig, frame):
        """
        @summary:
            Signal handler for termination signals
        """
        if sig in [signal.SIGTERM, signal.SIGINT, signal.SIGHUP]:
            self.log.notice("Thermal control was terminated PID={} frame={}".format(os.getpid(), frame))
            self.stop()
            self.exit.set()

            self.log.notice("Thermal control terminated")
            sys.exit(1)

    # ----------------------------------------------------------------------
    @staticmethod
    def _match_system_table(typename):
        """
        @summary: Find corresponded dmin table configuration based on system typename
        @param typename: name of system dmin table/ Please see available names in THERMAL_TABLE_LIST
        can be:1
        1. system name
        2. Thermal class
        3. SKU
        """
        if not typename:
            return None
        thermal_table = None
        for typename_mask in THERMAL_TABLE_LIST.keys():
            if re.match(typename_mask, typename):
                thermal_table = THERMAL_TABLE_LIST[typename_mask]
                break
        return thermal_table

    # ----------------------------------------------------------------------
    def init_thermal_table(self):
        """
        @summary: Init dmin table by the system type. Type definition priority
            1. Check sys_typename from command line argument
            2. Get type from config/thermal_type
            3. Get SKU
            4. Using default table
        """
        typename = None
        if self.sys_typename:
            typename = self.sys_typename
        else:
            typename = self.read_file("config/thermal_type")
            if typename:
                typename = "tc_t{}".format(typename)
            elif self.board_type:
                typename = self.board_type

        self.thermal_table = self._match_system_table(typename)

        if not self.thermal_table:
            self.thermal_table = THERMAL_TABLE_LIST["default"]
            self.log.notice("System typename {} not found. Using default thermal type:{}".format(typename, self.thermal_table["name"]))
        else:
            self.log.notice("System typename \"{}\" thermal type:\"{}\"".format(self.sys_typename, self.thermal_table["name"]))

    # ----------------------------------------------------------------------
    def init_sensor_configuration(self):
        """
        @summary: Init sensor configuration based on system type and information from
        hw-management configuration folder
        """

        for psu_idx in range(1, self.psu_count + 1):
            name = "psu{}_fan".format(psu_idx)
            in_file = "psu{}".format(psu_idx)
            self._sensor_add_config("psu_fan_sensor", name, {"base_name": in_file})

            name = "psu{}_temp".format(psu_idx)
            in_file = "thermal/psu{}_temp".format(psu_idx)
            self._sensor_add_config("thermal_sensor", name, {"base_name": in_file})

        for fan_idx in range(1, self.fan_drwr_num + 1):
            name = "fan{}".format(fan_idx)
            self._sensor_add_config("fan_sensor", name, {"base_name": name, "drwr_id": fan_idx, "tacho_cnt": self.fan_drwr_capacity})

        for module_idx in range(1, self.module_counter + 1):
            name = "mlxsw-module{}".format(module_idx)
            self._sensor_add_config("thermal_module_sensor", name, {"base_name": name})

        for gearbox_idx in range(1, self.gearbox_counter + 1):
            name = "mlxsw-gearbox{}".format(gearbox_idx)
            self._sensor_add_config("thermal_module_sensor", name, {"base_name": name})

        self._sensor_add_config("thermal_module_sensor", "mlxsw", {"base_name": "mlxsw"})

        if self.check_file("thermal/cpu_pack"):
            self._sensor_add_config("thermal_sensor", "cpu_pack", {"base_name": "thermal/cpu_pack"})
        elif self.check_file("thermal/cpu_core1"):
            self._sensor_add_config("thermal_sensor", "cpu_core1", {"base_name": "thermal/cpu_core1"})

        self._sensor_add_config("ambiant_thermal_sensor", "sensor_amb")

        # scanning for extra sensors (SODIMM 1-4)
        for sodimm_idx in range(1, 5):
            name = "sodimm{}_temp".format(sodimm_idx)
            if self.check_file("thermal/{}_input".format(name)):
                self._sensor_add_config("thermal_sensor", name, {"base_name": "thermal/{}".format(name)})

        if self.check_file("thermal/pch_temp"):
            self._sensor_add_config("thermal_sensor", "pch", {"base_name": "thermal/pch"})

        if self.check_file("thermal/comex_amb"):
            self._sensor_add_config("thermal_sensor", "comex_amb", {"base_name": "thermal/comex_amb"})

    # ----------------------------------------------------------------------
    def init(self):
        """
        @summary: Init thermal-control main
        """
        self.log.notice("********************************")
        self.log.notice("Init thermal control ver: v.{}".format(VERSION))
        self.log.notice("********************************")

        # Set initial PWM to maximum
        self._set_pwm(CONST.PWM_MAX, reason="Set initial PWM")

        self.init_thermal_table()
        self.init_sensor_configuration()
        self.log.debug("Sensor config dump\n{}".format(json.dumps(self.sensors_config, sort_keys=True, indent=4)))

        for key, val in self.sensors_config.items():
            try:
                dev_class_ = globals()[val["type"]]
            except Exception as err:
                self.log.error("Unknown dev class {}".format(err.message))
                continue
            dev_obj = dev_class_(self.config, val, self.log)
            if not dev_obj:
                self.log.error("{} create failed".format(key))
                sys.exit(1)

            self.dev_obj_list.append(dev_obj)
        self.dev_obj_list.sort(key=lambda x: x.name)
        self.write_file(CONST.PERIODIC_REPORT_FILE, self.periodic_report_time)

        signal.signal(signal.SIGTERM, self.sig_handler)
        signal.signal(signal.SIGINT, self.sig_handler)
        signal.signal(signal.SIGHUP, self.sig_handler)

    # ----------------------------------------------------------------------
    def start(self):
        """
        @summary: Start sensor service.
        Used when suspend mode was de-asserted
        """

        if self.state != CONST.RUNNING:
            self.log.notice("Thermal control state changed {} -> {}".format(self.state, CONST.RUNNING))
            self.state = CONST.RUNNING

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    dev_obj.start()

            if not self.periodic_report_worker_timer:
                self.periodic_report_worker_timer = RepeatedTimer(self.periodic_report_time, self.print_periodic_info)
            self.periodic_report_worker_timer.start()

            if not self.pwm_worker_timer:
                self.pwm_worker_timer = RepeatedTimer(self.pwm_worker_poll_time, self._pwm_worker)
            self.pwm_worker_timer.stop()

            self._check_fan_dir()

    # ----------------------------------------------------------------------
    def stop(self):
        """
        @summary: Stop sensor service and set PWM to PWM-MAX.
        Used when suspend mode was de-asserted  or when kill signal was revived
        """
        if self.state != CONST.STOPPED:
            self.log.notice("Thermal control state changed {} -> {}".format(self.state, CONST.STOPPED))
            self.state = CONST.STOPPED

            if self.pwm_worker_timer:
                self.pwm_worker_timer.stop()
                self.pwm_worker_timer = None

            if self.periodic_report_worker_timer:
                self.periodic_report_worker_timer.stop()
                self.periodic_report_worker_timer = None

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    dev_obj.stop()

            self._set_pwm(CONST.PWM_MAX, reason="TC stop")

    # ----------------------------------------------------------------------
    def run(self):
        """
        @summary:  main thermal control loop
        """

        self.log.notice("********************************")
        self.log.notice("Run thermal control")
        self.log.notice("********************************")

        self.trusted = True

        # Service of sensor ambient first because we must init amb temp and flow dir
        ambient_sensor = self._get_dev_obj("sensor_amb")
        if ambient_sensor:
            ambient_sensor.process(self.thermal_table, CONST.TEMP_INIT_DEF, CONST.C2P)
            amb_tmp = ambient_sensor.get_value()
            flow_dir = ambient_sensor.get_flow_dir()
        else:
            amb_tmp = CONST.TEMP_INIT_DEF
            flow_dir = CONST.C2P

        # main loop
        while not self.exit.is_set():
            try:
                log_level = int(self.read_file(CONST.LOG_LEVEL_FILENAME))
                if log_level != self.config["verbosity"]:
                    self.config["verbosity"] = log_level
                    self.log.set_loglevel(self.config["verbosity"])
            except BaseException:
                pass

            if self._is_suspend():
                self.stop()
                self.exit.wait(5)
                continue
            else:
                self.start()

            pwm_list = {}
            timestump_next = current_milli_time() + 60 * 1000
            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    if current_milli_time() >= dev_obj.get_timestump():
                        # process sensors
                        dev_obj.process(self.thermal_table, flow_dir, amb_tmp)
                        dev_obj.update_timestump()

                        if dev_obj.name == "sensor_amb":
                            self.trusted = self._check_untrusted_module_sensor()
                            amb_tmp = dev_obj.get_value()
                            flow_dir = dev_obj.get_flow_dir()
                            dev_obj.set_trusted(self.trusted)

                    pwm = dev_obj.get_pwm()
                    self.log.debug("{0:25}: PWM {1}".format(dev_obj.name, pwm))
                    pwm_list[dev_obj.name] = pwm

                    obj_timestump = dev_obj.get_timestump()
                    timestump_next = min(obj_timestump, timestump_next)

            pwm, name = self._pwm_strategy_max(pwm_list)
            self.log.debug("Result PWM {}".format(pwm))
            self._set_pwm(pwm, reason=name)
            sleep_ms = int(timestump_next - current_milli_time())

            # Poll time should not be smaller than 1 sec to reduce system load
            # and mot more 10 sec to have a good response for suspend mode change polling
            if sleep_ms < 1000:
                sleep_ms = 1000
            elif sleep_ms > 10 * 1000:
                sleep_ms = 10 * 1000
            self.exit.wait(sleep_ms / 1000)

    # ----------------------------------------------------------------------
    def print_periodic_info(self):
        """
        @summary:  Print current TC state and info reported by the sensor objects
        """
        ambient_sensor = self._get_dev_obj("sensor_amb")
        if ambient_sensor:
            amb_tmp = ambient_sensor.get_value()
            flow_dir = ambient_sensor.get_flow_dir()
        else:
            amb_tmp = "-"
            flow_dir = "-"

        mlxsw_sensor = self._get_dev_obj("mlxsw")
        if mlxsw_sensor:
            mlxsw_tmp = mlxsw_sensor.get_value()
        else:
            mlxsw_tmp = "N/A"

        self.log.notice("Thermal periodic report")
        self.log.notice("================================")
        self.log.notice("Temperature(C): asic {}, amb {}".format(mlxsw_tmp, amb_tmp))
        self.log.notice("Cooling(%) {} ({})".format(self.pwm_target, self.pwm_change_reason))
        self.log.notice("dir:{}, trusted:{}".format(flow_dir, self.trusted))
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
    CMD_PARSER.add_argument("--sensors_config",
                            dest=CONST.SENSORS_CONFIG,
                            help="Config file with additional sensors description",
                            default=None)
    CMD_PARSER.add_argument("-l", "--log_file",
                            dest=CONST.LOG_FILE,
                            help="Add output also to log file. Pass file name here",
                            default="/var/log/tc_log")
    CMD_PARSER.add_argument("-s", "--syslog",
                            dest=CONST.LOG_USE_SYSLOG,
                            help="enable/disable output to syslog",
                            type=str2bool_argparse, default=True)
    CMD_PARSER.add_argument("-t", "--systypename",
                            dest="systypename",
                            help="System name/type/SKU (MSN2700, HI110, VMOD0001)",
                            default=None)
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
        thermal_management.run()
    except BaseException:
        thermal_management.log.error(traceback.format_exc())
        thermal_management.stop()

    sys.exit(0)
