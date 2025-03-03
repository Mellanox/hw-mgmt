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

        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic": {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                    "asic2": {"fin": "/sys/module/sx_core/asic1/"}
                },
        },

        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 36}
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

        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic": {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                    "asic2": {"fin": "/sys/module/sx_core/asic1/"}
                }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 36}
        },
        {"fin": None,
         "fn": "redfish_get_sensor", "arg" : ["/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP", "bmc", 1000], "poll": 30, "ts": 0}
    ],
    "HI171|HI172|HI144|HI147|HI148|HI174": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic":  {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 66}
        }        
    ],
    "HI122": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic":  {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 32}
        }
    ],
    "HI123|HI124": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic":  {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 64}
        }
    ],
    "HI160": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic":  {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 28}
        }
    ],
    "HI157": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic":  {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                    "asic2": {"fin": "/sys/module/sx_core/asic1/"}
                }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 37}
        }
    ],
    "HI158": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic":  {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                    "asic2": {"fin": "/sys/module/sx_core/asic1/"},
                    "asic3": {"fin": "/sys/module/sx_core/asic2/"},
                    "asic4": {"fin": "/sys/module/sx_core/asic3/"}
                }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 73}
        }
    ],
    "HI175": [
       {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg" : {  "asic":  {"fin": "/sys/module/sx_core/asic0/"},
                    "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                    "asic2": {"fin": "/sys/module/sx_core/asic1/"},
                    "asic3": {"fin": "/sys/module/sx_core/asic2/"},
                    "asic4": {"fin": "/sys/module/sx_core/asic3/"}
                 }
        },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg" : {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 91}
        }
    ],
    "def": [
         {"fin": "/var/run/hw-management/config/thermal_enforced_full_spped",
         "fn": "run_cmd",
         "arg": ["if [[ -f /var/run/hw-management/config/thermal_enforced_full_spped && "
                 "$(</var/run/hw-management/config/thermal_enforced_full_spped) == \"1\" ]]; then "
                 "/usr/bin/hw-management-user-dump; fi"],
         "poll": 5, "ts": 0},
    ],
    "test": [
         {"fin": "/tmp/power_button_clr",
         "fn": "run_power_button_event",
         "arg": [],
         "poll": 1, "ts": 0},
    ]
}

class CONST(object):
    # inde1pendent mode - module reading temperature via SDK sysfs
    SDK_FW_CONTROL = 0
    # inde1pendent mode - module reading temperature via EEPROM
    SDK_SW_CONTROL = 1
    #
    ASIC_TEMP_MIN_DEF = 75000
    ASIC_TEMP_MAX_DEF = 85000
    ASIC_TEMP_FAULT_DEF = 105000
    ASIC_TEMP_CRIT_DEF = 120000
    #
    MODULE_TEMP_MIN_DEF = 70000
    MODULE_TEMP_MAX_DEF = 75000
    MODULE_TEMP_FAULT_DEF = 105000
    MODULE_TEMP_CRIT_DEF = 120000

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
def is_module_host_management_mode(f_module_path):
    """
    @summary: Check if ASIC in independent mode
    @return: True if ASIC in independent mode
    """
    # Based on modue control type we can get SDK mode (dependent/independent)
    f_module_control_path = os.path.join(f_module_path, "control")
    try:
        with open(f_module_control_path, 'r') as f:
            # reading module control. 1 - SW(independent), 0 - FW(dependent)
            module_mode = int(f.read().strip())
    except:
        # by default use FW control (dependent mode)
        module_mode = CONST.SDK_FW_CONTROL

    # If control mode is FW, skip temperature reading (independent mode)
    return module_mode == CONST.SDK_SW_CONTROL

# ----------------------------------------------------------------------
def is_asic_ready(asic_name, asic_attr):
    asic_ready = False
    if os.path.exists(asic_attr["fin"]):
        f_asic_ready = "/var/run/hw-management/config/{}_ready".format(asic_name)
        try:
            with open(f_asic_ready, 'r') as f:
                asic_ready = int(f.read().strip())
        except:
            asic_ready = True
    return bool(asic_ready)

# ----------------------------------------------------------------------
def asic_temp_reset(asic_name, f_asic_src_path):
    # Default temperature values
    file_paths = {
        "": "",
        "_temp_norm": "",
        "_temp_crit": "",
        "_temp_emergency": "",
        "_temp_trip_crit": ""
    }
    for suffix, value in file_paths.items():
        f_name = "/var/run/hw-management/thermal/{}{}".format(asic_name, suffix)
        with open(f_name, 'w', encoding="utf-8") as f:
            f.write("{}\n".format(value))

