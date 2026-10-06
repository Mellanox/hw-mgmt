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
    returns (1, error string). The command line takes --get or --set; with
    no feature name it lists the names registered for that action.

    is_usb0_managed_by_nos reads the database override first. If none is
    set, it reports whether /etc/sonic/sonic_version.yml exists.
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
        hw_management_feature.py -l /tmp/hw-mgmt.trace.log --get is_redfish_disabled
        # -l/--log must appear before --get/--set
        # stdout is the result string; exit code is the handler retcode
"""

import argparse
import datetime
import fcntl
import os
import re
import stat
import sys
import json
import tempfile
import threading
from hw_management_lib import str2bool, run_shell_cmd

# Action -> metadata and feature name -> handler function name and help text.
# CLI flags are built from this tree.
# Extra CLI arguments are forwarded to the selected function.
# "help" is action metadata; every other key is a feature.
COMMANDS = {
    "get": {
        "help": "Read a feature. First value is the feature name; "
                "remaining values are optional arguments. "
                "With no feature name, print the available options",
        "is_usb0_managed_by_nos": {
            "handler": "is_usb0_managed_by_nos",
            "help": "Report whether USB0 is managed by the NOS",
        },
        "is_redfish_disabled": {
            "handler": "is_redfish_disabled",
            "help": "Report whether Redfish is disabled on this host",
        },
    },
    "set": {
        "help": "Set a feature. First value is the feature name; "
                "the next value is a boolean. "
                "With no feature name, print the available options",
        "is_redfish_disabled": {
            "handler": "is_redfish_disabled_set",
            "help": "Set whether Redfish is disabled. Value is a boolean",
        },
        "is_usb0_managed_by_nos": {
            "handler": "is_usb0_managed_by_nos_set",
            "help": "Set whether USB0 is managed by the NOS. Value is a boolean",
        },
    },
}

# Keys in an action dict that are not feature names.
_COMMAND_META_KEYS = ("help",)

# SONiC version manifest. Present only on SONiC hosts.
SONIC_VERSION_FILE = "/etc/sonic/sonic_version.yml"
# Version lines from "show version". The version strings themselves vary.
SONIC_SHOW_VERSION_TIMEOUT = 5
SONIC_SOFTWARE_VERSION_RE = re.compile(r"^SONiC Software Version:\s+\S+")
SONIC_OS_VERSION_RE = re.compile(r"^SONiC OS Version:\s+\S+")
# Persistent feature flags.
HW_MANAGEMENT_DB_FILE = "/etc/hw-management/hw_management_features.json"
HW_MANAGEMENT_DB = {}
# Serializes in-process threads. flock does not block a second thread in this process.
_DB_THREAD_LOCK = threading.Lock()
# Same path and line format as hw-management-helpers.sh print_function_call.
TRACE_LOG_FILE = "/var/log/hw-mgmt.trace.log"


def print_log(function_name, argument=""):
    """
    @summary: Append one function-call trace line to TRACE_LOG_FILE.
              Format matches hw-management-helpers.sh print_function_call:
              script(pid) [YYYY_mm_dd_HH-MM-SS.mmm]: function_name argument
              The file is opened, written, and closed. No FD is kept.
    @param function_name: Name of the calling function.
    @param argument: Optional argument string.
    """
    script_name = os.path.basename(__file__)
    pid = os.getpid()
    now = datetime.datetime.now()
    ts = now.strftime("%Y_%m_%d_%H-%M-%S.") + "%03d" % (now.microsecond // 1000)
    line = "%s(%s) [%s]: %s %s\n" % (
        script_name, pid, ts, function_name, argument)
    try:
        with open(TRACE_LOG_FILE, "a") as log_f:
            log_f.write(line)
    except (OSError, IOError):
        pass


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
    print_log("is_redfish_disabled", "get_hw_management_db: %s" % enabled)
    if enabled is None:
        enabled = is_sonic_os()
        print_log("is_redfish_disabled", "is_sonic_os: %s" % enabled)
    print_log("is_redfish_disabled", "enabled: %s" % enabled)
    return 0, str(str2bool(enabled))


def is_redfish_disabled_set(*_args):
    """
    @summary: Set whether Redfish is disabled on this host.
    @param _args: Optional arguments. First argument is the value to set.
    @return: (retcode, message). 0 and "" on success. Non-zero and an
             error string on failure.
    """
    if not _args:
        print_log("is_redfish_disabled_set", "no args")
        return 1, "missing value"

    val = str2bool(_args[0])
    if val is None:
        print_log("is_redfish_disabled_set", "invalid value: %s" % _args[0])
        return 1, "invalid value"
    print_log("is_redfish_disabled_set", "setting to: %s" % val)
    ret = set_hw_management_db(["is_redfish_disabled", "enabled"], val)
    if save_hw_management_db(HW_MANAGEMENT_DB_FILE) != 0:
        print_log("is_redfish_disabled_set", "save_hw_management_db failed")
        return 1, "save_hw_management_db failed"
    print_log("is_redfish_disabled_set", "save_hw_management_db success")
    return ret, ""


def is_usb0_managed_by_nos(*_args):
    """
    @summary: Check whether USB0 is managed by the NOS.
    @param _args: Optional arguments. Unused by this check.
    @return: (0, "True") when USB0 is NOS-managed, (0, "False") otherwise.
             Uses the database override if present, else whether
             SONIC_VERSION_FILE exists.
    """
    enabled = get_hw_management_db(["is_usb0_managed_by_nos", "enabled"])
    print_log("is_usb0_managed_by_nos", "get_hw_management_db: %s" % enabled)
    if enabled is None:
        enabled = os.path.isfile(SONIC_VERSION_FILE)
        print_log("is_usb0_managed_by_nos", "os.path.isfile: %s" % enabled)
    print_log("is_usb0_managed_by_nos", "enabled: %s" % enabled)
    return 0, str(str2bool(enabled))


def is_usb0_managed_by_nos_set(*_args):
    """
    @summary: Set whether USB0 is managed by NOS on this host.
    @param _args: Optional arguments. First argument is the value to set.
    @return: (retcode, message). 0 and "" on success. Non-zero and an
             error string on failure.
    """
    if not _args:
        print_log("is_usb0_managed_by_nos_set", "no args")
        return 1, "missing value"
    val = str2bool(_args[0])
    if val is None:
        print_log("is_usb0_managed_by_nos_set", "invalid value: %s" % _args[0])
        return 1, "invalid value"
    print_log("is_usb0_managed_by_nos_set", "setting to: %s" % val)
    ret = set_hw_management_db(["is_usb0_managed_by_nos", "enabled"], val)
    if save_hw_management_db(HW_MANAGEMENT_DB_FILE) != 0:
        print_log("is_usb0_managed_by_nos_set", "save_hw_management_db failed")
        return 1, "save_hw_management_db failed"
    print_log("is_usb0_managed_by_nos_set", "save_hw_management_db success")
    return ret, ""


def _action_features(command):
    """
    @summary: Feature name -> spec for one action, excluding metadata keys.
    @param command: One COMMANDS action dict.
    @return: Dict of feature names to handler/help specs.
    """
    return {
        name: spec
        for name, spec in command.items()
        if name not in _COMMAND_META_KEYS and isinstance(spec, dict)
    }


def feature_request(action, feature_name, *args):
    """
    @summary: Call the function registered for an action and feature name.
    @param action: Command key in COMMANDS ("get" or "set").
    @param feature_name: Feature key under that action.
    @param args: Optional arguments forwarded to the handler.
    @return: (retcode, result string). retcode 0 is success. On error,
             retcode is non-zero and the string is an error message.

    Get and set both fail if the database file exists but cannot be read
    or is not a JSON object. A missing file is not an error.

    An exclusive flock on db_file.lock is held for load, handler, and save.
    In-process threads take _DB_THREAD_LOCK first; flock does not block a
    second thread in the same process.
    """
    extra = " ".join(str(a) for a in args)
    print_log(
        "feature_request",
        " ".join((str(action), str(feature_name), extra)).strip())
    lock_fd = None
    _DB_THREAD_LOCK.acquire()
    try:
        try:
            lock_path = HW_MANAGEMENT_DB_FILE + ".lock"
            db_dir = os.path.dirname(lock_path)
            if db_dir:
                os.makedirs(db_dir, exist_ok=True)
            lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
        except (OSError, IOError):
            print_log("feature_request", "lock failed: %s" % HW_MANAGEMENT_DB_FILE)
            return 1, "DB lock failed"
        ret = load_hw_management_db(HW_MANAGEMENT_DB_FILE)
        if ret != 0:
            print_log("feature_request", "load_hw_management_db: %s" % HW_MANAGEMENT_DB_FILE)
            return 1, "DB load failed"
        command = COMMANDS.get(action)
        if command is None:
            print_log("feature_request", "command: %s is None" % action)
            return 1, "Command unknown: %s" % action
        feature = _action_features(command).get(feature_name)
        if feature is None:
            print_log("feature_request", "feature: %s is None" % feature_name)
            return 1, "Feature unknown: %s" % feature_name
        handler_name = feature["handler"]
        print_log("feature_request", "feature_name: %s handler_name: %s" % (feature_name, handler_name))
        handler = globals().get(handler_name)
        if handler is None:
            print_log("feature_request", "handler: %s is None" % handler_name)
            return 1, "Handler unknown: %s" % handler_name
        return handler(*args)
    finally:
        if lock_fd is not None:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            except (OSError, IOError):
                pass
            try:
                os.close(lock_fd)
            except (OSError, IOError):
                pass
        try:
            _DB_THREAD_LOCK.release()
        except RuntimeError:
            pass


def print_feature_help(action):
    """
    @summary: Print the second-level options registered for an action.
    @param action: Command key in COMMANDS ("get" or "set").
    @return: 0
    """
    features = _action_features(COMMANDS[action])
    print("Available --%s options:" % action)
    if not features:
        print("  (none)")
        return 0
    width = max(len(name) for name in features)
    for name in sorted(features):
        print("  %-*s  %s" % (width, name, features[name].get("help", "")))
    return 0


def run_action(action, values):
    """
    @summary: Run one command from COMMANDS.
    @param action: Command key in COMMANDS ("get" or "set").
    @param values: Feature name followed by optional arguments. Empty prints help.
    @return: Shell exit code.
    """
    if not values:
        return print_feature_help(action)
    ret, text = feature_request(action, values[0], *values[1:])
    if ret != 0:
        if text:
            print(text, file=sys.stderr)
        return ret
    if text:
        print(text)
    return ret


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
              Writes a unique temp file in the same directory, then replaces
              db_file so an interrupted write cannot truncate stored settings.
              New files are 0644; an existing file keeps its mode.
    @param db_file: Destination JSON path.
    @return: 0 on success, 1 on I/O error. An empty database is left unchanged.
    """
    if not HW_MANAGEMENT_DB:
        print_log("save_hw_management_db", "HW_MANAGEMENT_DB is empty")
        return 0
    db_dir = os.path.dirname(db_file)
    tmp_dir = db_dir if db_dir else "."
    print_log("save_hw_management_db", "db_dir: %s" % db_dir)
    fd = None
    tmp = None
    try:
        if db_dir:
            os.makedirs(db_dir, exist_ok=True)
        print_log("save_hw_management_db", "db_dir exists: %s" % db_dir)
        fd, tmp = tempfile.mkstemp(prefix=".tmp_", dir=tmp_dir)
        print_log("save_hw_management_db", "tmp: %s" % tmp)
        with os.fdopen(fd, "w") as f:
            fd = None
            json.dump(HW_MANAGEMENT_DB, f)
            f.write("\n")
        print_log("save_hw_management_db", "json.dump success")
        prev_mode = 0o644
        try:
            prev_mode = stat.S_IMODE(os.stat(db_file).st_mode)
        except (OSError, IOError):
            pass
        os.chmod(tmp, prev_mode)
        os.replace(tmp, db_file)
        tmp = None
    except (OSError, IOError):
        print_log("save_hw_management_db", "OSError or IOError")
        if fd is not None:
            try:
                os.close(fd)
            except (OSError, IOError):
                pass
        if tmp:
            try:
                os.unlink(tmp)
            except (OSError, IOError):
                pass
        return 1
    print_log("save_hw_management_db", "save_hw_management_db success")
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
        print_log("load_hw_management_db", "file does not exist: %s" % db_file)
        return 0
    try:
        with open(db_file, 'r') as f:
            loaded = json.load(f)
    except (ValueError, OSError, IOError):
        print_log("load_hw_management_db", "json.load failed: %s" % db_file)
        return 1
    if not isinstance(loaded, dict):
        print_log("load_hw_management_db", "loaded is not a dict: %s" % db_file)
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
    -l FILE writes the trace log to FILE instead of TRACE_LOG_FILE.
    -l/--log must appear before --get/--set.
    """
    global TRACE_LOG_FILE
    parser = argparse.ArgumentParser(
        description="Host feature get/set for hw-management. "
                    "-l/--log must appear before --get/--set.")
    parser.add_argument(
        "-l", "--log",
        dest="log_file",
        metavar="FILE",
        default=TRACE_LOG_FILE,
        help="Trace log file (default: %s). "
             "Must appear before --get/--set" % TRACE_LOG_FILE)
    action_group = parser.add_mutually_exclusive_group(required=True)
    for name in COMMANDS:
        action_group.add_argument(
            "--%s" % name,
            nargs="*",
            metavar=("FEATURE", "ARG"),
            help=COMMANDS[name]["help"])
    args = parser.parse_args()
    TRACE_LOG_FILE = args.log_file

    for name in COMMANDS:
        values = getattr(args, name)
        if values is not None:
            return run_action(name, values)
    return 2


if __name__ == "__main__":
    sys.exit(main())
