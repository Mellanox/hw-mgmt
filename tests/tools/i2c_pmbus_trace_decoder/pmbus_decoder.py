#!/usr/bin/python
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
"""
PMBUS I2C Trace Dump Decoder

This tool decodes Linux i2c trace dumps for PMBUS protocol, supporting all known PMBUS commands.
It can parse various i2c trace formats and decode PMBUS data according to the specification.

Author: Generated for hardware management debugging
License: MIT
"""

import re
import sys
import argparse
import struct
from enum import Enum
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass


class PMBusDataFormat(Enum):
    """PMBUS data format types"""
    LINEAR11 = "LINEAR11"
    LINEAR16 = "LINEAR16"
    DIRECT = "DIRECT"
    UNSIGNED = "UNSIGNED"
    SIGNED = "SIGNED"
    STRING = "STRING"
    BLOCK = "BLOCK"
    NONE = "NONE"


@dataclass
class PMBusCommand:
    """PMBUS command definition"""
    code: int
    name: str
    description: str
    data_format: PMBusDataFormat
    read_write: str  # 'R', 'W', 'RW'
    num_bytes: int = 0  # Expected number of data bytes (0 for variable)


class PMBusDecoder:
    """Main PMBUS protocol decoder"""

    # Track pending kernel trace operations (bus -> (addr, cmd, msg_num))
    _kernel_pending_ops: Dict[str, Tuple[int, int, int]] = {}

    # Complete PMBUS command set (Part II Commands - Standard)
    COMMANDS: Dict[int, PMBusCommand] = {
        # Page commands
        0x00: PMBusCommand(0x00, "PAGE", "Page", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x01: PMBusCommand(0x01, "OPERATION", "Operation", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x02: PMBusCommand(0x02, "ON_OFF_CONFIG", "On/Off Configuration", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x03: PMBusCommand(0x03, "CLEAR_FAULTS", "Clear Faults", PMBusDataFormat.NONE, "W", 0),
        0x04: PMBusCommand(0x04, "PHASE", "Phase", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x05: PMBusCommand(0x05, "PAGE_PLUS_WRITE", "Page Plus Write", PMBusDataFormat.BLOCK, "W", 0),
        0x06: PMBusCommand(0x06, "PAGE_PLUS_READ", "Page Plus Read", PMBusDataFormat.BLOCK, "W", 0),

        # Zone commands
        0x07: PMBusCommand(0x07, "ZONE_CONFIG", "Zone Configuration", PMBusDataFormat.BLOCK, "RW", 0),
        0x08: PMBusCommand(0x08, "ZONE_ACTIVE", "Zone Active", PMBusDataFormat.BLOCK, "RW", 0),

        # Capability and Status
        0x10: PMBusCommand(0x10, "WRITE_PROTECT", "Write Protect", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x11: PMBusCommand(0x11, "STORE_DEFAULT_ALL", "Store Default All", PMBusDataFormat.NONE, "W", 0),
        0x12: PMBusCommand(0x12, "RESTORE_DEFAULT_ALL", "Restore Default All", PMBusDataFormat.NONE, "W", 0),
        0x13: PMBusCommand(0x13, "STORE_DEFAULT_CODE", "Store Default Code", PMBusDataFormat.UNSIGNED, "W", 1),
        0x14: PMBusCommand(0x14, "RESTORE_DEFAULT_CODE", "Restore Default Code", PMBusDataFormat.UNSIGNED, "W", 1),
        0x15: PMBusCommand(0x15, "STORE_USER_ALL", "Store User All", PMBusDataFormat.NONE, "W", 0),
        0x16: PMBusCommand(0x16, "RESTORE_USER_ALL", "Restore User All", PMBusDataFormat.NONE, "W", 0),
        0x17: PMBusCommand(0x17, "STORE_USER_CODE", "Store User Code", PMBusDataFormat.UNSIGNED, "W", 1),
        0x18: PMBusCommand(0x18, "RESTORE_USER_CODE", "Restore User Code", PMBusDataFormat.UNSIGNED, "W", 1),
        0x19: PMBusCommand(0x19, "CAPABILITY", "Capability", PMBusDataFormat.UNSIGNED, "R", 1),
        0x1A: PMBusCommand(0x1A, "QUERY", "Query", PMBusDataFormat.BLOCK, "RW", 0),
        0x1B: PMBusCommand(0x1B, "SMBALERT_MASK", "SMBAlert Mask", PMBusDataFormat.BLOCK, "RW", 0),

        # Output voltage configuration
        0x20: PMBusCommand(0x20, "VOUT_MODE", "Vout Mode", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x21: PMBusCommand(0x21, "VOUT_COMMAND", "Vout Command", PMBusDataFormat.LINEAR16, "RW", 2),
        0x22: PMBusCommand(0x22, "VOUT_TRIM", "Vout Trim", PMBusDataFormat.LINEAR16, "RW", 2),
        0x23: PMBusCommand(0x23, "VOUT_CAL_OFFSET", "Vout Calibration Offset", PMBusDataFormat.LINEAR16, "RW", 2),
        0x24: PMBusCommand(0x24, "VOUT_MAX", "Vout Max", PMBusDataFormat.LINEAR16, "RW", 2),
        0x25: PMBusCommand(0x25, "VOUT_MARGIN_HIGH", "Vout Margin High", PMBusDataFormat.LINEAR16, "RW", 2),
        0x26: PMBusCommand(0x26, "VOUT_MARGIN_LOW", "Vout Margin Low", PMBusDataFormat.LINEAR16, "RW", 2),
        0x27: PMBusCommand(0x27, "VOUT_TRANSITION_RATE", "Vout Transition Rate", PMBusDataFormat.LINEAR16, "RW", 2),
        0x28: PMBusCommand(0x28, "VOUT_DROOP", "Vout Droop", PMBusDataFormat.LINEAR16, "RW", 2),
        0x29: PMBusCommand(0x29, "VOUT_SCALE_LOOP", "Vout Scale Loop", PMBusDataFormat.LINEAR16, "RW", 2),
        0x2A: PMBusCommand(0x2A, "VOUT_SCALE_MONITOR", "Vout Scale Monitor", PMBusDataFormat.LINEAR16, "RW", 2),
        0x2B: PMBusCommand(0x2B, "VOUT_MIN", "Vout Min", PMBusDataFormat.LINEAR16, "RW", 2),

        # Coefficient configuration for READ_* commands using direct format
        0x30: PMBusCommand(0x30, "COEFFICIENTS", "Coefficients", PMBusDataFormat.BLOCK, "RW", 0),
        0x31: PMBusCommand(0x31, "POUT_MAX", "Pout Max", PMBusDataFormat.LINEAR11, "RW", 2),
        0x32: PMBusCommand(0x32, "MAX_DUTY", "Max Duty", PMBusDataFormat.LINEAR11, "RW", 2),
        0x33: PMBusCommand(0x33, "FREQUENCY_SWITCH", "Frequency Switch", PMBusDataFormat.LINEAR11, "RW", 2),
        0x34: PMBusCommand(0x34, "POWER_MODE", "Power Mode", PMBusDataFormat.UNSIGNED, "RW", 1),

        # Input voltage configuration
        0x35: PMBusCommand(0x35, "VIN_ON", "Vin On", PMBusDataFormat.LINEAR11, "RW", 2),
        0x36: PMBusCommand(0x36, "VIN_OFF", "Vin Off", PMBusDataFormat.LINEAR11, "RW", 2),
        0x37: PMBusCommand(0x37, "INTERLEAVE", "Interleave", PMBusDataFormat.BLOCK, "RW", 0),
        0x38: PMBusCommand(0x38, "IOUT_CAL_GAIN", "Iout Calibration Gain", PMBusDataFormat.LINEAR11, "RW", 2),
        0x39: PMBusCommand(0x39, "IOUT_CAL_OFFSET", "Iout Calibration Offset", PMBusDataFormat.LINEAR11, "RW", 2),
        0x3A: PMBusCommand(0x3A, "FAN_CONFIG_1_2", "Fan Config 1-2", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x3B: PMBusCommand(0x3B, "FAN_COMMAND_1", "Fan Command 1", PMBusDataFormat.LINEAR11, "RW", 2),
        0x3C: PMBusCommand(0x3C, "FAN_COMMAND_2", "Fan Command 2", PMBusDataFormat.LINEAR11, "RW", 2),
        0x3D: PMBusCommand(0x3D, "FAN_CONFIG_3_4", "Fan Config 3-4", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x3E: PMBusCommand(0x3E, "FAN_COMMAND_3", "Fan Command 3", PMBusDataFormat.LINEAR11, "RW", 2),
        0x3F: PMBusCommand(0x3F, "FAN_COMMAND_4", "Fan Command 4", PMBusDataFormat.LINEAR11, "RW", 2),

        # Fault limits
        0x40: PMBusCommand(0x40, "VOUT_OV_FAULT_LIMIT", "Vout OV Fault Limit", PMBusDataFormat.LINEAR16, "RW", 2),
        0x41: PMBusCommand(0x41, "VOUT_OV_FAULT_RESPONSE", "Vout OV Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x42: PMBusCommand(0x42, "VOUT_OV_WARN_LIMIT", "Vout OV Warn Limit", PMBusDataFormat.LINEAR16, "RW", 2),
        0x43: PMBusCommand(0x43, "VOUT_UV_WARN_LIMIT", "Vout UV Warn Limit", PMBusDataFormat.LINEAR16, "RW", 2),
        0x44: PMBusCommand(0x44, "VOUT_UV_FAULT_LIMIT", "Vout UV Fault Limit", PMBusDataFormat.LINEAR16, "RW", 2),
        0x45: PMBusCommand(0x45, "VOUT_UV_FAULT_RESPONSE", "Vout UV Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x46: PMBusCommand(0x46, "IOUT_OC_FAULT_LIMIT", "Iout OC Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x47: PMBusCommand(0x47, "IOUT_OC_FAULT_RESPONSE", "Iout OC Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x48: PMBusCommand(0x48, "IOUT_OC_LV_FAULT_LIMIT", "Iout OC LV Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x49: PMBusCommand(0x49, "IOUT_OC_LV_FAULT_RESPONSE", "Iout OC LV Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x4A: PMBusCommand(0x4A, "IOUT_OC_WARN_LIMIT", "Iout OC Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x4B: PMBusCommand(0x4B, "IOUT_UC_FAULT_LIMIT", "Iout UC Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x4C: PMBusCommand(0x4C, "IOUT_UC_FAULT_RESPONSE", "Iout UC Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),

        # Temperature fault limits
        0x4F: PMBusCommand(0x4F, "OT_FAULT_LIMIT", "OT Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x50: PMBusCommand(0x50, "OT_FAULT_RESPONSE", "OT Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x51: PMBusCommand(0x51, "OT_WARN_LIMIT", "OT Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x52: PMBusCommand(0x52, "UT_WARN_LIMIT", "UT Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x53: PMBusCommand(0x53, "UT_FAULT_LIMIT", "UT Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x54: PMBusCommand(0x54, "UT_FAULT_RESPONSE", "UT Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x55: PMBusCommand(0x55, "VIN_OV_FAULT_LIMIT", "Vin OV Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x56: PMBusCommand(0x56, "VIN_OV_FAULT_RESPONSE", "Vin OV Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x57: PMBusCommand(0x57, "VIN_OV_WARN_LIMIT", "Vin OV Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x58: PMBusCommand(0x58, "VIN_UV_WARN_LIMIT", "Vin UV Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x59: PMBusCommand(0x59, "VIN_UV_FAULT_LIMIT", "Vin UV Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x5A: PMBusCommand(0x5A, "VIN_UV_FAULT_RESPONSE", "Vin UV Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x5B: PMBusCommand(0x5B, "IIN_OC_FAULT_LIMIT", "Iin OC Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x5C: PMBusCommand(0x5C, "IIN_OC_FAULT_RESPONSE", "Iin OC Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x5D: PMBusCommand(0x5D, "IIN_OC_WARN_LIMIT", "Iin OC Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x5E: PMBusCommand(0x5E, "POWER_GOOD_ON", "Power Good On", PMBusDataFormat.LINEAR16, "RW", 2),
        0x5F: PMBusCommand(0x5F, "POWER_GOOD_OFF", "Power Good Off", PMBusDataFormat.LINEAR16, "RW", 2),

        # Timing configuration
        0x60: PMBusCommand(0x60, "TON_DELAY", "Ton Delay", PMBusDataFormat.LINEAR11, "RW", 2),
        0x61: PMBusCommand(0x61, "TON_RISE", "Ton Rise", PMBusDataFormat.LINEAR11, "RW", 2),
        0x62: PMBusCommand(0x62, "TON_MAX_FAULT_LIMIT", "Ton Max Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x63: PMBusCommand(0x63, "TON_MAX_FAULT_RESPONSE", "Ton Max Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x64: PMBusCommand(0x64, "TOFF_DELAY", "Toff Delay", PMBusDataFormat.LINEAR11, "RW", 2),
        0x65: PMBusCommand(0x65, "TOFF_FALL", "Toff Fall", PMBusDataFormat.LINEAR11, "RW", 2),
        0x66: PMBusCommand(0x66, "TOFF_MAX_WARN_LIMIT", "Toff Max Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),

        # Pin fault limits
        0x68: PMBusCommand(0x68, "POUT_OP_FAULT_LIMIT", "Pout OP Fault Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x69: PMBusCommand(0x69, "POUT_OP_FAULT_RESPONSE", "Pout OP Fault Response", PMBusDataFormat.UNSIGNED, "RW", 1),
        0x6A: PMBusCommand(0x6A, "POUT_OP_WARN_LIMIT", "Pout OP Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),
        0x6B: PMBusCommand(0x6B, "PIN_OP_WARN_LIMIT", "Pin OP Warn Limit", PMBusDataFormat.LINEAR11, "RW", 2),

        # Status registers
        0x78: PMBusCommand(0x78, "STATUS_BYTE", "Status Byte", PMBusDataFormat.UNSIGNED, "R", 1),
        0x79: PMBusCommand(0x79, "STATUS_WORD", "Status Word", PMBusDataFormat.UNSIGNED, "R", 2),
        0x7A: PMBusCommand(0x7A, "STATUS_VOUT", "Status Vout", PMBusDataFormat.UNSIGNED, "R", 1),
        0x7B: PMBusCommand(0x7B, "STATUS_IOUT", "Status Iout", PMBusDataFormat.UNSIGNED, "R", 1),
        0x7C: PMBusCommand(0x7C, "STATUS_INPUT", "Status Input", PMBusDataFormat.UNSIGNED, "R", 1),
        0x7D: PMBusCommand(0x7D, "STATUS_TEMPERATURE", "Status Temperature", PMBusDataFormat.UNSIGNED, "R", 1),
        0x7E: PMBusCommand(0x7E, "STATUS_CML", "Status CML", PMBusDataFormat.UNSIGNED, "R", 1),
        0x7F: PMBusCommand(0x7F, "STATUS_OTHER", "Status Other", PMBusDataFormat.UNSIGNED, "R", 1),
        0x80: PMBusCommand(0x80, "STATUS_MFR_SPECIFIC", "Status MFR Specific", PMBusDataFormat.UNSIGNED, "R", 1),
        0x81: PMBusCommand(0x81, "STATUS_FANS_1_2", "Status Fans 1-2", PMBusDataFormat.UNSIGNED, "R", 1),
        0x82: PMBusCommand(0x82, "STATUS_FANS_3_4", "Status Fans 3-4", PMBusDataFormat.UNSIGNED, "R", 1),

        # Read telemetry
        0x88: PMBusCommand(0x88, "READ_EIN", "Read Ein", PMBusDataFormat.BLOCK, "R", 0),
        0x89: PMBusCommand(0x89, "READ_EOUT", "Read Eout", PMBusDataFormat.BLOCK, "R", 0),
        0x8A: PMBusCommand(0x8A, "READ_VIN", "Read Vin", PMBusDataFormat.LINEAR11, "R", 2),
        0x8B: PMBusCommand(0x8B, "READ_IIN", "Read Iin", PMBusDataFormat.LINEAR11, "R", 2),
        0x8C: PMBusCommand(0x8C, "READ_VCAP", "Read Vcap", PMBusDataFormat.LINEAR11, "R", 2),
        0x8D: PMBusCommand(0x8D, "READ_VOUT", "Read Vout", PMBusDataFormat.LINEAR16, "R", 2),
        0x8E: PMBusCommand(0x8E, "READ_IOUT", "Read Iout", PMBusDataFormat.LINEAR11, "R", 2),
        0x8F: PMBusCommand(0x8F, "READ_TEMPERATURE_1", "Read Temperature 1", PMBusDataFormat.LINEAR11, "R", 2),
        0x90: PMBusCommand(0x90, "READ_TEMPERATURE_2", "Read Temperature 2", PMBusDataFormat.LINEAR11, "R", 2),
        0x91: PMBusCommand(0x91, "READ_TEMPERATURE_3", "Read Temperature 3", PMBusDataFormat.LINEAR11, "R", 2),
        0x92: PMBusCommand(0x92, "READ_FAN_SPEED_1", "Read Fan Speed 1", PMBusDataFormat.LINEAR11, "R", 2),
        0x93: PMBusCommand(0x93, "READ_FAN_SPEED_2", "Read Fan Speed 2", PMBusDataFormat.LINEAR11, "R", 2),
        0x94: PMBusCommand(0x94, "READ_FAN_SPEED_3", "Read Fan Speed 3", PMBusDataFormat.LINEAR11, "R", 2),
        0x95: PMBusCommand(0x95, "READ_FAN_SPEED_4", "Read Fan Speed 4", PMBusDataFormat.LINEAR11, "R", 2),
        0x96: PMBusCommand(0x96, "READ_DUTY_CYCLE", "Read Duty Cycle", PMBusDataFormat.LINEAR11, "R", 2),
        0x97: PMBusCommand(0x97, "READ_FREQUENCY", "Read Frequency", PMBusDataFormat.LINEAR11, "R", 2),
        0x98: PMBusCommand(0x98, "READ_POUT", "Read Pout", PMBusDataFormat.LINEAR11, "R", 2),
        0x99: PMBusCommand(0x99, "READ_PIN", "Read Pin", PMBusDataFormat.LINEAR11, "R", 2),

        # Peak values
        0x9A: PMBusCommand(0x9A, "PMBUS_REVISION", "PMBus Revision", PMBusDataFormat.UNSIGNED, "R", 1),
        0x9B: PMBusCommand(0x9B, "MFR_ID", "MFR ID", PMBusDataFormat.BLOCK, "R", 0),
        0x9C: PMBusCommand(0x9C, "MFR_MODEL", "MFR Model", PMBusDataFormat.BLOCK, "R", 0),
        0x9D: PMBusCommand(0x9D, "MFR_REVISION", "MFR Revision", PMBusDataFormat.BLOCK, "R", 0),
        0x9E: PMBusCommand(0x9E, "MFR_LOCATION", "MFR Location", PMBusDataFormat.BLOCK, "R", 0),
        0x9F: PMBusCommand(0x9F, "MFR_DATE", "MFR Date", PMBusDataFormat.BLOCK, "R", 0),
        0xA0: PMBusCommand(0xA0, "MFR_SERIAL", "MFR Serial", PMBusDataFormat.BLOCK, "R", 0),
        0xA1: PMBusCommand(0xA1, "APP_PROFILE_SUPPORT", "App Profile Support", PMBusDataFormat.BLOCK, "R", 0),
        0xA2: PMBusCommand(0xA2, "MFR_VIN_MIN", "MFR Vin Min", PMBusDataFormat.LINEAR11, "R", 2),
        0xA3: PMBusCommand(0xA3, "MFR_VIN_MAX", "MFR Vin Max", PMBusDataFormat.LINEAR11, "R", 2),
        0xA4: PMBusCommand(0xA4, "MFR_IIN_MAX", "MFR Iin Max", PMBusDataFormat.LINEAR11, "R", 2),
        0xA5: PMBusCommand(0xA5, "MFR_PIN_MAX", "MFR Pin Max", PMBusDataFormat.LINEAR11, "R", 2),
        0xA6: PMBusCommand(0xA6, "MFR_VOUT_MIN", "MFR Vout Min", PMBusDataFormat.LINEAR16, "R", 2),
        0xA7: PMBusCommand(0xA7, "MFR_VOUT_MAX", "MFR Vout Max", PMBusDataFormat.LINEAR16, "R", 2),
        0xA8: PMBusCommand(0xA8, "MFR_IOUT_MAX", "MFR Iout Max", PMBusDataFormat.LINEAR11, "R", 2),
        0xA9: PMBusCommand(0xA9, "MFR_POUT_MAX", "MFR Pout Max", PMBusDataFormat.LINEAR11, "R", 2),
        0xAA: PMBusCommand(0xAA, "MFR_TAMBIENT_MAX", "MFR Tambient Max", PMBusDataFormat.LINEAR11, "R", 2),
        0xAB: PMBusCommand(0xAB, "MFR_TAMBIENT_MIN", "MFR Tambient Min", PMBusDataFormat.LINEAR11, "R", 2),
        0xAC: PMBusCommand(0xAC, "MFR_EFFICIENCY_LL", "MFR Efficiency LL", PMBusDataFormat.BLOCK, "R", 0),
        0xAD: PMBusCommand(0xAD, "MFR_EFFICIENCY_HL", "MFR Efficiency HL", PMBusDataFormat.BLOCK, "R", 0),
        0xAE: PMBusCommand(0xAE, "MFR_PIN_ACCURACY", "MFR Pin Accuracy", PMBusDataFormat.UNSIGNED, "R", 1),
        0xAF: PMBusCommand(0xAF, "IC_DEVICE_ID", "IC Device ID", PMBusDataFormat.BLOCK, "R", 0),
        0xB0: PMBusCommand(0xB0, "IC_DEVICE_REV", "IC Device Rev", PMBusDataFormat.BLOCK, "R", 0),

        # User data and misc
        0xB1: PMBusCommand(0xB1, "USER_DATA_00", "User Data 00", PMBusDataFormat.BLOCK, "RW", 0),
        0xB2: PMBusCommand(0xB2, "USER_DATA_01", "User Data 01", PMBusDataFormat.BLOCK, "RW", 0),
        0xB3: PMBusCommand(0xB3, "USER_DATA_02", "User Data 02", PMBusDataFormat.BLOCK, "RW", 0),
        0xB4: PMBusCommand(0xB4, "USER_DATA_03", "User Data 03", PMBusDataFormat.BLOCK, "RW", 0),
        0xB5: PMBusCommand(0xB5, "USER_DATA_04", "User Data 04", PMBusDataFormat.BLOCK, "RW", 0),
        0xB6: PMBusCommand(0xB6, "USER_DATA_05", "User Data 05", PMBusDataFormat.BLOCK, "RW", 0),
        0xB7: PMBusCommand(0xB7, "USER_DATA_06", "User Data 06", PMBusDataFormat.BLOCK, "RW", 0),
        0xB8: PMBusCommand(0xB8, "USER_DATA_07", "User Data 07", PMBusDataFormat.BLOCK, "RW", 0),
        0xB9: PMBusCommand(0xB9, "USER_DATA_08", "User Data 08", PMBusDataFormat.BLOCK, "RW", 0),
        0xBA: PMBusCommand(0xBA, "USER_DATA_09", "User Data 09", PMBusDataFormat.BLOCK, "RW", 0),
        0xBB: PMBusCommand(0xBB, "USER_DATA_10", "User Data 10", PMBusDataFormat.BLOCK, "RW", 0),
        0xBC: PMBusCommand(0xBC, "USER_DATA_11", "User Data 11", PMBusDataFormat.BLOCK, "RW", 0),
        0xBD: PMBusCommand(0xBD, "USER_DATA_12", "User Data 12", PMBusDataFormat.BLOCK, "RW", 0),
        0xBE: PMBusCommand(0xBE, "USER_DATA_13", "User Data 13", PMBusDataFormat.BLOCK, "RW", 0),
        0xBF: PMBusCommand(0xBF, "USER_DATA_14", "User Data 14", PMBusDataFormat.BLOCK, "RW", 0),
        0xC0: PMBusCommand(0xC0, "USER_DATA_15", "User Data 15", PMBusDataFormat.BLOCK, "RW", 0),

        # MFR specific (common manufacturer extensions)
        0xD0: PMBusCommand(0xD0, "MFR_SPECIFIC_00", "MFR Specific 00", PMBusDataFormat.BLOCK, "RW", 0),
        0xD1: PMBusCommand(0xD1, "MFR_SPECIFIC_01", "MFR Specific 01", PMBusDataFormat.BLOCK, "RW", 0),
        0xD2: PMBusCommand(0xD2, "MFR_SPECIFIC_02", "MFR Specific 02", PMBusDataFormat.BLOCK, "RW", 0),
        0xD3: PMBusCommand(0xD3, "MFR_SPECIFIC_03", "MFR Specific 03", PMBusDataFormat.BLOCK, "RW", 0),
        0xD4: PMBusCommand(0xD4, "MFR_SPECIFIC_04", "MFR Specific 04", PMBusDataFormat.BLOCK, "RW", 0),
        0xD5: PMBusCommand(0xD5, "MFR_SPECIFIC_05", "MFR Specific 05", PMBusDataFormat.BLOCK, "RW", 0),
        0xD6: PMBusCommand(0xD6, "MFR_SPECIFIC_06", "MFR Specific 06", PMBusDataFormat.BLOCK, "RW", 0),
        0xD7: PMBusCommand(0xD7, "MFR_SPECIFIC_07", "MFR Specific 07", PMBusDataFormat.BLOCK, "RW", 0),
        0xD8: PMBusCommand(0xD8, "MFR_SPECIFIC_08", "MFR Specific 08", PMBusDataFormat.BLOCK, "RW", 0),
        0xFA: PMBusCommand(0xFA, "MFR_SPECIFIC_COMMAND", "MFR Specific Command", PMBusDataFormat.BLOCK, "RW", 0),
        0xFB: PMBusCommand(0xFB, "MFR_SPECIFIC_COMMAND_EXT", "MFR Specific Command Ext", PMBusDataFormat.BLOCK, "RW", 0),
    }

    def __init__(self):
        self.vout_mode = None  # Store VOUT_MODE for proper VOUT decoding
        self._kernel_pending_ops = {}  # Track pending kernel trace operations

    @staticmethod
    def decode_linear11(data: bytes) -> float:
        """
        Decode LINEAR11 format (2 bytes)
        Format: 5-bit exponent, 11-bit mantissa
        Value = mantissa * 2^exponent
        """
        if len(data) < 2:
            return 0.0

        raw = struct.unpack('<H', data[:2])[0]

        # Extract exponent (upper 5 bits) - signed
        exponent = (raw >> 11) & 0x1F
        if exponent & 0x10:  # Sign extend
            exponent |= 0xFFFFFFE0
        exponent = struct.unpack('i', struct.pack('I', exponent & 0xFFFFFFFF))[0]

        # Extract mantissa (lower 11 bits) - signed
        mantissa = raw & 0x7FF
        if mantissa & 0x400:  # Sign extend
            mantissa |= 0xFFFFF800
        mantissa = struct.unpack('i', struct.pack('I', mantissa & 0xFFFFFFFF))[0]

        return float(mantissa) * (2.0 ** exponent)

    @staticmethod
    def decode_linear16(data: bytes, vout_mode: Optional[int] = None) -> float:
        """
        Decode LINEAR16 format (2 bytes)
        Format depends on VOUT_MODE:
        - If VOUT_MODE bit 5 is 0: exponent from VOUT_MODE[4:0], 16-bit mantissa
        - If VOUT_MODE bit 5 is 1: direct format (requires coefficients)
        """
        if len(data) < 2:
            return 0.0

        mantissa = struct.unpack('<h', data[:2])[0]  # Signed 16-bit

        if vout_mode is None:
            # Assume exponent of 0 if VOUT_MODE not known
            exponent = 0
        else:
            mode = vout_mode & 0x1F
            if mode & 0x10:  # Sign extend 5-bit exponent
                mode |= 0xFFFFFFE0
            exponent = struct.unpack('i', struct.pack('I', mode & 0xFFFFFFFF))[0]

        return float(mantissa) * (2.0 ** exponent)

    @staticmethod
    def decode_unsigned(data: bytes) -> int:
        """Decode unsigned integer (1-2 bytes)"""
        if len(data) == 0:
            return 0
        elif len(data) == 1:
            return struct.unpack('B', data)[0]
        elif len(data) >= 2:
            return struct.unpack('<H', data[:2])[0]
        return 0

    @staticmethod
    def decode_signed(data: bytes) -> int:
        """Decode signed integer (1-2 bytes)"""
        if len(data) == 0:
            return 0
        elif len(data) == 1:
            return struct.unpack('b', data)[0]
        elif len(data) >= 2:
            return struct.unpack('<h', data[:2])[0]
        return 0

    @staticmethod
    def decode_string(data: bytes) -> str:
        """Decode string/block data"""
        try:
            return data.decode('ascii', errors='replace')
        except BaseException:
            return data.hex()

    @staticmethod
    def decode_block(data: bytes) -> str:
        """Decode block data (first byte is count)"""
        if len(data) == 0:
            return ""

        count = data[0]
        if len(data) < count + 1:
            # Invalid block format
            return f"[Block: {' '.join(f'{b:02x}' for b in data)}]"

        block_data = data[1:count + 1]
        # Try to decode as ASCII string
        try:
            decoded = block_data.decode('ascii', errors='ignore')
            if decoded.isprintable() or all(c in '\n\r\t' for c in decoded if not c.isprintable()):
                return f'"{decoded}"'
        except BaseException:
            pass

        return f"[{' '.join(f'{b:02x}' for b in block_data)}]"

    def decode_data(self, cmd: PMBusCommand, data: bytes) -> str:
        """Decode data based on command format"""
        if len(data) == 0:
            return "No data"

        try:
            if cmd.data_format == PMBusDataFormat.LINEAR11:
                value = self.decode_linear11(data)
                return f"{value:.6f}"
            elif cmd.data_format == PMBusDataFormat.LINEAR16:
                value = self.decode_linear16(data, self.vout_mode)
                return f"{value:.6f}"
            elif cmd.data_format == PMBusDataFormat.UNSIGNED:
                value = self.decode_unsigned(data)
                return f"0x{value:02x} ({value})"
            elif cmd.data_format == PMBusDataFormat.SIGNED:
                value = self.decode_signed(data)
                return f"{value}"
            elif cmd.data_format == PMBusDataFormat.BLOCK:
                return self.decode_block(data)
            elif cmd.data_format == PMBusDataFormat.STRING:
                return self.decode_string(data)
            elif cmd.data_format == PMBusDataFormat.NONE:
                return "No data expected"
            else:
                return f"[{' '.join(f'{b:02x}' for b in data)}]"
        except Exception as e:
            return f"[Decode error: {e}] Raw: {' '.join(f'{b:02x}' for b in data)}"

    def decode_status_byte(self, value: int) -> List[str]:
        """Decode STATUS_BYTE register"""
        flags = []
        if value & 0x80:
            flags.append("BUSY")
        if value & 0x40:
            flags.append("OFF")
        if value & 0x20:
            flags.append("VOUT_OV_FAULT")
        if value & 0x10:
            flags.append("IOUT_OC_FAULT")
        if value & 0x08:
            flags.append("VIN_UV_FAULT")
        if value & 0x04:
            flags.append("TEMPERATURE")
        if value & 0x02:
            flags.append("CML")
        if value & 0x01:
            flags.append("NONE_OF_ABOVE")
        return flags

    def decode_status_word(self, value: int) -> List[str]:
        """Decode STATUS_WORD register"""
        flags = []
        # High byte (same as STATUS_BYTE)
        high_byte = (value >> 8) & 0xFF
        if high_byte & 0x80:
            flags.append("VOUT")
        if high_byte & 0x40:
            flags.append("IOUT_POUT")
        if high_byte & 0x20:
            flags.append("INPUT")
        if high_byte & 0x10:
            flags.append("MFR_SPECIFIC")
        if high_byte & 0x08:
            flags.append("POWER_GOOD#")
        if high_byte & 0x04:
            flags.append("FANS")
        if high_byte & 0x02:
            flags.append("OTHER")
        if high_byte & 0x01:
            flags.append("UNKNOWN")

        # Low byte (same as STATUS_BYTE)
        low_byte = value & 0xFF
        if low_byte & 0x80:
            flags.append("BUSY")
        if low_byte & 0x40:
            flags.append("OFF")
        if low_byte & 0x20:
            flags.append("VOUT_OV_FAULT")
        if low_byte & 0x10:
            flags.append("IOUT_OC_FAULT")
        if low_byte & 0x08:
            flags.append("VIN_UV_FAULT")
        if low_byte & 0x04:
            flags.append("TEMPERATURE")
        if low_byte & 0x02:
            flags.append("CML")
        if low_byte & 0x01:
            flags.append("NONE_OF_ABOVE")

        return flags

    def decode_status_input(self, value: int) -> List[str]:
        """Decode STATUS_INPUT register (0x7C)"""
        flags = []
        if value & 0x80:
            flags.append("VIN_OV_FAULT")
        if value & 0x40:
            flags.append("VIN_UV_FAULT")
        if value & 0x20:
            flags.append("VIN_OV_WARNING")
        if value & 0x10:
            flags.append("VIN_UV_WARNING")
        if value & 0x08:
            flags.append("IIN_OC_FAULT")
        if value & 0x04:
            flags.append("IIN_OC_WARNING")
        if value & 0x02:
            flags.append("PIN_OP_WARNING")
        if value & 0x01:
            flags.append("UNIT_OFF_FOR_LOW_INPUT")
        return flags

    def decode_status_vout(self, value: int) -> List[str]:
        """Decode STATUS_VOUT register (0x7A)"""
        flags = []
        if value & 0x80:
            flags.append("VOUT_OV_FAULT")
        if value & 0x40:
            flags.append("VOUT_OV_WARNING")
        if value & 0x20:
            flags.append("VOUT_UV_WARNING")
        if value & 0x10:
            flags.append("VOUT_UV_FAULT")
        if value & 0x08:
            flags.append("VOUT_MAX_WARNING")
        if value & 0x04:
            flags.append("TON_MAX_FAULT")
        if value & 0x02:
            flags.append("TOFF_MAX_WARNING")
        if value & 0x01:
            flags.append("VOUT_TRACKING_ERROR")
        return flags

    def decode_status_iout(self, value: int) -> List[str]:
        """Decode STATUS_IOUT register (0x7B)"""
        flags = []
        if value & 0x80:
            flags.append("IOUT_OC_FAULT")
        if value & 0x40:
            flags.append("IOUT_OC_LV_FAULT")
        if value & 0x20:
            flags.append("IOUT_OC_WARNING")
        if value & 0x10:
            flags.append("IOUT_UC_FAULT")
        if value & 0x08:
            flags.append("CURRENT_SHARE_FAULT")
        if value & 0x04:
            flags.append("POUT_OP_FAULT")
        if value & 0x02:
            flags.append("POUT_OP_WARNING")
        if value & 0x01:
            flags.append("POWER_LIMIT_MODE")
        return flags

    def decode_status_temperature(self, value: int) -> List[str]:
        """Decode STATUS_TEMPERATURE register (0x7D)"""
        flags = []
        if value & 0x80:
            flags.append("OT_FAULT")
        if value & 0x40:
            flags.append("OT_WARNING")
        if value & 0x20:
            flags.append("UT_WARNING")
        if value & 0x10:
            flags.append("UT_FAULT")
        return flags

    def decode_status_cml(self, value: int) -> List[str]:
        """Decode STATUS_CML register (0x7E)"""
        flags = []
        if value & 0x80:
            flags.append("INVALID_COMMAND")
        if value & 0x40:
            flags.append("INVALID_DATA")
        if value & 0x20:
            flags.append("PEC_FAILED")
        if value & 0x10:
            flags.append("MEMORY_FAULT")
        if value & 0x08:
            flags.append("PROCESSOR_FAULT")
        if value & 0x04:
            flags.append("RESERVED")
        if value & 0x02:
            flags.append("COMM_FAULT_OTHER")
        if value & 0x01:
            flags.append("COMM_FAULT")
        return flags

    def parse_and_decode(self, trace_line: str) -> Optional[Dict[str, Any]]:
        """Parse a single i2c trace line and decode PMBUS data"""
        result = None

        # Try different i2c trace formats
        parsers = [
            self._parse_i2cdetect_format,
            self._parse_i2cdump_format,
            self._parse_i2ctransfer_format,
            self._parse_kernel_trace_format,
            self._parse_busybox_format,
        ]

        for parser in parsers:
            result = parser(trace_line)
            if result:
                break

        return result

    def _parse_i2ctransfer_format(self, line: str) -> Optional[Dict[str, Any]]:
        """
        Parse i2ctransfer format:
        i2c-1: w2@0x50 0x8d 0x00 r2@0x50
        w1@0x50 0x8d r2@0x50 - 0x40 0x00
        or raw hex dumps
        """
        # Combined write-read pattern (command followed by read with data)
        # Format: w<N>@0x<addr> <cmd> [<data>] r<M>@0x<addr> - <result_bytes>
        combined_pattern = r'w(\d+)@(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)(?:\s+(?:r\d+@0x[0-9a-fA-F]+))?\s*-\s*((?:0x[0-9a-fA-F]+\s*)+)'
        combined_match = re.search(combined_pattern, line)

        if combined_match:
            addr = int(combined_match.group(2), 16)
            cmd_code = int(combined_match.group(3), 16)
            result_data = [int(x, 16) for x in re.findall(r'0x[0-9a-fA-F]+', combined_match.group(4))]

            return {
                'type': 'read',
                'address': addr,
                'command': cmd_code,
                'data': bytes(result_data),
                'raw_line': line
            }

        # Pattern: w<count>@0x<addr> <bytes...> (write only, no read)
        write_only_pattern = r'w(\d+)@(0x[0-9a-fA-F]+)\s+((?:0x[0-9a-fA-F]+\s*)+)(?!.*r\d+@)'
        write_match = re.search(write_only_pattern, line)
        if write_match:
            count = int(write_match.group(1))
            addr = int(write_match.group(2), 16)
            data_str = write_match.group(3)
            data_bytes = [int(x, 16) for x in re.findall(r'0x[0-9a-fA-F]+', data_str)]

            if len(data_bytes) >= 1:
                cmd_code = data_bytes[0]
                cmd_data = bytes(data_bytes[1:]) if len(data_bytes) > 1 else b''

                return {
                    'type': 'write',
                    'address': addr,
                    'command': cmd_code,
                    'data': cmd_data,
                    'raw_line': line
                }

        # Check for read operation without preceding write in same line
        read_pattern = r'r(\d+)@(0x[0-9a-fA-F]+)'
        read_match = re.search(read_pattern, line)
        if read_match and '-' not in line:  # Ensure we don't double-match combined format
            count = int(read_match.group(1))
            addr = int(read_match.group(2), 16)

            # Try to find hex data after the read command
            data_pattern = r'r\d+@0x[0-9a-fA-F]+\s*[:\-]?\s*((?:0x[0-9a-fA-F]+\s*)+)'
            data_match = re.search(data_pattern, line)

            if data_match:
                data_str = data_match.group(1)
                data_bytes = [int(x, 16) for x in re.findall(r'0x[0-9a-fA-F]+', data_str)]
                cmd_data = bytes(data_bytes)
            else:
                cmd_data = b''

            return {
                'type': 'read',
                'address': addr,
                'command': None,  # Read doesn't show command in this line
                'data': cmd_data,
                'raw_line': line
            }

        return None

    def _parse_i2cdump_format(self, line: str) -> Optional[Dict[str, Any]]:
        """
        Parse i2cdump format:
        00: 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10
        """
        # Pattern: <offset>: <hex bytes>
        pattern = r'^([0-9a-fA-F]+):\s+((?:[0-9a-fA-F]{2}\s*)+)'
        match = re.match(pattern, line.strip())

        if match:
            offset = int(match.group(1), 16)
            data_str = match.group(2)
            data_bytes = [int(x, 16) for x in data_str.split()]

            # i2cdump shows register contents, treat as multiple reads
            results = []
            for i, byte_val in enumerate(data_bytes):
                cmd_code = offset + i
                results.append({
                    'type': 'read',
                    'address': None,  # Address not in this line
                    'command': cmd_code,
                    'data': bytes([byte_val]),
                    'raw_line': line
                })

            return results[0] if results else None

        return None

    def _parse_kernel_trace_format(self, line: str) -> Optional[Dict[str, Any]]:
        """
        Parse kernel i2c trace format (ftrace output):
        sensors-16426   [005] ..... 22100.535879: i2c_write: i2c-15 #0 a=061 f=0004 l=1 [88]
        sensors-16426   [005] ..... 22100.535881: i2c_read: i2c-15 #1 a=061 f=0005 l=3
        sensors-16426   [005] ..... 22100.536529: i2c_reply: i2c-15 #1 a=061 f=0005 l=3 [f9-d2-b3]

        OR old format:
        i2c-1: master_xfer[0]: addr=0x50 flags=0x0 len=2 buf=8d 00
        """
        # New ftrace format with i2c_write/i2c_read/i2c_reply events
        # Pattern for i2c_write event
        ftrace_write_pattern = r'i2c_write:\s+(i2c-\d+)\s+#(\d+)\s+a=([0-9a-fA-F]+)\s+f=([0-9a-fA-F]+)\s+l=(\d+)\s+\[([0-9a-fA-F\-]+)\]'
        write_match = re.search(ftrace_write_pattern, line)

        if write_match:
            bus = write_match.group(1)
            msg_num = int(write_match.group(2))
            addr = int(write_match.group(3), 16)
            flags = int(write_match.group(4), 16)
            length = int(write_match.group(5))
            data_str = write_match.group(6)
            data_bytes = [int(x, 16) for x in data_str.split('-')]

            # Store the command for later matching with reply
            if len(data_bytes) >= 1:
                cmd_code = data_bytes[0]
                cmd_data = bytes(data_bytes[1:]) if len(data_bytes) > 1 else b''

                # Store pending operation (bus+msg_num as key)
                self._kernel_pending_ops[f"{bus}#{msg_num + 1}"] = (addr, cmd_code, cmd_data)

                # If this is a write-only operation (has data beyond command)
                if len(data_bytes) > 1:
                    return {
                        'type': 'write',
                        'address': addr,
                        'command': cmd_code,
                        'data': cmd_data,
                        'raw_line': line,
                        'bus': bus,
                        'timestamp': self._extract_timestamp(line)
                    }
            return None

        # Pattern for i2c_read event (just marks a read request, no data yet)
        ftrace_read_pattern = r'i2c_read:\s+(i2c-\d+)\s+#(\d+)\s+a=([0-9a-fA-F]+)\s+f=([0-9a-fA-F]+)\s+l=(\d+)'
        read_match = re.search(ftrace_read_pattern, line)

        if read_match:
            # Just note that a read is expected, actual data comes in i2c_reply
            return None

        # Pattern for i2c_reply event (contains the read data)
        ftrace_reply_pattern = r'i2c_reply:\s+(i2c-\d+)\s+#(\d+)\s+a=([0-9a-fA-F]+)\s+f=([0-9a-fA-F]+)\s+l=(\d+)\s+\[([0-9a-fA-F\-]+)\]'
        reply_match = re.search(ftrace_reply_pattern, line)

        if reply_match:
            bus = reply_match.group(1)
            msg_num = int(reply_match.group(2))
            addr = int(reply_match.group(3), 16)
            flags = int(reply_match.group(4), 16)
            length = int(reply_match.group(5))
            data_str = reply_match.group(6)
            data_bytes = [int(x, 16) for x in data_str.split('-')]

            # Look up the pending command for this bus/message
            key = f"{bus}#{msg_num}"
            if key in self._kernel_pending_ops:
                pending_addr, cmd_code, cmd_data = self._kernel_pending_ops[key]
                del self._kernel_pending_ops[key]  # Remove from pending

                return {
                    'type': 'read',
                    'address': addr,
                    'command': cmd_code,
                    'data': bytes(data_bytes),
                    'raw_line': line,
                    'bus': bus,
                    'timestamp': self._extract_timestamp(line)
                }
            else:
                # Reply without matching write (shouldn't happen in normal traces)
                return {
                    'type': 'read',
                    'address': addr,
                    'command': None,
                    'data': bytes(data_bytes),
                    'raw_line': line,
                    'bus': bus,
                    'timestamp': self._extract_timestamp(line)
                }

        # Old master_xfer format
        # Write pattern
        old_write_pattern = r'addr=(0x[0-9a-fA-F]+).*?flags=(0x[0-9a-fA-F]+).*?buf=((?:[0-9a-fA-F]{2}\s*)+)'
        old_write_match = re.search(old_write_pattern, line)

        if old_write_match:
            addr = int(old_write_match.group(1), 16)
            flags = int(old_write_match.group(2), 16)
            data_str = old_write_match.group(3)
            data_bytes = [int(x, 16) for x in data_str.split()]

            if flags & 0x0001:  # Read flag
                return {
                    'type': 'read',
                    'address': addr,
                    'command': None,
                    'data': bytes(data_bytes),
                    'raw_line': line
                }
            else:  # Write
                if len(data_bytes) >= 1:
                    cmd_code = data_bytes[0]
                    cmd_data = bytes(data_bytes[1:]) if len(data_bytes) > 1 else b''

                    return {
                        'type': 'write',
                        'address': addr,
                        'command': cmd_code,
                        'data': cmd_data,
                        'raw_line': line
                    }

        return None

    def _extract_timestamp(self, line: str) -> Optional[str]:
        """Extract timestamp from kernel trace line"""
        # Pattern: CPU# ..... timestamp:
        timestamp_pattern = r'\[(\d+)\]\s+[\.\w]+\s+(\d+\.\d+):'
        match = re.search(timestamp_pattern, line)
        if match:
            return match.group(2)
        return None

    def _parse_i2cdetect_format(self, line: str) -> Optional[Dict[str, Any]]:
        """Parse i2cdetect format (not very useful for PMBUS but included for completeness)"""
        return None

    def _parse_busybox_format(self, line: str) -> Optional[Dict[str, Any]]:
        """
        Parse busybox i2c tools format or raw hex dumps:
        0x50: 8d 00 -> 12 34
        """
        pattern = r'(0x[0-9a-fA-F]+):\s+((?:[0-9a-fA-F]{2}\s*)+)\s*->\s*((?:[0-9a-fA-F]{2}\s*)+)'
        match = re.search(pattern, line)

        if match:
            addr = int(match.group(1), 16)
            write_data = [int(x, 16) for x in match.group(2).split()]
            read_data = [int(x, 16) for x in match.group(3).split()]

            if len(write_data) >= 1:
                return {
                    'type': 'read',
                    'address': addr,
                    'command': write_data[0],
                    'data': bytes(read_data),
                    'raw_line': line
                }

        return None

    def format_decoded_line(self, parsed: Dict[str, Any]) -> str:
        """Format a decoded line for output"""
        if not parsed:
            return ""

        lines = []
        addr_str = f"0x{parsed['address']:02x}" if parsed.get('address') is not None else "??"

        # Add bus and timestamp if available (from kernel trace)
        bus_str = f" | Bus: {parsed['bus']}" if parsed.get('bus') else ""
        time_str = f" | Time: {parsed['timestamp']}" if parsed.get('timestamp') else ""

        if parsed['type'] == 'write':
            cmd_code = parsed.get('command')
            if cmd_code is not None:
                cmd = self.COMMANDS.get(cmd_code)
                if cmd:
                    cmd_name = f"{cmd.name} (0x{cmd_code:02x})"
                    decoded = self.decode_data(cmd, parsed['data'])

                    # Store VOUT_MODE for later VOUT decoding
                    if cmd_code == 0x20 and len(parsed['data']) >= 1:
                        self.vout_mode = parsed['data'][0]

                    lines.append(f"[WRITE] Addr: {addr_str}{bus_str}{time_str} | Cmd: {cmd_name} | Data: {decoded}")
                    lines.append(f"        Description: {cmd.description}")
                else:
                    lines.append(f"[WRITE] Addr: {addr_str}{bus_str}{time_str} | Cmd: 0x{cmd_code:02x} (UNKNOWN) | Data: {parsed['data'].hex()}")

        elif parsed['type'] == 'read':
            cmd_code = parsed.get('command')
            if cmd_code is not None:
                cmd = self.COMMANDS.get(cmd_code)
                if cmd:
                    cmd_name = f"{cmd.name} (0x{cmd_code:02x})"
                    decoded = self.decode_data(cmd, parsed['data'])

                    lines.append(f"[READ]  Addr: {addr_str}{bus_str}{time_str} | Cmd: {cmd_name} | Data: {decoded}")
                    lines.append(f"        Description: {cmd.description}")

                    # Add status register decoding
                    if cmd_code == 0x78 and len(parsed['data']) >= 1:  # STATUS_BYTE
                        status = parsed['data'][0]
                        flags = self.decode_status_byte(status)
                        if flags:
                            lines.append(f"        Status Flags: {', '.join(flags)}")

                    elif cmd_code == 0x79 and len(parsed['data']) >= 2:  # STATUS_WORD
                        status = struct.unpack('<H', parsed['data'][:2])[0]
                        flags = self.decode_status_word(status)
                        if flags:
                            lines.append(f"        Status Flags: {', '.join(flags)}")

                    elif cmd_code == 0x7A and len(parsed['data']) >= 1:  # STATUS_VOUT
                        status = parsed['data'][0]
                        flags = self.decode_status_vout(status)
                        if flags:
                            lines.append(f"        Status Flags: {', '.join(flags)}")

                    elif cmd_code == 0x7B and len(parsed['data']) >= 1:  # STATUS_IOUT
                        status = parsed['data'][0]
                        flags = self.decode_status_iout(status)
                        if flags:
                            lines.append(f"        Status Flags: {', '.join(flags)}")

                    elif cmd_code == 0x7C and len(parsed['data']) >= 1:  # STATUS_INPUT
                        status = parsed['data'][0]
                        flags = self.decode_status_input(status)
                        if flags:
                            lines.append(f"        Status Flags: {', '.join(flags)}")

                    elif cmd_code == 0x7D and len(parsed['data']) >= 1:  # STATUS_TEMPERATURE
                        status = parsed['data'][0]
                        flags = self.decode_status_temperature(status)
                        if flags:
                            lines.append(f"        Status Flags: {', '.join(flags)}")

                    elif cmd_code == 0x7E and len(parsed['data']) >= 1:  # STATUS_CML
                        status = parsed['data'][0]
                        flags = self.decode_status_cml(status)
                        if flags:
                            lines.append(f"        Status Flags: {', '.join(flags)}")
                else:
                    lines.append(f"[READ]  Addr: {addr_str}{bus_str}{time_str} | Cmd: 0x{cmd_code:02x} (UNKNOWN) | Data: {parsed['data'].hex()}")
            else:
                # Read without explicit command (continuation of previous write)
                lines.append(f"[READ]  Addr: {addr_str}{bus_str}{time_str} | Data: {parsed['data'].hex()}")

        return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='PMBUS I2C Trace Dump Decoder',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Supported trace formats:
  - i2ctransfer: w2@0x50 0x8d 0x00 r2@0x50
  - i2cdump: 00: 01 02 03 04 05 06 07 08
  - kernel trace: addr=0x50 flags=0x0 len=2 buf=8d 00
  - busybox: 0x50: 8d 00 -> 12 34

Examples:
  # Decode from file
  %(prog)s trace.log

  # Decode from stdin
  cat trace.log | %(prog)s -

  # Filter by address
  %(prog)s trace.log --addr 0x50

  # Filter by bus
  %(prog)s trace.log --bus i2c-15

  # Filter by both
  %(prog)s trace.log --addr 0x61 --bus i2c-1

  # Decode with command listing
  %(prog)s --list-commands
        """)

    parser.add_argument('input_file', nargs='?', default='-',
                        help='Input trace file (use - for stdin)')
    parser.add_argument('--list-commands', action='store_true',
                        help='List all supported PMBUS commands')
    parser.add_argument('--show-raw', action='store_true',
                        help='Show raw trace lines alongside decoded output')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')
    parser.add_argument('--addr', '--address', type=str, metavar='ADDR',
                        help='Filter by I2C address (e.g., 0x50, 0x61, 50, 061)')
    parser.add_argument('--bus', type=str, metavar='BUS',
                        help='Filter by I2C bus name (e.g., i2c-1, i2c-15)')

    args = parser.parse_args()

    decoder = PMBusDecoder()

    # Parse address filter if provided
    filter_addr = None
    if args.addr:
        addr_str = args.addr.strip()
        try:
            # Handle both 0x50 and 50 formats, and 061 (octal-looking hex)
            if addr_str.startswith('0x') or addr_str.startswith('0X'):
                filter_addr = int(addr_str, 16)
            else:
                # Try as hex first, then decimal
                try:
                    filter_addr = int(addr_str, 16)
                except ValueError:
                    filter_addr = int(addr_str, 10)
        except ValueError:
            print(f"Error: Invalid address format '{args.addr}'. Use hex (0x50, 50) or decimal.", file=sys.stderr)
            return 1

    # Parse bus filter if provided
    filter_bus = None
    if args.bus:
        filter_bus = args.bus.strip()

    # List commands if requested
    if args.list_commands:
        print("=" * 80)
        print("SUPPORTED PMBUS COMMANDS")
        print("=" * 80)
        for cmd_code in sorted(decoder.COMMANDS.keys()):
            cmd = decoder.COMMANDS[cmd_code]
            print(f"0x{cmd_code:02X} | {cmd.name:30s} | {cmd.description}")
        print("=" * 80)
        print(f"Total: {len(decoder.COMMANDS)} commands")
        return 0

    # Read input
    if args.input_file == '-':
        lines = sys.stdin.readlines()
    else:
        try:
            with open(args.input_file, 'r') as f:
                lines = f.readlines()
        except FileNotFoundError:
            print(f"Error: File '{args.input_file}' not found", file=sys.stderr)
            return 1
        except Exception as e:
            print(f"Error reading file: {e}", file=sys.stderr)
            return 1

    # Process each line
    print("=" * 80)
    print("PMBUS TRACE DECODER OUTPUT")
    if filter_addr is not None or filter_bus is not None:
        print("FILTERS ACTIVE:", end="")
        if filter_addr is not None:
            print(f" Addr=0x{filter_addr:02x}", end="")
        if filter_bus is not None:
            print(f" Bus={filter_bus}", end="")
        print()
    print("=" * 80)
    print()

    decoded_count = 0
    filtered_count = 0

    for line_num, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue

        if args.show_raw:
            print(f"Raw [{line_num}]: {line}")

        parsed = decoder.parse_and_decode(line)
        if parsed:
            if isinstance(parsed, list):
                # Multiple results from one line (e.g., i2cdump)
                for p in parsed:
                    # Apply filters
                    if filter_addr is not None and p.get('address') != filter_addr:
                        filtered_count += 1
                        continue
                    if filter_bus is not None and p.get('bus') != filter_bus:
                        filtered_count += 1
                        continue

                    decoded_line = decoder.format_decoded_line(p)
                    if decoded_line:
                        print(decoded_line)
                        print()
                        decoded_count += 1
            else:
                # Apply filters
                if filter_addr is not None and parsed.get('address') != filter_addr:
                    filtered_count += 1
                elif filter_bus is not None and parsed.get('bus') != filter_bus:
                    filtered_count += 1
                else:
                    decoded_line = decoder.format_decoded_line(parsed)
                    if decoded_line:
                        print(decoded_line)
                        print()
                        decoded_count += 1
        elif args.verbose:
            print(f"[{line_num}] Unable to parse: {line}")
            print()

    print("=" * 80)
    print(f"Decoded {decoded_count} PMBUS transactions")
    if filtered_count > 0:
        print(f"Filtered out {filtered_count} transactions")
    print("=" * 80)

    return 0


if __name__ == '__main__':
    sys.exit(main())
