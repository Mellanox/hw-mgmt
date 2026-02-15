#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2021-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
Created on Dec 17 15, 2021

Author: Oleksandr Shamray <olekandrs@nvidia.com>
Version: 0.1

Description:
Getting temperature sensor value from NVLink ASIC
'''

#######################################################################
# Global imports
#######################################################################
import os
import sys
import argparse
import array
import fcntl
import struct

"""
Reading NVLink themperature sensors using ioctl API
#define  NVSWITCH_NUM_MAX_CHANNELS  16

typedef struct
{
    NvU32  channelMask;
    NvTemp temperature[NVSWITCH_NUM_MAX_CHANNELS];
    NvS32  status[NVSWITCH_NUM_MAX_CHANNELS];
} NVSWITCH_CTRL_GET_TEMPERATURE_PARAMS;
"""

#######################################################################
# Constants
#######################################################################
NVSWITCH_NUM_MAX_CHANNELS = 16
IOCTL_NVSWITCH_GET_TEMPERATURE = 3229901851


def print_log(log, verbose=0):
    if verbose <= args.verbose:
        print(log)


def chunks(l, n):
    n = max(1, n)
    return [l[i:i + n] for i in range(0, len(l), n)]


def convert_temperature(buf):
    temperature = float(struct.unpack('i', buf)[0])
    temperature /= 256
    return temperature


def compose_request(sensor):
    buf = array.array('b', [0] * (4 + 4 * NVSWITCH_NUM_MAX_CHANNELS + 4 * NVSWITCH_NUM_MAX_CHANNELS))
    buf[0] = 1 << sensor
    return buf


def parse_responce(buf):
    mask = struct.unpack('i', buf[0:4])[0]

    offset = 4
    temp_list_raw = chunks(buf[offset:offset + 4 * NVSWITCH_NUM_MAX_CHANNELS], 4)
    temp_list = [convert_temperature(temp_raw) for temp_raw in temp_list_raw]

    offset += 4 * NVSWITCH_NUM_MAX_CHANNELS
    status_list_raw = chunks(buf[offset:offset + 4 * NVSWITCH_NUM_MAX_CHANNELS], 4)
    status_list = [status_list_raw[i][0] for i in range(0, NVSWITCH_NUM_MAX_CHANNELS)]
    TEMPERATURE_PARAMS = {"mask": mask, "status": status_list, "temp": temp_list}

    return TEMPERATURE_PARAMS


parser = argparse.ArgumentParser(description='NVLink read ASIC temperature sensor')
parser.add_argument('-n', '--nv_id', dest='nv_id', default=0, type=int, help='NVLink ASIC chip idx')
parser.add_argument('-s', '--sensor', dest='sensor', default=0, type=int, help='Sensor idx')
parser.add_argument('-v', '--verbose', dest='verbose', default=0, type=int, help='Verbosity output level')
args = parser.parse_args()


print_log("[+] Read NVLink chip {} temperature sensor {}".format(args.nv_id, args.sensor), 1)
nvlink_dev_filename = "/dev/nvidia-nvswitch{}".format(args.nv_id)
if not os.path.exists(nvlink_dev_filename):
    print_log("[+] Missing NV device file {}".format(nvlink_dev_filename))
    sys.exit(1)

print_log("[+] Openning device file {}".format(nvlink_dev_filename), 1)

try:
    nvlink_fd = open(nvlink_dev_filename, "wb")
except Exception as e:
    print_log("[+] Openning {} failed: {}t".format(nvlink_dev_filename, e))
    sys.exit(1)

print_log("[+] Getting raw temperatures values", 1)

buf = compose_request(args.sensor)
try:
    fcntl.ioctl(nvlink_fd.fileno(), IOCTL_NVSWITCH_GET_TEMPERATURE, buf, 1)
except Exception as e:
    print_log("Temperature reading error {}".format(e))
    nvlink_fd.close()
    sys.exit(1)
print_log(buf, 2)

print_log("[+] Convert recieved temperature RAW values", 1)
temperature_results = parse_responce(buf)
if temperature_results["status"][args.sensor] != 0:
    print_log("[+] Error getting ASIC:{} sensor:{} temperature status:{}".format(
        args.nv_id, args.sensor, temperature_results["status"][args.sensor]), 1)
    nvlink_fd.close()

print(temperature_results["temp"][args.sensor])

nvlink_fd.close()
sys.exit(0)
