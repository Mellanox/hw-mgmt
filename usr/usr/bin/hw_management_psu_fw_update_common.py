#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# Copyright (c) 2021 NVIDIA CORPORATION & AFFILIATES.
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

'''
Created on June 10, 2021

Author: Mykola Kostenok <c_mykolak@nvidia.com>
Version: 0.1

Description:
Common functions and helpers function for NVidia PSU FW update tool.

'''
from __future__ import print_function
import os
import time

PMBUS_DELAY = 0.1


def calc_crc8(data):
    """
    @summary: Calculate smbus PEC.
    """
    crc8 = 0
# CRC8  = x^8 + x^2 + x^1 + x^0.
    crc8_table = [0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15,
                  0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D,
                  0x70, 0x77, 0x7E, 0x79, 0x6C, 0x6B, 0x62, 0x65,
                  0x48, 0x4F, 0x46, 0x41, 0x54, 0x53, 0x5A, 0x5D,
                  0xE0, 0xE7, 0xEE, 0xE9, 0xFC, 0xFB, 0xF2, 0xF5,
                  0xD8, 0xDF, 0xD6, 0xD1, 0xC4, 0xC3, 0xCA, 0xCD,
                  0x90, 0x97, 0x9E, 0x99, 0x8C, 0x8B, 0x82, 0x85,
                  0xA8, 0xAF, 0xA6, 0xA1, 0xB4, 0xB3, 0xBA, 0xBD,
                  0xC7, 0xC0, 0xC9, 0xCE, 0xDB, 0xDC, 0xD5, 0xD2,
                  0xFF, 0xF8, 0xF1, 0xF6, 0xE3, 0xE4, 0xED, 0xEA,
                  0xB7, 0xB0, 0xB9, 0xBE, 0xAB, 0xAC, 0xA5, 0xA2,
                  0x8F, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9D, 0x9A,
                  0x27, 0x20, 0x29, 0x2E, 0x3B, 0x3C, 0x35, 0x32,
                  0x1F, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0D, 0x0A,
                  0x57, 0x50, 0x59, 0x5E, 0x4B, 0x4C, 0x45, 0x42,
                  0x6F, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7D, 0x7A,
                  0x89, 0x8E, 0x87, 0x80, 0x95, 0x92, 0x9B, 0x9C,
                  0xB1, 0xB6, 0xBF, 0xB8, 0xAD, 0xAA, 0xA3, 0xA4,
                  0xF9, 0xFE, 0xF7, 0xF0, 0xE5, 0xE2, 0xEB, 0xEC,
                  0xC1, 0xC6, 0xCF, 0xC8, 0xDD, 0xDA, 0xD3, 0xD4,
                  0x69, 0x6E, 0x67, 0x60, 0x75, 0x72, 0x7B, 0x7C,
                  0x51, 0x56, 0x5F, 0x58, 0x4D, 0x4A, 0x43, 0x44,
                  0x19, 0x1E, 0x17, 0x10, 0x05, 0x02, 0x0B, 0x0C,
                  0x21, 0x26, 0x2F, 0x28, 0x3D, 0x3A, 0x33, 0x34,
                  0x4E, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5C, 0x5B,
                  0x76, 0x71, 0x78, 0x7F, 0x6A, 0x6D, 0x64, 0x63,
                  0x3E, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2C, 0x2B,
                  0x06, 0x01, 0x08, 0x0F, 0x1A, 0x1D, 0x14, 0x13,
                  0xAE, 0xA9, 0xA0, 0xA7, 0xB2, 0xB5, 0xBC, 0xBB,
                  0x96, 0x91, 0x98, 0x9F, 0x8A, 0x8D, 0x84, 0x83,
                  0xDE, 0xD9, 0xD0, 0xD7, 0xC2, 0xC5, 0xCC, 0xCB,
                  0xE6, 0xE1, 0xE8, 0xEF, 0xFA, 0xFD, 0xF4, 0xF3]

    for j in data:
        crc8 = crc8_table[(crc8 ^ j) & 0xff]
    return crc8


