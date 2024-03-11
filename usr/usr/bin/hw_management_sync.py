#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
# pylint: disable=W0718
# pylint: disable=R0913:

########################################################################
# Copyright (c) 2023 NVIDIA CORPORATION & AFFILIATES.
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
import time
import pdb

atttrib_list = {
    "NVLink_Switch_Scaleout": [
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/fan1",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN1 {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/fan2",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN2 {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/fan3",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN3 {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/fan4",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN4 {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/fan5",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN5 {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/fan6",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN6 {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/leakage1",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}",
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/leakage1",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}",
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/leakage_rope1",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE_ROPE1 {arg1}",
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/leakage_rope2",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE_ROPE2 {arg1}",
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/thermal1_pdb",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event THERMAL1_PDB {arg1}",
         "poll": 3, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/thermal2_pdb",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event THERMAL2_PDB {arg1}",
         "poll": 3, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/pwm_pg",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event PWM_PG {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/power_button",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event POWER_BUTTON {arg1}",
         "poll": 1, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/erot1_error",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event EROT1_ERROR {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/erot2_error",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event EROT2_ERROR {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/erot1_ap",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event EROT1_AP {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/erot2_ap",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event EROT2_AP {arg1}",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/intrusion",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event INTRUSION {arg1}",
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{}/gwp",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event GWP  {arg1}",
         "poll": 2, "ts": 0}
    ],
    "test": [
        {"fin": "/tmp/hwmon/{}/fan1",
         "cmd": "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN1 {arg1}",
         "poll": 5, "ts": 0}
    ]
}

# ----------------------------------------------------------------------
def update_attr(attr_prop):
    """
    @summary: Update hw-mgmt attributes and invoke cmd per attr change
    """
    ts = time.time()
    if ts >= attr_prop["ts"]:
        # update timestamp
        attr_prop["ts"] = ts + attr_prop["poll"]
        # update file
        try:
            fin = attr_prop["fin"].format(attr_prop["hwmon"])
            with open(fin, 'r', encoding="utf-8") as f:
                val = f.read().rstrip('\n')
            if "oldval" not in attr_prop.keys() or attr_prop["oldval"] != val:
                cmd = attr_prop["cmd"] + " 2> /dev/null 1> /dev/null"
                os.system(cmd.format(arg1=val))
                attr_prop["oldval"] = val
        except Exception as e:
            pass

def init_attr(attr_prop):
    if "hwmon" in attr_prop["fin"]:
        path = attr_prop["fin"].split("hwmon")[0]
        try:
            flist = os.listdir(os.path.join(path, "hwmon"))
            hwmon_name = [fn for fn in flist if "hwmon" in fn]
            attr_prop["hwmon"] = hwmon_name[0]
        except Exception as e:
            attr_prop["hwmon"] = ""

def main():
    """
    @summary: Update attributes
    arg1: system type
    """

    args = len(sys.argv) - 1

    if args < 1:
        try:
            f = open("/sys/devices/virtual/dmi/id/product_name", "r")
            system_type = f.read()
        except Exception as e:
            system_type = ""
    else:
        system_type = sys.argv[1]

    if system_type not in atttrib_list.keys():
        print("Not supported system type: {}".format(system_type))
        sys.exit(1)

    sys_attr = atttrib_list[system_type]
    for attr in sys_attr:
        init_attr(attr)

    while True:
        for attr in sys_attr:
            update_attr(attr)
        time.sleep(1)

if __name__ == '__main__':
    main()