# ----------------------------------------------------------------------
def asic_temp_populate(arg_list, arg):
    """
    @summary: Update asic attributes
    """
    asic_chipup_completed = 0
    asic_src_list = []
    for asic_name, asic_attr in arg_list.items():
        f_asic_src_path = asic_attr["fin"]
        # ASIC not ready (SDK is not started)
        if not is_asic_ready(asic_name, asic_attr):
            asic_temp_reset(asic_name, f_asic_src_path)
            continue

        if f_asic_src_path not in asic_src_list:
            asic_src_list.append(f_asic_src_path)
            asic_chipup_completed += 1

        # If link to asic temperatule already exists - nothing to do
        f_dst_name = "/var/run/hw-management/thermal/{}".format(asic_name)
        if os.path.islink(f_dst_name):
            continue

        # If independent mode - skip temperature reading
        if is_module_host_management_mode(os.path.join(f_asic_src_path, "module0")):
            continue

        # Default temperature values
        try:
            f_src_input = os.path.join(f_asic_src_path, "temperature/input")
            with open(f_src_input, 'r') as f:
                val = f.read()
            temperature = sdk_temp2degree(int(val))
            temperature_min =  CONST.ASIC_TEMP_MIN_DEF
            temperature_max = CONST.ASIC_TEMP_MAX_DEF
            temperature_fault = CONST.ASIC_TEMP_FAULT_DEF
            temperature_crit = CONST.ASIC_TEMP_CRIT_DEF
        except:
            temperature = ""
            temperature_min = ""
            temperature_max = ""
            temperature_fault = ""
            temperature_crit = ""

        file_paths = {
            "": temperature,
            "_temp_norm": temperature_min,
            "_temp_crit": temperature_max,
            "_temp_emergency": temperature_fault,
            "_temp_trip_crit": temperature_crit
        }

        # Write the temperature data to files
        for suffix, value in file_paths.items():
            f_name = "/var/run/hw-management/thermal/{}{}".format(asic_name, suffix)
            with open(f_name, 'w', encoding="utf-8") as f:
                f.write("{}\n".format(value))

    asic_chipup_completed_fname = os.path.join("/var/run/hw-management/config", "asic_chipup_completed")
    asic_num_fname = os.path.join("/var/run/hw-management/config", "asic_num")
    asics_init_done_fname = os.path.join("/var/run/hw-management/config", "asics_init_done")

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

    with open(asics_init_done_fname, 'w+', encoding="utf-8") as f:
        f.write(str(asics_init_done)+"\n")

    with open(asic_chipup_completed_fname, 'w', encoding="utf-8") as f:
        f.write(str(asic_chipup_completed)+"\n")

# ----------------------------------------------------------------------
def module_temp_populate(arg_list, _dummy):
    ''
    fin = arg_list["fin"]
    module_count = arg_list["module_count"]
    offset = arg_list["fout_idx_offset"]
    host_management_mode = None
    for idx in range(module_count):
        module_name = "module{}".format(idx+offset)
        f_dst_name = "/var/run/hw-management/thermal/{}_temp_input".format(module_name)
        if os.path.islink(f_dst_name):
            continue

        f_src_path = fin.format(idx)
        module_present = 0

        # Check if module is present
        f_src_present = os.path.join(f_src_path, "present")
        try:
            with open(f_src_present, 'r') as f:
                module_present = int(f.read().strip())
        except:
            pass  # Module is not present or file reading failed

        # Default temperature values
        temperature = "0"
        temperature_min = "0"
        temperature_max = "0"
        temperature_fault = "0"
        temperature_crit = "0"

        if module_present:
            # If control mode is FW, skip temperature reading (independent mode)
            if host_management_mode is None:
                host_management_mode = is_module_host_management_mode(f_src_path)

            if host_management_mode:
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
                    temperature_min = CONST.MODULE_TEMP_MIN_DEF

                if os.path.isfile(f_src_max):
                    with open(f_src_max, 'r') as f:
                        val = f.read()
                    temperature_max = sdk_temp2degree(int(val))
                else:
                    temperature_max = CONST.MODULE_TEMP_MAX_DEF
                temperature_crit = CONST.MODULE_TEMP_CRIT_DEF
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
        f.write("{}\n".format(module_count))
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

    sys_attr = atttrib_list["def"]
    for key, val in atttrib_list.items():
        if re.match(key, product_sku):
            sys_attr.extend(val)
            break

    for attr in sys_attr:
        init_attr(attr)

    while True:
        for attr in sys_attr:
            update_attr(attr)
        time.sleep(1)

if __name__ == '__main__':
    main()
