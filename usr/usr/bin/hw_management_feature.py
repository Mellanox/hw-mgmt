#!/usr/bin/python3
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
@summary:
    Host feature get/set used by hw-management.

    feature_request(action, feature_name) calls the handler registered in
    COMMANDS. action is "get" or "set". An unknown action or feature name
    raises ValueError. The command line takes --get or --set; with no
    feature name it lists the names registered for that action.

    is_usb0_managed_by_nos reports whether /etc/sonic/sonic_version.yml exists.
    The shell caller also requires a BMC/host contract file before it treats
    usb0 as NOS-owned.

    is_redfish_disabled returns (0, "True") or (0, "False"). If the database
    has no value, it is True when the host is SONiC (SONIC_VERSION_FILE exists
    and "show version" reports SONiC Software Version and SONiC OS Version).
    Otherwise the default is False, so Redfish login and BMC sensor polling
    stay enabled.

Usage:
    As a module:
        from hw_management_feature import feature_request
        ret, value = feature_request("get", "is_usb0_managed_by_nos")
        if ret == 0 and value == "True":
            ...

    As a command (for shell callers):
        hw_management_feature.py --get is_usb0_managed_by_nos
        hw_management_feature.py --get is_usb0_managed_by_nos aaa bbb
        hw_management_feature.py --get is_redfish_disabled
        hw_management_feature.py --set <feature name> <args>
        # stdout is the result string; exit code is the handler retcode
