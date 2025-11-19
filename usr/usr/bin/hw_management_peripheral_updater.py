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
    import time
    import json
    import re
    import argparse
    import traceback
    from hw_management_lib import HW_Mgmt_Logger as Logger
    from collections import Counter

    from hw_management_redfish_client import RedfishClient, BMCAccessor
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

# Import platform configuration - SINGLE SOURCE OF TRUTH
try:
    from hw_management_platform_config import get_module_count
except ImportError:
    # Fallback if platform config not available
    def get_module_count(sku):
        return 0

VERSION = "1.0.0"


class CONST(object):
    # *************************
    # Sensor constants
    # *************************
    # BMC sensor scale factor (temperature in millidegrees)
    BMC_SENSOR_SCALE = 1000

    # *************************
    # ASIC constants
    # *************************
    # Default ASIC count when config read fails
    ASIC_NUM_DEFAULT = 255

    # *************************
    # Folders definition
    # *************************
    # default hw-management folder
    HW_MGMT_FOLDER_DEF = "/var/run/hw-management"
    # File which defined current level filename.
    # User can dynamically change loglevel without svc restarting.
    LOG_LEVEL_FILENAME = "config/log_level"


def _build_attrib_list():
    """
    Build peripheral configuration dictionary from central platform config.

    This function dynamically generates the peripheral monitoring configuration
    from the centralized hw_management_platform_config module, eliminating
    duplication and ensuring consistency across services.

    Returns:
        dict: Dictionary mapping SKUs to their peripheral monitoring entries.
              Each entry is a list of monitoring items with 'fin', 'fn', 'arg',
              'poll', and 'ts' keys.

    Notes:
        - Configuration is built from PLATFORM_CONFIG in hw_management_platform_config
        - Individual SKUs (HI162, HI166, etc.) are taken directly from PLATFORM_CONFIG
        - 'def' key contains default monitoring applicable to all platforms
        - 'test' key contains test-specific monitoring entries
    """
    from hw_management_platform_config import PLATFORM_CONFIG

    # Use PLATFORM_CONFIG directly - it already contains the ready-to-use entries
    # No need to build them dynamically since the old table structure has them
    config = PLATFORM_CONFIG.copy()

    return config


# Build peripheral configuration dynamically from centralized platform config
attrib_list = _build_attrib_list()


# ----------------------------------------------------------------------
# ASIC CHIPUP STATUS MANAGEMENT
# ----------------------------------------------------------------------
# These functions manage ASIC initialization status tracking.
# Moved to peripheral_updater for reliability (this service is less likely
# to be disabled/killed compared to thermal_updater).
# ----------------------------------------------------------------------

def get_asic_num():
    """
    @summary: Read the number of ASICs configured for the system
    @return: Number of ASICs, or CONST.ASIC_NUM_DEFAULT if unable to read
    """
    asic_num_fname = os.path.join("/var/run/hw-management/config", "asic_num")
    try:
        with open(asic_num_fname, 'r', encoding="utf-8") as f:
            asic_num = f.read().rstrip('\n')
            asic_num = int(asic_num)
        if LOGGER:
            LOGGER.info(None, id="asic_num_read_fail")
        return asic_num
    except (OSError, ValueError) as e:
        error_message = str(e)
        if LOGGER:
            LOGGER.warning("{} {}".format(asic_num_fname, error_message), id="asic_num_read_fail")
        return CONST.ASIC_NUM_DEFAULT


