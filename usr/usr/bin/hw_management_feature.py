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
    has no value, it is True when the host is SONiC (SONIC_VERSION_FILE exists
    and the "show" executable is on PATH). Otherwise the default is False, so
    Redfish login and BMC sensor polling stay enabled.

    feature_request holds an exclusive flock on <db file>.lock from the
    database load until the save, so concurrent processes and threads cannot
    lose each other's updates. If the lock cannot be taken within
    DB_LOCK_TIMEOUT seconds, or the lock file cannot be opened, both get and
    set fail with (1, "DB lock failed") and the database is not read or
    written. Callers must treat a non-zero get as "unknown" and pick a safe
    default.

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
import errno
import fcntl
import os
import shutil
import stat
import sys
import json
import tempfile
import time
from datetime import datetime
from hw_management_lib import str2bool

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
# Persistent feature flags.
HW_MANAGEMENT_DB_FILE = "/etc/hw-management/hw_management_features.json"
# Same path and line format as hw-management-helpers.sh print_function_call.
TRACE_LOG_FILE = "/var/log/hw-mgmt.trace.log"
# Bounded so a stuck lock holder cannot hang usb0 ifup or hw-management start.
DB_LOCK_TIMEOUT = 5.0
DB_LOCK_POLL_INTERVAL = 0.05

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
        "timestamp": "2026_10_23_12-00-00.000",
        "user": "root",
    },
    "feature_name3": {
        "value": 123,
        "timestamp": "2026_10_23_12-00-00.000",
        "user": "root",
    },
    "feature_name4": {
        "value": {"key1": "value1", "key2": "value2"},
        "timestamp": "2026_10_23_12-00-00.000",
        "user": "root",
    },
}
"""

class _DbFileLock(object):
    """
    @summary: Exclusive flock on <db_file>.lock.
              flock belongs to the open file description, so every acquire
              opens its own fd. That serializes other processes and other
              threads of this process alike.
    """

    def __init__(self, db_file_name, timeout=None):
        self._lock_file_name = db_file_name + ".lock"
        self._timeout = DB_LOCK_TIMEOUT if timeout is None else timeout
        self._fd = None

    def acquire(self):
        """
        @summary: Take the lock, waiting up to the timeout.
        @raise OSError: The lock file cannot be opened, or the timeout expired
                        (TimeoutError).
        """
        os.makedirs(os.path.dirname(self._lock_file_name), exist_ok=True)
        fd = os.open(self._lock_file_name,
                     os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
        deadline = time.monotonic() + self._timeout
        try:
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except OSError as e:
                    if e.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                        raise
                    if time.monotonic() >= deadline:
                        raise TimeoutError(
                            f"DB lock timeout: {self._lock_file_name}")
                    time.sleep(DB_LOCK_POLL_INTERVAL)
        except BaseException:
            os.close(fd)
            raise
        self._fd = fd

    def release(self):
        """
        @summary: Drop the lock. Safe to call when it is not held.
        """
        fd = self._fd
        if fd is None:
            return
        self._fd = None
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


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
    @return: True or False. True when SONIC_VERSION_FILE exists and the "show"
             executable is on PATH.
    """
    if not os.path.isfile(SONIC_VERSION_FILE):
        print_log("is_sonic_os", f"SONIC_VERSION_FILE not found: {SONIC_VERSION_FILE}")
        return False

    if not shutil.which("show"):
        print_log("is_sonic_os", "show not found on PATH")
        return False

    return True


def is_redfish_disabled(hw_mgmt_db, *_args):
    """
    @summary: Check whether Redfish is disabled on this host.
    @param hw_mgmt_db: The hw-management database.
    @param _args: Optional arguments. Unused by this check.
    @return: (0, "True") or (0, "False"). Defaults to True on SONiC hosts.
    """
    enabled = hw_management_db_get(hw_mgmt_db, "is_redfish_disabled")
    print_log("is_redfish_disabled", f"hw_management_db_get: {enabled}")
    # missing value in db.
    if enabled is None:
        # set the value to the default value based on OS version
        # At this moment, only Sonic requires to disable Redfish
        # save value in DB for future faster access
        enabled = is_sonic_os()
        hw_management_db_set(hw_mgmt_db, "is_redfish_disabled", enabled, user="def")
        print_log("is_redfish_disabled", f"is_sonic_os: {enabled}")

    print_log("is_redfish_disabled", f"enabled: {enabled}")
    val = str2bool(enabled)
    if val is None:
        return 1, "invalid value"
    return 0, str(val)


