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

try:
    import os
    import sys
    import time
    import json
    import re
    import pdb

    from hw_management_redfish_client import RedfishClient, BMCAccessor
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

atttrib_list = {
    "HI162": [
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan1",
         "fn": "sync_fan", "arg": "1",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan2",
         "fn": "sync_fan", "arg": "2",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan3",
         "fn": "sync_fan", "arg": "3",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan4",
         "fn": "sync_fan", "arg": "4",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan5",
         "fn": "sync_fan", "arg": "5",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan6",
         "fn": "sync_fan", "arg": "6",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage1",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage2",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage3",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE3 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage4",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE4 {arg1}"],
         "poll": 2, "ts": 0},

        {"fin": "/var/run/hw-management/system/power_button_evt",
         "fn": "run_power_button_event",
         "arg": [],
         "poll": 1, "ts": 0},

        {"fin": "/sys/module/sx_core/asic0/temperature/input",
         "fn": "asic_temp_populate",
         "arg" : ["asic"],
         "poll": 3, "ts": 0},
        {"fin": "/sys/module/sx_core/asic0/temperature/input",
         "fn": "asic_temp_populate",
         "arg" : ["asic1"],
         "poll": 3, "ts": 0},
        {"fin": "/sys/module/sx_core/asic1/temperature/input",
         "fn": "asic_temp_populate",
         "arg" : ["asic2"],
         "poll": 3, "ts": 0},

        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {  "module1": {"fin": "/sys/module/sx_core/asic0/module0/"},
                    "module2": {"fin": "/sys/module/sx_core/asic0/module1/"},
                    "module3": {"fin": "/sys/module/sx_core/asic0/module2/"},
                    "module4": {"fin": "/sys/module/sx_core/asic0/module3/"},
                    "module5": {"fin": "/sys/module/sx_core/asic0/module4/"},
                    "module6": {"fin": "/sys/module/sx_core/asic0/module5/"},
                    "module7": {"fin": "/sys/module/sx_core/asic0/module6/"},
                    "module8": {"fin": "/sys/module/sx_core/asic0/module7/"},
                    "module9": {"fin": "/sys/module/sx_core/asic0/module8/"},
                    "module10": {"fin": "/sys/module/sx_core/asic0/module9/"},
                    "module11": {"fin": "/sys/module/sx_core/asic0/module10/"},
                    "module12": {"fin": "/sys/module/sx_core/asic0/module11/"},
                    "module13": {"fin": "/sys/module/sx_core/asic0/module12/"},
                    "module14": {"fin": "/sys/module/sx_core/asic0/module13/"},
                    "module15": {"fin": "/sys/module/sx_core/asic0/module14/"},
                    "module16": {"fin": "/sys/module/sx_core/asic0/module15/"},
                    "module17": {"fin": "/sys/module/sx_core/asic0/module16/"},
                    "module18": {"fin": "/sys/module/sx_core/asic0/module17/"},
                    "module19": {"fin": "/sys/module/sx_core/asic0/module18/"},
                    "module20": {"fin": "/sys/module/sx_core/asic0/module19/"},
                    "module21": {"fin": "/sys/module/sx_core/asic0/module20/"},
                    "module22": {"fin": "/sys/module/sx_core/asic0/module21/"},
                    "module23": {"fin": "/sys/module/sx_core/asic0/module22/"},
                    "module24": {"fin": "/sys/module/sx_core/asic0/module23/"},
                    "module25": {"fin": "/sys/module/sx_core/asic0/module24/"},
                    "module26": {"fin": "/sys/module/sx_core/asic0/module25/"},
                    "module27": {"fin": "/sys/module/sx_core/asic0/module26/"},
                    "module28": {"fin": "/sys/module/sx_core/asic0/module27/"},
                    "module29": {"fin": "/sys/module/sx_core/asic0/module28/"},
                    "module30": {"fin": "/sys/module/sx_core/asic0/module29/"},
                    "module31": {"fin": "/sys/module/sx_core/asic0/module30/"},
                    "module32": {"fin": "/sys/module/sx_core/asic0/module31/"},
                    "module33": {"fin": "/sys/module/sx_core/asic0/module32/"},
                    "module34": {"fin": "/sys/module/sx_core/asic0/module33/"},
                    "module35": {"fin": "/sys/module/sx_core/asic0/module34/"},
                    "module36": {"fin": "/sys/module/sx_core/asic0/module35/"}, },
        },
        {"fin": None,
         "fn": "redfish_get_sensor", "arg" : ["/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP", "bmc", 1000], "poll": 30, "ts": 0}
    ],
    "HI166|HI167|HI169|HI170": [
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan1",
         "fn": "sync_fan", "arg": "1",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan2",
         "fn": "sync_fan", "arg": "2",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan3",
         "fn": "sync_fan", "arg": "3",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan4",
         "fn": "sync_fan", "arg": "4",
         "poll": 5, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage1",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage2",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage3",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE3 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage4",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE4 {arg1}"],
         "poll": 2, "ts": 0},

        {"fin": "/var/run/hw-management/system/graseful_pwr_off",
         "fn": "run_power_button_event",
         "arg": [],
         "poll": 1, "ts": 0},

        {"fin": "/sys/module/sx_core/asic0/temperature/input",
         "fn": "asic_temp_populate",
         "arg" : ["asic"],
         "poll": 3, "ts": 0},
        {"fin": "/sys/module/sx_core/asic0/temperature/input",
         "fn": "asic_temp_populate",
         "arg" : ["asic1"],
         "poll": 3, "ts": 0},
        {"fin": "/sys/module/sx_core/asic1/temperature/input",
         "fn": "asic_temp_populate",
         "arg" : ["asic2"],
         "poll": 3, "ts": 0},

        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {  "module1": {"fin": "/sys/module/sx_core/asic0/module0/"},
                    "module2": {"fin": "/sys/module/sx_core/asic0/module1/"},
                    "module3": {"fin": "/sys/module/sx_core/asic0/module2/"},
                    "module4": {"fin": "/sys/module/sx_core/asic0/module3/"},
                    "module5": {"fin": "/sys/module/sx_core/asic0/module4/"},
                    "module6": {"fin": "/sys/module/sx_core/asic0/module5/"},
                    "module7": {"fin": "/sys/module/sx_core/asic0/module6/"},
                    "module8": {"fin": "/sys/module/sx_core/asic0/module7/"},
                    "module9": {"fin": "/sys/module/sx_core/asic0/module8/"},
                    "module10": {"fin": "/sys/module/sx_core/asic0/module9/"},
                    "module11": {"fin": "/sys/module/sx_core/asic0/module10/"},
                    "module12": {"fin": "/sys/module/sx_core/asic0/module11/"},
                    "module13": {"fin": "/sys/module/sx_core/asic0/module12/"},
                    "module14": {"fin": "/sys/module/sx_core/asic0/module13/"},
                    "module15": {"fin": "/sys/module/sx_core/asic0/module14/"},
                    "module16": {"fin": "/sys/module/sx_core/asic0/module15/"},
                    "module17": {"fin": "/sys/module/sx_core/asic0/module16/"},
                    "module18": {"fin": "/sys/module/sx_core/asic0/module17/"},
                    "module19": {"fin": "/sys/module/sx_core/asic0/module18/"},
                    "module20": {"fin": "/sys/module/sx_core/asic0/module19/"},
                    "module21": {"fin": "/sys/module/sx_core/asic0/module20/"},
                    "module22": {"fin": "/sys/module/sx_core/asic0/module21/"},
                    "module23": {"fin": "/sys/module/sx_core/asic0/module22/"},
                    "module24": {"fin": "/sys/module/sx_core/asic0/module23/"},
                    "module25": {"fin": "/sys/module/sx_core/asic0/module24/"},
                    "module26": {"fin": "/sys/module/sx_core/asic0/module25/"},
                    "module27": {"fin": "/sys/module/sx_core/asic0/module26/"},
                    "module28": {"fin": "/sys/module/sx_core/asic0/module27/"},
                    "module29": {"fin": "/sys/module/sx_core/asic0/module28/"},
                    "module30": {"fin": "/sys/module/sx_core/asic0/module29/"},
                    "module31": {"fin": "/sys/module/sx_core/asic0/module30/"},
                    "module32": {"fin": "/sys/module/sx_core/asic0/module31/"},
                    "module33": {"fin": "/sys/module/sx_core/asic0/module32/"},
                    "module34": {"fin": "/sys/module/sx_core/asic0/module33/"},
                    "module35": {"fin": "/sys/module/sx_core/asic0/module34/"},
                    "module36": {"fin": "/sys/module/sx_core/asic0/module35/"}, },
        },
        {"fin": None,
         "fn": "redfish_get_sensor", "arg" : ["/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP", "bmc", 1000], "poll": 30, "ts": 0},
        {"fin": None,
         "fn": "asic_state_poll", "arg" : ["/sys/module/sx_core/asic0/", 0], "poll": 10, "ts": 0},
        {"fin": None,
         "fn": "asic_state_poll", "arg" : ["/sys/module/sx_core/asic1/", 0], "poll": 10, "ts": 0}
    ],
    "HI171|HI172": [
        {"fin": "/sys/module/sx_core/asic0/temperature/input",
         "fn": "asic_temp_populate",   "arg" : ["asic1"],   "poll": 3, "ts": 0},
	    {"fin": "/sys/module/sx_core/asic0/temperature/input",
         "fn": "asic_temp_populate",   "arg" : ["asic"],  "poll": 3, "ts": 0},
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {  "module1": {"fin": "/sys/module/sx_core/asic0/module0/"},
                    "module2": {"fin": "/sys/module/sx_core/asic0/module1/"},
                    "module3": {"fin": "/sys/module/sx_core/asic0/module2/"},
                    "module4": {"fin": "/sys/module/sx_core/asic0/module3/"},
                    "module5": {"fin": "/sys/module/sx_core/asic0/module4/"},
                    "module6": {"fin": "/sys/module/sx_core/asic0/module5/"},
                    "module7": {"fin": "/sys/module/sx_core/asic0/module6/"},
                    "module8": {"fin": "/sys/module/sx_core/asic0/module7/"},
                    "module9": {"fin": "/sys/module/sx_core/asic0/module8/"},
                    "module10": {"fin": "/sys/module/sx_core/asic0/module9/"},
                    "module11": {"fin": "/sys/module/sx_core/asic0/module10/"},
                    "module12": {"fin": "/sys/module/sx_core/asic0/module11/"},
                    "module13": {"fin": "/sys/module/sx_core/asic0/module12/"},
                    "module14": {"fin": "/sys/module/sx_core/asic0/module13/"},
                    "module15": {"fin": "/sys/module/sx_core/asic0/module14/"},
                    "module16": {"fin": "/sys/module/sx_core/asic0/module15/"},
                    "module17": {"fin": "/sys/module/sx_core/asic0/module16/"},
                    "module18": {"fin": "/sys/module/sx_core/asic0/module17/"},
                    "module19": {"fin": "/sys/module/sx_core/asic0/module18/"},
                    "module20": {"fin": "/sys/module/sx_core/asic0/module19/"},
                    "module21": {"fin": "/sys/module/sx_core/asic0/module20/"},
                    "module22": {"fin": "/sys/module/sx_core/asic0/module21/"},
                    "module23": {"fin": "/sys/module/sx_core/asic0/module22/"},
                    "module24": {"fin": "/sys/module/sx_core/asic0/module23/"},
                    "module25": {"fin": "/sys/module/sx_core/asic0/module24/"},
                    "module26": {"fin": "/sys/module/sx_core/asic0/module25/"},
                    "module27": {"fin": "/sys/module/sx_core/asic0/module26/"},
                    "module28": {"fin": "/sys/module/sx_core/asic0/module27/"},
                    "module29": {"fin": "/sys/module/sx_core/asic0/module28/"},
                    "module30": {"fin": "/sys/module/sx_core/asic0/module29/"},
                    "module31": {"fin": "/sys/module/sx_core/asic0/module30/"},
                    "module32": {"fin": "/sys/module/sx_core/asic0/module31/"},
                    "module33": {"fin": "/sys/module/sx_core/asic0/module32/"},
                    "module34": {"fin": "/sys/module/sx_core/asic0/module33/"},
                    "module35": {"fin": "/sys/module/sx_core/asic0/module34/"},
                    "module36": {"fin": "/sys/module/sx_core/asic0/module35/"},
                    "module37": {"fin": "/sys/module/sx_core/asic0/module36/"},
                    "module38": {"fin": "/sys/module/sx_core/asic0/module37/"},
                    "module39": {"fin": "/sys/module/sx_core/asic0/module38/"},
                    "module40": {"fin": "/sys/module/sx_core/asic0/module39/"},
                    "module41": {"fin": "/sys/module/sx_core/asic0/module40/"},
                    "module42": {"fin": "/sys/module/sx_core/asic0/module41/"},
                    "module43": {"fin": "/sys/module/sx_core/asic0/module42/"},
                    "module44": {"fin": "/sys/module/sx_core/asic0/module43/"},
                    "module45": {"fin": "/sys/module/sx_core/asic0/module44/"},
                    "module46": {"fin": "/sys/module/sx_core/asic0/module45/"},
                    "module47": {"fin": "/sys/module/sx_core/asic0/module46/"},
                    "module48": {"fin": "/sys/module/sx_core/asic0/module47/"},
                    "module49": {"fin": "/sys/module/sx_core/asic0/module48/"},
                    "module50": {"fin": "/sys/module/sx_core/asic0/module49/"},
                    "module51": {"fin": "/sys/module/sx_core/asic0/module50/"},
                    "module52": {"fin": "/sys/module/sx_core/asic0/module51/"},
                    "module53": {"fin": "/sys/module/sx_core/asic0/module52/"},
                    "module54": {"fin": "/sys/module/sx_core/asic0/module53/"},
                    "module55": {"fin": "/sys/module/sx_core/asic0/module54/"},
                    "module56": {"fin": "/sys/module/sx_core/asic0/module55/"},
                    "module57": {"fin": "/sys/module/sx_core/asic0/module56/"},
                    "module58": {"fin": "/sys/module/sx_core/asic0/module57/"},
                    "module59": {"fin": "/sys/module/sx_core/asic0/module58/"},
                    "module60": {"fin": "/sys/module/sx_core/asic0/module59/"},
                    "module61": {"fin": "/sys/module/sx_core/asic0/module60/"},
                    "module62": {"fin": "/sys/module/sx_core/asic0/module61/"},
                    "module63": {"fin": "/sys/module/sx_core/asic0/module62/"},
                    "module64": {"fin": "/sys/module/sx_core/asic0/module63/"},
                    "module65": {"fin": "/sys/module/sx_core/asic0/module64/"},
                    "module66": {"fin": "/sys/module/sx_core/asic0/module65/"}, },
        },
        {"fin": None,
         "fn": "asic_state_poll", "arg" : ["/sys/module/sx_core/asic0/", 0], "poll": 10, "ts": 0}
    ],
    "test": [
         {"fin": "/tmp/power_button_clr",
         "fn": "run_power_button_event",
         "arg": [],
         "poll": 1, "ts": 0},
    ]
}

