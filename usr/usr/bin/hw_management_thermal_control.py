#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# Copyright (c) 2021 NVIDIA CORPORATION & AFFILIATES.
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

'''
Created on Oct 01, 2022

Author: Oleksandr Shamray <oleksandrs@nvidia.com>
Version: 2.0.0

Description:
System Thermal control tool

'''


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
import syslog
import atexit
import json
import re
from threading import Timer, Event
import datetime 
import pdb

#############################
# Global const
#############################
#pylint: disable=c0301,W0105

VERSION = "2.0.0"


#############################
# Local const
#############################

class CONST(object):
    '''
    @summary: hw-management constants
    '''
    LOG_USE_SYSLOG = "use_syslog"
    LOG_FILE = "log_filename"
    HW_MGMT_ROOT = "root_folder"
    GLOBAL_CONFIG = 'global_config'
    SENSORS_CONFIG = 'sensors_config'
    C2P = "C2P"
    C2P_SENS = "thermal/fan_amb"
    P2C = "P2C"
    P2C_SENS = "thermal/port_amb"
    UNKNOWN = "Unknown"
    TRUST_TYPE = "trusted"
    UNTRUST_TYPE = "untrusted"
    HW_MGMT_FOLDER_DEF= "/var/run/hw-management"
    SUSPEND_FILE="config/suspend"

    SENSOR_POLL_TIME_DEF = 3
    PERIODIC_REPORT_TIME = 20
    TEMP_INIT_DEF = 25

    TEMP_SENSOR_SCALE = 1000.0
    PWM_MIN = 20
    PWM_MAX = 100
    TEMP_MIN_MAX = {"val_min": 10, "val_max":  65}

    FAN_RELAX_TIME = 15
    FAN_CALIBRATE_CYCLES = 2
    PWM_CHANGE_TRH = 5
    DMIN_PWM_STEP_MIN = 2

    PSU_COUNT_DEF = 2
    FAN_DRWR_COUNT_DEF = 6
    FAN_TACHO_COUNT_DEF = 6
    MODULE_COUNT_DEF = 16
    GEARBOX_COUNT_DEF = 0
    
    SENSOR_FREAD_FAIL_TIMES = 3
    
    UNDEFINED = "UNDEFINED"
    STOPPED = "STOPPED"
    RUNNING = "RUNNING"

sensor_by_name_def_config = {
    r'psu\d+': {"type": "psu_sensor", "pwm_min": 25, "pwm_max": 100, "poll_time": 30},
    r'fan\d+': {"type": "fan_sensor", "pwm_min": 25, "pwm_max": 100, "poll_time": 30},
    r'mlxsw-module\d+': {"type": "thermal_module_sensor", "pwm_min" : 25, "pwm_max" : 100, "poll_time" : 20, "refresh_attr_timeout" : 30 * 60},
    r'mlxsw-gearbox\d+': {"type": "thermal_module_sensor", "pwm_min" : 25, "pwm_max" : 100, "poll_time" : 6},
    r'mlxsw': {"type": "thermal_module_sensor", "pwm_min" : 25, "pwm_max" : 100, "poll_time" : 3},
    r'cpu_pack': {"type": "thermal_sensor", "val_min": 15, "val_max": 65,  "pwm_min": 25, "pwm_max": 100, "poll_time": 3, "input_smooth_level" : 3},
    r'fan_amb': {"type": "thermal_sensor", "val_min": 15, "val_max": 65,  "pwm_min": 25, "pwm_max": 100, "poll_time": 60},
    r'port_amb': {"type": "thermal_sensor", "val_min": 15, "val_max": 65,  "pwm_min": 25, "pwm_max": 100, "poll_time": 60},
    r'sensor_amb': {"type": "ambiant_thermal_sensor", "file_in_dict": {CONST.C2P: CONST.C2P_SENS, CONST.P2C: CONST.P2C_SENS}, "poll_time": 10}
    }

#############################
# System definition table
#############################
fan_err_default = {
                "tacho" : {"-127:40":70, "41:120":100},
                "present" :  {"-127:120":100},
                "fault" :  {"-127:120":100},
                "direction" :  {"-127:120":100}
            }

