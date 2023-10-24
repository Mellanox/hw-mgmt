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
import struct
import binascii
import zlib

#############################
# Global const
#############################
VERSION = '0.1'

# TLV header format
# struct {
#    char type;
#    char size;
#  };
TLV_FORMAT = ">BB"
TLV_FIELDS = ["type", "size"]

# FRU bin header format
FRU_SANITY_FORMAT = ">8sBH"
FRU_SANITY_FORMAT_FIELDS = ["tlv_header", "ver", "total_len"]

# MLNX header format
MLNX_HDR_FORMAT = ">IHBBBBH"
MLNX_HDR_FORMAT_FIELDS = ["IANA", "block_size", "major_ver", "minor_ver", "block_type", "cs", "reserved"]


# Supported FRU versions
SUPPORTED_FRU_VER = [1]

# FRU fields description
LC_VPD = { 2 : {'type_name': "PRODUCT_NAME_VPD_FIELD", "fn":"format_unpack", "format": "{}s"},
           3 : {'type_name': "PN_VPD_FIELD", "fn":"format_unpack", "format": "{}s"},
           4 : {'wtype_name': "SN_VPD_FIELD", "fn":"format_unpack", "format": "{}s"},
           5 : {'type_name': "MFG_DATE_FIELD", "fn":"format_unpack", "format": "{}s"},
           6 : {'type_name': "SW_REV_FIELD", "fn":"format_unpack", "format": "b"},
           7 : {'type_name': "HW_REV_FIELD", "fn":"format_unpack", "format": "b"},
           8 : {'type_name': "PORT_NUM_FIELD", "fn":"format_unpack", "format": "b"},
           9 : {'type_name': "PORT_SPEED_FIELD", "fn":"format_unpack", "format": ">i"},
           10: {'type_name': "MANUFACTURER_VPD_FIELD", "fn":"format_unpack", "format": "{}s"},
           11: {'type_name': "CHSUM_FIELD", "fn":"format_unpack", "format": ">I"}
          }

SYSTEM_VPD = { 33: {'type_name': "Product Name", "fn":"format_unpack", "format": "{}s"},
               34 : {'type_name': "Part Number", "fn":"format_unpack", "format": "{}s"},
               35 : {'type_name': "Serial Number", "fn":"format_unpack", "format": "{}s"},
               36 : {'type_name': "Base MAC Address", "fn":"format_unpack", "format": "{}s", "transform":"hex"},
               37 : {'type_name': "Manufacture Date", "fn":"format_unpack", "format": "{}s"},
               38 : {'type_name': "Device Version", "fn":"format_unpack", "format": "b"},
               39 : {'type_name': "Label Revision", "fn":"format_unpack", "format": "{}s"},
               40 : {'type_name': "Platform Name", "fn":"format_unpack", "format": "{}s"},
               41 : {'type_name': "ONIE Version", "fn":"format_unpack", "format": "{}s"},
               42 : {'type_name': "MAC Addresses", "fn":"format_unpack", "format": ">h"},
               43 : {'type_name': "Manufacturer", "fn":"format_unpack", "format": "{}s"},
               45 : {'type_name': "Vendor", "fn":"format_unpack", "format": "{}s "},
               47 : {'type_name': "Service Tag", "fn":"format_unpack", "format": "{}s"},
               253: {'type_name': "Vendor Extension", "fn" : "mlnx_vendor_unpack"},
               254: {'type_name': "CHSUM_FIELD", "fn":"format_unpack", "format": ">I"}
              }