REDFISH_OBJ = None

"""
Key:
 'ReadingType': 'Temperature'
Value:
in 'Thresholds' reasponnse:
{
    'LowerCaution': {'Reading': 5.0},
    'UpperCaution': {'Reading': 105.0},
    'UpperCritical': {'Reading': 108.0}
}
"""
redfish_attr = {"Temperature" : {"folder" : "/var/run/hw-management/thermal",
                                 "LowerCaution" : "min",
                                 "UpperCaution" : "max",
                                 "LowerCritical" :"lcrit",
                                 "UpperCritical" :"crit"
                                },
                "Voltage" : {"folder" : "/var/run/hw-management/environment",
                             "LowerCaution" : "min",
                             "UpperCaution" : "max",
                             "LowerCritical" :"lcrit",
                             "UpperCritical" :"crit"
                            }
               }

# ----------------------------------------------------------------------
def redfish_init():
    bmc_accessor = BMCAccessor()
    ret = bmc_accessor.login()
    if ret != RedfishClient.ERR_CODE_OK:
        return None

    return bmc_accessor

# ----------------------------------------------------------------------
def redfish_get_req(path):
    global REDFISH_OBJ
    response = None
    if not REDFISH_OBJ:
        REDFISH_OBJ = redfish_init()

    if REDFISH_OBJ:
        cmd = REDFISH_OBJ.rf_client.build_get_cmd(path)
        ret, response, _ = REDFISH_OBJ.rf_client.exec_curl_cmd(cmd)

        if ret != RedfishClient.ERR_CODE_OK:
            REDFISH_OBJ.login()
            response = None

        if response:
            response = json.loads(response)
    return response

