#!/usr/bin/env python
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2021-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

import time
import sys
import errno
import os.path
import argparse
from python_sdk_api.sx_api import *
from python_sdk_api.sxd_api import *

POLL_TIME = 5
POLL_TIMEOUT = 60

parser = argparse.ArgumentParser(description='SXD-API MSCI example')
parser.add_argument('-c', '--command', dest='command', default=0, type=int, help='Read CPLD version command')
parser.add_argument('-i', '--idx', dest='index', default=0, type=int, help='CPLD index')
parser.add_argument('-s', '--strict', dest='strict', default=0, type=int, help='Print only version')
parser.add_argument('-r', '--retry', dest='retry', default=(POLL_TIMEOUT / POLL_TIME), type=int, help='CPLD read retry count')
args = parser.parse_args()
msci_command = args.command

retcode = 0
if args.strict != 0:
    print("[+] MSCI example start")
    print("[+] Initializing register access")

for i in range(0, args.retry):
    print("Reading MSCI reg try: {}".format(i))
    if i != 0:
        print("wait {}sec".format(POLL_TIME))
        time.sleep(POLL_TIME)

    if not os.path.isfile("/dev/shm/dpt"):
        print("DPT not initialised. Wait some more time ...")
        continue

    rc = sxd_access_reg_init(0, None, 4)
    if rc != 0:
        print("Failed to initializing register access.\nPlease check that SDK is running.")
        retcode = errno.EACCES
        continue

    meta = sxd_reg_meta_t()
    meta.dev_id = 1
    meta.swid = 0
    meta.access_cmd = SXD_ACCESS_CMD_GET

    msci = ku_msci_reg()
    msci.command = msci_command
    msci.index = args.index

    if args.strict != 0:
        print("[+] Querying meta cmd ({})".format(msci_command))
    rc = sxd_access_reg_msci(msci, meta, 1, None, None)
    if rc != 0:
        retcode = rc
        print("Failed to query MSCI register, rc: %d" % (rc))
        continue

    if args.strict != 0:
        print("[+] Version:{}".format(msci.version))
        print("[+] MSCI example end")
    else:
        print("Version:{}".format(msci.version))
    retcode = 0
    break

sys.exit(retcode)
