#!/usr/bin/python

# pylint: disable=line-too-long
# pylint: disable=C0103

##################################################################################
# Copyright (c) 2018 - 2021, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
Created on Nov 05, 2020

Author: Oleksandr Shamray <oleksandrs@mellanox.com>
Version: 1.0

Description: This util converting FRU data file and saving it to file

Command line parameters:
usage: hw-management-fru-dump.py [-h] [-i INPUT] [-o OUTPUT] [-v]

optional arguments:
  -h, --help            show this help message and exit
  -i INPUT, --input_file INPUT
                        FRU binary file name.
  -o OUTPUT, --output_file OUTPUT
                        File to output parsed FRU fields
  -v, --version         show version

'''

#############################
# Global imports
#############################
import sys
import argparse
import os.path
import subprocess
import struct
import binascii
import zlib
import tempfile
import shutil


#############################
# Global const
#############################
VERSION = "2.0"


# TLV header format.
# struct {
#    char type;
#    char size;
#  };
TLV_FORMAT = ">BB"
TLV_FIELDS = ["type", "size"]

# FRU bin header format.
FRU_SANITY_FORMAT = ">8sBH"
FRU_SANITY_FORMAT_FIELDS = ["tlv_header", "ver", "total_len"]

# MLNX header format.
MLNX_HDR_FORMAT = ">HBBBBH"
MLNX_HDR_FORMAT_FIELDS = ["block_size", "major_ver", "minor_ver", "block_type", "cs", "reserved"]

MLNX_BASE_BLK_FIELD = ">BB"
MLNX_BASE_BLK_FIELD_FORMAT = ["block_start", "block_type"]

# Supported FRU versions.
SUPPORTED_FRU_VER = [1]


#
MAX_VPD_DATA_SIZE = 4096


class LC_ID(object):
    """
    @summary: hw-management-vpd LC constants
    """
    PRODUCT_NAME = 2
    PN = 3
    SN = 4
    MFG_DATE = 5
    SW_REV = 6
    HW_REV = 7
    PORT_NUM = 8
    PORT_SPEED = 9
    MANUFACTURER = 10
    CHSUM = 11


class ONIE_ID(object):
    """
    @summary: hw-management-vpd ONIE constants
    """
    PRODUCT_NAME = 33
    PN = 34
    SN = 35
    BASE_MAC = 36
    MFG_DATE = 37
    DEV_VER = 38
    LABEL_REV = 39
    PLATFORM_NAME = 40
    ONIE_VER = 41
    MAC_ADDR = 42
    MANUFACTURER = 43
    VENDOR = 45
    SVC_TAG = 47
    VENDOR_BLK = 253
    CHSUM = 254


class MLNX_ID(object):
    """
    @summary: hw-management-vpd ONIE constants
    """
    MFG = 1
    GUIDS = 2
    CPUDATA = 3
    OSBOOT = 4
    HWCHAR = 5
    LIC = 6
    EKEYING = 7
    MIN_FIT = 8
    PORT_CFG = 9
    VENDOR_ID = 10
    MFG_INTERNAL = 12
    PSU = 16
    DPU = 17
    PSID = 18
    GUIDS_1 = 0x80
    GUIDS_2 = 0x81
    PORT_CFG_EXT = 0x82
    EKEYING_NEW = 0x83

    MINOR_NEW_VER = 0x10


# FRU fields description.
SYSTEM_VPD = {"type": "ONIE",
              LC_ID.PRODUCT_NAME: {'type_name': "PRODUCT_NAME_VPD_FIELD", "fn": "format_unpack", "format": "{}s"},
              LC_ID.PN: {'type_name': "PN_VPD_FIELD", "fn": "format_unpack", "format": "{}s"},
              LC_ID.SN: {'type_name': "SN_VPD_FIELD", "fn": "format_unpack", "format": "{}s"},
              LC_ID.MFG_DATE: {'type_name': "MFG_DATE_FIELD", "fn": "format_unpack", "format": "{}s"},
              LC_ID.SW_REV: {'type_name': "SW_REV_FIELD", "fn": "format_unpack", "format": "b"},
              LC_ID.HW_REV: {'type_name': "HW_REV_FIELD", "fn": "format_unpack", "format": "b"},
              LC_ID.PORT_NUM: {'type_name': "PORT_NUM_FIELD", "fn": "format_unpack", "format": "b"},
              LC_ID.PORT_SPEED: {'type_name': "PORT_SPEED_FIELD", "fn": "format_unpack", "format": ">i"},
              LC_ID.MANUFACTURER: {'type_name': "MANUFACTURER_VPD_FIELD", "fn": "format_unpack", "format": "{}s"},
              LC_ID.CHSUM: {'type_name': "CHSUM_FIELD", "fn": "format_unpack", "format": ">I"},
              ONIE_ID.PRODUCT_NAME: {'type_name': "Product Name", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.PN: {'type_name': "Part Number", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.SN: {'type_name': "Serial Number", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.BASE_MAC: {'type_name': "Base MAC Address", "fn": "format_unpack", "format": "{}s", "transform": "hex"},
              ONIE_ID.MFG_DATE: {'type_name': "Manufacture Date", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.DEV_VER: {'type_name': "Device Version", "fn": "format_unpack", "format": "b"},
              ONIE_ID.LABEL_REV: {'type_name': "Label Revision", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.PLATFORM_NAME: {'type_name': "Platform Name", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.ONIE_VER: {'type_name': "ONIE Version", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.MAC_ADDR: {'type_name': "MAC Addresses", "fn": "format_unpack", "format": ">h"},
              ONIE_ID.MANUFACTURER: {'type_name': "Manufacturer", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.VENDOR: {'type_name': "Vendor", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.SVC_TAG: {'type_name': "Service Tag", "fn": "format_unpack", "format": "{}s"},
              ONIE_ID.VENDOR_BLK: {'type_name': "", "fn": "onie_parse_vendor_blk"},
              ONIE_ID.CHSUM: {'type_name': "CHSUM_FIELD", "fn": "format_unpack", "format": ">I"}
              }


MLNX_IANA = 0x00008119
# fmt: off
MLNX_VENDOR_BLK = {"type": "MLNX",
                    MLNX_ID.MFG: {'blk_type': "MFG", "fn": "mlnx_blk_unpack", "format": [
                            ["SN",  1,  8, 24,  "FIT_NORMAL", "FT_ASCII"],
                            ["PN",  1, 32, 20,  "FIT_NORMAL", "FT_ASCII"],
                            ["REV", 1, 52, 4,   "FIT_NORMAL", "FT_ASCII"],
                            ["RESERVED",    1, 56, 1,   "FIT_NORMAL", "FT_RESERVED"],
                            ["MFG_DATE",    1, 57, 3,   "FIT_NORMAL", "FT_NUM"],
                            ["PROD_NAME",   1, 60, 64,  "FIT_NORMAL", "FT_ASCII"],
                            ["HW_MGT_ID",   2, 124, 3,  "FIT_NORMAL", "FT_NUM"],
                            ["HW_MGT_REV",  2, 127, 1,  "FIT_NORMAL", "FT_NUM"],
                            ["SW_MGT_ID",   3, 128, 4,  "FIT_NORMAL", "FT_NUM"],
                            ["SYS_DISPLAY", 3, 132, 16, "FIT_NORMAL", "FT_ASCII"]
                        ]},
                    MLNX_ID.GUIDS: {'blk_type': "GUIDS", "fn": "mlnx_blk_unpack", "format": [
                            ["GUID_TYPE",   1, 8,  1, "FIT_NORMAL", "FT_HEX"],
                            ["RESERVED",    2, 9, 7,  "FIT_NORMAL", "FT_RESERVED"],
                            ["UID",         1, 16, 8, "FIT_COMP",   "FT_NUM"]
                        ]},
                    MLNX_ID.CPUDATA: {'blk_type': "CPUDATA"},
                    MLNX_ID.OSBOOT: {'blk_type': "OSBOOT"},
                    MLNX_ID.HWCHAR: {'blk_type': "HWCHAR", "fn": "mlnx_blk_unpack", "format": [
                            ["MAX_POWER",      1, 8,  2, "FIT_NORMAL", "FT_NUM"],
                            ["CRIT_AMB_TEMP",  1, 10, 1, "FIT_NORMAL", "FT_NUM"],
                            ["CRIT_IC_TEMP",   1, 11, 1, "FIT_NORMAL", "FT_NUM"],
                            ["ALERT_AMB_TEMP", 1, 12, 1, "FIT_NORMAL", "FT_NUM"],
                            ["ALERT_IC_TEMP",  1, 13, 1, "FIT_NORMAL", "FT_NUM"],
                            ["FAN_DIR",        2, 14, 1, "FIT_NORMAL", "FT_NUM"],
                            ["LENGTH",         3, 15, 1, "FIT_NORMAL", "FT_NUM"],
                            ["WIDTH",          3, 16, 1, "FIT_NORMAL", "FT_NUM"],
                            ["LED",            3, 17, 1, "FIT_NORMAL", "FT_NUM"]
                        ]},
                    MLNX_ID.LIC: {'blk_type': "LIC", "fn": "mlnx_blk_unpack", "format": [
                            ["FEATURE_EN_", 1, 8, 1, "FIT_COMP", "FT_NUM"]
                        ]},
                    MLNX_ID.EKEYING: {'blk_type': "EKEYING", "fn": "mlnx_blk_unpack", "format": [
                            ["RESERVED",          1, 8,  1,  "FIT_NORMAL", "FT_RESERVED"],
                            ["NUM_SCHEME",        1, 9,  1,  "FIT_NORMAL", "FT_NUM"],
                            ["EN_PORTS_NUM",      1, 10, 1,  "FIT_NORMAL", "FT_NUM"],
                            ["PORTS_INC_SCHEME",  1, 11, 1,  "FIT_NORMAL", "FT_NUM"],
                            ["PORTS_INC_ORDER_",  1, 12, 1, "FIT_COMP",   "FT_NUM"]
                        ]},
                    MLNX_ID.MIN_FIT: {'blk_type': "MIN_FIT"},
                    MLNX_ID.PORT_CFG:  {'blk_type': "PORT_CFG", "fn": "mlnx_blk_unpack", "format": [
                            ["PORT_CFG_", 1, 8, 1,  "FIT_COMP",   "FT_NUM"]
                        ]},
                    MLNX_ID.VENDOR_ID: {'blk_type': "VENDOR_ID", "fn": "mlnx_blk_unpack", "format": [
                            ["VENDOR_ID", 1, 8, 8,  "FIT_NORMAL",   "FT_NUM"]
                        ]},
                    MLNX_ID.MFG_INTERNAL: {'blk_type': "MFG_INTERNAL", "fn": "mlnx_blk_unpack", "format": [
                            ["MFG_INTERNAL", 2, 8, 1,  "FIT_COMP",   "FT_NUM"]
                        ]},
                    MLNX_ID.PSU: {'blk_type': "PSU", "fn": "mlnx_blk_unpack", "format": [
                            ["MAX_PSU",     1, 8,  1,   "FIT_NORMAL", "FT_NUM"],
                            ["MIN_PSU",     1, 9,  1, "FIT_NORMAL", "FT_NUM"],
                            ["FACTORY_ASSMBL_PSU",  1, 10, 1, "FIT_NORMAL", "FT_NUM"]
                        ]},
                    MLNX_ID.DPU: {'blk_type': "DPU", "fn": "mlnx_blk_unpack", "format": [
                            ["DPU_NUM",       1, 8,   1,   "FIT_NORMAL", "FT_NUM"],
                            ["DPU1_SN",       1, 9,   24,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU1_PN",       1, 33,  20,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU1_REV",      1, 53,  4,   "FIT_NORMAL", "FT_ASCII"],
                            ["DPU1_BASE_MAC", 1, 57,  6,   "FIT_NORMAL", "FT_MAC"],
                            ["DPU2_SN",       1, 63,  24,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU2_PN",       1, 87,  20,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU2_REV",      1, 107, 4,   "FIT_NORMAL", "FT_ASCII"],
                            ["DPU2_BASE_MAC", 1, 111, 6,   "FIT_NORMAL", "FT_MAC"],
                            ["DPU3_SN",       1, 117, 24,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU3_PN",       1, 141, 20,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU3_REV",      1, 161, 4,   "FIT_NORMAL", "FT_ASCII"],
                            ["DPU3_BASE_MAC", 1, 165, 6,   "FIT_NORMAL", "FT_MAC"],
                            ["DPU4_SN",       1, 171, 24,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU4_PN",       1, 195, 20,  "FIT_NORMAL", "FT_ASCII"],
                            ["DPU4_REV",      1, 215, 4,   "FIT_NORMAL", "FT_ASCII"],
                            ["DPU4_BASE_MAC", 1, 219, 6,   "FIT_NORMAL", "FT_MAC"]
                        ]},
                    MLNX_ID.PSID: {'blk_type': "PSID", "fn": "mlnx_blk_unpack", "format": [
                            ["PSID",  1,  8, 34,  "FIT_NORMAL", "FT_ASCII"]
                        ]},
                    MLNX_ID.GUIDS_1: {'blk_type': "GUIDS", "fn": "mlnx_blk_unpack", "format": [
                            ["GUID_TYPE",    1, 8,  1,   "FIT_NORMAL", "FT_HEX"],
                            ["RESERVED",     2, 9,  7, "FIT_NORMAL", "FT_RESERVED"],
                            ["BASE_MAC_1",  16, 16, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_1", 16, 22, 2, "FIT_NORMAL", "FT_NUM_INV"],
                            ["BASE_MAC_2",  16, 24, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_2", 16, 30, 2, "FIT_NORMAL", "FT_NUM_INV"],
                            ["BASE_MAC_3",  16, 32, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_3", 16, 38, 2, "FIT_NORMAL", "FT_NUM_INV"],
                            ["BASE_MAC_4",  16, 40, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_4", 16, 42, 2, "FIT_NORMAL", "FT_NUM_INV"]
                        ]},
                    MLNX_ID.GUIDS_2: {'blk_type': "GUIDS", "fn": "mlnx_blk_unpack", "format": [
                            ["GUID_TYPE",    1, 8,  1, "FIT_NORMAL", "FT_HEX"],
                            ["RESERVED",     2, 9,  7, "FIT_NORMAL", "FT_RESERVED"],
                            ["BASE_MAC_1",  16, 16, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_1", 16, 22, 2, "FIT_NORMAL", "FT_HEX_INV"],
                            ["BASE_GUID_1", 17, 24, 8, "FIT_NORMAL", "FT_MAC"],
                            ["BASE_MAC_2",  16, 32, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_2", 16, 38, 2, "FIT_NORMAL", "FT_HEX_INV"],
                            ["BASE_GUID_2", 17, 40, 8, "FIT_NORMAL", "FT_MAC"],
                            ["BASE_MAC_3",  16, 48, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_3", 16, 54, 2, "FIT_NORMAL", "FT_HEX_INV"],
                            ["BASE_GUID_3", 17, 56, 8, "FIT_NORMAL", "FT_MAC"],
                            ["BASE_MAC_4",  16, 64, 6, "FIT_NORMAL", "FT_MAC"],
                            ["MAC_RANGE_4", 16, 70, 2, "FIT_NORMAL", "FT_HEX_INV"],
                            ["BASE_GUID_4", 17, 72, 8, "FIT_NORMAL", "FT_MAC"]
                        ]},
                    MLNX_ID.PORT_CFG_EXT:  {'blk_type': "PORT_CFG", "fn": "mlnx_blk_unpack", "format": [
                            ["PORT_CFG_", 2, 8, 2,  "FIT_COMP",   "FT_NUM"]
                        ]},
                    MLNX_ID.EKEYING_NEW: {'blk_type': "EKEYING", "fn": "mlnx_blk_unpack", "format": [
                            ["PORTS_LIC_SCHEME",  2, 8,  1,  "FIT_NORMAL", "FT_ASCII"],
                            ["NUM_SCHEME",        1, 9,  1,  "FIT_NORMAL", "FT_NUM"],
                            ["EN_PORTS_NUM",      1, 10, 1,  "FIT_NORMAL", "FT_NUM"],
                            ["PORTS_INC_SCHEME",  1, 11, 1,  "FIT_NORMAL", "FT_NUM"],
                            ["RESERVED",          1, 12, 4,  "FIT_NORMAL", "FT_RESERVED"],
                            ["PORTS_LIC_ARRAY_",  1, 16, 1,  "FIT_COMP",   "FT_NUM"]
                        ]},
}
# fmt: on

# FAN "fixed fileds" FRU fields description
FIXED_FIELD_FAN_VPD = {"type": "FIXED_FILED_VPD",
                       "blk_type": "FIXED_FIELD_FAN_VPD_BLK",
                       "format": [
                               ["PN", 0, 16, "FT_ASCII"],
                               ["SN", 16, 16, "FT_ASCII"]
                       ]}

MLNX_VENDOR_BLK_FIELDS = ["name", "minor_version", "offset", "length", "info_type", "type"]
FIXED_FIELD_BLK_FIELDS = ["name", "offset", "length", "type"]

MLNX_CPU_VPD = MLNX_VENDOR_BLK
MLNX_FAN_VPD = MLNX_VENDOR_BLK
MLNX_PDB_VPD = MLNX_VENDOR_BLK
MLNX_CARTRIDGE_VPD = MLNX_VENDOR_BLK
LC_VPD = SYSTEM_VPD


def bin_decode(val):
    return val.decode('ascii').rstrip('\x00') if isinstance(val, bytes) else val


def int_unpack_be(val):
    return sum([b * 2**(8 * n) for (b, n) in zip(val, range(len(val))[::-1])])


def int_unpack_le(val):
    return sum([b * 2**(8 * n) for (b, n) in zip(val, range(len(val)))])


def printv(message, verbosity):
    if verbosity:
        print(str(message))


def format_unpack(_data, item, blk_header, verbose=False):
    """
    @summary: unpack binary data by format
    """
    item_format = item['format'].format(blk_header['size'])
    val = struct.unpack(item_format, _data)[0]
    if isinstance(val, str):
        if blk_header["type"] == ONIE_ID.BASE_MAC:
            pass
        else:
            val = val.split('\x00', 1)[0]
    elif 'I' in item_format:
        val = "{0:#0{1}x}".format(val, 10).upper()

    if "transform" in item.keys():
        transform = item["transform"]
        if transform == "hex":
            val = binascii.hexlify(val)
    val = bin_decode(val)
    return val


def parse_fru_fixed_fields_bin(data, blk_hdr, verbose=False):
    if "format" not in blk_hdr.keys():
        return "-"
    block_format = blk_hdr["format"]
    printv("Block_type {}\n".format(blk_hdr["blk_type"]), verbose)
    rec_list = []
    for rec in block_format:
        rec_dict = dict(list(zip(FIXED_FIELD_BLK_FIELDS, rec)))
        rec_size = rec_dict["length"]
        rec_offset = rec_dict["offset"]

        rec_type = rec_dict["type"]
        if rec_type == "FT_RESERVED":
            continue

        printv("rec: {}".format(rec), verbose)

        _data = data[rec_offset: rec_offset + rec_size]
        rec_name = rec_dict["name"]
        if rec_type == "FT_ASCII":
            item_format = "{}s".format(rec_size)
            val = struct.unpack(item_format, _data)[0]
            val = val.split(b'\x00')[0]
        elif rec_type == "FT_NUM":
            _data_str = struct.unpack("{}B".format(rec_size), _data)
            val = int_unpack_be(_data_str)
        elif rec_type == "FT_NUM_INV":
            _data_str = struct.unpack("{}B".format(rec_size), _data)
            val = int_unpack_le(_data_str)
        elif rec_type == "FT_HEX":
            _data_str = struct.unpack("{}B".format(rec_size), _data)
            val = hex(int_unpack_be(_data_str))
        elif rec_type == "FT_HEX_INV":
            _data_str = struct.unpack("{}B".format(rec_size), _data)
            val = hex(int_unpack_le(_data_str))
        elif rec_type == "FT_MAC":
            _data_str = struct.unpack("{}B".format(rec_size), _data)
            val = ':'.join(['{:02X}'.format(byte) for byte in _data_str])
        else:
            continue

        printv("BIN: {}".format(binascii.hexlify(_data)), verbose)
        printv("{} : {}\n".format(rec_name, bin_decode(val)), verbose)

        rec_list.append([rec_name, bin_decode(val)])

    return {'items': rec_list}


def mlnx_blk_unpack(data, blk_hdr, size, verbose=False):
    if "format" not in blk_hdr.keys():
        return "-"
    block_format = blk_hdr["format"]
    printv("Block_type {}\n".format(blk_hdr['blk_type']), verbose)
    rec_list = []
    for rec in block_format:
        rec_dict = dict(list(zip(MLNX_VENDOR_BLK_FIELDS, rec)))
        rec_size = rec_dict["length"]
        rec_offset = rec_dict["offset"] - 8
        if rec_offset + rec_size >= size:
            break

        rec_type = rec_dict["type"]
        if rec_type == "FT_RESERVED":
            continue

        if rec_dict["info_type"] == "FIT_COMP":
            num_of_repeat = int((size - (6 + rec_offset)) / rec_size)
            rec_name_fmt = rec_dict["name"] + "{idx}"
        else:
            num_of_repeat = 1
            rec_name_fmt = rec_dict["name"]
        printv("rec: {}".format(rec), verbose)

        for idx in range(num_of_repeat):
            offset = rec_offset + idx * rec_size
            _data = data[offset: offset + rec_size]
            if rec_type == "FT_ASCII":
                item_format = "{}s".format(rec_size)
                val = struct.unpack(item_format, _data)[0]
                rec_name = rec_name_fmt.format(idx)
            elif rec_type == "FT_NUM":
                _data_str = struct.unpack("{}B".format(rec_size), _data)
                val = int_unpack_be(_data_str)
                rec_name = rec_name_fmt.format(idx=idx)
            elif rec_type == "FT_NUM_INV":
                _data_str = struct.unpack("{}B".format(rec_size), _data)
                val = int_unpack_le(_data_str)
                rec_name = rec_name_fmt.format(idx=idx)
            elif rec_type == "FT_HEX":
                _data_str = struct.unpack("{}B".format(rec_size), _data)
                val = hex(int_unpack_be(_data_str))
                rec_name = rec_name_fmt.format(idx=idx)
            elif rec_type == "FT_HEX_INV":
                _data_str = struct.unpack("{}B".format(rec_size), _data)
                val = hex(int_unpack_le(_data_str))
                rec_name = rec_name_fmt.format(idx=idx)
            elif rec_type == "FT_MAC":
                _data_str = struct.unpack("{}B".format(rec_size), _data)
                val = ':'.join(['{:02X}'.format(byte) for byte in _data_str])
                rec_name = rec_name_fmt.format(idx=idx)
            else:
                continue
            printv("BIN: {}".format(binascii.hexlify(_data)), verbose)
            printv("{} : {}\n".format(rec_name, bin_decode(val)), verbose)

            rec_list.append([rec_name, bin_decode(val)])
    return rec_list


def parse_packed_data(data, data_format, fields):
    '''
    @summary: converting binary packed data to dictionary
    @param data: binary data array
    @param data_format: struct.unpack data format
    @param fields: list of fields names
    @return: dictionary with parsed field_name:value list and header size in bytes
    '''
    struct_size = struct.calcsize(data_format)
    unpack_res = struct.unpack(data_format, data[:struct_size])
    res_dict = dict(list(zip(fields, unpack_res)))
    for key, val in list(res_dict.items()):
        if isinstance(val, str):
            res_dict[key] = val.split('\x00', 1)[0]

    return res_dict, struct_size


def fru_get_tlv_header(data_bin):
    '''
    @summary: get FRU TLV header from binary
    @param data: binary data array
    @return: dictionary with parsed TLV header
    '''
    res_dict, size = parse_packed_data(data_bin, TLV_FORMAT, TLV_FIELDS)
    if res_dict['size'] > 1024:
        return None, 0

    return res_dict, size


def onie_parse_vendor_blk(data, _data_format, _fields, verbose=False):
    blk_IANA = struct.unpack(">I", data[:4])[0]

    if blk_IANA == MLNX_IANA:
        _data = data[4:]
        blk_header, hdr_size = parse_packed_data(_data, MLNX_HDR_FORMAT, MLNX_HDR_FORMAT_FIELDS)
        _data = _data[hdr_size: hdr_size + blk_header['block_size']]
        return parse_mlnx_blk(_data, blk_header, MLNX_VENDOR_BLK, verbose)

    return None


def parse_mlnx_blk(data, blk_header, FRU_ITEMS, verbose=False):
    if blk_header["block_type"] == MLNX_ID.GUIDS:
        if blk_header["minor_ver"] == MLNX_ID.MINOR_NEW_VER:
            blk_header["block_type"] = MLNX_ID.GUIDS_1
        elif blk_header["minor_ver"] > MLNX_ID.MINOR_NEW_VER:
            blk_header["block_type"] = MLNX_ID.GUIDS_2
    elif blk_header["block_type"] == MLNX_ID.PORT_CFG:
        if blk_header["minor_ver"] >= MLNX_ID.MINOR_NEW_VER:
            blk_header["block_type"] = MLNX_ID.PORT_CFG_EXT
    elif blk_header["block_type"] == MLNX_ID.EKEYING:
        if blk_header["minor_ver"] >= MLNX_ID.MINOR_NEW_VER:
            blk_header["block_type"] = MLNX_ID.EKEYING_NEW

    blk_id = blk_header["block_type"]
    out_str = ""
    if blk_id in FRU_ITEMS.keys():
        blk_item = FRU_ITEMS[blk_id]
        fn_name = blk_item.get("fn", None)
        if fn_name:
            rec_list = globals()[fn_name](data, blk_item, blk_header['block_size'], verbose)
            out_str += "=== MLNX_block: {}({}) ===\n".format(blk_item["blk_type"], blk_id, verbose) if verbose else ""
            print_format = '{:<25}{}\n'
            for key, val in rec_list:
                out_str += print_format.format(key + ":", val)
    else:
        printv("Not supported block_type {}".format(blk_id), verbose)
    return out_str


def parse_fru_mlnx_bin(data, FRU_ITEMS, verbose=False):
    fru_dict = {}
    fru_dict['items'] = []
    blk_header, hdr_size = parse_packed_data(data, MLNX_HDR_FORMAT, MLNX_HDR_FORMAT_FIELDS)

    _data = data[hdr_size:]
    try:
        sanity_str = bin_decode(struct.unpack("4s", _data[:4])[0])
    except BaseException:
        sanity_str = ""
    if sanity_str != "MLNX":
        printv("MLNX Sanitiy check fail", verbose)
        return None
    printv("Sanitiy check is OK", verbose)
    out_str = ""
    base_pos = hdr_size + 4
    while base_pos <= (blk_header["block_size"]):
        printv("BLK offset: {}".format(base_pos), verbose)
        base_data = data[base_pos:]
        rec_header, rec_size = parse_packed_data(base_data, MLNX_BASE_BLK_FIELD, MLNX_BASE_BLK_FIELD_FORMAT)
        printv("BLK header: {}".format(rec_header), verbose)
        base_pos += rec_size
        if rec_header["block_type"] == 0:
            continue

        blk_data_off = rec_header["block_start"] * 16
        printv("BLK data offset: {}".format(blk_data_off), verbose)
        blk_header, hdr_size = parse_packed_data(data[blk_data_off:], MLNX_HDR_FORMAT, MLNX_HDR_FORMAT_FIELDS)
        printv("BLK header: {}".format(blk_header), verbose)
        out_str += parse_mlnx_blk(data[blk_data_off + hdr_size:], blk_header, FRU_ITEMS, verbose)

    fru_dict['items'].append(["", out_str])
    return fru_dict


def parse_fru_onie_bin(data, FRU_ITEMS, verbose=False):
    '''
    @summary: main function. Takes binary FRU data and return dictionary with all parsed data
    @param data: binary data array
    @return: dictionary with parsed data.
      Output example:
        {   'items': [   ['Product_Name', 'line card product name '],
                         ['Partnumber', 'line card Part num'],
                         ['Serialnumber', 'line card serail number'],
                         ['MFGDate', '123456789abcdefghij'],
                         ['device_sw_id', 0],
                         ['device_hw_revision', 0],
                         ['Manufacturer', 'Mellanox'],
                         ['max_power', '10000000'],
                         ['CRC32', '0x78563412']],
            'tlv_header': 'TlvInfo',
            'total_len': 167,
            'ver': 1}
    '''
    fru_dict, offset = parse_packed_data(data, FRU_SANITY_FORMAT, FRU_SANITY_FORMAT_FIELDS)
    try:
        tlv_header = bin_decode(fru_dict['tlv_header'])
    except BaseException:
        tlv_header = ""
    if 'TlvInfo' not in tlv_header or fru_dict['ver'] not in SUPPORTED_FRU_VER:
        return None

    fru_dict['items'] = []
    fru_dict['items_dict'] = {}
    pos = offset
    while pos < fru_dict['total_len'] + offset:
        blk_header, header_size = fru_get_tlv_header(data[pos:])
        pos += header_size
        if blk_header['type'] not in list(FRU_ITEMS.keys()):
            print("Not supported item type {}".format(blk_header['type']))
            pos += blk_header['size']
            continue
        item = FRU_ITEMS[blk_header['type']]
        fn_name = item.get("fn", None)
        if fn_name:
            _data = data[pos: pos + blk_header['size']]
            val = globals()[fn_name](_data, item, blk_header, verbose)
            if val:
                fru_dict['items'].append([item['type_name'], val])
                fru_dict['items_dict'][item['type_name']] = val

        pos += blk_header['size']

    if check_crc32(data[: fru_dict['total_len'] + 7],
                   fru_dict['items_dict']['CHSUM_FIELD'][2:]):
        print("CRC32 error.")
        return None

    return fru_dict


def parse_ipmi_fru_bin(data, verbose):
    retcode = 1
    ipmi_fru_exec_path_list = ["/usr/sbin/ipmi-fru", "/usr/bin/ipmi-fru"]
    # Create a binary temporary file, read/write, not deleted automatically
    with tempfile.NamedTemporaryFile(mode='w+b') as tmp:
        # Write some binary data
        tmp.write(data)
        # Move cursor to the beginning for reading
        tmp.seek(0)
        ipmi_fru_path = shutil.which("ipmi-fru")
        if not ipmi_fru_path:
            for path in ipmi_fru_exec_path_list:
                if os.path.exists(path):
                    ipmi_fru_path = path
                    break
        print("ipmi_fru_path: {}".format(ipmi_fru_path))
        if ipmi_fru_path:
            cmd = [ipmi_fru_path, "--fru-file={}".format(tmp.name)]
            print("cmd: {}".format(cmd))
            try:
                result = subprocess.run(cmd, capture_output=True, text=True)
                output_str = result.stdout.strip()   # Command's standard output
                retcode = result.returncode          # Command's return code
                print("output_str: {}".format(output_str))
            except Exception as e:
                return None

    if not retcode:
        output_str = output_str.split("\n")[2:]
        output_str = "\n".join(output_str)
        return {'items': [["", output_str]]}
    else:
        return None


def parse_fru_bin(data, VPD_TYPE, verbose):
    res = None
    if VPD_TYPE in globals().keys():
        FRU_ITEMS = globals()[args.vpd_type]
    else:
        FRU_ITEMS = {"type": None}

    if FRU_ITEMS["type"] == "ONIE":
        res = parse_fru_onie_bin(data, FRU_ITEMS, verbose)
    elif FRU_ITEMS["type"] == "MLNX":
        res = parse_fru_mlnx_bin(data, FRU_ITEMS, verbose)
    elif FRU_ITEMS["type"] == "FIXED_FILED_VPD":
        res = parse_fru_fixed_fields_bin(data, FRU_ITEMS, verbose)
    else:
        res = parse_fru_onie_bin(data, SYSTEM_VPD, verbose)
        if not res:
            res = parse_fru_mlnx_bin(data, MLNX_VENDOR_BLK, verbose)
        if not res:
            res = parse_ipmi_fru_bin(data, verbose)

    return res


def dump_fru(fru_dict):
    """
    @summary: Print to screen contents of FRU
    @param fru_dict: parsed fru dictionary
    @return: None
    """
    for item in fru_dict['items']:
        if item[0]:
            print("{:<25}{}".format(item[0] + ":", str(item[1]).rstrip()))
        else:
            print("{}".format(str(item[1]).rstrip()))


def save_fru(fru_dict, out_filename):
    """
    @summary: Save to file contents of FRU
    @param fru_dict: parsed fru dictionary
    @param out_filename: output filename
    @return: None
    """
    try:
        out_file = open(out_filename, 'w+')
    except IOError as err:
        print("I/O error({0}): {1} with log file {2}".format(err.errno,
                                                             err.strerror,
                                                             out_filename))
    for item in fru_dict['items']:
        if item[0]:
            out_file.write("{:<25}{}\n".format(item[0] + ":", str(item[1]).rstrip()))
        else:
            out_file.write("{}\n".format(str(item[1]).rstrip()))

    out_file.close()


def load_fru_bin(file_name):
    """
    @summary: Load binary data from input file
    @param file_name: input file filename
    @return: binary data array or None in case of loading error
    """
    if not file_name:
        return None

    if not os.path.isfile(file_name):
        pathname = os.path.dirname(file_name)
        if pathname == "":
            pathname = os.path.dirname(os.path.realpath(__file__))
            file_name = pathname + "/" + file_name

    if not os.path.isfile(file_name):
        return None

    fru_file = open(file_name, 'rb')
    data_bin = fru_file.read(MAX_VPD_DATA_SIZE)

    return data_bin


def check_crc32(data_bin, crc32):
    'Calculate and compare CRC32 '
    crcvalue = 0
    crcvalue = zlib.crc32(data_bin, 0)
    crcvalue_str = format(crcvalue & 0xFFFFFFFF, '08x')
    if crcvalue_str.upper() != crc32:
        return 1
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Read and convert FRU binary file to human readable format")
    parser.add_argument('-i', '--input_file', dest='input', required=True, help='FRU binary file name', default=None)
    parser.add_argument('-o', '--output_file', dest='output', required=False, help='File to output parsed FRU fields', default=None)
    parser.add_argument('-t', '--type', dest='vpd_type', required=False, help='VPD type', default="Auto", choices=["Auto",
                                                                                                                   "LC_VPD",
                                                                                                                   "SYSTEM_VPD",
                                                                                                                   "MLNX_CPU_VPD",
                                                                                                                   "MLNX_FAN_VPD",
                                                                                                                   "FIXED_FIELD_FAN_VPD",
                                                                                                                   "MLNX_PDB_VPD",
                                                                                                                   "MLNX_CARTRIDGE_VPD"])
    parser.add_argument('--verbose', dest='verbose', required=False, default=0, help=argparse.SUPPRESS)
    parser.add_argument("--version", action="version", version="%(prog)s ver:{}".format(VERSION))
    args = parser.parse_args()

    if not args.input:
        print("Input file not specified")
        sys.exit(1)

    fru_data_bin = load_fru_bin(args.input)
    if not fru_data_bin:
        print("Can't pasrse inpuf binary.")
        sys.exit(1)

    fru_data_dict = parse_fru_bin(fru_data_bin, args.vpd_type, args.verbose)
    if not fru_data_dict:
        print("FRU parse error or wrong FRU file contents.")
        sys.exit(1)

    if args.output:
        save_fru(fru_data_dict, args.output)
    else:
        dump_fru(fru_data_dict)
    sys.exit(0)