# ----------------------------------------------------------------------
def redfish_post_req(path, data_dict):
    global REDFISH_OBJ
    ret = None
    if not REDFISH_OBJ:
        REDFISH_OBJ = redfish_init()

    if REDFISH_OBJ:
        cmd = REDFISH_OBJ.rf_client.build_post_cmd(path, data_dict)
        ret, response, _ = REDFISH_OBJ.rf_client.exec_curl_cmd(cmd)

        if ret != RedfishClient.ERR_CODE_OK:
            REDFISH_OBJ.login()
    return ret

# ----------------------------------------------------------------------
def redfish_get_sensor(argv, _dummy):
    sensor_path = argv[0]
    response = redfish_get_req(sensor_path)
    if not response:
        return
    if response["Status"]["State"] != "Enabled":
        return
    if response["Status"]["Health"] != "OK":
        return

    ReadingType = response.get("ReadingType", None)
    if not ReadingType:
        return

    sensor_redfish_attr = redfish_attr.get(ReadingType, None)
    if not sensor_redfish_attr:
        return

    sensor_path = sensor_redfish_attr["folder"]
    sensor_name = argv[1]
    sensor_scale = argv[2]
    sensor_attr = {sensor_name : int(response["Reading"] * sensor_scale)}
    for responce_trh_name in response["Thresholds"].keys():
        if responce_trh_name in sensor_redfish_attr.keys():
            trh_name = "{}_{}".format(sensor_name, sensor_redfish_attr[responce_trh_name])
            trh_val = response["Thresholds"][responce_trh_name]["Reading"]
            sensor_attr[trh_name] = int(trh_val * sensor_scale)

    for attr_name, attr_val in sensor_attr.items():
        attr_path = os.path.join(sensor_path, attr_name)
        with open(attr_path, "w") as attr_file:
            attr_file.write(str(attr_val)+"\n")

