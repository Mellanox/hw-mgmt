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
        hw_management_os_api.py is_redfish_disabled
        # exit 0 when the selected check is true, 1 otherwise
"""

import argparse
import os
import sys

# SONiC version manifest. Present only on SONiC hosts.
SONIC_VERSION_FILE = "/etc/sonic/sonic_version.yml"


def is_usb0_managed_by_nos():
    """
    @summary: Check whether the SONiC version manifest is present.
    @return: True when /etc/sonic/sonic_version.yml exists, False otherwise.
    """
    return os.path.isfile(SONIC_VERSION_FILE)


def is_redfish_disabled_os():
    """
    @summary: Check whether Redfish is disabled on this host.
    @return: Always False until the NOS API is available. Bug 5272044.
    """
    return False


OS_API = {
    "is_usb0_managed_by_nos": is_usb0_managed_by_nos,
    "is_redfish_disabled": is_redfish_disabled_os,
}


def os_api_get(api_name, arg=None):
    """
    @summary: Call a host OS check by name.
    @param api_name: Check to run (is_usb0_managed_by_nos or is_redfish_disabled).
    @param arg: Optional argument forwarded to the check. Omitted when None.
    @return: Result of the selected check.
    """
    handler = OS_API.get(api_name)
    if handler is None:
        raise ValueError("Unknown OS API: %s" % api_name)
    if arg is None:
        return handler()
    return handler(arg)


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
        "arg",
        nargs="?",
        default=None,
        help="Optional argument forwarded to the check")
    args = parser.parse_args()

    result = os_api_get(args.get, args.arg)
    print(result)
    return 0 if result else 1


if __name__ == "__main__":
    sys.exit(main())
