#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
# pylint: disable=W0718
# pylint: disable=R0913:
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
Hardware Management Thermal Updater Service

This daemon monitors and updates ASIC and optical module temperature data
from SDK sysfs to hw-management thermal sysfs.

Separated from hw_management_sync.py to provide independent thermal monitoring
of ASICs and optical modules with different poll intervals and lifecycle management.
"""

try:
    import os
    import time
    import re
    import argparse
    import traceback
    import signal
    import threading
    from hw_management_lib import HW_Mgmt_Logger as Logger, atomic_file_write
    from collections import Counter
    from hw_management_platform_config import (
        PLATFORM_CONFIG,
        get_module_count
    )
    # Note: ASIC chipup status tracking is now handled independently by
    # peripheral_updater using monitor_asic_chipup_status() function.
    # This ensures chipup tracking continues even if thermal_updater is stopped.
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

VERSION = "1.0.0"


class CONST(object):
    # Module control modes
    SDK_FW_CONTROL = 0  # FW control (dependent mode)
    SDK_SW_CONTROL = 1  # SW control (independent mode)

    # ASIC temperature defaults (millidegrees)
    ASIC_TEMP_MIN_DEF = 75000
    ASIC_TEMP_MAX_DEF = 85000
    ASIC_TEMP_FAULT_DEF = 105000
    ASIC_TEMP_CRIT_DEF = 120000

    # Module temperature defaults (millidegrees)
    MODULE_TEMP_MAX_DEF = 75000
    MODULE_TEMP_FAULT_DEF = 105000
    MODULE_TEMP_CRIT_DEF = 120000
    MODULE_TEMP_EMERGENCY_OFFSET = 10000

    # Error retry configuration
    ASIC_READ_ERR_RETRY_COUNT = 3

    # Temperature conversion constants
    SDK_TEMP_MULTIPLIER = 125  # SDK to millidegrees conversion
    SDK_TEMP_MASK = 0xffff      # Mask for negative temperature values

    # Folder paths
    HW_MGMT_FOLDER_DEF = "/var/run/hw-management"
    LOG_LEVEL_FILENAME = "config/log_level"


# ----------------------------------------------------------------------
# PLATFORM CONFIGURATION - DYNAMICALLY BUILT FROM CENTRAL CONFIG
# ----------------------------------------------------------------------
# NOTE: Platform configurations are now maintained in hw_management_platform_config.py
# This is the SINGLE SOURCE OF TRUTH for all platform hardware definitions.
# The thermal_config dictionary is built dynamically from that central configuration.
# ----------------------------------------------------------------------

def _build_thermal_config():
    """
    Build thermal configuration dictionary from central platform config.

    This function dynamically generates the thermal_config structure used by
    the thermal updater daemon. The platform data comes from the centralized
    hw_management_platform_config module.

    This function filters the PLATFORM_CONFIG to extract only thermal-related
    entries (asic_temp_populate, module_temp_populate) since thermal_updater
    only handles temperature monitoring, not peripheral monitoring.

    @return: Dictionary mapping platform patterns to thermal configurations
    """
    from hw_management_platform_config import get_all_platform_skus

    config = {}

    # Define which functions are thermal-related (handled by this updater)
    thermal_functions = {"asic_temp_populate", "module_temp_populate"}

    # Build configuration for each platform, filtering for thermal entries only
    for sku in get_all_platform_skus():
        platform_entries = PLATFORM_CONFIG.get(sku, [])
        if platform_entries:
            # Filter to only thermal-related entries
            thermal_entries = [
                entry for entry in platform_entries
                if entry.get("fn") in thermal_functions
            ]
            if thermal_entries:
                config[sku] = thermal_entries

    # Add default empty configuration
    config["def"] = []

    return config


# Build the thermal configuration at module load time
# This maintains backward compatibility with existing code that expects thermal_config dict
thermal_config = _build_thermal_config()

# Module-level singleton for logging
LOGGER = None

EXIT = threading.Event()
sig_condition_name = ""

# ----------------------------------------------------------------------


def sdk_temp2degree(val):
    """
    @summary: Convert SDK temperature value to millidegrees Celsius
    @param val: Raw temperature value from SDK
    @return: Temperature in millidegrees Celsius (e.g., 85000 = 85°C)
    """
    if val >= 0:
        temperature = val * CONST.SDK_TEMP_MULTIPLIER
    else:
        temperature = CONST.SDK_TEMP_MASK + val + 1
    return temperature

# ----------------------------------------------------------------------


def is_module_host_management_mode(f_module_path):
    """
    @summary: Check if ASIC in independent mode
    @return: True if ASIC in independent mode
    """
    # Based on module control type we can get SDK mode (dependent/independent)
    f_module_control_path = os.path.join(f_module_path, "control")
    try:
        with open(f_module_control_path, 'r') as f:
            # reading module control. 1 - SW(independent), 0 - FW(dependent)
            module_mode = int(f.read().strip())
    except (OSError, ValueError):
        # by default use FW control (dependent mode)
        module_mode = CONST.SDK_FW_CONTROL

    # If control mode is FW, skip temperature reading (independent mode)
    return module_mode == CONST.SDK_SW_CONTROL

# ----------------------------------------------------------------------


def is_asic_ready(asic_name, asic_attr):
    """
    @summary: Check if ASIC is ready for temperature reading
    @param asic_name: ASIC identifier (e.g., "asic", "asic1")
    @param asic_attr: Dictionary containing ASIC attributes including "fin" path
    @return: True if ASIC is ready, False otherwise
    """
    asic_ready = False
    if os.path.exists(asic_attr["fin"]):
        f_asic_ready = "/var/run/hw-management/config/{}_ready".format(asic_name)
        try:
            with open(f_asic_ready, 'r') as f:
                asic_ready = int(f.read().strip())
        except (OSError, ValueError):
            asic_ready = True
    return bool(asic_ready)

# ----------------------------------------------------------------------


def asic_temp_reset(asic_name, f_asic_src_path):
    """
    @summary: Reset ASIC temperature attributes to empty values
    @param asic_name: ASIC identifier (e.g., "asic", "asic1")
    @param f_asic_src_path: Path to ASIC source directory (unused but kept for interface)
    """
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
        atomic_file_write(f_name, str(value) + "\n")


# ----------------------------------------------------------------------


def asic_temp_populate(arg_list, arg):
    """
    @summary: Update ASIC temperature attributes

    Reads temperature data from SDK sysfs and writes to hw-management thermal
    sysfs. This function focuses solely on temperature monitoring.

    Note: ASIC chipup status tracking is now handled independently by
    peripheral_updater's monitor_asic_chipup_status() function.

    @param arg_list: Dictionary of ASIC configurations with names as keys
    @param arg: Unused parameter (for interface compatibility)
    """
    for asic_name, asic_attr in arg_list.items():
        cntrs_obj = asic_attr.get("counters")
        if not cntrs_obj:
            cntrs_obj = Counter()
            asic_attr["counters"] = cntrs_obj

        LOGGER.debug("{} temp_populate".format(asic_name))
        f_asic_src_path = asic_attr["fin"]

        # Check if ASIC not ready (SDK is not started)
        if not is_asic_ready(asic_name, asic_attr):
            LOGGER.notice("{} not ready".format(asic_name), id="{} not_ready".format(asic_name))
            cntrs_obj["ASIC_NOT_READY"] += 1
            if cntrs_obj["ASIC_NOT_READY"] >= CONST.ASIC_READ_ERR_RETRY_COUNT:
                LOGGER.warning("{} ASIC_NOT_READY".format(asic_name),
                               id="{} ASIC_NOT_READY".format(asic_name))
                asic_temp_reset(asic_name, f_asic_src_path)
            continue
        else:
            cntrs_obj["ASIC_NOT_READY"] = 0
            LOGGER.info(None, id="{} not_ready".format(asic_name))
            LOGGER.info(None, id="{} ASIC_NOT_READY".format(asic_name))

        # If link to asic temperature already exists - nothing to do
        f_dst_name = "/var/run/hw-management/thermal/{}".format(asic_name)
        if os.path.islink(f_dst_name):
            LOGGER.notice("{} link exists".format(asic_name), id="{} asic_link_exists".format(asic_name))
            continue
        else:
            LOGGER.notice(None, id="{} asic_link_exists".format(asic_name))

        # Read temperature values
        try:
            f_src_input = os.path.join(f_asic_src_path, "temperature/input")
            with open(f_src_input, 'r') as f:
                val = f.read()
            temperature = sdk_temp2degree(int(val))
            temperature_min = CONST.ASIC_TEMP_MIN_DEF
            temperature_max = CONST.ASIC_TEMP_MAX_DEF
            temperature_fault = CONST.ASIC_TEMP_FAULT_DEF
            temperature_crit = CONST.ASIC_TEMP_CRIT_DEF
        except (OSError, ValueError) as e:
            error_message = str(e)
            LOGGER.notice("{} {}".format(f_src_input, error_message), id="{} read fail".format(asic_name))
            cntrs_obj["ASIC_READ_ERROR"] += 1
            if cntrs_obj["ASIC_READ_ERROR"] >= CONST.ASIC_READ_ERR_RETRY_COUNT:
                LOGGER.warning("{} ASIC_READ_ERROR".format(asic_name),
                               id="{} ASIC_READ_ERROR".format(asic_name))
                asic_temp_reset(asic_name, f_asic_src_path)
            continue
        else:
            cntrs_obj["ASIC_READ_ERROR"] = 0
            LOGGER.info(None, id="{} read fail".format(asic_name))
            LOGGER.info(None, id="{} ASIC_READ_ERROR".format(asic_name))

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
            try:
                atomic_file_write(f_name, str(value) + "\n")
            except Exception as e:
                LOGGER.error(f"Error writing {f_name}: {e}")
                continue

# ----------------------------------------------------------------------


def module_temp_populate(arg_list, _dummy):
    """
    @summary: Populate module temperature attributes from SDK sysfs

    Reads temperature data for optical modules from SDK sysfs interface
    and writes to hw-management thermal sysfs. Only processes modules
    in FW control mode (dependent mode, not host management).

    @param arg_list: Dictionary containing:
                     - "fin": Path template for module directories
                     - "module_count": Number of modules to process
                     - "fout_idx_offset": Offset for output file indexing
    @param _dummy: Unused parameter (for interface compatibility)
    """
    fin = arg_list["fin"]
    module_count = arg_list["module_count"]
    offset = arg_list["fout_idx_offset"]
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
        except (OSError, ValueError) as e:
            error_message = str(e)
            LOGGER.warning("{} {}".format(f_src_present, error_message), id="{} present_read_fail".format(module_name))
        else:
            LOGGER.notice(None, id="{} present_read_fail".format(module_name))

        # Default temperature values
        temperature = "0"
        temperature_emergency = "0"
        temperature_fault = "0"
        temperature_trip_crit = "0"
        temperature_crit = "0"
        cooling_level_input = None
        cooling_level_warning = None

        if module_present:
            f_src_input = os.path.join(f_src_path, "temperature/input")
            f_src_crit = os.path.join(f_src_path, "temperature/threshold_hi")
            f_src_hcrit = os.path.join(f_src_path, "temperature/threshold_critical_hi")
            f_src_cooling_level_input = os.path.join(f_src_path, "temperature/tec/cooling_level")
            f_src_cooling_level_warning = os.path.join(f_src_path, "temperature/tec/warning_cooling_level")

            if os.path.isfile(f_src_cooling_level_input):
                try:
                    with open(f_src_cooling_level_input, 'r') as f:
                        cooling_level_input = f.read()
                except OSError:
                    pass

            if os.path.isfile(f_src_cooling_level_warning):
                try:
                    with open(f_src_cooling_level_warning, 'r') as f:
                        cooling_level_warning = f.read()
                except OSError:
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

            except (OSError, ValueError):
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
            "_cooling_level_input": cooling_level_input,
            "_cooling_level_warning": cooling_level_warning,
            "_status": module_present  # SDK sysfs moduleX/present
        }

        for suffix, value in file_paths.items():
            f_name = "/var/run/hw-management/thermal/{}{}".format(module_name, suffix)
            if value is not None:
                try:
                    atomic_file_write(f_name, str(value) + "\n")
                except Exception as e:
                    LOGGER.error(f"Error writing {f_name}: {e}")
                    continue

    return

# ----------------------------------------------------------------------


def update_thermal_attr(attr_prop):
    """
    @summary: Update thermal attributes and invoke temperature monitoring functions per poll interval

    This function is called for each thermal monitoring entry (ASIC temps, module temps)
    at the configured polling interval. It invokes the appropriate thermal function
    (e.g., asic_temp_populate, module_temp_populate) to read and update temperature data.
    """
    ts = time.time()
    if ts >= attr_prop["ts"]:
        # update timestamp
        attr_prop["ts"] = ts + attr_prop["poll"]
        fn_name = attr_prop["fn"]
        argv = attr_prop["arg"]

        try:
            globals()[fn_name](argv, None)
        except (OSError, ValueError, KeyError, TypeError):
            # Catch common errors from dynamically called functions
            # to prevent daemon crash
            pass

# ----------------------------------------------------------------------


def handle_shutdown(sig, _frame):
    """
    @summary: Handle application signal
    @param sig: Signal
    @param _frame: Unused frame
    """
    global sig_condition_name
    try:
        sig_condition_name = signal.Signals(sig).name
    except (ValueError, AttributeError):
        sig_condition_name = str(sig)
    EXIT.set()

    return

# ----------------------------------------------------------------------


def main():
    """
    @summary: Hardware Management Thermal Updater Main Loop

    Monitors ASIC and optical module temperatures from SDK sysfs and
    updates hw-management thermal sysfs.
    """

    CMD_PARSER = argparse.ArgumentParser(description="HW Management Thermal Updater")
    CMD_PARSER.add_argument("--version", action="version", version="%(prog)s ver:{}".format(VERSION))
    CMD_PARSER.add_argument("-l", "--log_file",
                            dest="log_file",
                            help="Add output also to log file. Pass file name here",
                            default="/var/log/hw_management_thermal_updater_log")

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
            with open("/sys/devices/virtual/dmi/id/product_sku", "r") as f:
                product_sku = f.read()
        except OSError as e:
            product_sku = ""
    else:
        product_sku = args["system_type"]
    product_sku = product_sku.strip()

    LOGGER.notice("hw-management-thermal-updater: load config ({})".format(product_sku))
    thermal_attr = thermal_config["def"]
    for key, val in thermal_config.items():
        if re.match(key, product_sku):
            thermal_attr.extend(val)
            break

    EXIT.clear()
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGHUP, handle_shutdown)

    LOGGER.notice("hw-management-thermal-updater: start main loop")
    while not EXIT.is_set():
        try:
            for attr in thermal_attr:
                update_thermal_attr(attr)
            try:
                log_level_filename = os.path.join(CONST.HW_MGMT_FOLDER_DEF, CONST.LOG_LEVEL_FILENAME)
                if os.path.isfile(log_level_filename):
                    with open(log_level_filename, 'r', encoding="utf-8") as f:
                        log_level = f.read().rstrip('\n')
                        log_level = int(log_level)
                        LOGGER.set_loglevel(log_level)
            except (OSError, ValueError):
                # Expected errors when reading/parsing log level file
                # These are non-critical, just skip and continue
                pass
        except Exception as e:
            # Safety net: catch any unexpected exceptions to keep daemon alive
            LOGGER.error("Unexpected error in main loop: {}".format(e))
            LOGGER.notice(traceback.format_exc())
            # Continue running despite error

        EXIT.wait(timeout=1)

    LOGGER.notice("hw-management-thermal-updater: stopped main loop ({})".format(sig_condition_name))


if __name__ == '__main__':
    main()