# ----------------------------------------------------------------------
def run_power_button_event(argv, val):
    cmd = "/usr/bin/hw-management-chassis-events.sh hotplug-event POWER_BUTTON {}".format(val)
    os.system(cmd)
    cmd = "/usr/bin/hw-management-chassis-events.sh hotplug-event GRACEFUL_PWR_OFF {}".format(val)
    os.system(cmd)
    if str(val) == "1":
        cmd = """logger -t hw-management-sync -p daemon.info "Graceful CPU power off request " """
        os.system(cmd)
        """req_path = "redfish/v1/Systems/System_0/Actions/ComputerSystem.Reset"
        req_data = {"ResetType": "GracefulShutdown"}
        redfish_post_req(req_path, req_data)"""

# ----------------------------------------------------------------------
def run_cmd(cmd_list, arg):
    for cmd in cmd_list:
        cmd = cmd + " 2> /dev/null 1> /dev/null"
        os.system(cmd.format(arg1=arg))

# ----------------------------------------------------------------------
def asic_state_poll(arg_list, arg):
    """
        Check if all expected ASICs are inited
    """
    asic_path = arg_list[0]
    asic_state_old = arg_list[1]

    if os.path.exists(asic_path):
        asic_state = 1
    else:
        asic_state = 0

    if asic_state != asic_state_old:            
        arg_list[1] = asic_state
        asic_chipup_completed_fname = os.path.join("/var/run/hw-management/config", "asic_chipup_completed")
        with open(asic_chipup_completed_fname, 'a+', encoding="utf-8") as f:
            f.seek(0)
            try:
                asic_chipup_completed = f.read().rstrip('\n')
                asic_chipup_completed = int(asic_chipup_completed)
            except: 
                asic_chipup_completed = 0

            if asic_state == 1:
                asic_chipup_completed += 1
            else:
                asic_chipup_completed -= 1
        with open(asic_chipup_completed_fname, 'w', encoding="utf-8") as f:
            f.write(str(asic_chipup_completed)+"\n")

        asic_num_fname = os.path.join("/var/run/hw-management/config", "asic_num")
        try:
            with open(asic_num_fname, 'r', encoding="utf-8") as f:
                asic_num = f.read().rstrip('\n')
                asic_num = int(asic_num)
        except:
            asic_num = 255

        if asic_chipup_completed >= asic_num:
            asics_init_done = 1
        else:
            asics_init_done = 0

        asics_init_done_fname = os.path.join("/var/run/hw-management/config", "asics_init_done")
        with open(asics_init_done_fname, 'w+', encoding="utf-8") as f:
            f.write(str(asics_init_done)+"\n")