"""

import argparse
import os
import re
import sys
import json
from hw_management_lib import str2bool, run_shell_cmd

# Action -> feature name -> handler function name and help text.
# CLI flags are built from this tree.
# Extra CLI arguments are forwarded to the selected function.
COMMANDS = {
    "get": {
        "help": "Read a feature. First value is the feature name; "
                "remaining values are optional arguments. "
                "With no feature name, print the available options",
        "features": {
            "is_usb0_managed_by_nos": {
                "handler": "is_usb0_managed_by_nos",
                "help": "Report whether USB0 is managed by the NOS",
            },
            "is_redfish_disabled": {
                "handler": "is_redfish_disabled",
                "help": "Report whether Redfish is disabled on this host",
            },
        },
    },
    "set": {
        "help": "Set a feature. First value is the feature name; "
                "the next value is a boolean. "
                "With no feature name, print the available options",
        "features": {
            "is_redfish_disabled": {
                "handler": "is_redfish_disabled_set",
                "help": "Set whether Redfish is disabled. Value is a boolean",
            },
            "is_usb0_managed_by_nos": {
                "handler": "is_usb0_managed_by_nos_set",
                "help": "Set whether USB0 is managed by the NOS. Value is a boolean",
            },
        },
    },
}

# SONiC version manifest. Present only on SONiC hosts.
SONIC_VERSION_FILE = "/etc/sonic/sonic_version.yml"
# Version lines from "show version". The version strings themselves vary.
SONIC_SHOW_VERSION_TIMEOUT = 5
SONIC_SOFTWARE_VERSION_RE = re.compile(r"^SONiC Software Version:\s+\S+")
SONIC_OS_VERSION_RE = re.compile(r"^SONiC OS Version:\s+\S+")
# default hw-management folder
HW_MGMT_FOLDER = "/var/run/hw-management"
HW_MANAGEMENT_DB_FILE = os.path.join(HW_MGMT_FOLDER, "config", "hw_management_features.json")
HW_MANAGEMENT_DB = {}


def is_sonic_os():
    """
    @summary: Detect whether this host is running SONiC.
    @return: True when SONIC_VERSION_FILE exists and "show version" reports
             both SONiC Software Version and SONiC OS Version. False otherwise.
    """
    if not os.path.isfile(SONIC_VERSION_FILE):
        return False
    _ret, output = run_shell_cmd("show", ["version"], timeout=SONIC_SHOW_VERSION_TIMEOUT)
    has_sw_ver = False
    has_os_ver = False
    for line in (output or "").splitlines():
        line = line.strip()
        if not has_sw_ver and SONIC_SOFTWARE_VERSION_RE.match(line):
            has_sw_ver = True
        elif not has_os_ver and SONIC_OS_VERSION_RE.match(line):
            has_os_ver = True
        if has_sw_ver and has_os_ver:
            return True
    return False


def is_redfish_disabled(*_args):
    """
    @summary: Check whether Redfish is disabled on this host.
    @param _args: Optional arguments. Unused by this check.
    @return: (0, "True") or (0, "False"). Defaults to True on SONiC hosts.
    """
    enabled = get_hw_management_db(["is_redfish_disabled", "enabled"])
    if enabled is None:
        enabled = is_sonic_os()
    return 0, str(str2bool(enabled))


def is_redfish_disabled_set(*_args):
    """
    @summary: Set whether Redfish is disabled on this host.
    @param _args: Optional arguments. First argument is the value to set.
    @return: (retcode, ""). 0 on success, non-zero on error.
    """
    if not _args:
        raise ValueError("is_redfish_disabled requires a value")
    val = str2bool(_args[0])
    if val is None:
        raise ValueError("Boolean value expected")
    ret = set_hw_management_db(["is_redfish_disabled", "enabled"], val)
    if save_hw_management_db(HW_MANAGEMENT_DB_FILE) != 0:
        return 1, ""
    return ret, ""


def is_usb0_managed_by_nos(*_args):
    """
    @summary: Check whether the SONiC version manifest is present.
    @param _args: Optional arguments. Unused by this check.
    @return: (0, "True") when USB0 is NOS-managed, (0, "False") otherwise.
    """
    enabled = get_hw_management_db(["is_usb0_managed_by_nos", "enabled"])
    if enabled is None:
        enabled = os.path.isfile(SONIC_VERSION_FILE)
    return 0, str(str2bool(enabled))


def is_usb0_managed_by_nos_set(*_args):
    """
    @summary: Set whether USB0 is managed by NOS on this host.
    @param _args: Optional arguments. First argument is the value to set.
    @return: (retcode, ""). 0 on success, non-zero on error.
    """
    if not _args:
        raise ValueError("is_usb0_managed_by_nos requires a value")
    val = str2bool(_args[0])
    if val is None:
        raise ValueError("Boolean value expected")
    ret = set_hw_management_db(["is_usb0_managed_by_nos", "enabled"], val)
    if save_hw_management_db(HW_MANAGEMENT_DB_FILE) != 0:
        return 1, ""
    return ret, ""


def feature_request(action, feature_name, *args):
    """
    @summary: Call the function registered for an action and feature name.
    @param action: Command key in COMMANDS ("get" or "set").
    @param feature_name: Feature key under that action.
    @param args: Optional arguments forwarded to the handler.
    @return: (retcode, result string). retcode 0 is success.

    Get fails if the database file exists but cannot be read or is not a
    JSON object. Set still runs: load already left an empty in-memory
    database, so the setter can replace the file.
    """
    ret = load_hw_management_db(HW_MANAGEMENT_DB_FILE)
    if ret != 0 and action != "set":
        return ret, ""
    command = COMMANDS.get(action)
    if command is None:
        raise ValueError("Unknown action: %s" % action)
    feature = command["features"].get(feature_name)
    if feature is None:
        raise ValueError("Unknown feature: %s" % feature_name)
    handler_name = feature["handler"]
    handler = globals().get(handler_name)
    if handler is None:
        raise ValueError("Unknown feature: %s" % feature_name)
    return handler(*args)


def print_feature_help(parser, action):
    """
    @summary: Print the second-level options registered for an action.
    @param parser: Argument parser. Unused. Kept for the run_action call.
    @param action: Command key in COMMANDS ("get" or "set").
    @return: 0
    """
    features = COMMANDS[action]["features"]
    print("Available --%s options:" % action)
    if not features:
        print("  (none)")
        return 0
    width = max(len(name) for name in features)
    for name in sorted(features):
        print("  %-*s  %s" % (width, name, features[name].get("help", "")))
    return 0


def run_action(parser, action, values):
    """
    @summary: Run one command from COMMANDS.
    @param parser: Argument parser used for help text.
    @param action: Command key in COMMANDS ("get" or "set").
    @param values: Feature name followed by optional arguments. Empty prints help.
    @return: Shell exit code.
    """
    if not values:
        return print_feature_help(parser, action)
    try:
        ret, text = feature_request(action, values[0], *values[1:])
        if text:
            print(text)
        return ret
    except ValueError as e:
        print(e)
        return 2


def get_hw_management_db(path):
    """
    @summary: Return the nested value at path, or None if a key is missing.
    @param path: Dict keys from the outermost level to the leaf.
    @return: The value at path, or None.
    """
    dict_in = HW_MANAGEMENT_DB
    for sub_path in path:
        if not isinstance(dict_in, dict):
            return None
        dict_in = dict_in.get(sub_path, None)
        if dict_in is None:
            break
    return dict_in


def set_hw_management_db(path, val):
    """
    @summary: Set the value of a key in the hw-management database.
              create new key:val if key missing.if pat does not exist, create it.
              create key tree if not exists.
    @param path: dict_in keys organized in array.
    @param val: The value to set.
    @return: 0
    """
    dict_in = HW_MANAGEMENT_DB
    for sub_path in path[:-1]:
        child = dict_in.get(sub_path)
        if not isinstance(child, dict):
            child = {}
            dict_in[sub_path] = child
        dict_in = child
    dict_in[path[-1]] = val
    return 0


def save_hw_management_db(db_file):
    """
    @summary: Write the in-memory hw-management database to db_file.
    @param db_file: Destination JSON path.
    @return: 0 on success, 1 on I/O error. An empty database is left unchanged.
    """
    global HW_MANAGEMENT_DB
    if not HW_MANAGEMENT_DB:
        return 0
    db_dir = os.path.dirname(db_file)
    try:
        if db_dir and not os.path.isdir(db_dir):
            os.makedirs(db_dir)
        tmp = db_file + ".tmp"
        with open(tmp, 'w') as f:
            json.dump(HW_MANAGEMENT_DB, f)
            f.write("\n")
        os.rename(tmp, db_file)
    except (OSError, IOError):
        return 1
    return 0


def load_hw_management_db(db_file):
    """
    @summary: Load the hw-management database from db_file.
    @param db_file: Source JSON path.
    @return: 0 on success or when the file is missing. 1 if the file
             exists but cannot be read or is not a JSON object.
    """
    global HW_MANAGEMENT_DB
    HW_MANAGEMENT_DB = {}
    if not os.path.exists(db_file):
        return 0
    try:
        with open(db_file, 'r') as f:
            loaded = json.load(f)
    except (ValueError, OSError, IOError):
        return 1
    if not isinstance(loaded, dict):
        return 1
    HW_MANAGEMENT_DB = loaded
    return 0


def main():
    """
    @summary: CLI entry point.

    Flags and handlers come from COMMANDS. Exactly one action is required.
    --get <feature name> <args> reads a feature.
    --set <feature name> <args> writes a feature.

    Prints the handler result string and exits with the handler retcode.
    """
    parser = argparse.ArgumentParser(
        description="Host feature get/set for hw-management")
    action_group = parser.add_mutually_exclusive_group(required=True)
    for name in COMMANDS:
        action_group.add_argument(
            "--%s" % name,
            nargs="*",
            metavar=("FEATURE", "ARG"),
            help=COMMANDS[name]["help"])
    args = parser.parse_args()

    for name in COMMANDS:
        values = getattr(args, name)
        if values is not None:
            return run_action(parser, name, values)
    return 2


if __name__ == "__main__":
    sys.exit(main())
