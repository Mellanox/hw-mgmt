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
    set, it reports whether the host is SONiC (is_sonic_os).
    The shell caller also requires a BMC/host contract file before it treats
    usb0 as NOS-owned.

    is_redfish_disabled returns (0, "True") or (0, "False"). If the database
    has no value, it is True when the host is SONiC (SONIC_VERSION_FILE exists,
    the "show" executable is on PATH, and a running container image contains
    docker-sonic-mgmt-framework). Otherwise the default is False, so Redfish
    login and BMC sensor polling stay enabled.

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
        # -l/--log_file is hidden; it must appear before --get/--set
        # stdout is the result string; exit code is the handler retcode
"""

import argparse
import fcntl
import os
import shutil
import stat
import sys
import json
import tempfile
import threading
from datetime import datetime
from hw_management_lib import str2bool, run_shell_cmd, get_nested_value

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
SONIC_MGMT_FRAMEWORK_IMAGE = "docker-sonic-mgmt-framework"
# Persistent feature flags.
HW_MANAGEMENT_DB_FILE = "/etc/hw-management/hw_management_features.json"
HW_MANAGEMENT_DB = {}
# Same path and line format as hw-management-helpers.sh print_function_call.
TRACE_LOG_FILE = "/var/log/hw-mgmt.trace.log"
# Serializes threads in this process. The flock on <db>.lock serializes processes.
_DB_LOCK = threading.RLock()
_DB_LOCK_STATE = threading.local()

"""
@summary: hw-mgmt DB structure example:
{
    "feature_name1": {
        "value": True,
        "timestamp": "2026_10_23_12-00-00.000",
        "user": "root",
    },
    "feature_name2": {
        "value": "test",
        "timestamp": 026_10_23_12-00-00.000,
        "user": "root",
    },
    "feature_name3": {
        "value": 123,
        "timestamp": 026_10_23_12-00-00.000,
        "user": "root",
    },
    "feature_name4": {
        "value": {"key1": "value1", "key2": "value2"},
        "timestamp": 026_10_23_12-00-00.000,
        "user": "root",
    },
}
"""


class _DbLock(object):
    """
    @summary: In-process lock plus an exclusive flock on <db_file>.lock.
              A nested enter on this thread reuses the flock already held.
    """

    def __init__(self, db_file):
        self._db_file = db_file
        self._acquired = False

    def __enter__(self):
        _DB_LOCK.acquire()
        try:
            depth = getattr(_DB_LOCK_STATE, "depth", 0)
            if depth == 0:
                fd = os.open(
                    self._db_file + ".lock", os.O_CREAT | os.O_RDONLY, 0o644)
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX)
                except OSError:
                    os.close(fd)
                    raise
                _DB_LOCK_STATE.fd = fd
            _DB_LOCK_STATE.depth = depth + 1
            self._acquired = True
            return self
        except BaseException:
            _DB_LOCK.release()
            raise

    def __exit__(self, exc_type, exc, tb):
        try:
            if self._acquired:
                _DB_LOCK_STATE.depth -= 1
                if _DB_LOCK_STATE.depth == 0:
                    fd = _DB_LOCK_STATE.fd
                    _DB_LOCK_STATE.fd = None
                    try:
                        fcntl.flock(fd, fcntl.LOCK_UN)
                    finally:
                        os.close(fd)
        finally:
            _DB_LOCK.release()
        return False


def print_log(function_name, *args):
    """
    @summary: Append one function-call trace line to TRACE_LOG_FILE.
              Format matches hw-management-helpers.sh print_function_call:
              script(pid) [YYYY_mm_dd_HH-MM-SS.mmm]: function_name argument
              The file is opened, written, and closed. No FD is kept.
    @param function_name: Name of the calling function.
    @param args: Variable length argument list.
    """
    script_name = os.path.basename(__file__)
    pid = os.getpid()
    ts = datetime.now().strftime("%Y_%m_%d_%H-%M-%S.%f")[:-3]
    line = "%s(%s) [%s]: %s %s\n" % (script_name, pid, ts, function_name, " ".join(args))
    try:
        with open(TRACE_LOG_FILE, "a") as log_f:
            log_f.write(line)
    except (OSError, IOError):
        pass


def is_sonic_os():
    """
    @summary: Detect whether this host is running SONiC.
    @return: True or False. True when SONIC_VERSION_FILE exists, "show" is on PATH, and a
             running container image contains docker-sonic-mgmt-framework.
    """
    if not os.path.isfile(SONIC_VERSION_FILE):
        print_log("is_sonic_os", f"SONIC_VERSION_FILE not found: {SONIC_VERSION_FILE}")
        return False

    if not shutil.which("show"):
        print_log("is_sonic_os", "show not found on PATH")
        return False

    # Temporarily comment out docker check for now.
    # ret, images = run_shell_cmd(
    #    "docker", ["ps", "--format", "{{.Image}}"], timeout=5)
    # if ret != 0 or SONIC_MGMT_FRAMEWORK_IMAGE not in (images or ""):
    #    print_log("is_sonic_os", "docker-sonic-mgmt-framework not running")
    #    return False
    return True


def is_redfish_disabled(*_args):
    """
    @summary: Check whether Redfish is disabled on this host.
    @param _args: Optional arguments. Unused by this check.
    @return: (0, "True") or (0, "False"). Defaults to True on SONiC hosts.
    """
    enabled = hw_management_db_get("is_redfish_disabled")
    print_log("is_redfish_disabled", f"hw_management_db_get: {enabled}")
    # missing value in db.
    if enabled is None:
        enabled = is_sonic_os()
        # set the value to the default value based on OS version
        # At this moment, only Sonic requires to disable Redfish
        hw_management_db_set("is_redfish_disabled", enabled, user="def")
        print_log("is_redfish_disabled", f"is_sonic_os: {enabled}")

    print_log("is_redfish_disabled", f"enabled: {enabled}")
    val = str2bool(enabled)
    if val is None:
        return 1, "invalid value"
    return 0, str(val)


def is_redfish_disabled_set(*_args):
    """
    @summary: Set whether Redfish is disabled on this host.
    @param _args: Optional arguments. First argument is the value to set.
    @return: (retcode, message). 0 and "" on success. Non-zero and an
             error string on failure.
    """
    if len(_args) != 1:
        print_log("is_redfish_disabled_set", f"expected exactly one value, got {len(_args)}")
        return 1, "expected exactly one value"

    val = str2bool(_args[0])
    if val is None:
        print_log("is_redfish_disabled_set", f"invalid value: {_args[0]}")
        return 1, "invalid value"
    print_log("is_redfish_disabled_set", f"setting to: {val}")
    ret = hw_management_db_set("is_redfish_disabled", val, user="sw")
    return ret, ""


def is_usb0_managed_by_nos(*_args):
    """
    @summary: Check whether USB0 is managed by the NOS.
    @param _args: Optional arguments. Unused by this check.
    @return: (0, "True") when USB0 is NOS-managed, (0, "False") otherwise.
             Uses the database override if present, else is_sonic_os().
    """
    enabled = hw_management_db_get("is_usb0_managed_by_nos")
    print_log("is_usb0_managed_by_nos", f"hw_management_db_get: {enabled}")
    if enabled is None:
        # set the value to the default value based on OS version
        # At this moment, only Sonic requires to manage USB0 by NOS
        enabled = is_sonic_os()
        hw_management_db_set("is_usb0_managed_by_nos", enabled, user="def")
        print_log("is_usb0_managed_by_nos", f"is_sonic_os: {enabled}")
    print_log("is_usb0_managed_by_nos", f"enabled: {enabled}")
    val = str2bool(enabled)
    if val is None:
        return 1, "invalid value"
    return 0, str(val)


def is_usb0_managed_by_nos_set(*_args):
    """
    @summary: Set whether USB0 is managed by NOS on this host.
    @param _args: Optional arguments. First argument is the value to set.
    @return: (retcode, message). 0 and "" on success. Non-zero and an
             error string on failure.
    """
    if len(_args) != 1:
        print_log("is_usb0_managed_by_nos_set", f"expected exactly one value, got {len(_args)}")
        return 1, "expected exactly one value"

    val = str2bool(_args[0])
    if val is None:
        print_log("is_usb0_managed_by_nos_set", f"invalid value: {_args[0]}")
        return 1, "invalid value"
    print_log("is_usb0_managed_by_nos_set", f"setting to: {val}")
    hw_management_db_set("is_usb0_managed_by_nos", val, user="sw")
    return 0, ""


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
          The database is written when the handler success.
          Each caller loads its own snapshot. The last caller
          update_hw_management_db() writes that snapshot back, in this
          process or another, and overwrites keys it already contained.
          A key added by someone else after this snapshot was loaded is kept.
    @param action: Command key in COMMANDS ("get" or "set").
    @param feature_name: Feature key under that action.
    @param args: Optional arguments forwarded to the handler.
    @return: (retcode, result string). retcode 0 is success. On error,
             retcode is non-zero and the string is an error message.
    """
    global HW_MANAGEMENT_DB
    extra = " ".join(str(a) for a in args)
    print_log(
        "feature_request",
        " ".join((str(action), str(feature_name), extra)).strip())

    try:
        command = COMMANDS.get(action)
        if command is None:
            print_log("feature_request", f"command: {action} is None")
            return 1, f"Command unknown: {action}"
        feature = _action_features(command).get(feature_name)
        if feature is None:
            print_log("feature_request", f"feature: {feature_name} is None")
            return 1, f"Feature unknown: {feature_name}"
        handler_name = feature["handler"]
        print_log("feature_request", f"feature_name: {feature_name} handler_name: {handler_name}")
        handler = globals().get(handler_name)
        if handler is None:
            print_log("feature_request", f"handler: {handler_name} is None")
            return 1, f"Handler unknown: {handler_name}"

        HW_MANAGEMENT_DB = load_hw_management_db(HW_MANAGEMENT_DB_FILE)
        if HW_MANAGEMENT_DB is None:
            print_log("feature_request", f"Cannot load DB file: {HW_MANAGEMENT_DB_FILE}")
            return 1, f"Cannot load DB file: {HW_MANAGEMENT_DB_FILE}"

        result, text = handler(*args)
        if result == 0:
            result = update_hw_management_db(HW_MANAGEMENT_DB_FILE, HW_MANAGEMENT_DB)
            if result != 0:
                print_log("feature_request", f"update_hw_management_db failed: {HW_MANAGEMENT_DB_FILE}")
                return 1, "update_hw_management_db failed"
        return result, text
    except Exception as e:
        print_log("feature_request", f"Exception: {e}")
        return 1, f"Exception: {e}"