def update_asic_chipup_status(asic_chipup_completed):
    """
    @summary: Update ASIC chipup completion status files

    Writes the number of ASICs that have completed chipup and determines
    if all ASICs are initialized based on the configured asic_num.

    This function is called by thermal_updater when monitoring ASIC temperatures,
    but lives in peripheral_updater for reliability (thermal_updater can be
    disabled by customers or killed by OS).

    @param asic_chipup_completed: Number of unique ASICs that have completed chipup
    """
    asic_chipup_completed_fname = os.path.join("/var/run/hw-management/config", "asic_chipup_completed")
    asics_init_done_fname = os.path.join("/var/run/hw-management/config", "asics_init_done")

    # Get expected number of ASICs
    asic_num = get_asic_num()

    # Determine if all ASICs are initialized
    asics_init_done = 1 if asic_chipup_completed >= asic_num else 0

    # Write asics_init_done status
    try:
        with open(asics_init_done_fname, 'w+', encoding="utf-8") as f:
            f.write(str(asics_init_done) + "\n")
        if LOGGER:
            LOGGER.info(None, id="asics_init_done_write_fail")
    except OSError as e:
        if LOGGER:
            LOGGER.warning("Failed to write {}: {}".format(asics_init_done_fname, e),
                           id="asics_init_done_write_fail")

    # Write asic_chipup_completed count
    try:
        with open(asic_chipup_completed_fname, 'w', encoding="utf-8") as f:
            f.write(str(asic_chipup_completed) + "\n")
        if LOGGER:
            LOGGER.info(None, id="asic_chipup_completed_write_fail")
    except OSError as e:
        if LOGGER:
            LOGGER.warning("Failed to write {}: {}".format(asic_chipup_completed_fname, e),
                           id="asic_chipup_completed_write_fail")

    # Log the status for debugging
    if LOGGER:
        if asics_init_done:
            LOGGER.debug("All ASICs initialized: {}/{}".format(asic_chipup_completed, asic_num))
        else:
            LOGGER.debug("ASICs initializing: {}/{}".format(asic_chipup_completed, asic_num))


def monitor_asic_chipup_status(arg, _dummy):
    """
    @summary: Monitor ASIC chipup completion status independently of thermal monitoring

    This function checks which ASICs are ready by probing their sysfs paths
    and updates chipup status files. It runs in peripheral_updater to ensure
    chipup tracking continues even if thermal_updater is stopped by users or OS.

    Unlike thermal_updater's temperature monitoring, this function only checks
    ASIC readiness (chipup completion) by verifying temperature file accessibility,
    without processing temperature values.

    @param arg: Dictionary with ASIC configuration in format:
                {"asic": {"fin": "/path/to/asic0/"},
                 "asic1": {"fin": "/path/to/asic0/"},
                 "asic2": {"fin": "/path/to/asic1/"}}
    @param _dummy: Unused parameter (for interface compatibility with update functions)

    Design rationale:
    - Peripheral_updater is more critical and less likely to be disabled
    - Chipup status is initialization state, not thermal-specific data
    - Other services may depend on chipup status even without thermal monitoring
    """
    if not isinstance(arg, dict):
        return

    asic_src_list = []

    # Check each configured ASIC for readiness
    for asic_name, asic_info in arg.items():
        if not isinstance(asic_info, dict):
            continue

        f_asic_src_path = asic_info.get("fin", "")
        if not f_asic_src_path:
            continue

        # Check if ASIC is ready by verifying temperature/input file exists and is readable
        f_src_input = os.path.join(f_asic_src_path, "temperature/input")
        if os.path.isfile(f_src_input):
            try:
                # Try to read temperature to verify ASIC is actually ready
                # (not just that the file exists)
                with open(f_src_input, 'r', encoding="utf-8") as f:
                    val = f.read()
                # Successfully read - ASIC is ready
                # Count unique source paths (same ASIC may appear multiple times)
                if f_asic_src_path not in asic_src_list:
                    asic_src_list.append(f_asic_src_path)
                    if LOGGER:
                        LOGGER.debug("ASIC ready: {} -> {}".format(asic_name, f_asic_src_path))
            except (OSError, ValueError):
                # Can't read - ASIC not ready yet
                if LOGGER:
                    LOGGER.debug("ASIC not ready: {} -> {}".format(asic_name, f_asic_src_path))

    # Update chipup status based on number of unique ready ASICs
    asic_chipup_completed = len(asic_src_list)
    update_asic_chipup_status(asic_chipup_completed)


# ----------------------------------------------------------------------
# MODULE-LEVEL SINGLETONS
# ----------------------------------------------------------------------
# LOGGER: Initialized once in main(), used throughout the daemon for consistent logging
#         This is a standard pattern for daemon logging infrastructure
LOGGER = None

# RedfishConnection: Singleton class to manage BMC connection state


