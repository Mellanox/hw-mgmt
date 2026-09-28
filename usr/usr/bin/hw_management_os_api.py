#!/usr/bin/python
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause

"""
@summary:
    Host OS checks used by hw-management.

    is_usb0_managed_by_nos reports whether /etc/sonic/sonic_version.yml exists.
    The shell caller also requires a BMC/host contract file before it treats
    usb0 as NOS-owned.

    is_redfish_disabled is a temporary stand-in (Bug 5272044). It always
    returns False, so Redfish login and BMC sensor polling stay enabled on
    every NOS until the real NOS API is available.

Usage:
    As a module:
        from hw_management_os_api import os_api_get
        if os_api_get("is_usb0_managed_by_nos"):
            ...

    As a command (for shell callers, exit code based):
        hw_management_os_api.py is_usb0_managed_by_nos
        hw_management_os_api.py is_usb0_managed_by_nos aaa bbb
        hw_management_os_api.py is_redfish_disabled
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


def is_redfish_disabled_os(*_args):
    """
    @summary: Check whether Redfish is disabled on this host.
    @param _args: Optional arguments. Unused by this check.
    @return: Always False until the NOS API is available. Bug 5272044.
    """
    return False


OS_API = {
    "is_usb0_managed_by_nos": is_usb0_managed_by_nos,
    "is_redfish_disabled": is_redfish_disabled_os,
}


def os_api_get(api_name, *args):
    """
    @summary: Call a host OS check by name.
    @param api_name: Check to run (is_usb0_managed_by_nos or is_redfish_disabled).
    @param args: Optional arguments forwarded to the check.
    @return: Result of the selected check.
    """
    handler = OS_API.get(api_name)
    if handler is None:
        raise ValueError("Unknown OS API: %s" % api_name)
    return handler(*args)


def main():
    """
    @summary: CLI entry point.

    Argument get selects the check, dispatched through os_api_get():
        is_usb0_managed_by_nos -> is_usb0_managed_by_nos()
        is_redfish_disabled  -> is_redfish_disabled_os()

    Prints the boolean result and returns a shell-friendly exit code:
    0 when the selected check is true, 1 otherwise.
    """
    parser = argparse.ArgumentParser(
        description="Host OS checks for hw-management")
    parser.add_argument(
        "get",
        choices=sorted(OS_API.keys()),
        help="Check to run")
    parser.add_argument(
        "args",
        nargs="*",
        help="Optional arguments forwarded to the check")
    args = parser.parse_args()

    result = os_api_get(args.get, *args.args)
    print(result)
    return 0 if result else 1


if __name__ == "__main__":
    sys.exit(main())
