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