# ----------------------------------------------------------------------
def sync_fan(fan_id, val):
    if int(val) == 0:
        status = 1
    else:
        status = 0

    cmd = "echo {} > /var/run/hw-management/thermal/fan{}_status".format(status, fan_id)
    os.system(cmd)

    cmd = "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN{} {} 2> /dev/null 1> /dev/null".format(fan_id, status)
    os.system(cmd)

# ----------------------------------------------------------------------
def sdk_temp2degree(val):
    if val >= 0:
        temperature = val * 125
    else:
        temperature = 0xffff + val + 1
    return temperature

# ----------------------------------------------------------------------
def asic_temp_populate(arg_list, arg):
    """
    @summary: Update asic attributes
    """
    try:
        val = sdk_temp2degree(int(arg))
        temp_norm = "75000\n"
        temp_crit = "85000\n"
        temp_emergency = "105000\n"
        temp_fault = "120000\n"
    except:
        val = ""
        temp_crit = ""
        temp_emergency = ""
        temp_fault = ""
        temp_norm = ""

    f_name = "/var/run/hw-management/thermal/{}".format(arg_list[0])
    with open(f_name, 'w', encoding="utf-8") as f:
        f.write(str(val)+"\n")

    f_name = "/var/run/hw-management/thermal/{}_temp_trip_crit".format(arg_list[0])
    if not os.path.isfile(f_name):
        with open(f_name, 'w', encoding="utf-8") as f:
            f.write(temp_fault)

        f_name = "/var/run/hw-management/thermal/{}_temp_emergency".format(arg_list[0])
        with open(f_name, 'w', encoding="utf-8") as f:
            f.write(temp_emergency)

        f_name = "/var/run/hw-management/thermal/{}_temp_crit".format(arg_list[0])
        with open(f_name, 'w', encoding="utf-8") as f:
            f.write(temp_crit)

        f_name = "/var/run/hw-management/thermal/{}_temp_norm".format(arg_list[0])
        with open(f_name, 'w', encoding="utf-8") as f:
            f.write(temp_norm)