class RedfishConnection:
    """
    @summary: Singleton class to manage Redfish BMC connection

    Encapsulates the global Redfish connection object to avoid direct
    global variable access. Provides lazy initialization and automatic
    reconnection on failures.
    """
    _instance = None

    @classmethod
    def get_instance(cls):
        """
        @summary: Get or create the singleton Redfish connection
        @return: BMCAccessor object or None if connection failed
        """
        if cls._instance is None:
            bmc_accessor = BMCAccessor()
            ret = bmc_accessor.login()
            if ret == RedfishClient.ERR_CODE_OK:
                cls._instance = bmc_accessor
        return cls._instance

    @classmethod
    def reset_instance(cls):
        """
        @summary: Reset the connection (forces reconnection on next use)
        """
        cls._instance = None


"""
Key:
 'ReadingType': 'Temperature'
Value:
in 'Thresholds' response:
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
    """
    @summary: Initialize Redfish BMC connection
    @return: BMCAccessor object if login successful, None otherwise
    @deprecated: Use RedfishConnection.get_instance() instead
    """
    return RedfishConnection.get_instance()

# ----------------------------------------------------------------------


def redfish_get_req(path):
    """
    @summary: Execute Redfish GET request
    @param path: Redfish API endpoint path
    @return: Response data as dictionary, or None on error
    """
    response = None
    redfish_obj = RedfishConnection.get_instance()

    if redfish_obj:
        cmd = redfish_obj.rf_client.build_get_cmd(path)
        ret, response, _ = redfish_obj.rf_client.exec_curl_cmd(cmd)

        if ret != RedfishClient.ERR_CODE_OK:
            # Try to re-login and reset connection for next attempt
            redfish_obj.login()
            response = None

        if response:
            response = json.loads(response)
    return response

# ----------------------------------------------------------------------


def redfish_post_req(path, data_dict):
    """
    @summary: Execute Redfish POST request
    @param path: Redfish API endpoint path
    @param data_dict: Dictionary containing request data
    @return: Return code from request execution
    """
    ret = None
    redfish_obj = RedfishConnection.get_instance()

    if redfish_obj:
        cmd = redfish_obj.rf_client.build_post_cmd(path, data_dict)
        ret, response, _ = redfish_obj.rf_client.exec_curl_cmd(cmd)

        if ret != RedfishClient.ERR_CODE_OK:
            # Try to re-login for next attempt
            redfish_obj.login()
    return ret

# ----------------------------------------------------------------------


def redfish_get_sensor(argv, _dummy):
    """
    @summary: Read sensor data via Redfish and write to hw-management sysfs
    @param argv: List containing [sensor_path, sensor_name, sensor_scale]
    @param _dummy: Unused parameter (for interface compatibility)
    """
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
    """
    @summary: Handle power button and graceful power-off events
    @param argv: Unused argument list (for interface compatibility)
    @param val: Event value (1=pressed/triggered, 0=released/cleared)
    """
    cmd = "/usr/bin/hw-management-chassis-events.sh hotplug-event POWER_BUTTON {}".format(val)
    os.system(cmd)
    cmd = "/usr/bin/hw-management-chassis-events.sh hotplug-event GRACEFUL_PWR_OFF {}".format(val)
    os.system(cmd)
    if str(val) == "1":
        cmd = """logger -t hw-management-peripheral-updater -p daemon.info "Graceful CPU power off request " """
        os.system(cmd)

# ----------------------------------------------------------------------


def run_cmd(cmd_list, arg):
    """
    @summary: Execute list of shell commands with argument substitution
    @param cmd_list: List of command strings (supports {arg1} placeholder)
    @param arg: Argument value to substitute into commands
    """
    for cmd in cmd_list:
        cmd = cmd + " 2> /dev/null 1> /dev/null"
        os.system(cmd.format(arg1=arg))

# ----------------------------------------------------------------------


def sync_fan(fan_id, val):
    """
    @summary: Synchronize fan status and trigger chassis events
    @param fan_id: Fan number/identifier (1-based index)
    @param val: Fan presence value (0=absent/fault, non-zero=present)
    """
    if int(val) == 0:
        status = 1
    else:
        status = 0

    cmd = "echo {} > /var/run/hw-management/thermal/fan{}_status".format(status, fan_id)
    os.system(cmd)

    cmd = "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN{} {} 2> /dev/null 1> /dev/null".format(fan_id, status)
    os.system(cmd)

# ----------------------------------------------------------------------


def update_peripheral_attr(attr_prop):
    """
    @summary: Update peripheral attributes and invoke monitoring functions on value changes

    This function is called for each peripheral monitoring entry (fans, leakage sensors,
    power button, BMC sensors, etc.) at the configured polling interval. It reads the
    input file and invokes the appropriate function only when the value changes,
    implementing change-based triggering for peripheral monitoring.
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
                except (OSError, ValueError):
                    # File exists but read error
                    globals()[fn_name](argv, "")
                    attr_prop["oldval"] = ""
            else:
                attr_prop["oldval"] = None
        else:
            try:
                globals()[fn_name](argv, None)
            except (OSError, ValueError, KeyError, TypeError):
                # Catch common errors from dynamically called functions
                # to prevent daemon crash
                pass