psu_err_default = {
                "present" :  {"-127:120":100},
                "direction" :  {"-127:120":100},
                "fault" :  {"-127:120":100},
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
            CONST.TRUST_TYPE : {"-127:20":30, "21:25":40 , "26:30":50, "31:120":60},
            CONST.UNTRUST_TYPE : {"-127:20":30, "21:25":40 , "26:30":50, "31:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:40":30, "41:120":50},
            CONST.UNTRUST_TYPE :  {"-127:25":30, "26:30":40 , "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:25":30, "26:30":40 , "31:35":50, "36:120":60},
            CONST.UNTRUST_TYPE :  {"-127:25":30, "26:30":40 , "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:40":20, "41:120":30},
            CONST.UNTRUST_TYPE : {"-127:40":20, "41:120":30},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:15":20, "16:25":30, "26:31":40, "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:40":20, "41:120":30},
            CONST.UNTRUST_TYPE :  {"-127:15":20, "16:25":30, "26:31":40, "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:120":30},
            CONST.UNTRUST_TYPE : {"-127:15":30, "16:30":40 , "31:35":50, "36:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:120":30},
            CONST.UNTRUST_TYPE : {"-127:35":30, "36:40":40 , "41:120":50},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:120":30},
            CONST.UNTRUST_TYPE : {"-127:15":30, "16:30":40 , "31:35":50, "36:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:20":20, "21:25":30, "26:30":40, "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:15":20, "16:20":30, "21:30":40, "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:15":20, "16:20":30, "21:30":40, "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:25":20, "26:40":30 , "41:120":40},
            CONST.UNTRUST_TYPE : {"-127:25":20, "26:40":30 , "41:120":40},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE :  {"-127:26":20, "26:40":30 , "41:120":40},
            CONST.UNTRUST_TYPE :  {"-127:15":20, "16:30":30 , "31:35":40, "36:40":40, "41:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:26":20, "26:40":30 , "41:120":40},
            CONST.UNTRUST_TYPE : {"-127:15":20, "16:30":30 , "31:35":40, "36:40":40, "41:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:35":20, "36:40":30 , "41:120":40},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:40":20, "41:120":30},
            CONST.UNTRUST_TYPE : {"-127:10":20, "11:20":30, "21:30":40 , "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:40":30, "41:120":30},
            CONST.UNTRUST_TYPE : {"-127:10":20, "11:20":30, "21:30":40 , "31:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:30":20, "31:40":30, "41:120":40},
            CONST.UNTRUST_TYPE : {"-127:20":20, "21:30":30 , "31:40":40 , "41:45":50, "46:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:35":20, "36:120":30},
            CONST.UNTRUST_TYPE : {"-127:0":20, "1:10":30, "11:15":40 , "16:20":50, "21:35":60, "36:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:30":20, "31:40":30, "41:120":40},
            CONST.UNTRUST_TYPE : {"-127:0":20, "1:10":30, "11:15":40 , "16:20":50, "21:35":60, "36:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:40":20, "41:120":30},
            CONST.UNTRUST_TYPE : {"-127:30":20, "31:40":30, "41:120":40},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE :  {"-127:5":20, "6:20":30, "21:30":40 , "31:35":50, "36:40":60, "41:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:40":20, "41:120":30},
            CONST.UNTRUST_TYPE : {"-127:5":20, "6:20":30, "21:30":40 , "31:35":50, "36:40":60, "41:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:40":20, "41:120":40},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:25":20, "26:35":30 , "36:40":40, "41:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:25":20, "26:35":30 , "36:40":40, "41:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE :  {"-127:35":20, "36:120":50},
            CONST.UNTRUST_TYPE :  {"-127:35":20, "36:120":50},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:35":20, "36:120":50},
            CONST.UNTRUST_TYPE :  {"-127:35":20, "36:120":50},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE :  {"-127:35":20, "36:120":50},
            CONST.UNTRUST_TYPE :  {"-127:35":20, "36:120":50},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE :  {"-127:35":30, "36:40":40, "41:120":50},
            CONST.UNTRUST_TYPE : {"-127:20":30, "21:25":40 , "26:30":50, "31:35":60, "36:40":70, "41:120":80},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE :  {"-127:30":30, "31:35":40 , "36:40":50, "41:120":60},
            CONST.UNTRUST_TYPE :  {"-127:15":30, "16:20":40 , "21:25":50, "26:30":60, "31:35":70, "41:45":80, "46:120":90},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE :  {"-127:30":30, "31:35":40 , "36:40":50, "41:120":60},
            CONST.UNTRUST_TYPE : {"-127:15":30, "16:20":40 , "21:25":50, "26:30":60, "31:35":70, "41:45":80, "46:120":90},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:15":20, "16:35":30, "36:120":40},
            CONST.UNTRUST_TYPE : {"-127:15":20, "16:25":30, "26:35":40, "41:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:5":20, "6:15":30, "16:25":40, "26:30":50, "36:40":60, "41:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE :  {"-127:15":20, "16:35":30, "36:120":40},
            CONST.UNTRUST_TYPE : {"-127:5":20, "6:15":30, "16:25":40, "26:30":50, "36:40":60, "41:120":70},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
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
            CONST.TRUST_TYPE : {"-127:120":20},
            CONST.UNTRUST_TYPE : {"-127:120":20},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default 
    },
    CONST.P2C: {
            CONST.TRUST_TYPE :  {"-127:25":20, "26:30":30, "31:120":40},
            CONST.UNTRUST_TYPE : {"-127:5":20, "6:20":30, "21:25":40, "26:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    },
    CONST.UNKNOWN: {
            CONST.TRUST_TYPE :  {"-127:25":20, "26:30":30, "31:120":40},
            CONST.UNTRUST_TYPE : {"-127:5":20, "6:20":30, "21:25":40, "26:35":50, "36:120":60},
            "fan_err": fan_err_default,
            "psu_err": psu_err_default
    }
}

THERMAL_TABLE_LIST = {
                   "default": TABLE_CLASS1,
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
                   r"(MSN4800)|(tc_t13)": TABLE_CLASS13
                 }

def str2bool(val):
    '''
    @summary:
        Convert input val value to bool
    '''
    if isinstance(val, bool):
        return val
    if val.lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    elif val.lower() in ('no', 'false', 'f', 'n', '0'):
        return False
    else:
        return None
    
def current_milli_time():
    return round(time.time() * 1000)   

def get_dict_val_by_path(dict, path):
    for sub_path in path:
        dict = dict.get(sub_path, None)
        if dict is None:
            break
    return dict

def g_get_dmin_range(line, temp):
    for key, val in line.items():
        t_range = key.split(':')
        t_min = int(t_range[0]) 
        t_max = int(t_range[1])
        if t_min <= temp <= t_max:
            return val, t_min, t_max
    return None, None, None

def g_get_dmin(thermal_table, temp, path, interpolated=False):
    line = get_dict_val_by_path(thermal_table, path)

    if not line:
        return CONST.PWM_MAX
    # get current range
    dmin, min, max = g_get_dmin_range(line, temp)
    if not interpolated:
        return dmin

    # get range of next step
    dmin_next, min_next, max_next = g_get_dmin_range(line, max+1)
    # reached maximum range 
    if dmin_next == None:
        return dmin

    # calculate smooth step 
    start_smooth_change_position = max - (dmin_next - dmin) / CONST.DMIN_PWM_STEP_MIN + 1
    if temp < start_smooth_change_position:
        return dmin
    elif start_smooth_change_position < min:
        step = float(dmin_next - dmin) / float(max + 1 - min)
    else:
        step = CONST.DMIN_PWM_STEP_MIN
    dmin = dmin_next - ((max - temp) * step)
    return int(dmin)

def add_missing_to_dict(dict_base, dict_new):
    base_keys = dict_base.keys()
    for key in dict_new.keys():
        if key not in base_keys:
            dict_base[key] = dict_new[key]
        
class Logger(object):
    '''
    Logger class provide functionality to log messages.
    It can log to several places in parallel
    '''

    def __init__(self, use_syslog=False, log_file=None, verbosity=0):
        '''
        @summary:
            The following class provide functionality to log messages.
            log provided by /lib/lsb/init-functions always turned on
        @param use_syslog: log also to syslog. Applicable arg
            value 1-enable/0-disable
        @param log_file: log to user specified file. Set '' if no log needed
        '''
        self.logger = None
        logging.basicConfig(level=logging.DEBUG)
        logging.addLevelName(logging.INFO+5, "NOTICE")
        self.logger = logging.getLogger("main")
        self.logger.setLevel(logging.DEBUG)
        self.logger.propagate = False
        self.set_param(use_syslog, log_file, verbosity)

    def set_param(self, use_syslog=None, log_file=None, verbosity=0):
        '''
        @summary:
            Set logger parameters. Can be called any time
            log provided by /lib/lsb/init-functions always turned on
        @param use_syslog: log also to syslog. Applicable arg
            value 1-enable/0-disable
        @param log_file: log to user specified file. Set None if no log needed
        '''
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')

        stream_handler = logging.StreamHandler()
        stream_handler.setLevel(logging.ERROR)
        stream_handler.setFormatter(formatter)
        self.logger.addHandler(stream_handler)

        if log_file:
            dt = datetime.datetime.now()
            log_file =  "{}_{}".format(log_file,int(dt.strftime("%Y%m%d%H%M%S")))
            if any (std_file in log_file for std_file in ["stdout", "stderr"]):
                logger_fh = logging.StreamHandler()
            else:
                logger_fh = RotatingFileHandler(log_file, maxBytes=1*1024*1024, backupCount=2)           

            logger_fh.setFormatter(formatter)
            logger_fh.setLevel(verbosity)
            self.logger.addHandler(logger_fh)

        if use_syslog:
            if sys.platform == "darwin":
                address = "/var/run/syslog"
            elif sys.platform == 'linux2':
                address = '/dev/log'
            else:
                address = ('localhost', 514)
            facility = SysLogHandler.LOG_SYSLOG
            syslog_handler = SysLogHandler(address=address, facility=facility)
            syslog_handler.setLevel(logging.INFO+5)

            syslog_handler.setFormatter(logging.Formatter('hw-management-tc: %(levelname)s - %(message)s'))
            self.logger.addHandler(syslog_handler)

    def debug(self, msg=''):
        '''
        @summary:
            Log "debug" message.
        @param msg: message to save to log
        '''
        if self.logger:
            self.logger.debug(msg)

    def info(self, msg=''):
        '''
        @summary:
            Log "info" message.
        @param msg: message to save to log
        '''
        if self.logger:
            self.logger.info(msg)

    def notice(self, msg=''):
        '''
        @summary:
            Log "notice" message.
        @param msg: message to save to log
        '''
        if self.logger:
            self.logger.log(logging.INFO+5, msg)

    def warn(self, msg=''):
        '''
        @summary:
            Log "warn" message.
        @param msg: message to save to log
        '''
        if self.logger:
            self.logger.warning(msg)

    def error(self, msg=''):
        '''
        @summary:
            Log "error" message.
        @param msg: message to save to log
        '''
        if self.logger:
            self.logger.error(msg)


class RepeatedTimer(object):
    '''
     @summary:
         Provide repeat timer service. Can start provided function with selected  interval
    '''
    def __init__(self, interval, function):
        '''
        @summary:
            Create timer object which run function in separate thread
            Automatically start timer after init
        @param interval: Interval in seconds to run function
        @param function: function name to run
        '''
        self._timer     = None
        self.interval   = interval
        self.function   = function

        self.is_running = False
        self.start()

    def _run(self):
        '''
        @summary:
            wrapper to run function
        '''
        self.is_running = False
        self.start()
        self.function()

    def start(self):
        '''
        @summary:
            Start selected timer (if it not running)
        '''
        if not self.is_running:
            self._timer = Timer(self.interval, self._run)
            self._timer.start()
            self.is_running = True

    def stop(self):
        '''
        @summary:
            Stop selected timer (if it started before
        '''
        self._timer.cancel()
        self.is_running = False

class hw_managemet_file_op(object):
    def __init__(self, config):
        if not config[CONST.HW_MGMT_ROOT]:
            self.root_folder = CONST.HW_MGMT_FOLDER_DEF
        else:
            self.root_folder = config[CONST.HW_MGMT_ROOT]

    # ----------------------------------------------------------------------    
    def _read_file(self, filename):
        '''
        @summary:
            read file from hw-management tree.
        @param filename: file to read from {hw-management-folder}/filename
        @return: file contents
        '''
        content = None
        filename = os.path.join(self.root_folder, filename)
        if os.path.isfile(filename):
            with open(filename, 'r') as content_file:
                content = content_file.read().rstrip("\n")

        return content

    # ----------------------------------------------------------------------
    def _write_file(self, filename, data):
        '''
        @summary:
            write data to file in hw-management tree.
        @param filename: file to write  {hw-management-folder}/filename
        @param data: data to write
        '''
        filename = os.path.join(self.root_folder, filename)
        with open(filename, 'w') as content_file:
            content_file.write(str(data))
            content_file.close()

    # ----------------------------------------------------------------------
    def _thermal_read_file(self, filename):
        '''
        @summary:
            read file from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @return: file contents
        '''
        return self._read_file(os.path.join("thermal", filename))

    # ----------------------------------------------------------------------
    def _thermal_read_file_int(self, filename):
        '''
        @summary:
            read file from hw-management/thermal tree.
        @param filename: file to read from {hw-management-folder}/thermal/filename
        @return: int value from file
        '''
        val = self._read_file(os.path.join("thermal", filename))
        return int(val)

    # ----------------------------------------------------------------------
    def _get_file_val(self, filename, def_val=None, scale=1):
        ''
        val = None
        if self._check_file(filename):
            try:
                val = int(self._read_file(filename))/scale
            except ValueError:
                pass
        if val == None:
            val = def_val
        return val

    # ----------------------------------------------------------------------
    def _thermal_write_file(self, filename, data):
        '''
        @summary:
            write data to file in hw-management/thermal tree.
        @param filename: file to write  {hw-management-folder}/thermal/filename
        @param data: data to write
        '''
        return self._write_file(os.path.join("thermal", filename), data)

    # ----------------------------------------------------------------------
    def _check_file(self, filename):
        '''
        @summary:
            check if file exist in file system in hw-management tree.
        @param filename: file to check {hw-management-folder}/filename
        '''
        filename = os.path.join(self.root_folder, filename)
        return os.path.isfile( filename )

    def _rm_file(self, filename):
        '''
        @summary:
            remove file in hw-management tree.
        @param filename: file to remove {hw-management-folder}/filename
        @param data: data to write
        '''
        filename = os.path.join(self.root_folder, filename)
        os.remove(filename)

class system_device(hw_managemet_file_op):
    '''
    '''
    def __init__(self, config, dev_config_dict, logger):

        hw_managemet_file_op.__init__(self, config)
        self.log = logger
        self.sensors_config = dev_config_dict
        self.name = dev_config_dict["name"]
        self.type = dev_config_dict["type"]
        self.log.info("Init {0} ({1})".format(self.name, self.type))
        self.file_in = self.sensors_config.get("file_in", None)
        self.enable = int(self.sensors_config.get("enable", 1))
        self.value = CONST.TEMP_INIT_DEF
        self.pwm = CONST.PWM_MIN
        self.trusted = True
        self.state = CONST.STOPPED
        self.err_fread_max = CONST.SENSOR_FREAD_FAIL_TIMES
        
    # ----------------------------------------------------------------------
    def start(self):
        '''
        '''
        if self.state == CONST.RUNNING:
           return
        self.log.info("Staring {}".format(self.name))
        self.state = CONST.RUNNING 
        self.pwm_min = int(self.sensors_config.get("pwm_min",CONST.PWM_MIN))
        self.pwm_max = int(self.sensors_config.get("pwm_max",CONST.PWM_MAX))
        self.poll_time = int(self.sensors_config.get("poll_time",CONST.SENSOR_POLL_TIME_DEF))
        self.enable = int(self.sensors_config.get("enable", 1))
        self.err_fread_err_counter_dict = {}
        self.sensor_configure()
        self.update_timestump(1)
     
    def stop(self):
        ''
        if self.state == CONST.STOPPED:
           return
       
        self.pwm = self.pwm_min
        self.log.info("Stopping {}".format(self.name))
        self.state = CONST.STOPPED
       
    # ----------------------------------------------------------------------
    def sensor_configure(self):
        ''

    # ----------------------------------------------------------------------
    def update_timestump(self, timeout=0):
        '''
        '''
        if not timeout:
            timeout = self.poll_time * 1000
        self.poll_time_next = current_milli_time() + timeout

    # ----------------------------------------------------------------------
    def handle_input(self, thermal_table, flow_dir, amb_tmp):
        '''
        '''

    # ----------------------------------------------------------------------
    def handle_err(self, thermal_table, flow_dir, amb_tmp):
        '''
        '''

    # ----------------------------------------------------------------------
    def handle_reading_file_err(self, filename, reset=False):
        '''
        '''
        if not reset:
            if filename in self.err_fread_err_counter_dict.keys():
                self.err_fread_err_counter_dict[filename] += 1
            else:
                self.err_fread_err_counter_dict[filename] = 1
        else:
            self.err_fread_err_counter_dict[filename] = 0

     # ----------------------------------------------------------------------
    def check_reading_file_err(self):
        '''
        '''
        err_keys = []
        for key,val in self.err_fread_err_counter_dict.items():
            if val > self.err_fread_max:
                self.log.error("{}: read file {} errors count {}".format(self.name, key, val))
                err_keys.append(key)
        return err_keys 

    # ----------------------------------------------------------------------
    def get_pwm(self):
        '''
        '''
        return self.pwm

    # ----------------------------------------------------------------------
    def get_value(self):
        '''
        '''
        return self.value
 
    # ----------------------------------------------------------------------
    def get_timestump(self):
        '''
        '''
        return self.poll_time_next

    # ----------------------------------------------------------------------
    def is_trusted(self):
        return True if self.trusted ==  CONST.TRUST_TYPE else False

    # ----------------------------------------------------------------------
    def set_trusted(self,trusted):
        self.trusted = CONST.TRUST_TYPE if trusted  else CONST.UNTRUST_TYPE

    # ----------------------------------------------------------------------
    def calculate_pwm_formula(self):
        '''
        '''
        if self.val_max == self.val_min:
            return self.pwm_min

        pwm = self.pwm_min + ( (self.value - self.val_min) /  (self.val_max - self.val_min)) * (self.pwm_max - self.pwm_min)
        if pwm > self.pwm_max:
            pwm = self.pwm_max

        if pwm < self.pwm_min:
            pwm = self.pwm_min
        return int(round(pwm))

    # ----------------------------------------------------------------------
    def read_val_min_max(self, filename, type, scale=1):
        '''
        '''
        val = self._get_file_val(filename,  self.sensors_config.get(type, CONST.TEMP_MIN_MAX[type]))
        self.log.info("Set {} {} : {}".format(self.name, type, val))
        return val

    # ----------------------------------------------------------------------
    def check_sensor_blocked(self, name=None):
        ''
        if not name:
            name = self.file_in
        blk_filename = "thermal/{}_blacklist".format(name)
        if self._check_file(blk_filename):
            try:
                val_str = self._read_file(blk_filename)
                val = str2bool(val_str)
            except ValueError: 
                return False               
        else:
            return False
        return val
  
    # ----------------------------------------------------------------------
    def process(self, thermal_table, flow_dir, amb_tmp):
        '''
        '''
        if self.check_sensor_blocked():
            self.stop()
        else:
            self.start()
        
        if self.state == CONST.RUNNING:
            self.handle_input(thermal_table, flow_dir, amb_tmp)
            self.handle_err(thermal_table, flow_dir, amb_tmp)

    def info(self):
        return ("\"{}\" val:{} pwm:{} {}".format(self.name, self.value, self.pwm, self.state))


class thermal_sensor(system_device):
        def __init__(self, config, dev_config_dict, logger):
            system_device.__init__(self, config, dev_config_dict, logger)

        # ----------------------------------------------------------------------
        def sensor_configure(self):
            self.val_min = self.read_val_min_max("{}_min".format(self.file_in), "val_min", CONST.TEMP_SENSOR_SCALE)   
            self.val_max = self.read_val_min_max("{}_max".format(self.file_in), "val_max", CONST.TEMP_SENSOR_SCALE)
            self.input_smooth_level = self.sensors_config.get("input_smooth_level", 1)
            self.value_acc = 0

        # ----------------------------------------------------------------------
        def handle_input(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            self.set_trusted(True)
            pwm = self.pwm_min
            if not self._check_file(self.file_in):
                self.handle_reading_file_err(self.file_in)
                self.log.error("Missing file {}. Set pwm for dev {} to {}".format(self.file_in, self.name, self.pwm))
            else:
                try:
                    temperature = int(self._read_file(self.file_in))
                    self.handle_reading_file_err(self.file_in, True)
                    temperature /= CONST.TEMP_SENSOR_SCALE
                    value = int(temperature)
                    
                except:
                    self.log.error("Wrong value reading from file: {}".format(self.file_in))
                    self.handle_reading_file_err(self.file_in)

            # integral filter for soothing temperature change
            self.value_acc -= self.value_acc/self.input_smooth_level
            self.value_acc += value
            self.value = int(round(float(self.value_acc)/self.input_smooth_level))

            if self.value > self.val_max:
                pwm = self.pwm_max
                self.log.notice("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                            self.value,
                                                                            self.val_max,
                                                                            pwm))                       
            elif self.value < self.val_min:
                pwm = self.pwm_min
                self.log.debug("{} value {}".format(self.name, self.value))

            #check if module have sensor interface
            if self.val_max == 0 and self.val_min == 0:
                self.set_trusted(False)
                return

            self.pwm = max(self.calculate_pwm_formula(), pwm)

        # ----------------------------------------------------------------------
        def handle_err(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            # sensor error reading counter
            if self.check_reading_file_err():
                self.pwm = max(self.pwm_max, self.pwm)
            return None

        # ----------------------------------------------------------------------
        def info(self):
            str = "\"{}\" temperature:{}, pwm:{} {}".format(self.name, self.value, self.pwm, self.state)
            return str


class thermal_module_sensor(system_device):
        def __init__(self, config, dev_config_dict, logger):
            system_device.__init__(self, config, dev_config_dict, logger)
            
            result = re.match(r'.*(module\d+)', self.file_in)
            if result and len(result.groups()) > 0:
                module_name = result.group(1)
                self.module_name = module_name
            else:
                self.module_name = ""

         # ----------------------------------------------------------------------
        def sensor_configure(self):
            self.val_max = self.read_val_min_max("thermal/{}/temp_trip_hot".format(self.file_in), "val_max", scale=CONST.TEMP_SENSOR_SCALE)
            self.val_min = self.read_val_min_max("thermal/{}/temp_trip_norm".format(self.file_in), "val_min", scale=CONST.TEMP_SENSOR_SCALE)

            self.refresh_attr_timeout = self.sensors_config.get("refresh_attr_timeout", 0)
            if self.refresh_attr_timeout:
                self.refresh_timeout = current_milli_time() + self.refresh_attr_timeout * 1000
            else:
                self.refresh_timeout = 0
            self.trusted = 0
            
        # ----------------------------------------------------------------------
        def handle_input(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            self.set_trusted(True)
            pwm = self.pwm_min

            if self.refresh_attr_timeout and self.refresh_timeout < current_milli_time():
                self.val_max = self.read_val_min_max("thermal/{}/temp_trip_hot".format(self.file_in), "val_max", scale=CONST.TEMP_SENSOR_SCALE)
                self.val_min = self.read_val_min_max("thermal/{}/temp_trip_norm".format(self.file_in), "val_min", scale=CONST.TEMP_SENSOR_SCALE)
                self.refresh_timeout = current_milli_time() + self.refresh_attr_timeout * 1000

            temp_read_file = "thermal/{}/thermal_zone_temp".format(self.file_in)
            if not self._check_file(temp_read_file):
                self.log.info("Missing file {} :{}.".format(self.name, temp_read_file))
            else:
                try:
                    temperature = int(self._read_file(temp_read_file))
                    self.handle_reading_file_err(temp_read_file, True)
                    temperature /= CONST.TEMP_SENSOR_SCALE
                    # for modules that is not equipped with thermal sensor temperature returns zero 
                    self.value = int(temperature)
                    if self.value != 0:
                        if self.value > self.val_max:
                            pwm = self.pwm_max
                            self.log.notice("{} value({}) more then max({}). Set pwm {}".format(self.name,
                                                                                    self.value,
                                                                                    self.val_max,
                                                                                    pwm))
                        elif self.value < self.val_min:
                            pwm = self.pwm_min
                except:
                    self.log.warn("value reading from file: {}".format(self.file_in))
                    self.handle_reading_file_err(rpm_file_name)
            
            self.log.debug("{} value {}".format(self.name, self.value))
            
            #check if module have sensor interface
            if self.val_max == 0 and self.val_min == 0 and self.value == 0:
                self.set_trusted(False)
                return

            self.pwm = max(self.calculate_pwm_formula(), pwm)

        # ----------------------------------------------------------------------
        def handle_err(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            fault_status = 0
            if self.module_name:
                fault_filename = temp_read_file = "thermal/{}_temp_fault".format(self.module_name)
                if self._check_file(fault_filename):
                    try:
                        fault_status = int(self._read_file(fault_filename))
                        self.handle_reading_file_err(fault_filename, True)
                        if fault_status:
                            self.log.error("{} temp_fault {}".format(fault_filename, fault_status))
                            self.set_trusted(False)
                    except:
                        self.log.error("Value reading from file: {}".format(fault_filename))
                        self.handle_reading_file_err(fault_filename)                   
                else:
                    self.log.error("{} : {} attribute not exist".format(self.name, fault_filename))
                    self.handle_reading_file_err(fault_filename)

            # sensor error reading counter
            err_keys = self.check_reading_file_err()
            err_len = len(err_keys)
            if err_keys:
                if "thermal_zone_temp" in err_keys:
                    self.set_trusted(False)
                    err_len -= 1
                # we have some other errors other then thermal_zone_temp
                if err_len > 0:
                    self.pwm = max(self.pwm_max, self.pwm)

            return None

        # ----------------------------------------------------------------------
        def info(self):
            str = "\"{}\" temperature {}, tmin {}, tmax {}, pwm {}, {}".format(self.name, self.value, self.val_min, self.val_max, self.pwm, self.state)
            return str


class psu_sensor(system_device):
        def __init__(self, config, dev_config_dict, logger):
            system_device.__init__(self, config, dev_config_dict, logger)

            self.val_min = self.read_val_min_max("thermal/{}_fan_min".format(self.file_in), "val_min")
            self.val_max = self.read_val_min_max("thermal/{}_fan_max".format(self.file_in), "val_max")
            self.prsnt_err_pwm_min = self._get_file_val("config/pwm_min_psu_not_present")
            
            self.rpm_trh = 0.15      
            self.fault_list = []

        # ----------------------------------------------------------------------
        def _get_status(self):
            '''
            '''
            psu_status_filename = "thermal/{}_status".format(self.file_in)
            psu_status = 0
            if not self._check_file(psu_status_filename):
                self.log.error("Missing file {} dev {}".format(psu_status_filename, self.name))
                self.handle_reading_file_err(psu_status_filename)
            else:
                try:
                    psu_status = int(self._read_file(psu_status_filename))
                    self.handle_reading_file_err(psu_status_filename, True)
                except:
                    self.log.error("Can't read {}".format(psu_status_filename))
                    self.handle_reading_file_err(psu_status_filename)
            return psu_status

        # ----------------------------------------------------------------------
        def set_pwm(self, pwm):
            present = self._thermal_read_file_int("{0}_pwr_status".format(self.file_in))
            if present == 1:
                bus     = self._read_file("config/{0}_i2c_bus".format(self.file_in))
                addr    = self._read_file("config/{0}_i2c_addr".format(self.file_in))
                command = self._read_file("config/fan_command")
                subprocess.call("i2cset -f -y {0} {1} {2} {3} wp".format(bus, addr, command, pwm), shell = True)

        # ----------------------------------------------------------------------
        def handle_input(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            self.pwm = self.pwm_min
            rpm_file_name = "thermal/{}_fan1_speed_get".format(self.file_in)
            if not self._check_file(rpm_file_name):
                self.log.error("Missing file {} dev {}".format(rpm_file_name, self.name))
                self.handle_reading_file_err(rpm_file_name)
            else:
                try:
                    self.value = int(self._read_file(rpm_file_name))
                    self.handle_reading_file_err(rpm_file_name, True)
                    self.log.debug("{} value {}".format(self.name, self.value))
                except:
                    self.log.error("Value reading from file: {}".format(rpm_file_name))
                    self.handle_reading_file_err(rpm_file_name)
            return 

        # ----------------------------------------------------------------------
        def handle_err(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            self.fault_list = []
            pwm = self.pwm_min
            psu_status = self._get_status()
            if psu_status == 0:
                # PSU status error. Calculating dmin based on this information
                self.fault_list.append("present")
                if self.prsnt_err_pwm_min:
                    pwm = self.prsnt_err_pwm_min
                else:
                    pwm = g_get_dmin(thermal_table, amb_tmp,  [flow_dir, "psu_err", 'present'])
                self.log.error("{} psu_status {}".format(self.name, psu_status))

            # sensor error reading counter
            if self.check_reading_file_err():
                self.pwm = max(self.pwm_max, self.pwm)
            self.pwm = max(pwm, self.pwm)
            
            return

        # ----------------------------------------------------------------------
        def info(self):
            return "\"{}\" FAN rpm:{}, faults:[{}] pwm: {}, {}".format(self.name, self.value, ",".join(self.fault_list), self.pwm, self.state)


class fan_sensor(system_device):
        def __init__(self, config, dev_config_dict, logger):
            system_device.__init__(self, config, dev_config_dict, logger)
            
            self.val_min = self.read_val_min_max("config/fan_min_speed", "val_min")
            self.val_max = self.read_val_min_max("config/fan_max_speed", "val_max")
            self.tacho_cnt = dev_config_dict.get("tacho_cnt", 1)
            self.fan_drwr_id = int(dev_config_dict["drwr_id"])
            self.tacho_idx = ((self.fan_drwr_id-1) * self.tacho_cnt) + 1
            self.fan_dir = self._get_dir()
            self.fan_dir_fail = False
            self.is_calibrated = False
            self.rpm_pwm_scale = self.val_max / 255

            self.rpm_trh = 0.15
            self.rpm_relax_timeout = CONST.FAN_RELAX_TIME * 1000
            self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout
            self.name = "{}:{}".format(self.name, range(self.tacho_idx, self.tacho_idx + self.tacho_cnt))

        # ----------------------------------------------------------------------
        def sensor_configure(self):
            ''
            self.value = [0] * self.tacho_cnt
            
            self.fault_list = []
            self.pwm = self.pwm_min
            self.pwm_last = 0
            self.rpm_valid_state = True

            if not self.is_calibrated:
                self.log.info("{}: Preparing calibration".format(self.name))
                # get real FAN max_speed
                pwm = int(self._read_file("thermal/pwm1"))
                # check if PWM max already set
                if pwm < 255:
                    self._thermal_write_file("pwm1", 255)
                    time.sleep(int(self.rpm_relax_timeout/1000))
    
                # get FAN RPM 
                rpm = 0
                self.log.info("{}: Calibrating FAN rpm max...".format(self.name))
                for i in range(CONST.FAN_CALIBRATE_CYCLES):
                    for tacho_idx in range(self.tacho_idx, self.tacho_idx + self.tacho_cnt):
                        time.sleep(0.5)
                        rpm += self._thermal_read_file_int("fan{}_speed_get".format(tacho_idx))
    
                rpm_max_real = float(rpm) / (CONST.FAN_CALIBRATE_CYCLES * self.tacho_cnt)
                self.rpm_pwm_scale = rpm_max_real / 255
                self.log.info("{}: rpm: max {} real {} scale {}".format(self.name, self.val_max, rpm_max_real, self.rpm_pwm_scale))
                self.is_calibrated = True

        # ----------------------------------------------------------------------
        def _get_dir(self):
            '''
            '''
            dir_val = self._read_file("thermal/fan{}_dir".format(self.fan_drwr_id))
            dir = CONST.C2P if dir_val=="1" else CONST.P2C
            return dir
      
        # ----------------------------------------------------------------------
        def _get_status(self):
            '''
            '''
            status_filename =  "thermal/fan{}_status".format(self.fan_drwr_id)
            status = None
            if not self._check_file(status_filename):
                self.log.error("Missing file {} dev {}".format(status_filename, self.name))
                self.handle_reading_file_err(status_filename)
            else:
                try:
                    status = int(self._read_file(status_filename))
                    self.handle_reading_file_err(status_filename, True)
                except:
                    self.log.error("Value reading from file: {}".format(status_filename))
                    self.handle_reading_file_err(status_filename)
            return 

        # ----------------------------------------------------------------------
        def _get_fault(self):
            '''
            '''
            fan_fault = []
            for tacho_idx in range(self.tacho_idx, self.tacho_idx + self.tacho_cnt):
                fan_fault_filename =  "thermal/fan{}_fault".format(tacho_idx)
                if not self._check_file(fan_fault_filename):
                    self.log.info("Missing file {} dev {}".format(fan_fault_filename, self.name))
                else:
                    try:
                        val = int(self._read_file(fan_fault_filename))
                        fan_fault.append(val) 
                    except:
                        self.log.error("Value reading from file: {}".format(fan_fault_filename))
            return fan_fault

        # ----------------------------------------------------------------------
        def _validate_fan_rpm(self):
            '''
            '''
            pwm_curr = self._thermal_read_file_int("pwm1")
            if pwm_curr != self.pwm_last:
                self.pwm_last = self._thermal_read_file_int("pwm1")
                self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout
            elif self.rpm_relax_timestump < current_milli_time():
                self.rpm_relax_timestump = current_milli_time() + self.rpm_relax_timeout
                self.rpm_valid_state = True
                for tacho_idx in range(self.tacho_idx, self.tacho_idx + self.tacho_cnt):
                    rpm_real = self._thermal_read_file_int("fan{}_speed_get".format(tacho_idx))
                    rpm_expected = int(pwm_curr * self.rpm_pwm_scale)
                    rpm_diff = abs(rpm_real - rpm_expected)
                    if float(rpm_diff) / rpm_expected >= self.rpm_trh:
                        self.log.error("{} read RPM_{} {} too much different than expected {}".format(self.name, tacho_idx, rpm_real, rpm_expected))
                        self.rpm_valid_state = False
    
            return self.rpm_valid_state

        # ----------------------------------------------------------------------
        def get_dir(self):
            return self.fan_dir

        # ----------------------------------------------------------------------
        def handle_input(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            self.pwm = self.pwm_min
            for tacho_id in range(0, self.tacho_cnt):
                rpm_file_name = "thermal/fan{}_speed_get".format(self.tacho_idx + tacho_id)
                if not self._check_file(rpm_file_name):
                    self.log.error("Missing file {} dev {}".format(rpm_file_name, self.name))
                    self.handle_reading_file_err(rpm_file_name)
                else:
                    try:
                        self.value[tacho_id] = int(self._read_file(rpm_file_name))
                        self.handle_reading_file_err(rpm_file_name, True)
                        self.log.debug("{} value {}".format(self.name, self.value))
                    except:
                        self.log.error("Value reading from file: {}".format(rpm_file_name))
                        self.handle_reading_file_err(rpm_file_name)
            return

        # ----------------------------------------------------------------------
        def handle_err(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            self.fault_list = []
            pwm = self.pwm_min
            fan_status = self._get_status()
            if fan_status == 0:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", 'present'])
                self.fault_list.append("present")
                self.log.error("{} status {}. Set PWM low threshold {}".format(self.name, pwm))


            fan_fault = self._get_fault()
            if 1 in fan_fault:
                pwm = g_get_dmin(thermal_table, amb_tmp, [flow_dir, "fan_err", 'fault'])
                self.fault_list.append("fault")
                self.log.error("{} tacho {} fault. Set PWM low threshold {}".format(self.name, fan_fault, pwm))

            if not self._validate_fan_rpm():
                self.fault_list.append("tacho")
                pwm = max(g_get_dmin(thermal_table, amb_tmp, [flow_dir,  "fan_err", 'tacho']), pwm)
                self.log.error("{} incorrect rpm {}. Set PWM low threshold {}".format(self.name, self.value, pwm))

            if self.fan_dir_fail:
                self.fault_list.append("direction")
                pwm = max(g_get_dmin(thermal_table, amb_tmp, [flow_dir,  "fan_err", 'direction']), pwm)
                self.log.error("{} dir error. Set PWM low threshold {}".format(self.name, self.pwm))

            # sensor error reading counter
            if self.check_reading_file_err():
                self.pwm = max(self.pwm_max, self.pwm)
            self.pwm = max(pwm, self.pwm)

            return

        # ----------------------------------------------------------------------
        def info(self):
            
            str = "\"{}\" rpm:{}, dir:{} faults:[{}] pwm {} {}".format(self.name, self.value, self.fan_dir, ",".join(self.fault_list), self.pwm, self.state)
            return str


class ambiant_thermal_sensor(system_device):
        def __init__(self, config, dev_config_dict, logger):
            system_device.__init__(self, config, dev_config_dict, logger)
           
            self.file_in = dev_config_dict.get("file_in_dict", None)
            self.value_dict = {CONST.C2P_SENS: 0, CONST.P2C_SENS: 0}
            self.flow_dir = CONST.C2P
            self.trusted = CONST.UNTRUST_TYPE

        # ----------------------------------------------------------------------
        def get_flow_dir(self):
            return self.flow_dir

        # ----------------------------------------------------------------------
        def set_trusted(self, trusted_type):
            self.trusted = trusted_type

        # ----------------------------------------------------------------------
        def handle_input(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            # reading all amb sensors
            for key, file_in in self.file_in.items():
                if not self._check_file(file_in):
                    self.handle_reading_file_err(self.file_in)
                    self.log.error("Missing file {}. Set pwm for dev {} to {}".format(file_in, self.name, self.pwm))
                else:
                    try:
                        temperature = int(self._read_file(file_in))
                        self.handle_reading_file_err(file_in, True)
                        temperature /= CONST.TEMP_SENSOR_SCALE
                        self.value_dict[file_in] = int(temperature)
                    except:
                        self.log.error("Error value reading from file: {}".format(self.file_in))
                        self.handle_reading_file_err(self.file_in)
    
                self.log.debug("{} {} value {}".format(self.name, file_in, temperature))

            if self.value_dict[CONST.P2C_SENS] > self.value_dict[CONST.C2P_SENS]:
                self.flow_dir = CONST.C2P
                self.value = self.value_dict[CONST.C2P_SENS]
            elif self.value_dict[CONST.P2C_SENS] < self.value_dict[CONST.C2P_SENS]:
                self.flow_dir = CONST.P2C
                self.value = self.value_dict[CONST.P2C_SENS]
            else:
                self.flow_dir = CONST.UNKNOWN
                self.value = self.value_dict[CONST.P2C_SENS]

            self.pwm = g_get_dmin(thermal_table, self.value,  [self.flow_dir , self.trusted])

        # ----------------------------------------------------------------------
        def handle_err(self, thermal_table, flow_dir, amb_tmp):
            '''
            '''
            # sensor error reading counter
            if self.check_reading_file_err():
                self.pwm = max(self.pwm_max, self.pwm)
            return None

        # ----------------------------------------------------------------------
        def info(self):
            str = "\"{}\" temperature:{}, dir:{}, pwm:{}, {}".format(self.name, self.value_dict, self.flow_dir, self.pwm, self.state)
            return str

class ThermalManagement(hw_managemet_file_op):
    '''
        @summary:
            Main class of thermal algorithm.
            Provide system monitoring and thermal control
    '''

    def __init__(self, config):
        '''
        @summary:
            Init  thermal algorithm
        @param config: global thermal configuration        
        '''
        hw_managemet_file_op.__init__(self, config)
        self.log = Logger(config[CONST.LOG_USE_SYSLOG], config[CONST.LOG_FILE], config["verbosity"])
        self.periodic_report_worker_timer = None
        self.thermal_table = None
        self.config = config

        sensors_config = {}
        if config[CONST.SENSORS_CONFIG]:
            file = config[CONST.SENSORS_CONFIG]
            if not os.path.isfile(file):
                self.log.error("Can't load sensor config. Missing file {}".format(file))
            else:
                with open(file) as f:
                    sensors_config = json.load(f)
        else:
            file = "{}/config/tc_sensors.conf".format(self.root_folder)
            if os.path.isfile(file):
                with open(file) as f:
                    sensors_config = json.load(f)
                    
        if self._check_file("config/periodic_report"):
            self.periodic_report_time = int(self._read_file("config/periodic_report"))
            self._rm_file("config/periodic_report")
        else:
            self.periodic_report_time = CONST.PERIODIC_REPORT_TIME
 
        self.sensors_config = sensors_config
        self.sys_typename = self.config.get("systypename", None)

        self.dev_obj_list = [] 

        self.pwm = 50
        self.pwm_target = 50
        self.pwm_sooth_step_max = 10
        self.pwm_worker_poll_time = 2
        self.pwm_worker_timer = None
        
        self.max_tachos = CONST.FAN_TACHO_COUNT_DEF
        self.fan_drwr_num = CONST.FAN_DRWR_COUNT_DEF
        self.psu_count = CONST.PSU_COUNT_DEF
        self.module_counter = CONST.MODULE_COUNT_DEF
        self.gearbox_counter = CONST.GEARBOX_COUNT_DEF

        self.state = CONST.UNDEFINED
        self.exit = Event()

    # ---------------------------------------------------------------------
    def _collect_hw_info(self):

        try:
            self.max_tachos = int(self._read_file('config/max_tachos'))
        except:
            self.log.error("Missing max tachos config.")
            sys.exit(1)

        try:
            self.fan_drwr_num = int(self._read_file('config/fan_drwr_num'))
        except:
            self.log.error("Missing fan_drwr_num config.")
            sys.exit(1)

        try :
            self.psu_count = int(self._read_file("config/hotplug_psus"))
        except:
            self.log.error("Missing hotplug_psus config.")
            sys.exit(1)

        self.fan_drwr_capacity = int(self.max_tachos / self.fan_drwr_num)
        self.module_counter = int(self._get_file_val("config/module_counter", CONST.MODULE_COUNT_DEF) )
        self.gearbox_counter = int(self._get_file_val("config/gearbox_counter", CONST.GEARBOX_COUNT_DEF))

    # ----------------------------------------------------------------------
    def _get_dev_obj(self, name):
        '''
        '''
        for dev_obj in self.dev_obj_list:
            if  name == dev_obj.name:
                return dev_obj
        return None

    # ----------------------------------------------------------------------
    def _check_untrusted_module_sensor(self):
        '''
        @summary:
            Check if some module if fault stste
        @return: True - on sensor failure False - Ok
        '''
        for dev_obj in self.dev_obj_list:
            if dev_obj.enable:
                if not dev_obj.is_trusted():
                    return False
        return True

    def _check_fan_dir(self):
        '''
        '''
        c2p_count = 0
        p2c_count = 0
        fan_obj_list = []
        for obj in self.dev_obj_list:
            fan_dir = getattr(obj, "fan_dir", None)
            if fan_dir == CONST.C2P:
                c2p_count += 1
            elif fan_dir == CONST.P2C:
                p2c_count += 1
        dir = CONST.C2P if c2p_count >= p2c_count else CONST.P2C

        for obj in self.dev_obj_list:
            fan_dir = getattr(obj, "fan_dir", None)
            if fan_dir != None and fan_dir != dir:
                setattr(obj, "fan_dir_fail", 1)

    # ---------------------------------------------------------------------- 
    def _update_psu_fan_speed(self, pwm):
        '''
        @summary:
            Set PSU fan depending of current cooling state
        @return: pwm value calculated based on PSU state
        '''
        for psu_idx in range(1, self.psu_count + 1):
            psu_obj = self._get_dev_obj("psu{}".format(psu_idx))
            if psu_obj:
                psu_obj.set_pwm(pwm)

    # ----------------------------------------------------------------------
    def _write_pwm(self, pwm_val):
        self.log.info("Update FAN PWM {}".format(self.pwm))
        self._thermal_write_file('pwm1', int(self.pwm * 255 / 100))     

    # ----------------------------------------------------------------------
    def _set_pwm(self, pwm, threshold=CONST.PWM_CHANGE_TRH):
        '''
        '''
        pwm = int(pwm)
        pwm_diff = abs(pwm - self.pwm_target)
        if pwm_diff >= threshold:
            self.log.notice("PWM target changed from {} to PWM {}".format(self.pwm_target, pwm))
            self._update_psu_fan_speed(pwm)
            self.pwm_target = pwm
            if self.pwm_worker_timer:
                self.pwm_worker_timer.start()
            else:
                self.pwm = pwm
                self._write_pwm(self.pwm)

    # ----------------------------------------------------------------------
    def _pwm_worker(self):
        ''
        if self.pwm_target == self.pwm:
            pwm_real = self._thermal_read_file_int("pwm1")
            pwm_set = self.pwm * 255 / 100
            if pwm_real != pwm_set:
                self.log.warn("Uunexpected pwm1 value {}. Force set to {}".format(pwm_real, pwm_set))
                self._write_pwm(self.pwm)
            self.pwm_worker_timer.stop()
            return

        self.log.debug("PWM target: {} curr: {}".format(self.pwm_target, self.pwm))
        diff = abs(self.pwm_target - self.pwm)

        diff = int(round((float(diff) / 2 + 0.5)))
        if diff > self.pwm_sooth_step_max:
            diff = self.pwm_sooth_step_max     

        if self.pwm_target > self.pwm:
            self.pwm += diff
        else:
            self.pwm -= diff

        self._write_pwm(self.pwm)

    # ----------------------------------------------------------------------
    def sensor_add_config(self, type, name, extra_config = {}):
        if  name not in self.sensors_config.keys():
            self.sensors_config[name] = {"type" : type}
        self.sensors_config[name]["name"] = name

        for name_mask in sensor_by_name_def_config.keys():
            if re.match(name_mask, name):
                add_missing_to_dict(self.sensors_config[name], sensor_by_name_def_config[name_mask])
                break;

        if extra_config:
            add_missing_to_dict(self.sensors_config[name], extra_config)

    # ----------------------------------------------------------------------
    def get_obj_name(obj):
        return obj.name

    # ----------------------------------------------------------------------
    def pwm_strategy_max(self, pwm_list):
        return max(pwm_list)

    # ----------------------------------------------------------------------
    def pwm_strategy_avg(self, pwm_list):
        return float(sum(pwm_list)) / len(pwm_list)

    # ----------------------------------------------------------------------
    def _match_system_table(self, typename):
        thermal_table = None
        for typename_mask in THERMAL_TABLE_LIST.keys():
            if re.match(typename_mask, typename):
                thermal_table = THERMAL_TABLE_LIST[typename_mask]
                break;
        return thermal_table

    # ----------------------------------------------------------------------
    def init_system_table(self):
        if self.sys_typename:
            self.thermal_table = self._match_system_table(self.sys_typename)
        else:
            typename = self._read_file("config/thermal_type")
            if typename:
                typename = "tc_t{}".format(typename)
            else:
                sku_filename = "/sys/devices/virtual/dmi/id/product_sku"
                if os.path.isfile(sku_filename):
                    with open(sku_filename, 'r') as sku_file:
                        typename = content_file.sku_file().rstrip("\n")
            if typename:
                self.thermal_table = self._match_system_table(self.sys_typename)

        if not self.thermal_table:
            self.thermal_table = THERMAL_TABLE_LIST['default']
            self.log.notice("System typename {} not found. Using default thermal type:{}".format(self.sys_typename, self.thermal_table['name']))
        else:
            self.log.notice("System typename \"{}\" thermal type:\"{}\"".format(self.sys_typename, self.thermal_table['name']))


    # ----------------------------------------------------------------------
    def init(self):
        '''
        '''
        self.log.notice("********************************")
        self.log.notice("Init thermal control ver: v.{}".format(VERSION))
        self.log.notice("********************************")
        self._collect_hw_info()

        # Set initial PWM to maximum
        self._set_pwm(CONST.PWM_MIN, threshold=CONST.PWM_CHANGE_TRH)

        self.init_system_table()
        
        for psu_idx in range(1,self.psu_count+1):
            name = "psu{}".format(psu_idx)
            in_file = "psu{}".format(psu_idx)
            self.sensor_add_config("psu_sensor", name, {"file_in": in_file})
 
        for fan_idx in range(1,self.fan_drwr_num+1):
            name = "fan{}".format(fan_idx)
            self.sensor_add_config("fan_sensor", name, {"file_in": name, "drwr_id": fan_idx, "tacho_cnt" : self.fan_drwr_capacity})

        for module_idx in range(1,self.module_counter+1):
            name = "mlxsw-module{}".format(module_idx)
            self.sensor_add_config("thermal_module_sensor", name, {"file_in": name})
          
        for gearbox_idx in range(1,self.gearbox_counter+1):
            name = "mlxsw-gearbox{}".format(gearbox_idx)
            self.sensor_add_config("thermal_module_sensor", name, {"file_in": name})   

        name = "mlxsw"
        self.sensor_add_config("thermal_module_sensor", name, {"file_in": name})

        name = "cpu_pack"
        self.sensor_add_config("thermal_sensor", name, {"file_in": "thermal/cpu_pack", "val_min": 15, "val_max": 65})

        name = "sensor_amb"
        self.sensor_add_config("ambiant_thermal_sensor", name, {"file_in_dict": {CONST.C2P: CONST.C2P_SENS, CONST.P2C: CONST.P2C_SENS}})

        #print(json.dumps(self.sensors_config, sort_keys=True, indent=4))

        for key,val in self.sensors_config.items():
            try:
                dev_class_ = globals()[val["type"]]
            except Exception as err:
                print (err.message)
            dev_obj = dev_class_(self.config, val, self.log)
            if not dev_obj:
                self.log.error("{} create failed".format(key))
                sys.exit(1)

            self.dev_obj_list.append(dev_obj)
        self.dev_obj_list.sort(key=lambda x: x.name)
        self._check_fan_dir()

        #print (json.dumps(self.sensors_config, indent=4))

    # ----------------------------------------------------------------------
    def start(self):
        ''
        if self.state != CONST.RUNNING:
            self.log.notice("Thermal control state changed {} -> {}".format(self.state, CONST.RUNNING))
            self.state = CONST.RUNNING

            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    dev_obj.start()

            self._write_file("config/periodic_report", self.periodic_report_time)

            if not self.periodic_report_worker_timer:
                self.periodic_report_worker_timer = RepeatedTimer(self.periodic_report_time , self.print_periodic_info)
            self.periodic_report_worker_timer.start()

            if not self.pwm_worker_timer:
                self.pwm_worker_timer = RepeatedTimer(self.pwm_worker_poll_time, self._pwm_worker)
            self.pwm_worker_timer.stop()

    # ----------------------------------------------------------------------
    def stop(self):
        ''
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

            self._set_pwm(CONST.PWM_MAX, threshold=0)

    # ----------------------------------------------------------------------
    def run(self):
        '''
        '''
        signal.signal(signal.SIGTERM, self.sig_handler)
        signal.signal(signal.SIGINT,  self.sig_handler)
        signal.signal(signal.SIGHUP,  self.sig_handler)

        self.log.notice("********************************")
        self.log.notice("Run thermal control")
        self.log.notice("********************************")

        while not self.exit.is_set():
            if self.is_suspend():
                self.stop()
                self.exit.wait(5)
                continue
            else:
                self.start()

            amb_sensor_dev = self._get_dev_obj('sensor_amb')
            if amb_sensor_dev:
                type = CONST.TRUST_TYPE if self._check_untrusted_module_sensor() else CONST.UNTRUST_TYPE
                amb_tmp = amb_sensor_dev.get_value()
                flow_dir = amb_sensor_dev.get_flow_dir()
                amb_sensor_dev.set_trusted(type)

            pwm_list = []
            timestump_next = current_milli_time() + 60 * 1000
            for dev_obj in self.dev_obj_list:
                if dev_obj.enable:
                    if current_milli_time() >= dev_obj.get_timestump():
                        # process sensors
                        dev_obj.process(self.thermal_table, flow_dir, amb_tmp)
                        dev_obj.update_timestump()

                    pwm = dev_obj.get_pwm()
                    self.log.debug("{0:25}: PWM {1}".format(dev_obj.name, pwm))
                    pwm_list.append(pwm)

                    obj_timestump = dev_obj.get_timestump()
                    timestump_next = min(obj_timestump, timestump_next)

            pwm = self.pwm_strategy_max(pwm_list)
            self.log.debug("Result PWM {}".format(pwm))
            self._set_pwm(pwm)
            sleep_ms = int(timestump_next - current_milli_time())
            if sleep_ms < 1000:
                 sleep_ms = 1000
            self.log.debug("sleeping {} msec".format(sleep_ms))
            self.exit.wait(sleep_ms/1000)

    # ----------------------------------------------------------------------
    def sig_handler(self, sig, frame):
        '''
        @summary:
            Signal handler for trination signals
        '''
        if sig in [signal.SIGTERM, signal.SIGINT, signal.SIGHUP]:
            self.log.notice("Thermal control was terminated PID={}".format( os.getpid() ))
            self.stop()
            self.exit.set()

        sys.exit(1)

    # ----------------------------------------------------------------------
    def print_periodic_info(self):
        ''
        self.log.notice("Thermal periodic report")
        self.log.notice("================================")
        self.log.notice("Cooling(%) pwm {} strategy(maximum)".format(self.pwm_target))
        self.log.notice("================================")
        for dev_obj in self.dev_obj_list:
            if dev_obj.enable:
                obj_info_str = dev_obj.info()
                if obj_info_str:
                    self.log.notice(obj_info_str)
        self.log.notice("================================")

    # ----------------------------------------------------------------------
    def is_suspend(self):
        ''
        suspend_filename = CONST.SUSPEND_FILE
        if self._check_file(suspend_filename):
            try:
                val_str = self._read_file(suspend_filename)
                val = str2bool(val_str)
            except ValueError: 
                return False               
        else:
            return False
        return val

def str2bool_argparse(val):
    '''
    @summary:
        Convert input val value to bool
    '''
    res = str2bool(val)
    if res is None:
        raise argparse.ArgumentTypeError('Boolean value expected.')
    return res

class RawTextArgumentDefaultsHelpFormatter(
        argparse.ArgumentDefaultsHelpFormatter,
        argparse.RawTextHelpFormatter
    ):
        pass
if __name__ == '__main__':
    CMD_PARSER = argparse.ArgumentParser(formatter_class=RawTextArgumentDefaultsHelpFormatter, description='hw-management thermal control')
    CMD_PARSER.add_argument('--version', action='version', version='%(prog)s ver:{}'.format(VERSION))
    CMD_PARSER.add_argument('--sensors_config', 
                        dest=CONST.SENSORS_CONFIG,
                        help='Config file with additional sensors description', 
                        default=None)
    CMD_PARSER.add_argument('-l', '--log_file',
                        dest=CONST.LOG_FILE,
                        help='Add output also to log file. Pass file name here',
                        default="/tmp/tc_log")
    CMD_PARSER.add_argument('-s', '--syslog',
                        dest=CONST.LOG_USE_SYSLOG,
                        help='enable/disable output to syslog',
                        type=str2bool_argparse, default=True)
    CMD_PARSER.add_argument('-t', '--systypename',
                        dest="systypename",
                        help='System name/type/SKU (MSN2700, HI110, VMOD0001)',
                        default="default")
    CMD_PARSER.add_argument('-v', '--verbosity',
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
    CMD_PARSER.add_argument('-r', '--root_folder',
                        dest=CONST.HW_MGMT_ROOT,
                        help='Define custon hw-management root folder',
                        default=CONST.HW_MGMT_FOLDER_DEF)
    args = vars(CMD_PARSER.parse_args())
    thermal_management = ThermalManagement(args)

    try:
       thermal_management.init()
       thermal_management.run()
    except:
        thermal_management.log.error(traceback.format_exc())
        thermal_management.stop()

    sys.exit(0)
  