def pmbus_write(i2c_bus, i2c_addr, data):
    """
    @summary: Write pmbus command.
    """
    cmd_len = len(data) + 1
    i2c_addr_sh = i2c_addr << 1
    data_for_crc = [i2c_addr_sh]
    data_for_crc.extend(data)
    pec = calc_crc8(data_for_crc)
    data_str = "".join("0x{:02x} ".format(x) for x in data)
    # print("i2ctransfer -f -y {0:d} w{1:d}@0x{2:02X} {3}
    #        0x{4:02X}".format(i2c_bus, cmd_len, i2c_addr, data_str, pec))
    ret = os.popen("i2ctransfer -f -y {0:d} w{1:d}@0x{2:02X} {3} 0x{4:02X}"
                   .format(i2c_bus, cmd_len, i2c_addr, data_str, pec)).read()
    time.sleep(PMBUS_DELAY)
    return ret


def pmbus_write_nopec(i2c_bus, i2c_addr, data):
    """
    @summary: Write pmbus command without PEC.
    """
    cmd_len = len(data)
    data_str = "".join("0x{:02x} ".format(x) for x in data)
    ret = os.popen("i2ctransfer -f -y {0:d} w{1:d}@0x{2:02X} {3}"
                   .format(i2c_bus, cmd_len, i2c_addr, data_str)).read()
    time.sleep(PMBUS_DELAY)
    return ret


def pmbus_read(i2c_bus, i2c_addr, cmd_addr, cmd_len):
    """
    @summary: Read pmbus command.
    """
    ret = os.popen("i2ctransfer -f -y {0:d} w1@0x{1:02X} 0x{2:02X} r{3:d}"
                   .format(i2c_bus, i2c_addr, cmd_addr, cmd_len)).read()
    time.sleep(PMBUS_DELAY)
    return ret


def pmbus_read_block(i2c_bus, i2c_addr, cmd_addr):
    """
    @summary: Read pmbus block.
    """
    ret = ''
    cmd_len = pmbus_read(i2c_bus, i2c_addr, cmd_addr, 1)
    if cmd_len != '' and len(cmd_len) > 3 and cmd_len[:2] == '0x':
        ret = pmbus_read(i2c_bus, i2c_addr, cmd_addr, int(cmd_len, 16) + 1)
    return ret


def pmbus_page(i2c_bus, i2c_addr, page):
    """
    @summary: Set pmbus page.
    """
    data = [0x00, page]
    pmbus_write(i2c_bus, i2c_addr, data)


def pmbus_page_nopec(i2c_bus, i2c_addr, page):
    """
    @summary: Set pmbus page without PEC.
    """
    data = [0x00, page]
    pmbus_write_nopec(i2c_bus, i2c_addr, data)


def pmbus_read_mfr_id(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_ID.
    """
    ret = pmbus_read_block(i2c_bus, i2c_addr, 0x99)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        ascii_str = ''.join(chr(int(i, 16)) for i in ret.split())[1:]
        return ascii_str
    return ''


def pmbus_read_mfr_model(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_MODEL.
    """
    ret = pmbus_read_block(i2c_bus, i2c_addr, 0x9a)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        ascii_str = ''.join(chr(int(i, 16)) for i in ret.split())[1:]
        return ascii_str
    return ''


def pmbus_read_mfr_revision(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_REVISION.
    """
    ret = pmbus_read_block(i2c_bus, i2c_addr, 0x9b)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        ascii_str = ''.join(chr(int(i, 16)) for i in ret.split())[1:]
        return ascii_str
    return ''


def progress_bar(progress, total):
    """
    @summary: print progress bar.
    """
    print('\r[{0:20}]{1:>2}%'.format('#' * int(progress * 20 / total), progress), end=(''))


def check_psu_redundancy(proceed, ignore_addr):
    """
    @summary: Check PSU redundancy.
    """
    psu_num = os.popen("cat /var/run/hw-management/config/hotplug_psus").read()
    for i in range(1, int(psu_num) + 1):
        psu_dc = os.popen("cat /var/run/hw-management/thermal/psu{}_pwr_status".format(i)).read()
        psu_i2c_addr = os.popen("cat /var/run/hw-management/config/psu{}_i2c_addr".format(i)).read()
        if int(psu_dc) != 1:
            if proceed and ignore_addr == int(psu_i2c_addr, 16):
                print("The previous update is in progress, so ignore PSU{} {} is powered OFF.".format(i, psu_i2c_addr[:-1]))
                continue
            print("PSU{} {} powered OFF, PSU redundancy checkup failed. PSU count: {}".format(i, psu_i2c_addr[:-1], int(psu_num)))
            exit(-1)
    return 0
