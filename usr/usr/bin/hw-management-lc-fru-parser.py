#!/usr/bin/python

# pylint: disable=line-too-long
# pylint: disable=C0103

########################################################################
# Copyright (c) 2020 Mellanox Technologies. All rights reserved.
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
FRU_SANITY_FORMAT = "8sBB"
FRU_SANITY_FORMAT_FIELDS = ["tlv_header", "ver", "total_len"]

# Supported FRU versions
SUPPORTED_FRU_VER = [1]

# FRU fields description
LC_FRU_ITEMS_FORMAT = {2 : {'type_name': "PRODUCT_NAME_VPD_FIELD", "format": "{}s"},
                3 : {'type_name': "PN_VPD_FIELD", "format": "{}s"},
                4 : {'type_name': "SN_VPD_FIELD", "format": "{}s"},
                5 : {'type_name': "MFG_DATE_FIELD", "format": "{}s"},
                6 : {'type_name': "SW_ID_FIELD", "format": "b"},
                7 : {'type_name': "HW_REV_FIELD", "format": "b"},
                8 : {'type_name': "PORT_NUM_FIELD", "format": "b"},
                9 : {'type_name': "PORT_SPEEDFIELD", "format": "I"},
                10: {'type_name': "MANUFACTURER_VPD_FIELD", "format": "{}s"},
                11: {'type_name': "MAX_POWER_FIELD", "format": "{}s"},
                16: {'type_name': "CHSUM_FIELD", "format": "i"}
               }

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
    res_dict = dict(zip(fields, unpack_res))
    for key, val in res_dict.items():
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
    if res_dict['size'] > 128:
        return None, 0

    return res_dict, size

def parse_fru_bin(data):
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
    if 'TlvInfo' not in fru_dict['tlv_header'] and fru_dict['ver'] not in SUPPORTED_FRU_VER:
        print "Not supported FRU format"
        return None

    fru_dict['items'] = []
    pos = 0
    while pos < fru_dict['total_len']:
        blk_header, header_size = fru_get_tlv_header(data[pos + offset:])
        pos += header_size
        if blk_header['type'] not in LC_FRU_ITEMS_FORMAT.keys():
            print "Not supported item type {}".format(blk_header['type'])
            continue
        item = LC_FRU_ITEMS_FORMAT[blk_header['type']]
        item_format = item['format'].format(blk_header['size'])

        _data = data[pos+offset : pos+offset+blk_header['size']]
        val = struct.unpack(item_format, _data)[0]

        if isinstance(val, str):
            val = val.split('\x00', 1)[0]
        elif 'i' in item_format:
            val = hex(val)
        fru_dict['items'].append([item['type_name'], val])
        pos += blk_header['size']

    return fru_dict

def dump_fru(fru_dict):
    """
    @summary: Print to screen contents of FRU
    @param fru_dict: parsed fru dictionary
    @return: None
    """
    for item in fru_dict['items']:
        print "{}: {}".format(item[0], item[1])

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
        print "I/O error({0}): {1} with log file {2}".format(err.errno,
                                                             err.strerror,
                                                             out_filename)
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

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Read and convert FRU binary file to human readable format")
    parser.add_argument('-i', '--input_file', dest='input', required=False, help='FRU binary file name', default=None)
    parser.add_argument('-o', '--output_file', dest='output', required=False, help='File to output parsed FRU fields', default=None)
    parser.add_argument('-v', '--version', dest='version', required=False, help='show version', action='store_const', const=True)
    args = parser.parse_args()

    if args.version:
        print "This is FRU converting tool. Version {}".format(VERSION)
        sys.exit(0)

    if not args.input:
        print "Input file not specified"
        sys.exit(1)

    fru_data_bin = load_fru_bin(args.input)
    if not fru_data_bin:
        print "Input file read error."
        sys.exit(1)

    fru_dict = parse_fru_bin(fru_data_bin)
    if not fru_dict:
        print "FRU parse error or wrong FRU file contents."
        sys.exit(1)

    if args.output:
        save_fru(fru_dict, args.output)
    else:
        dump_fru(fru_dict)
    sys.exit(0)