# ----------------------------------------------------------------------
def module_temp_populate(arg_list, _dummy):
    ''
    total_module_count = 0
    for module_name, module_attr in arg_list.items():
        total_module_count += 1
        f_dst_name = "/var/run/hw-management/thermal/{}_temp_input".format(module_name)
        if os.path.islink(f_dst_name):
            continue

        f_src_path = module_attr["fin"]
        module_present = 0

        # Check if module is present
        f_src_present = os.path.join(f_src_path, "present")
        try:
            with open(f_src_present, 'r') as f:
                module_present = int(f.read().strip())
        except (FileNotFoundError, ValueError):
            pass  # Module is not present or file reading failed

        # Default temperature values
        temperature = "0"
        temperature_min = "0"
        temperature_max = "0"
        temperature_fault = "0"
        temperature_crit = "0"

        if module_present:
            # reading module control (1 -SW, 0 - FW)
            f_read_mode_path = os.path.join(f_src_path, "control")
            try:
                with open(f_read_mode_path, 'r') as f:
                    read_mode = int(f.read().strip())
            except:
                # by default use SW control
                read_mode = 1
    
            # If control mode is FW, skip temperature reading
            if read_mode == 0:
                continue

            f_src_input = os.path.join(f_src_path, "temperature/input")
            f_src_min = os.path.join(f_src_path, "temperature/threshold_lo")
            f_src_max = os.path.join(f_src_path, "temperature/threshold_hi")

            try:
                with open(f_src_input, 'r') as f:
                    val = f.read()
                temperature = sdk_temp2degree(int(val))

                if os.path.isfile(f_src_min):
                    with open(f_src_min, 'r') as f:
                        val = f.read()
                    temperature_min = sdk_temp2degree(int(val))
                else:
                    temperature_min = "70000"

                if os.path.isfile(f_src_max):
                    with open(f_src_max, 'r') as f:
                        val = f.read()
                    temperature_max = sdk_temp2degree(int(val))
                else:
                     temperature_max = "75000"
                temperature_crit = "120000"
            except:
               pass

        # Write the temperature data to files
        file_paths = {
            "_temp_input": temperature,
            "_temp_crit": temperature_min,
            "_temp_emergency": temperature_max,
            "_temp_fault": temperature_fault,
            "_temp_trip_crit": temperature_crit
        }

        for suffix, value in file_paths.items():
            f_name = "/var/run/hw-management/thermal/{}{}".format(module_name, suffix)
            with open(f_name, 'w', encoding="utf-8") as f:
                f.write("{}\n".format(value))
    
    with open("/var/run/hw-management/config/module_counter", 'w+', encoding="utf-8") as f:
        f.write("{}\n".format(total_module_count))
    return

