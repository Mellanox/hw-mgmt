#!/usr/bin/python
# pylint: disable=line-too-long
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
Platform Hardware Configuration Module

This module provides a single source of truth for platform-specific hardware
configurations including:
- ASIC counts and sysfs paths
- Module (optical) counts and paths
- Thermal monitoring parameters
- Peripheral monitoring configuration (fans, leakage sensors, power buttons, etc.)

IMPORTANT: This is the ONLY place where platform hardware configuration should be defined.
All services (thermal_updater, peripheral_updater, hw-management.sh) should derive
their configuration from this module.
"""

VERSION = "1.0.0"

PLATFORM_CONFIG = {
    "def": [
        {'fin': '/var/run/hw-management/config/thermal_enforced_full_spped', 'fn': 'run_cmd', 'arg': ['if [[ -f /var/run/hw-management/config/thermal_enforced_full_spped && $(</var/run/hw-management/config/thermal_enforced_full_spped) == "1" ]]; then /usr/bin/hw-management-user-dump; fi'], 'poll': 5, 'ts': 0},
    ],
    "test": [
        {'fin': '/tmp/power_button_clr', 'fn': 'run_power_button_event', 'arg': [], 'poll': 1, 'ts': 0},
    ],
    "HI112|HI116|HI136|MSN3700|MSN3700C": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 32}},
    ],
    "HI120": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 60}},
    ],
    "HI121": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 54}},
    ],
    "HI122|HI156|MSN4700": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 32}},
    ],
    "HI123|HI124": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 64}},
    ],
    "HI144|HI174": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 65}},
    ],
    "HI146": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 32}},
    ],
    "HI147|HI171|HI172": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 66}},
    ],
    "HI157": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 37}},
    ],
    "HI158": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}, 'asic3': {'fin': '/sys/module/sx_core/asic2/'}, 'asic4': {'fin': '/sys/module/sx_core/asic3/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}, 'asic3': {'fin': '/sys/module/sx_core/asic2/'}, 'asic4': {'fin': '/sys/module/sx_core/asic3/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 73}},
    ],
    "HI160": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 28}},
    ],
    "HI162": [
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan1', 'fn': 'sync_fan', 'arg': '1', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan2', 'fn': 'sync_fan', 'arg': '2', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan3', 'fn': 'sync_fan', 'arg': '3', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan4', 'fn': 'sync_fan', 'arg': '4', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan5', 'fn': 'sync_fan', 'arg': '5', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan6', 'fn': 'sync_fan', 'arg': '6', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage1', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage2', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage3', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE3 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage4', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE4 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/var/run/hw-management/system/power_button_evt', 'fn': 'run_power_button_event', 'arg': [], 'poll': 1, 'ts': 0},
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 36}},
        {'fin': None, 'fn': 'redfish_get_sensor', 'arg': ['/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP', 'bmc', 1000], 'poll': 30, 'ts': 0},
    ],
    "HI166|HI167|HI169|HI170": [
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan1', 'fn': 'sync_fan', 'arg': '1', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan2', 'fn': 'sync_fan', 'arg': '2', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan3', 'fn': 'sync_fan', 'arg': '3', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/fan4', 'fn': 'sync_fan', 'arg': '4', 'poll': 5, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage1', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE1 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage2', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE2 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage3', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE3 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/sys/devices/platform/mlxplat/mlxreg-io/hwmon/{hwmon}/leakage4', 'fn': 'run_cmd', 'arg': ['/usr/bin/hw-management-chassis-events.sh hotplug-event LEAKAGE4 {arg1}'], 'poll': 2, 'ts': 0},
        {'fin': '/var/run/hw-management/system/graceful_pwr_off', 'fn': 'run_power_button_event', 'arg': [], 'poll': 1, 'ts': 0},
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 36}},
        {'fin': None, 'fn': 'redfish_get_sensor', 'arg': ['/redfish/v1/Chassis/MGX_BMC_0/Sensors/BMC_TEMP', 'bmc', 1000], 'poll': 30, 'ts': 0},
    ],
    "HI175": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}, 'asic3': {'fin': '/sys/module/sx_core/asic2/'}, 'asic4': {'fin': '/sys/module/sx_core/asic3/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}, 'asic2': {'fin': '/sys/module/sx_core/asic1/'}, 'asic3': {'fin': '/sys/module/sx_core/asic2/'}, 'asic4': {'fin': '/sys/module/sx_core/asic3/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 91}},
    ],
    "HI178": [
        {'fin': None, 'fn': 'asic_temp_populate', 'poll': 3, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'monitor_asic_chipup_status', 'poll': 5, 'ts': 0, 'arg': {'asic': {'fin': '/sys/module/sx_core/asic0/'}, 'asic1': {'fin': '/sys/module/sx_core/asic0/'}}},
        {'fin': None, 'fn': 'module_temp_populate', 'poll': 20, 'ts': 0, 'arg': {'fin': '/sys/module/sx_core/asic0/module{}/', 'fout_idx_offset': 1, 'module_count': 24}},
    ],
}


def get_platform_config(product_sku):
    """
    Get the complete platform configuration for a given SKU.

    This function matches the product_sku against regex patterns in PLATFORM_CONFIG keys.
    For example, a key "HI144|HI174" will match both "HI144" and "HI174" SKUs.

    @param product_sku: Platform SKU identifier (e.g., "HI162", "MSN3700", "HI144")
    @return: List of monitoring entries, or empty list if not found

    Example:
        config = get_platform_config("HI144")  # Matches "HI144|HI174" key
        if config:
            for entry in config:
                print(f"Function: {entry['fn']}, Poll: {entry['poll']}s")
    """
    import re

    config = []
    for key, val in PLATFORM_CONFIG.items():
        if re.match(key, product_sku):
            config = val
            break
    return config


def get_module_count(product_sku):
    """
    Get the number of optical modules for a given platform.

    Uses regex matching to find the platform config, then extracts module_count
    from the module_temp_populate entry.

    @param product_sku: Platform SKU identifier (e.g., "HI144")
    @return: Number of modules, or 0 if not found
    """
    # Use get_platform_config which handles regex matching
    config = get_platform_config(product_sku)
    if not config:
        return 0
    if isinstance(config, list):
        for entry in config:
            if entry.get("fn") == "module_temp_populate":
                arg = entry.get("arg", {})
                if isinstance(arg, dict):
                    return arg.get("module_count", 0)
        return 0
    return config.get("module_count", 0)


def get_all_platform_skus():
    """Get a list of all supported platform SKUs."""
    return list(PLATFORM_CONFIG.keys())