def print_feature_help(action):
    """
    @summary: Print the second-level options registered for an action.
    @param action: Command key in COMMANDS ("get" or "set").
    @return: 0
    """
    features = _action_features(COMMANDS[action])
    print(f"Available --{action} options:")
    if not features:
        print("  (none)")
        return 0
    width = max(len(name) for name in features)
    for name in sorted(features):
        print(f"  {name:<{width}}  {features[name].get('help', '')}")
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


def hw_management_db_get(feature_name):
    """
    @summary: Return the nested value at path from the hw-management database, or None if a key is missing.
    @param feature_name: The feature name to get.
    @return: The value at path, or None.
    """
    db_root = HW_MANAGEMENT_DB
    entry = db_root.get(feature_name)
    if not isinstance(entry, dict):
        return None
    return entry.get("value", None)


def hw_management_db_set(feature_name, value, user="def"):
    """
    @summary: Set or update record in the hw-management database.
              If record does not exist, create it with value, timestamp, and user.
              If record exists:
                update record timestamp if user or value changed.
                do not update if value or user not changed
    @param feature_name: The feature name to set.
    @param value: The value to set.
    @param user: The user who is setting the value.
    @return: 0
    """
    db_root = HW_MANAGEMENT_DB
    entry = db_root.get(feature_name)
    new_entry = {
        "value": value,
        "timestamp": datetime.now().strftime("%Y_%m_%d_%H-%M-%S.%f")[:-3],
        "user": user,
        "updated": True,
    }
    if not isinstance(entry, dict):
        entry = None
    if entry is None:
        db_root[feature_name] = new_entry
    elif entry.get("user", None) != user or entry.get("value", None) != value:
        db_root[feature_name] = new_entry
    return 0