# ----------------------------------------------------------------------
def update_attr(attr_prop):
    """
    @summary: Update hw-mgmt attributes and invoke cmd per attr change
    """
    ts = time.time()
    if ts >= attr_prop["ts"]:
        # update timestamp
        attr_prop["ts"] = ts + attr_prop["poll"]
        fn_name = attr_prop["fn"]
        argv = attr_prop["arg"]
        fin = attr_prop.get("fin", None)
        # File content based trigger
        if fin:
            fin_name = fin.format(hwmon=attr_prop.get("hwmon", ""))
            if os.path.isfile(fin_name):
                try:
                    with open(fin_name, 'r', encoding="utf-8") as f:
                        val = f.read().rstrip('\n')
                    if "oldval" not in attr_prop.keys() or attr_prop["oldval"] != val:
                        globals()[fn_name](argv, val)
                        attr_prop["oldval"] = val
                except:
                    # File exists but read error
                    globals()[fn_name](argv, "")
                    attr_prop["oldval"] = ""
                    pass
            else:
                attr_prop["oldval"] = None
        else:
            try:
                globals()[fn_name](argv, None)
            except:
                pass

def init_attr(attr_prop):
    if "hwmon" in str(attr_prop["fin"]):
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
            f = open("/sys/devices/virtual/dmi/id/product_sku", "r")
            product_sku = f.read()
        except Exception as e:
            product_sku = ""
    else:
        product_sku = sys.argv[1]
    product_sku = product_sku.strip()
    
    sys_attr = None
    for key, val in atttrib_list.items():
        if re.match(key, product_sku):
            sys_attr = val
            break

    if not sys_attr:
        print("Not supported product SKU: {}".format(product_sku))
        while True:
            time.sleep(10)

    for attr in sys_attr:
        init_attr(attr)

    while True:
        for attr in sys_attr:
            update_attr(attr)
        time.sleep(1)

if __name__ == '__main__':
    main()
