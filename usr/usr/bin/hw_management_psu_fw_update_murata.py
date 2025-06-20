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
Created on June 15, 2021

Author: Mykola Kostenok <c_mykolak@nvidia.com>
Version: 1.0

Description:
Murata PSU FW update tool.

'''
import os
import re
import time
import argparse
from textwrap import wrap

import hw_management_psu_fw_update_common as psu_upd_cmn

TOOL_VERSION = '1.0'
PS_STATUS_ADDR = 0xE0
UPGRADE_STATUS_ADDR = 0xFA
BOOTLOADER_STATUS_ADDR = 0xFB
BOOTLOADER_I2C_ADDR = 0x60


def read_murata_fw_revision(i2c_bus, i2c_addr, primary):
    """
    @summary: Read Murata PSU secondary revision.
    """
    if (primary):
        psu_upd_cmn.pmbus_page(i2c_bus, i2c_addr, 0)
    else:
        psu_upd_cmn.pmbus_page(i2c_bus, i2c_addr, 1)

    ret = psu_upd_cmn.pmbus_read_block(i2c_bus, i2c_addr, 0x9b)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        psu_upd_cmn.pmbus_page(i2c_bus, i2c_addr, 0)
        ascii_str = ''.join(chr(int(i, 16)) for i in ret.split())[1:]
        return ascii_str


def power_supply_reset(i2c_bus, i2c_addr):
    """
    @summary: send PSU reset.
    """
    data = [0xf8, 0xaf]
    if i2c_addr == BOOTLOADER_I2C_ADDR:
        psu_upd_cmn.pmbus_write_nopec(i2c_bus, i2c_addr, data)
    else:
        psu_upd_cmn.pmbus_write(i2c_bus, i2c_addr, data)


def end_of_file(i2c_bus, i2c_addr):
    """
    @summary: send PSU end of file.
    """
    data = [0xfa, 0x44, 0x01, 0x00]
    data.extend([0] * 32)
    data.extend([0x00, 0xc1])
    if i2c_addr == BOOTLOADER_I2C_ADDR:
        psu_upd_cmn.pmbus_write_nopec(i2c_bus, i2c_addr, data)
    else:
        psu_upd_cmn.pmbus_write(i2c_bus, i2c_addr, data)


def check_power_supply_status(i2c_bus, i2c_addr):
    """
    @summary: check power supply status.
    """
    ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, PS_STATUS_ADDR, 3)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        # print("check_power_supply_status: {}".format(ret))
        ps_status = [int(i, 16) for i in ret.split()]
        bootoader_mode = ps_status[1] & 1 << 2
        bootload_complette = ps_status[1] & 1 << 1
        power_down = ps_status[1] & 1 << 0
        print("bootoader_mode:{0}, bootload_complette:{1}, power_down:{2}".format(bootoader_mode, bootload_complette, power_down))


upgrade_status_dict = {
    0x18: "POLL_STATUS_FAILED",
    0x33: "POLL_STATUS_POWERDOWN",
    0x55: "POLL_STATUS_BUSY",
    0x81: "POLL_STATUS_SUCCSESS",
    0xaa: "POLL_STATUS_NOTACTIVE",
    # This indicates checksum check error in the payload in the packet that was just received.
    0x16: "POLL_STATUS_DATA_ERROR",
    # Data not recognized.
    0x10: "POLL_STATUS_INVALID_RECORD_TYPE"
}


def poll_upgrade_status(i2c_bus, i2c_addr):
    """
    @summary: poll upgrade status.
    """
    ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, UPGRADE_STATUS_ADDR, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upgrade_status = upgrade_status_dict.get(int(ret, 16), "POLL_STATUS_UNDEFINED")
        # print(upgrade_status)
        return upgrade_status


def test_poll_upgrade_status(i2c_bus, i2c_addr):
    """
    @summary: poll upgrade status with 3 reties.
    """
    retry = 0
    while True:
        upgrade_status = poll_upgrade_status(i2c_bus, i2c_addr)
        if (upgrade_status != "POLL_STATUS_BUSY") or (retry > 3):
            break
        time.sleep(0.3)
        retry += 1

    if upgrade_status != "POLL_STATUS_SUCCSESS":
        print("PSU FW upgrade failed.")
        exit(1)


bootloader_status_dict = {
    0: "BOOTLOADER_STATUS_NONE",
    1 << 0: "B0OTLOADING_PRIMARY",
    1 << 1: "BO0TLOADING_FLOATING",
    1 << 2: "BO0TLOADING_SECONDARY",
    1 << 3: "B0OTLOADING_PRIMARY_COMPLETED",
    1 << 4: "BO0TLOADING_FLOATING_COMPLETED",
    1 << 5: "BO0TLOADING_SECONDARY_COMPLETED",
    1 << 6: "RESET_PRIMARY_COMPLETED",
    1 << 7: "RESET_FLOATING_COMPLETED",
}


def bootloader_status(i2c_bus, i2c_addr):
    """
    @summary: read bootloader status.
    """
    ret = psu_upd_cmn.pmbus_read(i2c_bus, i2c_addr, BOOTLOADER_STATUS_ADDR, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        bl_status = bootloader_status_dict.get(int(ret, 16))
        print(bl_status)
        return bl_status


def two_complement_checksum(data):
    """
    @summary: calculate two complement checksum.
    """
    return -(sum(c for c in data) % 256) & 0xFF


def upgrade_data_command(i2c_bus, i2c_addr, data):
    """
    @summary: send upgrade data command.
    """
    send_data = [0xfa, 0x44, 0x0, 0x0]
    send_data.extend(data)
    res_chksum = two_complement_checksum(send_data)
    send_data.extend([0x0, res_chksum])
    # print(send_data)
    psu_upd_cmn.pmbus_write_nopec(i2c_bus, i2c_addr, send_data)


def burn_fw_file(i2c_bus, i2c_addr, fw_filename):
    """
    @summary: burn FW file.
    """
    data_flag = 0
    with open(fw_filename) as fp:
        lines = fp.readlines()
        for number, line in enumerate(lines):
            psu_upd_cmn.progress_bar(((number + 1) * 100) / len(lines), 100)
            if "[data]" in line:
                data_flag = 1
                continue
            if "[checksum]" in line:
                data_flag = 0
            if data_flag == 1:
                data = line.split("=")[1:]
                data_str = data[0].rstrip("\n")
                data_arr = [int(i, 16) for i in wrap(data_str, 2)]
                # print(data_str)
                upgrade_data_command(i2c_bus, i2c_addr, data_arr)
                test_poll_upgrade_status(i2c_bus, i2c_addr)
        print("\nSend FW Done.")


microtype_dict = {
    "MICROTYPE_PRIMARY": 0x50,
    "MICROTYPE_SECONDARY": 0x53,
    "MICROTYPE_FLOATING": 0x46,
}


def enter_bootload_mode(i2c_bus, i2c_addr, primary):
    """
    @summary: enter bootload mode.
    """
    data = [0xfa, 0x42]

    if (primary):
        data.extend([microtype_dict["MICROTYPE_PRIMARY"]])
    else:
        data.extend([microtype_dict["MICROTYPE_SECONDARY"]])

    data.extend([0x44, 0x41, 0x54, 0x50])
    if i2c_addr == BOOTLOADER_I2C_ADDR:
        psu_upd_cmn.pmbus_write_nopec(i2c_bus, i2c_addr, data)
    else:
        psu_upd_cmn.pmbus_write(i2c_bus, i2c_addr, data)


def murata_update(i2c_bus, i2c_addr, continue_update, fw_filename, primary):
    """
    @summary: Murata PSU update.
    """
    current_fw_rev = ""
    # If coninue_update skip entering to boot_mode.
    if not continue_update:
        # 1. Read current firmware revision using command the READ_MFG_FW_REVISION.
        current_fw_rev = read_murata_fw_revision(i2c_bus, i2c_addr, primary)
        print(current_fw_rev)

        check_power_supply_status(i2c_bus, i2c_addr)

        # 2. Send the ENTER_BOOTLOAD_MODE command during Normal Operation.
        enter_bootload_mode(i2c_bus, i2c_addr, primary)

        # fmt: off
        # 3. When the command is received.
            # a. The Power supply will enter a power down state, shutting down main power conversion.
                # i. Power Supply will respond POWER_DOWN.
            # b. Upon successful power down, the power supply enters Bootload Mode.
            # c. The power supply will change the PMBus address to 0x60 and erase the targeted microcontroller.
                # i. Power Supply will respond BUSY during the erase the process.
            # d. Wait for host to initiate data transfer.
                # i. Power Supply will respond SUCCESS while waiting for data.

        # 4. Wait typically for 1 second to allow the Power Supply to enter Bootload Mode.
        # fmt: on
        time.sleep(1)
    else:
        # Erase, since previous update failed.
        enter_bootload_mode(args.i2c_bus, BOOTLOADER_I2C_ADDR, primary)
        time.sleep(2)

    # 5. Send the POLL_UPGRADE_STATUS command for successful entry into Bootload Mode.
        # 5a. Send the Host POWER_DOWN, BUSY or SUCCESS.

    if poll_upgrade_status(i2c_bus, BOOTLOADER_I2C_ADDR) != "POLL_STATUS_SUCCSESS":
        print("failed to enter boot mode")
        exit(1)

    # 6. Send the PAGE command to get the microcontroller ready for the data dump.
    psu_upd_cmn.pmbus_page_nopec(i2c_bus, BOOTLOADER_I2C_ADDR, 0x01)

    # 7. For each line in the app file.
    burn_fw_file(i2c_bus, BOOTLOADER_I2C_ADDR, fw_filename)

    # 8. Send the END_OF_FILE command to the Power Supply.
    end_of_file(i2c_bus, BOOTLOADER_I2C_ADDR)

    # 9. Wait typically for 1 second to allow the Power Supply to enter Bootload Mode.
    time.sleep(2)

    # fmt: off
    # 10. Send the POLL_UPGRADE_STATUS command for a successful transaction.
        # 10a. The target microcontroller will do a soft reset and conducts a checksum test of the upgraded firmware.
        # 10b. If the checksum test passes, the target microcontroller will leave BOOTLOAD Mode and will respond NOT_ACTIVE.
        # 10c. If the checksum test fails, the target microcontroller remains in BOOTLOAD Mode and will response
        #     SUCCESS. The SUCCESS response refers to successfully entering BOOTLOAD Mode. (Read Section: What to
        #     do if IN-SYSTEM PROGRAMMING fails).
    # fmt: on

    if poll_upgrade_status(i2c_bus, BOOTLOADER_I2C_ADDR) == "POLL_STATUS_NOTACTIVE":
        print("checksum test passes, the target microcontroller will leave BOOTLOAD Mode")
    else:
        print("checksum test fails, the target microcontroller remains in BOOTLOAD Mode")
        exit(1)

    if args.skip_redundancy_check:
        print("Not checking FW version after update. Use -v option after power cycle.")
        exit(0)

    # 11. Repeat steps 1-9 to upgrade remaining microcontrollers.
    # Now we updating only secondary, so nothing todo here.
    # 12. Upgrading is complete, send the POWER_SUPPLY_RESET command.
    power_supply_reset(i2c_bus, BOOTLOADER_I2C_ADDR)
    # fmt: off
    # 12a. The Power Supply will send all microcontrollers a soft reset command. This will allow all the
    #    microcontrollers to restart together.
    # 12b. The Power Supply will leave Bootload Mode and change its PMBus address back to the address for Normal Operation.
    # 12c. After restart, the power supply will begin to deliver power again.
    # fmt: on
    time.sleep(2)
    # 13. To confirm the Power Supply is running upgraded firmware, send the READ_MFG_FW_REVISION command.
    new_fw_rev = read_murata_fw_revision(i2c_bus, i2c_addr, primary)
    print(new_fw_rev)

    if new_fw_rev != current_fw_rev:
        print("FW Update successful.")
        exit(0)
    else:
        print("FW version not changed.")
        exit(1)


def detect_address_60(i2c_bus, proceed):
    """
    @summary: Check if address 0x60 ocupied.
    """
    i2c_detect = os.popen("i2cdetect -y {}".format(i2c_bus)).read()
    addr_60 = re.findall(r'60: (..)', i2c_detect)
    if not proceed:
        if addr_60 and addr_60[0] == "60":
            print("i2c address 0x60 ocupied.")
            addr_70 = re.findall(r'70: (..)', i2c_detect)
            if addr_70 and addr_70[0] == "70":
                print("i2c address 0x70 also ocupied, may be psu FW update in progress. Use -p to countinue update.")
                exit(1)
            else:
                print("i2c address 0x70 free, may be psu FW update in progress. Use -c to force cpld remap from adress 0x60 to 0x70.")
                exit(1)
    else:
        print("proceed update.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    required = parser.add_argument_group('required arguments')
    parser.add_argument('-i', "--input_file")
    required.add_argument('-b', "--i2c_bus", type=int, default=0, required=True)
    required.add_argument('-a', "--i2c_addr", type=lambda x: int(x, 0), default=0, required=True)
    parser.add_argument('-p', "--proceed", type=bool, nargs='?',
                        const=True, default=False)
    parser.add_argument('-c', "--cpld_remap", type=bool, nargs='?',
                        const=True, default=False)
    parser.add_argument('-r', "--reset_and_exit", type=bool, nargs='?',
                        const=True, default=False)
    parser.add_argument('-P', "--primary", type=bool, nargs='?',
                        const=True, default=False)
    parser.add_argument('-S', "--skip_redundancy_check", type=bool, nargs='?',
                        const=True, default=False)
    parser.add_argument('-v', "--version", type=bool, nargs='?',
                        const=True, default=False)
    args = parser.parse_args()

    # print('Input args "', args.input_file, args.i2c_bus, args.i2c_addr)
    # read_mfr_id(i2c_bus, i2c_adr)
    # read_mfr_model(i2c_bus, i2c_adr)
    # read_mfr_revision(i2c_bus, i2c_adr)
    # read_murata_fw_revision(i2c_bus, i2c_adr)
    # check_power_supply_status(i2c_bus, i2c_adr)
    # poll_upgrade_status(i2c_bus, i2c_adr)
    # bootloader_status(i2c_bus, i2c_adr)
    # burn_fw_file(i2c_bus, i2c_addr)
    if args.version:
        fw_rev = read_murata_fw_revision(args.i2c_bus, args.i2c_addr, args.primary)
        print(fw_rev)
        exit(0)

    if args.reset_and_exit:
        power_supply_reset(args.i2c_bus, args.i2c_addr)
        print("Send reset command i2c_bus {}, i2c_addr {}".format(args.i2c_bus, args.i2c_addr))
        exit(0)

    if not vars(args)['input_file']:
        parser.error('The --input_file(-i) is required')
        exit(1)

    if args.cpld_remap:
        os.popen("iorw -w -b 0x2537 -l 1 -v 0x80").read()

    detect_address_60(args.i2c_bus, args.proceed)

    if not args.skip_redundancy_check:
        psu_upd_cmn.check_psu_redundancy(args.proceed, args.i2c_addr)

    murata_update(args.i2c_bus, args.i2c_addr, args.proceed, args.input_file, args.primary)