def init_attr(attr_prop):
    """
    @summary: Initialize attribute properties, resolve hwmon device names
    @param attr_prop: Attribute property dictionary to initialize
    """
    LOGGER.info("init_attr: {}".format(attr_prop))
    if "hwmon" in str(attr_prop["fin"]):
        path = attr_prop["fin"].split("hwmon")[0]
        try:
            flist = os.listdir(os.path.join(path, "hwmon"))
            hwmon_name = [fn for fn in flist if "hwmon" in fn]
            attr_prop["hwmon"] = hwmon_name[0]
        except (OSError, IndexError) as e:
            attr_prop["hwmon"] = ""


def write_module_counter(product_sku):
    """
    @summary: Write module_counter configuration file during initialization

    Gets module_count from centralized platform configuration and writes it to
    /var/run/hw-management/config/module_counter for use by other services.
    This is done in peripheral_updater to ensure availability even if
    thermal_updater is disabled by the customer.

    @param product_sku: Platform SKU identifier to load correct config
    """
    # Get module count from centralized platform configuration
    # This is the SINGLE SOURCE OF TRUTH for module counts
    module_count = get_module_count(product_sku)

    # Always write module_counter (even 0) so other services can reliably read it
    try:
        with open("/var/run/hw-management/config/module_counter", 'w', encoding="utf-8") as f:
            f.write("{}\n".format(module_count))
        if module_count > 0:
            LOGGER.notice("hw-management-peripheral-updater: module_counter initialized ({})".format(module_count))
        else:
            LOGGER.notice("hw-management-peripheral-updater: module_counter initialized (0 - no modules on this platform)")
    except OSError as e:
        LOGGER.warning("Failed to write module_counter: {}".format(e))


def main():
    """
    @summary: Update attributes
    arg1: system type
    """

    CMD_PARSER = argparse.ArgumentParser(description="HW Management Peripheral Updater")
    CMD_PARSER.add_argument("--version", action="version", version="%(prog)s ver:{}".format(VERSION))
    CMD_PARSER.add_argument("-l", "--log_file",
                            dest="log_file",
                            help="Add output also to log file. Pass file name here",
                            default="/var/log/hw_management_peripheral_updater_log")

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
            with open("/sys/devices/virtual/dmi/id/product_sku", "r") as f:
                product_sku = f.read()
        except OSError as e:
            product_sku = ""
    else:
        product_sku = args["system_type"]
    product_sku = product_sku.strip()

    LOGGER.notice("hw-management-peripheral-updater: load config ({})".format(product_sku))
    sys_attr = attrib_list["def"]
    for key, val in attrib_list.items():
        if re.match(key, product_sku):
            sys_attr.extend(val)
            break

    # Write module_counter for other services (must be done before they start)
    # This is done here in peripheral_updater to ensure it's written even if
    # thermal_updater is disabled by the customer
    write_module_counter(product_sku)

    LOGGER.notice("hw-management-peripheral-updater: init attributes")
    for attr in sys_attr:
        init_attr(attr)

    LOGGER.notice("hw-management-peripheral-updater: start main loop")
    while True:
        try:
            for attr in sys_attr:
                update_peripheral_attr(attr)
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

        time.sleep(1)


if __name__ == '__main__':
    main()
