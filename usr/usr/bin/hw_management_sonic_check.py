#!/usr/bin/python
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

"""
@summary:
    Detect whether the host NOS is SONiC.

    SONiC ships a version manifest at /etc/sonic/sonic_version.yml that is not
    present on other network operating systems (e.g. Cumulus Linux). Its
    presence is used as the single source of truth for "host is running SONiC".

    When the host runs SONiC, hw-management must NOT drive the CPU<->BMC sync
    flow (Redfish login / BMC password rotation / BMC temperature polling),
    because SONiC owns BMC communication on those platforms. On any other host
    OS the existing behavior is unchanged.

Usage:
    As a module:
        from hw_management_sonic_check import is_sonic_os
        if is_sonic_os():
            ...

    As a command (for shell callers, exit code based):
        hw_management_sonic_check.py   # exit 0 if SONiC, 1 otherwise
"""

import os
import sys

# SONiC version manifest. Present only on SONiC hosts.
SONIC_VERSION_FILE = "/etc/sonic/sonic_version.yml"


def is_sonic_os():
    """
    @summary: Check whether the host is running SONiC.
    @return: True if the SONiC version manifest exists, False otherwise.
    """
    return os.path.isfile(SONIC_VERSION_FILE)


def main():
    """
    @summary: CLI entry point.

    Prints the boolean result and returns a shell-friendly exit code:
    0 when the host runs SONiC, 1 otherwise.
    """
    sonic = is_sonic_os()
    print(sonic)
    return 0 if sonic else 1


if __name__ == "__main__":
    sys.exit(main())
