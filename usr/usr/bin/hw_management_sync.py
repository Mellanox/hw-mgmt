#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
# pylint: disable=W0718
# pylint: disable=R0913:
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

try:
    import os
    import sys
    import time
    import json
    import re
    import argparse
    import traceback
    from hw_management_lib import HW_Mgmt_Logger as Logger

    from hw_management_redfish_client import RedfishClient, BMCAccessor
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

VERSION = "1.0.0"

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
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage5",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE5 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage6",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE6 {arg1}"],
         "poll": 2, "ts": 0},

        {"fin": "/var/run/hw-management/system/power_button_evt",
         "fn": "run_power_button_event",
         "arg": [],
         "poll": 1, "ts": 0},

        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"}
                 },
         },

        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 36}
         },
        {"fin": None,
         "fn": "redfish_get_sensor", "arg": ["/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP", "bmc", 1000], "poll": 30, "ts": 0}
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
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage5",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE5 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage6",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE6 {arg1}"],
         "poll": 2, "ts": 0},

        {"fin": "/var/run/hw-management/system/graceful_pwr_off",
         "fn": "run_power_button_event",
         "arg": [],
         "poll": 1, "ts": 0},

        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 36}
         },
        {"fin": None,
         "fn": "redfish_get_sensor", "arg": ["/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP", "bmc", 1000], "poll": 30, "ts": 0}
    ],
    "HI144|HI174": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 65}
         }
    ],
    "HI147|HI171|HI172": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 66}
         }
    ],
    "HI112|HI116|HI136|MSN3700|MSN3700C": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 32}
         }
    ],
    "HI120": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 60}
         }
    ],
    "HI121": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 54}
         }
    ],
    "HI122|HI156|MSN4700": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 32}
         }
    ],
    "HI123|HI124": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 64}
         }
    ],
    "HI146": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 32}
         }
    ],
    "HI160": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 28}
         }
    ],
    "HI157": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 37}
         }
    ],
    "HI158": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"},
                 "asic3": {"fin": "/sys/module/sx_core/asic2/"},
                 "asic4": {"fin": "/sys/module/sx_core/asic3/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 73}
         }
    ],
    "HI175": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"},
                 "asic3": {"fin": "/sys/module/sx_core/asic2/"},
                 "asic4": {"fin": "/sys/module/sx_core/asic3/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 91}
         }
    ],
    "HI176": [
        {"fin": "/var/run/hw-management/system/graceful_pwr_off", "fn": "run_power_button_event",
         "arg": [], "poll": 1, "ts": 0},
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"}
                 }
         },
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage1",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage2",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": None,
         "fn": "redfish_get_sensor", "arg": ["/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP", "bmc", 1000], "poll": 30, "ts": 0}
    ],
    "HI177": [
        {"fin": "/var/run/hw-management/system/graceful_pwr_off", "fn": "run_power_button_event",
         "arg": [], "poll": 1, "ts": 0},
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"},
                 "asic3": {"fin": "/sys/module/sx_core/asic2/"}
                 }
         },
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage1",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage2",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": None,
         "fn": "redfish_get_sensor", "arg": ["/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP", "bmc", 1000], "poll": 30, "ts": 0}
    ],
    "HI178": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 24}
         }
    ],
    "HI179": [
        {"fin": None, "fn": "asic_temp_populate", "poll": 3, "ts": 0,
         "arg": {"asic": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic1": {"fin": "/sys/module/sx_core/asic0/"},
                 "asic2": {"fin": "/sys/module/sx_core/asic1/"},
                 "asic3": {"fin": "/sys/module/sx_core/asic2/"},
                 "asic4": {"fin": "/sys/module/sx_core/asic3/"}
                 }
         },
        {"fin": None, "fn": "module_temp_populate", "poll": 20, "ts": 0,
         "arg": {"fin": "/sys/module/sx_core/asic0/module{}/", "fout_idx_offset": 1, "module_count": 73}
         }
    ],
    "HI180": [
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage1",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage2",
         "fn": "run_cmd",
         "arg": ["/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}"],
         "poll": 2, "ts": 0},
        {"fin": "/var/run/hw-management/system/graceful_pwr_off",
         "fn": "run_power_button_event",
         "arg": [],
         "poll": 1, "ts": 0},
    ],
    "def": [
        {"fin": "/var/run/hw-management/config/thermal_enforced_full_speed",
         "fn": "run_cmd",
         "arg": ["if [[ -f /var/run/hw-management/config/thermal_enforced_full_speed && "
                 "$(</var/run/hw-management/config/thermal_enforced_full_speed) == \"1\" ]]; then "
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
    MODULE_TEMP_MAX_DEF = 75000
    MODULE_TEMP_FAULT_DEF = 105000
    MODULE_TEMP_CRIT_DEF = 120000
    MODULE_TEMP_EMERGENCY_OFFSET = 10000

    # *************************
    # Folders definition
    # *************************
    # default hw-management folder
    HW_MGMT_FOLDER_DEF = "/var/run/hw-management"
    # File which defined current level filename.
    # User can dynamically change loglevel without svc restarting.
    LOG_LEVEL_FILENAME = "config/log_level"


REDFISH_OBJ = None
LOGGER = None

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
redfish_attr = {"Temperature": {"folder": "/var/run/hw-management/thermal",
                                "LowerCaution": "min",
                                "UpperCaution": "max",
                                "LowerCritical": "lcrit",
                                "UpperCritical": "crit"
                                },
                "Voltage": {"folder": "/var/run/hw-management/environment",
                            "LowerCaution": "min",
                            "UpperCaution": "max",
                            "LowerCritical": "lcrit",
                            "UpperCritical": "crit"
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
    sensor_attr = {sensor_name: int(response["Reading"] * sensor_scale)}
    for responce_trh_name in response["Thresholds"].keys():
        if responce_trh_name in sensor_redfish_attr.keys():
            trh_name = "{}_{}".format(sensor_name, sensor_redfish_attr[responce_trh_name])
            trh_val = response["Thresholds"][responce_trh_name]["Reading"]
            sensor_attr[trh_name] = int(trh_val * sensor_scale)

    for attr_name, attr_val in sensor_attr.items():
        attr_path = os.path.join(sensor_path, attr_name)
        with open(attr_path, "w") as attr_file:
            attr_file.write(str(attr_val) + "\n")

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
    except BaseException:
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
        except BaseException:
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
        LOGGER.debug("{} temp_populate".format(asic_name))
        f_asic_src_path = asic_attr["fin"]
        # Check if ASIC not ready (SDK is not started)
        if not is_asic_ready(asic_name, asic_attr):
            LOGGER.notice("{} not ready".format(asic_name), id="{} not_ready".format(asic_name))
            asic_temp_reset(asic_name, f_asic_src_path)
            continue
        else:
            LOGGER.notice(None, id="{} not ready".format(asic_name))

        if f_asic_src_path not in asic_src_list:
            asic_src_list.append(f_asic_src_path)
            asic_chipup_completed += 1

        # If link to asic temperatule already exists - nothing to do
        f_dst_name = "/var/run/hw-management/thermal/{}".format(asic_name)
        if os.path.islink(f_dst_name):
            LOGGER.notice("{} link exists".format(asic_name), id="{} asic_link_exists".format(asic_name))
            continue
        else:
            LOGGER.notice(None, id="{} asic_link_exists".format(asic_name))

        # Default temperature values
        try:
            f_src_input = os.path.join(f_asic_src_path, "temperature/input")
            with open(f_src_input, 'r') as f:
                val = f.read()
            temperature = sdk_temp2degree(int(val))
            temperature_min = CONST.ASIC_TEMP_MIN_DEF
            temperature_max = CONST.ASIC_TEMP_MAX_DEF
            temperature_fault = CONST.ASIC_TEMP_FAULT_DEF
            temperature_crit = CONST.ASIC_TEMP_CRIT_DEF
        except Exception as e:
            error_message = str(e)
            LOGGER.warning("{} {}".format(error_message), id="{} read fail".format(asic_name))
            temperature = ""
            temperature_min = ""
            temperature_max = ""
            temperature_fault = ""
            temperature_crit = ""
            pass
        else:
            LOGGER.notice(None, id="{} read fail".format(asic_name))

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
                LOGGER.debug(f"Write {asic_name}{suffix}: {value}")

    asic_chipup_completed_fname = os.path.join("/var/run/hw-management/config", "asic_chipup_completed")
    asic_num_fname = os.path.join("/var/run/hw-management/config", "asic_num")
    asics_init_done_fname = os.path.join("/var/run/hw-management/config", "asics_init_done")

    try:
        with open(asic_num_fname, 'r', encoding="utf-8") as f:
            asic_num = f.read().rstrip('\n')
            asic_num = int(asic_num)
    except BaseException as e:
        error_message = str(e)
        LOGGER.warning("{} {}".format(asic_num_fname, error_message), id="{} asic_num_read_fail".format(asic_name))
        asic_num = 255
    else:
        LOGGER.notice(None, id="{} asic_num_read_fail".format(asic_name))

    if asic_chipup_completed >= asic_num:
        asics_init_done = 1
    else:
        asics_init_done = 0

    with open(asics_init_done_fname, 'w+', encoding="utf-8") as f:
        f.write(str(asics_init_done) + "\n")

    with open(asic_chipup_completed_fname, 'w', encoding="utf-8") as f:
        f.write(str(asic_chipup_completed) + "\n")

# ----------------------------------------------------------------------


def module_temp_populate(arg_list, _dummy):
    ''
    fin = arg_list["fin"]
    module_count = arg_list["module_count"]
    offset = arg_list["fout_idx_offset"]
    module_updated = False
    LOGGER.debug("module_temp_populate")
    for idx in range(module_count):
        module_name = "module{}".format(idx + offset)
        f_dst_name = "/var/run/hw-management/thermal/{}_temp_input".format(module_name)
        if os.path.islink(f_dst_name):
            LOGGER.notice("skip link: {}".format(module_name), id="{} link_exists".format(module_name))
            continue
        else:
            LOGGER.notice(None, id="{} link_exists".format(module_name))

        f_src_path = fin.format(idx)
        # If control mode is SW - skip temperature reading (independent mode)
        if is_module_host_management_mode(f_src_path):
            LOGGER.notice("{} independent mode".format(module_name), id="{} independent_mode".format(module_name))
            continue
        else:
            LOGGER.notice(None, id="{} independent_mode".format(module_name))

        # Check if module is present
        module_present = 0
        f_src_present = os.path.join(f_src_path, "present")
        try:
            with open(f_src_present, 'r') as f:
                module_present = int(f.read().strip())
        except BaseException as e:
            error_message = str(e)
            LOGGER.warning("{} {}".format(f_src_present, error_message), id="{} present_read_fail".format(module_name))
            pass
        else:
            LOGGER.notice(None, id="{} present_read_fail".format(module_name))

        # Default temperature values
        temperature = "0"
        temperature_emergency = "0"
        temperature_fault = "0"
        temperature_trip_crit = "0"
        temperature_crit = "0"
        cooling_level_input = None
        max_cooling_level_input = None

        if module_present:
            f_src_input = os.path.join(f_src_path, "temperature/input")
            f_src_crit = os.path.join(f_src_path, "temperature/threshold_hi")
            f_src_hcrit = os.path.join(f_src_path, "temperature/threshold_critical_hi")
            f_src_cooling_level_input = os.path.join(f_src_path, "temperature/tec/cooling_level")
            f_src_max_cooling_level_input = os.path.join(f_src_path, "temperature/tec/max_cooling_level")

            if os.path.isfile(f_src_cooling_level_input):
                try:
                    with open(f_src_cooling_level_input, 'r') as f:
                        cooling_level_input = f.read()
                except BaseException:
                    pass

            if os.path.isfile(f_src_max_cooling_level_input):
                try:
                    with open(f_src_max_cooling_level_input, 'r') as f:
                        max_cooling_level_input = f.read()
                except BaseException:
                    pass

            try:
                with open(f_src_input, 'r') as f:
                    val = f.read()
                temperature = sdk_temp2degree(int(val))

                if os.path.isfile(f_src_crit):
                    with open(f_src_crit, 'r') as f:
                        val = f.read()
                    temperature_crit = sdk_temp2degree(int(val))
                else:
                    temperature_crit = CONST.MODULE_TEMP_MAX_DEF

                if os.path.isfile(f_src_hcrit):
                    with open(f_src_hcrit, 'r') as f:
                        val = f.read()
                        temperature_emergency = sdk_temp2degree(int(val))
                else:
                    temperature_emergency = temperature_crit + CONST.MODULE_TEMP_EMERGENCY_OFFSET

                temperature_trip_crit = CONST.MODULE_TEMP_CRIT_DEF

            except BaseException:
                pass
        else:
            LOGGER.notice(None, id="{} read_fail".format(module_name), repeat=0)

        # Write the temperature data to files
        file_paths = {
            "_temp_input": temperature,  # SDK sysfs temperature/input
            "_temp_crit": temperature_crit,  # SDK sysfs temperature/threshold_hi, CMIS bytes 132-133 TempMonHighWarningTreshold
            "_temp_emergency": temperature_emergency,  # SDK sysfs temperature/threshold_critical_hi, CMIS bytes 128-129 TempMonHighAlarmTreshold
            "_temp_fault": temperature_fault,
            "_temp_trip_crit": temperature_trip_crit,
            "_cooling_level_input": cooling_level_input,  # SDK sysfs temperature/tec/cooling_level
            "_max_cooling_level_input": max_cooling_level_input,  # SDK sysfs temperature/tec/max_cooling_level
            "_status": module_present  # SDK sysfs moduleX/present
        }

        for suffix, value in file_paths.items():
            f_name = "/var/run/hw-management/thermal/{}{}".format(module_name, suffix)
            if value is not None:
                with open(f_name, 'w', encoding="utf-8") as f:
                    f.write("{}\n".format(value))
                    LOGGER.debug(f"Write {module_name}{suffix}: {value}")
        module_updated = True

    if module_updated:
        LOGGER.debug("{} module_counter ({}) updated".format(module_name, module_count))
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
                except Exception:
                    # File exists but read error
                    globals()[fn_name](argv, "")
                    attr_prop["oldval"] = ""
                    pass
            else:
                attr_prop["oldval"] = None
        else:
            try:
                globals()[fn_name](argv, None)
            except Exception:
                pass


def init_attr(attr_prop):
    LOGGER.info("init_attr: {}".format(attr_prop))
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

    CMD_PARSER = argparse.ArgumentParser(description="HW Management Sync Tool")
    CMD_PARSER.add_argument("--version", action="version", version="%(prog)s ver:{}".format(VERSION))
    CMD_PARSER.add_argument("-l", "--log_file",
                            dest="log_file",
                            help="Add output also to log file. Pass file name here",
                            default="/var/log/hw_management_sync_log")

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
    CMD_PARSER.add_argument("-s", "--system_type", nargs='?', help="System type (optional) for custom system emulation.")

    args = vars(CMD_PARSER.parse_args())
    global LOGGER
    LOGGER = Logger(log_file=args["log_file"], log_level=args["verbosity"], log_repeat=2)

    if args["system_type"] is None:
        try:
            f = open("/sys/devices/virtual/dmi/id/product_sku", "r")
            product_sku = f.read()
        except Exception as e:
            product_sku = ""
    else:
        product_sku = args["system_type"]
    product_sku = product_sku.strip()

    LOGGER.notice("hw-management-sync: load config ({}".format(product_sku))
    sys_attr = atttrib_list["def"]
    for key, val in atttrib_list.items():
        if re.match(key, product_sku):
            sys_attr.extend(val)
            break

    LOGGER.notice("hw-management-sync: init attributes")
    for attr in sys_attr:
        init_attr(attr)

    LOGGER.notice("hw-management-sync: start main loop")
    while True:
        for attr in sys_attr:
            update_attr(attr)
        try:
            log_level_filename = os.path.join(CONST.HW_MGMT_FOLDER_DEF, CONST.LOG_LEVEL_FILENAME)
            if os.path.isfile(log_level_filename):
                with open(log_level_filename, 'r', encoding="utf-8") as f:
                    log_level = f.read().rstrip('\n')
                    log_level = int(log_level)
                    LOGGER.set_loglevel(log_level)
        except Exception:
            LOGGER.error("Crash in main loop")
            LOGGER.notice(traceback.format_exc())
            pass

        time.sleep(1)


if __name__ == '__main__':
    main()