def _save_hw_management_db(db_file, db_dict):
    """
    @summary: Write the database dict to db_file.
              Writes a unique temp file in the same directory, then replaces
              db_file so an interrupted write cannot truncate stored settings.
              New files are 0644; an existing file keeps its mode.
    @param db_file: Destination JSON path.
    @param db_dict: Database dict to save.
    @return: 0 on success, not 0 on failure.
    """
    result = 0
    tmp_file_path = None
    db_dir = os.path.dirname(db_file)
    try:
        os.makedirs(db_dir, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            dir=db_dir, mode="w", delete=False, encoding="utf-8"
        ) as tf:
            tmp_file_path = tf.name
            payload = dict(db_dict)
            json.dump(payload, tf)
            tf.write("\n")
            tf.flush()
            os.fsync(tf.fileno())
        if os.path.exists(db_file):
            mode = stat.S_IMODE(os.stat(db_file).st_mode)
        else:
            mode = 0o644
        os.chmod(tmp_file_path, mode)
        os.replace(tmp_file_path, db_file)
        tmp_file_path = None
        result = 0
    except OSError:
        print_log("_save_hw_management_db", "OSError")
        result = 1
    finally:
        if tmp_file_path:
            try:
                os.unlink(tmp_file_path)
            except OSError:
                print_log("_save_hw_management_db", "unlink failed: %s" % tmp_file_path)
                result = 1
    print_log("_save_hw_management_db", f"result: {result}")
    return result


