#!/usr/bin/python
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
Delta PSU FW update tool.

'''
import sys, time, array, argparse

import hw_mgmt_psu_fw_update_common as hw_mgmt_pmbus

mfr_fwupload_mode = 0xd6
mfr_fwupload = 0xd7
mfr_fwupload_status = 0xd2
mfr_fwupload_revision = 0xd5


def read_mfr_fw_revision(i2c_bus, i2c_addr):
    ret = hw_mgmt_pmbus.pmbus_read(i2c_bus, i2c_addr, mfr_fwupload_revision, 8)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        ascii_str = ''.join(chr(int(i, 16)) for i in ret.split())
        print(ascii_str)
        return ascii_str


upload_status_dict = {
    0: "Reset: all bits get reset to 0 when the power supply enters FW upload mode.",
    1 << 0: "Full image received.",
    1 << 1: "Full image not received yet. The PSU will keep this bit asserted until the full image is received by the PSU.",
    1 << 2: "Full image received but image is bad or corrupt. Power supply can power ON, but only in safe mode with minimal operating capability.",
    1 << 3: "Full image received but image is bad or corrupt. Power supply can power ON and support full features.",
    1 << 4: "FW image not supported by PSU. If the PSU receives the image header and determines that the PSU HW does \
    not support the image being sent by the system; it shall not accept the image and it shall assert this bit.",
    }


def read_mfr_fw_upload_status(i2c_bus, i2c_addr):
    ret = hw_mgmt_pmbus.pmbus_read(i2c_bus, i2c_addr, mfr_fwupload_status, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upload_status = upload_status_dict.get(int(ret, 16))
        print(upload_status)
        return upload_status


upload_mode_dict = {
    0: "Exit firmware upload mode.",
    1 << 0: "Enter Firmware upload mode."
    }


def read_mfr_fw_upload_mode(i2c_bus, i2c_addr):
    ret = hw_mgmt_pmbus.pmbus_read(i2c_bus, i2c_addr, mfr_fwupload_mode, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upload_mode = upload_mode_dict.get(int(ret, 16))
        print(upload_mode)
        return upload_mode


def write_mfr_fw_upload_mode(i2c_bus, i2c_addr, mode):
    data = [mfr_fwupload_mode]
    data.extend([mode])
    hw_mgmt_pmbus.pmbus_write(i2c_bus, i2c_addr, data)


def write_mfr_fw_upload(i2c_bus, i2c_addr, data_in):
    data = [mfr_fwupload]
    data.extend(data_in)
    hw_mgmt_pmbus.pmbus_write(i2c_bus, i2c_addr, data)
    

fw_header = {
    "model_name":"",
    "fw_revision":[],
    "hw_revision":"",
    "block_size":64,
    "write_time":120
    }


def parce_header(data_list):
    fw_header["model_name"] = "".join(chr(x) for x in data_list[10:22])
    fw_header["fw_revision"] = data_list[23:26]
    fw_header["hw_revision"] = "".join("{0:c}{1:c}".format(data_list[26], data_list[27]))
    fw_header["block_size"] = data_list[29] * 256 + data_list[28]
    fw_header["write_time"] = data_list[31] * 256 + data_list[30]
    print(fw_header)


def delta_fw_file_burn(i2c_bus, i2c_addr, fw_filename):
    with open(fw_filename, "rb") as fp:
        while True:
            byte_array = array.array('B')
            try: byte_array.fromfile(fp, fw_header["block_size"])
            except EOFError: break
            data_list = [fw_header["block_size"]]
            data_list.extend(byte_array.tolist())
            write_mfr_fw_upload(i2c_bus, i2c_addr, data_list)
            # Wait delay
            time.sleep(fw_header["write_time"] * 0.001)


def update_delta(i2c_bus, i2c_addr, fw_filename):
    # Validate we need update FW
    current_fw_rev = read_mfr_fw_revision(i2c_bus, i2c_addr)

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

        with open(fw_filename, "rb") as fp:
            byte_array = array.array('B')
            try: byte_array.fromfile(fp, 32)
            except EOFError:
                print("Fail read FW header.")
                exit(1)
            data_list = byte_array.tolist()
            # Read FW image header for blocksize and delay time.
            parce_header(data_list)
    
            # Write FW
            delta_fw_file_burn(i2c_bus, i2c_addr, fw_filename)

        # Read FW Upload status.
        if read_mfr_fw_upload_status(i2c_bus, i2c_addr) == "Full image received.":
            # Put PSU back to normal mode
            write_mfr_fw_upload_mode(i2c_bus, i2c_addr, 0)

            time.sleep(120)
            # Check FW revision changed. if no - fail.
            new_fw_rev = read_mfr_fw_revision(i2c_bus, i2c_addr)
            if new_fw_rev != current_fw_rev:
                print("FW Update successfull.")
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


def main(argv):
    parser = argparse.ArgumentParser()
    required = parser.add_argument_group('required arguments')
    required.add_argument('-i', "--input_file", required=True)
    required.add_argument('-b', "--i2c_bus", type=int, default=0, required=True)
    required.add_argument('-a', "--i2c_addr", type=lambda x: int(x, 0), default=0, required=True)
    args = parser.parse_args()

    print('Input args "', args.input_file, args.i2c_bus, args.i2c_addr)

    hw_mgmt_pmbus.pmbus_read_mfr_id(args.i2c_bus, args.i2c_addr)
    hw_mgmt_pmbus.pmbus_read_mfr_model(args.i2c_bus, args.i2c_addr)
    hw_mgmt_pmbus.pmbus_read_mfr_revision(args.i2c_bus, args.i2c_addr)

    update_delta(args.i2c_bus, args.i2c_addr, args.input_file)


if __name__ == "__main__":
    main(sys.argv[1:])