MLNX_VENDOR_BLK = {
    0 : {'blk_type': "BASE", "format": [
            ["SANITIFIER", 1, 8,  4, "FIT_NORMAL", "DT_ASCII"],
            ["B1START",    1, 12, 1, "FIT_NORMAL", "DT_NUM"],
            ["B1TYPE",     1, 12, 1, "FIT_NORMAL", "DT_NUM"]
        ]},
    1 : {'blk_type': "MFG", "fn": "mlnx_blk_unpack", "format": [
            ["SN_VPD_FIELD",  1,  8, 24,  "FIT_NORMAL", "FT_ASCII"],
            ["PN_VPD_FIELD",  1, 32, 20,  "FIT_NORMAL", "FT_ASCII"],
            ["REV_VPD_FIELD", 1, 52, 4,   "FIT_NORMAL", "FT_ASCII"],
            ["RESERVED",      1, 56, 1,   "FIT_NORMAL", "FT_RESERVED"],
            ["MFG_DATE",    1, 57, 3,   "FIT_NORMAL", "FT_NUM"],
            ["PROD_NAME",   1, 60, 64,  "FIT_NORMAL", "FT_ASCII"],
            ["HW_MGT_ID",     2, 124, 3,  "FIT_NORMAL", "FT_NUM"],
            ["HW_MGT_REV",    2, 127, 1,  "FIT_NORMAL", "FT_NUM"],
            ["SW_MGT_ID",     3, 128, 4,  "FIT_NORMAL", "FT_NUM"],
            ["SYS_DISPLAY",   3, 132, 16, "FIT_NORMAL", "FT_ASCII"]
        ]},
    2 : {'blk_type': "GUIDS", "fn": "mlnx_blk_unpack", "format": [
            ["GUID_TYPE",   1, 8,  1, "FIT_NORMAL", "FT_NUM"],
            ["RESERVED",    2, 9, 7,  "FIT_NORMAL", "FT_RESERVED"],
            ["PRE_UID",     1, 16, 8, "FIT_COMP",   "FT_NUM"]
        ]},
    3 : {'blk_type': "CPUDATA"},
    4 : {'blk_type': "OSBOOT"},
    5 : {'blk_type': "HWCHAR", "fn": "mlnx_blk_unpack", "format": [
            ["MAX_POWER",      1, 8,  2, "FIT_NORMAL", "FT_NUM"],
            ["CRIT_AMB_TEMP",  1, 10, 1, "FIT_NORMAL", "FT_NUM"],
            ["CRIT_IC_TEMP",   1, 11, 1, "FIT_NORMAL", "FT_NUM"],
            ["ALERT_AMB_TEMP", 1, 12, 1, "FIT_NORMAL", "FT_NUM"],
            ["ALERT_IC_TEMP",  1, 13, 1, "FIT_NORMAL", "FT_NUM"],
            ["FAN_DIR_FIELD",  2, 14, 1, "FIT_NORMAL", "FT_NUM"],
            ["LENGTH",         3, 15, 1, "FIT_NORMAL", "FT_NUM"],
            ["WIDTH",          3, 16, 1, "FIT_NORMAL", "FT_NUM"],
            ["LED",            3, 17, 1, "FIT_NORMAL", "FT_NUM"]
        ]},
    6 : {'blk_type': "LIC", "fn": "mlnx_blk_unpack", "format": [
            ["PRE_LIC", 1, 8, 1, "FIT_COMP", "FT_NUM"]
        ]},
    7 : {'blk_type': "EKEYING", "fn": "mlnx_blk_unpack", "format": [
            ["RESERVED",          1, 8,  1,  "FIT_NORMAL", "FT_RESERVED"],
            ["NUM_SCHEME",        1, 9,  1,  "FIT_NORMAL", "FT_NUM"],
            ["EN_PORTS_NUM",      1, 10, 1,  "FIT_NORMAL", "FT_NUM"],
            ["PORTS_INC_SCHEME",  1, 11, 1,  "FIT_NORMAL", "FT_NUM"],
            ["PRE_PORT_INC",      1, 12, 1, "FIT_COMP",   "FT_NUM"]
        ]},
    8 : {'blk_type': "MIN_FIT"},
    9 :  {'blk_type': "PORT_CFG"},
    10 : {'blk_type': "VENDOR_ID"},
    11 : {'blk_type': "MFG_INTERNAL"},
    12 : {'blk_type': "PSU"}
}
MLNX_VENDOR_BLK_FIELDS = ["name", "minor_version", "offset", "length", "info_type", "type"]

bin_decode = lambda val: val.decode('ascii').rstrip('\x00') if isinstance(val,bytes) else val
int_unpack_be = lambda val: sum([b * 2**(8*n) for (b, n) in zip(val, range(len(val))[::-1])])