def is_redfish_disabled_set(hw_mgmt_db, *_args):
    """
    @summary: Set whether Redfish is disabled on this host.
    @param hw_mgmt_db: The hw-management database.
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
    ret = hw_management_db_set(hw_mgmt_db, "is_redfish_disabled", val, user="sw")
    return ret, ""


def is_usb0_managed_by_nos(hw_mgmt_db, *_args):
    """
    @summary: Check whether USB0 is managed by the NOS.
    @param hw_mgmt_db: The hw-management database.
    @param _args: Optional arguments. Unused by this check.
    @return: (0, "True") when USB0 is NOS-managed, (0, "False") otherwise.
             Uses the database override if present, else is_sonic_os().
    """
    enabled = hw_management_db_get(hw_mgmt_db, "is_usb0_managed_by_nos")
    print_log("is_usb0_managed_by_nos", f"hw_management_db_get: {enabled}")
    if enabled is None:
        # set the value to the default value based on OS version
        # At this moment, only Sonic requires to manage USB0 by NOS
        # save value in DB for future faster access
        enabled = is_sonic_os()
        hw_management_db_set(hw_mgmt_db, "is_usb0_managed_by_nos", enabled, user="def")
        print_log("is_usb0_managed_by_nos", f"is_sonic_os: {enabled}")
    print_log("is_usb0_managed_by_nos", f"enabled: {enabled}")
    val = str2bool(enabled)
    if val is None:
        return 1, "invalid value"
    return 0, str(val)


def is_usb0_managed_by_nos_set(hw_mgmt_db, *_args):
    """
    @summary: Set whether USB0 is managed by NOS on this host.
    @param hw_mgmt_db: The hw-management database.
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
    ret = hw_management_db_set(hw_mgmt_db, "is_usb0_managed_by_nos", val, user="sw")
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

def recover_hw_management_db():
    """
    @summary: Recover the hw-management database from corruption.
    Rename corrupted DB file to .corrupted file and create a new empty DB file.
    Only one copy of .corrupted file saved
    @return: (retcode, hw_mgmt_db). retcode 0 on success, not 0 on failure
    """
    print_log("recover_hw_management_db", f"Recovering hw-management database from corruption: {HW_MANAGEMENT_DB_FILE}")
    hw_mgmt_db = {} # create an empty database
    # rename corrupted DB file to .corrupted
    os.rename(HW_MANAGEMENT_DB_FILE, HW_MANAGEMENT_DB_FILE + ".corrupted")
    print_log("recover_hw_management_db", f"Rename corrupted DB file to: {HW_MANAGEMENT_DB_FILE}.corrupted")
    # create a new DB file
    result = _save_hw_management_db(HW_MANAGEMENT_DB_FILE, hw_mgmt_db)
    if result != 0:
        print_log("recover_hw_management_db", f"New DB file cannot be saved: {HW_MANAGEMENT_DB_FILE}")
        return 1, {}
    print_log("recover_hw_management_db", f"Create DB successfully: {HW_MANAGEMENT_DB_FILE}")
    return 0, hw_mgmt_db

def feature_request(action, feature_name, *args):
    """
    @summary: Call the function registered for an action and feature name.
          If the handler succeeds, the records it changed are merged into
          the database file.
    @param action: Command key in COMMANDS ("get" or "set").
    @param feature_name: Feature key under that action.
    @param args: Optional arguments forwarded to the handler.
    @return: (retcode, result string). retcode 0 is success. On error,
             retcode is non-zero and the string is an error message.
    """
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

        db_lock = _DbFileLock(HW_MANAGEMENT_DB_FILE)
        try:
            db_lock.acquire()
        except OSError as e:
            print_log("feature_request", f"DB lock failed: {e}")
            return 1, "DB lock failed"
        try:
            hw_mgmt_db = load_hw_management_db(HW_MANAGEMENT_DB_FILE)
            if hw_mgmt_db is None:
                print_log("feature_request", f"Cannot load DB file: {HW_MANAGEMENT_DB_FILE}.")
                return 1, "Cannot load DB file"

            result, text = handler(hw_mgmt_db, *args)
            if result == 0 and db_lock is not None:
                saved = update_hw_management_db(HW_MANAGEMENT_DB_FILE, hw_mgmt_db)
                if saved != 0 and action == "set":
                    print_log("feature_request", f"update_hw_management_db failed: {HW_MANAGEMENT_DB_FILE}")
                    return 1, "update_hw_management_db failed"
            return result, text
        finally:
            if db_lock is not None:
                db_lock.release()
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


def hw_management_db_get(hw_mgmt_db, feature_name):
    """
    @summary: Return the value of a feature from the hw-management database, or None if the feature is missing.
    @param hw_mgmt_db: The hw-management database.
    @param feature_name: The feature name to get.
    @return: The stored value, or None.
    """
    entry = hw_mgmt_db.get(feature_name)
    if not isinstance(entry, dict):
        return None
    return entry.get("value", None)


