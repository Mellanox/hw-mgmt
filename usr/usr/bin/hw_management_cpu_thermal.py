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
Created on Sept 15, 2021

Author: Mykola Kostenok <c_mykolak@nvidia.com>
Version: 0.1

Description:
Control cooling devices according to CPU temperature trends

'''

import argparse

HWMGMT_THERMAL_PATH = "/var/run/hw-management/thermal"
CPU_COOLING_STATE = "cooling2_cur_state"

MAX_COOLING_STATE = 10
MIN_COOLING_STATE = 2
TEMP_HIGH = 95
TEMP_LOW = 80

def set_cooling_state(cstate):
    """
    @summary: Set cooling state.
    @param cstate: cooling state to set.
    @return: Last set cooling state.
    """
    try:
        with open("{}/{}".format(HWMGMT_THERMAL_PATH, CPU_COOLING_STATE), 'w+') as f:
            cstate = f.write(str(cstate))
    except:
        pass

    return cstate

def get_cooling_state():
    """
    @summary: Set cooling state.
    @return: Colling state.
    """
    cstate = MIN_COOLING_STATE

    try:
        with open("{}/{}".format(HWMGMT_THERMAL_PATH, CPU_COOLING_STATE), 'r') as f:
            cstate = f.read()
            cstate = int(cstate, 10)
    except:
        pass

    return cstate

def read_cpu_temp():
    """
    @summary: Read CPU temperature.
    @return: CPU tempterature.
    """
    cpu_temp = TEMP_HIGH

    try:
        with open("{}/cpu_pack".format(HWMGMT_THERMAL_PATH), 'r') as f:
            cpu_temp = f.read()
            if int(cpu_temp, 10) > 1000:
                cpu_temp = int(cpu_temp, 10)/1000
            else:
                cpu_temp = int(cpu_temp, 10)
    except:
        pass

    return cpu_temp

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    required = parser.add_argument_group('required arguments')
    required.add_argument('-t', "--last_temp", type=int, default=0, required=True)
    args = parser.parse_args()
    last_cooling_state = get_cooling_state()
    last_cpu_temp = args.last_temp

    cur_cpu_temp = read_cpu_temp()

    if cur_cpu_temp < TEMP_LOW:
        set_cooling_state(MIN_COOLING_STATE)
    elif cur_cpu_temp > TEMP_HIGH:
        set_cooling_state(MAX_COOLING_STATE)
    elif cur_cpu_temp >= TEMP_LOW:
        if cur_cpu_temp > last_cpu_temp:
            set_cooling_state(min(last_cooling_state+1, MAX_COOLING_STATE))
        elif cur_cpu_temp < last_cpu_temp:
            set_cooling_state(max(last_cooling_state-1, MIN_COOLING_STATE))

    exit(cur_cpu_temp)