def update_hw_management_db(db_file, db_dict):
    """
    @summary: Update the database dict.
        1. Acquire the in-process lock and an exclusive flock on <db_file>.lock
        2. Load DB from file
        3. Update DB with new(updated) fields from db_dict. Replace existing fields.
        4. Save DB to file
        5. Release the flock and the in-process lock
    @param db_file: Database file path.
    @param db_dict: Database dict to update.
    @return: 0 on success, not 0 on failure
    """
    db_modified = False
    os.makedirs(os.path.dirname(db_file), exist_ok=True)
    db_lock = _DbLock(db_file)
    try:
        db_lock.__enter__()
    except OSError:
        print_log("update_hw_management_db", f"DB lock failed: {db_file}")
        return 1
    try:
        loaded_db_dict = load_hw_management_db(db_file)
        if loaded_db_dict is None:
            print_log("update_hw_management_db", f"Cannot load DB file: {db_file}")
            return 1

        for feature_name, feature_data in db_dict.items():
            if not isinstance(feature_data, dict) or not feature_data.get("updated"):
                continue
            loaded_db_dict[feature_name] = {
                key: val for key, val in feature_data.items() if key != "updated"
            }
            db_modified = True
        if db_modified:
            result = _save_hw_management_db(db_file, loaded_db_dict)
            if result != 0:
                print_log("update_hw_management_db", f"_save_hw_management_db failed: {db_file}")
                return result
        return 0
    finally:
        db_lock.__exit__(None, None, None)


def load_hw_management_db(db_file):
    """
    @summary: Load the hw-management database from db_file.
    @param db_file: Database file path.
    @return: Dict - in case json load from file was successful
             empty dict {} - if file is absent
             None - if exists but cannot be read or is not a JSON object
    """
    if not os.path.exists(db_file):
        print_log("load_hw_management_db", "file does not exist: %s" % db_file)
        return {}
    try:
        with open(db_file, "r") as handle:
            loaded = json.load(handle)
    except (ValueError, OSError, IOError):
        print_log("load_hw_management_db", "json.load failed: %s" % db_file)
        return None
    if not isinstance(loaded, dict):
        print_log("load_hw_management_db", "loaded is not a dict: %s" % db_file)
        return None
    return loaded


def main():
    """
    @summary: CLI entry point.

    Flags and handlers come from COMMANDS. Exactly one action is required.
    --get <feature name> <args> reads a feature.
    --set <feature name> <args> writes a feature.

    Prints the handler result string and exits with the handler retcode.
    -l/--log_file FILE writes the trace log to FILE instead of TRACE_LOG_FILE.
    The option is hidden from --help and must appear before --get/--set.
    """
    global TRACE_LOG_FILE
    parser = argparse.ArgumentParser(
        description="Host feature get/set for hw-management.")
    parser.add_argument(
        "-l", "--log_file",
        dest="log_file",
        metavar="FILE",
        default=TRACE_LOG_FILE,
        help=argparse.SUPPRESS)
    action_group = parser.add_mutually_exclusive_group(required=True)
    for name in COMMANDS:
        action_group.add_argument(
            f"--{name}",
            nargs="*",
            metavar=("FEATURE", "ARG"),
            help=COMMANDS[name]["help"])
    args = parser.parse_args()
    TRACE_LOG_FILE = args.log_file

    ret = 2
    for name in COMMANDS:
        values = getattr(args, name)
        if values is not None:
            ret = run_action(name, values)
    return ret


if __name__ == "__main__":
    sys.exit(main())
