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

try:
    import os
    import json
    import re
    import argparse
    import traceback
    import signal
    import threading
    from hw_management_lib import (
        HW_Mgmt_Logger as Logger,
        exit_wait,
        current_milli_time,
    )
    from collections import Counter

    from hw_management_redfish_client import RedfishClient, BMCAccessor
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

# Import platform configuration - SINGLE SOURCE OF TRUTH
try:
    from hw_management_platform_config import get_module_count, get_platform_config
except ImportError:
    # Fallback if platform config not available
    def get_module_count(sku):
        return 0

    def get_platform_config(sku):
        return []

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
    LOG_FILE = "/var/log/hw-management-peripheral-updater.log"

    # Log rotation size
    LOG_ROTATION_SIZE = 1 * 1024 * 1024  # 1MB
    LOG_ROTATION_COUNT = 3


EXIT = threading.Event()
_sig_condition_name = ""


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

    This function is called by monitor_asic_chipup_status() within peripheral_updater
    for reliability (peripheral_updater runs independently and can't be disabled).

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
                {"asic1": {"fin": "/path/to/asic0/"},
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

def _resolve_hwmon(src_path):
    """
    @summary: Resolve hwmon name under path (init_attr logic)
    @param src_path: Path to hwmon directory
    @return: hwmonN (e.g. hwmon0) or empty string on failure
    """
    try:
        flist = os.listdir(os.path.join(src_path,"hwmon"))
        hwmon_list = [fn for fn in flist if "hwmon" in fn]
        if not hwmon_list:
            return ""
        else:
            return hwmon_list[0]
    except (OSError, IndexError):
        return ""

# ----------------------------------------------------------------------
def _init_hotplug_dev_state(arg, dev_name):
    """
    @summary: One-time init for device hotplug polling (hwmon path and dev_state list)
    @param arg: Platform config arg dict
    @param dev_name: Device name (e.g. fan1, psu1, pwr1)
    @return: Dict with dev_name, status, path_prefix, src_path
    if path_prefix not set in config - set it empty string since it not used in event command
    """
    dev = {"dev_name": dev_name, "status": None}
    src_path = arg.get("src_path", "")
    if not src_path:
        LOGGER.error("Failed to resolve src_path for: {}".format(dev_name), id="src_path_empty {}".format(dev_name), repeat=0, log_repeat=1)
        return {}

    dev["src_path"] = src_path
    dst_path = arg.get("_dst_path", "")
    if not dst_path:
        # dst path not set - no mirroring to dst_path will be done
        # use src_path as dst_path
        dev["dst_path"] = src_path
    else:
        dev["dst_path"] = dst_path
    dev["path_prefix"] = arg.get("_path_prefix", "/")
    return dev

# ----------------------------------------------------------------------
def _send_hotplug_event(arg, dev, status):
    """
    @summary: Send hotpl event for a given device
    @param arg: Dict with path_prefix, evt_cmd (mutable)
    @param dev: Dict with dev_name, status, path_prefix, src_path
    @param status: Device status (0=absent/fault, 1=present)
    """
    # Mirror status bit to _dst_path (if _dst_path is set)
    if dev["dst_path"]:
        dst_path_name = os.path.join(dev["dst_path"], dev["dev_name"])
        LOGGER.info("sw_hotplug_handler: mirroring status bit to dst_path: {}".format(dst_path_name))
        if not os.path.exists(dev["dst_path"]):
            # create parent directories if missing
            os.makedirs(dev["dst_path"], exist_ok=True)

        with open(dst_path_name, 'w', encoding="utf-8") as f:
            f.write(str(status) + '\n')
    dev["status"] = status
    evt_cmd = arg.get("_evt_cmd", "")
    if not evt_cmd:
        return 1
    try:
        cmd = evt_cmd.format(**dev)
    except (KeyError, ValueError, TypeError, NameError, AttributeError) as e:
        LOGGER.error("update_hotplug_dev_event: failed to format command string: {}, error: {}".format(evt_cmd, e), id="failed_to_format_command_string {}".format(evt_cmd), repeat=0, log_repeat=3)
        return 1
    else:
        # Clear the rate-limit counter for this error ID so it will be logged again if the error recurs.
        LOGGER.notice(None, id="failed_to_format_command_string {}".format(evt_cmd))

    LOGGER.info("sw_hotplug_handler: executing command: {}".format(cmd))
    retcode = os.system(cmd + " 2> /dev/null 1> /dev/null")
    if retcode != 0:
        LOGGER.error("sw_hotplug_handler: failed to execute command: {}, retcode: {}".format(cmd, int(retcode)))
    return retcode

def sw_hotplug_handler(arg: dict, _dummy: any):
    """
    @summary: Software emulation of interrupt register handler. On interrupt event
    happens - run hotplug event handler.
    @param arg: dict with:
        - name_list: List of device names (e.g. ["fan1", "fan2", "fan3", "fan4", "fan5"]).
        - _event_reg: Event register name (e.g. fan_event). Bits packed to decimal value. Example:
            2 => 00000010 => Event for device[1] (fan2) is set. index starts from 0.
          '1' - event; '0' - no event
          Should be cleaned after event is handled. Write ‘0’ to clear event.
          On event change to 1 - get dev status from _status_reg. Check if status changed.
             - Status changed - run hotplug event.
             - Status not changed - it means we had fast insert/remove during the poll. Need to handle it
               status = 0 : means dev was inserted and removed fast. Just send hotplug event with status = 0.
               status = 1 : means dev was removed and inserted fast. Send 2 hotplug events with status = 0 and then with status = 1.
        - _status_reg: Status register name (e.g. fan_status). Bits packed to decimal value
          '1' - Present; '0' - Not Present
        - _mask: Mask value (e.g. 00111111). LSB is first device.
        - _src_path: Source path (e.g. /sys/devices/platform/mlxplat/mlxreg-io/hwmon/).
          Sysfs path to read status/event register from. If path contains 'hwmon' - resolve hwmon name and append to path.
        - _dst_path: Destination path (e.g. /var/run/hw-management/system/).
          Sysfs path to write status to (write file with status).
          Status file names defined in _name_list. If file already exists - replace it with new status or unlink it.
          Optional. If not set - no mirroring to dst_path will be done and dst = src_path.
          Example: /var/run/hw-management/system/fan1, /var/run/hw-management/system/fan2, etc.
        - _evt_cmd: Event command (e.g. /usr/bin/hw-management-chassis-events.sh hotplug-event {dev_name} {status} {path_prefix} {dst_path}).
          Command to run hotplug event.
          Example: /usr/bin/hw-management-chassis-events.sh hotplug-event FAN1 1 {path_prefix} /var/run/hw-management/system/fan1
          Note: path_prefix is optional and can be "/" for non-hwmon paths.
    @param _dummy: Unused (interface compatibility with update_peripheral_attr)
    """

    # If first run - set event to mask value.
    name_list = arg.get("name_list", [])
    event_reg = arg.get("_event_reg", "")
    status_reg = arg.get("_status_reg", "")
    mask = arg.get("_mask", "")

    src_path = arg.get("src_path", "")
    if not src_path:
        _src_path = arg.get("_src_path", "")
        # resolve src_path
        if "hwmon" in _src_path:
            hwmon_name = _resolve_hwmon(_src_path.split("hwmon")[0])
            if hwmon_name:
                src_path = os.path.join(_src_path, hwmon_name)
                LOGGER.info("sw_hotplug_handler: resolved src_path: {}".format(src_path))
            else:
                LOGGER.error("Failed to resolve hwmon name for: {}".format(_src_path), id="hwmon_name_empty {}".format(_src_path), repeat=0, log_repeat=1)
                return
        else:
            src_path = _src_path
            LOGGER.info("sw_hotplug_handler: resolved src_path: {}".format(src_path))
    arg["src_path"] = src_path

    if not name_list:
        LOGGER.error("sw_hotplug_handler: failed to resolve name_list", id="name_list_empty", repeat=1, log_repeat=3)
        return
    if not event_reg:
        LOGGER.error("sw_hotplug_handler: failed to resolve event_reg", id="event_reg_empty", repeat=1, log_repeat=3)
        return
    if not status_reg:
        LOGGER.error("sw_hotplug_handler: failed to resolve status_reg", id="status_reg_empty", repeat=1, log_repeat=3)
        return
    if not mask:
        LOGGER.error("sw_hotplug_handler: failed to resolve mask_reg", id="mask_reg_empty", repeat=1, log_repeat=3)
        return

    # On first run - handle all devices like all events active.
    first_run = arg.get("first_run", True)

    event_reg_name = os.path.join(src_path, event_reg)
    if first_run:
        event = int(mask, 2)
    else:
        # read event register
        try:
            with open(event_reg_name, 'r', encoding="utf-8") as f:
                event = f.read().rstrip('\n')
            event = int(event)
        except (OSError, ValueError, TypeError) as e:
            LOGGER.error("sw_hotplug_handler: failed to read event register: {}, error: {}".format(event_reg_name, e), id="failed_to_read_event_register {}".format(event_reg_name), repeat=0, log_repeat=3)
            return

    event_to_handle = event & int(mask, 2)
    if event_to_handle != 0:
        try:
            status_reg_name = os.path.join(src_path, status_reg)
            try:
                with open(status_reg_name, 'r', encoding="utf-8") as f:
                    status_byte = f.read().rstrip('\n')
                status_byte = int(status_byte)
            except (OSError, ValueError, TypeError) as e:
                LOGGER.error("sw_hotplug_handler: failed to read status register: {}, error: {}".format(status_reg_name, e), id="failed_to_read_status_register {}".format(status_reg_name), repeat=0, log_repeat=3)
                return

            # ACK: clear all masked snapshotted event bits immediately after reading.
            # The hardware register is now free to accumulate new events throughout
            # all subsequent processing; any new arrival re-sets its bit and is
            # caught on the next poll instead of being lost to a stale-snapshot write.
            # Re-reading current register state preserves bits that arrived in the
            # narrow window between the snapshot read above and this write.
            with open(event_reg_name, 'r', encoding="utf-8") as f:
                current_event = int(f.read().rstrip('\n'))
            with open(event_reg_name, 'w', encoding="utf-8") as f:
                LOGGER.info("sw_hotplug_handler: clearing masked event bits: 0x{:x}".format(event_to_handle))
                f.write(str(current_event & ~event_to_handle) + '\n')           
        except (OSError, ValueError, TypeError) as e:
            LOGGER.error("sw_hotplug_handler: failed to clear event register: {}, error: {}".format(event_reg_name, e),
                         id="failed_to_clear_event_register {}".format(event_reg_name), repeat=0, log_repeat=3)
            return

    if not "devices_state" in arg:
        arg["devices_state"] = {}
    devices_state = arg["devices_state"]

    # if event_to_handle 0 - nothing to do
    if event_to_handle != 0:
        # Go over active masked event bits and run hotplug event for each device.
        # Mask string is written MSB-first; LSB (rightmost bit) maps to device[0].
        for i in range(len(mask)):
            first_run = False
            if (event_to_handle & (1 << i)) == 0:
                continue

            LOGGER.info("sw_hotplug_handler: event_to_handle: {} status_byte: {}".format(event_to_handle, status_byte))
            # Extract status bit (1/0) from status register 1 - present, 0 - not present
            status = 1 if (status_byte & (1 << i)) != 0 else 0
            LOGGER.info("sw_hotplug_handler: status[{}]: {}".format(i, status))
            # init dev state if not exists (only first run)
            if i >= len(name_list):
                break
            name = name_list[i]
            if name not in devices_state:
                dev = _init_hotplug_dev_state(arg, name)
                if not dev:
                    LOGGER.error("sw_hotplug_handler: failed to init dev state for: {}".format(name))
                    continue
                devices_state[name] = dev
            else:
                dev = devices_state[name]
            dev_status = dev.get("status", None)
            LOGGER.info("sw_hotplug_handler: dev_status: {}, status: {}".format(dev_status, status))

            # handle status change
            if dev_status == status:
                # status not changed but event is set. It means we had fast insetrt/remove during the poll.
                if status == 0:
                    # dev was inserted and removed fast
                    LOGGER.info("sw_hotplug_handler: dev was inserted and removed fast - sending hotplug event with status: 0")
                    _send_hotplug_event(arg, dev, 0)
                else:
                    # dev was removed and inserted fast
                    # Start re-insert process
                    LOGGER.info("sw_hotplug_handler: dev was removed and inserted fast - sending hotplug event with status: 0")
                    _send_hotplug_event(arg, dev, 0)
                    LOGGER.info("sw_hotplug_handler: dev was removed and inserted fast - sending hotplug event with status: 1")
                    _send_hotplug_event(arg, dev, 1)
            else:
                # status changed
                LOGGER.info("sw_hotplug_handler: status changed - sending hotplug event with status: {}".format(status))
                _send_hotplug_event(arg, dev, status)
        else:
            first_run = False

        arg["first_run"] = first_run

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
    ts = current_milli_time() // 1000
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
            attr_prop["hwmon"] = _resolve_hwmon(path)
        except (OSError, IndexError):
            attr_prop["hwmon"] = ""

def write_module_counter(product_sku):
    """
    @summary: Write module_counter configuration file during initialization

    Gets module_count from centralized platform configuration and writes it to
    /var/run/hw-management/config/module_counter for use by other services.
    This is done in peripheral_updater to ensure availability even if
    thermal_updater is disabled by the customer.

    If product_sku does not match any entry in PLATFORM_CONFIG, the file is not
    created or modified (unsupported platform — leave existing content intact).

    @param product_sku: Platform SKU identifier to load correct config
    """
    if not get_platform_config(product_sku):
        LOGGER.notice(
            "hw-management-peripheral-updater: module_counter skipped (platform not in config)"
        )
        return

    # Get module count from centralized platform configuration
    # This is the SINGLE SOURCE OF TRUTH for module counts
    module_count = get_module_count(product_sku)

    # Write module_counter (including 0) for supported platforms only
    try:
        with open("/var/run/hw-management/config/module_counter", 'w', encoding="utf-8") as f:
            f.write("{}\n".format(module_count))
        if module_count > 0:
            LOGGER.notice("hw-management-peripheral-updater: module_counter initialized ({})".format(module_count))
        else:
            LOGGER.notice("hw-management-peripheral-updater: module_counter initialized (0 - no modules on this platform)")
    except OSError as e:
        LOGGER.warning("Failed to write module_counter: {}".format(e))


def handle_shutdown(sig, _frame):
    """
    @summary: Handle application signal
    @param sig: Signal number
    @param _frame: Unused frame
    """
    global _sig_condition_name
    try:
        _sig_condition_name = signal.Signals(sig).name
    except (ValueError, AttributeError):
        _sig_condition_name = str(sig)

    EXIT.set()

# ----------------------------------------------------------------------


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
                            default=CONST.LOG_FILE)

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
    LOGGER.set_log_rotation_size(file_size=CONST.LOG_ROTATION_SIZE, file_count=CONST.LOG_ROTATION_COUNT)

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

    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGHUP, handle_shutdown)
    EXIT.clear()

    LOGGER.notice("hw-management-peripheral-updater: start main loop")
    while not EXIT.is_set():
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

        exit_wait(EXIT, 1, chunk_sec=0.2)

    LOGGER.notice("hw-management-peripheral-updater: stopped main loop ({})".format(_sig_condition_name))
    return


if __name__ == '__main__':
    main()
