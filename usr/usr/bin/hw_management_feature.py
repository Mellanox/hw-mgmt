#!/usr/bin/python
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

    is_redfish_disabled is a temporary stand-in (Bug 5272044). It always
    returns False, so Redfish login and BMC sensor polling stay enabled on
    every NOS until the real NOS API is available.

Usage:
    As a module:
        from hw_management_feature import feature_request
        if feature_request("get", "is_usb0_managed_by_nos"):
            ...

    As a command (for shell callers, exit code based):
        hw_management_feature.py --get is_usb0_managed_by_nos
        hw_management_feature.py --get is_usb0_managed_by_nos aaa bbb
        hw_management_feature.py --get is_redfish_disabled
        hw_management_feature.py --set <feature name> <args>
        # exit 0 when the selected check is true, 1 otherwise
"""

import argparse
import os
import sys

# SONiC version manifest. Present only on SONiC hosts.
SONIC_VERSION_FILE = "/etc/sonic/sonic_version.yml"


def is_usb0_managed_by_nos(*_args):
    """
    @summary: Check whether the SONiC version manifest is present.
    @param _args: Optional arguments. Unused by this check.
    @return: True when /etc/sonic/sonic_version.yml exists, False otherwise.
    """
    return os.path.isfile(SONIC_VERSION_FILE)


def is_redfish_disabled(*_args):
    """
    @summary: Check whether Redfish is disabled on this host.
    @param _args: Optional arguments. Unused by this check.
    @return: Always False until the NOS API is available. Bug 5272044.
    """
    return False


# Action -> feature name -> handler. CLI flags are built from this tree.
# Extra CLI arguments are forwarded to the selected function.
COMMANDS = {
    "get": {
        "help": "Read a feature. First value is the feature name; "
                "remaining values are optional arguments. "
                "With no feature name, print this help",
        "features": {
            "is_usb0_managed_by_nos": is_usb0_managed_by_nos,
            "is_redfish_disabled": is_redfish_disabled,
        },
    },
    "set": {
        "help": "Set a feature. First value is the feature name; "
                "remaining values are optional arguments. "
                "With no feature name, print this help",
        "features": {},
    },
}


def feature_request(action, feature_name, *args):
    """
    @summary: Call the function registered for an action and feature name.
    @param action: Command key in COMMANDS ("get" or "set").
    @param feature_name: Feature key under that action.
    @param args: Optional arguments forwarded to the handler.
    @return: Result of the selected handler.
    """
    command = COMMANDS.get(action)
    if command is None:
        raise ValueError("Unknown action: %s" % action)
    handler = command["features"].get(feature_name)
    if handler is None:
        raise ValueError("Unknown feature: %s" % feature_name)
    return handler(*args)


def print_feature_help(parser, action):
    """
    @summary: Print CLI usage and the features registered for an action.
    @param parser: Argument parser whose usage is printed.
    @param action: Command key in COMMANDS ("get" or "set").
    @return: 0
    """
    features = COMMANDS[action]["features"]
    parser.print_help()
    print("\nAvailable --%s features:" % action)
    for name in sorted(features):
        print("  %s" % name)
    if not features:
        print("  (none)")
    return 0


def report_result(result):
    """
    @summary: Print a feature result and map it to a shell exit code.
    @param result: Value returned by the feature handler.
    @return: 0 when result is true, 1 otherwise.
    """
    print(result)
    return 0 if result else 1


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
        result = feature_request(action, values[0], *values[1:])
        return report_result(result)
    except ValueError as e:
        print(e)
        return 2


def main():
    """
    @summary: CLI entry point.

    Flags and handlers come from COMMANDS. Exactly one action is required.
    --get <feature name> <args> reads a feature.
    --set <feature name> <args> writes a feature.

    Prints the boolean result and returns a shell-friendly exit code:
    0 when the selected check is true, 1 otherwise.
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