def hw_management_db_set(hw_mgmt_db, feature_name, value, user="def"):
    """
    @summary: Set or update record in the hw-management database.
              If record does not exist, create it with value, timestamp, and user.
              If record exists:
                update record timestamp if user or value changed.
                do not update if value or user not changed
    @param hw_mgmt_db: The hw-management database.
    @param feature_name: The feature name to set.
    @param value: The value to set.
    @param user: The user who is setting the value.
    @return: 0
    """
    entry = hw_mgmt_db.get(feature_name)
    new_entry = {
        "value": value,
        "timestamp": datetime.now().strftime("%Y_%m_%d_%H-%M-%S.%f")[:-3],
        "user": user,
        "updated": True,
    }
    if not isinstance(entry, dict):
        entry = None
    if entry is None:
        hw_mgmt_db[feature_name] = new_entry
    elif entry.get("user", None) != user or entry.get("value", None) != value:
        hw_mgmt_db[feature_name] = new_entry
    return 0


def _save_hw_management_db(db_file_name, hw_mgmt_db):
    """
    @summary: Write the database dict to db_file_name.
              Writes a unique temp file in the same directory, then replaces
              db_file so an interrupted write cannot truncate stored settings.
              New files are 0644; an existing file keeps its mode.
    @param db_file_name: Destination JSON path.
    @param hw_mgmt_db: Database dict to save.
    @return: 0 on success, not 0 on failure.
    """
    result = 0
    tmp_file_path = None
    db_dir = os.path.dirname(db_file_name)
    try:
        os.makedirs(db_dir, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            dir=db_dir, mode="w", delete=False, encoding="utf-8"
        ) as tf:
            tmp_file_path = tf.name
            json.dump(hw_mgmt_db, tf)
            tf.write("\n")
            tf.flush()
            os.fsync(tf.fileno())
        if os.path.exists(db_file_name):
            mode = stat.S_IMODE(os.stat(db_file_name).st_mode)
        else:
            mode = 0o644
        os.chmod(tmp_file_path, mode)
        os.replace(tmp_file_path, db_file_name)
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
                print_log("_save_hw_management_db", f"unlink failed: {tmp_file_path}")
                result = 1
    print_log("_save_hw_management_db", f"result: {result}")
    return result


def update_hw_management_db(db_file_name, hw_mgmt_db):
    """
    @summary: Update the database file from the records flagged "updated" in hw_mgmt_db.
        1. Load DB from file
        2. Update DB with new(updated) fields from hw_mgmt_db. Replace existing fields.
        3. Save DB to file
    @param db_file_name: Database file path.
    @param hw_mgmt_db: Database dict to update.
    @return: 0 on success, not 0 on failure
    """
    db_modified = False
    try:
        os.makedirs(os.path.dirname(db_file_name), exist_ok=True)
        loaded_db_dict = load_hw_management_db(db_file_name)
        if loaded_db_dict is None:
            print_log("update_hw_management_db", f"Cannot load DB file: {db_file_name}")
            return 1

        for feature_name, feature_data in hw_mgmt_db.items():
            if not isinstance(feature_data, dict) or not feature_data.get("updated"):
                continue
            loaded_db_dict[feature_name] = {
                key: val for key, val in feature_data.items() if key != "updated"
            }
            db_modified = True
        if db_modified:
            result = _save_hw_management_db(db_file_name, loaded_db_dict)
            if result != 0:
                print_log("update_hw_management_db", f"_save_hw_management_db failed: {db_file_name}")
                return result
        return 0
    except OSError:
        print_log("update_hw_management_db", f"DB update failed: {db_file_name}")
        return 1


def load_hw_management_db(db_file_name):
    """
    @summary: Load the hw-management database from db_file_name.
    @param db_file_name: Database file path.
    @return: Dict - in case json load from file was successful
             empty dict {} - if file is absent
             None - if exists but cannot be read or is not a JSON object
    """
    recover_db = False
    loaded = {}
    if not os.path.exists(db_file_name):
        print_log("load_hw_management_db", f"file does not exist: {db_file_name}")
        return {}
    try:
        with open(db_file_name, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except (OSError, IOError):
        print_log("load_hw_management_db", f"json.load failed OSError or IOError: {db_file_name}")
        return None
    except ValueError:
        print_log("load_hw_management_db", f"json.load failed ValueError: {db_file_name}")
        recover_db = True

    if not recover_db and not isinstance(loaded, dict):
        print_log("load_hw_management_db", f"loaded is not a dict: {db_file_name}")
        recover_db = True

    if recover_db:
        print_log("load_hw_management_db", f"Recovering DB file: {db_file_name}.")
        recover_result, loaded = recover_hw_management_db()
        if recover_result != 0:
            print_log("load_hw_management_db", f"Cannot recover DB file: {db_file_name}")
            return None
        print_log("load_hw_management_db", f"Recovered DB file: {db_file_name}")

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
