#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# Copyright (c) 2021-2023 NVIDIA CORPORATION & AFFILIATES.
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

Description:
Delta and Acbel PSU FW update tool.

'''
import time
import array
import argparse
import os

import hw_management_psu_fw_update_common as psu_upd_cmn

MFR_FWUPLOAD_MODE = 0xd6
MFR_FWUPLOAD = 0xd7
MFR_FWUPLOAD_STATUS = 0xd2
MFR_FW_REVISION = 0xd5

MFR_FWUPLOAD_STATUS_ACBEL = 0xd8
MFR_FW_REVISION_ACBEL = 0xd9

MFR_FWUPLOAD_MODE_ACBEL_460 = 0xfa
MFR_FWUPLOAD_ACBEL_460 = 0xfb
MFR_FWUPLOAD_STATUS_ACBEL_460 = 0xfc
MFR_FW_REVISION_ACBEL_460 = 0xd9

# Delta 550 PSU Model
MFR_MODEL_500AB = "DPS-550AB"

# Acbel 2000 PSU Models
MFR_MODEL_ACBEL_2000_FWD="FSP016-9G0G"
MFR_MODEL_ACBEL_2000_REV="FSP017-9G0G"

# Acbel 1100 PSU Models
MFR_MODEL_ACBEL_1100_FWD="FSP007-9G0G"
MFR_MODEL_ACBEL_1100_REV="FSN022-9G0G"

# Acbel 460 PSU Models
MFR_MODEL_ACBEL_460_FWD="FSF008-9G0G"
MFR_MODEL_ACBEL_460_REV="FSF007-9G0G"

def mfr_model_is_acbel(mfr_model):
    """
    @summary: Check if PSU model is Acbel 1100 or 2000.
    """
    if mfr_model.startswith(MFR_MODEL_ACBEL_2000_FWD) or mfr_model.startswith(MFR_MODEL_ACBEL_2000_REV) or \
       mfr_model.startswith(MFR_MODEL_ACBEL_1100_FWD) or mfr_model.startswith(MFR_MODEL_ACBEL_1100_REV):
        return True
    else:
        return False

def mfr_model_is_acbel_1100(mfr_model):
    """
    @summary: Check if PSU model is Acbel 1100
    """
    if mfr_model.startswith(MFR_MODEL_ACBEL_1100_FWD) or mfr_model.startswith(MFR_MODEL_ACBEL_1100_REV):
        return True
    else:
        return False

def mfr_model_is_acbel_2000(mfr_model):
    """
    @summary: Check if PSU model is Acbel 2000.
    """
    if mfr_model.startswith(MFR_MODEL_ACBEL_2000_FWD) or mfr_model.startswith(MFR_MODEL_ACBEL_2000_REV):
        return True
    else:
        return False

def mfr_model_is_acbel_460(mfr_model):
    """
    @summary: Check if PSU model is Acbel 460.
    """
    if mfr_model.startswith(MFR_MODEL_ACBEL_460_FWD) or mfr_model.startswith(MFR_MODEL_ACBEL_460_REV):
        return True
    else:
        return False

def read_mfr_fw_revision(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_FW_REVISION.
    """
    mfr_model = psu_upd_cmn.pmbus_read_mfr_model(i2c_bus, i2c_addr)
    if mfr_model.startswith(MFR_MODEL_500AB):
        ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FW_REVISION, 8)
    elif mfr_model_is_acbel_1100(mfr_model):
        ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FW_REVISION_ACBEL, 4)
        if ret != '' and len(ret) > 3 and ret[:2] == '0x':
            int_list = ret.split()
            int_list = int_list[1:3]
            int_list.reverse()
            ascii_str = '.'.join(str(int(i, 16)) for i in int_list)
            return ascii_str
    elif mfr_model_is_acbel_460(mfr_model):
        ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FW_REVISION_ACBEL, 5)
        if ret != '' and len(ret) > 3 and ret[:2] == '0x':
            int_list = ret.split()
            int_list = int_list[1:5]
            ver_list = [int_list[1], int_list[0], int_list[3], int_list[2]]
            ascii_str = '.'.join(str(int(i, 16)) for i in ver_list)
            return ascii_str
    elif mfr_model_is_acbel_2000(mfr_model):
        ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FW_REVISION_ACBEL, 6)
    else:
        ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FW_REVISION, 6)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        ascii_str = ''.join(chr(int(i, 16)) for i in ret.split())
        return ascii_str


UPLOAD_STATUS_DICT = {
    0: "Reset: all bits get reset to 0 when the power supply enters FW upload mode.",
    1 << 0: "Full image received.",
    1 << 1: "Full image not received yet. The PSU will keep this bit asserted until the full image is received by the PSU.",
    1 << 2: "Full image received but image is bad or corrupt. Power supply can power ON, but only in safe mode with minimal operating capability.",
    1 << 3: "Full image received but image is bad or corrupt. Power supply can power ON and support full features.",
    1 << 4: "FW image not supported by PSU. If the PSU receives the image header and determines that the PSU HW does \
    not support the image being sent by the system; it shall not accept the image and it shall assert this bit.",
    }

UPLOAD_STATUS_DICT_ACBEL_460 = {
    0x51: "ISP Mode Disabled",
    0x30: "ISP No Error",
    0x31: "ISP Checksum Error",
    0x32: "ISP Write to flash Error",
    0x33: "ISP Incorrect Image",
    0x35: "ISP Incorrect Image Checksum",
    0x36: "ISP Busy",
    0x37: "ISP Timeout",
     }

def read_mfr_fw_upload_status(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_FW_UPLOAD_STATUS.
    """
    mfr_model = psu_upd_cmn.pmbus_read_mfr_model(i2c_bus, i2c_addr)
    if mfr_model_is_acbel(mfr_model):
        mfr_upload_status_cmd = MFR_FWUPLOAD_STATUS_ACBEL
    else:
        mfr_upload_status_cmd = MFR_FWUPLOAD_STATUS
    ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, mfr_upload_status_cmd, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upload_status = UPLOAD_STATUS_DICT.get(int(ret, 16))
        print(upload_status)
        return upload_status

def read_mfr_fw_upload_status_acbel_460(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_FW_UPLOAD_STATUS.
    """
    ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FWUPLOAD_STATUS_ACBEL_460, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upload_status = UPLOAD_STATUS_DICT_ACBEL_460.get(int(ret, 16))
        return upload_status

UPLOAD_MODE_DICT = {
    0: "Exit firmware upload mode.",
    1 << 0: "Enter Firmware upload mode."
    }


def read_mfr_fw_upload_mode(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_FW_UPLOAD_MODE.
    """
    ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FWUPLOAD_MODE, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upload_mode = UPLOAD_MODE_DICT.get(int(ret, 16))
        print(upload_mode)
        return upload_mode

def read_mfr_fw_upload_mode_acbel_460(i2c_bus, i2c_addr):
    """
    @summary: Read MFR_FW_UPLOAD_MODE.
    """
    ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, MFR_FWUPLOAD_MODE_ACBEL_460, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upload_mode = UPLOAD_MODE_DICT.get(int(ret, 16))
        print(upload_mode)
        return upload_mode

def write_mfr_fw_upload_mode(i2c_bus, i2c_addr, mode):
    """
    @summary: Write MFR_FW_UPLOAD_MODE.
    """
    data = [MFR_FWUPLOAD_MODE]
    data.extend([mode])
    psu_upd_cmn.pmbus_write(i2c_bus, i2c_addr, data)

def write_mfr_fw_upload_mode_acbel_460(i2c_bus, i2c_addr, mode):
    """
    @summary: Write MFR_FW_UPLOAD_MODE.
    """
    data = [MFR_FWUPLOAD_MODE_ACBEL_460]
    data.extend([mode])
    psu_upd_cmn.pmbus_write(i2c_bus, i2c_addr, data)

def write_mfr_fw_upload(i2c_bus, i2c_addr, data_in):
    """
    @summary: Write MFR_FW_UPLOAD.
    """
    data = [MFR_FWUPLOAD]
    data.extend(data_in)
    psu_upd_cmn.pmbus_write(i2c_bus, i2c_addr, data)

def write_mfr_fw_upload_acbel_460(i2c_bus, i2c_addr, data_in):
    """
    @summary: Write MFR_FW_UPLOAD.
    """
    data = [MFR_FWUPLOAD_ACBEL_460]
    data.extend(data_in)
    psu_upd_cmn.pmbus_write(i2c_bus, i2c_addr, data)

FW_HEADER = {
    "model_name":"",
    "fw_revision":[],
    "hw_revision":"",
    "block_size":64,
    "write_time":120
    }


def parce_header_delta(data_list):
    """
    @summary: Parse Delta FW file header.
    """
    FW_HEADER["model_name"] = "".join(chr(x) for x in data_list[10:22])
    FW_HEADER["fw_revision"] = data_list[23:26]
    FW_HEADER["hw_revision"] = "".join("{0:c}{1:c}".format(data_list[26], data_list[27]))
    FW_HEADER["block_size"] = data_list[29] * 256 + data_list[28]
    FW_HEADER["write_time"] = data_list[31] * 256 + data_list[30]
    print(FW_HEADER)


def parce_header_acbel(data_list):
    """
    @summary: Parse Acbel FW file header.
    """
    FW_HEADER["model_name"] = "".join(chr(x) for x in data_list[10:20])
    FW_HEADER["fw_revision"] = data_list[23:26]
    FW_HEADER["hw_revision"] = ".".join(chr(x) for x in data_list[26:28])
    FW_HEADER["block_size"] = data_list[29] * 256 + data_list[28]
    FW_HEADER["write_time"] = data_list[31] * 256 + data_list[30]
    print(FW_HEADER)


def delta_fw_file_burn(i2c_bus, i2c_addr, fw_filename):
    """
    @summary: Burn Delta fw file.
    """
    fw_filesize = os.path.getsize(fw_filename)
    with open(fw_filename, "rb") as fw_file:
        while True:
            byte_array = array.array('B')
            try:
                byte_array.fromfile(fw_file, FW_HEADER["block_size"])
            except EOFError:
                break
            psu_upd_cmn.progress_bar((fw_file.tell()*100)/fw_filesize, 100)

            data_list = [FW_HEADER["block_size"]]
            data_list.extend(byte_array.tolist())
            write_mfr_fw_upload(i2c_bus, i2c_addr, data_list)
            # Wait delay
            time.sleep(FW_HEADER["write_time"] * 0.001)
        print("\nSend FW Done.")


def acbel_460_fw_file_burn(i2c_bus, i2c_addr, fw_filename):
    """
    @summary: Burn Acbel 460 FW file.
    """
    offs = 0
    fw_filesize = os.path.getsize(fw_filename)
    with open(fw_filename, "rb") as fw_file:
        while True:
            byte_array = array.array('B')
            try:
                byte_array.fromfile(fw_file, 16)
            except EOFError:
                break
            psu_upd_cmn.progress_bar((fw_file.tell()*100)/fw_filesize, 100)

            data_list = [(offs & 0xff000000) >> 24, (offs & 0x00ff0000) >> 16, (offs & 0x0000ff00) >> 8, offs & 0x000000ff]
            data_list.extend(byte_array.tolist())

            # Send data and read status
            retry_cnt = 0
            while True:
                write_mfr_fw_upload_acbel_460(i2c_bus, i2c_addr, data_list)
                # Wait delay
                time.sleep(50 * 0.001)

                status = read_mfr_fw_upload_status_acbel_460(i2c_bus, i2c_addr)
                if status == "ISP No Error":
                    break
                if retry_cnt >= 2:
                    print("Failed to send FW data")
                    print(status)
                    return
                retry_cnt += 1

            offs += 16
        print("\nSend FW Done.")

def update_delta(i2c_bus, i2c_addr, fw_filename):
    """
    @summary: Update Delta PSU FW.
    """
    # Validate we need update FW
    current_fw_rev = read_mfr_fw_revision(i2c_bus, i2c_addr)
    print(current_fw_rev)

    retry_cnt = 0
    while True:
        # Put PSU into FW update mode.
        write_mfr_fw_upload_mode(i2c_bus, i2c_addr, 1)

        time.sleep(1)

        if read_mfr_fw_upload_mode(i2c_bus, i2c_addr) != "Enter Firmware upload mode.":
            if retry_cnt >= 2:
                print("Fail to enter FW upload mode.")
                exit(1)
            retry_cnt += 1
            continue

        with open(fw_filename, "rb") as fw_file:
            byte_array = array.array('B')
            try:
                byte_array.fromfile(fw_file, 32)
            except EOFError:
                print("Fail read FW header.")
                exit(1)
            data_list = byte_array.tolist()
            mfr_model = psu_upd_cmn.pmbus_read_mfr_model(i2c_bus, i2c_addr)
            # Read FW image header for blocksize and delay time.
            if mfr_model_is_acbel(mfr_model):
                parce_header_acbel(data_list)
            else:
                parce_header_delta(data_list)

            # Write FW
            delta_fw_file_burn(i2c_bus, i2c_addr, fw_filename)

        # Read FW Upload status.
        if read_mfr_fw_upload_status(i2c_bus, i2c_addr) == "Full image received.":
            # Put PSU back to normal mode
            write_mfr_fw_upload_mode(i2c_bus, i2c_addr, 0)

            time.sleep(120)
            # Check FW revision changed. if no - fail.
            new_fw_rev = read_mfr_fw_revision(i2c_bus, i2c_addr)
            print(new_fw_rev)
            if new_fw_rev != current_fw_rev:
                print("FW Update successful.")
                exit(0)
            else:
                print("FW version not changed.")
                exit(1)

        else:
            # Put PSU back to normal mode
            write_mfr_fw_upload_mode(i2c_bus, i2c_addr, 0)
            if retry_cnt >= 2:
                print("Fail to enter FW upload mode.")
                exit(1)
        retry_cnt += 1


def update_acbel_460(i2c_bus, i2c_addr, fw_filename):
    """
    @summary: Update Acbel 460 PSU FW.
    """
    # Read current FW version
    current_fw_rev = read_mfr_fw_revision(i2c_bus, i2c_addr)
    print(current_fw_rev)

    # Put PSU into FW update mode.
    print("Entering FW upload mode")
    retry_cnt = 0
    while True:
        write_mfr_fw_upload_mode_acbel_460(i2c_bus, i2c_addr, 1)

        time.sleep(1)

        if read_mfr_fw_upload_status_acbel_460(i2c_bus, i2c_addr) == "ISP No Error":
            break
        if retry_cnt >= 2:
                print("Failed to enter FW upload mode.")
                exit(1)
        retry_cnt += 1

    # Write FW
    print("Sending data")
    acbel_460_fw_file_burn(i2c_bus, i2c_addr, fw_filename)

    # Put PSU back to normal mode
    print("Exiting FW upload mode")
    retry_cnt = 0
    while True:
        write_mfr_fw_upload_mode_acbel_460(i2c_bus, i2c_addr, 0)
        time.sleep(10)

        status = read_mfr_fw_upload_status_acbel_460(i2c_bus, i2c_addr)
        if (status == "ISP Mode Disabled") or (status == "ISP No Error"):
            break
        if retry_cnt >= 2:
                print("Failed to exit FW upload mode.")
                print(status)
                exit(1)
        retry_cnt += 1

    # Check FW revision changed. if no - fail.
    new_fw_rev = read_mfr_fw_revision(i2c_bus, i2c_addr)
    print(new_fw_rev)
    if new_fw_rev != current_fw_rev:
        print("FW Update successful.")
        exit(0)
    else:
        print("FW version not changed.")
        exit(1)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    required = parser.add_argument_group('required arguments')
    parser.add_argument('-i', "--input_file", required=False)
    required.add_argument('-b', "--i2c_bus", type=int, default=0, required=True)
    required.add_argument('-a', "--i2c_addr", type=lambda x: int(x, 0), default=0, required=True)
    parser.add_argument('-S', "--skip_redundancy_check", type=bool, nargs='?',
                        const=True, default=False)
    required.add_argument('-v', "--version", type=bool, nargs='?',
                        const=True, default=False)
    args = parser.parse_args()

    if args.version:
        fw_rev = read_mfr_fw_revision(args.i2c_bus, args.i2c_addr)
        print(fw_rev)
        exit(0)

    if not vars(args)['input_file']:
        parser.error('The --input_file(-i) is required')
        exit(1)

    psu_upd_cmn.pmbus_read_mfr_id(args.i2c_bus, args.i2c_addr)
    psu_upd_cmn.pmbus_read_mfr_model(args.i2c_bus, args.i2c_addr)
    psu_upd_cmn.pmbus_read_mfr_revision(args.i2c_bus, args.i2c_addr)

    if not args.skip_redundancy_check:
        psu_upd_cmn.check_psu_redundancy(False, args.i2c_addr)

    mfr_model = psu_upd_cmn.pmbus_read_mfr_model(args.i2c_bus, args.i2c_addr)
    if mfr_model_is_acbel_460(mfr_model):
        update_acbel_460(args.i2c_bus, args.i2c_addr, args.input_file)
    else:
        update_delta(args.i2c_bus, args.i2c_addr, args.input_file)