def format_unpack(_data, item, blk_header):
    item_format = item['format'].format(blk_header['size'])
    val = struct.unpack(item_format, _data)[0]
    if isinstance(val, str):
        val = val.split('\x00', 1)[0]
    elif 'I' in item_format:
        val =  "{0:#0{1}x}".format(val,10).upper()

    if "transform" in item.keys():
        transform = item["transform"]
        if transform == "hex":
            val = binascii.hexlify(val)
    val = bin_decode(val)
    return val


def mlnx_blk_unpack(data, item, size):
    if "format" not in item.keys():
        return "-"
    block_format = item["format"]
    res_str = ""
    for rec in block_format:
        rec_dict = dict(list(zip(MLNX_VENDOR_BLK_FIELDS, rec)))
        rec_type = rec_dict["type"]
        if rec_type == "FT_RESERVED":
            continue

        rec_size = rec_dict["length"]
        rec_offset = rec_dict["offset"] - 8
        if rec_offset+rec_size >= size:
            break
        _data = data[rec_offset  : rec_offset+rec_size]
        if rec_type == "FT_ASCII":
            item_format = "{}s".format(rec_size)
            val = struct.unpack(item_format, _data)[0]
        elif rec_type == "FT_NUM":                
            _data_str = struct.unpack("{}B".format(rec_size), _data)
            val = int_unpack_be(_data_str)
        res_str += "{:<20}{}\n".format(rec_dict["name"], bin_decode(val))
    return res_str


def mlnx_vendor_unpack(data, item, blk_header):
    blk_header, hdr_size = parse_packed_data(data, MLNX_HDR_FORMAT, MLNX_HDR_FORMAT_FIELDS)
    blk_id  = blk_header["block_type"]
    val = "Not support\n"
    if blk_id in MLNX_VENDOR_BLK.keys():
        blk_item = MLNX_VENDOR_BLK[blk_id]
        fn_name = blk_item.get("fn", None) 
        if fn_name:
            _data = data[hdr_size  : hdr_size+blk_header['block_size']]
            val = globals()[fn_name](_data, blk_item, blk_header['block_size'])
        str = "\n=== {} ==\n{}".format(blk_item["blk_type"], val)
    return  str


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
        if isinstance(val,  str):
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

def parse_fru_bin(data, FRU_ITEMS):
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
    tlv_header = bin_decode(fru_dict['tlv_header'])
    if 'TlvInfo' not in tlv_header and fru_dict['ver'] not in SUPPORTED_FRU_VER:
        print("Not supported FRU format")
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
            _data = data[pos : pos+blk_header['size']] 
            val = globals()[fn_name](_data, item, blk_header)
            fru_dict['items'].append([item['type_name'], val])
            fru_dict['items_dict'][item['type_name']] = val

        pos += blk_header['size']
    return fru_dict

def dump_fru(fru_dict):
    """
    @summary: Print to screen contents of FRU
    @param fru_dict: parsed fru dictionary
    @return: None
    """
    for item in fru_dict['items']:
        print("{}: {}".format(item[0], item[1]))

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
        out_file.write("{}: {}\n".format(item[0], item[1]))

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
    data_bin = fru_file.read()

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
    parser.add_argument('-t', '--type', dest='vpd_type', required=False, help='VPD type', default="SYSTEM_VPD", choices=["LC_VPD","SYSTEM_VPD"])
    parser.add_argument('-v', '--version', dest='version', required=False, help='show version', action='store_const', const=True)
    args = parser.parse_args()

    if args.version:
        print("This is FRU converting tool. Version {}".format(VERSION))
        sys.exit(0)

    if not args.input:
        print("Input file not specified")
        sys.exit(1)

    fru_data_bin = load_fru_bin(args.input)
    if not fru_data_bin:
        print("Input file read error.")
        sys.exit(1)

    fru_data_dict = parse_fru_bin(fru_data_bin, globals()[args.vpd_type])
    if not fru_data_dict:
        print("FRU parse error or wrong FRU file contents.")
        sys.exit(1)

    if check_crc32(fru_data_bin[ : fru_data_dict['total_len']+7],
                   fru_data_dict['items_dict']['CHSUM_FIELD'][2:]):
        print("CRC32 error.")
        sys.exit(1)

    if args.output:
        save_fru(fru_data_dict, args.output)
    else:
        dump_fru(fru_data_dict)
    sys.exit(0)